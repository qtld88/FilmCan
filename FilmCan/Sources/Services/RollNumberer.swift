import Foundation

enum RollNumberer {
    static func cardKey(volumeUUID: String?, sourcePath: String, volumeRoot: String) -> String {
        var rel = sourcePath
        if sourcePath == volumeRoot {
            rel = ""
        } else {
            let prefix = volumeRoot.hasSuffix("/") ? volumeRoot : volumeRoot + "/"
            if sourcePath.hasPrefix(prefix) { rel = String(sourcePath.dropFirst(prefix.count)) }
        }
        return "\(volumeUUID ?? "nouuid")|\(rel)"
    }

    /// Card key for a real path: reads the volume UUID and volume root from disk.
    static func cardKey(forPath path: String) -> String {
        let volumeRoot = (try? URL(fileURLWithPath: path)
            .resourceValues(forKeys: [.volumeURLKey]))?.volume?.path ?? "/"
        return cardKey(volumeUUID: FanOutCopier.sourceVolumeUUID(path), sourcePath: path, volumeRoot: volumeRoot)
    }

    /// Pure. For each DIRECTORY source (sorted for determinism): reuse an existing assignment
    /// for its card key; else keep an ARRI/RED reel name; else take the next free number.
    static func assign(sources: [String], isDirectory: (String) -> Bool,
                       kinds: [String: SourceMediaKind], settings: RollNumbering,
                       existing: [String: String], keyFor: (String) -> String,
                       signatureFor: (String) -> CardSignature?)
        -> (names: [String: String], assignments: [String: String])
    {
        var assignments = existing
        var names: [String: String] = [:]
        for path in sources.sorted() where isDirectory(path) {
            let key = keyFor(path)
            if let known = assignments[key] {
                names[path] = known
                continue
            }
            let kind = kinds[path] ?? .camera
            if settings.keepCameraReelNames, kind == .camera,
               let reel = signatureFor(path)?.reelName, !reel.isEmpty {
                assignments[key] = reel
                names[path] = reel
                continue
            }
            let name = nextName(kind: kind, settings: settings, assigned: Array(assignments.values))
            assignments[key] = name
            names[path] = name
        }
        return (names, assignments)
    }

    static func nextName(kind: SourceMediaKind, settings: RollNumbering, assigned: [String]) -> String {
        let prefix = kind == .sound ? settings.soundPrefix : settings.cameraPrefix
        let start = kind == .sound ? settings.soundStart : settings.cameraStart
        let escaped = NSRegularExpression.escapedPattern(for: prefix)
        let regex = try? NSRegularExpression(pattern: "^\(escaped)(\\d+)$")
        var highest = 0
        for value in assigned {
            let range = NSRange(value.startIndex..., in: value)
            if let m = regex?.firstMatch(in: value, range: range),
               let r = Range(m.range(at: 1), in: value), let n = Int(value[r]) {
                highest = max(highest, n)
            }
        }
        let number = max(start, highest + 1)
        let s = String(number)
        let padded = String(repeating: "0", count: max(0, settings.digits - s.count)) + s
        return prefix + padded
    }
}

@MainActor
final class RollNumberingStore {
    static let shared = RollNumberingStore()

    struct ConfigState: Codable, Equatable {
        var assignments: [String: String] = [:]
        var currentDay: String?
        var lastRunDate: Date?
    }

    private let fileURL: URL
    private var states: [String: ConfigState] = [:]

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.fileURL = base.appendingPathComponent("FilmCan", isDirectory: true)
                .appendingPathComponent("roll-numbering.json")
        }
        load()
    }

    func state(for configId: UUID) -> ConfigState {
        states[configId.uuidString] ?? ConfigState()
    }

    func update(_ state: ConfigState, for configId: UUID) {
        states[configId.uuidString] = state
        save()
    }

    func resetNumbering(for configId: UUID) {
        var s = state(for: configId)
        s.assignments = [:]
        update(s, for: configId)
    }

    /// Every film's state, keyed by the film's id (for the Recognition page).
    var allStates: [String: ConfigState] { states }

    /// Forgets one card of one film: the card gets a new roll name the next time it
    /// is used with that film. The old name stays taken (kept under a key that is not
    /// a card), so it is never given to another card while a roll folder of that name
    /// may be on a drive. Nothing happens if the card no longer holds `rollName`.
    /// `configId` is the stored key, so a film that no longer exists can be cleaned too.
    func forgetAssignment(cardKey: String, rollName: String, configId: String) {
        guard !Self.isForgottenKey(cardKey),
              var state = states[configId], state.assignments[cardKey] == rollName else { return }
        state.assignments.removeValue(forKey: cardKey)
        state.assignments[Self.forgottenKeyPrefix + rollName] = rollName
        states[configId] = state
        save()
    }

    /// A card key starts with a volume id or "nouuid", never with this.
    static let forgottenKeyPrefix = "forgotten|"
    static func isForgottenKey(_ key: String) -> Bool { key.hasPrefix(forgottenKeyPrefix) }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        states = (try? decoder.decode([String: ConfigState].self, from: data)) ?? [:]
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(states) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}

/// Per-drive correction of the detector, keyed by volume UUID.
enum CardRoleOverrides {
    private static let defaultsKey = "filmcan.cardRoleOverrides"
    /// Drive name and date of each correction, for the Recognition page only: nothing
    /// in detection reads it. Corrections made before it existed have no entry.
    private static let detailsKey = "filmcan.cardRoleOverrideDetails"

    struct Detail: Equatable {
        var name: String?
        var date: Date?
    }

    static func role(forVolumeUUID uuid: String, defaults: UserDefaults = .standard) -> CardRole? {
        let dict = defaults.dictionary(forKey: defaultsKey) as? [String: String]
        return dict?[uuid].flatMap(CardRole.init(rawValue:))
    }

    /// `driveName` is remembered next to the correction so the drive can be named
    /// while it is not connected.
    static func set(_ role: CardRole?, forVolumeUUID uuid: String, driveName: String? = nil,
                    now: Date = Date(), defaults: UserDefaults = .standard) {
        var dict = (defaults.dictionary(forKey: defaultsKey) as? [String: String]) ?? [:]
        var details = (defaults.dictionary(forKey: detailsKey) as? [String: [String: Any]]) ?? [:]
        if let role {
            dict[uuid] = role.rawValue
            var entry: [String: Any] = ["date": now.timeIntervalSince1970]
            if let driveName, !driveName.isEmpty { entry["name"] = driveName }
            details[uuid] = entry
        } else {
            dict.removeValue(forKey: uuid)
            details.removeValue(forKey: uuid)
        }
        defaults.set(dict, forKey: defaultsKey)
        defaults.set(details, forKey: detailsKey)
    }

    /// Every remembered correction; a stored value this version does not know is left out.
    static func all(defaults: UserDefaults = .standard) -> [String: CardRole] {
        let dict = (defaults.dictionary(forKey: defaultsKey) as? [String: String]) ?? [:]
        return dict.compactMapValues(CardRole.init(rawValue:))
    }

    static func details(defaults: UserDefaults = .standard) -> [String: Detail] {
        let stored = (defaults.dictionary(forKey: detailsKey) as? [String: [String: Any]]) ?? [:]
        return stored.mapValues { entry in
            Detail(name: entry["name"] as? String,
                   date: (entry["date"] as? Double).map(Date.init(timeIntervalSince1970:)))
        }
    }
}
