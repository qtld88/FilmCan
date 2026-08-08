# Spotlight Lockout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop macOS Spotlight from thrashing FilmCan's source and destination volumes by dropping a `.metadata_never_index` marker at each *external* volume root at backup start, gated by a default-on Settings toggle.

**Architecture:** A tiny pure `SpotlightIndexing` utility writes the marker (no root, same tier as the existing `.filmcan` folder). `TransferViewModel` calls it for every source + destination just before the copy loop, gated on the `disableSpotlightIndexing` default (default `true`). A new **Drives** settings tab exposes the toggle. The marker is left in place permanently (standard for camera cards; keeps them fast).

**Tech Stack:** Swift 5.9, SwiftUI, `@AppStorage`/`UserDefaults`, `FileManager`, `DriveUtilities`.

**Safety invariant:** NEVER write the marker on the internal/boot volume. Every write path is guarded by `DriveUtilities.summary(for:).isExternal`.

---

## File Structure

- Create `FilmCan/Sources/Utilities/SpotlightIndexing.swift` — pure marker logic + gate read.
- Create `FilmCan/Tests/SpotlightIndexingTests.swift` — unit tests (temp-dir, no mocks).
- Modify `FilmCan/Sources/ViewModels/TransferViewModel.swift` — call at backup start.
- Create `FilmCan/Sources/Views/DriveSettingsView.swift` — new settings tab body.
- Modify `FilmCan/Sources/Views/SettingsView.swift` — add `@AppStorage` key + tab.

---

## Task 1: `SpotlightIndexing` utility + tests

**Files:**
- Create: `FilmCan/Sources/Utilities/SpotlightIndexing.swift`
- Test: `FilmCan/Tests/SpotlightIndexingTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `FilmCan/Tests/SpotlightIndexingTests.swift`:

```swift
import XCTest
@testable import FilmCan

final class SpotlightIndexingTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("spotlight-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func test_writeMarker_createsEmptyNeverIndexFile() {
        let ok = SpotlightIndexing.writeMarker(atVolumeRoot: root.path)
        XCTAssertTrue(ok)
        let marker = root.appendingPathComponent(SpotlightIndexing.markerName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
        let data = try? Data(contentsOf: marker)
        XCTAssertEqual(data?.count, 0)
    }

    func test_writeMarker_isIdempotent() {
        XCTAssertTrue(SpotlightIndexing.writeMarker(atVolumeRoot: root.path))
        // Second call must not fail even though the file already exists.
        XCTAssertTrue(SpotlightIndexing.writeMarker(atVolumeRoot: root.path))
    }

    func test_writeMarker_doesNotClobberExistingMarker() throws {
        let marker = root.appendingPathComponent(SpotlightIndexing.markerName)
        try Data("keep".utf8).write(to: marker)
        XCTAssertTrue(SpotlightIndexing.writeMarker(atVolumeRoot: root.path))
        // Existing content is preserved (we only ensure presence, never overwrite).
        XCTAssertEqual(try Data(contentsOf: marker), Data("keep".utf8))
    }

    func test_shouldDisable_defaultsTrueWhenUnset() {
        let d = UserDefaults(suiteName: "spotlight-test-\(UUID().uuidString)")!
        XCTAssertTrue(SpotlightIndexing.shouldDisable(defaults: d))
    }

    func test_shouldDisable_respectsStoredFalse() {
        let d = UserDefaults(suiteName: "spotlight-test-\(UUID().uuidString)")!
        d.set(false, forKey: SpotlightIndexing.defaultsKey)
        XCTAssertFalse(SpotlightIndexing.shouldDisable(defaults: d))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project FilmCan/FilmCan.xcodeproj -scheme FilmCan -destination 'platform=macOS' -only-testing:FilmCanTests/SpotlightIndexingTests`
Expected: FAIL — `cannot find 'SpotlightIndexing' in scope`.

- [ ] **Step 3: Write the implementation**

Create `FilmCan/Sources/Utilities/SpotlightIndexing.swift`:

```swift
import Foundation

/// Disables macOS Spotlight indexing on a volume by dropping the documented
/// `.metadata_never_index` marker at its root. No root privilege required —
/// same tier as the existing `.filmcan` namespace. Best-effort and idempotent.
///
/// Safety: `disableIndexing(forVolumeContaining:)` refuses to touch the
/// internal/boot volume. The marker is intentionally left in place (never
/// removed) — it keeps camera cards and backup drives from being re-scanned.
enum SpotlightIndexing {

    static let markerName = ".metadata_never_index"
    static let defaultsKey = "disableSpotlightIndexing"

    /// Read the gate. Absent key ⇒ enabled (opt-out feature).
    static func shouldDisable(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: defaultsKey) as? Bool ?? true
    }

    /// Ensure the never-index marker exists at `root`. Never overwrites an
    /// existing marker. Returns true if the marker is present after the call.
    @discardableResult
    static func writeMarker(atVolumeRoot root: String) -> Bool {
        let marker = (root as NSString).appendingPathComponent(markerName)
        if FileManager.default.fileExists(atPath: marker) { return true }
        return FileManager.default.createFile(atPath: marker, contents: Data())
    }

    /// Resolve the volume root backing `path` and, only if that volume is
    /// external/removable, drop the marker. Boot/internal volumes are never
    /// touched. Best-effort: failures are swallowed (logged by the caller).
    @discardableResult
    static func disableIndexing(forVolumeContaining path: String) -> Bool {
        guard let root = DriveUtilities.volumeRootPath(for: path) else { return false }
        guard DriveUtilities.summary(for: root).isExternal else { return false }
        return writeMarker(atVolumeRoot: root)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project FilmCan/FilmCan.xcodeproj -scheme FilmCan -destination 'platform=macOS' -only-testing:FilmCanTests/SpotlightIndexingTests`
Expected: PASS — 5/5.

- [ ] **Step 5: Commit**

```bash
git add FilmCan/Sources/Utilities/SpotlightIndexing.swift FilmCan/Tests/SpotlightIndexingTests.swift
git commit -m "feat(spotlight): add SpotlightIndexing marker utility"
```

---

## Task 2: Call at backup start (gated)

**Files:**
- Modify: `FilmCan/Sources/ViewModels/TransferViewModel.swift:160` (after `let sources = activeConfig.sourcePaths`)

- [ ] **Step 1: Add the call**

In `TransferViewModel.swift`, immediately after line 160 (`let sources = activeConfig.sourcePaths`) and before `do {`, insert:

```swift
        // Stop Spotlight from thrashing the card and backup drives during the
        // run. Opt-out via Settings › Drives. Best-effort; never blocks a backup.
        if SpotlightIndexing.shouldDisable() {
            for path in sources + destinations {
                SpotlightIndexing.disableIndexing(forVolumeContaining: path)
            }
        }
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild build -project FilmCan/FilmCan.xcodeproj -scheme FilmCan -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED.

> No unit test here — this is glue over Task 1's tested helpers, and `runBackup` drives real disk I/O. Behavior is covered by the Manual QA section.

- [ ] **Step 3: Commit**

```bash
git add FilmCan/Sources/ViewModels/TransferViewModel.swift
git commit -m "feat(spotlight): disable indexing on source + dest volumes at backup start"
```

---

## Task 3: Settings toggle (new Drives tab)

**Files:**
- Create: `FilmCan/Sources/Views/DriveSettingsView.swift`
- Modify: `FilmCan/Sources/Views/SettingsView.swift` (add `@AppStorage` + tab)

- [ ] **Step 1: Create the settings view**

Create `FilmCan/Sources/Views/DriveSettingsView.swift`:

```swift
import SwiftUI

struct DriveSettingsView: View {
    @Binding var disableSpotlightIndexing: Bool

    var body: some View {
        Form {
            Section("Spotlight") {
                Toggle("Disable Spotlight indexing on backup drives", isOn: $disableSpotlightIndexing)
                Text("Drops a `.metadata_never_index` marker on each source card and destination drive at backup start, so macOS stops indexing them mid-copy. Only external/removable volumes are affected — your internal disk is never touched. The marker is left in place.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }
}
```

- [ ] **Step 2: Wire the `@AppStorage` key and tab into SettingsView**

In `FilmCan/Sources/Views/SettingsView.swift`, add this `@AppStorage` line alongside the others near the top of `SettingsView` (e.g. after line 19 `historyRetentionLimit`):

```swift
    @AppStorage("disableSpotlightIndexing") private var disableSpotlightIndexing: Bool = true
```

Then inside the `TabView`, insert a new tab immediately after the `HistorySettingsView` tab block (before `HotkeysSettingsView`):

```swift
            DriveSettingsView(
                disableSpotlightIndexing: $disableSpotlightIndexing
            )
            .tabItem {
                Label("Drives", systemImage: "externaldrive")
            }
```

The `@AppStorage("disableSpotlightIndexing")` key here and `SpotlightIndexing.defaultsKey` are the same string — both `"disableSpotlightIndexing"`, both default `true` — so the toggle and the backup-time gate read one value.

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodebuild build -project FilmCan/FilmCan.xcodeproj -scheme FilmCan -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add FilmCan/Sources/Views/DriveSettingsView.swift FilmCan/Sources/Views/SettingsView.swift
git commit -m "feat(spotlight): add Drives settings tab with indexing toggle"
```

---

## Manual QA (real hardware)

Release-gate: units cannot exercise real volumes. On a real external SD/exFAT card and an external destination drive:

1. Toggle ON (default). Run a backup. → `.metadata_never_index` exists at both `/Volumes/<card>/` and `/Volumes/<dest>/` (check with `ls -la /Volumes/<name>/.metadata_never_index`).
2. Confirm the internal boot volume is untouched: no marker created at `/` (there won't be — `isExternal` guard — but verify no permission errors logged).
3. Re-run the backup. → no error; marker still present (idempotent, not clobbered).
4. Put text in the marker manually, re-run. → content preserved (never overwritten).
5. Toggle OFF in Settings › Drives, run a backup on a *fresh* card with no marker. → no marker written.
6. `mdutil -s /Volumes/<card>` after step 1 → indexing reported disabled for that volume.
7. Backup still completes/verifies normally with the marker present (the marker must not appear in the copied file set — `FileEnumerator` already excludes dotfiles at root? confirm the marker is NOT copied to destinations; if it is, that's acceptable but note it).

---

## Self-Review Notes

- **Spec coverage:** toggle (Task 3), auto-disable on both source+dest at backup start (Task 2), boot-volume safety (`isExternal` guard, Task 1), leave-in-place (never removed, Task 1). ✅
- **Type consistency:** `SpotlightIndexing.defaultsKey == "disableSpotlightIndexing"` matches the `@AppStorage` key in SettingsView. `writeMarker`/`disableIndexing`/`shouldDisable` signatures identical across tasks. ✅
- **No placeholders:** every step has concrete code and exact commands. ✅
