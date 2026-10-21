import SwiftUI

struct SettingsView: View {
    @State private var source: StickerSource
    @State private var urlText: String
    @State private var token: String
    @State private var entities: String
    @State private var width: Double
    @State private var height: Double
    @State private var opacity: Double
    @State private var zoom: Double
    @State private var cornerRadius: Double
    @State private var mode: StickerMode
    @State private var appearance: StickerAppearance
    @State private var lockPosition: Bool

    private let original: StickerSettings
    private let onSave: (StickerSettings) -> Void
    private let onCancel: () -> Void

    init(settings: StickerSettings,
         onSave: @escaping (StickerSettings) -> Void,
         onCancel: @escaping () -> Void) {
        self.original = settings
        self.onSave = onSave
        self.onCancel = onCancel
        _source = State(initialValue: settings.source)
        _urlText = State(initialValue: settings.haURL.isEmpty ? "http://192.168.5.18:8123" : settings.haURL)
        _token = State(initialValue: settings.token)
        _entities = State(initialValue: settings.entities)
        _width = State(initialValue: settings.width)
        _height = State(initialValue: settings.height)
        _opacity = State(initialValue: settings.opacity)
        _zoom = State(initialValue: settings.zoom)
        _cornerRadius = State(initialValue: settings.cornerRadius)
        _mode = State(initialValue: settings.mode)
        _appearance = State(initialValue: settings.appearance)
        _lockPosition = State(initialValue: settings.lockPosition)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("HA 贴纸设置").font(.headline)

            connectionSection
            displaySection
            behaviorSection

            HStack {
                Button("取消") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存") {
                    var s = original
                    s.source = source
                    s.haURL = urlText
                    s.token = token
                    s.entities = entities
                    s.width = width
                    s.height = height
                    s.opacity = opacity
                    s.zoom = zoom
                    s.cornerRadius = cornerRadius
                    s.mode = mode
                    s.appearance = appearance
                    s.lockPosition = lockPosition
                    onSave(s)
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 2)
        }
        .padding(20)
        .frame(width: 500)
    }

    // MARK: - 连接

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Picker("内容来源", selection: $source) {
                ForEach(StickerSource.allCases) { Text($0.displayName).tag($0) }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(source == .native ? "Home Assistant 地址" : "仪表盘网页地址")
                    .font(.subheadline)
                TextField("http://192.168.5.18:8123", text: $urlText)
                    .textFieldStyle(.roundedBorder)
                Text(source == .native
                     ? "只填到端口就行，路径会被忽略：http://192.168.5.18:8123"
                     : "指向贴纸仪表盘，例如 http://192.168.5.18:8123/ha-sticker?kiosk")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if source == .native {
                VStack(alignment: .leading, spacing: 3) {
                    Text("长期访问令牌").font(.subheadline)
                    SecureField("粘贴令牌", text: $token)
                        .textFieldStyle(.roundedBorder)
                    Text("HA 网页左下角点你的用户名 → 安全 → 长期访问令牌 → 创建，复制粘过来。\n令牌只存在本机 ~/Library/Application Support/HASticker/settings.json")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("显示哪些实体（可留空）").font(.subheadline)
                    TextField("留空 = 自动显示所有开关、灯、风扇、空调", text: $entities)
                        .textFieldStyle(.roundedBorder)
                    Text("想自己排顺序就填 entity_id，逗号分隔，比如：switch.pzg_0002_069f_switch, light.yeelight")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - 外观

    private var displaySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("宽").frame(width: 32, alignment: .leading)
                Slider(value: $width, in: 180...900)
                Text("\(Int(width))").frame(width: 44, alignment: .trailing)
            }
            HStack {
                Text("高").frame(width: 32, alignment: .leading)
                Slider(value: $height, in: 180...1200)
                Text("\(Int(height))").frame(width: 44, alignment: .trailing)
            }
            if source == .web {
                HStack {
                    Text("缩放").frame(width: 32, alignment: .leading)
                    Slider(value: $zoom, in: 0.5...2.0)
                    Text("\(Int(zoom * 100))%").frame(width: 44, alignment: .trailing)
                }
            }
            HStack {
                Text("透明").frame(width: 32, alignment: .leading)
                Slider(value: $opacity, in: 0.4...1.0)
                Text("\(Int(opacity * 100))%").frame(width: 44, alignment: .trailing)
            }

            Picker("贴法", selection: $mode) {
                ForEach(StickerMode.allCases) { Text($0.displayName).tag($0) }
            }
            Picker("外观", selection: $appearance) {
                ForEach(StickerAppearance.allCases) { Text($0.displayName).tag($0) }
            }
        }
    }

    // MARK: - 行为

    private var behaviorSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: $lockPosition) {
                Text(lockPosition ? "锁定（固定位置与大小）" : "调整模式（可拖动、可缩放）")
            }
            Text(lockPosition
                 ? "已锁定：拖不动也缩放不了，只能点里面的开关。取消勾选回到调整模式。"
                 : "调整模式下贴纸任意位置按住左键即可拖动，顶部会出现拖动条，拖边缘可缩放。调好后勾选锁定。")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
