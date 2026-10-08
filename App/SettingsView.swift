import SwiftUI

struct SettingsView: View {
    @AppStorage(Preferences.themeKey) private var theme = Theme.system
    @AppStorage(Preferences.fontKey) private var fontFamily = Preferences.defaultFont

    private let installedFamilies = NSFontManager.shared.availableFontFamilies
        .filter { !$0.hasPrefix(".") }

    var body: some View {
        Form {
            Picker("Theme", selection: $theme) {
                ForEach(Theme.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            Picker("Font", selection: $fontFamily) {
                ForEach(FontChoice.builtIn, id: \.value) { Text($0.name).tag($0.value) }
                Divider()
                ForEach(installedFamilies, id: \.self) { Text($0).tag($0) }
                if !isKnown(fontFamily) {
                    Text(fontFamily).tag(fontFamily)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize()
        .onChange(of: theme, initial: true) { _, theme in
            NSApp.appearance = theme.appearance
        }
    }

    private func isKnown(_ family: String) -> Bool {
        FontChoice.builtIn.contains { $0.value == family } || installedFamilies.contains(family)
    }
}
