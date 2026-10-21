import AppKit
import WebKit

/// 贴纸的内容：一个圆角容器 + WKWebView（持久 cookie，登录一次长期有效）
final class StickerContentView: NSView, WKNavigationDelegate {
    private(set) var webView: WKWebView!
    private var settings: StickerSettings
    private var isDark = false

    private static let lightBG = NSColor(calibratedWhite: 0.97, alpha: 1)
    private static let darkBG  = NSColor(calibratedRed: 0.11, green: 0.11, blue: 0.12, alpha: 1)

    init(settings: StickerSettings) {
        self.settings = settings
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = CGFloat(settings.cornerRadius)
        layer?.masksToBounds = true
        layer?.backgroundColor = StickerContentView.lightBG.cgColor

        setupWebView()
        applyAppearance(appearance: settings.appearance.nsAppearance,
                        isDark: settings.appearance.resolvedIsDark)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        // 默认数据存储是持久的，HA 登录态会一直留着
        config.websiteDataStore = .default()
        // 拖动贴纸时不希望网页里的文字被框选
        config.userContentController = WKUserContentController()

        let wv = StickerWebView(frame: bounds, configuration: config)
        wv.autoresizingMask = [.width, .height]
        wv.navigationDelegate = self
        wv.allowsBackForwardNavigationGestures = false
        wv.allowsMagnification = true
        // 让网页背景透明，配合圆角容器不出现白边
        wv.setValue(false, forKey: "drawsBackground")
        if #available(macOS 11.0, *) {
            wv.pageZoom = CGFloat(settings.zoom)
        }
        addSubview(wv)
        self.webView = wv
    }

    func update(settings newSettings: StickerSettings) {
        settings = newSettings
        layer?.cornerRadius = CGFloat(settings.cornerRadius)
        if #available(macOS 11.0, *) {
            webView.pageZoom = CGFloat(settings.zoom)
        }
    }

    /// 切换深浅色：容器底色 + 网页 appearance + 强制给 HA 推一次主题
    func applyAppearance(appearance: NSAppearance?, isDark dark: Bool) {
        isDark = dark
        self.appearance = appearance
        webView?.appearance = appearance
        layer?.backgroundColor = (dark ? StickerContentView.darkBG : StickerContentView.lightBG).cgColor
        installThemeScript(dark: dark)
    }

    /// 注入脚本：让 HA 前端跟着切深色（前端主题设为「默认」时会看 prefers-color-scheme，
    /// 这里再补一道保险，直接给 home-assistant 元素发 settheme）
    private func installThemeScript(dark: Bool) {
        guard let controller = webView?.configuration.userContentController else { return }
        controller.removeAllUserScripts()

        let js = """
        (function(){
          var dark = \(dark ? "true" : "false");
          try { document.documentElement.style.colorScheme = dark ? 'dark' : 'light'; } catch(e){}
          var tries = 0;
          function apply(){
            try {
              var ha = document.querySelector('home-assistant');
              if (ha) {
                ha.dispatchEvent(new CustomEvent('settheme', { detail: { theme: 'default', dark: dark } }));
              }
            } catch(e){}
            if (++tries < 8) { setTimeout(apply, 600); }
          }
          apply();
        })();
        """
        controller.addUserScript(WKUserScript(source: js,
                                              injectionTime: .atDocumentEnd,
                                              forMainFrameOnly: true))
    }

    func load() {
        installThemeScript(dark: isDark)
        guard let s = settings.normalizedURLString(), let url = URL(string: s) else {
            showErrorPage(title: "还没设置 HA 地址",
                          detail: "右键贴纸，或点菜单栏图标 → 设置",
                          retryURL: nil)
            return
        }
        webView.load(URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 30))
    }

    /// 用自己的不透明错误页替掉白屏/404 页，免得桌面图标透出来像坏掉了
    private func showErrorPage(title: String, detail: String, retryURL: String?) {
        let safeDetail = detail.replacingOccurrences(of: "\n", with: "<br>")
        let retry = retryURL == nil ? "" :
            "<a href=\"\(retryURL!)\" style=\"display:inline-block;margin-top:16px;padding:6px 16px;" +
            "border-radius:6px;background:\(isDark ? "#3a3a3c" : "#e0e0e3");" +
            "color:\(isDark ? "#e8e8e8" : "#1c1c1e");text-decoration:none;font-size:12px\">重试</a>"
        let bg = isDark ? "#1c1c1e" : "#f6f6f7"
        let fg = isDark ? "#d8d8d8" : "#1c1c1e"
        let sub = isDark ? "#8a8a8e" : "#6b6b70"
        let html = """
        <!doctype html><html><head><meta charset="utf-8">
        <style>
        html,body{margin:0;height:100%;background:\(bg);}
        .wrap{height:100%;display:flex;align-items:center;justify-content:center;
              font-family:-apple-system,"PingFang SC",sans-serif;text-align:center;color:\(fg);}
        .t{font-size:14px;margin-bottom:10px;}
        .d{font-size:12px;line-height:1.8;color:\(sub);word-break:break-all;padding:0 18px;}
        </style></head><body><div class="wrap"><div>
        <div class="t">\(title)</div><div class="d">\(safeDetail)</div>\(retry)
        </div></div></body></html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    func reload() {
        if webView.url == nil {
            load()
        } else {
            webView.reload()
        }
    }

    /// 清掉 HA 的登录态，下次会重新要求登录
    func clearLogin() {
        let store = webView.configuration.websiteDataStore
        store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                         modifiedSince: Date(timeIntervalSince1970: 0)) { [weak self] in
            DispatchQueue.main.async { self?.load() }
        }
    }

    // MARK: - WKNavigationDelegate

    /// 先看 HTTP 状态码：404 基本就是仪表盘路径不对，直接给个能看懂的错误页
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if navigationResponse.isForMainFrame,
           let http = navigationResponse.response as? HTTPURLResponse,
           http.statusCode >= 400 {
            decisionHandler(.cancel)

            var detail = "HA 返回 HTTP \(http.statusCode)\n\(settings.haURL)"
            if http.statusCode == 404 {
                detail = "仪表盘路径不存在\n\(settings.haURL)\n\n在 HA 里建好这个仪表盘，\n或者右键 → 设置 换个地址"
            }
            let retry = settings.normalizedURLString()
            showErrorPage(title: "打不开仪表盘", detail: detail, retryURL: retry)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView,
                 didFail navigation: WKNavigation!,
                 withError error: Error) {
        showErrorPage(title: "打不开 HA",
                      detail: error.localizedDescription,
                      retryURL: settings.normalizedURLString())
    }

    func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        let nsError = error as NSError
        // 网页内部的资源加载失败不提示，只看主文档
        if nsError.code == NSURLErrorCannotFindHost ||
            nsError.code == NSURLErrorCannotConnectToHost ||
            nsError.code == NSURLErrorTimedOut {
            showErrorPage(title: "连不上 HA",
                          detail: "检查地址和网络\n\(settings.haURL)",
                          retryURL: settings.normalizedURLString())
        }
    }
}

/// WKWebView 的子类，只为一件事：接受「第一次点击」。
/// NSView.acceptsFirstMouse 默认 false —— app 未激活时，第一次点击只被用来
/// 激活窗口、不会传给视图。贴纸平时就是未激活状态，那样第一次点开关会没反应，
/// 必须点两下才生效。这里改成 true。
final class StickerWebView: WKWebView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
