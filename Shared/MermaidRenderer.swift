import AppKit
import WebKit

/// Renders Mermaid diagrams to images with one hidden, shared web view. It is only created when a
/// document actually contains a diagram, so plain documents never start WebKit.
final class MermaidRenderer: NSObject, WKNavigationDelegate {
    static let shared = MermaidRenderer()

    private var webView: WKWebView?
    private var window: NSWindow?
    private var ready = false
    private var pending: [() -> Void] = []
    private var busy = false

    func render(_ source: String, dark: Bool, width: CGFloat, completion: @escaping (Result<NSImage, Error>) -> Void) {
        enqueue { [weak self] in self?.perform(source, dark: dark, width: width, completion: completion) }
    }

    private func enqueue(_ job: @escaping () -> Void) {
        pending.append(job)
        if webView == nil { load() } else { next() }
    }

    private func next() {
        guard ready, !busy, !pending.isEmpty else { return }
        busy = true
        pending.removeFirst()()
    }

    private func finish() {
        busy = false
        next()
    }

    private func load() {
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1200, height: 4000))
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = self
        // Snapshots need the view in a window; this one is never shown.
        let window = NSWindow(contentRect: webView.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = webView
        self.webView = webView
        self.window = window
        guard let page = Bundle.main.url(forResource: "mermaid", withExtension: "html") else { return }
        webView.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        ready = true
        next()
    }

    private func perform(_ source: String, dark: Bool, width: CGFloat, completion: @escaping (Result<NSImage, Error>) -> Void) {
        guard let webView else { return finish() }
        webView.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        webView.callAsyncJavaScript("return await renderDiagram(source, dark, width)",
                                    arguments: ["source": source, "dark": dark, "width": width],
                                    in: nil, in: .page) { [weak self] result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
                self?.finish()
            case .success(let value):
                guard let size = value as? [String: Double], let w = size["width"], let h = size["height"], w > 0, h > 0 else {
                    completion(.failure(CocoaError(.coderInvalidValue)))
                    self?.finish()
                    return
                }
                let config = WKSnapshotConfiguration()
                config.rect = NSRect(x: 0, y: 0, width: ceil(w), height: ceil(h))
                config.afterScreenUpdates = true
                webView.takeSnapshot(with: config) { image, error in
                    if let image { completion(.success(image)) } else { completion(.failure(error ?? CocoaError(.coderInvalidValue))) }
                    self?.finish()
                }
            }
        }
    }
}
