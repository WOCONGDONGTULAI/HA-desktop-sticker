import AppKit

// 关掉常驻滚动条（必须在建 WKWebView 之前设）。
//
// 系统设置 → 外观 →「显示滚动条」如果是「始终」，WebKit 会画 15px 的常驻滚动条，
// 贴纸那么窄，右边和底下永远挂两条很难看。而且实测过几条路都走不通：
//   - 文档级 CSS `::-webkit-scrollbar{width:0}`：只对主文档有效，穿不进 shadow DOM，
//     而 HA 是 Lit 写的、页面几乎全是 shadow DOM；
//   - 塞进 shadow root 里的 CSS：同样无效（样式在，但滚动条照画）；
//   - WKWebView 私有开关 _setAlwaysShowsVerticalScroller: 无效。
// 唯一对所有情况都生效的是这个：NSUserDefaults 的 AppleShowScrollBars 写在
// **app 自己的域**里，优先级高于 NSGlobalDomain，所以能只对本 app 覆盖系统设置。
// 实测 Always → 15px 常驻；WhenScrolling → 0（悬浮式，不滑就不显示）。
UserDefaults.standard.set("WhenScrolling", forKey: "AppleShowScrollBars")

// 贴纸是「辅助型」app：不进 Dock、不进 Command+Tab，只在菜单栏留一个图标。
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
