import AppKit

/// `NSServices` handler for the Finder right-click → Services → "FilmCan Copy".
/// The selector name must match `NSMessage` (= `quickCopy`) in Info.plist.
@MainActor
final class QuickCopyServiceProvider: NSObject {
    static let shared = QuickCopyServiceProvider()

    static func paths(from pasteboard: NSPasteboard) -> [String] {
        let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.map(\.path)
    }

    @objc func quickCopy(_ pasteboard: NSPasteboard,
                         userData: String,
                         error: AutoreleasingUnsafeMutablePointer<NSString>) {
        let paths = Self.paths(from: pasteboard)
        guard !paths.isEmpty else {
            error.pointee = "FilmCan Copy: no files were selected." as NSString
            return
        }
        QuickCopyCoordinator.shared.open(paths: paths)
    }
}
