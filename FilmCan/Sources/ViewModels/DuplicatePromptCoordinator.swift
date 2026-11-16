import Foundation

/// UI-facing description of a cross-run roll-name clash (a same-named roll already
/// exists at a destination). Carries the engine's recommendation so the sheet can
/// pre-select it while still letting the user override.
struct RollIdentityPrompt: Identifiable {
    let id = UUID()
    let rollName: String
    let recommendation: RollIdentityRecommendation
    let sourceVolumeName: String
    let recordedVolumeName: String?
    let recordedLastSeen: Date?
    let proposedNewName: String
}

@MainActor
final class DuplicatePromptCoordinator: ObservableObject {
    @Published var activeDuplicatePrompt: DuplicatePrompt? = nil
    @Published var pendingUnreadableFiles: [String] = []
    @Published var activeRollIdentityPrompt: RollIdentityPrompt? = nil

    private var pendingDuplicatePrompts: [PendingDuplicatePrompt] = []
    private var activeDuplicateContinuation: CheckedContinuation<DuplicateResolution, Never>? = nil
    private var cachedDuplicateResolution: DuplicateResolution? = nil
    private var isShowingDuplicatePrompt = false
    private var unreadableContinuation: CheckedContinuation<Bool, Never>? = nil
    private var rollIdentityContinuation: CheckedContinuation<Bool, Never>? = nil
    private var isClosed = false

    private struct PendingDuplicatePrompt {
        let prompt: DuplicatePrompt
        let continuation: CheckedContinuation<DuplicateResolution, Never>
    }

    func resolveDuplicate(prompt: DuplicatePrompt) async -> DuplicateResolution {
        if isClosed {
            return DuplicateResolution(action: .skip, applyToAll: false, counterTemplate: nil)
        }
        if let cached = cachedDuplicateResolution {
            return cached
        }
        return await withCheckedContinuation { continuation in
            let pending = PendingDuplicatePrompt(prompt: prompt, continuation: continuation)
            pendingDuplicatePrompts.append(pending)
            if !isShowingDuplicatePrompt {
                presentNextDuplicatePrompt()
            }
        }
    }

    func submitDuplicateResolution(
        action: OrganizationPreset.DuplicatePolicy,
        applyToAll: Bool,
        counterTemplate: String? = nil
    ) {
        let resolution = DuplicateResolution(
            action: action,
            applyToAll: applyToAll,
            counterTemplate: counterTemplate
        )
        if applyToAll {
            cachedDuplicateResolution = resolution
        }

        activeDuplicatePrompt = nil
        activeDuplicateContinuation?.resume(returning: resolution)
        activeDuplicateContinuation = nil

        if applyToAll {
            let pending = pendingDuplicatePrompts
            pendingDuplicatePrompts.removeAll()
            isShowingDuplicatePrompt = false
            pending.forEach { $0.continuation.resume(returning: resolution) }
            return
        }

        if pendingDuplicatePrompts.isEmpty {
            isShowingDuplicatePrompt = false
            return
        }
        presentNextDuplicatePrompt()
    }

    private func presentNextDuplicatePrompt() {
        guard !pendingDuplicatePrompts.isEmpty else {
            isShowingDuplicatePrompt = false
            return
        }
        let next = pendingDuplicatePrompts.removeFirst()
        activeDuplicateContinuation = next.continuation
        activeDuplicatePrompt = next.prompt
        isShowingDuplicatePrompt = true
    }

    /// True while any engine-blocking prompt is waiting on the user.
    var hasActivePrompt: Bool {
        activeDuplicatePrompt != nil || activeRollIdentityPrompt != nil || !pendingUnreadableFiles.isEmpty
    }

    /// Unblocks every suspended engine callback with a non-destructive answer
    /// (skip duplicates, abort on unreadable files, resume the roll). A continuation
    /// that is dropped instead of resumed hangs its run forever in "Preparing".
    func resolveAllPending() {
        let skip = DuplicateResolution(action: .skip, applyToAll: false, counterTemplate: nil)
        let duplicateContinuations = [activeDuplicateContinuation].compactMap { $0 }
            + pendingDuplicatePrompts.map(\.continuation)
        activeDuplicatePrompt = nil
        activeDuplicateContinuation = nil
        pendingDuplicatePrompts = []
        isShowingDuplicatePrompt = false
        duplicateContinuations.forEach { $0.resume(returning: skip) }

        resolveUnreadable(proceed: false)
        submitRollIdentity(isResume: true)
    }

    /// Run cancelled: answer everything pending, and auto-answer any prompt the
    /// engine still raises while it unwinds, since nobody is left to show it.
    func close() {
        isClosed = true
        resolveAllPending()
    }

    func reset() {
        resolveAllPending()
        cachedDuplicateResolution = nil
        isClosed = false
    }

    /// The sheet went away without a button press: answer as the sheet's
    /// safest default so the engine is never left suspended.
    func dismissDuplicatePrompt(id: UUID) {
        guard activeDuplicatePrompt?.id == id else { return }
        submitDuplicateResolution(action: .skip, applyToAll: false)
    }

    func dismissRollIdentityPrompt(id: UUID) {
        guard let prompt = activeRollIdentityPrompt, prompt.id == id else { return }
        submitRollIdentity(isResume: prompt.recommendation != .newCard)
    }

    func dismissUnreadablePrompt(paths: [String]) {
        guard !paths.isEmpty, pendingUnreadableFiles == paths else { return }
        resolveUnreadable(proceed: false)
    }

    /// Suspend until the user resolves a roll-identity prompt; returns true to resume
    /// into the existing roll, false to save the source as a fresh "-N" roll.
    func resolveRollIdentity(prompt: RollIdentityPrompt) async -> Bool {
        if isClosed { return true }
        return await withCheckedContinuation { continuation in
            rollIdentityContinuation = continuation
            activeRollIdentityPrompt = prompt
        }
    }

    func submitRollIdentity(isResume: Bool) {
        let c = rollIdentityContinuation
        rollIdentityContinuation = nil
        activeRollIdentityPrompt = nil
        c?.resume(returning: isResume)
    }

    func resolveUnreadable(proceed: Bool) {
        let c = unreadableContinuation
        unreadableContinuation = nil
        pendingUnreadableFiles = []
        c?.resume(returning: proceed)
    }

    func setUnreadableContinuation(_ continuation: CheckedContinuation<Bool, Never>, paths: [String]) {
        if isClosed {
            continuation.resume(returning: false)
            return
        }
        unreadableContinuation = continuation
        pendingUnreadableFiles = paths
    }
}
