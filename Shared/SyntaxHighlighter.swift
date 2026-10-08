import AppKit
import JavaScriptCore

/// Runs highlight.js inside JavaScriptCore (in-process, no web view) on a background queue and
/// returns color runs to apply to already-displayed code blocks.
final class SyntaxHighlighter {
    static let shared = SyntaxHighlighter()

    struct Run {
        let range: NSRange
        let color: NSColor
    }

    private let queue = DispatchQueue(label: "minmd.highlight", qos: .userInitiated)
    private var highlight: JSValue?

    /// Starts loading highlight.js so the first document doesn't pay for it.
    func warmUp() {
        queue.async { _ = self.highlightFunction() }
    }

    /// Calls `completion` on the main queue with color runs per block, relative to each block's code.
    func highlight(_ blocks: [(code: String, language: String)], completion: @escaping ([[Run]]) -> Void) {
        queue.async {
            let runs = blocks.map { self.runs(code: $0.code, language: $0.language) }
            DispatchQueue.main.async { completion(runs) }
        }
    }

    private func highlightFunction() -> JSValue? {
        if let highlight { return highlight }
        guard let context = JSContext() else { return nil }
        context.evaluateScript("var console = { log() {}, warn() {}, error() {} };")
        for name in ["highlight.min", "highlight-languages.min"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "js"),
                  let script = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            context.evaluateScript(script)
        }
        highlight = context.evaluateScript("""
            (function (code, language) {
              if (!hljs.getLanguage(language)) return null;
              return hljs.highlight(code, { language, ignoreIllegals: true }).value;
            })
            """)
        return highlight
    }

    private func runs(code: String, language: String) -> [Run] {
        guard let html = highlightFunction()?.call(withArguments: [code, language.lowercased()]),
              html.isString, let markup = html.toString() else { return [] }
        return Self.parse(markup)
    }

    /// Walks highlight.js output (`<span class="hljs-…">` + HTML entities) and maps scopes to colors.
    static func parse(_ html: String) -> [Run] {
        var runs: [Run] = []
        var scopes: [String] = []
        var offset = 0
        var index = html.startIndex

        func emit(_ length: Int) {
            if let color = scopes.last.flatMap(color(for:)) {
                runs.append(Run(range: NSRange(location: offset, length: length), color: color))
            }
            offset += length
        }

        while index < html.endIndex {
            if html[index...].hasPrefix("<span class=\"") {
                let start = html.index(index, offsetBy: 13)
                let end = html[start...].firstIndex(of: "\"") ?? html.endIndex
                scopes.append(String(html[start..<end]))
                index = html[end...].firstIndex(of: ">").map { html.index(after: $0) } ?? html.endIndex
            } else if html[index...].hasPrefix("</span>") {
                _ = scopes.popLast()
                index = html.index(index, offsetBy: 7)
            } else if html[index] == "&", let semicolon = html[index...].prefix(8).firstIndex(of: ";") {
                emit(1)
                index = html.index(after: semicolon)
            } else {
                let next = html[index...].firstIndex(where: { $0 == "<" || $0 == "&" }) ?? html.endIndex
                emit(html[index..<next].utf16.count)
                index = next
            }
        }
        return runs
    }

    private static func color(for scope: String) -> NSColor? {
        let classes = scope.split(separator: " ").map { $0.replacingOccurrences(of: "hljs-", with: "") }
        guard let name = classes.first else { return nil }
        switch name {
        case "keyword", "doctag", "template-tag", "template-variable", "type", "deletion":
            return Palette.Syntax.keyword
        case "title":
            return Palette.Syntax.entity
        case "attr", "attribute", "literal", "meta", "number", "operator", "selector-attr",
             "selector-class", "selector-id", "variable", "section":
            return classes.contains("language_") ? Palette.Syntax.keyword : Palette.Syntax.constant
        case "string", "regexp":
            return Palette.Syntax.string
        case "built_in", "symbol", "bullet":
            return Palette.Syntax.variable
        case "comment", "code", "formula", "quote":
            return Palette.Syntax.comment
        case "name", "selector-tag", "selector-pseudo", "addition":
            return Palette.Syntax.tag
        default:
            return nil
        }
    }
}
