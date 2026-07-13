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

    private struct PendingDuplicatePrompt {
        let prompt: DuplicatePrompt
        let continuation: CheckedContinuation<DuplicateResolution, Never>
    }

    func resolveDuplicate(prompt: DuplicatePrompt) async -> DuplicateResolution {
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

    func reset() {
        activeDuplicatePrompt = nil
        cachedDuplicateResolution = nil
        pendingDuplicatePrompts = []
        activeDuplicateContinuation = nil
        isShowingDuplicatePrompt = false
        unreadableContinuation = nil
        let roll = rollIdentityContinuation
        rollIdentityContinuation = nil
        activeRollIdentityPrompt = nil
        roll?.resume(returning: true)  // unblock any pending run on reset (defaults to resume)
    }

    /// Suspend until the user resolves a roll-identity prompt; returns true to resume
    /// into the existing roll, false to save the source as a fresh "-N" roll.
    func resolveRollIdentity(prompt: RollIdentityPrompt) async -> Bool {
        await withCheckedContinuation { continuation in
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
        unreadableContinuation = continuation
        pendingUnreadableFiles = paths
    }
}
