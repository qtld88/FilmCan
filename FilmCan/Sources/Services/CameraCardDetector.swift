import Foundation

enum CameraBrand: String, Codable, CaseIterable {
    case arri, red, sony, canon, panasonic, blackmagic, dji, gopro, soundRecorder

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
        case .soundRecorder: return "Sound recorder"
        }
    }

    var isSound: Bool { self == .soundRecorder }
}

struct CardSignature: Equatable {
    var brand: CameraBrand
    var reelName: String?
}

enum CameraCardDetector {
    private static let maxDepth = 3
    private static let maxEntries = 2000
    private static let videoExtensions: Set<String> = ["mov", "mp4", "mxf", "braw", "r3d", "crm", "ari", "mts"]

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

        // 5. Panasonic
        if exists("PRIVATE/PANA_GRP") || exists("PRIVATE/AVCHD") || dcim.contains(where: { $0.uppercased().hasSuffix("_PANA") }) {
            return CardSignature(brand: .panasonic, reelName: nil)
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

        // 9. Sound
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
