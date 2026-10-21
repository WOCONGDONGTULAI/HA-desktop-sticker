import SwiftUI
import AppKit

/// 从 HA /api/states 拿回来的一个实体（编辑器专用，比 HAState 少两个字段）
struct HAEntityRow: Identifiable, Hashable {
    let id: String          // entity_id
    let name: String        // friendly_name
    let domain: String
    let state: String

    init(dict: [String: Any]) {
        let eid = dict["entity_id"] as? String ?? ""
        let attrs = dict["attributes"] as? [String: Any] ?? [:]
        let friendly = attrs["friendly_name"] as? String ?? ""
        id = eid
        name = friendly.isEmpty ? eid : friendly
        domain = String(eid.split(separator: ".").first ?? "")
        state = dict["state"] as? String ?? "unknown"
    }
}

/// 「贴纸内容」编辑器：决定贴纸上放哪些磁贴、排什么顺序、叫什么、用什么图标。
/// 结果写回 settings.json 的 entities / names / icons 三个字段。
struct TileEditorView: View {
    var settings: StickerSettings
    var onSave: (StickerSettings) -> Void
    var onCancel: () -> Void

    @State private var picked: [String] = []                 // 已选 entity_id，顺序 = 显示顺序
    @State private var known: [String: HAEntityRow] = [:]    // entity_id -> 实体信息
    @State private var all: [HAEntityRow] = []
    @State private var icons: [String: String] = [:]
    @State private var names: [String: String] = [:]
    @State private var query = ""
    @State private var notice = ""
    @State private var editingID: String?

    init(settings: StickerSettings,
         onSave: @escaping (StickerSettings) -> Void,
         onCancel: @escaping () -> Void) {
        self.settings = settings
        self.onSave = onSave
        self.onCancel = onCancel
        _picked = State(initialValue: settings.explicitEntities)
        _icons = State(initialValue: settings.icons)
        _names = State(initialValue: settings.names)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerView
            Divider()
            selectedSection
            addSection
            Divider()
            footerView
        }
        .padding(16)
        .frame(width: 700)
        .task { await loadEntities() }
        .sheet(isPresented: pickerShown) { picker }
    }

    // MARK: - 头部

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("编辑贴纸内容").font(.headline)
                Spacer()
                Button {
                    Task { await loadEntities() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("重新读取 HA 里的实体")
            }
            if notice.isEmpty {
                Text("已读到 \(all.count) 个实体。选好之后点保存，贴纸会立刻刷新。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text(notice)
                    .font(.caption)
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 已选列表

    private var selectedSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("贴纸上显示的（从上到下）").font(.subheadline)
                Text("\(picked.count) 个").font(.caption).foregroundColor(.secondary)
                Spacer()
                Button("填入开关类") { fillToggleable() }
                    .disabled(toggleableEntities.isEmpty)
                    .help("把能开关的设备一次性加进来，再手动删掉不想要的")
                Button("清空") { picked.removeAll() }
                    .disabled(picked.isEmpty)
            }

            ZStack {
                List {
                    ForEach(Array(picked.enumerated()), id: \.element) { index, id in
                        tileRow(id: id, index: index)
                    }
                }
                .frame(height: 230)
                if picked.isEmpty {
                    Text("一个都没选 = 回到自动模式（显示所有开关 / 灯 / 风扇 / 空调，最多 12 个）")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )

            Text("左侧方块是图标，点一下就能换；中间可以直接改名字；↕ 调顺序，✕ 删掉。")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func tileRow(id: String, index: Int) -> some View {
        HStack(spacing: 8) {
            Button { editingID = id } label: {
                Image(systemName: iconFor(id))
                    .font(.system(size: 16))
                    .frame(width: 34, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.accentColor.opacity(0.14))
                    )
            }
            .help("换图标")
            .disabled(!symbolExists(iconFor(id)))

            VStack(alignment: .leading, spacing: 1) {
                TextField("名称", text: nameBinding(id))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 210)
                Text(id)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            if let row = known[id] {
                Text(domainLabel(row.domain))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 4)

            Button { moveUp(index) } label: { Image(systemName: "arrow.up") }
                .disabled(index == 0)
            Button { moveDown(index) } label: { Image(systemName: "arrow.down") }
                .disabled(index == picked.count - 1)
            Button { picked.remove(at: index) } label: { Image(systemName: "xmark") }
                .foregroundColor(.red)
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 1)
    }

    // MARK: - 待添加列表

    private var addSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("添加设备 / 传感器").font(.subheadline)
                Spacer()
                TextField("搜索名字或 entity_id", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 250)
            }

            ZStack {
                List {
                    ForEach(candidates) { row in
                        HStack(spacing: 8) {
                            Image(systemName: guessSymbol(domain: row.domain,
                                                          name: row.name,
                                                          state: row.state,
                                                          entityID: row.id))
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(row.name).lineLimit(1)
                                Text(row.id)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer(minLength: 4)
                            Text(domainLabel(row.domain))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Button("添加") { add(row.id) }
                        }
                        .padding(.vertical, 1)
                    }
                }
                .frame(height: 230)
                if candidates.isEmpty {
                    Text(all.isEmpty ? "还没读到 HA 的实体列表" : "没有匹配的实体")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )

            Text("传感器也能加：点不动，但会把数值显示在磁贴上（室温、湿度、电量这类）。")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - 底部按钮

    private var footerView: some View {
        HStack {
            Button("取消") { onCancel() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            Text(picked.isEmpty ? "保存后会回到自动模式" : "保存后按这个顺序显示 \(picked.count) 个")
                .font(.caption)
                .foregroundColor(.secondary)
            Button("保存") { save() }
                .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - 图标选择器

    private var pickerShown: Binding<Bool> {
        Binding(get: { editingID != nil }, set: { if !$0 { editingID = nil } })
    }

    private var picker: some View {
        Group {
            if let id = editingID {
                IconPickerView(title: displayName(id), current: iconFor(id)) { chosen in
                    icons[id] = chosen
                    editingID = nil
                } onReset: {
                    icons[id] = nil
                    editingID = nil
                } onClose: {
                    editingID = nil
                }
            }
        }
    }

    // MARK: - 数据

    private func loadEntities() async {
        notice = "正在读取 HA 实体列表…"
        guard let base = settings.baseURL else {
            notice = "先在设置里填 HA 地址。"
            return
        }
        let token = settings.token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            notice = "先在设置里填长期访问令牌，否则读不到实体列表。"
            return
        }
        guard let url = URL(string: "api/states", relativeTo: base) else {
            notice = "HA 地址写错了。"
            return
        }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                notice = status == 401 ? "令牌无效，读不到实体列表。去设置里换一个。" : "读不到实体列表：HTTP \(status)"
                return
            }
            guard let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                notice = "HA 返回的数据看不懂。"
                return
            }
            var map: [String: HAEntityRow] = [:]
            var list: [HAEntityRow] = []
            for d in arr {
                let row = HAEntityRow(dict: d)
                if row.id.isEmpty { continue }
                map[row.id] = row
                list.append(row)
            }
            known = map
            all = list
            notice = ""
            // 贴纸原本是自动模式时，把「现在实际显示的那 12 个」先摆进来，
            // 用户只要删掉不要的、再点保存，比从 168 个里一个个挑省事得多。
            if settings.explicitEntities.isEmpty && picked.isEmpty {
                picked = toggleableEntities.prefix(12).map { $0.id }
                if !picked.isEmpty {
                    notice = "贴纸现在是自动模式。我已把当前显示的那几个放进上面的列表，删掉不想要的再保存就行。"
                }
            }
        } catch {
            notice = "连不上 HA：\(error.localizedDescription)"
        }
    }

    private func save() {
        var s = settings
        s.entities = picked.joined(separator: ",")

        var cleanNames: [String: String] = [:]
        for id in picked {
            guard let v = names[id] else { continue }
            let trimmed = v.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed == (known[id]?.name ?? id) { continue }
            cleanNames[id] = trimmed
        }
        var cleanIcons: [String: String] = [:]
        for id in picked {
            if let v = icons[id], !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                cleanIcons[id] = v.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        s.names = cleanNames
        s.icons = cleanIcons
        onSave(s)
    }

    private func add(_ id: String) {
        guard !picked.contains(id) else { return }
        picked.append(id)
    }

    private func moveUp(_ index: Int) {
        guard index > 0, index < picked.count else { return }
        picked.swapAt(index, index - 1)
    }

    private func moveDown(_ index: Int) {
        guard index >= 0, index < picked.count - 1 else { return }
        picked.swapAt(index, index + 1)
    }

    /// 一把梭：把能开关的设备按现在的顺序全塞进来（挑豆子方便点）
    private func fillToggleable() {
        let wanted = toggleableEntities.map { $0.id }
        for id in wanted where !picked.contains(id) { picked.append(id) }
    }

    private var toggleableEntities: [HAEntityRow] {
        let domains: Set<String> = ["switch", "light", "fan", "input_boolean", "climate"]
        return all
            .filter { domains.contains($0.domain) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var candidates: [HAEntityRow] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let pool = all.filter { !picked.contains($0.id) }
        let filtered = q.isEmpty ? pool : pool.filter {
            $0.name.lowercased().contains(q) || $0.id.lowercased().contains(q)
        }
        // 排序：能点的设备在最前，传感器其次，自动化/脚本再往后，杂项垫底
        let ranks: [String: Int] = ["switch": 0, "light": 0, "fan": 0, "climate": 0, "input_boolean": 0,
                                    "cover": 1, "media_player": 1, "vacuum": 1, "lock": 1, "script": 1,
                                    "sensor": 2, "binary_sensor": 2,
                                    "automation": 3, "button": 3, "number": 3, "select": 3, "text": 3,
                                    "person": 4, "device_tracker": 4, "weather": 4,
                                    "update": 8, "notify": 8]
        return Array(filtered.sorted { a, b in
            let ra = ranks[a.domain] ?? 6
            let rb = ranks[b.domain] ?? 6
            if ra != rb { return ra < rb }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }.prefix(200))
    }

    // MARK: - 小工具

    private func displayName(_ id: String) -> String {
        if let n = names[id], !n.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return n }
        return known[id]?.name ?? id
    }

    private func iconFor(_ id: String) -> String {
        if let i = icons[id], !i.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return i }
        if let row = known[id] {
            return guessSymbol(domain: row.domain, name: row.name, state: row.state, entityID: id)
        }
        return "power"
    }

    private func nameBinding(_ id: String) -> Binding<String> {
        Binding(
            get: { displayName(id) },
            set: { newValue in
                let original = known[id]?.name ?? id
                if newValue.isEmpty || newValue == original { names[id] = nil } else { names[id] = newValue }
            }
        )
    }

    private func domainLabel(_ domain: String) -> String {
        switch domain {
        case "switch":         return "开关"
        case "light":          return "灯"
        case "fan":            return "风扇"
        case "input_boolean":  return "虚拟开关"
        case "climate":        return "空调"
        case "sensor":         return "传感器"
        case "binary_sensor":  return "状态"
        case "automation":     return "自动化"
        case "script":         return "脚本"
        case "button":         return "按钮"
        case "number":         return "数字"
        case "select":         return "选择器"
        case "cover":          return "窗帘"
        case "media_player":   return "音箱"
        case "vacuum":         return "扫地机"
        case "lock":           return "门锁"
        case "person":         return "人"
        case "device_tracker": return "设备"
        case "weather":        return "天气"
        case "update":         return "升级"
        case "notify":         return "通知"
        default:               return domain
        }
    }
}

/// 图标选择面板：一堆常用的 macOS 自带图标 + 手填名字
struct IconPickerView: View {
    let title: String
    let current: String
    var onPick: (String) -> Void
    var onReset: () -> Void
    var onClose: () -> Void

    @State private var custom = ""

    /// 常用的一些；系统里没有的（不同 macOS 版本带的 SF Symbols 版本不同）会被自动过滤掉
    private static let presets: [(String, String)] = [
        ("power", "开关"), ("power.circle.fill", "开关"), ("switch.2", "开关2"),
        ("bolt.fill", "电"), ("bolt.circle.fill", "电"), ("bolt.horizontal.fill", "通断"),
        ("lightbulb", "灯"), ("lightbulb.fill", "亮灯"), ("lamp.desk.fill", "台灯"),
        ("flame", "火"), ("flame.fill", "取暖"), ("heat.waves", "暖"),
        ("drop", "水"), ("drop.fill", "热水"), ("humidity.fill", "湿度"),
        ("thermometer", "温度"), ("thermometer.sun.fill", "温"),
        ("wind", "风"), ("wind.snow", "冷风"), ("snowflake", "制冷"),
        ("fan.blades", "风扇"), ("fan.badge.automatic", "自动风"), ("air.purifier.fill", "净化器"),
        ("fan.floor", "落地扇"), ("washer", "洗衣机"), ("refrigerator.fill", "冰箱"),
        ("oven.fill", "烤箱"), ("cup.and.saucer.fill", "杯"), ("shower.fill", "淋浴"),
        ("bathtub.fill", "浴缸"), ("toilet.fill", "马桶"),
        ("desktopcomputer", "电脑"), ("laptopcomputer", "笔记本"), ("display", "显示器"),
        ("tv", "电视"), ("tv.fill", "电视"), ("printer", "打印机"),
        ("speaker.fill", "音箱"), ("speaker.wave.2.fill", "播放"), ("hifispeaker.fill", "音响"),
        ("headphones", "耳机"), ("music.note", "音乐"), ("video.fill", "视频"),
        ("wifi", "Wi-Fi"), ("wifi.router", "路由"), ("network", "网络"),
        ("antenna.radiowaves.left.and.right", "信号"),
        ("iphone", "手机"), ("ipad", "平板"), ("applewatch.side.right", "手表"),
        ("camera.fill", "相机"), ("web.camera.fill", "摄像头"), ("doorbell.fill", "门铃"),
        ("lock.fill", "锁"), ("lock.open.fill", "开锁"), ("key.fill", "钥匙"),
        ("door.left.hand.closed", "门关"), ("door.left.hand.open", "门开"),
        ("rectangle.on.rectangle", "窗"), ("window.vertical.closed", "窗"),
        ("garage.door.right.closed", "车库门"), ("blinds.horizontal.closed", "窗帘"),
        ("car.fill", "车"), ("bicycle", "自行车"), ("scooter", "滑板车"),
        ("bed.double.fill", "床"), ("sofa.fill", "沙发"), ("house.fill", "家"),
        ("building.2.fill", "楼"), ("door.garage.closed", "院门"),
        ("leaf.fill", "植物"), ("pawprint.fill", "宠物"), ("cat.fill", "猫"), ("dog.fill", "狗"),
        ("clock", "时钟"), ("alarm.fill", "闹钟"), ("timer", "计时"), ("calendar", "日历"),
        ("bell.fill", "提醒"), ("bell.badge.fill", "通知"), ("hand.raised.fill", "手动"),
        ("person.fill", "人"), ("figure.walk", "走动"), ("figure.and.child.holdinghands", "家人"),
        ("battery.100", "电量"), ("battery.25", "低电"), ("bolt.batteryblock.fill", "电池"),
        ("sun.max.fill", "白天"), ("sun.min.fill", "光"), ("moon.fill", "夜晚"),
        ("moon.stars.fill", "夜间"), ("cloud.sun.fill", "多云"), ("cloud.rain.fill", "雨"),
        ("sunrise.fill", "日出"), ("sunset.fill", "日落"),
        ("sparkles", "自动"), ("star.fill", "星"), ("heart.fill", "心"),
        ("square.grid.2x2.fill", "网格"), ("circle.grid.3x3.fill", "九宫格"),
        ("number.circle.fill", "数字"), ("gauge", "读数"), ("speedometer", "读数"),
        ("arrow.triangle.2.circlepath", "循环"), ("repeat", "周期"), ("timer.circle", "定时")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("给「\(title)」换个图标").font(.headline)

            HStack(spacing: 10) {
                Image(systemName: symbolExists(current) ? current : "questionmark")
                    .font(.system(size: 26))
                    .frame(width: 50, height: 44)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.14)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(symbolExists(current) ? current : "当前图标不可用")
                        .font(.system(size: 11, design: .monospaced))
                    Text("下面是从 macOS 自带图标里挑的常用款")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("恢复自动") { onReset() }
                    .help("回到按名字自动猜的那个图标")
            }

            Divider()

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 54))], spacing: 8) {
                    ForEach(options, id: \.0) { item in
                        Button { onPick(item.0) } label: {
                            VStack(spacing: 2) {
                                Image(systemName: item.0)
                                    .font(.system(size: 19))
                                    .frame(height: 24)
                                Text(item.1)
                                    .font(.system(size: 9))
                                    .lineLimit(1)
                                    .foregroundColor(.secondary)
                            }
                            .frame(width: 54, height: 46)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(item.0 == current
                                          ? Color.accentColor.opacity(0.24)
                                          : Color.primary.opacity(0.05))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(height: 300)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    TextField("也可以直接写 SF Symbol 名字，比如 wand.and.stars", text: $custom)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(applyCustom)
                    Button("应用", action: applyCustom)
                        .disabled(!symbolExists(trimmedCustom))
                    Button("关闭") { onClose() }
                }
                if !trimmedCustom.isEmpty && !symbolExists(trimmedCustom) {
                    Text("这台 Mac 上没有这个图标（SF Symbols 旧一点就没有），换一个试试。")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                Text("想查全部图标名字：App Store 里下官方的「SF Symbols」App，免费。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .frame(width: 540)
    }

    private var trimmedCustom: String {
        custom.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func applyCustom() {
        guard !trimmedCustom.isEmpty, symbolExists(trimmedCustom) else { return }
        onPick(trimmedCustom)
    }

    private var options: [(String, String)] {
        Self.presets.filter { !$0.1.isEmpty && symbolExists($0.0) }
    }
}
