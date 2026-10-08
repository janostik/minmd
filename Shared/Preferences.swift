import AppKit

/// The two user-facing settings (plus zoom), shared between the app and the Quick Look extension.
/// The extension reads the app's defaults domain via a read-only shared-preference entitlement.
enum Preferences {
    static let appDomain = "com.janostik.minmd"

    static let themeKey = "theme"
    static let fontKey = "fontFamily"
    static let zoomKey = "zoom"

    static let defaultFont = "JetBrains Mono"

    static var store: UserDefaults {
        if Bundle.main.bundleIdentifier == appDomain { return .standard }
        return UserDefaults(suiteName: appDomain) ?? .standard
    }

    static var theme: Theme {
        Theme(rawValue: store.string(forKey: themeKey) ?? "") ?? .system
    }

    static var fontFamily: String {
        store.string(forKey: fontKey) ?? defaultFont
    }

    static var zoom: Double {
        let value = store.double(forKey: zoomKey)
        return value > 0 ? value : 1
    }
}

enum Theme: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var appearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// GitHub's Primer palette. Every color is dynamic, so a theme switch needs no re-render.
enum Palette {
    static let background = color(0xFFFFFF, 0x0D1117)
    static let text = color(0x1F2328, 0xE6EDF3)
    static let muted = color(0x59636E, 0x9198A1)
    static let border = color(0xD1D9E0, 0x3D444D)
    static let codeBackground = color(0xF6F8FA, 0x151B23)
    static let inlineCodeBackground = color(0xEFF1F3, 0x232931)
    static let link = color(0x0969DA, 0x4493F8)

    enum Syntax {
        static let keyword = color(0xCF222E, 0xFF7B72)
        static let entity = color(0x6639BA, 0xD2A8FF)
        static let constant = color(0x0550AE, 0x79C0FF)
        static let string = color(0x0A3069, 0xA5D6FF)
        static let variable = color(0x953800, 0xFFA657)
        static let tag = color(0x116329, 0x7EE787)
        static let comment = color(0x59636E, 0x9198A1)
    }

    private static func color(_ light: UInt32, _ dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
    }
}

/// Font choices. Values starting with "." are system fonts; anything else is a font family name.
enum Fonts {
    static let builtIn: [(name: String, value: String)] = [
        ("JetBrains Mono", "JetBrains Mono"),
        ("SF Pro", ".system"),
        ("New York", ".serif"),
        ("SF Mono", ".mono"),
    ]

    /// Registers the bundled JetBrains Mono for this process (app or extension). Cheap and idempotent.
    static let registerBundled: Void = {
        let urls = ["Regular", "Italic", "Bold", "BoldItalic"].compactMap {
            Bundle.main.url(forResource: "JetBrainsMono-\($0)", withExtension: "ttf")
        }
        CTFontManagerRegisterFontURLs(urls as CFArray, .process, false, nil)
    }()

    static func body(_ family: String, size: CGFloat) -> NSFont {
        _ = registerBundled
        switch family {
        case ".system":
            return .systemFont(ofSize: size)
        case ".serif":
            let descriptor = NSFont.systemFont(ofSize: size).fontDescriptor.withDesign(.serif)
            return descriptor.flatMap { NSFont(descriptor: $0, size: size) } ?? .systemFont(ofSize: size)
        case ".mono":
            return .monospacedSystemFont(ofSize: size, weight: .regular)
        default:
            return regular(family, size: size) ?? code(size: size)
        }
    }

    static func code(size: CGFloat) -> NSFont {
        _ = registerBundled
        return regular("JetBrains Mono", size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    /// Thread-safe (unlike NSFontManager), so documents can be rendered off the main thread.
    static func styled(_ font: NSFont, bold: Bool, italic: Bool) -> NSFont {
        guard bold || italic else { return font }
        var traits = font.fontDescriptor.symbolicTraits
        if bold { traits.insert(.bold) }
        if italic { traits.insert(.italic) }
        return NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(traits), size: font.pointSize) ?? font
    }

    private static func regular(_ family: String, size: CGFloat) -> NSFont? {
        let descriptor = NSFontDescriptor(fontAttributes: [
            .family: family,
            .traits: [NSFontDescriptor.TraitKey.weight: NSFont.Weight.regular],
        ])
        guard let font = NSFont(descriptor: descriptor, size: size),
              font.familyName == family else { return nil }
        return font
    }

    /// Pays TextKit's and CoreText's one-time setup (~25 ms) on a background thread while AppKit
    /// is still finishing launch, instead of on the main thread when the first document arrives.
    static func warmUp(fontFamily: String) {
        DispatchQueue.global(qos: .userInteractive).async {
            let sample = "# A\n\n**b** *i* `c` [l](#a)\n\n> q\n\n- [x] t\n1. n\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\n```\nx\n```\n"
            let text = MarkdownRenderer(fontFamily: fontFamily, size: 14, directory: nil).render(sample).text
            let storage = NSTextStorage(attributedString: text)
            let layout = NSLayoutManager()
            storage.addLayoutManager(layout)
            let container = NSTextContainer(size: NSSize(width: 600, height: 10_000))
            layout.addTextContainer(container)
            layout.ensureLayout(for: container)
        }
    }
}
