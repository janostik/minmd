# minmd

An extremely minimal Markdown **viewer** for macOS. No editor, no sidebar, no tabs — one file per window, rendered in [Solarized](https://ethanschoonover.com/solarized/) with [JetBrains Mono](https://www.jetbrains.com/lp/mono/), and the same rendering when you press <kbd>Space</kbd> in Finder.

<p>
  <img src="docs/screenshot-light.png" width="49%" alt="minmd, light">
  <img src="docs/screenshot-dark.png" width="49%" alt="minmd, dark">
</p>

## Features

- **Viewer only.** minmd never writes to your files.
- **One file, one window.** Opening another Markdown file opens another window.
- **Quick Look.** Select a `.md` file in Finder and press <kbd>Space</kbd>.
- **Live reload.** Edit the file in any editor and the window updates in place, keeping your scroll position.
- **GitHub-flavoured Markdown.** Tables, task lists, strikethrough, autolinks, front matter, syntax-highlighted code.
- **Two settings** (<kbd>⌘,</kbd>): theme (System / Light / Dark) and font. Quick Look uses the same settings.
- <kbd>⌘F</kbd> find, <kbd>⌘+</kbd> / <kbd>⌘-</kbd> / <kbd>⌘0</kbd> zoom. Links open in your browser; links to other Markdown files open in minmd.

## Install

Requires macOS 14+, Xcode, and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
git clone https://github.com/janostik/minmd.git
cd minmd
make install        # builds Release and copies minmd.app to /Applications
```

Then:

1. **Make it the default viewer:** in Finder, select any `.md` file → <kbd>⌘I</kbd> → *Open with* → **minmd** → **Change All…**
2. **Quick Look:** it registers automatically on install. If <kbd>Space</kbd> still shows plain text, enable *minmd Quick Look* in **System Settings → General → Login Items & Extensions → Quick Look**, then run `qlmanage -r`.

The build is ad-hoc signed (no Apple Developer account needed), so it is meant to be built locally.

## Development

```sh
make open    # generate minmd.xcodeproj and open it in Xcode
make build   # command-line Release build into ./build
```

The Xcode project is generated from `project.yml` and is not checked in.

```
App/          SwiftUI app: read-only DocumentGroup, settings, file watcher
QuickLook/    Quick Look preview extension
Shared/       Renderer + web view used by both; CSS, JS, fonts
```

Markdown is rendered by [marked](https://github.com/markedjs/marked) and [highlight.js](https://highlightjs.org) inside a `WKWebView`. Everything is inlined into the page, and a strict Content-Security-Policy stops scripts embedded in Markdown files from running.

## License

MIT. Bundled third-party components are listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
