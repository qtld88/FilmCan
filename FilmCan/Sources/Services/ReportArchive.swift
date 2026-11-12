import Foundation

/// Keeps a copy of every backup report on this Mac, so it can be read with the
/// drives unplugged: `<base>/<film>/<day>/<drive>/` holding the PDF and the
/// checksum list of each roll. Local file copies only; no network.
///
/// App-wide preference, on by default. It only acts when a film writes a PDF report.
enum ReportArchive {
    enum DefaultsKey {
        static let enabled = "reportArchiveEnabled"
        /// Empty or absent = `defaultBaseURL()`.
        static let folder = "reportArchiveFolder"
    }

    static let defaultFolderName = "FilmCan Reports"

    // MARK: - Preferences

    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: DefaultsKey.enabled) as? Bool ?? true
    }

    static func defaultBaseURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Documents").appendingPathComponent(defaultFolderName)
    }

    static func baseURL(defaults: UserDefaults = .standard,
                        home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        let custom = (defaults.string(forKey: DefaultsKey.folder) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return custom.isEmpty ? defaultBaseURL(home: home) : URL(fileURLWithPath: custom)
    }

    // MARK: - Layout (pure)

    /// A single folder name: no path separators, no leading dot, never empty.
    static func safeName(_ raw: String, fallback: String) -> String {
        var name = raw
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while name.hasPrefix(".") { name.removeFirst() }
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? fallback : name
    }

    /// The film's shoot day when it has one, else the run's calendar date (`2026-11-11`).
    static func dayFolderName(day: String, date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let dated = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        return safeName(day, fallback: dated)
    }

    static func folder(base: URL, film: String, day: String, date: Date, drive: String,
                       calendar: Calendar = .current) -> URL {
        base.appendingPathComponent(safeName(film, fallback: "Untitled"))
            .appendingPathComponent(dayFolderName(day: day, date: date, calendar: calendar))
            .appendingPathComponent(safeName(drive, fallback: "Drive"))
    }

    /// Checksum-list copies are prefixed with the roll, unless the name already carries it.
    static func hashListFileName(roll: String, original: String) -> String {
        let safeRoll = safeName(roll, fallback: "roll")
        return original.contains(safeRoll) ? original : "\(safeRoll)_\(original)"
    }

    // MARK: - What to copy

    /// The checksum list of each roll this destination result wrote: the latest ASC MHL
    /// generation on disk, else the simple hidden list. Sorted by roll name.
    /// `style` is the film's current style: it decides which list is looked for first, so an
    /// old list of the other style left in the roll is not picked over the current one.
    static func hashLists(for result: TransferResult,
                          style: HashListStyle = .ascMHL) -> [(roll: String, url: URL)] {
        guard let dest = result.destinationResults.first else { return [] }
        var out: [(roll: String, url: URL)] = []
        for (rootPath, rollFolder) in dest.rollFolders {
            let roll = (rootPath as NSString).lastPathComponent
            let ascDir = FanOutCopier.ascMHLDir(rollFolder: rollFolder)
            let asc = ASCMHLChain.latestManifestFileName(ascmhlDir: ascDir)
                .map { ascDir.appendingPathComponent($0) }
            let simpleURL = URL(fileURLWithPath: dest.destinationPath)
                .appendingPathComponent(".filmcan").appendingPathComponent("hashlists")
                .appendingPathComponent("\(roll).mhl")
            let simple = FileManager.default.fileExists(atPath: simpleURL.path) ? simpleURL : nil
            if let url = (style == .ascMHL ? (asc ?? simple) : (simple ?? asc)) {
                out.append((roll, url))
            }
        }
        return out.sorted { $0.roll < $1.roll }
    }

    static func driveName(for result: TransferResult) -> String {
        let path = result.destinationResults.first?.destinationPath ?? result.destination
        let volume = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.volumeNameKey]).volumeName
        if let volume, !volume.isEmpty, FileManager.default.fileExists(atPath: path) { return volume }
        return (path as NSString).lastPathComponent
    }

    // MARK: - Copy

    /// Copies the PDF and the checksum lists into `folder`, replacing same-named files.
    /// Never throws: a file that cannot be copied is skipped and logged. Returns what was written.
    @discardableResult
    static func copy(pdfPath: String?, hashLists: [(roll: String, url: URL)], into folder: URL,
                     fileManager fm: FileManager = .default) -> [URL] {
        var items: [(source: URL, name: String)] = []
        if let pdfPath, fm.fileExists(atPath: pdfPath) {
            let url = URL(fileURLWithPath: pdfPath)
            items.append((url, url.lastPathComponent))
        }
        for list in hashLists where fm.fileExists(atPath: list.url.path) {
            items.append((list.url, hashListFileName(roll: list.roll, original: list.url.lastPathComponent)))
        }
        guard !items.isEmpty else { return [] }
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            DebugLog.warn("Report copy: cannot create \(folder.path): \(error.localizedDescription)")
            return []
        }
        var written: [URL] = []
        for item in items {
            let target = folder.appendingPathComponent(item.name)
            let temp = folder.appendingPathComponent(".\(item.name).\(UUID().uuidString).tmp")
            do {
                try fm.copyItem(at: item.source, to: temp)
                if fm.fileExists(atPath: target.path) {
                    _ = try fm.replaceItemAt(target, withItemAt: temp)
                } else {
                    try fm.moveItem(at: temp, to: target)
                }
                written.append(target)
            } catch {
                try? fm.removeItem(at: temp)
                DebugLog.warn("Report copy: \(item.name) not copied: \(error.localizedDescription)")
            }
        }
        return written
    }

    /// Called after a report was written for one destination result.
    @discardableResult
    static func archive(pdfPath: String?, result: TransferResult, config: BackupConfiguration,
                        defaults: UserDefaults = .standard) -> [URL] {
        guard isEnabled(defaults: defaults) else { return [] }
        let target = folder(
            base: baseURL(defaults: defaults), film: config.name, day: config.day,
            date: result.startTime, drive: driveName(for: result))
        return copy(pdfPath: pdfPath, hashLists: hashLists(for: result, style: config.hashListStyle), into: target)
    }
}
