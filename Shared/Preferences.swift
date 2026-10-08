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

/// Fonts offered before the list of installed families. Values starting with `ui-` / `-apple-`
/// are CSS generic families and are passed through unquoted.
enum FontChoice {
    static let builtIn: [(name: String, value: String)] = [
        ("JetBrains Mono", "JetBrains Mono"),
        ("SF Pro", "-apple-system"),
        ("New York", "ui-serif"),
        ("SF Mono", "ui-monospace"),
    ]

    static func cssStack(for family: String) -> String {
        let primary = family.hasPrefix("ui-") || family.hasPrefix("-apple-")
            ? family
            : "\"\(family.replacingOccurrences(of: "\"", with: ""))\""
        return "\(primary), \"JetBrains Mono\", ui-monospace, monospace"
    }
}

extension NSColor {
    /// Solarized base3 / base03 — the page background, used to avoid flashes before the page paints.
    static let solarizedBackground = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0x00 / 255, green: 0x2B / 255, blue: 0x36 / 255, alpha: 1)
            : NSColor(srgbRed: 0xFD / 255, green: 0xF6 / 255, blue: 0xE3 / 255, alpha: 1)
    }
}
