import Foundation

/// The folder layout of a film as a small tree, for the visual editor. It is another
/// view of the same two strings the engine reads (the camera and the sound folder
/// layout): it parses them and writes them back unchanged, or declares itself unable
/// to (`parse` returns nil) and the text field stays the only editor.
struct FolderStructure: Equatable {
    /// Folders from the drive down to where cards land. Empty: cards at the drive's top level.
    var camera: [String]
    /// Folders down to where sound lands. Nil: sound goes with the cards.
    var sound: [String]?

    init(camera: [String] = [], sound: [String]? = nil) {
        self.camera = camera
        self.sound = sound
        normalize()
    }

    // MARK: Text <-> tree

    /// Words the tree can show in clear, with the name it gives them.
    static let knownTokens: [(token: String, label: String)] = [
        ("{movie}", "Movie name"),
        ("{day}", "Shoot day"),
        ("{date}", "Date"),
        ("{episode}", "Project / episode"),
        ("{unit}", "Unit"),
        ("{cameraFormat}", "Camera format")
    ]

    /// Nil when the tree cannot show `camera` / `sound` and give them back unchanged:
    /// a name the tree does not know (`{source}`, `{counter}`, file dates…), an empty
    /// folder name, a backslash, or spaces around the text.
    static func parse(camera: String, sound: String) -> FolderStructure? {
        guard let cameraParts = segments(of: camera), let soundParts = segments(of: sound) else { return nil }
        // An empty sound layout means "with the cards"; a sound layout without a camera
        // layout cannot be shown as one tree.
        if cameraParts.isEmpty && !soundParts.isEmpty { return nil }
        let structure = FolderStructure(camera: cameraParts, sound: soundParts.isEmpty ? nil : soundParts)
        guard structure.cameraTemplate == camera, structure.soundTemplate == sound else { return nil }
        return structure
    }

    private static func segments(of template: String) -> [String]? {
        if template.isEmpty { return [] }
        guard template == template.trimmingCharacters(in: .whitespacesAndNewlines),
              !template.contains("\\") else { return nil }
        let parts = template.components(separatedBy: "/")
        guard parts.allSatisfy(isShowable) else { return nil }
        return parts
    }

    /// A folder name the tree can show: not empty, and every `{…}` in it is a known word.
    /// The folder must also be one a run writes exactly as shown: a name the run would
    /// alter (accents, "&", doubled or leading underscores, "." or "..") is not showable.
    static func isShowable(_ segment: String) -> Bool {
        guard !segment.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        // Each automatic word becomes a stand-in letter, in one pass: what is left of
        // a brace afterwards is not a known word.
        var rest = segment
        for known in knownTokens { rest = rest.replacingOccurrences(of: known.token, with: "\u{1}") }
        guard !rest.contains("{"), !rest.contains("}") else { return false }
        let plain = rest.replacingOccurrences(of: "\u{1}", with: "X")
        return OrganizationTemplate.folderNameAsWritten(plain) == plain
    }

    var cameraTemplate: String { camera.joined(separator: "/") }
    var soundTemplate: String { sound?.joined(separator: "/") ?? "" }

    // MARK: Rows

    struct Row: Identifiable, Equatable {
        enum Branch: Equatable { case shared, camera, sound }
        let branch: Branch
        /// Position of the folder in its path(s).
        let index: Int
        let depth: Int
        let segment: String
        /// Cards land directly in this folder.
        let holdsCards: Bool
        /// Sound lands directly in this folder.
        let holdsSound: Bool

        var id: String { "\(branch)-\(index)" }
        /// A folder whose name is plain text (can be renamed by typing).
        var isPlain: Bool { !segment.contains("{") }
        var label: String { FolderStructure.label(for: segment) }
    }

    /// "{date}_{day}" -> "‹Date›_‹Shoot day›"; a name that is one word alone -> "Shoot day".
    static func label(for segment: String) -> String {
        if let alone = knownTokens.first(where: { $0.token == segment }) { return alone.label }
        var out = segment
        for known in knownTokens { out = out.replacingOccurrences(of: known.token, with: "‹\(known.label)›") }
        return out
    }

    /// Folders shared by cards and sound.
    private var sharedCount: Int {
        guard let sound else { return camera.count }
        var count = 0
        while count < camera.count, count < sound.count, camera[count] == sound[count] { count += 1 }
        return count
    }

    var cardsAtTopLevel: Bool { camera.isEmpty }
    var soundAtTopLevel: Bool { camera.isEmpty && sound == nil }
    var soundIsSeparate: Bool { sound != nil }

    /// Top to bottom: shared folders, then the cards' own, then the sound's own.
    var rows: [Row] {
        let shared = sharedCount
        let soundPath = sound ?? camera
        var out: [Row] = []
        for index in 0..<shared {
            out.append(Row(branch: .shared, index: index, depth: index, segment: camera[index],
                           holdsCards: index == camera.count - 1,
                           holdsSound: index == soundPath.count - 1))
        }
        for index in shared..<camera.count {
            out.append(Row(branch: .camera, index: index, depth: index, segment: camera[index],
                           holdsCards: index == camera.count - 1, holdsSound: false))
        }
        if let sound {
            for index in shared..<sound.count {
                out.append(Row(branch: .sound, index: index, depth: index, segment: sound[index],
                               holdsCards: false, holdsSound: index == sound.count - 1))
            }
        }
        return out
    }

    // MARK: Editing

    /// A typed folder name made safe: no path separator, no braces, no leading dot or space.
    static func cleanName(_ name: String) -> String {
        var out = name.filter { !"/\\:{}".contains($0) }
        out = out.trimmingCharacters(in: .whitespacesAndNewlines)
        while out.hasPrefix(".") { out.removeFirst() }
        // Keep the name as a run would write it, so the tree never shows another folder.
        return OrganizationTemplate.folderNameAsWritten(out) ?? ""
    }

    private func touchesCamera(_ row: Row) -> Bool { row.branch != .sound }
    private func touchesSound(_ row: Row) -> Bool { sound != nil && row.branch != .camera }

    mutating func rename(_ row: Row, to name: String) {
        let clean = Self.cleanName(name)
        guard !clean.isEmpty, row.isPlain else { return }
        replace(row, with: clean)
    }

    private mutating func replace(_ row: Row, with segment: String) {
        if touchesCamera(row), camera.indices.contains(row.index) { camera[row.index] = segment }
        if touchesSound(row), sound?.indices.contains(row.index) == true { sound?[row.index] = segment }
        normalize()
    }

    /// Adds a folder inside `row` (nil: at the top level). `segment` is a plain name or
    /// one of `knownTokens`. Whatever landed in `row` now lands in the new folder.
    mutating func addFolder(_ segment: String, inside row: Row?) {
        let name = Self.knownTokens.contains { $0.token == segment } ? segment : Self.cleanName(segment)
        guard !name.isEmpty else { return }
        let position = (row?.index ?? -1) + 1
        let inCamera = row == nil || row?.branch != .sound
        let inSound = sound != nil && (row == nil || row?.branch != .camera)
        if inCamera, position <= camera.count { camera.insert(name, at: position) }
        if inSound, let count = sound?.count, position <= count { sound?.insert(name, at: position) }
        normalize()
    }

    mutating func remove(_ row: Row) {
        if touchesCamera(row), camera.indices.contains(row.index) { camera.remove(at: row.index) }
        if touchesSound(row), sound?.indices.contains(row.index) == true { sound?.remove(at: row.index) }
        normalize()
    }

    /// Can `row` trade places with the folder above (-1) or below (+1) it?
    func canMove(_ row: Row, by delta: Int) -> Bool {
        let other = row.index + delta
        guard delta == 1 || delta == -1, other >= 0 else { return false }
        switch row.branch {
        case .shared: return other < sharedCount
        case .camera: return other >= sharedCount && other < camera.count
        case .sound: return other >= sharedCount && other < (sound?.count ?? 0)
        }
    }

    mutating func move(_ row: Row, by delta: Int) {
        guard canMove(row, by: delta) else { return }
        let other = row.index + delta
        if touchesCamera(row) { camera.swapAt(row.index, other) }
        if touchesSound(row) { sound?.swapAt(row.index, other) }
        normalize()
    }

    /// Sound gets its own folder, next to where the cards land.
    mutating func separateSound(named name: String = "Sound") {
        guard sound == nil, !camera.isEmpty else { return }
        let clean = Self.cleanName(name)
        guard !clean.isEmpty else { return }
        var path = Array(camera.dropLast())
        path.append(clean == camera.last ? clean + " 2" : clean)
        sound = path
        normalize()
    }

    mutating func putSoundWithCards() {
        sound = nil
    }

    /// The text form has no way to say "sound at the top level while cards are in a
    /// folder", nor "sound in a folder while cards are at the top level": both fall
    /// back to "sound with the cards".
    private mutating func normalize() {
        if let sound, sound.isEmpty || camera.isEmpty || sound == camera { self.sound = nil }
    }

    // MARK: Starting points

    struct StartingPoint: Identifiable, Equatable {
        let id: String
        let title: String
        let detail: String
        let structure: FolderStructure
    }

    static let startingPoints: [StartingPoint] = [
        StartingPoint(id: "oneDay", title: "One day",
                      detail: "Movie › Camera and Sound",
                      structure: FolderStructure(camera: ["{movie}", "Camera"], sound: ["{movie}", "Sound"])),
        StartingPoint(id: "severalDays", title: "Several days",
                      detail: "Movie › Shoot day › Camera and Sound",
                      structure: FolderStructure(camera: ["{movie}", "{day}", "Camera"],
                                                 sound: ["{movie}", "{day}", "Sound"])),
        StartingPoint(id: "netflix", title: "Netflix Ingest",
                      detail: "Date_Episode_Day_Unit › Camera_Media, Sound_Media",
                      structure: FolderStructure(
                        camera: ["{date}_{episode}_{day}_{unit}", "Camera_Media", "{cameraFormat}"],
                        sound: ["{date}_{episode}_{day}_{unit}", "Sound_Media"])),
        StartingPoint(id: "free", title: "Free",
                      detail: "Start empty and add your folders",
                      structure: FolderStructure())
    ]
}

/// Which two strings hold a film's folder layout. For the Netflix preset the film's
/// own editable fields win over the preset's when they are filled (same rule as the
/// run: `TransferViewModel.resolveOrganizationPreset`).
enum FolderLayoutSource {
    /// What the visual editor shows for a film.
    enum TreeState: Equatable {
        case editable(FolderStructure)
        /// The layout is switched off but its text is kept: editing the tree would
        /// replace it, so the tree waits until the layout is switched on.
        case switchedOff
        /// The film is on "Off" and its own settings are kept aside: a tree edit would
        /// replace them.
        case setAside
        /// The text uses something the tree cannot show.
        case notShowable

        var structure: FolderStructure? {
            if case .editable(let structure) = self { return structure }
            return nil
        }

        /// The sentence shown in place of the tree.
        var explanation: String? {
            switch self {
            case .editable: return nil
            case .switchedOff: return "The folder layout is switched off. Switch it on to edit it here."
            case .setAside: return "This movie's own settings are set aside. Choose them again in the Preset menu to edit the folder layout here."
            case .notShowable: return "This layout uses names the visual editor cannot show. Edit it as text below."
            }
        }
    }

    static func treeState(useFolderTemplate: Bool, camera: String, sound: String,
                          hasSettingsSetAside: Bool) -> TreeState {
        if hasSettingsSetAside { return .setAside }
        guard useFolderTemplate else {
            let kept = !(camera + sound).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return kept ? .switchedOff : .editable(FolderStructure())
        }
        guard let structure = FolderStructure.parse(camera: camera, sound: sound) else { return .notShowable }
        return .editable(structure)
    }

    static func templates(preset: OrganizationPreset, isNetflix: Bool,
                          cameraOverride: String, soundOverride: String) -> (camera: String, sound: String) {
        var camera = preset.folderTemplate
        var sound = preset.soundFolderTemplate
        if isNetflix {
            if !cameraOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { camera = cameraOverride }
            if !soundOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { sound = soundOverride }
        }
        return (camera, sound)
    }
}
