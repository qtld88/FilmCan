import XCTest
import Combine
@testable import FilmCan

@MainActor
final class OrganizationEditorModelTests: XCTestCase {
    private func makeVM() -> BackupEditorViewModel {
        BackupEditorViewModel(config: BackupConfiguration())
    }

    func test_readsThroughToViewModel() {
        let vm = makeVM(); vm.episode = "EP101"
        let model = OrganizationEditorModel(viewModel: vm)
        XCTAssertEqual(model.episode, "EP101")
    }

    func test_writeThroughPersists() {
        let vm = makeVM()
        let model = OrganizationEditorModel(viewModel: vm)
        model.episode = "EP202"
        XCTAssertEqual(vm.episode, "EP202")
        XCTAssertEqual(vm.config.episode, "EP202")
    }

    func test_publishesOnOrgEdit() {
        let vm = makeVM()
        let model = OrganizationEditorModel(viewModel: vm)
        var fired = false
        let c = model.objectWillChange.sink { _ in fired = true }
        model.cameraFolderTemplate = "ARRI/{date}"
        XCTAssertTrue(fired); c.cancel()
    }

    func test_doesNotPublishOnUnrelatedViewModelChange() {
        let vm = makeVM()
        let model = OrganizationEditorModel(viewModel: vm)
        var fired = false
        let c = model.objectWillChange.sink { _ in fired = true }
        vm.sourceAutoDetectEnabled.toggle()
        XCTAssertFalse(fired); c.cancel()
    }
}
