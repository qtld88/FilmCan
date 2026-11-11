import Foundation

/// A film owns its settings. A preset record with `ownerFilmId` is that film's private
/// copy; a record without one is a shared preset: a starting point, never live-linked.
/// Pure functions, so the rules are testable without storage.
enum FilmPresetOwnership {
    struct Adoption: Equatable {
        var configurations: [BackupConfiguration]
        var presets: [OrganizationPreset]
        var changed: Bool
    }

    /// Shared presets: what a film, Quick Copy or an export can start from.
    static func shared(_ presets: [OrganizationPreset]) -> [OrganizationPreset] {
        presets.filter { $0.ownerFilmId == nil }
    }

    static func isOwnCopy(_ preset: OrganizationPreset, of filmId: UUID) -> Bool {
        preset.ownerFilmId == filmId
    }

    /// A private copy of `preset` for one film: same values and name, new identity.
    static func ownCopy(of preset: OrganizationPreset, for filmId: UUID) -> OrganizationPreset {
        var copy = preset
        copy.id = UUID()
        copy.ownerFilmId = filmId
        return copy
    }

    /// Every film that points at a preset it does not own gets its own copy and points
    /// at it. Films without a preset, or with an id that matches nothing, are left alone.
    /// Shared presets are kept. Running it again on its own result changes nothing.
    static func adopt(configurations: [BackupConfiguration],
                      presets: [OrganizationPreset]) -> Adoption {
        var configs = configurations
        var all = presets
        var changed = false
        for index in configs.indices {
            guard let id = configs[index].selectedOrganizationPresetId,
                  let preset = all.first(where: { $0.id == id }),
                  !isOwnCopy(preset, of: configs[index].id) else { continue }
            let copy = ownCopy(of: preset, for: configs[index].id)
            all.append(copy)
            configs[index].selectedOrganizationPresetId = copy.id
            // The film's saved working copy may be older than the preset another film
            // edited meanwhile. Align it, so the film's first save cannot write stale
            // folders into its new copy.
            configs[index].mirrorOrganization(from: copy)
            changed = true
        }
        return Adoption(configurations: configs, presets: all, changed: changed)
    }

    /// "Preset 3": numbered among the shared presets, skipping names already taken.
    static func nextSharedName(in presets: [OrganizationPreset]) -> String {
        let names = Set(shared(presets).map(\.name))
        var number = names.count + 1
        while names.contains("Preset \(number)") { number += 1 }
        return "Preset \(number)"
    }

    /// Presets left once a film is deleted: its own copies go with it.
    static func removingCopies(ownedBy filmId: UUID,
                               from presets: [OrganizationPreset]) -> [OrganizationPreset] {
        presets.filter { $0.ownerFilmId != filmId }
    }
}

extension BackupConfiguration {
    /// The film's working copy of the folder and renaming settings follows `preset`.
    /// (A run reads the preset itself; these fields are what the editor saves back.)
    mutating func mirrorOrganization(from preset: OrganizationPreset) {
        organizationFolderTemplate = preset.folderTemplate
        organizationRenameTemplate = preset.renameTemplate
        organizationUseFolderTemplate = preset.useFolderTemplate
        organizationUseRenameTemplate = preset.useRenameTemplate
        organizationRenameOnlyPatterns = preset.renameOnlyPatterns
        organizationIncludePatterns = preset.includePatterns
        organizationExcludePatterns = preset.excludePatterns
        organizationCopyOnlyPatterns = preset.copyOnlyPatterns
        organizationUseCustomDate = preset.useCustomDate
        organizationCustomDate = preset.customDate
    }

    /// Takes every setting a preset carries (copy, verification, logs, duplicates,
    /// folders). The caller points the film at its own copy of the preset.
    mutating func takeSettings(from preset: OrganizationPreset) {
        copyFolderContents = preset.copyFolderContents
        runInParallel = preset.runInParallel
        engineOptions = preset.engineOptions
        logEnabled = preset.logEnabled
        logLocation = preset.logLocation
        customLogPath = preset.customLogPath
        logFileNameTemplate = preset.logFileNameTemplate
        duplicatePolicy = preset.duplicatePolicy
        duplicateCounterTemplate = preset.duplicateCounterTemplate
        mirrorOrganization(from: preset)
        // Netflix's approved layout puts per-roll reports in a Reports/ folder at the
        // shoot-day root. Pre-fill that as a changeable default (don't clobber a path
        // the user already chose).
        if preset.name == OrganizationPreset.netflixIngestName, customLogPath.isEmpty {
            logLocation = .custom
            customLogPath = "Reports"
        }
    }
}

// MARK: - A new film like a previous one

enum FilmTemplate {
    /// Letters and digits only, lowercased: "Citizen K" and "CITIZEN_K" compare equal.
    static func normalizedName(_ name: String) -> String {
        String(name.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    /// When the first folder of `template` spells `filmName`, it becomes `{movie}`,
    /// so a film created from this one gets its own top folder. Anything else is
    /// returned as typed.
    static func replacingLeadingFilmFolder(in template: String, filmName: String) -> String {
        let wanted = normalizedName(filmName)
        guard !wanted.isEmpty else { return template }
        var parts = template.components(separatedBy: "/")
        guard let first = parts.first, !first.contains("{"),
              normalizedName(first) == wanted else { return template }
        parts[0] = "{movie}"
        return parts.joined(separator: "/")
    }

    static func replacingLeadingFilmFolder(in preset: OrganizationPreset, filmName: String) -> OrganizationPreset {
        var out = preset
        out.folderTemplate = replacingLeadingFilmFolder(in: preset.folderTemplate, filmName: filmName)
        out.soundFolderTemplate = replacingLeadingFilmFolder(in: preset.soundFolderTemplate, filmName: filmName)
        return out
    }
}

extension BackupConfiguration {
    /// A new film with the settings of `source`: a copy, never a link. What belongs to
    /// the other film's shoot stays there: cards, drives, their tags, the shoot day,
    /// card names, usage dates. Counters and history are stored per film id, so a new
    /// id starts them fresh. The caller gives the film its own preset copy.
    static func newFilm(name: String, like source: BackupConfiguration) -> BackupConfiguration {
        var config = source
        config.id = UUID()
        config.name = name
        config.sourcePaths = []
        config.destinationPaths = []
        config.excludedSourcePaths = []
        config.excludedDestinationPaths = []
        config.sourceMediaKinds = [:]
        config.organizationReuseByDestination = [:]
        config.genericRollNames = [:]
        config.runRollNames = [:]
        config.day = ""
        config.forceRecopy = false
        config.selectedOrganizationPresetId = nil
        config.createdAt = Date()
        config.lastUsedAt = nil
        for keyPath in [\BackupConfiguration.organizationFolderTemplate,
                        \BackupConfiguration.offOrganizationFolderTemplate,
                        \BackupConfiguration.cameraFolderTemplate,
                        \BackupConfiguration.soundFolderTemplate] {
            config[keyPath: keyPath] = FilmTemplate.replacingLeadingFilmFolder(
                in: config[keyPath: keyPath], filmName: source.name)
        }
        return config
    }
}
