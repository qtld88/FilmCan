import Foundation

struct RsyncOptions: Codable, Equatable {
    var copyEngine: CopyEngine = .rsync
    var useChecksum: Bool = false         // -c flag
    var verbose: Bool = true               // -v
    var showProgress: Bool = true         // --progress
    var showStats: Bool = true            // --stats (always enabled)
    var humanReadable: Bool = true        // -h
    var delete: Bool = false              // --delete (dangerous!)
    var inplace: Bool = false             // --inplace
    var postVerify: Bool = true           // Post-copy verification
    var onlyCopyChanged: Bool = true      // Default rsync behavior (quick check)
    var useHashListPrecheck: Bool = false // FilmCan Engine: skip unchanged using hash list
    var reuseOrganizedFiles: Bool = false // Reuse identical files from previous organized backup
    var allowResume: Bool = true          // Keep partials so transfers can resume after pause
    var customArgs: String = ""           // Additional custom arguments
    var fileOrdering: FileOrdering = .defaultOrder
    var parallelCopyEnabled: Bool = true  // FilmCan Engine: allow parallel file copy
    var customVerifyEnabled: Bool = true  // FilmCan Engine: verify with hashes during copy

    private static let defaultExcludedRootDirectories: [String] = [
        ".Trashes",
        ".fseventsd",
        ".Spotlight-V100",
        ".DocumentRevisions-V100",
        ".TemporaryItems"
    ]

    static let defaultExcludedPatterns: [String] = [
        ".DS_Store"
    ] + defaultExcludedRootDirectories

    static func defaultExcludeArgs() -> [String] {
        defaultExcludedPatterns.map { "--exclude=\($0)" }
    }
    
    var isValid: Bool {
        if copyEngine == .custom {
            return true
        }
        // Block dangerous flags in the free-text custom args field.
        // --delete is already handled by its own toggle, so flag it here too to prevent duplication.
        let dangerous = ["--remove-source-files", "--fake-super", "--delete"]
        let args = customArgs.lowercased()
        return !dangerous.contains { args.contains($0) }
    }
    
    func buildArgs() -> [String] {
        var args: [String] = []
        
        // Always recurse into directories
        args.append("-r")
        // Preserve modification times to avoid re-copying unchanged files
        args.append("-t")
        // Skip common macOS metadata files and protected system folders at the volume root
        args.append(contentsOf: RsyncOptions.defaultExcludeArgs())
        
        if useChecksum {
            args.append("--checksum-choice=xxh128")
            args.append("-c")
        }
        
        if verbose { args.append("-v") }
        args.append("--itemize-changes")
        args.append("--out-format=FILMCAN\t%i\t%n%L")
        if showProgress { args.append("--progress") }
        // Always include stats so we can summarize what changed
        args.append("--stats")
        if humanReadable { args.append("-h") }
        if delete { args.append("--delete") }
        if inplace { args.append("--inplace") }
        if !onlyCopyChanged { args.append("--ignore-times") }
        if allowResume {
            args.append("--partial")
            args.append("--partial-dir=\(FilmCanPaths.partial)")
        }
        
        if !customArgs.isEmpty {
            args.append(contentsOf: sanitizedCustomArgs())
        }
        
        return args
    }

    private func sanitizedCustomArgs() -> [String] {
        let raw = customArgs
        let pattern = #"--log-file(?:=\S+|\s+"[^"]+"|\s+'[^']+'|\s+\S+)"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(raw.startIndex..., in: raw)
            let cleaned = regex.stringByReplacingMatches(in: raw, range: range, withTemplate: "")
            return cleaned.split(whereSeparator: \.isWhitespace).map(String.init)
        }
        return raw.split(whereSeparator: \.isWhitespace).map(String.init)
    }
}
