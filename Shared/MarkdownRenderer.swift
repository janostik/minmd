import AppKit
import Markdown

/// The result of rendering: styled text plus what the viewer needs to finish the job lazily.
struct RenderedMarkdown {
    let text: NSAttributedString
    /// Code blocks to syntax-highlight after the first paint.
    let codeBlocks: [(range: NSRange, language: String)]
    /// Heading slug → character offset, for `#fragment` links.
    let anchors: [String: Int]
    /// Images to load after the first paint (local files are decoded off the main thread).
    let pendingImages: [(cell: ImageCell, url: URL)]
    /// Mermaid diagrams, rendered to images after the first paint.
    let diagrams: [(cell: ImageCell, source: String)]
}

/// Turns Markdown (GitHub flavoured, parsed by swift-markdown / cmark-gfm) into an attributed string
/// laid out with TextKit 1 text blocks and tables.
final class MarkdownRenderer {
    private let family: String
    private let size: CGFloat
    private let directory: URL?

    private let out = NSMutableAttributedString()
    private var codeBlocks: [(range: NSRange, language: String)] = []
    private var anchors: [String: Int] = [:]
    private var pendingImages: [(cell: ImageCell, url: URL)] = []
    private var diagrams: [(cell: ImageCell, source: String)] = []
    private var fontCache: [String: NSFont] = [:]

    private struct Context {
        var indent: CGFloat = 0
        var blocks: [NSTextBlock] = []
        var color: NSColor = Palette.text
        var tight = false
    }

    private struct Style {
        var bold = false
        var italic = false
        var strike = false
        var code = false
        var scale: CGFloat = 1
        var link: URL?
        var color: NSColor = Palette.text
    }

    init(fontFamily: String, size: CGFloat, directory: URL?) {
        self.family = fontFamily
        self.size = size
        self.directory = directory
    }

    func render(_ source: String) -> RenderedMarkdown {
        var markdown = source
        if let (frontMatter, rest) = Self.splitFrontMatter(source) {
            codeBlock(frontMatter, language: "yaml", ctx: Context())
            markdown = rest
        }
        blocks(Document(parsing: markdown).children, ctx: Context())
        if out.mutableString.hasSuffix("\n") {
            out.deleteCharacters(in: NSRange(location: out.length - 1, length: 1))
        }
        return RenderedMarkdown(text: out, codeBlocks: codeBlocks, anchors: anchors,
                                pendingImages: pendingImages, diagrams: diagrams)
    }

    // MARK: - Blocks

    private func blocks(_ children: MarkupChildren, ctx: Context, marker: NSAttributedString? = nil) {
        var marker = marker
        for child in children {
            block(child, ctx: ctx, marker: marker)
            marker = nil
        }
    }

    private func block(_ markup: Markup, ctx: Context, marker: NSAttributedString?) {
        switch markup {
        case let heading as Heading:
            let scale: CGFloat = [1.75, 1.4, 1.18, 1.0, 1.0, 1.0][min(heading.level, 6) - 1]
            let start = out.length
            anchors[slug(heading.plainText)] = start
            let text = inlines(heading.children, Style(bold: true, scale: scale, color: heading.level == 6 ? Palette.muted : ctx.color))
            paragraph(text, ctx: ctx, before: start == 0 ? 0 : size * 1.5, after: size * 0.6)

        case let paragraph as Paragraph:
            if let image = Self.soleImage(paragraph) {
                self.paragraph(imageText(image.source, alt: image.plainText, width: nil), ctx: ctx, marker: marker)
            } else {
                self.paragraph(inlines(paragraph.children, Style(color: ctx.color)), ctx: ctx, marker: marker)
            }

        case let quote as BlockQuote:
            let block = Self.fullWidthBlock()
            block.setWidth(3, type: .absoluteValueType, for: .border, edge: .minX)
            block.setBorderColor(Palette.border, for: .minX)
            block.setWidth(size, type: .absoluteValueType, for: .padding, edge: .minX)
            block.setWidth(size * 0.9, type: .absoluteValueType, for: .margin, edge: .maxY)
            var inner = ctx
            inner.blocks.append(block)
            inner.color = Palette.muted
            blocks(quote.children, ctx: inner)
            trimTrailingSpacing()

        case let code as CodeBlock where code.language?.lowercased() == "mermaid":
            let cell = ImageCell(maxWidth: nil)
            cell.placeholder = "Rendering diagram…"
            diagrams.append((cell, code.code))
            let attachment = NSTextAttachment()
            attachment.attachmentCell = cell
            paragraph(NSAttributedString(attachment: attachment), ctx: ctx)

        case let code as CodeBlock:
            codeBlock(code.code, language: code.language, ctx: ctx)

        case let list as UnorderedList:
            listItems(Array(list.listItems), ordered: nil, ctx: ctx)

        case let list as OrderedList:
            listItems(Array(list.listItems), ordered: Int(list.startIndex), ctx: ctx)

        case let table as Table:
            self.table(table, ctx: ctx)

        case is ThematicBreak:
            let block = Self.fullWidthBlock()
            block.setWidth(1, type: .absoluteValueType, for: .border, edge: .maxY)
            block.setBorderColor(Palette.border, for: .maxY)
            block.setWidth(size * 1.2, type: .absoluteValueType, for: .margin, edge: .minY)
            block.setWidth(size * 1.6, type: .absoluteValueType, for: .margin, edge: .maxY)
            var inner = ctx
            inner.blocks.append(block)
            let style = paragraphStyle(ctx: inner)
            out.append(NSAttributedString(string: " \n", attributes: [.font: font(Style(scale: 0.2)), .paragraphStyle: style]))

        case let html as HTMLBlock:
            htmlBlock(html.rawHTML, ctx: ctx)

        default:
            // Directives and anything unexpected: show their text rather than dropping it.
            let text = markup.format().trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { paragraph(NSAttributedString(string: text, attributes: attributes(Style(color: ctx.color))), ctx: ctx) }
        }
    }

    private func listItems(_ items: [ListItem], ordered start: Int?, ctx: Context) {
        let markerWidth = size * (start == nil ? 1.6 : 2.3)
        for (index, item) in items.enumerated() {
            let markerText: String
            var markerStyle = Style(color: Palette.muted)
            switch item.checkbox {
            case .checked?: markerText = "☑"; markerStyle.color = Palette.link
            case .unchecked?: markerText = "☐"
            case nil:
                if let start { markerText = "\(start + index)."; markerStyle.code = true } else {
                    markerText = ["•", "◦", "▪"][Int(ctx.indent / (size * 1.6)) % 3]
                }
            }
            var markerAttributes = attributes(markerStyle)
            markerAttributes[.backgroundColor] = nil
            let marker = NSAttributedString(string: markerText + "\t", attributes: markerAttributes)
            var inner = ctx
            inner.indent += markerWidth
            inner.tight = true
            blocks(item.children, ctx: inner, marker: marker)
        }
        trimTrailingSpacing()
    }

    private func codeBlock(_ code: String, language: String?, ctx: Context) {
        let block = Self.fullWidthBlock()
        block.backgroundColor = Palette.codeBackground
        block.setWidth(size * 0.9, type: .absoluteValueType, for: .padding)
        var inner = ctx
        inner.blocks.append(block)

        let style = NSMutableParagraphStyle()
        style.textBlocks = inner.blocks
        style.firstLineHeadIndent = ctx.indent
        style.headIndent = ctx.indent
        style.lineSpacing = size * 0.2

        var body = code
        if body.hasSuffix("\n") { body.removeLast() }
        let start = out.length
        out.append(NSAttributedString(string: body + "\n", attributes: [
            .font: font(Style(code: true, scale: 0.9)),
            .foregroundColor: Palette.text,
            .paragraphStyle: style,
        ]))
        if let language = language?.split(separator: " ").first.map(String.init), !language.isEmpty {
            codeBlocks.append((NSRange(location: start, length: (body as NSString).length), language))
        }
        spacer(ctx: ctx)
    }

    /// A tiny paragraph outside the preceding block. It ends the block (TextKit would otherwise fuse
    /// it with an identical block that follows) and provides the gap after it.
    private func spacer(ctx: Context) {
        let style = paragraphStyle(ctx: ctx)
        style.lineSpacing = 0
        style.paragraphSpacing = size * 0.6
        out.append(NSAttributedString(string: "\n", attributes: [.font: font(Style(scale: 0.3)), .paragraphStyle: style]))
    }

    private func table(_ table: Table, ctx: Context) {
        let columns = max(table.maxColumnCount, 1)
        let textTable = NSTextTable()
        textTable.numberOfColumns = columns
        textTable.collapsesBorders = true
        textTable.hidesEmptyCells = false

        let rows: [(cells: [Table.Cell], header: Bool)] =
            [(Array(table.head.cells), true)] + table.body.rows.map { (Array($0.cells), false) }

        for (rowIndex, row) in rows.enumerated() {
            var column = 0
            for cell in row.cells where column < columns {
                let span = max(Int(cell.colspan), 1)
                let block = NSTextTableBlock(table: textTable, startingRow: rowIndex, rowSpan: 1,
                                             startingColumn: column, columnSpan: span)
                block.setWidth(1, type: .absoluteValueType, for: .border)
                block.setBorderColor(Palette.border)
                block.setWidth(size * 0.4, type: .absoluteValueType, for: .padding, edge: .minY)
                block.setWidth(size * 0.4, type: .absoluteValueType, for: .padding, edge: .maxY)
                block.setWidth(size * 0.8, type: .absoluteValueType, for: .padding, edge: .minX)
                block.setWidth(size * 0.8, type: .absoluteValueType, for: .padding, edge: .maxX)
                if row.header { block.backgroundColor = Palette.codeBackground }

                var inner = ctx
                inner.blocks.append(block)
                let style = paragraphStyle(ctx: inner)
                switch table.columnAlignments[safe: column] ?? nil {
                case .center?: style.alignment = .center
                case .right?: style.alignment = .right
                default: style.alignment = .natural
                }
                let text = NSMutableAttributedString(attributedString: inlines(cell.children, Style(bold: row.header, color: ctx.color)))
                text.append(NSAttributedString(string: "\n"))
                text.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: text.length))
                out.append(text)
                column += span
            }
        }
        spacer(ctx: ctx)
    }

    private func htmlBlock(_ html: String, ctx: Context) {
        let trimmed = html.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("<!--") { return }
        // README-style HTML is mostly images (logos, badges); keep those, drop the rest of the markup.
        let images = Self.htmlImages(trimmed)
        if !images.isEmpty {
            let line = NSMutableAttributedString()
            for (index, image) in images.enumerated() {
                if index > 0 { line.append(NSAttributedString(string: " ")) }
                line.append(imageText(image.src, alt: image.alt, width: image.width))
            }
            paragraph(line, ctx: ctx)
            return
        }
        let text = trimmed.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            paragraph(NSAttributedString(string: text, attributes: attributes(Style(color: ctx.color))), ctx: ctx)
        }
    }

    // MARK: - Paragraphs

    private func paragraphStyle(ctx: Context) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.textBlocks = ctx.blocks
        style.firstLineHeadIndent = ctx.indent
        style.headIndent = ctx.indent
        style.lineSpacing = size * 0.4
        return style
    }

    private func paragraph(_ text: NSAttributedString, ctx: Context, marker: NSAttributedString? = nil,
                           before: CGFloat = 0, after: CGFloat? = nil) {
        let style = paragraphStyle(ctx: ctx)
        style.paragraphSpacingBefore = before
        style.paragraphSpacing = after ?? (ctx.tight ? size * 0.3 : size * 0.9)
        let line = NSMutableAttributedString()
        if let marker {
            let markerWidth = size * (marker.string.hasSuffix(".\t") ? 2.3 : 1.6)
            style.firstLineHeadIndent = ctx.indent - markerWidth
            style.tabStops = [NSTextTab(textAlignment: .left, location: ctx.indent)]
            line.append(marker)
        }
        line.append(text)
        line.append(NSAttributedString(string: "\n"))
        line.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: line.length))
        out.append(line)
    }

    /// Lists and quotes add spacing after themselves; drop their last item's spacing to avoid doubling.
    private func trimTrailingSpacing() {
        guard out.length > 0,
              let style = out.attribute(.paragraphStyle, at: out.length - 1, effectiveRange: nil) as? NSParagraphStyle
        else { return }
        // `mutableString`, not `string`: the latter copies the whole document on every call.
        let paragraph = out.mutableString.paragraphRange(for: NSRange(location: out.length - 1, length: 0))
        let updated = style.mutableCopy() as! NSMutableParagraphStyle
        updated.paragraphSpacing = max(style.paragraphSpacing, size * 0.9)
        out.addAttribute(.paragraphStyle, value: updated, range: paragraph)
    }

    // MARK: - Inlines

    private func inlines(_ children: MarkupChildren, _ style: Style) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for child in children { inline(child, style, into: result) }
        return result
    }

    private func inline(_ markup: Markup, _ style: Style, into result: NSMutableAttributedString) {
        var style = style
        switch markup {
        case let text as Text:
            result.append(autolinked(text.string, style))
        case is SoftBreak:
            result.append(NSAttributedString(string: " ", attributes: attributes(style)))
        case is LineBreak:
            result.append(NSAttributedString(string: "\u{2028}", attributes: attributes(style)))
        case let code as InlineCode:
            style.code = true
            result.append(NSAttributedString(string: code.code, attributes: attributes(style)))
        case is Emphasis:
            style.italic = true
            for child in markup.children { inline(child, style, into: result) }
        case is Strong:
            style.bold = true
            for child in markup.children { inline(child, style, into: result) }
        case is Strikethrough:
            style.strike = true
            for child in markup.children { inline(child, style, into: result) }
        case let link as Link:
            style.link = link.destination.flatMap(resolve)
            for child in markup.children { inline(child, style, into: result) }
        case let image as Image:
            result.append(imageText(image.source, alt: image.plainText, width: nil))
        case let html as InlineHTML:
            if html.rawHTML.lowercased().hasPrefix("<br") {
                result.append(NSAttributedString(string: "\u{2028}", attributes: attributes(style)))
            } else if let image = Self.htmlImages(html.rawHTML).first {
                result.append(imageText(image.src, alt: image.alt, width: image.width))
            }
        default:
            if markup.childCount > 0 {
                for child in markup.children { inline(child, style, into: result) }
            } else {
                result.append(NSAttributedString(string: markup.format(), attributes: attributes(style)))
            }
        }
    }

    /// GitHub-style bare URL links (swift-markdown doesn't enable cmark's autolink extension).
    private func autolinked(_ string: String, _ style: Style) -> NSAttributedString {
        let text = NSMutableAttributedString(string: string, attributes: attributes(style))
        guard style.link == nil, !style.code, string.contains("://") || string.contains("www.") else { return text }
        for match in Self.linkDetector.matches(in: string, range: NSRange(location: 0, length: text.length)) {
            guard let url = match.url, url.scheme == "http" || url.scheme == "https" else { continue }
            var linked = style
            linked.link = url
            text.setAttributes(attributes(linked), range: match.range)
        }
        return text
    }

    private static let linkDetector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    private func attributes(_ style: Style) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font(style),
            .foregroundColor: style.color,
        ]
        if style.code { attributes[.backgroundColor] = Palette.inlineCodeBackground }
        if style.strike {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            attributes[.foregroundColor] = Palette.muted
        }
        if let link = style.link {
            attributes[.link] = link
            attributes[.toolTip] = link.isFileURL ? link.path : link.absoluteString
        }
        return attributes
    }

    private func font(_ style: Style) -> NSFont {
        let key = "\(style.bold)\(style.italic)\(style.code)\(style.scale)"
        if let cached = fontCache[key] { return cached }
        let pointSize = (size * style.scale * (style.code ? 0.9 : 1)).rounded(.toNearestOrEven)
        var font = style.code ? Fonts.code(size: pointSize) : Fonts.body(family, size: pointSize)
        font = Fonts.styled(font, bold: style.bold, italic: style.italic)
        fontCache[key] = font
        return font
    }

    // MARK: - Images

    private func imageText(_ source: String?, alt: String, width: CGFloat?) -> NSAttributedString {
        guard let source, let url = resolve(source) else {
            return NSAttributedString(string: alt, attributes: attributes(Style(color: Palette.muted)))
        }
        let cell = ImageCell(maxWidth: width)
        if let cached = ImageCell.cache.object(forKey: ImageCell.cacheKey(url)) {
            cell.image = cached
        } else if url.isFileURL {
            if let size = Self.imageSize(url) {
                // Reserve the space now; pixels are decoded off the main thread after the first frame.
                cell.reservedSize = size
                pendingImages.append((cell, url))
            } else if let image = NSImage(contentsOf: url) {
                cell.image = image // SVG, PDF and other formats ImageIO can't size
            } else {
                return NSAttributedString(string: alt, attributes: attributes(Style(color: Palette.muted)))
            }
        } else {
            pendingImages.append((cell, url))
        }
        let attachment = NSTextAttachment()
        attachment.attachmentCell = cell
        let text = NSMutableAttributedString(attachment: attachment)
        text.addAttribute(.toolTip, value: alt, range: NSRange(location: 0, length: text.length))
        return text
    }

    // MARK: - Helpers

    private func resolve(_ destination: String) -> URL? {
        if destination.hasPrefix("#") { return URL(string: destination) }
        if let url = URL(string: destination), url.scheme != nil { return url }
        let path = destination.removingPercentEncoding ?? destination
        if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
        guard let directory else { return nil }
        let parts = path.split(separator: "#", maxSplits: 1).map(String.init)
        guard let first = parts.first else { return nil }
        var url = directory.appendingPathComponent(first).standardizedFileURL
        if parts.count > 1, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.fragment = parts[1]
            url = components.url ?? url
        }
        return url
    }

    private func slug(_ text: String) -> String {
        let base = String(text.lowercased().unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || $0 == " " || $0 == "-" || $0 == "_"
        }).replacingOccurrences(of: " ", with: "-")
        var slug = base
        var counter = 1
        while anchors[slug] != nil {
            slug = "\(base)-\(counter)"
            counter += 1
        }
        return slug
    }

    private static func fullWidthBlock() -> NSTextBlock {
        let block = NSTextBlock()
        block.setValue(100, type: .percentageValueType, for: .width)
        return block
    }

    /// The image's size in points, from its header only (no pixel decoding).
    private static func imageSize(_ url: URL) -> NSSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat else { return nil }
        let dpi = (properties[kCGImagePropertyDPIWidth] as? CGFloat).flatMap { $0 > 0 ? $0 : nil } ?? 72
        return NSSize(width: width * 72 / dpi, height: height * 72 / dpi)
    }

    private static func soleImage(_ paragraph: Paragraph) -> Image? {
        guard paragraph.childCount == 1 else { return nil }
        return paragraph.child(at: 0) as? Image
    }

    static func splitFrontMatter(_ source: String) -> (String, String)? {
        guard source.hasPrefix("---\n") || source.hasPrefix("---\r\n") else { return nil }
        let lines = source.components(separatedBy: "\n")
        guard let end = lines.dropFirst().firstIndex(where: {
            let line = $0.trimmingCharacters(in: .whitespaces.union(.init(charactersIn: "\r")))
            return line == "---" || line == "..."
        }) else { return nil }
        return (lines[1..<end].joined(separator: "\n"), lines[(end + 1)...].joined(separator: "\n"))
    }

    private static let imgTag = try! NSRegularExpression(pattern: "<img\\b[^>]*>", options: .caseInsensitive)

    static func htmlImages(_ html: String) -> [(src: String, alt: String, width: CGFloat?)] {
        imgTag.matches(in: html, range: NSRange(html.startIndex..., in: html)).compactMap { match in
            let tag = String(html[Range(match.range, in: html)!])
            guard let src = attribute("src", in: tag) else { return nil }
            return (src, attribute("alt", in: tag) ?? "", attribute("width", in: tag).flatMap { Double($0) }.map { CGFloat($0) })
        }
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        let pattern = "\\b\(name)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)) else { return nil }
        for group in 1...3 {
            if let range = Range(match.range(at: group), in: tag) { return String(tag[range]) }
        }
        return nil
    }
}

/// Draws an image scaled down to fit the text column, or a one-line placeholder until it has one.
final class ImageCell: NSTextAttachmentCell {
    static let cache = NSCache<NSString, NSImage>()
    private let maxWidth: CGFloat?
    var placeholder: String?
    /// Layout size while the image is still loading.
    var reservedSize: NSSize?

    /// Local files are keyed by modification date too, so an edited image is picked up on reload.
    static func cacheKey(_ url: URL) -> NSString {
        guard url.isFileURL else { return url.absoluteString as NSString }
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        return "\(url.path)|\(modified?.timeIntervalSince1970 ?? 0)" as NSString
    }

    init(maxWidth: CGFloat?) {
        self.maxWidth = maxWidth
        super.init(imageCell: nil)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func cellFrame(for textContainer: NSTextContainer, proposedLineFragment lineFrag: NSRect,
                            glyphPosition position: NSPoint, characterIndex charIndex: Int) -> NSRect {
        let available = textContainer.size.width - 2 * textContainer.lineFragmentPadding - lineFrag.minX
        guard let size = image?.size ?? reservedSize, size.width > 0, size.height > 0 else {
            return placeholder == nil ? .zero : NSRect(x: 0, y: 0, width: max(available, 1), height: 28)
        }
        let width = min(size.width, maxWidth ?? .greatestFiniteMagnitude, max(available, 1))
        return NSRect(x: 0, y: 0, width: width, height: size.height * width / size.width)
    }

    override func cellSize() -> NSSize { image?.size ?? reservedSize ?? .zero }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        if image == nil, let placeholder {
            (placeholder as NSString).draw(at: NSPoint(x: cellFrame.minX, y: cellFrame.minY + 6), withAttributes: [
                .font: NSFont.systemFont(ofSize: 12), .foregroundColor: Palette.muted,
            ])
            return
        }
        image?.draw(in: cellFrame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    override func wantsToTrackMouse() -> Bool { false }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
