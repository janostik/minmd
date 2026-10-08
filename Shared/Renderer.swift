import Foundation

/// Builds the self-contained HTML page. Markdown is parsed in the page by marked + highlight.js,
/// all of which are inlined so the page needs no file or network access to render.
enum Renderer {
    struct Options {
        var fontFamily: String = Preferences.defaultFont
        /// Extra top padding for windows whose content runs under a transparent title bar.
        var topInset: Int = 0
        /// In-page find bar (⌘F). Off in Quick Look, which has no keyboard focus anyway.
        var findBar: Bool = false
    }

    static func html(markdown: String, options: Options) -> String {
        let nonce = UUID().uuidString
        let payload = Payload(markdown: markdown, findBar: options.findBar)
        let json = (try? String(data: JSONEncoder().encode(payload), encoding: .utf8)) ?? "{}"

        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'nonce-\(nonce)'; style-src 'unsafe-inline'; img-src * data: file: blob:; media-src * file:; font-src data:">
        <style>
        \(Assets.fontFaces)
        \(Assets.css)
        :root { --font-body: \(FontChoice.cssStack(for: options.fontFamily)); --top-inset: \(options.topInset)px; }
        </style>
        </head>
        <body>
        <main id="content"></main>
        <script nonce="\(nonce)">\(Assets.marked)</script>
        <script nonce="\(nonce)">\(Assets.highlight)</script>
        <script nonce="\(nonce)">window.__MINMD__ = \(json);</script>
        <script nonce="\(nonce)">\(Assets.js)</script>
        </body>
        </html>
        """
    }

    /// Markdown files are almost always UTF-8; fall back gracefully for the odd legacy file.
    static func decode(_ data: Data) -> String {
        String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .windowsCP1252)
            ?? String(decoding: data, as: UTF8.self)
    }

    private struct Payload: Encodable {
        let markdown: String
        let findBar: Bool
    }

    private enum Assets {
        static let css = text("minmd", "css")
        static let js = text("minmd", "js")
        static let marked = text("marked.min", "js")
        static let highlight = text("highlight.min", "js")

        static let fontFaces: String = [
            ("Regular", "normal", 400),
            ("Italic", "italic", 400),
            ("Bold", "normal", 700),
            ("BoldItalic", "italic", 700),
        ].map { file, style, weight in
            guard let url = Bundle.main.url(forResource: "JetBrainsMono-\(file)", withExtension: "woff2"),
                  let data = try? Data(contentsOf: url) else { return "" }
            return """
            @font-face { font-family: "JetBrains Mono"; font-style: \(style); font-weight: \(weight); \
            src: url(data:font/woff2;base64,\(data.base64EncodedString())) format("woff2"); }
            """
        }.joined(separator: "\n")

        private static func text(_ name: String, _ ext: String) -> String {
            guard let url = Bundle.main.url(forResource: name, withExtension: ext),
                  let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
            return text
        }
    }
}
