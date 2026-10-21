import AppKit

// 贴纸是「辅助型」app：不进 Dock、不进 Command+Tab，只在菜单栏留一个图标。
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
