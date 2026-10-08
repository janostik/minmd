import AppKit

/// A read-only Markdown document. minmd never writes files.
final class MarkdownDocument: NSDocument {
    private(set) var text = ""
    private var watcher: FileWatcher?
    private var viewer: MarkdownViewer? {
        (windowControllers.first as? DocumentWindowController)?.viewer
    }

    override class var autosavesInPlace: Bool { false }

    override func read(from data: Data, ofType typeName: String) throws {
        text = Self.decode(data)
        Trace.mark("document-read")
    }

    override func data(ofType typeName: String) throws -> Data {
        throw CocoaError(.fileWriteNoPermission)
    }

    override func makeWindowControllers() {
        let controller = DocumentWindowController()
        addWindowController(controller)
        controller.viewer.currentFilePath = fileURL?.path
        controller.viewer.show(markdown: text, directory: fileURL?.deletingLastPathComponent(),
                               fontFamily: Preferences.fontFamily, zoom: Preferences.zoom)
        controller.viewer.scrollToTop()
        startWatching()
        Trace.mark("window-ready")
        if let path = ProcessInfo.processInfo.environment["MINMD_SNAPSHOT"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { controller.snapshot(to: path) }
        }
    }

    func applyPreferences() {
        viewer?.update(fontFamily: Preferences.fontFamily, zoom: Preferences.zoom)
    }

    // Live reload is handled by the watcher; NSDocument's own handling would offer to revert.
    override func presentedItemDidChange() {}

    override var fileURL: URL? {
        didSet { if oldValue != nil, oldValue != fileURL { startWatching() } }
    }

    private func startWatching() {
        guard let url = fileURL else { return }
        watcher = FileWatcher(url: url) { [weak self] in self?.reload() }
    }

    private func reload() {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return }
        let text = Self.decode(data)
        guard text != self.text else { return }
        self.text = text
        viewer?.show(markdown: text, directory: url.deletingLastPathComponent(),
                     fontFamily: Preferences.fontFamily, zoom: Preferences.zoom)
    }

    /// Markdown files are almost always UTF-8; fall back gracefully for the odd legacy file.
    static func decode(_ data: Data) -> String {
        String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .windowsCP1252)
            ?? String(decoding: data, as: UTF8.self)
    }
}
