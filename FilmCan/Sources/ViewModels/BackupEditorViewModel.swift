import Foundation
import Combine
import SwiftUI

struct GenericCardWarning: Identifiable, Equatable {
    /// Card key (volume UUID + relative path).
    let id: String
    let path: String
    let name: String
    let suggested: String
}

@MainActor
class BackupEditorViewModel: ObservableObject {
    @Published var config: BackupConfiguration
    @Published var showValidationError: Bool = false
    @Published var validationMessage: String = ""
    
    private let storage: ConfigurationStorage
    private var isSyncingFromPreset = false
    
    /// `storage`: the app's storage unless a test passes its own (a temp directory).
    init(config: BackupConfiguration, storage: ConfigurationStorage? = nil) {
        self.config = config
        self.storage = storage ?? AppState.shared.storage
    }

    func syncFromStorage(_ updated: BackupConfiguration) {
        guard updated.id == config.id else { return }
        if config != updated {
            config = updated
        }
    }
    
    // Source paths
    var sourcePaths: [String] {
        get { config.sourcePaths }
        set {
            let previous = config.sourcePaths
            config.sourcePaths = newValue
            storage.lastSourcePath = newValue.last
            let removed = Set(previous).subtracting(newValue)
            config.excludedSourcePaths.subtract(removed)
            save()
            if !removed.isEmpty { keepReaddedSourcesUnchecked(removed, previous: previous) }
            refreshGenericCards()
        }
    }

    var includedSourcePaths: [String] { config.includedSourcePaths }

    func isSourceIncluded(_ path: String) -> Bool { !config.excludedSourcePaths.contains(path) }

    func setSourcesIncluded(_ paths: [String], _ included: Bool) {
        if included { config.excludedSourcePaths.subtract(paths) } else { config.excludedSourcePaths.formUnion(paths) }
        save()
    }

    /// With auto-detect on, a removed drive that is still plugged in comes straight back.
    /// Keep it where it was, unchecked, so it stays visibly out of the backup.
    private func keepReaddedSourcesUnchecked(_ removed: Set<String>, previous: [String]) {
        refreshAutoDetectedSources()
        refreshAutoDetectedSoundSources()
        refreshAutoDetectedCards()
        let readded = removed.intersection(config.sourcePaths)
        guard !readded.isEmpty else { return }
        let current = Set(config.sourcePaths)
        config.sourcePaths = previous.filter { current.contains($0) }
            + config.sourcePaths.filter { !previous.contains($0) }
        config.excludedSourcePaths.formUnion(readded)
        save()
    }
    
    func addSource(_ path: String) {
        guard !path.isEmpty && !config.sourcePaths.contains(path) else { return }
        config.sourcePaths.append(path)
        storage.lastSourcePath = path
        save()
        refreshGenericCards()
    }
    
    func removeSource(at index: Int) {
        guard index < config.sourcePaths.count else { return }
        let path = config.sourcePaths.remove(at: index)
        config.excludedSourcePaths.remove(path)
        save()
    }
    
    // Destinations
    var destinations: [String] {
        get { config.destinationPaths }
        set {
            let previous = config.destinationPaths
            config.destinationPaths = newValue
            if let first = newValue.first {
                storage.lastDestinationPath = first
            }
            let removed = Set(previous).subtracting(newValue)
            config.excludedDestinationPaths.subtract(removed)
            save()
            if !removed.isEmpty { keepReaddedDestinationsUnchecked(removed, previous: previous) }
            refreshGenericCards(recompute: true)
        }
    }

    var includedDestinationPaths: [String] { config.includedDestinationPaths }

    func isDestinationIncluded(_ path: String) -> Bool { !config.excludedDestinationPaths.contains(path) }

    func setDestinationsIncluded(_ paths: [String], _ included: Bool) {
        if included { config.excludedDestinationPaths.subtract(paths) } else { config.excludedDestinationPaths.formUnion(paths) }
        save()
    }

    private func keepReaddedDestinationsUnchecked(_ removed: Set<String>, previous: [String]) {
        refreshAutoDetectedDestinations()
        let readded = removed.intersection(config.destinationPaths)
        guard !readded.isEmpty else { return }
        let current = Set(config.destinationPaths)
        config.destinationPaths = previous.filter { current.contains($0) }
            + config.destinationPaths.filter { !previous.contains($0) }
        config.excludedDestinationPaths.formUnion(readded)
        save()
    }
    
    func addDestination(_ path: String) {
        if !path.isEmpty && !config.destinationPaths.contains(path) {
            config.destinationPaths.append(path)
            storage.lastDestinationPath = path
            save()
            refreshGenericCards(recompute: true)
        }
    }
    
    func removeDestination(at index: Int) {
        guard index < config.destinationPaths.count else { return }
        let path = config.destinationPaths.remove(at: index)
        config.excludedDestinationPaths.remove(path)
        save()
    }
    
    func moveDestinations(from source: IndexSet, to destination: Int) {
        config.destinationPaths.move(fromOffsets: source, toOffset: destination)
        save()
    }
    
    // Rsync options
    var engineOptions: EngineOptions {
        get { config.engineOptions }
        set {
            config.engineOptions = newValue
            save()
        }
    }

    /// Verification mode (Off / Fast / Paranoid). Keeps `customVerifyEnabled`
    /// in sync so hash-list generation and verify-enabled UI follow the choice.
    var verificationMode: VerifyMode {
        get { config.engineOptions.verificationMode }
        set {
            config.engineOptions.verificationMode = newValue
            config.engineOptions.customVerifyEnabled = (newValue != .off)
            save()
        }
    }

    func enforceCustomEngineDefaultsIfNeeded() {}
    
    // Name
    var name: String {
        get { config.name }
        set {
            config.name = newValue
            save()
        }
    }
    
    // Log location
    var logEnabled: Bool {
        get { config.logEnabled }
        set {
            config.logEnabled = newValue
            save()
        }
    }

    var logLocation: BackupConfiguration.LogLocation {
        get { config.logLocation }
        set {
            config.logLocation = newValue
            save()
        }
    }
    
    var customLogPath: String {
        get { config.customLogPath }
        set {
            config.customLogPath = newValue
            save()
        }
    }

    var logFileNameTemplate: String {
        get { config.logFileNameTemplate }
        set {
            config.logFileNameTemplate = newValue
            save()
        }
    }
    
    var runInParallel: Bool {
        get { config.runInParallel }
        set {
            config.runInParallel = newValue
            save()
        }
    }

    var destinationCopyMode: DestinationCopyMode {
        get { config.destinationCopyMode }
        set {
            config.destinationCopyMode = newValue
            save()
        }
    }

    var forceRecopy: Bool {
        get { config.forceRecopy }
        set {
            config.forceRecopy = newValue
            save()
        }
    }

    var reVerifyExistingOnResume: Bool {
        get { config.reVerifyExistingOnResume }
        set { config.reVerifyExistingOnResume = newValue; save() }
    }

    var hashListStyle: HashListStyle {
        get { config.hashListStyle }
        set { config.hashListStyle = newValue; save() }
    }

    var episode: String {
        get { config.episode }
        set { config.episode = newValue; save() }
    }
    var day: String {
        get { config.day }
        set { config.day = newValue; save() }
    }
    var unit: String {
        get { config.unit }
        set { config.unit = newValue; save() }
    }
    var cameraFormat: String {
        get { config.cameraFormat }
        set { config.cameraFormat = newValue; save() }
    }

    var copyFolderContents: Bool {
        get { config.copyFolderContents }
        set {
            config.copyFolderContents = newValue
            save()
            refreshGenericCards(recompute: true)
        }
    }

    // MARK: - Generic card names (Untitled, DJI ...)

    /// Single guard: with automatic roll numbering on, none of the generic-name handling applies.
    var genericCardSupportActive: Bool { !config.rollNumbering.enabled }

    @Published var genericCardWarning: GenericCardWarning?
    private var dismissedGenericCards: Set<String> = []
    /// Card keys whose name the user typed (or cleared): never auto-written again.
    private var userEditedGenericCards: Set<String> = []
    /// Card keys whose name this session suggested: the only ones recomputed.
    private var autoWrittenGenericCards: Set<String> = []

    func isGenericSource(_ path: String) -> Bool {
        genericCardSupportActive && Self.isDirectory(path)
            && GenericCardName.isGeneric((path as NSString).lastPathComponent)
    }

    private var genericSourcePaths: [String] { config.sourcePaths.filter { isGenericSource($0) } }

    private func effectiveRunPreset() -> OrganizationPreset? {
        var preset: OrganizationPreset?
        if let id = config.selectedOrganizationPresetId,
           let selected = storage.organizationPresets.first(where: { $0.id == id }) {
            preset = selected
        } else {
            let local = localOrganizationPreset
            let hasTemplate = local.useFolderTemplate
                && !local.folderTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let hasRename = local.useRenameTemplate
                && !local.renameTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let hasPatterns = SourceFilterMatching.hasCustomFilterPatterns(
                include: local.includePatterns, exclude: local.excludePatterns, copyOnly: local.copyOnlyPatterns)
            if hasTemplate || hasRename || hasPatterns || local.useCustomDate { preset = local }
        }
        guard var result = preset else { return nil }
        if result.name == OrganizationPreset.netflixIngestName {
            let cam = config.cameraFolderTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cam.isEmpty { result.folderTemplate = config.cameraFolderTemplate }
            let snd = config.soundFolderTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
            if !snd.isEmpty { result.soundFolderTemplate = config.soundFolderTemplate }
        }
        return result
    }

    private func existingGenericNames(for path: String) -> [String] {
        GenericRollNameScanner.existingNames(
            source: path, destinations: config.destinationPaths,
            preset: effectiveRunPreset(), date: Date(),
            metadata: ShootMetadata(episode: config.episode, day: config.day,
                                    unit: config.unit, cameraFormat: config.cameraFormat,
                                    movie: config.name),
            mediaKind: mediaKind(for: path))
    }

    private func genericNamesOfOtherSources(excluding path: String) -> [String] {
        let own = RollNumberer.cardKey(forPath: path)
        return config.sourcePaths.compactMap { other in
            guard other != path else { return nil }
            let key = RollNumberer.cardKey(forPath: other)
            return key == own ? nil : config.genericRollNames[key]
        }
    }

    /// Next free numbered name for a generic card, e.g. `Untitled_01`.
    func suggestedRollName(for path: String) -> String {
        GenericCardName.nextNumberedName(
            base: GenericCardName.baseName((path as NSString).lastPathComponent),
            taken: existingGenericNames(for: path) + genericNamesOfOtherSources(excluding: path))
    }

    func rollNameOverride(for path: String) -> String? {
        guard genericCardSupportActive else { return nil }
        return config.genericRollNames[RollNumberer.cardKey(forPath: path)]
    }

    func setRollNameOverride(_ name: String, for path: String) {
        let key = RollNumberer.cardKey(forPath: path)
        let cleaned = name.replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        userEditedGenericCards.insert(key)
        autoWrittenGenericCards.remove(key)
        if cleaned.isEmpty {
            config.genericRollNames[key] = nil
            dismissedGenericCards.insert(key)
        } else {
            config.genericRollNames[key] = cleaned
        }
        save()
        updateGenericCardWarning()
    }

    /// Folder mode: gives each generic card without a name its suggestion. `recompute`
    /// (destinations, preset or copy mode changed) also refreshes the suggestions made this session.
    func ensureGenericRollNames(recompute: Bool = false) {
        guard genericCardSupportActive, !config.copyFolderContents else { return }
        var changed = false
        if recompute {
            for path in genericSourcePaths {
                let key = RollNumberer.cardKey(forPath: path)
                if autoWrittenGenericCards.contains(key), !userEditedGenericCards.contains(key),
                   config.genericRollNames.removeValue(forKey: key) != nil {
                    changed = true
                }
            }
        }
        for path in genericSourcePaths {
            let key = RollNumberer.cardKey(forPath: path)
            guard config.genericRollNames[key] == nil, !userEditedGenericCards.contains(key) else { continue }
            config.genericRollNames[key] = suggestedRollName(for: path)
            autoWrittenGenericCards.insert(key)
            changed = true
        }
        if changed { save() }
    }

    /// Fills missing names (folder mode) and raises the contents-mode warning when needed.
    func refreshGenericCards(recompute: Bool = false) {
        ensureGenericRollNames(recompute: recompute)
        updateGenericCardWarning()
    }

    private func updateGenericCardWarning() {
        guard genericCardSupportActive, config.copyFolderContents else {
            genericCardWarning = nil
            return
        }
        if let current = genericCardWarning,
           config.sourcePaths.contains(current.path), config.genericRollNames[current.id] == nil,
           !dismissedGenericCards.contains(current.id) {
            return
        }
        genericCardWarning = nil
        for path in genericSourcePaths {
            let key = RollNumberer.cardKey(forPath: path)
            guard config.genericRollNames[key] == nil, !dismissedGenericCards.contains(key) else { continue }
            genericCardWarning = GenericCardWarning(
                id: key, path: path,
                name: GenericCardName.baseName((path as NSString).lastPathComponent),
                suggested: suggestedRollName(for: path))
            return
        }
    }

    func acceptGenericCardWarning() {
        guard let warning = genericCardWarning else { return }
        genericCardWarning = nil
        setRollNameOverride(warning.suggested, for: warning.path)
    }

    func dismissGenericCardWarning() {
        guard let warning = genericCardWarning else { return }
        dismissedGenericCards.insert(warning.id)
        genericCardWarning = nil
        updateGenericCardWarning()
    }

    var sourceAutoDetectEnabled: Bool {
        get { config.sourceAutoDetectEnabled }
        set {
            config.sourceAutoDetectEnabled = newValue
            save()
        }
    }

    var sourceAutoDetectPatterns: [String] {
        get { config.sourceAutoDetectPatterns }
        set {
            config.sourceAutoDetectPatterns = newValue
            save()
        }
    }

    // MARK: - Camera/Sound media kind (Netflix Sound_Media routing)

    func mediaKind(for path: String) -> SourceMediaKind {
        config.sourceMediaKinds[path] ?? .camera
    }

    func setMediaKind(_ kind: SourceMediaKind, for path: String) {
        if kind == .camera {
            config.sourceMediaKinds[path] = nil   // camera is the default; keep the map small
        } else {
            config.sourceMediaKinds[path] = kind
        }
        save()
    }

    var cameraFolderTemplate: String {
        get { config.cameraFolderTemplate }
        set { config.cameraFolderTemplate = newValue; save() }
    }

    var soundFolderTemplate: String {
        get { config.soundFolderTemplate }
        set { config.soundFolderTemplate = newValue; save() }
    }

    var soundAutoDetectEnabled: Bool {
        get { config.soundAutoDetectEnabled }
        set { config.soundAutoDetectEnabled = newValue; save() }
    }

    var soundAutoDetectPatterns: [String] {
        get { config.soundAutoDetectPatterns }
        set { config.soundAutoDetectPatterns = newValue; save() }
    }

    var soundDayFolderAutoDetect: Bool {
        get { config.soundDayFolderAutoDetect }
        set { config.soundDayFolderAutoDetect = newValue; save() }
    }

    // MARK: - Card recognition and roll numbering

    var rollNumbering: RollNumbering {
        get { config.rollNumbering }
        set { config.rollNumbering = newValue; save() }
    }

    var dayAutoAdvance: Bool {
        get { config.dayAutoAdvance }
        set { config.dayAutoAdvance = newValue; save() }
    }

    var cardAutoDetectEnabled: Bool {
        get { config.cardAutoDetectEnabled }
        set { config.cardAutoDetectEnabled = newValue; save() }
    }

    private var cardCache: [String: CardSignature?] = [:]

    /// Detected camera/sound card for a source path (cached until the next drive refresh).
    func detectedCard(for path: String) -> CardSignature? {
        if let cached = cardCache[path] { return cached }
        let signature = CameraCardDetector.detect(rootPath: path)
        cardCache[path] = .some(signature)
        return signature
    }

    func clearCardCache() {
        cardCache.removeAll()
        objectWillChange.send()
    }

    /// Roll name the next run would give this source; nil when numbering is off or the
    /// source is not a folder. Does not save anything.
    func rollNamePreview(for path: String) -> String? {
        guard config.rollNumbering.enabled else { return nil }
        let state = RollNumberingStore.shared.state(for: config.id)
        let result = RollNumberer.assign(
            sources: config.includedSourcePaths,
            isDirectory: Self.isDirectory,
            kinds: config.sourceMediaKinds,
            settings: config.rollNumbering,
            existing: state.assignments,
            keyFor: { RollNumberer.cardKey(forPath: $0) },
            signatureFor: { [weak self] in self?.detectedCard(for: $0) })
        return result.names[path]
    }

    /// "Next camera roll: A004 · next sound roll: S002".
    var nextRollSummary: String {
        let state = RollNumberingStore.shared.state(for: config.id)
        let assigned = Array(state.assignments.values)
        let cam = RollNumberer.nextName(kind: .camera, settings: config.rollNumbering, assigned: assigned)
        let snd = RollNumberer.nextName(kind: .sound, settings: config.rollNumbering, assigned: assigned)
        return "Next camera roll: \(cam) · next sound roll: \(snd)"
    }

    /// Shoot day a run started now would use — same computation as
    /// `TransferViewModel.applyRollNumberingAndDay`, so the folder preview matches the copy.
    func effectiveShootDay(now: Date = Date()) -> String {
        guard config.dayAutoAdvance else { return config.day }
        let state = RollNumberingStore.shared.state(for: config.id)
        return ShootDayCounter.advance(
            day: state.currentDay ?? config.day, lastRun: state.lastRunDate,
            now: now, calendar: .current)
    }

    /// Day change made from the film header. With the day counter on it is today's
    /// override (tomorrow's first run advances from it); otherwise it is the film's day.
    func setShootDayFromHeader(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != effectiveShootDay() else { return }
        if config.dayAutoAdvance {
            shootDayToday = trimmed
        } else {
            day = trimmed
        }
    }

    /// Today's shoot day when auto-advance is on. Setting it overrides the counter for
    /// today; tomorrow's first run advances from the edited value.
    var shootDayToday: String {
        get { effectiveShootDay() }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return }
            var state = RollNumberingStore.shared.state(for: config.id)
            state.currentDay = trimmed
            state.lastRunDate = Date()
            RollNumberingStore.shared.update(state, for: config.id)
            objectWillChange.send()
        }
    }

    func resetRollNumbering() {
        RollNumberingStore.shared.resetNumbering(for: config.id)
        objectWillChange.send()
    }

    private static func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    /// Volume UUID of the drive holding `path`, for the per-drive recognition override.
    func volumeUUID(for path: String) -> String? {
        FanOutCopier.sourceVolumeUUID(path)
    }

    /// Correct the detector for one drive and remember it (by volume UUID).
    func setCardRole(_ role: CardRole?, for path: String) {
        if let uuid = volumeUUID(for: path) {
            CardRoleOverrides.set(role, forVolumeUUID: uuid, driveName: FanOutCopier.sourceVolumeName(path))
        }
        if role == .sound { setMediaKind(.sound, for: path) }
        else if role == .camera { setMediaKind(.camera, for: path) }
        else if role == .notACard, let index = config.sourcePaths.firstIndex(of: path) {
            removeSource(at: index)
        }
        clearCardCache()
        refreshAutoDetectedCards()
    }

    /// Adds recognised camera/sound cards among the mounted external drives to the
    /// sources (sound cards are tagged Sound). Drives the user marked "not a card" are
    /// skipped; destinations are never added.
    func refreshAutoDetectedCards() {
        cardCache.removeAll()
        guard config.cardAutoDetectEnabled else { return }
        var sources = config.sourcePaths
        var kinds = config.sourceMediaKinds
        var changed = false
        for volumeURL in mountedExternalVolumes() {
            let path = volumeURL.path
            if config.destinationPaths.contains(where: { $0 == path || $0.hasPrefix(path + "/") }) { continue }
            if sources.contains(path) && !config.soundDayFolderAutoDetect { continue }
            let override = FanOutCopier.sourceVolumeUUID(path).flatMap { CardRoleOverrides.role(forVolumeUUID: $0) }
            if override == .notACard { continue }
            let role: CardRole
            if let override {
                role = override
            } else if let signature = CameraCardDetector.detect(rootPath: path) {
                role = signature.brand.isSound ? .sound : .camera
            } else {
                continue
            }
            if role != .sound && FolderPick.hasDeeperPick(under: path, in: sources) { continue }
            let added = role == .sound ? soundDayPaths(path) : [path]
            let updated = keepingOnlyToday(sources + added.filter { !sources.contains($0) },
                                           volumePath: path, resolved: added)
            if updated != sources { sources = updated; changed = true }
            if role == .sound {
                for day in added where kinds[day] != .sound { kinds[day] = .sound; changed = true }
            }
        }
        if changed {
            config.sourcePaths = sources
            config.sourceMediaKinds = kinds
            save()
            refreshGenericCards()
        }
    }

    var destinationAutoDetectEnabled: Bool {
        get { config.destinationAutoDetectEnabled }
        set {
            config.destinationAutoDetectEnabled = newValue
            save()
        }
    }

    var destinationAutoDetectPatterns: [String] {
        get { config.destinationAutoDetectPatterns }
        set {
            config.destinationAutoDetectPatterns = newValue
            save()
        }
    }

    func refreshAutoDetectedSources() {
        guard config.sourceAutoDetectEnabled else { return }
        let rules = config.sourceAutoDetectPatterns
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !rules.isEmpty else { return }

        var updated = config.sourcePaths
        let volumeURLs = mountedExternalVolumes()
        for volumeURL in volumeURLs {
            let volumeName = volumeURL.lastPathComponent
            for rule in rules {
                let (pattern, subpath) = splitRule(rule)
                if matches(volumeName, pattern: pattern) {
                    let resolvedMatches = resolveSubpathMatches(rootURL: volumeURL, subpath: subpath)
                    for resolved in resolvedMatches
                    where !updated.contains(resolved) && !FolderPick.hasDeeperPick(under: resolved, in: updated) {
                        updated.append(resolved)
                    }
                    updated = keepingOnlyToday(updated, volumePath: volumeURL.path, resolved: resolvedMatches)
                }
            }
        }

        if updated != config.sourcePaths {
            config.sourcePaths = updated
            save()
            refreshGenericCards()
        }
    }

    /// Like `refreshAutoDetectedSources`, but for Sound: matching drives/folders are
    /// added to the source list AND tagged as Sound (Netflix Sound_Media routing).
    func refreshAutoDetectedSoundSources() {
        guard config.soundAutoDetectEnabled else { return }
        let rules = config.soundAutoDetectPatterns
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !rules.isEmpty else { return }

        var updated = config.sourcePaths
        var kinds = config.sourceMediaKinds
        var changed = false
        let volumeURLs = mountedExternalVolumes()
        for volumeURL in volumeURLs {
            let volumeName = volumeURL.lastPathComponent
            for rule in rules {
                let (pattern, subpath) = splitRule(rule)
                guard matches(volumeName, pattern: pattern) else { continue }
                var resolvedMatches: [String] = []
                for match in resolveSubpathMatches(rootURL: volumeURL, subpath: subpath) {
                    let days = soundDayPaths(match)
                    if days != [match], let index = updated.firstIndex(of: match) {
                        updated.remove(at: index)
                        changed = true
                    }
                    resolvedMatches += days
                }
                for resolved in resolvedMatches {
                    if !updated.contains(resolved) { updated.append(resolved); changed = true }
                    if kinds[resolved] != .sound { kinds[resolved] = .sound; changed = true }
                }
                let pruned = keepingOnlyToday(updated, volumePath: volumeURL.path, resolved: resolvedMatches)
                if pruned != updated { updated = pruned; changed = true }
            }
        }

        if changed {
            config.sourcePaths = updated
            config.sourceMediaKinds = kinds
            save()
            refreshGenericCards()
        }
    }

    func refreshAutoDetectedDestinations() {
        guard config.destinationAutoDetectEnabled else { return }
        let rules = config.destinationAutoDetectPatterns
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !rules.isEmpty else { return }

        var updated = config.destinationPaths
        let volumeURLs = mountedExternalVolumes()
        for volumeURL in volumeURLs {
            let volumeName = volumeURL.lastPathComponent
            for rule in rules {
                let (pattern, subpath) = splitRule(rule)
                if matches(volumeName, pattern: pattern) {
                    let resolvedMatches = resolveSubpathMatches(rootURL: volumeURL, subpath: subpath)
                    for resolved in resolvedMatches
                    where !updated.contains(resolved) && !FolderPick.hasDeeperPick(under: resolved, in: updated) {
                        updated.append(resolved)
                    }
                }
            }
        }

        if updated != config.destinationPaths {
            config.destinationPaths = updated
            if let first = updated.first {
                storage.lastDestinationPath = first
            }
            save()
            refreshGenericCards(recompute: true)
        }
    }

    var duplicatePolicy: OrganizationPreset.DuplicatePolicy {
        get { config.duplicatePolicy }
        set {
            config.duplicatePolicy = newValue
            save()
        }
    }

    var duplicateCounterTemplate: String {
        get { config.duplicateCounterTemplate }
        set {
            config.duplicateCounterTemplate = newValue
            save()
        }
    }

    private func mountedExternalVolumes() -> [URL] {
        FilmDriveDetector.mountedExternalVolumes()
    }

    private func splitRule(_ rule: String) -> (String, String) {
        FilmDriveDetector.splitRule(rule)
    }

    private func matches(_ name: String, pattern: String) -> Bool {
        FilmDriveDetector.matches(name, pattern: pattern)
    }

    private func soundDayPaths(_ path: String) -> [String] {
        guard config.soundDayFolderAutoDetect else { return [path] }
        let days = DayFolderResolver.findDayFolders(in: path)
        return days.isEmpty ? [path] : days
    }

    private func keepingOnlyToday(_ sources: [String], volumePath: String, resolved: [String]) -> [String] {
        let days = resolved.filter { DayFolderResolver.dayKey(($0 as NSString).lastPathComponent) != nil }
        return DayFolderResolver.replacingStaleDays(in: sources, volumePath: volumePath, fresh: days)
    }

    private func resolveSubpathMatches(rootURL: URL, subpath: String) -> [String] {
        FilmDriveDetector.resolveSubpathMatches(rootURL: rootURL, subpath: subpath)
    }

    var organizationPresets: [OrganizationPreset] {
        get { storage.organizationPresets }
        set {
            objectWillChange.send()
            storage.organizationPresets = newValue
            storage.save()
        }
    }

    /// Shared presets: what this film can start from. Its own copy is not listed.
    var sharedOrganizationPresets: [OrganizationPreset] {
        FilmPresetOwnership.shared(storage.organizationPresets)
    }

    /// True when the film's settings are its own copy (always, once adopted).
    var selectedPresetIsOwnCopy: Bool {
        guard let id = config.selectedOrganizationPresetId,
              let preset = storage.organizationPresets.first(where: { $0.id == id }) else { return false }
        return FilmPresetOwnership.isOwnCopy(preset, of: config.id)
    }

    /// Makes the film's own copy a copy of `preset` and returns its id (stable once the
    /// film has a copy). The shared preset itself is never linked to the film.
    private func replaceOwnCopy(with preset: OrganizationPreset) -> UUID {
        objectWillChange.send()
        let placed = FilmPresetOwnership.settingOwnCopy(
            of: preset, for: config.id, in: storage.organizationPresets)
        storage.organizationPresets = placed.presets
        return placed.copy.id
    }

    /// Makes sure the film has its own settings record (a film on "Off" that never had
    /// one), carrying exactly what it runs with today. Needed before saving anything the
    /// plain "Off" fields cannot hold, such as a separate sound folder.
    func ensureOwnSettingsCopy() {
        // Settings kept aside while the film is on "Off" are never replaced from here.
        guard config.selectedOrganizationPresetId == nil, parkedOwnCopy == nil else { return }
        var preset = localOrganizationPreset
        preset.copyFolderContents = config.copyFolderContents
        preset.runInParallel = config.runInParallel
        preset.engineOptions = config.engineOptions
        preset.logEnabled = config.logEnabled
        preset.logLocation = config.logLocation
        preset.customLogPath = config.customLogPath
        preset.logFileNameTemplate = config.logFileNameTemplate
        preset.duplicatePolicy = config.duplicatePolicy
        preset.duplicateCounterTemplate = config.duplicateCounterTemplate
        isSyncingFromPreset = true
        config.mirrorOrganization(from: preset)
        config.selectedOrganizationPresetId = replaceOwnCopy(with: preset)
        save()
        isSyncingFromPreset = false
    }

    /// The film's own settings while the film is switched to "Off": kept, so switching
    /// back does not lose them.
    var parkedOwnCopy: OrganizationPreset? {
        guard config.selectedOrganizationPresetId == nil else { return nil }
        return storage.organizationPresets.first { $0.ownerFilmId == config.id }
    }

    /// Back from "Off" to the film's own settings.
    func useParkedOwnCopy() {
        guard let parked = parkedOwnCopy else { return }
        isSyncingFromPreset = true
        config.mirrorOrganization(from: parked)
        config.selectedOrganizationPresetId = parked.id
        save()
        isSyncingFromPreset = false
        refreshGenericCards(recompute: true)
    }

    var selectedOrganizationPresetId: UUID? {
        get { config.selectedOrganizationPresetId }
        set {
            if let id = newValue,
               let preset = storage.organizationPresets.first(where: { $0.id == id }),
               !FilmPresetOwnership.isOwnCopy(preset, of: config.id) {
                // Picking a preset copies it: the film never edits a shared preset.
                isSyncingFromPreset = true
                config.mirrorOrganization(from: preset)
                config.selectedOrganizationPresetId = replaceOwnCopy(with: preset)
                isSyncingFromPreset = false
            } else {
                config.selectedOrganizationPresetId = newValue
            }
            save()
            refreshGenericCards(recompute: true)
        }
    }

    var localOrganizationPreset: OrganizationPreset {
        get {
            var preset = OrganizationPreset()
            preset.name = "Custom"
            preset.folderTemplate = config.offOrganizationFolderTemplate
            preset.renameTemplate = config.offOrganizationRenameTemplate
            preset.useFolderTemplate = config.offOrganizationUseFolderTemplate
            preset.useRenameTemplate = config.offOrganizationUseRenameTemplate
            preset.renameOnlyPatterns = config.offOrganizationRenameOnlyPatterns
            preset.includePatterns = config.offOrganizationIncludePatterns
            preset.excludePatterns = config.offOrganizationExcludePatterns
            preset.copyOnlyPatterns = config.offOrganizationCopyOnlyPatterns
            preset.useCustomDate = config.offOrganizationUseCustomDate
            preset.customDate = config.offOrganizationCustomDate
            return preset
        }
        set {
            config.offOrganizationFolderTemplate = newValue.folderTemplate
            config.offOrganizationRenameTemplate = newValue.renameTemplate
            config.offOrganizationUseFolderTemplate = newValue.useFolderTemplate
            config.offOrganizationUseRenameTemplate = newValue.useRenameTemplate
            config.offOrganizationRenameOnlyPatterns = newValue.renameOnlyPatterns
            config.offOrganizationIncludePatterns = newValue.includePatterns
            config.offOrganizationExcludePatterns = newValue.excludePatterns
            config.offOrganizationCopyOnlyPatterns = newValue.copyOnlyPatterns
            config.offOrganizationUseCustomDate = newValue.useCustomDate
            config.offOrganizationCustomDate = newValue.customDate
            if config.selectedOrganizationPresetId == nil {
                config.organizationFolderTemplate = newValue.folderTemplate
                config.organizationRenameTemplate = newValue.renameTemplate
                config.organizationUseFolderTemplate = newValue.useFolderTemplate
                config.organizationUseRenameTemplate = newValue.useRenameTemplate
                config.organizationRenameOnlyPatterns = newValue.renameOnlyPatterns
                config.organizationIncludePatterns = newValue.includePatterns
                config.organizationExcludePatterns = newValue.excludePatterns
                config.organizationCopyOnlyPatterns = newValue.copyOnlyPatterns
                config.organizationUseCustomDate = newValue.useCustomDate
                config.organizationCustomDate = newValue.customDate
            }
            save()
        }
    }

    /// "Off": the film stops using its folder and file settings. Its own copy is kept
    /// aside (see `parkedOwnCopy`); only the trash button deletes it.
    func applyOffOrganizationSettings() {
        config.selectedOrganizationPresetId = nil
        config.organizationFolderTemplate = config.offOrganizationFolderTemplate
        config.organizationRenameTemplate = config.offOrganizationRenameTemplate
        config.organizationUseFolderTemplate = config.offOrganizationUseFolderTemplate
        config.organizationUseRenameTemplate = config.offOrganizationUseRenameTemplate
        config.organizationRenameOnlyPatterns = config.offOrganizationRenameOnlyPatterns
        config.organizationIncludePatterns = config.offOrganizationIncludePatterns
        config.organizationExcludePatterns = config.offOrganizationExcludePatterns
        config.organizationCopyOnlyPatterns = config.offOrganizationCopyOnlyPatterns
        config.organizationUseCustomDate = config.offOrganizationUseCustomDate
        config.organizationCustomDate = config.offOrganizationCustomDate
        save()
    }

    /// Starts the film from `preset`: takes its values and keeps a private copy.
    /// Later edits stay in the film; the shared preset is not touched.
    func applyPreset(_ preset: OrganizationPreset) {
        config.takeSettings(from: preset)
        if FilmPresetOwnership.isOwnCopy(preset, of: config.id) {
            config.selectedOrganizationPresetId = preset.id
        } else {
            config.selectedOrganizationPresetId = replaceOwnCopy(with: preset)
        }
        save()
    }

    /// Apply the built-in Netflix Ingest preset, persisting it to storage (once) so it
    /// behaves like a normal selectable preset with a stable id/name.
    func applyNetflixIngestPreset() {
        objectWillChange.send()
        let preset: OrganizationPreset
        if let existing = sharedOrganizationPresets.first(where: { $0.name == OrganizationPreset.netflixIngestName }) {
            preset = existing
        } else {
            let p = OrganizationPreset.netflixIngest()
            storage.organizationPresets.append(p)
            preset = p
        }
        applyPreset(preset)
    }

    func syncFromSelectedPresetIfNeeded() {
        guard let selectedId = config.selectedOrganizationPresetId,
              let preset = storage.organizationPresets.first(where: { $0.id == selectedId }) else { return }
        isSyncingFromPreset = true
        config.mirrorOrganization(from: preset)
        save()
        isSyncingFromPreset = false
    }

    func updateSelectedPresetFromCurrent() {
        guard let selectedId = config.selectedOrganizationPresetId,
              let index = storage.organizationPresets.firstIndex(where: { $0.id == selectedId }) else { return }
        var preset = storage.organizationPresets[index]
        preset.copyFolderContents = config.copyFolderContents
        preset.runInParallel = config.runInParallel
        preset.engineOptions = config.engineOptions
        preset.logEnabled = config.logEnabled
        preset.logLocation = config.logLocation
        preset.customLogPath = config.customLogPath
        preset.logFileNameTemplate = config.logFileNameTemplate
        preset.duplicatePolicy = config.duplicatePolicy
        preset.duplicateCounterTemplate = config.duplicateCounterTemplate
        preset.folderTemplate = config.organizationFolderTemplate
        preset.renameTemplate = config.organizationRenameTemplate
        preset.useFolderTemplate = config.organizationUseFolderTemplate
        preset.useRenameTemplate = config.organizationUseRenameTemplate
        preset.renameOnlyPatterns = config.organizationRenameOnlyPatterns
        preset.includePatterns = config.organizationIncludePatterns
        preset.excludePatterns = config.organizationExcludePatterns
        preset.copyOnlyPatterns = config.organizationCopyOnlyPatterns
        preset.useCustomDate = config.organizationUseCustomDate
        preset.customDate = config.organizationCustomDate
        storage.organizationPresets[index] = preset
        storage.save()
    }

    /// Saves the film's current settings as a new shared preset. The film keeps its
    /// own copy; a film that had no folder settings of its own starts using them.
    func saveCurrentSettingsAsPreset() {
        objectWillChange.send()
        var preset: OrganizationPreset
        if let id = config.selectedOrganizationPresetId,
           let own = storage.organizationPresets.first(where: { $0.id == id }) {
            // The film's copy already carries everything, sound folders included.
            preset = own
            preset.id = UUID()
            preset.ownerFilmId = nil
        } else {
            preset = OrganizationPreset()
            preset.folderTemplate = config.organizationFolderTemplate
            preset.renameTemplate = config.organizationRenameTemplate
            preset.useFolderTemplate = config.organizationUseFolderTemplate
            preset.useRenameTemplate = config.organizationUseRenameTemplate
            preset.renameOnlyPatterns = config.organizationRenameOnlyPatterns
            preset.includePatterns = config.organizationIncludePatterns
            preset.excludePatterns = config.organizationExcludePatterns
            preset.copyOnlyPatterns = config.organizationCopyOnlyPatterns
            preset.useCustomDate = config.organizationUseCustomDate
            preset.customDate = config.organizationCustomDate
        }
        preset.copyFolderContents = config.copyFolderContents
        preset.runInParallel = config.runInParallel
        preset.engineOptions = config.engineOptions
        preset.logEnabled = config.logEnabled
        preset.logLocation = config.logLocation
        preset.customLogPath = config.customLogPath
        preset.logFileNameTemplate = config.logFileNameTemplate
        preset.duplicatePolicy = config.duplicatePolicy
        preset.duplicateCounterTemplate = config.duplicateCounterTemplate

        let sharedNames = Set(sharedOrganizationPresets.map(\.name))
        if config.selectedOrganizationPresetId == nil || sharedNames.contains(preset.name) {
            preset.name = FilmPresetOwnership.nextSharedName(in: storage.organizationPresets)
        }
        storage.organizationPresets.append(preset)
        if config.selectedOrganizationPresetId == nil {
            config.selectedOrganizationPresetId = replaceOwnCopy(with: preset)
        }
        storage.save()
        save()
    }

    /// Deletes a shared preset. Films that started from it keep their own copy.
    func deleteSharedPreset(id: UUID) {
        objectWillChange.send()
        storage.organizationPresets.removeAll { $0.id == id && $0.ownerFilmId == nil }
        storage.save()
    }

    func addOrganizationPreset() {
        objectWillChange.send()
        var preset = OrganizationPreset()
        preset.name = FilmPresetOwnership.nextSharedName(in: storage.organizationPresets)
        preset.folderTemplate = ""
        preset.renameTemplate = ""
        preset.useFolderTemplate = false
        preset.useRenameTemplate = false
        preset.renameOnlyPatterns = []
        storage.organizationPresets.append(preset)
        config.mirrorOrganization(from: preset)
        config.selectedOrganizationPresetId = replaceOwnCopy(with: preset)
        storage.save()
        save()
    }
    
    func deleteOrganizationPreset(id: UUID) {
        objectWillChange.send()
        let wasSelected = config.selectedOrganizationPresetId == id
        storage.organizationPresets.removeAll { $0.id == id }
        if wasSelected {
            // Never fall back to another record: it could be another film's copy.
            applyOffOrganizationSettings()
        }
        storage.save()
        save()
    }
    
    // Validation
    func validate() -> Bool {
        if config.sourceAutoDetectEnabled {
            refreshAutoDetectedSources()
        }
        if config.soundAutoDetectEnabled {
            refreshAutoDetectedSoundSources()
        }
        if config.cardAutoDetectEnabled {
            refreshAutoDetectedCards()
        }
        if config.includedSourcePaths.isEmpty {
            validationMessage = "Please add at least one source file or folder"
            showValidationError = true
            return false
        }
        
        if config.includedDestinationPaths.isEmpty {
            validationMessage = "Please add at least one destination folder"
            showValidationError = true
            return false
        }
        
        let fm = FileManager.default
        
        // Validate sources exist and are accessible
        for src in config.includedSourcePaths {
            if !fm.fileExists(atPath: src) {
                validationMessage = "Source does not exist: \(src)"
                showValidationError = true
                return false
            }
            
            // Check if source is readable
            if !fm.isReadableFile(atPath: src) {
                validationMessage = "Permission denied: Cannot read source \((src as NSString).lastPathComponent)"
                showValidationError = true
                return false
            }
        }

        func normalizedPath(_ path: String) -> String {
            URL(fileURLWithPath: path)
                .standardizedFileURL
                .resolvingSymlinksInPath()
                .path
        }

        // Prevent destinations inside sources (and exact matches).
        let normalizedSources = config.includedSourcePaths.map(normalizedPath)
        let normalizedDestinations = config.includedDestinationPaths.map(normalizedPath)
        for sourcePath in normalizedSources {
            var isDirectory: ObjCBool = false
            _ = fm.fileExists(atPath: sourcePath, isDirectory: &isDirectory)
            let sourceName = (sourcePath as NSString).lastPathComponent
            let sourcePrefix = sourcePath.hasSuffix("/") ? sourcePath : sourcePath + "/"
            for destPath in normalizedDestinations {
                if destPath == sourcePath {
                    validationMessage = "Source and destination are the same: \(sourceName)"
                    showValidationError = true
                    return false
                }
                if isDirectory.boolValue, destPath.hasPrefix(sourcePrefix) {
                    let destName = (destPath as NSString).lastPathComponent
                    validationMessage = "Destination “\(destName)” is inside source “\(sourceName)”. Choose a destination outside the source folder."
                    showValidationError = true
                    return false
                }
            }
        }
        
        // Validate destinations
        for dest in config.includedDestinationPaths {
            let summary = DriveUtilities.summary(for: dest)
            if summary.isReadOnly == true {
                let formatLabel = summary.formatLabel.map { " (\($0))" } ?? ""
                validationMessage = "Destination is read-only\(formatLabel): \(dest)"
                showValidationError = true
                return false
            }
            if !fm.fileExists(atPath: dest) {
                // Try to create it
                do {
                    try fm.createDirectory(atPath: dest, withIntermediateDirectories: true)
                } catch {
                    validationMessage = "Cannot create destination folder: \(dest)\n\(error.localizedDescription)"
                    showValidationError = true
                    return false
                }
            }
            
            // Check if destination is writable
            if !fm.isWritableFile(atPath: dest) {
                validationMessage = "Permission denied: Cannot write to \((dest as NSString).lastPathComponent)"
                showValidationError = true
                return false
            }
        }
        
        showValidationError = false
        return true
    }
    
    // Persistence
    func save() {
        storage.update(config)
        if config.selectedOrganizationPresetId != nil && !isSyncingFromPreset {
            updateSelectedPresetFromCurrent()
        }
    }
}
