import Foundation

struct DuplicatePrompt: Identifiable {
    let id = UUID()
    let sourcePath: String
    let destinationPath: String
    let isDirectory: Bool
    let counterTemplate: String
    let canVerifyWithHashList: Bool
    let hashListMissing: Bool
    /// How many files are in conflict in this run, and their destination paths, so
    /// the user sees the whole list before choosing.
    var conflictCount: Int = 1
    var conflictNames: [String] = []
    /// Index of the file this prompt asks about, in `conflictNames`.
    var position: Int = 0

    var sourceName: String {
        (sourcePath as NSString).lastPathComponent
    }

    var destinationName: String {
        (destinationPath as NSString).lastPathComponent
    }
}

struct DuplicateResolution {
    let action: OrganizationPreset.DuplicatePolicy
    let applyToAll: Bool
    let counterTemplate: String?
}
