import AppKit
import SwiftUI
import WebKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private var panel: StickerPanel!
    private var settings: StickerSettings
    private var settingsWindow: NSWindow?
    private var rightClickMenu: NSMenu!
    private var localMonitor: Any?
    private var moveObserver: NSObjectProtocol?
    private var resizeObserver: NSObjectProtocol?
    private var appearanceObserver: NSObjectProtocol?

    override init() {
        self.settings = StickerSettings.load()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()
        buildStatusItem()
        rightClickMenu = buildMenu()

        panel = StickerPanel(settings: settings)
        panel.onFrameChanged = { [weak self] in self?.saveFrame() }
        panel.load()
        panel.orderFrontRegardless()

        installRightClickMonitor()
        observeFrameChanges()
        observeSystemAppearance()

        // 原生面板里的「打开设置」按钮
        NotificationCenter.default.addObserver(forName: .haStickerOpenSettings,
                                              object: nil, queue: .main) { [weak self] _ in
            self?.openSettings()
        }

        if !settings.isConfigured {
            openSettings()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        panel?.captureFrame()
        if let s = panel?.currentSettings { s.save() }
        if let m = localMonitor { NSEvent.removeMonitor(m) }
        if let o = appearanceObserver {
            DistributedNotificationCenter.default().removeObserver(o)
        }
    }

    // MARK: - 主菜单
    // 这个 app 没有 Nib，也就没有默认的 Edit 菜单 —— 没有它 Cmd+C/V/X/A 一条都不通
    // （nil target 的菜单项会自动走响应链，最终落到 first responder，也就是网页里的输入框）。

    private func buildMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        let quitItem = NSMenuItem(title: "退出 HA 贴纸", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        appMenu.addItem(quitItem)
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        let defs: [(String, String, String)] = [
            ("撤销", "undo:", "z"),
            ("重做", "redo:", "Z"),
            ("剪切", "cut:", "x"),
            ("拷贝", "copy:", "c"),
            ("粘贴", "paste:", "v"),
            ("全选", "selectAll:", "a")
        ]
        for (title, sel, key) in defs {
            editMenu.addItem(NSMenuItem(title: title,
                                        action: NSSelectorFromString(sel),
                                        keyEquivalent: key))
        }
        editItem.submenu = editMenu
        main.addItem(editItem)

        NSApp.mainMenu = main
    }

    /// WKWebView 不响应 paste: 时的兜底：把剪贴板文本直接插进页面里当前聚焦的输入框
    @objc func paste(_ sender: Any?) {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
        let encoded = (try? JSONEncoder().encode(text)).flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
        let js = """
        (function(){
          var s = \(encoded);
          var el = document.activeElement;
          if (!el) return false;
          var tag = (el.tagName || '').toLowerCase();
          if (tag === 'input' || tag === 'textarea') {
            var v = el.value || '';
            var a = el.selectionStart, b = el.selectionEnd;
            if (a === null || b === null) { el.value = v + s; }
            else {
              el.value = v.slice(0, a) + s + v.slice(b);
              el.selectionStart = el.selectionEnd = a + s.length;
            }
            el.dispatchEvent(new Event('input', { bubbles: true }));
            return true;
          }
          if (el.isContentEditable) { document.execCommand('insertText', false, s); return true; }
          return false;
        })();
        """
        panel.content.webView.evaluateJavaScript(js, completionHandler: nil)
    }

    // MARK: - 菜单栏图标（贴纸没有 Dock 图标，这是唯一的入口）

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "rectangle.roundedtop.fill",
                                   accessibilityDescription: "HA 贴纸")
            button.image?.isTemplate = true
        }
        statusItem.menu = buildMenu()
    }

    // MARK: - 右键菜单

    private func installRightClickMonitor() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            guard let self = self, event.window === self.panel else { return event }
            // 返回 nil：吞掉事件，免得弹出网页自带的右键菜单
            let point = self.panel.contentView!.convert(event.locationInWindow, from: nil)
            self.rightClickMenu.popUp(positioning: nil, at: point, in: self.panel.contentView)
            return nil
        }
    }

    private func buildMenu() -> NSMenu {
        let m = NSMenu()
        m.delegate = self

        m.addItem(withTitle: "显示 / 隐藏贴纸", action: #selector(toggleVisible), keyEquivalent: "")
        m.addItem(.separator())
        m.addItem(withTitle: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        m.addItem(withTitle: "重新加载", action: #selector(reloadPage), keyEquivalent: "r")
        m.addItem(withTitle: "粘贴到页面", action: #selector(pasteToPage), keyEquivalent: "")
        m.addItem(withTitle: "在浏览器里打开 HA", action: #selector(openInBrowser), keyEquivalent: "")
        m.addItem(.separator())

        let sourceItem = NSMenuItem(title: "内容来源", action: nil, keyEquivalent: "")
        let sourceMenu = NSMenu()
        for src in StickerSource.allCases {
            let item = NSMenuItem(title: src.displayName, action: #selector(setSource(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = src.rawValue
            sourceMenu.addItem(item)
        }
        m.setSubmenu(sourceMenu, for: sourceItem)
        m.addItem(sourceItem)

        let modeItem = NSMenuItem(title: "贴法", action: nil, keyEquivalent: "")
        let modeMenu = NSMenu()
        for mode in StickerMode.allCases {
            let item = NSMenuItem(title: mode.displayName, action: #selector(setMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            modeMenu.addItem(item)
        }
        m.setSubmenu(modeMenu, for: modeItem)
        m.addItem(modeItem)

        let opacityItem = NSMenuItem(title: "透明度", action: nil, keyEquivalent: "")
        let opacityMenu = NSMenu()
        for value in [0.5, 0.7, 0.85, 1.0] {
            let item = NSMenuItem(title: "\(Int(value * 100))%", action: #selector(setOpacity(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = value
            opacityMenu.addItem(item)
        }
        m.setSubmenu(opacityMenu, for: opacityItem)
        m.addItem(opacityItem)

        let lookItem = NSMenuItem(title: "外观", action: nil, keyEquivalent: "")
        let lookMenu = NSMenu()
        for look in StickerAppearance.allCases {
            let item = NSMenuItem(title: look.displayName, action: #selector(setAppearance(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = look.rawValue
            lookMenu.addItem(item)
        }
        m.setSubmenu(lookMenu, for: lookItem)
        m.addItem(lookItem)

        // 不勾选 = 调整模式（能拖能缩放）；勾选 = 锁定，位置和大小都固定
        let lockItem = NSMenuItem(title: "锁定（固定位置与大小）", action: #selector(toggleLock), keyEquivalent: "")
        lockItem.representedObject = "lock"
        m.addItem(lockItem)

        m.addItem(.separator())
        m.addItem(withTitle: "清除登录状态", action: #selector(clearLogin), keyEquivalent: "")
        m.addItem(.separator())
        m.addItem(withTitle: "退出", action: #selector(quit), keyEquivalent: "q")

        for item in m.items where item.action != nil { item.target = self }
        return m
    }

    /// 打开菜单前刷新勾选状态（菜单有两份：菜单栏 + 右键）
    func menuWillOpen(_ menu: NSMenu) {
        for item in menu.items {
            guard let sub = item.submenu else { continue }
            for subItem in sub.items {
                if let raw = subItem.representedObject as? String,
                   let look = StickerAppearance(rawValue: raw) {
                    subItem.state = (look == settings.appearance) ? .on : .off
                } else if let raw = subItem.representedObject as? String,
                          let src = StickerSource(rawValue: raw) {
                    subItem.state = (src == settings.source) ? .on : .off
                } else if let modeRaw = subItem.representedObject as? String,
                   StickerMode(rawValue: modeRaw) != nil {
                    subItem.state = (modeRaw == settings.mode.rawValue) ? .on : .off
                } else if let value = subItem.representedObject as? Double {
                    subItem.state = abs(value - settings.opacity) < 0.001 ? .on : .off
                }
            }
        }
        if let lock = menu.items.first(where: { ($0.representedObject as? String) == "lock" }) {
            lock.state = settings.lockPosition ? .on : .off
            lock.title = settings.lockPosition ? "已锁定（取消勾选=调整模式）" : "锁定（固定位置与大小）"
        }
    }

    // MARK: - 动作

    @objc private func toggleVisible() {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    @objc private func reloadPage() {
        panel.reload()
    }

    /// Cmd+V 万一还是不通，右键里这一条直接走剪贴板 → 网页输入框
    @objc private func pasteToPage() { paste(nil) }

    @objc private func openInBrowser() {
        if let s = settings.normalizedURLString(), let url = URL(string: s) {
            NSWorkspace.shared.open(url)
        }
    }

    /// 切换内容来源：原生面板 / 网页
    @objc private func setSource(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let src = StickerSource(rawValue: raw), src != settings.source else { return }
        settings.source = src
        settings.save()
        panel.update(settings: settings)
        panel.load()
    }

    @objc private func setMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = StickerMode(rawValue: raw) else { return }
        settings.mode = mode
        settings.save()
        panel.update(settings: settings)
    }

    @objc private func setOpacity(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Double else { return }
        settings.opacity = value
        settings.save()
        panel.update(settings: settings)
    }

    @objc private func setAppearance(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let look = StickerAppearance(rawValue: raw) else { return }
        settings.appearance = look
        settings.save()
        panel.update(settings: settings)   // 内部会检测到外观变了，自动 reload
    }

    /// 系统深浅色切换（外观设为「跟随系统」时才需要跟着动）
    private func observeSystemAppearance() {
        appearanceObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil, queue: .main) { [weak self] _ in
                guard let self = self else { return }
                guard self.settings.appearance == .auto else { return }
                self.panel.applyAppearance()
                self.panel.reload()
            }
    }

    @objc private func toggleLock() {
        settings.lockPosition.toggle()
        settings.save()
        panel.isMovableByWindowBackground = !settings.lockPosition
    }

    @objc private func clearLogin() {
        panel.content.clearLogin()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - 设置窗口

    @objc func openSettings() {
        if let win = settingsWindow {
            NSApp.activate(ignoringOtherApps: true)
            win.makeKeyAndOrderFront(nil)
            return
        }

        let view = SettingsView(
            settings: settings,
            onSave: { [weak self] newSettings in
                guard let self = self else { return }
                self.settings = newSettings
                newSettings.save()
                self.panel.isMovableByWindowBackground = !newSettings.lockPosition
                self.panel.update(settings: newSettings)
                self.panel.load()
                self.closeSettings()
            },
            onCancel: { [weak self] in self?.closeSettings() }
        )

        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 680),
                           styleMask: [.titled, .closable],
                           backing: .buffered,
                           defer: false)
        win.title = "HA 贴纸设置"
        win.contentView = NSHostingView(rootView: view)
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.center()
        settingsWindow = win

        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    private func closeSettings() {
        settingsWindow?.close()
        settingsWindow = nil
    }

    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) === settingsWindow {
            settingsWindow = nil
        }
    }

    // MARK: - 位置 / 大小记忆

    private func observeFrameChanges() {
        let nc = NotificationCenter.default
        moveObserver = nc.addObserver(forName: NSWindow.didMoveNotification,
                                      object: panel, queue: .main) { [weak self] _ in self?.saveFrame() }
        resizeObserver = nc.addObserver(forName: NSWindow.didEndLiveResizeNotification,
                                        object: panel, queue: .main) { [weak self] _ in self?.saveFrame() }
    }

    private var saveWork: DispatchWorkItem?

    /// 拖动时 didMove 会疯狂触发，合并一下再落盘
    private func saveFrame() {
        panel.captureFrame()
        settings = panel.currentSettings
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.settings.save() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }
}
