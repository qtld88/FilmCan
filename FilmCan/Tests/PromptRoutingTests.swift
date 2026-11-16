import XCTest
@testable import FilmCan

/// Engine pre-copy prompts suspend a run on a CheckedContinuation. Every one must
/// reach a visible sheet and every continuation must be resumed, or the run hangs
/// forever in "Preparing".
@MainActor
final class PromptRoutingTests: XCTestCase {

    private func makeDuplicatePrompt() -> DuplicatePrompt {
        DuplicatePrompt(sourcePath: "/src/A001", destinationPath: "/dst/A001", isDirectory: true,
                        counterTemplate: "_{n}", canVerifyWithHashList: false, hashListMissing: false)
    }

    private func makeRollPrompt(_ recommendation: RollIdentityRecommendation) -> RollIdentityPrompt {
        RollIdentityPrompt(rollName: "A001", recommendation: recommendation, sourceVolumeName: "CARD",
                           recordedVolumeName: "CARD", recordedLastSeen: nil, proposedNewName: "A001-2")
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool,
                           file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(condition(), "condition never became true", file: file, line: line)
    }

    // MARK: - Concurrent worker prompts reach the main view model

    func test_workerDuplicatePrompt_surfacesOnMainAndResumesWorker() async {
        let main = TransferViewModel()
        let worker = TransferViewModel(isBackgroundWorker: true)
        main.registerConcurrentWorker(worker, configId: UUID())

        let answered = expectation(description: "worker resumed")
        Task {
            let resolution = await worker.resolveDuplicate(prompt: self.makeDuplicatePrompt())
            XCTAssertEqual(resolution.action, .overwrite)
            answered.fulfill()
        }

        await waitUntil { main.activeDuplicatePrompt != nil }
        main.submitDuplicateResolution(action: .overwrite, applyToAll: false)
        await fulfillment(of: [answered], timeout: 2)
        XCTAssertNil(main.activeDuplicatePrompt)
    }

    func test_workerRollIdentityPrompt_surfacesOnMainAndResumesWorker() async {
        let main = TransferViewModel()
        let worker = TransferViewModel(isBackgroundWorker: true)
        main.registerConcurrentWorker(worker, configId: UUID())

        let answered = expectation(description: "worker resumed")
        Task {
            let isResume = await worker.resolveRollIdentity(prompt: self.makeRollPrompt(.unknown))
            XCTAssertFalse(isResume)
            answered.fulfill()
        }

        await waitUntil { main.activeRollIdentityPrompt != nil }
        main.submitRollIdentity(isResume: false)
        await fulfillment(of: [answered], timeout: 2)
    }

    func test_workerUnreadablePrompt_surfacesOnMainAndResumesWorker() async {
        let main = TransferViewModel()
        let worker = TransferViewModel(isBackgroundWorker: true)
        main.registerConcurrentWorker(worker, configId: UUID())

        let answered = expectation(description: "worker resumed")
        Task {
            let proceed = await worker.resolveUnreadable(paths: ["/src/A001/bad.mov"])
            XCTAssertTrue(proceed)
            answered.fulfill()
        }

        await waitUntil { !main.pendingUnreadableFiles.isEmpty }
        main.resolveUnreadable(proceed: true)
        await fulfillment(of: [answered], timeout: 2)
    }

    func test_cancellingWorkerFromItsPrompt_resumesWorkerOnly() async {
        let main = TransferViewModel()
        let worker = TransferViewModel(isBackgroundWorker: true)
        let configId = UUID()
        main.registerConcurrentWorker(worker, configId: configId)

        let answered = expectation(description: "worker resumed")
        Task {
            let resolution = await worker.resolveDuplicate(prompt: self.makeDuplicatePrompt())
            XCTAssertEqual(resolution.action, .skip)
            answered.fulfill()
        }

        await waitUntil { main.activeDuplicatePrompt != nil }
        main.cancelRunFromDuplicatePrompt()
        await fulfillment(of: [answered], timeout: 2)
        XCTAssertFalse(main.isCancellingAll, "cancelling a worker's prompt must not cancel the main run")
    }

    // MARK: - Coordinator never drops a continuation

    func test_reset_resumesPendingUnreadable() async {
        let coordinator = DuplicatePromptCoordinator()
        let answered = expectation(description: "unreadable resumed")
        Task {
            let proceed = await withCheckedContinuation { continuation in
                coordinator.setUnreadableContinuation(continuation, paths: ["/x"])
            }
            XCTAssertFalse(proceed)
            answered.fulfill()
        }
        await waitUntil { !coordinator.pendingUnreadableFiles.isEmpty }
        coordinator.reset()
        await fulfillment(of: [answered], timeout: 2)
    }

    func test_reset_resumesActiveAndQueuedDuplicates() async {
        let coordinator = DuplicatePromptCoordinator()
        let answered = expectation(description: "duplicates resumed")
        answered.expectedFulfillmentCount = 2
        for _ in 0..<2 {
            Task {
                let resolution = await coordinator.resolveDuplicate(prompt: self.makeDuplicatePrompt())
                XCTAssertEqual(resolution.action, .skip)
                answered.fulfill()
            }
        }
        await waitUntil { coordinator.activeDuplicatePrompt != nil }
        coordinator.reset()
        await fulfillment(of: [answered], timeout: 2)
    }

    func test_dismissingRollIdentitySheet_resumesWithRecommendation() async {
        let coordinator = DuplicatePromptCoordinator()
        let answered = expectation(description: "roll resumed")
        Task {
            let isResume = await coordinator.resolveRollIdentity(prompt: self.makeRollPrompt(.newCard))
            XCTAssertFalse(isResume)
            answered.fulfill()
        }
        await waitUntil { coordinator.activeRollIdentityPrompt != nil }
        coordinator.dismissRollIdentityPrompt(id: coordinator.activeRollIdentityPrompt!.id)
        await fulfillment(of: [answered], timeout: 2)
    }

    func test_dismissingSheetViaBinding_resumesContinuation() async {
        let vm = TransferViewModel()
        let answered = expectation(description: "roll resumed")
        Task {
            _ = await vm.resolveRollIdentity(prompt: self.makeRollPrompt(.resumeSameCard))
            answered.fulfill()
        }
        await waitUntil { vm.activeRollIdentityPrompt != nil }
        vm.dismissRollIdentityPrompt(id: vm.activeRollIdentityPrompt!.id)   // the sheet binding's nil write
        XCTAssertNil(vm.activeRollIdentityPrompt)
        await fulfillment(of: [answered], timeout: 2)
    }

    func test_staleDismissal_doesNotAnswerTheNextQueuedPrompt() async {
        let coordinator = DuplicatePromptCoordinator()
        let answered = expectation(description: "both resumed")
        answered.expectedFulfillmentCount = 2
        for _ in 0..<2 {
            Task {
                _ = await coordinator.resolveDuplicate(prompt: self.makeDuplicatePrompt())
                answered.fulfill()
            }
        }
        await waitUntil { coordinator.activeDuplicatePrompt != nil }
        let first = coordinator.activeDuplicatePrompt!.id
        coordinator.submitDuplicateResolution(action: .overwrite, applyToAll: false)
        await waitUntil { coordinator.activeDuplicatePrompt != nil }
        coordinator.dismissDuplicatePrompt(id: first)   // late write from the first sheet
        XCTAssertNotNil(coordinator.activeDuplicatePrompt, "second prompt must stay up for the user")
        coordinator.submitDuplicateResolution(action: .skip, applyToAll: false)
        await fulfillment(of: [answered], timeout: 2)
    }

    func test_cancelledRun_autoAnswersLatePrompts() async {
        let vm = TransferViewModel(isBackgroundWorker: true)
        vm.cancelAll()
        let resolution = await vm.resolveDuplicate(prompt: makeDuplicatePrompt())
        XCTAssertEqual(resolution.action, .skip)
        let proceed = await vm.resolveUnreadable(paths: ["/x"])
        XCTAssertFalse(proceed)
        let isResume = await vm.resolveRollIdentity(prompt: makeRollPrompt(.unknown))
        XCTAssertTrue(isResume)
    }
}
