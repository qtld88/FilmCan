import Foundation

/// One source file the engine planned to copy, as it stood when the run enumerated it.
struct PlannedSourceFile: Hashable, Sendable {
    /// Absolute path, normalized (`URL(fileURLWithPath:).path`). The key the per-file
    /// proof in `DestResult.verifiedSourcePaths` uses.
    let sourcePath: String
    /// The source root the user picked (the card for a directory source).
    let rootPath: String
    /// Path relative to `rootPath` (the file name for a loose-file source).
    let relPath: String
    /// Byte count at enumeration time.
    let size: Int64
    /// Modification time at enumeration time, whole seconds since 1970.
    let modified: Int64
    /// False for a loose file picked on its own (no card to seal).
    let isDirectoryRoot: Bool

    static func proofKey(_ absolutePath: String) -> String {
        URL(fileURLWithPath: absolutePath).path
    }
}

/// What a run set out to copy. Carried to `TransferViewModel` so the card seal and the
/// catalog are based on the list the engine really copied and checked — never on a
/// second walk of the card after the copy.
struct RunPlan: Equatable, Sendable {
    var files: [PlannedSourceFile] = []
    /// Unreadable items the user chose to go on without. A run that ignored anything
    /// never proves the card is fully backed up.
    var ignoredUnreadable: [String] = []

    /// Planned files of one source root.
    func files(inRoot rootPath: String) -> [PlannedSourceFile] {
        files.filter { $0.rootPath == rootPath }
    }

    /// One plan out of the per-destination passes of a sequential run. A file is kept
    /// once (first pass wins); every destination must still prove all of them.
    static func merged(_ plans: [RunPlan]) -> RunPlan {
        var seen = Set<String>()
        var out = RunPlan()
        for plan in plans {
            for file in plan.files where seen.insert(file.sourcePath).inserted {
                out.files.append(file)
            }
            for path in plan.ignoredUnreadable where !out.ignoredUnreadable.contains(path) {
                out.ignoredUnreadable.append(path)
            }
        }
        return out
    }
}
