import AppKit
import CoreGraphics

/// 贴纸本体：一个无边框、圆角、可拖动的 NSPanel。
/// 内容有两种：原生面板（直连 HA API）和网页（嵌仪表盘），由 settings.source 决定。
final class StickerPanel: NSPanel {
    let web: StickerContentView
    let native: NativeContentView

    /// 兼容旧调用：粘贴 / 清 cookie 这些只跟网页有关
    var content: StickerContentView { web }

    private var settings: StickerSettings
    private let container = NSView()

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
        self.web = StickerContentView(settings: settings)
        self.native = NativeContentView(settings: settings)
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: settings.width, height: settings.height),
            // 注意：不能带 .nonactivatingPanel —— 带了点击就不会激活 app，
            // 窗口拿不到键盘焦点，登录框里既打不了字也粘不了东西
            styleMask: [.borderless, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false   // 点一下就要能拿到键盘焦点（要往登录框里打字/粘贴）
        animationBehavior = .utilityWindow
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        // 所有桌面空间都可见，切 Space / 全屏应用时不会丢
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        container.wantsLayer = true
        container.layer?.cornerRadius = CGFloat(settings.cornerRadius)
        container.layer?.masksToBounds = true
        self.contentView = container

        for v in [web, native] as [NSView] {
            v.frame = container.bounds
            v.autoresizingMask = [.width, .height]
            container.addSubview(v)
        }

        self.alphaValue = settings.opacity
        self.minSize = NSSize(width: 160, height: 160)
        applySource()
        applyMode(settings.mode)
        applyFrame()
        applyAppearance()
        applyAdjustUI()
    }

    /// 网页 / 原生面板二选一
    private func applySource() {
        web.isHidden = (settings.source != .web)
        native.isHidden = (settings.source != .native)
    }

    func load() {
        switch settings.source {
        case .web:    web.load()
        case .native: native.load()
        }
    }

    func reload() {
        switch settings.source {
        case .web:    web.reload()
        case .native: native.reload()
        }
    }

    // MARK: - 调整模式 / 锁定
    // 未锁定 = 调整模式：能拖能缩放，顶部显示拖动条 + 描边提示
    // 锁定   = 固定住：既不能拖也不能缩放，提示全部隐藏

    private var dragBar: DragBarView?

    private func applyAdjustUI() {
        let adjusting = !settings.lockPosition

        // 缩放：锁定后直接把 resizable 从 styleMask 摘掉，边缘就拖不动了
        if adjusting {
            styleMask.insert(.resizable)
        } else {
            styleMask.remove(.resizable)
        }
        isMovableByWindowBackground = adjusting

        // 拖动条：调整模式下自动出现，一眼看出「现在能拖」
        if adjusting {
            if dragBar == nil {
                let bar = DragBarView()
                bar.translatesAutoresizingMaskIntoConstraints = false
                bar.onDragEnd = { [weak self] in
                    self?.captureFrame()
                    self?.onFrameChanged?()
                }
                container.addSubview(bar)
                NSLayoutConstraint.activate([
                    bar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                    bar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                    bar.topAnchor.constraint(equalTo: container.topAnchor),
                    bar.heightAnchor.constraint(equalToConstant: 22)
                ])
                dragBar = bar
            }
        } else {
            dragBar?.removeFromSuperview()
            dragBar = nil
        }

        // 描边提示：调整模式下一圈细边，锁定后消失
        container.layer?.borderWidth = adjusting ? 1.5 : 0
        container.layer?.borderColor = NSColor.controlAccentColor.cgColor
    }

    /// 允许在需要输入时（比如 HA 登录框）自动拿到键盘焦点
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // MARK: - 拷贝粘贴
    // app 没有 Nib、也没有主菜单，Cmd+C/V/X/A 这些默认全都不通，
    // 这里直接在窗口层面拦下来转发给响应链（第一响应者是网页里的输入框）。

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command),
              let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }
        let sel: String?
        switch key {
        case "v": sel = "paste:"
        case "c": sel = "copy:"
        case "x": sel = "cut:"
        case "a": sel = "selectAll:"
        default:  sel = nil
        }
        guard let name = sel else { return super.performKeyEquivalent(with: event) }
        return NSApp.sendAction(NSSelectorFromString(name), to: nil, from: self)
    }

    // MARK: - 任意位置拖动

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            didDrag = false
            dragStartMouse = NSEvent.mouseLocation
            dragStartOrigin = frame.origin
            // accessory 型 app 要显式激活，否则窗口成不了 key，键盘输入进不来
            NSApp.activate(ignoringOtherApps: true)
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
            // 还没超过阈值：先吞掉，别让 content 开始框选
            if !didDrag && hypot(dx, dy) < StickerPanel.dragThreshold { return }
            didDrag = true
            setFrameOrigin(NSPoint(x: origin.x + dx, y: origin.y + dy))
            // 不转发给 content，否则会触发网页内部的选择 / 拖拽

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
            // 关键：必须站在「桌面图标层」之上，否则点不到。
            // Finder 的桌面图标是一块铺满全屏的透明窗口（-2147483603），
            // 而 macOS 的点击命中只看最上层窗口、不管透不透明，
            // 贴在 desktopWindow+1 会被它整块盖住 —— 开关点不动、也拖不动。
            // 抬到 icon 层 +1 之后：图标仍然在下面（会被贴纸遮住），
            // 但它依然远低于普通窗口(0)，所以应用窗口照样能盖住贴纸。
            let iconLevel = Int(CGWindowLevelForKey(.desktopIconWindow))
            level = NSWindow.Level(rawValue: iconLevel + 1)
        case .floating:
            level = .floating
        case .normal:
            level = .normal
        }
    }

    /// 深浅色：贴纸窗口 + 内容一起切
    func applyAppearance() {
        let appearance = settings.appearance.nsAppearance
        self.appearance = appearance
        NSApp.appearance = appearance
        web.applyAppearance(appearance: appearance, isDark: settings.appearance.resolvedIsDark)
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
        let sourceChanged = newSettings.source != settings.source
        settings = newSettings

        alphaValue = settings.opacity
        container.layer?.cornerRadius = CGFloat(settings.cornerRadius)
        web.update(settings: settings)
        native.update(settings: settings)

        applySource()
        applyMode(settings.mode)
        applyFrame()
        applyAppearance()
        applyAdjustUI()

        if sourceChanged {
            load()
        } else if appearanceChanged {
            reload()
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
