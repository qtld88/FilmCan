import Foundation

@MainActor
final class DuplicatePromptCoordinator: ObservableObject {
    @Published var activeDuplicatePrompt: DuplicatePrompt? = nil
    @Published var pendingUnreadableFiles: [String] = []

    private var pendingDuplicatePrompts: [PendingDuplicatePrompt] = []
    private var activeDuplicateContinuation: CheckedContinuation<DuplicateResolution, Never>? = nil
    private var cachedDuplicateResolution: DuplicateResolution? = nil
    private var isShowingDuplicatePrompt = false
    private var unreadableContinuation: CheckedContinuation<Bool, Never>? = nil

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
