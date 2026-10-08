import AppKit
import WebKit

/// A read-only web view that renders one Markdown string. After the first load, content and font
/// changes are pushed into the live page so scroll position survives reloads.
class MarkdownWebView: WKWebView, WKNavigationDelegate {
    var options = Renderer.Options()
    /// Called for clicked links that leave the page.
    var onOpenURL: ((URL) -> Void)?
    /// Called once the page has rendered.
    var onReady: (() -> Void)?

    private var markdown: String?
    private var renderedFont: String?
    private var loadedBaseURL: URL?
    private var pageReady = false
    private var expectingLoad = false

    init() {
        let config = WKWebViewConfiguration()
        config.suppressesIncrementalRendering = true
        super.init(frame: .zero, configuration: config)
        navigationDelegate = self
        allowsMagnification = true
        allowsBackForwardNavigationGestures = false
        setValue(false, forKey: "drawsBackground")
        underPageBackgroundColor = .solarizedBackground
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(markdown: String, fontFamily: String, baseURL: URL?) {
        guard pageReady, baseURL == loadedBaseURL else {
            load(markdown: markdown, fontFamily: fontFamily, baseURL: baseURL)
            return
        }
        if markdown != self.markdown {
            self.markdown = markdown
            callAsyncJavaScript("minmd.render(markdown)", arguments: ["markdown": markdown], in: nil, in: .page)
        }
        if fontFamily != renderedFont {
            renderedFont = fontFamily
            callAsyncJavaScript("minmd.setFont(stack)", arguments: ["stack": FontChoice.cssStack(for: fontFamily)], in: nil, in: .page)
        }
    }

    private func load(markdown: String, fontFamily: String, baseURL: URL?) {
        self.markdown = markdown
        renderedFont = fontFamily
        loadedBaseURL = baseURL
        pageReady = false
        expectingLoad = true
        var options = options
        options.fontFamily = fontFamily
        loadHTMLString(Renderer.html(markdown: markdown, options: options), baseURL: baseURL)
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if expectingLoad, action.navigationType == .other, action.targetFrame?.isMainFrame == true {
            expectingLoad = false
            decisionHandler(.allow)
            return
        }
        // The page never navigates itself: links open elsewhere, everything else is dropped.
        decisionHandler(.cancel)
        if action.navigationType == .linkActivated, let url = action.request.url {
            onOpenURL?(url)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pageReady = true
        onReady?()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        pageReady = false
        if let markdown, let renderedFont {
            load(markdown: markdown, fontFamily: renderedFont, baseURL: loadedBaseURL)
        }
    }
}
