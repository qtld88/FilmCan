import SwiftUI
import UniformTypeIdentifiers

/// A JSON file handed to `fileExporter` (history export, movie settings export).
struct JSONExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

extension MovieSettingsFile {
    /// `.filmcan-movie`: JSON under another extension.
    static var contentType: UTType {
        UTType(filenameExtension: fileExtension, conformingTo: .json) ?? .json
    }

    /// What the open panel accepts when starting a movie from a settings file.
    static var importContentTypes: [UTType] { [contentType, .json] }
}
