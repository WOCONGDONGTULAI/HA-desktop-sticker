import AppKit
import WebKit

/// 贴纸的内容：一个圆角容器 + WKWebView（持久 cookie，登录一次长期有效）
final class StickerContentView: NSView, WKNavigationDelegate {
    private(set) var webView: WKWebView!
    private var settings: StickerSettings
    private var statusLabel: NSTextField?

    init(settings: StickerSettings) {
        self.settings = settings
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = CGFloat(settings.cornerRadius)
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        setupWebView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        // 默认数据存储是持久的，HA 登录态会一直留着
        config.websiteDataStore = .default()

        let wv = WKWebView(frame: bounds, configuration: config)
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

    func load() {
        guard let s = settings.normalizedURLString(), let url = URL(string: s) else {
            showStatus("还没设置 HA 地址\n右键贴纸或点菜单栏图标 → 设置")
            return
        }
        hideStatus()
        webView.load(URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 30))
    }

    func reload() {
        hideStatus()
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

    // MARK: - 加载失败提示

    private func showStatus(_ text: String) {
        if statusLabel == nil {
            let label = NSTextField(wrappingLabelWithString: text)
            label.alignment = .center
            label.textColor = .secondaryLabelColor
            label.font = NSFont.systemFont(ofSize: 13)
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: centerXAnchor),
                label.centerYAnchor.constraint(equalTo: centerYAnchor),
                label.widthAnchor.constraint(equalTo: widthAnchor, constant: -32)
            ])
            statusLabel = label
        }
        statusLabel?.stringValue = text
        statusLabel?.isHidden = false
    }

    private func hideStatus() {
        statusLabel?.isHidden = true
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView,
                 didFail navigation: WKNavigation!,
                 withError error: Error) {
        showStatus("打不开 HA\n\(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        let nsError = error as NSError
        // 网页内部的资源加载失败不提示，只看主文档
        if nsError.code == NSURLErrorCannotFindHost ||
            nsError.code == NSURLErrorCannotConnectToHost ||
            nsError.code == NSURLErrorTimedOut {
            showStatus("打不开 HA\n检查地址或网络：\n\(settings.haURL)")
        }
    }
}
