import AppKit
import SwiftUI
import WebKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private var panel: StickerPanel!
    private var settings: StickerSettings
    private var settingsWindow: NSWindow?
    private var tileWindow: NSWindow?
    private var localMonitor: Any?
    private var moveObserver: NSObjectProtocol?
    private var resizeObserver: NSObjectProtocol?
    private var appearanceObserver: NSObjectProtocol?

    override init() {
        var s = StickerSettings.load()
        // 老配置里可能存着 0.5 / 0.7，这种透明度必然留残影，读进来就抬到安全值
        let safe = StickerPanel.safeAlpha(s.opacity)
        if abs(safe - s.opacity) > 0.001 {
            s.opacity = safe
            s.save()
        }
        self.settings = s
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()
        buildStatusItem()

        panel = StickerPanel(settings: settings)
        panel.onFrameChanged = { [weak self] in self?.saveFrame() }
        panel.load()
        panel.orderFrontRegardless()

        // app 挪过位置就更新一下开机启动里记的那条路径
        LaunchAtLogin.syncPathIfNeeded()

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

    /// 贴纸上右键什么都不弹：所有操作都在菜单栏那个图标里。
    /// 但事件还是吞掉（返回 nil），否则嵌网页时会弹出网页自带的右键菜单。
    private func installRightClickMonitor() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            guard let self = self, event.window === self.panel else { return event }
            return nil
        }
    }

    private func buildMenu() -> NSMenu {
        let m = NSMenu()
        m.delegate = self

        m.addItem(withTitle: "显示 / 隐藏贴纸", action: #selector(toggleVisible), keyEquivalent: "")
        m.addItem(.separator())
        m.addItem(withTitle: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        m.addItem(withTitle: "编辑贴纸内容…", action: #selector(openTileEditor), keyEquivalent: "e")
        m.addItem(withTitle: "重新加载", action: #selector(reloadPage), keyEquivalent: "r")
        m.addItem(withTitle: "刷新显示（出现残影时点这个）", action: #selector(fixGhosting), keyEquivalent: "R")
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
        // 不再提供 0.5 / 0.7 这种低透明度：窗口太透时桌面上会留下旧画面残影
        for value in [0.94, 0.97, 1.0] {
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

        let loginItem = NSMenuItem(title: "开机自动启动", action: #selector(toggleLoginItem), keyEquivalent: "")
        loginItem.representedObject = "login"
        m.addItem(loginItem)

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
        if let login = menu.items.first(where: { ($0.representedObject as? String) == "login" }) {
            login.state = LaunchAtLogin.isEnabled ? .on : .off
        }
    }

    // MARK: - 动作

    @objc private func toggleVisible() {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            // 重新出现前先重建内容，避免把上次留下的旧画面一起带回来
            panel.refreshDisplay()
            panel.orderFrontRegardless()
        }
    }

    @objc private func reloadPage() {
        panel.reload()
    }

    /// 贴纸上留了「没擦干净的印记」时用：把内容层重建、窗口缓存丢掉
    @objc private func fixGhosting() {
        panel.forceRedraw()
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

    /// 开机自动启动：往 ~/Library/LaunchAgents 写一份 plist
    @objc private func toggleLoginItem() {
        if LaunchAtLogin.isEnabled {
            if let err = LaunchAtLogin.disable() { showError(err, title: "关掉自动启动失败") }
        } else {
            if let err = LaunchAtLogin.enable() { showError(err, title: "开启自动启动失败") }
        }
    }

    private func showError(_ message: String, title: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
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
            onCancel: { [weak self] in self?.closeSettings() },
            // 编辑器会自己改 entities/icons/names，同时开着会让设置窗口里的旧快照把它冲掉
            onEditTiles: { [weak self] in
                guard let self = self else { return }
                self.closeSettings()
                self.openTileEditor()
            }
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

    // MARK: - 贴纸内容编辑器

    @objc func openTileEditor() {
        if let win = tileWindow {
            NSApp.activate(ignoringOtherApps: true)
            win.makeKeyAndOrderFront(nil)
            return
        }

        let view = TileEditorView(
            settings: settings,
            onSave: { [weak self] newSettings in
                guard let self = self else { return }
                self.settings = newSettings
                newSettings.save()
                // Reconfigure 里会比对 base + token，没变就不会重连，只是重画磁贴
                self.panel.update(settings: newSettings)
                self.closeTileEditor()
            },
            onCancel: { [weak self] in self?.closeTileEditor() }
        )

        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 700),
                           styleMask: [.titled, .closable],
                           backing: .buffered,
                           defer: false)
        win.title = "编辑贴纸内容"
        win.contentView = NSHostingView(rootView: view)
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.center()
        tileWindow = win

        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    private func closeTileEditor() {
        tileWindow?.close()
        tileWindow = nil
    }

    func windowWillClose(_ notification: Notification) {
        guard let win = notification.object as? NSWindow else { return }
        if win === settingsWindow {
            settingsWindow = nil
        } else if win === tileWindow {
            tileWindow = nil
        } else {
            return
        }
        // 设置 / 编辑器窗口曾经盖在贴纸上，关掉后贴纸这块画面容易留下旧窗口的印记，
        // 等关闭动画结束再整体重建一次
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.panel.forceRedraw()
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
