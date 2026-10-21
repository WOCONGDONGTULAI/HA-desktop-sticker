import Foundation
import Combine

/// 一个实体的快照。只留贴纸用得上的字段，避免把整个 attributes 拖着走
struct HAState: Identifiable, Equatable {
    var entityID: String
    var state: String
    var name: String
    var unit: String
    var deviceClass: String
    var minTemp: Double?
    var maxTemp: Double?

    var id: String { entityID }
    var domain: String { String(entityID.split(separator: ".").first ?? "") }

    /// 开关类实体是不是「开着」
    var isOn: Bool {
        switch state {
        case "on", "open", "playing", "heat", "cool", "heat_cool", "auto", "dry", "fan_only":
            return true
        default:
            return false
        }
    }

    /// 能不能点一下就切
    var isToggleable: Bool {
        ["switch", "light", "fan", "input_boolean", "climate"].contains(domain)
    }

    init?(dict: [String: Any]) {
        guard let eid = dict["entity_id"] as? String else { return nil }
        entityID = eid
        state = dict["state"] as? String ?? "unknown"
        let a = dict["attributes"] as? [String: Any] ?? [:]
        name = a["friendly_name"] as? String ?? eid
        unit = a["unit_of_measurement"] as? String ?? ""
        deviceClass = a["device_class"] as? String ?? ""
        minTemp = a["min_temp"] as? Double
        maxTemp = a["max_temp"] as? Double
    }
}

/// 直接跟 Home Assistant 说话：REST 拿全量状态 + WebSocket 订阅 state_changed。
/// 完全不碰网页，所以没有 HA 的顶栏、菜单、滚动条，也没有渲染延迟。
@MainActor
final class HAStore: ObservableObject {
    enum Status: Equatable {
        case idle                 // 还没配置
        case connecting
        case online
        case failed(String)

        var text: String {
            switch self {
            case .idle:       return "未配置"
            case .connecting: return "连接中…"
            case .online:     return "已连接"
            case .failed(let m): return m
            }
        }
    }

    @Published private(set) var states: [String: HAState] = [:]
    @Published private(set) var status: Status = .idle

    private var base: URL?
    private var token = ""
    private var socket: URLSessionWebSocketTask?
    private var loop: Task<Void, Never>?
    private var retryCount = 0
    private var currentKey: String = ""   // base+token 的指纹，用来判断要不要重连

    // MARK: - 配置

    func configure(base: URL?, token rawToken: String) {
        let t = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = "\(base?.absoluteString ?? "")|\(t)"
        guard key != currentKey else { return }
        currentKey = key
        self.base = base
        self.token = t
        restart()
    }

    func restart() {
        stop()
        guard base != nil, !token.isEmpty else {
            states = [:]
            status = .idle
            return
        }

        // 预览模式：令牌写 demo 就用假数据，方便调界面
        if token == "demo" {
            states = HAState.demoSet()
            status = .online
            return
        }

        loop = Task { [weak self] in await self?.bootstrap() }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
    }

    // MARK: - 首次拉全量 + 起 WebSocket

    private func bootstrap() async {
        status = .connecting
        await fetchAll()
        await runSocket()
    }

    private func fetchAll() async {
        guard let base, !token.isEmpty else { return }
        guard let url = URL(string: "api/states", relativeTo: base) else { return }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 10
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return }
            guard http.statusCode == 200 else {
                status = .failed(http.statusCode == 401 ? "令牌无效" : "HTTP \(http.statusCode)")
                return
            }
            guard let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
            var map: [String: HAState] = [:]
            for d in arr {
                if let s = HAState(dict: d) { map[s.entityID] = s }
            }
            states = map
        } catch {
            status = .failed("连不上 HA")
        }
    }

    private func socketURL() -> URL? {
        guard let base, var comps = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        comps.scheme = (comps.scheme == "https") ? "wss" : "ws"
        comps.path = "/api/websocket"
        return comps.url
    }

    private func runSocket() async {
        while !Task.isCancelled {
            guard let url = socketURL() else { return }
            status = (states.isEmpty ? .connecting : status)
            let task = URLSession.shared.webSocketTask(with: url)
            socket = task
            task.resume()
            do {
                // 1. auth_required
                let hello = try await receiveText(task)
                guard let helloObj = json(hello),
                      helloObj["type"] as? String == "auth_required" else {
                    throw HAError.protocolError
                }
                // 2. 认证
                try await task.send(.string(try encode(["type": "auth", "access_token": token])))
                let authRaw = try await receiveText(task)
                guard let authObj = json(authRaw) else { throw HAError.protocolError }
                if authObj["type"] as? String == "auth_invalid" {
                    status = .failed("令牌无效，请重新填")
                    task.cancel(with: .goingAway, reason: nil)
                    return
                }
                guard authObj["type"] as? String == "auth_ok" else { throw HAError.protocolError }

                // 3. 订阅状态变化
                try await task.send(.string(try encode([
                    "id": 1, "type": "subscribe_events", "event_type": "state_changed"
                ])))
                status = .online
                retryCount = 0

                // 4. 一直收
                while true {
                    let raw = try await receiveText(task)
                    handle(raw)
                }
            } catch {
                if Task.isCancelled { return }
                if case .failed = status {
                    // 令牌问题之类的硬错误，不重试
                    if status == .failed("令牌无效，请重新填") { return }
                }
                status = .failed("连接断开，重试中…")
                socket?.cancel(with: .goingAway, reason: nil)
                socket = nil
                // 退避重连：1s, 2s, 4s… 最多 15s
                let delay = min(pow(2.0, Double(retryCount)), 15)
                retryCount += 1
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                // 重连前补一次全量，免得漏事件
                await fetchAll()
            }
        }
    }

    private func receiveText(_ task: URLSessionWebSocketTask) async throws -> String {
        let msg = try await task.receive()
        switch msg {
        case .string(let s):  return s
        case .data(let d):    return String(data: d, encoding: .utf8) ?? ""
        @unknown default:     return ""
        }
    }

    private func handle(_ raw: String) {
        guard let obj = json(raw), obj["type"] as? String == "event",
              let event = obj["event"] as? [String: Any],
              let data = event["data"] as? [String: Any],
              let newState = data["new_state"] as? [String: Any],
              let s = HAState(dict: newState) else { return }
        states[s.entityID] = s
    }

    // MARK: - 操作

    func toggle(_ s: HAState) {
        guard let base, !token.isEmpty, token != "demo" else {
            // 预览模式下也让它点得动，方便看效果
            if token == "demo", var cur = states[s.entityID] {
                cur.state = cur.isOn ? "off" : "on"
                states[s.entityID] = cur
            }
            return
        }

        let service: String
        if s.domain == "climate" {
            service = s.isOn ? "turn_off" : "turn_on"
        } else {
            service = "toggle"
        }

        // 先乐观改本地状态，UI 立刻有反馈；随后 WebSocket 推送会校正
        if var cur = states[s.entityID] {
            cur.state = cur.isOn ? "off" : "on"
            if s.domain == "climate" { cur.state = s.isOn ? "off" : "heat" }
            states[s.entityID] = cur
        }

        guard let url = URL(string: "api/services/\(s.domain)/\(service)", relativeTo: base) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["entity_id": s.entityID])
        req.timeoutInterval = 10

        Task {
            do {
                let (_, resp) = try await URLSession.shared.data(for: req)
                if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
                    self.status = .failed("操作失败 HTTP \(http.statusCode)")
                }
            } catch {
                self.status = .failed("操作失败")
            }
            // 无论成败都补一次真实状态
            await self.fetchAll()
        }
    }

    // MARK: - 小工具

    private func json(_ s: String) -> [String: Any]? {
        guard let d = s.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: d) as? [String: Any]
    }

    private func encode(_ o: [String: Any]) throws -> String {
        let d = try JSONSerialization.data(withJSONObject: o)
        return String(data: d, encoding: .utf8) ?? "{}"
    }

    private enum HAError: Error { case protocolError }
}

// MARK: - 预览用的假数据
// 令牌填 demo 时启用，只为了调界面用；真机上不会走到这里。
extension HAState {
    static func demoSet() -> [String: HAState] {
        let rows: [(String, String, String, String, String, String)] = [
            ("switch.demo_heater",  "on",   "电暖器",   "",  "",       ""),
            ("switch.demo_water",   "off",  "热水器",   "",  "",       ""),
            ("switch.demo_pc",      "on",   "电脑",     "",  "",       ""),
            ("switch.demo_sign",    "off",  "牌匾灯",   "",  "",       ""),
            ("switch.demo_charger", "on",   "充电器",   "",  "",       ""),
            ("switch.demo_flash",   "off",  "闪光灯",   "",  "",       ""),
            ("fan.demo_purifier",   "on",   "净化器",   "",  "",       ""),
            ("climate.demo_ac",     "heat", "空调",     "",  "",       ""),
            ("sensor.demo_temp",    "20.2", "温度",     "°C", "temperature", ""),
            ("sensor.demo_hum",     "37",   "湿度",     "%",  "humidity",    "")
        ]
        var map: [String: HAState] = [:]
        for (eid, st, nm, unit, dc, _) in rows {
            map[eid] = HAState(raw: eid, state: st, name: nm, unit: unit, deviceClass: dc)
        }
        return map
    }

    init(raw: String, state: String, name: String, unit: String, deviceClass: String) {
        self.entityID = raw
        self.state = state
        self.name = name
        self.unit = unit
        self.deviceClass = deviceClass
        self.minTemp = 16
        self.maxTemp = 30
    }
}
