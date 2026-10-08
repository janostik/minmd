import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let markdown = UTType(importedAs: "net.daringfireball.markdown")
}

/// A read-only Markdown document. minmd never writes files.
struct MarkdownDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.markdown]
    static let writableContentTypes: [UTType] = []

    let text: String

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = Renderer.decode(data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        throw CocoaError(.fileWriteNoPermission)
    }
}
