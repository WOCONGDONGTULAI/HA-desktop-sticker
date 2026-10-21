import SwiftUI

struct SettingsView: View {
    @State private var urlText: String
    @State private var width: Double
    @State private var height: Double
    @State private var opacity: Double
    @State private var zoom: Double
    @State private var cornerRadius: Double
    @State private var mode: StickerMode
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
        _urlText = State(initialValue: settings.haURL.isEmpty ? StickerSettings.sampleURL : settings.haURL)
        _width = State(initialValue: settings.width)
        _height = State(initialValue: settings.height)
        _opacity = State(initialValue: settings.opacity)
        _zoom = State(initialValue: settings.zoom)
        _cornerRadius = State(initialValue: settings.cornerRadius)
        _mode = State(initialValue: settings.mode)
        _lockPosition = State(initialValue: settings.lockPosition)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("HA 贴纸设置").font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Home Assistant 仪表盘地址").font(.subheadline)
                TextField("http://homeassistant.local:8123/ha-sticker?kiosk", text: $urlText)
                    .textFieldStyle(.roundedBorder)
                Text("带上 ?kiosk 可以隐藏侧边栏和顶栏")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("宽").frame(width: 32, alignment: .leading)
                Slider(value: $width, in: 200...900)
                Text("\(Int(width))").frame(width: 44, alignment: .trailing)
            }
            HStack {
                Text("高").frame(width: 32, alignment: .leading)
                Slider(value: $height, in: 200...1200)
                Text("\(Int(height))").frame(width: 44, alignment: .trailing)
            }
            HStack {
                Text("缩放").frame(width: 32, alignment: .leading)
                Slider(value: $zoom, in: 0.5...2.0)
                Text("\(Int(zoom * 100))%").frame(width: 44, alignment: .trailing)
            }
            HStack {
                Text("透明").frame(width: 32, alignment: .leading)
                Slider(value: $opacity, in: 0.4...1.0)
                Text("\(Int(opacity * 100))%").frame(width: 44, alignment: .trailing)
            }

            Picker("贴法", selection: $mode) {
                ForEach(StickerMode.allCases) { Text($0.displayName).tag($0) }
            }

            Toggle("锁定位置（不能拖动）", isOn: $lockPosition)

            HStack {
                Button("取消") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存") {
                    var s = original
                    s.haURL = urlText
                    s.width = width
                    s.height = height
                    s.opacity = opacity
                    s.zoom = zoom
                    s.cornerRadius = cornerRadius
                    s.mode = mode
                    s.lockPosition = lockPosition
                    onSave(s)
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 480)
    }
}
