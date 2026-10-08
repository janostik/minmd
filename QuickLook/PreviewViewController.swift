import Cocoa
import Quartz

/// Finder's space-bar preview, rendered natively with the same renderer and settings as the app.
final class PreviewViewController: NSViewController, QLPreviewingController {
    private let viewer = MarkdownViewer()

    override func loadView() {
        view = viewer.scrollView
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
        viewer.currentFilePath = url.path
        viewer.onOpenURL = { NSWorkspace.shared.open($0) }
        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .windowsCP1252)
            ?? String(decoding: data, as: UTF8.self)
        viewer.show(markdown: text, directory: url.deletingLastPathComponent(),
                    fontFamily: Preferences.fontFamily, zoom: Preferences.zoom)
        viewer.scrollToTop()
        handler(nil)
    }
}
