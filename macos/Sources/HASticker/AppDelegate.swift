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

    override init() {
        self.settings = StickerSettings.load()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildStatusItem()
        rightClickMenu = buildMenu()

        panel = StickerPanel(settings: settings)
        panel.content.load()
        panel.orderFrontRegardless()

        installRightClickMonitor()
        observeFrameChanges()

        if !settings.isConfigured {
            openSettings()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        panel?.captureFrame()
        if let s = panel?.currentSettings { s.save() }
        if let m = localMonitor { NSEvent.removeMonitor(m) }
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
        m.addItem(withTitle: "在浏览器里打开 HA", action: #selector(openInBrowser), keyEquivalent: "")
        m.addItem(.separator())

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

        let lockItem = NSMenuItem(title: "锁定位置", action: #selector(toggleLock), keyEquivalent: "")
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
                if let modeRaw = subItem.representedObject as? String,
                   StickerMode(rawValue: modeRaw) != nil {
                    subItem.state = (modeRaw == settings.mode.rawValue) ? .on : .off
                } else if let value = subItem.representedObject as? Double {
                    subItem.state = abs(value - settings.opacity) < 0.001 ? .on : .off
                }
            }
        }
        if let lock = menu.items.first(where: { ($0.representedObject as? String) == "lock" }) {
            lock.state = settings.lockPosition ? .on : .off
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
        panel.content.reload()
    }

    @objc private func openInBrowser() {
        if let s = settings.normalizedURLString(), let url = URL(string: s) {
            NSWorkspace.shared.open(url)
        }
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
                self.panel.content.load()
                self.closeSettings()
            },
            onCancel: { [weak self] in self?.closeSettings() }
        )

        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 430),
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

    private func saveFrame() {
        panel.captureFrame()
        settings = panel.currentSettings
        settings.save()
    }
}
