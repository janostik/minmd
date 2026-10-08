import Cocoa
import Quartz

/// Finder's space-bar preview, rendered with the same page and settings as the app.
final class PreviewViewController: NSViewController, QLPreviewingController {
    private let webView = MarkdownWebView()

    override func loadView() {
        view = webView
        preferredContentSize = NSSize(width: 860, height: 1000)
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            handler(error)
            return
        }

        view.appearance = Preferences.theme.appearance
        webView.pageZoom = Preferences.zoom
        webView.onOpenURL = { NSWorkspace.shared.open($0) }

        // Hand the preview over once it has painted, or after a short timeout at the latest.
        var finished = false
        let finish = {
            guard !finished else { return }
            finished = true
            handler(nil)
        }
        webView.onReady = finish
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: finish)

        webView.show(markdown: Renderer.decode(data), fontFamily: Preferences.fontFamily, baseURL: url.deletingLastPathComponent())
    }
}
