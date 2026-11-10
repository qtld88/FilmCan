import AppKit
import Combine
import Foundation

/// State of ONE Quick Copy window: the form, the background worker and the
/// setup → running → finished lifecycle.
@MainActor
final class QuickCopySession: ObservableObject, Identifiable {

    enum Phase { case setup, running, finished }

    static let lastPresetKey = "quickCopy.lastPresetId"
    static let lastDestinationsKey = "quickCopy.lastDestinations"
    static let lastFilmKey = "quickCopy.lastFilmId"

    let id = UUID()
    @Published var form: QuickCopyFormModel
    @Published private(set) var phase: Phase = .setup
    /// Set when the user asked to stop; drives the "Stopping…" button state.
    @Published private(set) var stopRequested = false
    /// Total bytes per selected item, filled in off the main thread.
    @Published private(set) var sizes: [String: Int64] = [:]
    /// Read on a timer, not on every redraw: free space includes purgeable space
    /// that macOS reclaims at any moment, so per-redraw reads made the bars jump
    /// whenever an unrelated control changed.
    @Published private(set) var capacities: [String: (total: Int64?, available: Int64?)] = [:]

    let worker = TransferViewModel(isBackgroundWorker: true)
    weak var window: NSWindow?
    var windowClosed = false
    /// Called on the main actor when the run ends (success, failure or stop).
    var onFinished: (() -> Void)?

    private let storage: ConfigurationStorage
    private let defaults: UserDefaults
    private var workerObserver: AnyCancellable?
    private var stopTask: Task<Void, Never>?

    init(paths: [String],
         storage: ConfigurationStorage? = nil,
         defaults: UserDefaults = .standard) {
        let storage = storage ?? ConfigurationStorage.shared
        self.storage = storage
        self.defaults = defaults

        var form = QuickCopyFormModel(items: QuickCopyFormModel.items(for: paths))
        form.savedPresets = storage.organizationPresets
        // Quick Copy keeps its own "last used" keys — never the main app's lastUsedConfigId.
        if let raw = defaults.string(forKey: Self.lastPresetKey),
           let presetId = UUID(uuidString: raw),
           form.savedPresets.contains(where: { $0.id == presetId }) {
            form.selectedPresetId = presetId
        }
        form.savedFilms = storage.configurations
        if let raw = defaults.string(forKey: Self.lastFilmKey),
           let filmId = UUID(uuidString: raw),
           form.savedFilms.contains(where: { $0.id == filmId }) {
            form.selectFilm(filmId)
        }
        form.destinations = (defaults.stringArray(forKey: Self.lastDestinationsKey) ?? [])
            .filter { FileManager.default.fileExists(atPath: $0) }
        self.form = form

        workerObserver = worker.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        loadSizes()
        refreshCapacities()
    }

    func refreshCapacities() {
        capacities = Dictionary(form.destinations.map { ($0, DriveUtilities.capacity(for: $0)) },
                                uniquingKeysWith: { first, _ in first })
    }

    /// True as soon as every destination has its result (or the run was already
    /// backed up) — before `startTransfer` has finished history/notifications.
    var resultsComplete: Bool {
        phase == .finished
            || worker.alreadyBackedUp != nil
            || (!form.destinations.isEmpty
                && form.destinations.allSatisfy { d in worker.results.contains { $0.destination == d } })
    }

    var isRunning: Bool { phase == .running && !resultsComplete }

    // MARK: Setup actions

    func addDestinationViaPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        addDestinations(panel.urls.map(\.path))
    }

    /// Folders only; dropped files are ignored. Duplicates are skipped.
    func addDestinations(_ paths: [String]) {
        guard phase == .setup else { return }
        for path in paths where !form.destinations.contains(path) && Self.isDirectory(path) {
            form.destinations.append(path)
        }
        refreshCapacities()
    }

    func addSourceViaPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        addSources(panel.urls.map(\.path))
    }

    func addSources(_ paths: [String]) {
        guard phase == .setup else { return }
        let known = Set(form.items.map(\.path))
        var seen = Set<String>()
        let fresh = paths.filter { !known.contains($0) && FileManager.default.fileExists(atPath: $0) && seen.insert($0).inserted }
        guard !fresh.isEmpty else { return }
        let added = QuickCopyFormModel.items(for: fresh)
        form.items.append(contentsOf: added)
        loadSizes(for: added)
    }

    private static func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    func removeSource(_ path: String) {
        guard form.items.count > 1 else { return }
        form.items.removeAll { $0.path == path }
    }

    func removeDestination(_ path: String) {
        form.destinations.removeAll { $0 == path }
    }

    /// Same form, fresh results. A re-run resumes from the on-disk manifest.
    func backToSetup() {
        guard phase == .finished else { return }
        worker.results = []
        worker.alreadyBackedUp = nil
        worker.progress.resetProgress()
        stopRequested = false
        phase = .setup
        refreshCapacities()
    }

    // MARK: Run / stop

    func run() {
        guard phase == .setup, form.canRun else { return }

        if let preset = form.makeSavedPreset() {
            storage.addPreset(preset)
            form.savedPresets = storage.organizationPresets
            form.selectedPresetId = preset.id
            form.savePresetName = ""
        }
        defaults.set(form.selectedPresetId?.uuidString, forKey: Self.lastPresetKey)
        defaults.set(form.destinations, forKey: Self.lastDestinationsKey)
        defaults.set(form.selectedFilmId?.uuidString, forKey: Self.lastFilmKey)

        let config = form.makeConfiguration()
        let preset = form.runPreset()
        let recordAs = form.selectedFilm.map { (id: $0.id, name: $0.name) }
        phase = .running

        Task { [weak self, worker] in
            await worker.startTransfer(config: config, organizationPresetOverride: preset,
                                       recordAs: recordAs)
            self?.finish()
        }
    }

    /// Stops the copy. Deletes nothing; re-running the Quick Copy resumes from the
    /// on-disk manifest and copies only what is missing.
    func stop() {
        guard isRunning else { return }
        stopRequested = true
        worker.cancelAll()
        unblockPendingPrompts()
        guard stopTask == nil else { return }
        // `startTransfer` resets the cancel flag and the engine service may not exist
        // yet, so a single cancel can be lost: re-assert until the run ends.
        stopTask = Task { [weak self] in
            while self?.reassertStop() == true {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }

    private func reassertStop() -> Bool {
        guard phase == .running, !Task.isCancelled else { return false }
        if isRunning {
            worker.cancelAll()
            unblockPendingPrompts()
        }
        return true
    }

    /// A pending prompt holds a continuation inside the engine: answer it so the
    /// cancel cannot hang.
    private func unblockPendingPrompts() {
        if worker.activeRollIdentityPrompt != nil {
            worker.submitRollIdentity(isResume: true)
        }
        if !worker.pendingUnreadableFiles.isEmpty {
            worker.resolveUnreadable(proceed: false)
        }
        if worker.activeDuplicatePrompt != nil {
            worker.submitDuplicateResolution(action: .skip, applyToAll: true)
        }
    }

    private func finish() {
        stopTask?.cancel()
        stopTask = nil
        phase = .finished
        onFinished?()
    }

    // MARK: Sizes

    private func loadSizes(for items: [QuickCopyFormModel.Item]? = nil) {
        for item in items ?? form.items {
            let path = item.path
            Task { @MainActor [weak self] in
                let bytes = await Task.detached(priority: .utility) {
                    PreviewCalculator.calculateTotalsAndSizes(for: [path]).0
                }.value
                self?.sizes[path] = bytes
            }
        }
    }
}

#if DEBUG
extension QuickCopySession {
    func applyDemo(_ settings: DemoSettings) {
        form.destinations = settings.quickCopyDestinations.filter { FileManager.default.fileExists(atPath: $0) }
        refreshCapacities()
        guard settings.state != .setup else { return }
        worker.applyDemoRun(configId: nil,
                            sources: form.items.map(\.path),
                            destinations: form.destinations,
                            verifyMode: form.effectiveVerification,
                            settings: settings)
        phase = settings.state == .done ? .finished : .running
    }
}
#endif
