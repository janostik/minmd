import AppKit

/// The only two settings: theme and font. Plain AppKit, so the app never loads SwiftUI.
final class SettingsWindowController: NSWindowController {
    private let theme = NSSegmentedControl(labels: Theme.allCases.map(\.title), trackingMode: .selectOne,
                                           target: nil, action: nil)
    private let font = NSPopUpButton()

    init() {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: true)
        window.title = "Settings"
        super.init(window: window)

        theme.target = self
        theme.action = #selector(themeChanged)
        font.target = self
        font.action = #selector(fontChanged)

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Theme:"), theme],
            [NSTextField(labelWithString: "Font:"), font],
        ])
        grid.rowSpacing = 14
        grid.columnSpacing = 10
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        grid.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            grid.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -24),
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 32),
            grid.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -32),
            font.widthAnchor.constraint(equalToConstant: 240),
        ])
        window.contentView = content
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func showWindow(_ sender: Any?) {
        reload()
        super.showWindow(sender)
    }

    private func reload() {
        theme.selectedSegment = Theme.allCases.firstIndex(of: Preferences.theme) ?? 0

        font.removeAllItems()
        for choice in Fonts.builtIn {
            font.addItem(withTitle: choice.name)
            font.lastItem?.representedObject = choice.value
        }
        font.menu?.addItem(.separator())
        for family in NSFontManager.shared.availableFontFamilies where !family.hasPrefix(".") {
            font.addItem(withTitle: family)
            font.lastItem?.representedObject = family
        }
        let current = Preferences.fontFamily
        if let item = font.itemArray.first(where: { $0.representedObject as? String == current }) {
            font.select(item)
        } else {
            font.selectItem(at: 0)
        }
    }

    @objc private func themeChanged() {
        Preferences.store.set(Theme.allCases[theme.selectedSegment].rawValue, forKey: Preferences.themeKey)
    }

    @objc private func fontChanged() {
        guard let value = font.selectedItem?.representedObject as? String else { return }
        Preferences.store.set(value, forKey: Preferences.fontKey)
    }
}
