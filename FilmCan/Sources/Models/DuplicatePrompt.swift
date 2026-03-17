import Foundation

struct DuplicatePrompt: Identifiable {
    let id = UUID()
    let sourcePath: String
    let destinationPath: String
    let isDirectory: Bool
    let counterTemplate: String
    let canVerifyWithHashList: Bool
    let hashListMissing: Bool

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
