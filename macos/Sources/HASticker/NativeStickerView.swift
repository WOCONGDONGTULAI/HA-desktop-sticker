import SwiftUI
import AppKit

/// 原生贴纸面板：直接渲染 HA 状态，不走网页。
/// 刻意不用 ScrollView —— 系统「显示滚动条」设成「始终」时 SwiftUI 的 ScrollView
/// 也会挂一条常驻滚动条；这里改成按可用高度把磁贴平分，永远不用滚。
struct NativeStickerView: View {
    @ObservedObject var store: HAStore
    var settings: StickerSettings

    private let gap: CGFloat = 7
    private let pad: CGFloat = 9

    var body: some View {
        GeometryReader { geo in
            Group {
                if store.status == .idle {
                    placeholder(title: "还没配置",
                                detail: "填好 HA 地址和长期访问令牌就能用",
                                showSettings: true)
                } else if items(from: store).isEmpty && store.states.isEmpty {
                    placeholder(title: store.status.text,
                                detail: "检查地址和令牌是否正确",
                                showSettings: true)
                } else {
                    content(size: geo.size)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(bgColor)
        .clipShape(RoundedRectangle(cornerRadius: CGFloat(settings.cornerRadius), style: .continuous))
    }

    // MARK: - 主体

    private func content(size: CGSize) -> some View {
        let list = items(from: store)
        let cols = columnCount(for: list.count, size: size)
        let rows = stride(from: 0, to: list.count, by: cols).map { Array(list[$0..<min($0 + cols, list.count)]) }

        return VStack(spacing: gap) {
            header
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: gap) {
                    ForEach(row) { s in
                        TileView(state: s,
                                 title: settings.title(for: s.entityID, fallback: s.name),
                                 icon: settings.symbol(for: s.entityID, fallback: s.autoSymbol),
                                 on: s.isOn,
                                 enabled: s.isToggleable,
                                 readable: row.count > 1) {
                            // 传感器这类点不动的实体就别调 HA 服务了，省得报 400
                            if s.isToggleable { store.toggle(s) }
                        }
                    }
                    if row.count < cols {
                        ForEach(0..<(cols - row.count), id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .padding(pad)
    }

    /// 列数按「能不能塞进现有高度」来定：磁贴越多越会自动加列，
    /// 不然 12 个磁贴按 2 列排成 6 行，底下两行会被窗口切掉。
    private func columnCount(for count: Int, size: CGSize) -> Int {
        guard count > 1 else { return 1 }
        // 20 = 顶部胶囊，gap = 胶囊与第一行的间距，pad*2 = 四周留白
        let usableH = size.height - 20 - gap - pad * 2
        let widest = Int((size.width - pad * 2) / 86)          // 每格至少 86pt 宽才放得下字
        let maxCols = max(2, min(4, widest))
        for c in 2...maxCols {
            let rowCount = Int(ceil(Double(count) / Double(c)))
            let rowH = (usableH - gap * CGFloat(rowCount - 1)) / CGFloat(rowCount)
            if rowH >= 62 { return c }
        }
        return maxCols   // 实在放不下就尽量多排几列，至少不浪费宽度
    }

    /// 顶部：温湿度胶囊 + 连接状态点
    private var header: some View {
        HStack(spacing: 6) {
            ForEach(sensors, id: \.0) { item in
                HStack(spacing: 3) {
                    Image(systemName: item.0)
                        .font(.system(size: 10, weight: .medium))
                    Text(item.1)
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(Color.primary.opacity(0.07))
                )
            }
            Spacer(minLength: 0)
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
                .help(store.status.text)
        }
        .frame(height: 20)
    }

    private func placeholder(title: String, detail: String, showSettings: Bool) -> some View {
        VStack(spacing: 7) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Text(detail)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            if showSettings {
                Button("打开设置") {
                    NotificationCenter.default.post(name: .haStickerOpenSettings, object: nil)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .padding(.top, 2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 数据挑选

    /// 手填了就用填的（按填写顺序）；没填就自动挑：开关类 + 空调，最多 12 个
    private func items(from store: HAStore) -> [HAState] {
        let explicit = settings.explicitEntities
        if !explicit.isEmpty {
            return explicit.compactMap { store.states[$0] }
        }
        let domains = ["switch", "light", "fan", "input_boolean", "climate"]
        return Array(
            store.states.values
                .filter { domains.contains($0.domain) }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                .prefix(12)
        )
    }

    /// 家里往往有好几个温湿度传感器（净化器自带、插件自带…），名字最短的那个通常是屋里那个
    /// 正经温湿度计；另外必须用数值型，排除 unavailable / unknown 这类。
    private func bestSensor(of kind: String) -> HAState? {
        store.states.values
            .filter { $0.deviceClass == kind && Double($0.state) != nil }
            .sorted { $0.name.count < $1.name.count }
            .first
    }

    private var sensors: [(String, String)] {
        var out: [(String, String)] = []
        if let t = bestSensor(of: "temperature") {
            out.append(("thermometer", "\(t.state)\(t.unit)"))
        }
        if let h = bestSensor(of: "humidity") {
            out.append(("drop", "\(h.state)\(h.unit)"))
        }
        return out
    }

    private var statusColor: Color {
        switch store.status {
        case .online:     return .green
        case .connecting: return .orange
        case .failed:     return .red
        case .idle:       return .gray
        }
    }

    private var bgColor: Color {
        switch settings.appearance {
        case .dark:  return Color(white: 0.12)
        case .light: return Color(white: 0.97)
        case .auto:  return Color(nsColor: .textBackgroundColor)
        }
    }

    /// 图标自己不用挑：`HAState.autoSymbol` 里统一猜，用户手选过的由 StickerSettings 覆盖
}

/// 单个磁贴：图标 + 名字 + 状态，点一下切换
private struct TileView: View {
    let state: HAState
    let title: String           // 标题：可能被用户在编辑器里改过
    let icon: String            // SF Symbol：可能手选过
    let on: Bool
    let enabled: Bool           // 传感器之类不能切的就只是展示
    let readable: Bool          // 只有一个磁贴时不压缩文字
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(on ? .accentColor : Color.secondary.opacity(0.75))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundColor(on ? .accentColor.opacity(0.9) : .secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(on ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.055))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(on ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.07),
                                  lineWidth: 0.8)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(TileButtonStyle())
        .disabled(!enabled)
    }

    private var detail: String {
        if state.domain == "climate" {
            switch state.state {
            case "off": return "关"
            case "heat": return "制热"
            case "cool": return "制冷"
            case "dry": return "除湿"
            case "fan_only": return "送风"
            case "auto", "heat_cool": return "自动"
            default: return state.state
            }
        }
        if state.domain == "sensor" { return "\(state.state)\(state.unit)" }
        return state.isOn ? "开" : "关"
    }
}

/// 按下时轻微缩小，点击有反馈
private struct TileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// NSView 包装：把 SwiftUI 面板塞进贴纸窗口，接口跟网页版保持一致
final class NativeContentView: NSView {
    private let store = HAStore()
    private var hosting: NSHostingView<AnyView>?
    private var settings: StickerSettings

    init(settings: StickerSettings) {
        self.settings = settings
        super.init(frame: .zero)
        wantsLayer = true
        rebuild()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func rebuild() {
        let root = AnyView(NativeStickerView(store: store, settings: settings))
        if let h = hosting {
            h.rootView = root
        } else {
            let h = NSHostingView(rootView: root)
            h.frame = bounds
            h.autoresizingMask = [.width, .height]
            addSubview(h)
            hosting = h
        }
        layer?.cornerRadius = CGFloat(settings.cornerRadius)
    }

    /// 配置变了就重连（configure 内部会比对 base+token，没变不会重连）
    private func syncStore() {
        store.configure(base: settings.baseURL, token: settings.token)
    }

    func load() {
        rebuild()
        syncStore()
    }

    func reload() {
        rebuild()
        store.restart()
    }

    func update(settings newSettings: StickerSettings) {
        settings = newSettings
        rebuild()
        syncStore()
    }
}

extension Notification.Name {
    /// 原生面板里点「打开设置」时广播，由 AppDelegate 接收后弹设置窗
    static let haStickerOpenSettings = Notification.Name("haStickerOpenSettings")
}
