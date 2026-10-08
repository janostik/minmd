import AppKit

/// A scrolling, read-only Markdown view. Text appears synchronously; syntax colors, remote images
/// and Mermaid diagrams are filled in afterwards without blocking the first paint.
final class MarkdownViewer: NSObject, NSTextViewDelegate {
    let scrollView = NSScrollView()
    let textView: MarkdownTextView

    /// Called for links that leave the document (web pages, other files).
    var onOpenURL: ((URL) -> Void)?
    /// The shown file, so links to `#fragment`s within it scroll instead of reopening it.
    var currentFilePath: String?

    private var markdown = ""
    private var directory: URL?
    private var fontFamily = Preferences.defaultFont
    private var zoom: Double = 1
    private var anchors: [String: Int] = [:]
    private var diagrams: [(cell: ImageCell, source: String)] = []
    private var generation = 0
    private var renderedDiagrams: (generation: Int, dark: Bool)?

    static let baseSize: CGFloat = 14

    override init() {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)
        // Lay out what's visible first; long documents fill in as you scroll.
        layout.allowsNonContiguousLayout = true
        // TextKit 1 on purpose: tables and block backgrounds (NSTextBlock) need it.
        textView = MarkdownTextView(frame: .zero, textContainer: container)
        super.init()

        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.drawsBackground = true
        textView.backgroundColor = Palette.background
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.linkTextAttributes = [.foregroundColor: Palette.link, .cursor: NSCursor.pointingHand]
        textView.delegate = self
        textView.onAppearanceChange = { [weak self] in self?.renderDiagrams() }

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = Palette.background
    }

    /// Renders `markdown`, keeping the scroll position when the same document is re-rendered.
    func show(markdown: String, directory: URL?, fontFamily: String, zoom: Double) {
        let sameDocument = directory == self.directory && !self.markdown.isEmpty
        self.markdown = markdown
        self.directory = directory
        self.fontFamily = fontFamily
        self.zoom = zoom
        generation += 1

        let size = (Self.baseSize * zoom).rounded()
        let rendered = MarkdownRenderer(fontFamily: fontFamily, size: size, directory: directory).render(markdown)
        let origin = scrollView.contentView.bounds.origin

        textView.maxContentWidth = 54 * size
        textView.textStorage?.setAttributedString(rendered.text)
        anchors = rendered.anchors
        diagrams = rendered.diagrams

        if sameDocument {
            textView.layoutManager?.ensureLayout(for: textView.textContainer!)
            scrollView.contentView.scroll(to: origin)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        highlight(rendered.codeBlocks)
        loadImages(rendered.pendingImages)
        // Starting WebKit costs tens of milliseconds; never let it delay the first frame.
        textView.afterNextDraw { [weak self] in self?.renderDiagrams() }
    }

    /// Scrolls to the very top, below a transparent title bar if there is one.
    func scrollToTop() {
        scrollView.layoutSubtreeIfNeeded()
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: -scrollView.contentInsets.top))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    /// Re-renders with new settings (font family or zoom) if they changed.
    func update(fontFamily: String, zoom: Double) {
        guard fontFamily != self.fontFamily || zoom != self.zoom else { return }
        show(markdown: markdown, directory: directory, fontFamily: fontFamily, zoom: zoom)
    }

    // MARK: - Deferred work

    private func highlight(_ blocks: [(range: NSRange, language: String)]) {
        guard !blocks.isEmpty, let storage = textView.textStorage else { return }
        let generation = generation
        let sources = blocks.map { (code: storage.attributedSubstring(from: $0.range).string, language: $0.language) }
        SyntaxHighlighter.shared.highlight(sources) { [weak self] results in
            guard let self, self.generation == generation, let storage = self.textView.textStorage else { return }
            storage.beginEditing()
            for (block, runs) in zip(blocks, results) {
                for run in runs where NSMaxRange(run.range) <= block.range.length {
                    storage.addAttribute(.foregroundColor, value: run.color,
                                         range: NSRange(location: block.range.location + run.range.location, length: run.range.length))
                }
            }
            storage.endEditing()
        }
    }

    private func loadImages(_ images: [(cell: ImageCell, url: URL)]) {
        for (cell, url) in images {
            let key = ImageCell.cacheKey(url)
            let deliver: (NSImage) -> Void = { [weak self] image in
                DispatchQueue.main.async {
                    ImageCell.cache.setObject(image, forKey: key)
                    let sizeKnown = cell.reservedSize != nil
                    cell.image = image
                    if sizeKnown { self?.textView.needsDisplay = true } else { self?.relayout() }
                }
            }
            if url.isFileURL {
                DispatchQueue.global(qos: .userInitiated).async {
                    if let image = Self.decodedImage(url, size: cell.reservedSize) { deliver(image) }
                }
            } else {
                URLSession.shared.dataTask(with: url) { data, _, _ in
                    if let data, let image = NSImage(data: data) { deliver(image) }
                }.resume()
            }
        }
    }

    /// Fully decodes the pixels now, so drawing on the main thread doesn't have to.
    private static func decodedImage(_ url: URL, size: NSSize?) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        else { return NSImage(contentsOf: url) }
        return NSImage(cgImage: cgImage, size: size ?? NSSize(width: cgImage.width, height: cgImage.height))
    }

    private func renderDiagrams() {
        guard !diagrams.isEmpty else { return }
        let generation = generation
        let dark = textView.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        if let rendered = renderedDiagrams, rendered == (generation, dark) { return }
        renderedDiagrams = (generation, dark)
        let width = textView.maxContentWidth
        for (cell, source) in diagrams {
            MermaidRenderer.shared.render(source, dark: dark, width: width) { [weak self] result in
                guard let self, self.generation == generation else { return }
                switch result {
                case .success(let image): cell.image = image
                case .failure: cell.placeholder = "Mermaid diagram could not be rendered."
                }
                self.relayout()
            }
        }
    }

    private func relayout() {
        guard let layout = textView.layoutManager, let storage = textView.textStorage else { return }
        layout.invalidateLayout(forCharacterRange: NSRange(location: 0, length: storage.length), actualCharacterRange: nil)
        textView.needsDisplay = true
    }

    // MARK: - Links

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        let url = (link as? URL) ?? (link as? String).flatMap(URL.init(string:))
        guard let url else { return true }
        if url.scheme == nil, let fragment = url.fragment, url.path.isEmpty {
            scrollToAnchor(fragment)
        } else if url.isFileURL, let fragment = url.fragment, url.path == currentFilePath {
            scrollToAnchor(fragment)
        } else {
            onOpenURL?(url)
        }
        return true
    }

    private func scrollToAnchor(_ fragment: String) {
        let key = (fragment.removingPercentEncoding ?? fragment).lowercased()
        guard let location = anchors[key], let layout = textView.layoutManager, let container = textView.textContainer else { return }
        let glyphs = layout.glyphRange(forCharacterRange: NSRange(location: location, length: 0), actualCharacterRange: nil)
        let rect = layout.boundingRect(forGlyphRange: glyphs, in: container)
        let y = rect.minY + textView.textContainerOrigin.y - scrollView.contentInsets.top - 8
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: max(y, -scrollView.contentInsets.top)))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
}

/// Keeps the text in a centered, readable column whatever the window width.
final class MarkdownTextView: NSTextView {
    var maxContentWidth: CGFloat = 760 {
        didSet { updateInsets(for: frame.size) }
    }
    var onAppearanceChange: (() -> Void)?

    override func setFrameSize(_ newSize: NSSize) {
        updateInsets(for: newSize)
        super.setFrameSize(newSize)
    }

    private func updateInsets(for size: NSSize) {
        let horizontal = max(28, ((size.width - maxContentWidth) / 2).rounded())
        if textContainerInset.width != horizontal {
            textContainerInset = NSSize(width: horizontal, height: 24)
        }
    }

    var onFirstDraw: (() -> Void)?
    private var afterDraw: [() -> Void] = []

    /// Runs `action` right after the next frame has been drawn.
    func afterNextDraw(_ action: @escaping () -> Void) {
        afterDraw.append(action)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if let onFirstDraw {
            self.onFirstDraw = nil
            onFirstDraw()
        }
        if !afterDraw.isEmpty {
            let actions = afterDraw
            afterDraw = []
            DispatchQueue.main.async { actions.forEach { $0() } }
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChange?()
    }
}
