import XCTest
@testable import FilmCan

final class RecognitionGuideTests: XCTestCase {

    /// A family added to the detector must show on the page, with a name and a sentence.
    func test_everyDetectorFamily_isOnThePage() {
        let families = RecognitionGuide.families
        XCTAssertEqual(families.map(\.id), CameraBrand.allCases.map(\.rawValue))
        for brand in CameraBrand.allCases {
            guard let family = families.first(where: { $0.id == brand.rawValue }) else {
                XCTFail("\(brand) is missing from the Recognition page"); continue
            }
            XCTAssertEqual(family.name, brand.displayName)
            XCTAssertFalse(family.name.trimmingCharacters(in: .whitespaces).isEmpty, "\(brand)")
            XCTAssertFalse(family.recognisedBy.trimmingCharacters(in: .whitespaces).isEmpty, "\(brand)")
            XCTAssertEqual(family.isSound, brand.isSound)
        }
    }

    func test_signals_arePlainSentences() {
        XCTAssertFalse(RecognitionGuide.signals.isEmpty)
        XCTAssertEqual(Set(RecognitionGuide.signals).count, RecognitionGuide.signals.count)
        for sentence in RecognitionGuide.signals
            + [RecognitionGuide.whereToSwitch, RecognitionGuide.forgetCorrectionHelp, RecognitionGuide.forgetRollHelp] {
            XCTAssertTrue(sentence.hasSuffix("."), sentence)
            XCTAssertFalse(sentence.contains("{"), sentence)
        }
    }

    func test_recognitionPage_isInTheSidebar_withAPlainTitle() {
        XCTAssertTrue(SettingsPage.allCases.contains(.recognition))
        XCTAssertEqual(SettingsPage.page(for: "recognition"), .recognition)
        XCTAssertFalse(SettingsPage.recognition.icon.isEmpty)
    }
}

final class CardRoleOverridesTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "filmcan.tests.cardRoleOverrides"

    override func setUp() {
        super.setUp()
        UserDefaults().removePersistentDomain(forName: suite)
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func test_set_remembersRoleNameAndDate() {
        let when = Date(timeIntervalSince1970: 1_800_000_000)
        CardRoleOverrides.set(.sound, forVolumeUUID: "U1", driveName: "ZOOM_F8", now: when, defaults: defaults)
        XCTAssertEqual(CardRoleOverrides.role(forVolumeUUID: "U1", defaults: defaults), .sound)
        XCTAssertEqual(CardRoleOverrides.all(defaults: defaults), ["U1": .sound])
        XCTAssertEqual(CardRoleOverrides.details(defaults: defaults)["U1"],
                       CardRoleOverrides.Detail(name: "ZOOM_F8", date: when))
        // The correction itself keeps the format earlier versions read: [drive id: role].
        XCTAssertEqual(defaults.dictionary(forKey: "filmcan.cardRoleOverrides") as? [String: String], ["U1": "sound"])
    }

    func test_forget_removesRoleAndDetail() {
        CardRoleOverrides.set(.notACard, forVolumeUUID: "U1", driveName: "SSD", defaults: defaults)
        CardRoleOverrides.set(.camera, forVolumeUUID: "U2", driveName: "A001", defaults: defaults)
        CardRoleOverrides.set(nil, forVolumeUUID: "U1", defaults: defaults)
        XCTAssertNil(CardRoleOverrides.role(forVolumeUUID: "U1", defaults: defaults))
        XCTAssertEqual(CardRoleOverrides.all(defaults: defaults), ["U2": .camera])
        XCTAssertNil(CardRoleOverrides.details(defaults: defaults)["U1"])
        XCTAssertNotNil(CardRoleOverrides.details(defaults: defaults)["U2"])
    }

    /// A correction saved by an earlier version: a plain [uuid: role] dictionary, no details.
    func test_correctionFromAnEarlierVersion_stillApplies_andIsListed() {
        defaults.set(["OLD": "notACard", "ODD": "somethingElse"], forKey: "filmcan.cardRoleOverrides")
        XCTAssertEqual(CardRoleOverrides.role(forVolumeUUID: "OLD", defaults: defaults), .notACard)
        XCTAssertEqual(CardRoleOverrides.all(defaults: defaults), ["OLD": .notACard])
        XCTAssertTrue(CardRoleOverrides.details(defaults: defaults).isEmpty)

        let listed = RecognitionMemory.corrections(overrides: CardRoleOverrides.all(defaults: defaults),
                                                   details: [:], mountedNames: [:])
        XCTAssertEqual(listed.count, 1)
        XCTAssertNil(listed[0].driveName)
        XCTAssertNil(listed[0].date)
        XCTAssertTrue(listed[0].title.contains("OLD"))
    }
}

final class RecognitionMemoryTests: XCTestCase {

    func test_corrections_connectedFirst_thenByName_mountedNameWins() {
        let listed = RecognitionMemory.corrections(
            overrides: ["U1": .camera, "U2": .sound, "U3": .notACard],
            details: ["U1": .init(name: "B_CARD", date: nil),
                      "U2": .init(name: "OLD_NAME", date: Date(timeIntervalSince1970: 10)),
                      "U3": .init(name: "A_SSD", date: nil)],
            mountedNames: ["U2": "ZOOM"])
        XCTAssertEqual(listed.map(\.volumeUUID), ["U2", "U3", "U1"])
        XCTAssertEqual(listed[0].driveName, "ZOOM")
        XCTAssertTrue(listed[0].isConnected)
        XCTAssertEqual(listed[0].roleLabel, "Sound card")
        XCTAssertEqual(listed[1].roleLabel, "Not a card")
        XCTAssertEqual(listed[2].roleLabel, "Camera card")
        XCTAssertFalse(listed[2].isConnected)
    }

    func test_splitCardKey() {
        XCTAssertEqual(RecognitionMemory.splitCardKey("ABC|").uuid, "ABC")
        XCTAssertEqual(RecognitionMemory.splitCardKey("ABC|").folder, "")
        XCTAssertEqual(RecognitionMemory.splitCardKey("ABC|DCIM/Day 1|x").folder, "DCIM/Day 1|x")
        XCTAssertNil(RecognitionMemory.splitCardKey("nouuid|clips").uuid)
        XCTAssertEqual(RecognitionMemory.splitCardKey("nouuid|clips").folder, "clips")
        XCTAssertNil(RecognitionMemory.splitCardKey("odd").uuid)
    }

    func test_rolls_groupedByMovie_deletedMoviesLast_emptyLeftOut() {
        let a = UUID(), b = UUID(), gone = UUID()
        var stateA = RollNumberingStore.ConfigState()
        stateA.assignments = ["U1|": "A002", "U2|": "A001", "nouuid|sub": "S001"]
        stateA.lastRunDate = Date(timeIntervalSince1970: 100)
        var stateGone = RollNumberingStore.ConfigState()
        stateGone.assignments = ["U9|": "A001"]
        let listed = RecognitionMemory.rolls(
            states: [a.uuidString: stateA, b.uuidString: RollNumberingStore.ConfigState(), gone.uuidString: stateGone],
            movies: [(id: b, name: "Empty"), (id: a, name: "Citizen K")],
            mountedNames: ["U2": "CARD_2"])
        XCTAssertEqual(listed.map(\.title), ["Citizen K", "Deleted movie"])
        XCTAssertEqual(listed[0].rolls.map(\.rollName), ["A001", "A002", "S001"])
        XCTAssertEqual(listed[0].rolls[0].driveName, "CARD_2")
        XCTAssertNil(listed[0].rolls[1].driveName)
        XCTAssertEqual(listed[0].rolls[2].folder, "sub")
        XCTAssertEqual(listed[0].lastRun, Date(timeIntervalSince1970: 100))
        XCTAssertEqual(listed[1].rolls.map(\.rollName), ["A001"])
    }
}

@MainActor
final class RollMemoryForgetTests: XCTestCase {

    func test_forgetAssignment_removesOneCard_andIsSaved() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("filmcan-roll-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("roll-numbering.json")
        let film = UUID(), other = UUID()

        let store = RollNumberingStore(fileURL: file)
        var state = RollNumberingStore.ConfigState()
        state.assignments = ["U1|": "A001", "U2|": "A002"]
        state.currentDay = "Day03"
        store.update(state, for: film)
        store.update(state, for: other)

        store.forgetAssignment(cardKey: "U1|", rollName: "A001", configId: film.uuidString)
        store.forgetAssignment(cardKey: "missing|", rollName: "A001", configId: film.uuidString)
        store.forgetAssignment(cardKey: "U1|", rollName: "A001", configId: UUID().uuidString)
        // The page showed an old name for this card: nothing is forgotten.
        store.forgetAssignment(cardKey: "U2|", rollName: "A009", configId: film.uuidString)

        let reloaded = RollNumberingStore(fileURL: file)
        let kept = reloaded.state(for: film).assignments
        XCTAssertNil(kept["U1|"])
        XCTAssertEqual(kept["U2|"], "A002")
        XCTAssertEqual(reloaded.state(for: film).currentDay, "Day03")
        XCTAssertEqual(reloaded.state(for: other).assignments, ["U1|": "A001", "U2|": "A002"])
        XCTAssertEqual(reloaded.allStates.count, 2)

        // The forgotten name stays taken: neither the forgotten card nor a new one gets it.
        let next = RollNumberer.nextName(kind: .camera, settings: RollNumbering(), assigned: Array(kept.values))
        XCTAssertEqual(next, "A003")
    }

    /// Forgetting the highest name must not hand it to the next card: a roll folder
    /// of that name may be on a drive.
    func test_forgetHighestName_isNotReused_andIsNotListedAsACard() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("filmcan-roll-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = RollNumberingStore(fileURL: dir.appendingPathComponent("roll-numbering.json"))
        let film = UUID()
        var state = RollNumberingStore.ConfigState()
        state.assignments = ["U1|": "A001", "U2|": "A002", "U3|": "A003"]
        store.update(state, for: film)

        store.forgetAssignment(cardKey: "U3|", rollName: "A003", configId: film.uuidString)

        let existing = store.state(for: film).assignments
        let assigned = RollNumberer.assign(
            sources: ["/v/new", "/v/old"], isDirectory: { _ in true }, kinds: [:], settings: RollNumbering(),
            existing: existing, keyFor: { $0 == "/v/old" ? "U3|" : "U4|" }, signatureFor: { _ in nil })
        XCTAssertEqual(assigned.names["/v/new"], "A004")
        XCTAssertEqual(assigned.names["/v/old"], "A005")

        let listed = RecognitionMemory.rolls(states: store.allStates, movies: [(id: film, name: "Citizen K")],
                                             mountedNames: [:])
        XCTAssertEqual(listed.first?.rolls.map(\.rollName), ["A001", "A002"])

        // Starting the numbering over clears the names kept aside too.
        store.resetNumbering(for: film)
        XCTAssertTrue(store.state(for: film).assignments.isEmpty)
    }
}
}
