import AppKit
import CoreGraphics

/// 贴纸本体：一个无边框、圆角、可拖动的 NSPanel。
final class StickerPanel: NSPanel {
    let content: StickerContentView
    private var settings: StickerSettings

    /// 拖动结束后回调（用来把新位置写进配置）
    var onFrameChanged: (() -> Void)?

    // MARK: - 自由拖动状态
    // WKWebView 铺满整个窗口，会把鼠标事件全吃掉，NSPanel 自带的
    // isMovableByWindowBackground 根本收不到，所以这里在窗口层面自己接管拖动。
    private var dragStartMouse: NSPoint?     // 屏幕坐标
    private var dragStartOrigin: NSPoint?    // 窗口原点
    private var didDrag = false
    private static let dragThreshold: CGFloat = 4  // 移动超过 4pt 才算拖动，否则算点击

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
        applyAppearance()
        updateDragBar()
    }

    // MARK: - 拖动条（保底方案：万一网页把事件吃光，还能靠顶部这条拖动）

    private var dragBar: DragBarView?

    private func updateDragBar() {
        if settings.showDragBar {
            if dragBar == nil {
                let bar = DragBarView()
                bar.translatesAutoresizingMaskIntoConstraints = false
                bar.onDragEnd = { [weak self] in
                    self?.captureFrame()
                    self?.onFrameChanged?()
                }
                content.addSubview(bar)
                NSLayoutConstraint.activate([
                    bar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                    bar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                    bar.topAnchor.constraint(equalTo: content.topAnchor),
                    bar.heightAnchor.constraint(equalToConstant: 22)
                ])
                dragBar = bar
            }
        } else {
            dragBar?.removeFromSuperview()
            dragBar = nil
        }
    }

    /// 允许在需要输入时（比如 HA 登录框）自动拿到键盘焦点
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // MARK: - 任意位置拖动

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            didDrag = false
            dragStartMouse = NSEvent.mouseLocation
            dragStartOrigin = frame.origin
            super.sendEvent(event)

        case .leftMouseDragged:
            guard !settings.lockPosition,
                  let start = dragStartMouse,
                  let origin = dragStartOrigin else {
                super.sendEvent(event)
                return
            }
            let now = NSEvent.mouseLocation
            let dx = now.x - start.x
            let dy = now.y - start.y
            // 还没超过阈值：先吞掉，别让网页开始框选
            if !didDrag && hypot(dx, dy) < StickerPanel.dragThreshold { return }
            didDrag = true
            setFrameOrigin(NSPoint(x: origin.x + dx, y: origin.y + dy))
            // 不转发给 webview，否则会触发网页内部的选择 / 拖拽

        case .leftMouseUp:
            if didDrag {
                didDrag = false
                dragStartMouse = nil
                dragStartOrigin = nil
                captureFrame()
                onFrameChanged?()
                // 吞掉 mouseUp：网页收不到完整 click，不会误触发开关
                return
            }
            super.sendEvent(event)

        default:
            super.sendEvent(event)
        }
    }

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

    /// 深浅色：贴纸窗口 + 网页内容一起切
    func applyAppearance() {
        let appearance = settings.appearance.nsAppearance
        self.appearance = appearance
        NSApp.appearance = appearance
        content.applyAppearance(appearance: appearance, isDark: settings.appearance.resolvedIsDark)
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
        let appearanceChanged = newSettings.appearance != settings.appearance
        settings = newSettings
        alphaValue = settings.opacity
        content.update(settings: settings)
        applyMode(settings.mode)
        applyFrame()
        applyAppearance()
        updateDragBar()
        if appearanceChanged {
            content.reload()
        }
    }

    var currentSettings: StickerSettings { settings }
}

/// 顶部一条半透明的拖动条。它是贴纸窗口里真正的 NSView，
/// 不会被 WKWebView 抢走事件，所以一定能拖动（网页上面拖不动时的保底手段）。
private final class DragBarView: NSView {
    var onDragEnd: (() -> Void)?
    private var startMouse: NSPoint?
    private var startOrigin: NSPoint?

    override var isFlipped: Bool { true }

    convenience init() {
        self.init(frame: .zero)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.15, alpha: 0.62).setFill()
        bounds.fill()
        // 中间画三道小横杠，一眼看出这是能拖的
        let w: CGFloat = 26, h: CGFloat = 2, gap: CGFloat = 3
        let x = (bounds.width - w) / 2
        let y0 = (bounds.height - (h * 3 + gap * 2)) / 2
        NSColor(calibratedWhite: 1.0, alpha: 0.55).setFill()
        for i in 0..<3 {
            NSRect(x: x, y: y0 + CGFloat(i) * (h + gap), width: w, height: h).fill()
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        startMouse = NSEvent.mouseLocation
        startOrigin = window?.frame.origin
    }

    override func mouseDragged(with event: NSEvent) {
        guard let s = startMouse, let o = startOrigin, let win = window else { return }
        let now = NSEvent.mouseLocation
        win.setFrameOrigin(NSPoint(x: o.x + now.x - s.x, y: o.y + now.y - s.y))
    }

    override func mouseUp(with event: NSEvent) {
        if startMouse != nil { onDragEnd?() }
        startMouse = nil
        startOrigin = nil
    }
}
