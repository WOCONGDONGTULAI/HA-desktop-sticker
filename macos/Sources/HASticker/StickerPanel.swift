import AppKit
import CoreGraphics

/// 贴纸本体：一个无边框、圆角、可拖动的 NSPanel。
final class StickerPanel: NSPanel {
    let content: StickerContentView
    private var settings: StickerSettings

    init(settings: StickerSettings) {
        self.settings = settings
        self.content = StickerContentView(settings: settings)
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: settings.width, height: settings.height),
            styleMask: [.borderless, .nonactivatingPanel, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .utilityWindow
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        // 所有桌面空间都可见，切 Space / 全屏应用时不会丢
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        self.contentView = content
        self.alphaValue = settings.opacity
        self.minSize = NSSize(width: 160, height: 160)
        applyMode(settings.mode)
        applyFrame()
    }

    /// 允许在需要输入时（比如 HA 登录框）自动拿到键盘焦点
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func applyMode(_ mode: StickerMode) {
        switch mode {
        case .desktop:
            // 放到桌面图标之上、普通窗口之下 —— 这就是 macOS 上的「贴在桌面」
            let desktopLevel = Int(CGWindowLevelForKey(.desktopWindow))
            level = NSWindow.Level(rawValue: desktopLevel + 1)
        case .floating:
            level = .floating
        case .normal:
            level = .normal
        }
    }

    func applyFrame() {
        let size = NSSize(width: max(settings.width, minSize.width),
                          height: max(settings.height, minSize.height))
        var origin: NSPoint?

        if let x = settings.x, let y = settings.y {
            let p = NSPoint(x: x, y: y)
            // 只在坐标仍落在某块屏幕上时才沿用，否则会跑到消失的显示器上
            if NSScreen.screens.contains(where: { $0.frame.insetBy(dx: -80, dy: -80).contains(p) }) {
                origin = p
            }
        }

        if origin == nil {
            let screen = NSScreen.main ?? NSScreen.screens[0]
            let v = screen.visibleFrame
            origin = NSPoint(x: v.maxX - size.width - 24, y: v.maxY - size.height - 24)
        }

        setFrame(NSRect(origin: origin!, size: size), display: true)
    }

    /// 把当前位置 / 大小写回 settings
    func captureFrame() {
        settings.width = Double(frame.width)
        settings.height = Double(frame.height)
        settings.x = Double(frame.origin.x)
        settings.y = Double(frame.origin.y)
    }

    func update(settings newSettings: StickerSettings) {
        settings = newSettings
        alphaValue = settings.opacity
        content.update(settings: settings)
        applyMode(settings.mode)
        applyFrame()
    }

    var currentSettings: StickerSettings { settings }
}
