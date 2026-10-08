import SwiftUI

@main
struct MinMDApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        DocumentGroup(viewing: MarkdownDocument.self) { file in
            DocumentView(text: file.document.text, fileURL: file.fileURL)
        }
        .defaultSize(width: 860, height: 960)
        .commands {
            CommandGroup(before: .toolbar) {
                ZoomCommands()
                Divider()
            }
        }

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // One file per window — never merge documents into tabs.
        NSWindow.allowsAutomaticWindowTabbing = false
        NSApp.appearance = Preferences.theme.appearance
    }
}

private struct ZoomCommands: View {
    @AppStorage(Preferences.zoomKey) private var zoom = 1.0

    var body: some View {
        Button("Actual Size") { zoom = 1 }
            .keyboardShortcut("0")
        Button("Zoom In") { zoom = min(zoom + 0.1, 3) }
            .keyboardShortcut("+")
        Button("Zoom Out") { zoom = max(zoom - 0.1, 0.5) }
            .keyboardShortcut("-")
    }
}
