import Foundation

enum CameraBrand: String, Codable, CaseIterable {
    case arri, red, sony, canon, panasonic, blackmagic, dji, gopro
    case insta360, avchd
    /// Any other card laid out the standard `DCIM/` way (photo cameras, drones, phones).
    case genericDCIM
    case soundRecorder

    var displayName: String {
        switch self {
        case .arri: return "ARRI"
        case .red: return "RED"
        case .sony: return "Sony"
        case .canon: return "Canon"
        case .panasonic: return "Panasonic"
        case .blackmagic: return "Blackmagic"
        case .dji: return "DJI"
        case .gopro: return "GoPro"
        case .insta360: return "Insta360"
        case .avchd: return "AVCHD"
        case .genericDCIM: return "Camera"
        case .soundRecorder: return "Sound recorder"
        }
    }

    var isSound: Bool { self == .soundRecorder }

    /// One plain sentence: what on the card makes FilmCan recognise this family.
    var recognisedBy: String {
        switch self {
        case .arri: return "ARRIRAW or ARRI-named MXF clips"
        case .red: return "an .RDM reel folder"
        case .sony: return "the M4ROOT or XDROOT folder"
        case .canon: return "CONTENTS/CLIPS folders, or a CANON folder in DCIM"
        case .panasonic: return "the PANA_GRP folder, a _PANA folder in DCIM, or a P2 CONTENTS folder"
        case .blackmagic: return "Blackmagic RAW clips"
        case .dji: return "DJI folders or DJI-named files in DCIM"
        case .gopro: return "a GOPRO folder in DCIM"
        case .insta360: return "Insta360 clips (.insv) or a Camera01 folder in DCIM"
        case .avchd: return "the AVCHD folder written by many camcorders"
        case .genericDCIM: return "a DCIM folder that holds at least one video file"
        case .soundRecorder: return "WAV files and no video"
        }
    }
}

struct CardSignature: Equatable {
    var brand: CameraBrand
    var reelName: String?
}

enum CameraCardDetector {
    private static let maxDepth = 3
    private static let maxEntries = 2000
    private static let videoExtensions: Set<String> = ["mov", "mp4", "mxf", "braw", "r3d", "crm", "ari", "mts"]
    /// Video files that make a plain `DCIM/` volume a camera card. Wider than
    /// `videoExtensions` (which decides "sound only"), so that rule is untouched.
    private static let dcimVideoExtensions: Set<String> = videoExtensions.union(["m4v", "avi", "3gp", "m2ts", "insv", "lrv", "360"])
    private static let maxDCIMFolders = 64

    private struct Entry {
        let name: String
        let relPath: String
        let depth: Int
        let isDirectory: Bool
    }

    /// Scans at most depth 3 and 2 000 entries, skipping hidden names. First match wins.
    static func detect(rootPath: String) -> CardSignature? {
        let entries = scan(rootPath: rootPath)
        let fm = FileManager.default
        let rootName = URL(fileURLWithPath: rootPath).lastPathComponent

        // 1. RED
        if let rdm = entries.first(where: { $0.isDirectory && $0.depth <= 2 && $0.name.lowercased().hasSuffix(".rdm") }) {
            let reel = (rdm.name as NSString).deletingPathExtension
            return CardSignature(brand: .red, reelName: reel.isEmpty ? nil : reel)
        }

        // 2. ARRI
        let arriClip = entries.first(where: { e in
            guard !e.isDirectory, e.depth <= 3 else { return false }
            let lower = e.name.lowercased()
            if lower.hasSuffix(".ari") { return true }
            if lower.hasSuffix(".mxf") {
                return e.name.range(of: #"^[A-Z]\d{3}C\d{3}_"#, options: .regularExpression) != nil
            }
            return false
        })
        if let clip = arriClip {
            if rootName.range(of: #"^[A-Z]\d{3}[A-Z0-9_]*$"#, options: .regularExpression) != nil {
                return CardSignature(brand: .arri, reelName: rootName)
            }
            if clip.name.range(of: #"^[A-Z]\d{3}"#, options: .regularExpression) != nil {
                return CardSignature(brand: .arri, reelName: String(clip.name.prefix(4)))
            }
            return CardSignature(brand: .arri, reelName: nil)
        }

        func exists(_ rel: String) -> Bool {
            var isDir: ObjCBool = false
            return fm.fileExists(atPath: (rootPath as NSString).appendingPathComponent(rel), isDirectory: &isDir) && isDir.boolValue
        }
        func dcimChildren() -> [String] {
            ((try? fm.contentsOfDirectory(atPath: (rootPath as NSString).appendingPathComponent("DCIM"))) ?? [])
                .filter { !$0.hasPrefix(".") }
        }

        // 3. Sony
        if exists("PRIVATE/M4ROOT") || exists("XDROOT") || exists("PRIVATE/XDROOT") {
            return CardSignature(brand: .sony, reelName: nil)
        }

        // 4. Canon
        if let contents = try? fm.contentsOfDirectory(atPath: (rootPath as NSString).appendingPathComponent("CONTENTS")),
           contents.contains(where: { $0.uppercased().hasPrefix("CLIPS") }) {
            return CardSignature(brand: .canon, reelName: nil)
        }
        let dcim = dcimChildren()
        if dcim.contains(where: { $0.uppercased().contains("CANON") }) {
            return CardSignature(brand: .canon, reelName: nil)
        }

        // 5. Panasonic (own folders, or a P2 card: CONTENTS/ with CLIP + VIDEO)
        if exists("PRIVATE/PANA_GRP") || dcim.contains(where: { $0.uppercased().hasSuffix("_PANA") })
            || (exists("CONTENTS/CLIP") && exists("CONTENTS/VIDEO")) {
            return CardSignature(brand: .panasonic, reelName: nil)
        }
        // AVCHD without a Panasonic marker. Kept at this position (it used to be part of
        // the Panasonic rule) so it still wins over the families tested below.
        if exists("PRIVATE/AVCHD") {
            return CardSignature(brand: .avchd, reelName: nil)
        }

        // 6. Blackmagic
        if entries.contains(where: { !$0.isDirectory && $0.depth <= 2 && $0.name.lowercased().hasSuffix(".braw") }) {
            return CardSignature(brand: .blackmagic, reelName: nil)
        }

        // 7. GoPro
        if dcim.contains(where: { $0.uppercased().hasSuffix("GOPRO") }) {
            return CardSignature(brand: .gopro, reelName: nil)
        }

        // 8. DJI
        if dcim.contains(where: { $0.uppercased().hasPrefix("DJI_") }) {
            return CardSignature(brand: .dji, reelName: nil)
        }
        if let media = try? fm.contentsOfDirectory(atPath: (rootPath as NSString).appendingPathComponent("DCIM/100MEDIA")),
           media.contains(where: { $0.uppercased().hasPrefix("DJI_") }) {
            return CardSignature(brand: .dji, reelName: nil)
        }

        // 9. Insta360
        let hasInstaClip = entries.contains { e in
            guard !e.isDirectory else { return false }
            let ext = (e.name as NSString).pathExtension.lowercased()
            return ext == "insv" || ext == "insp"
        }
        if hasInstaClip || dcim.contains(where: { $0.range(of: #"^Camera\d{2}$"#, options: .regularExpression) != nil }) {
            return CardSignature(brand: .insta360, reelName: nil)
        }

        // 10. AVCHD at the root of the card (some camcorders). After every named family.
        if exists("AVCHD/BDMV") {
            return CardSignature(brand: .avchd, reelName: nil)
        }

        // 11. Generic DCIM: only when it holds video. A photo-only card is not proposed.
        if !dcim.isEmpty, dcimHoldsVideo(rootPath: rootPath, children: dcim) {
            return CardSignature(brand: .genericDCIM, reelName: nil)
        }

        // 12. Sound
        let hasAudio = entries.contains { e in
            guard !e.isDirectory, e.depth <= 2 else { return false }
            let ext = (e.name as NSString).pathExtension.lowercased()
            return ext == "wav" || ext == "bwf"
        }
        if hasAudio {
            let hasVideo = entries.contains { e in
                !e.isDirectory && videoExtensions.contains((e.name as NSString).pathExtension.lowercased())
            }
            if !hasVideo { return CardSignature(brand: .soundRecorder, reelName: nil) }
        }
        return nil
    }

    /// Looks for one video file in `DCIM/` or its direct subfolders (`DCIM/100XXXXX/`).
    /// Separate from `scan` so a card full of photos cannot hide its clips behind the entry cap.
    private static func dcimHoldsVideo(rootPath: String, children: [String]) -> Bool {
        let fm = FileManager.default
        let dcimPath = (rootPath as NSString).appendingPathComponent("DCIM")
        func isVideo(_ name: String) -> Bool {
            !name.hasPrefix(".") && dcimVideoExtensions.contains((name as NSString).pathExtension.lowercased())
        }
        if children.contains(where: isVideo) { return true }
        for child in children.sorted().prefix(maxDCIMFolders) {
            let path = (dcimPath as NSString).appendingPathComponent(child)
            guard let names = try? fm.contentsOfDirectory(atPath: path) else { continue }
            if names.contains(where: isVideo) { return true }
        }
        return false
    }

    /// Breadth-first scan, depth 1 = direct children of the root.
    private static func scan(rootPath: String) -> [Entry] {
        let fm = FileManager.default
        var result: [Entry] = []
        var queue: [(path: String, rel: String, depth: Int)] = [(rootPath, "", 1)]
        var index = 0
        while index < queue.count, result.count < maxEntries {
            let item = queue[index]; index += 1
            guard let names = try? fm.contentsOfDirectory(atPath: item.path) else { continue }
            for name in names.sorted() where !name.hasPrefix(".") {
                if result.count >= maxEntries { break }
                let full = (item.path as NSString).appendingPathComponent(name)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: full, isDirectory: &isDir) else { continue }
                let rel = item.rel.isEmpty ? name : item.rel + "/" + name
                result.append(Entry(name: name, relPath: rel, depth: item.depth, isDirectory: isDir.boolValue))
                if isDir.boolValue, item.depth < maxDepth {
                    queue.append((full, rel, item.depth + 1))
                }
            }
        }
        return result
    }
}
