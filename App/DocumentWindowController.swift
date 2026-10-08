import AppKit
import UniformTypeIdentifiers

final class DocumentWindowController: NSWindowController {
    let viewer = MarkdownViewer()
    private let titleLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = .titleBarFont(ofSize: 0)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingMiddle
        label.alignment = .center
        return label
    }()

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 960),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        // No toolbar: the file name stays centered, and the title bar only shows a divider
        // once content scrolls beneath it.
        window.titlebarSeparatorStyle = .automatic
        window.tabbingMode = .disallowed
        window.backgroundColor = Palette.background
        window.contentView = viewer.scrollView
        // Known up front, so the first frame is already scrolled to the top below the title bar.
        viewer.scrollView.automaticallyAdjustsContentInsets = false
        viewer.scrollView.contentInsets.top = window.frame.height - window.contentLayoutRect.height
        window.minSize = NSSize(width: 360, height: 240)
        // macOS 26+ left-aligns titles; draw our own centered one instead.
        window.titleVisibility = .hidden
        if let titlebar = window.standardWindowButton(.closeButton)?.superview {
            titleLabel.translatesAutoresizingMaskIntoConstraints = false
            titlebar.addSubview(titleLabel)
            NSLayoutConstraint.activate([
                titleLabel.centerXAnchor.constraint(equalTo: titlebar.centerXAnchor),
                titleLabel.centerYAnchor.constraint(equalTo: window.standardWindowButton(.closeButton)!.centerYAnchor),
                titleLabel.widthAnchor.constraint(lessThanOrEqualTo: titlebar.widthAnchor, constant: -180),
            ])
        }
        super.init(window: window)
        viewer.textView.onFirstDraw = { Trace.firstDraw() }
        shouldCascadeWindows = true
        windowFrameAutosaveName = "MarkdownWindow"
        viewer.onOpenURL = { url in
            if url.isFileURL, UTType(filenameExtension: url.pathExtension)?.conforms(to: UTType("net.daringfireball.markdown") ?? .plainText) == true {
                NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
            } else {
                NSWorkspace.shared.open(url)
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func windowDidLoad() {
        super.windowDidLoad()
        window?.center()
    }

    /// Debug aid: writes the window's content to a PNG (works without screen-recording permission).
    func snapshot(to path: String) {
        guard let view = window?.contentView?.superview, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        // Becoming first responder scrolls the text view's insertion point into view, ignoring the
        // title bar inset; start at the real top instead.
        viewer.scrollToTop()
    }

    override func synchronizeWindowTitleWithDocumentName() {
        super.synchronizeWindowTitleWithDocumentName()
        titleLabel.stringValue = window?.title ?? ""
    }

    @objc func showInFinder(_ sender: Any?) {
        guard let url = (document as? NSDocument)?.fileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
