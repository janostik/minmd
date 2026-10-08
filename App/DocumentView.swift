import SwiftUI
import UniformTypeIdentifiers

struct DocumentView: View {
    let fileURL: URL?

    @AppStorage(Preferences.fontKey) private var fontFamily = Preferences.defaultFont
    @AppStorage(Preferences.zoomKey) private var zoom = 1.0
    @State private var text: String
    @State private var watcher: FileWatcher?

    init(text: String, fileURL: URL?) {
        self.fileURL = fileURL
        _text = State(initialValue: text)
    }

    var body: some View {
        MarkdownView(markdown: text, fontFamily: fontFamily, zoom: zoom,
                     baseURL: fileURL?.deletingLastPathComponent())
            .ignoresSafeArea()
            .background(Color(nsColor: .solarizedBackground))
            .task(id: fileURL) {
                guard let fileURL else { return }
                reload(from: fileURL)
                watcher = FileWatcher(url: fileURL) { reload(from: fileURL) }
            }
    }

    private func reload(from url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }
        text = Renderer.decode(data)
    }
}

private struct MarkdownView: NSViewRepresentable {
    let markdown: String
    let fontFamily: String
    let zoom: Double
    let baseURL: URL?

    func makeNSView(context: Context) -> WindowAwareWebView {
        let webView = WindowAwareWebView()
        webView.options.findBar = true
        webView.options.topInset = 28
        webView.onOpenURL = Self.open
        return webView
    }

    func updateNSView(_ webView: WindowAwareWebView, context: Context) {
        webView.pageZoom = zoom
        webView.show(markdown: markdown, fontFamily: fontFamily, baseURL: baseURL)
    }

    private static func open(_ url: URL) {
        if url.isFileURL, UTType(filenameExtension: url.pathExtension)?.conforms(to: .markdown) == true {
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
        } else {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Lets the page run edge to edge under a transparent title bar.
private final class WindowAwareWebView: MarkdownWebView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.backgroundColor = .solarizedBackground
        window.tabbingMode = .disallowed
    }
}
