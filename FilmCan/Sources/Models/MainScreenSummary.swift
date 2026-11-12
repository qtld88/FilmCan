import Foundation

/// Logic behind the calmer main screen: the shoot-day stepper in the film header, the
/// one-line summary above the two columns, and the sentence under the Run button.
/// Pure functions; the views only lay the results out.

enum ShootDayStepper {
    /// Moves the trailing number of `day` by `delta`, keeping its prefix and width
    /// ("Day02" → "Day03", "D9" → "D10", "Day100" → "Day099"). Never goes below 1.
    /// Empty day: stepping forward gives "Day01" (same first value as the day counter).
    /// A day without a trailing number is returned unchanged.
    static func step(_ day: String, by delta: Int) -> String {
        let trimmed = day.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return delta > 0 ? "Day01" : day }
        let digits = String(trimmed.reversed().prefix { $0.isASCII && $0.isNumber }.reversed())
        guard !digits.isEmpty, let value = Int(digits) else { return day }
        let prefix = String(trimmed.dropLast(digits.count))
        let (sum, overflow) = value.addingReportingOverflow(delta)
        guard !overflow else { return day }
        let next = String(max(1, sum))
        let padded = String(repeating: "0", count: max(0, digits.count - next.count)) + next
        return prefix + padded
    }

    /// False when stepping back would change nothing (day 1, no number, empty).
    static func canStepBack(_ day: String) -> Bool { step(day, by: -1) != day }

    /// False for a day the stepper cannot move forward (text without a trailing number).
    static func canStepForward(_ day: String) -> Bool { step(day, by: 1) != day }

    /// The header only shows the day when the film's folders or file names use it.
    static func usesShootDay(_ preset: OrganizationPreset?) -> Bool {
        guard let preset else { return false }
        let token = "{day}"
        if preset.useFolderTemplate,
           preset.folderTemplate.contains(token) || preset.soundFolderTemplate.contains(token) {
            return true
        }
        return preset.useRenameTemplate && preset.renameTemplate.contains(token)
    }
}

/// "CITIZENK › Day02 › A003 — 128 GB · 412 items · 2 drives".
struct BackupSummary: Equatable {
    /// Destination folders from the drive root down to the roll (or "3 items").
    var breadcrumb: [String]
    var detail: String

    /// `relativePaths`: where each included source lands under a drive
    /// (`FolderTreeBuilder.relativePaths`). Nil when there is nothing to copy.
    static func make(relativePaths: [String], totalBytes: Int64, itemCount: Int?,
                     driveCount: Int, isLoading: Bool) -> BackupSummary? {
        let paths = relativePaths.map { $0.split(separator: "/").map(String.init) }.filter { !$0.isEmpty }
        guard !paths.isEmpty else { return nil }

        var breadcrumb: [String]
        if paths.count == 1 {
            breadcrumb = paths[0]
        } else {
            var common: [String] = []
            let shortest = paths.map(\.count).min() ?? 0
            for index in 0..<shortest {
                let component = paths[0][index]
                // The last component of a path is the copied item itself, never a shared folder.
                guard paths.allSatisfy({ $0[index] == component && index < $0.count - 1 }) else { break }
                common.append(component)
            }
            breadcrumb = common + ["\(paths.count) items"]
        }

        var parts: [String] = []
        if isLoading {
            parts.append("Measuring…")
        } else {
            parts.append(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))
            if let itemCount {
                parts.append(itemCount == 1 ? "1 file" : "\(itemCount) files")
            }
        }
        if driveCount > 0 {
            parts.append(driveCount == 1 ? "1 drive" : "\(driveCount) drives")
        }
        return BackupSummary(breadcrumb: breadcrumb, detail: parts.joined(separator: " · "))
    }
}

enum RunSubtitle {
    /// One short sentence saying what pressing Run will do, or what is missing.
    static func text(sourceCount: Int, driveCount: Int, newFolderCount: Int, isRunning: Bool) -> String {
        if isRunning { return "Backup in progress" }
        if sourceCount == 0 { return "Add a card or a folder to copy" }
        if driveCount == 0 { return "Add a drive to save to" }
        if newFolderCount == 1 { return "1 folder will be created" }
        if newFolderCount > 1 { return "\(newFolderCount) folders will be created" }
        return "Folders already exist: only missing files are copied"
    }

    /// Folders that do not exist yet, among the lines of one drive's preview.
    static func newFolderCount(in lines: [FolderTreeLine]) -> Int {
        lines.filter { $0.isNew && ($0.role == .folder || $0.role == .copiedFolder) && !$0.name.isEmpty }.count
    }
}

enum MainScreenChrome {
    /// A whole drive (`/Volumes/NAME`) already shows its name: its path line adds nothing
    /// and moves to the tooltip. A folder inside a drive, or on the Mac, keeps its path.
    static func showsPathLine(for path: String) -> Bool {
        let components = (path as NSString).standardizingPath.split(separator: "/")
        return !(components.count == 2 && components[0] == "Volumes")
    }

    /// Order numbers only help when there are several rows to tell apart.
    static func displayNumbers<ID: Hashable>(for ids: [ID], isIncluded: (ID) -> Bool) -> [ID: Int] {
        guard ids.count > 1 else { return [:] }
        return DriveIncludeColumn.numbers(for: ids, isIncluded: isIncluded)
    }

    /// The folder preview stays open only when it has something new to show.
    static func treeStartsCollapsed(_ lines: [FolderTreeLine]) -> Bool {
        !lines.isEmpty && !lines.contains { $0.isNew }
    }
}

/// Holds the summary line resolved before a run. A class on purpose: the view writes it
/// while rendering, which must not trigger another render.
final class SummaryFreeze {
    var summary: BackupSummary?
}
