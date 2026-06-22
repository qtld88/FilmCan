# TransferViewModel Decomposition Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Shrink the 1730-line `TransferViewModel` god-class by extracting cohesive responsibilities (notifications, logging, history, filtering, duplicate-prompt, repair) into focused, independently-testable types — without changing observable behavior or churning the views.

**Architecture:** Extract leaf/internal clusters first (lowest blast radius), arteries last. Pure logic becomes stateless types with real unit tests; I/O orchestration moves into small owned helpers the VM delegates to. The VM keeps its legitimate coordinator role (run loop, cancellation, progress dictionaries, `@Published` view state). View-bound `@Published` properties and view-called methods are preserved on the VM via thin forwarders so **no SwiftUI view is edited**.

**Tech Stack:** Swift 5.9, SwiftUI/MVVM, macOS 13+, XCTest (real temp-dir I/O, no mocks). Build: `xcodebuild test -project FilmCan/FilmCan.xcodeproj -scheme FilmCan -destination 'platform=macOS'`. New files require `cd FilmCan && xcodegen generate` before they compile.

---

## Background

`TransferViewModel` (`FilmCan/Sources/ViewModels/TransferViewModel.swift`, 1730 lines) is the project's top god-node (94 graph edges). Step 1 of this decomposition already landed: `LogItemizeParser` was extracted (commit `61fe4ec`). This plan covers the remaining extractions.

### The three arteries (shared mutable state — do NOT relocate)

These `@Published` members are read/written across many clusters and are the VM's coordinator state. Extracted helpers receive what they need as **parameters** and return results; they never reach back into the VM:

- `progress: TransferProgress`
- `results: [TransferResult]`
- run-state set: `isTransferring`, `activeConfigId`, `currentSources`, `currentDestination`, `allDestinations`, the progress dictionaries.

### Seam strategy

| Cluster | Extracted as | Seam |
|---|---|---|
| Notification formatting | `NotificationSummaryBuilder` (stateless) | pure funcs + a `NotificationSettings` value snapshot |
| Notification sending | `NotificationDispatcher` (stateless) | static funcs taking `NotificationSettings` + results |
| Log writing | `BackupLogWriter` (stateless) | static funcs taking explicit paths/config |
| Source-filter helpers | `SourceFilterMatching` (stateless) | pure funcs |
| History recording | `HistoryRecorder` (owned instance) | takes results+config, returns records |
| Duplicate/unreadable prompts | `DuplicatePromptCoordinator` (owned `ObservableObject`) | VM forwards view-facing API |
| Repair | `RepairCoordinator` (owned instance) | takes results, returns patched results |

`@AppStorage` stays on the VM (the same UserDefaults keys are read by `SettingsView`). The VM builds a plain `NotificationSettings` struct from them and passes it down — this makes the dispatcher testable without `@AppStorage`.

### Out of scope (tracked, not done here)

Protocolizing `NotificationService.shared` / `WebhookService` static calls for full send-path mocking (audit #7). These remain concrete; we test the **pure** formatting/summary logic, which is currently uncovered.

---

## File Map

| File | Responsibility |
|---|---|
| `FilmCan/Sources/Models/NotificationSettings.swift` | **New.** Value snapshot of notify/ntfy/webhook settings |
| `FilmCan/Sources/Services/NotificationSummaryBuilder.swift` | **New.** Pure: build titles/bodies/templated summaries |
| `FilmCan/Sources/Services/NotificationDispatcher.swift` | **New.** Send via NotificationService/WebhookService |
| `FilmCan/Sources/Utilities/BackupLogWriter.swift` | **New.** Resolve paths + write fan-out/custom/netflix logs |
| `FilmCan/Sources/Utilities/SourceFilterMatching.swift` | **New.** Pure pattern/filter helpers |
| `FilmCan/Sources/Services/HistoryRecorder.swift` | **New.** Build + persist history records |
| `FilmCan/Sources/ViewModels/DuplicatePromptCoordinator.swift` | **New.** Owns duplicate + unreadable prompt flow |
| `FilmCan/Sources/Services/RepairCoordinator.swift` | **New.** Sibling/source repair of failed destinations |
| `FilmCan/Sources/ViewModels/TransferViewModel.swift` | Slimmed; delegates to the above |
| `FilmCan/Tests/NotificationSummaryBuilderTests.swift` | **New** |
| `FilmCan/Tests/BackupLogWriterTests.swift` | **New** |
| `FilmCan/Tests/SourceFilterMatchingTests.swift` | **New** |

---

## Conventions for every task

- **Verbatim move:** when a step says "move the body verbatim", copy the existing function body unchanged from the cited `TransferViewModel.swift` location into the new type, adjusting only `self.`-qualified calls to the new internal call (e.g. a sibling helper now in the same new type) and references to `@AppStorage` to the passed-in `settings` value.
- After adding any new file: `cd FilmCan && xcodegen generate` before building.
- Each task ends green on the **full** suite and a commit. Current baseline: **150 tests, 1 skipped, 0 failures.**
- Never edit a file under `FilmCan/Sources/Views/` in this plan. If a step seems to require it, stop — the seam is wrong.

---

## Task 1: Extract `NotificationSummaryBuilder` (pure formatting)

Extracts the *pure* notification text logic so it gets real coverage. Sending stays in the VM for now (Task 2 moves it).

**Files:**
- Create: `FilmCan/Sources/Models/NotificationSettings.swift`
- Create: `FilmCan/Sources/Services/NotificationSummaryBuilder.swift`
- Create: `FilmCan/Tests/NotificationSummaryBuilderTests.swift`
- Modify: `FilmCan/Sources/ViewModels/TransferViewModel.swift` (`formatQuotedList` 848, `durationString` 861, `applyTemplate` 873; `destinationNotificationSummary` 737)

- [ ] **Step 1: Create the settings value type**

`FilmCan/Sources/Models/NotificationSettings.swift`:

```swift
import Foundation

/// Plain snapshot of the user's notification preferences, built from the
/// VM's @AppStorage at call time so notification logic is testable without
/// the property wrapper.
struct NotificationSettings {
    var notifyOnComplete: Bool
    var notifyOnError: Bool
    var ntfyEnabled: Bool
    var ntfyURL: String
    var ntfyTitleTemplate: String
    var ntfyMessageTemplate: String
    var webhookEnabled: Bool
    var webhookURL: String
    var webhookIncludeFullPaths: Bool
}
```

- [ ] **Step 2: Write the failing test**

`FilmCan/Tests/NotificationSummaryBuilderTests.swift`:

```swift
import XCTest
@testable import FilmCan

final class NotificationSummaryBuilderTests: XCTestCase {

    func test_formatQuotedList_variants() {
        XCTAssertEqual(NotificationSummaryBuilder.formatQuotedList([]), "No items")
        XCTAssertEqual(NotificationSummaryBuilder.formatQuotedList(["/a/One"]), "\"One\"")
        XCTAssertEqual(NotificationSummaryBuilder.formatQuotedList(["/a/One", "/b/Two"]),
                       "\"One\" and \"Two\"")
        XCTAssertEqual(NotificationSummaryBuilder.formatQuotedList(["/a/A", "/b/B", "/c/C", "/d/D"]),
                       "\"A\", \"B\", \"C\", and 1 others")
    }

    func test_durationString_formats() {
        XCTAssertNil(NotificationSummaryBuilder.durationString(durations: []))
        XCTAssertEqual(NotificationSummaryBuilder.durationString(durations: [5]), "5s")
        XCTAssertEqual(NotificationSummaryBuilder.durationString(durations: [65]), "1m 5s")
        XCTAssertEqual(NotificationSummaryBuilder.durationString(durations: [3661]), "1h 1m 1s")
    }
}
```

- [ ] **Step 3: Run — expect FAIL (type missing)**

```bash
cd FilmCan && xcodegen generate >/dev/null && cd ..
xcodebuild test -project FilmCan/FilmCan.xcodeproj -scheme FilmCan -destination 'platform=macOS' \
  -only-testing:FilmCanTests/NotificationSummaryBuilderTests 2>&1 | tail -15
```
Expected: compile error — `NotificationSummaryBuilder` not found.

- [ ] **Step 4: Create `NotificationSummaryBuilder`**

`FilmCan/Sources/Services/NotificationSummaryBuilder.swift`. Move `formatQuotedList`, `durationString` (refactored to take `durations:` not `results:`), and `applyTemplate` verbatim as `static`; move the `DestinationNotificationSummary` struct here as a non-private nested type. Keep the body of `destinationNotificationSummary` but split it: the async counting (`countVisibleFiles`, `PreviewCalculator`) stays in the VM and is passed in as already-computed `totalFiles`/`totalBytes`.

```swift
import Foundation

enum NotificationSummaryBuilder {

    struct DestinationNotificationSummary {
        let title: String
        let body: String
        let messageTitle: String
        let messageBody: String
        let fields: [String: String]
        let allSuccess: Bool
        let wasPaused: Bool
    }

    static func formatQuotedList(_ paths: [String]) -> String {
        let names = paths.map { "\"\(($0 as NSString).lastPathComponent)\"" }
        if names.isEmpty { return "No items" }
        if names.count == 1 { return names[0] }
        if names.count == 2 { return "\(names[0]) and \(names[1])" }
        let head = names.prefix(3).joined(separator: ", ")
        let remaining = names.count - 3
        if remaining > 0 { return "\(head), and \(remaining) others" }
        return head
    }

    static func durationString(durations: [TimeInterval]) -> String? {
        guard !durations.isEmpty else { return nil }
        let total = durations.reduce(0, +)
        let hours = Int(total) / 3600
        let minutes = (Int(total) % 3600) / 60
        let seconds = Int(total) % 60
        if hours > 0 { return String(format: "%dh %dm %ds", hours, minutes, seconds) }
        if minutes > 0 { return String(format: "%dm %ds", minutes, seconds) }
        return String(format: "%ds", seconds)
    }

    static func applyTemplate(_ template: String, replacements: [String: String]) -> String {
        OrganizationTemplate.substituteTokens(template, values: replacements)
    }

    /// Build the per-destination summary from already-resolved totals.
    static func destinationSummary(
        source: String,
        config: BackupConfiguration,
        result: TransferResult,
        totalFiles: Int,
        totalBytes: Int64,
        settings: NotificationSettings
    ) -> DestinationNotificationSummary {
        // MOVE VERBATIM the body of the current destinationNotificationSummary
        // starting at the `let wasPaused = result.wasPaused` line, EXCEPT:
        //   - delete the two async blocks that compute totalFiles/totalBytes
        //     (they are now parameters)
        //   - `durationString(for: [result])` -> durationString(durations: result.duration.map { [$0] } ?? [])
        //   - `formatQuotedList(...)` -> Self.formatQuotedList(...)
        //   - `applyTemplate(...)` -> Self.applyTemplate(...)
        //   - `ntfyMessageTemplate` -> settings.ntfyMessageTemplate
        //   - `ntfyTitleTemplate` -> settings.ntfyTitleTemplate
        fatalError("replace this comment with the moved body")
    }
}
```

- [ ] **Step 5: Point the VM at the builder**

In `TransferViewModel.swift`: delete `formatQuotedList`, `durationString`, `applyTemplate`, and the private `DestinationNotificationSummary` struct. Change `destinationNotificationSummary` to compute `totalFiles`/`totalBytes` (its existing async logic) then `return NotificationSummaryBuilder.destinationSummary(source:config:result:totalFiles:totalBytes:settings: makeNotificationSettings())`. Add a helper:

```swift
private func makeNotificationSettings() -> NotificationSettings {
    NotificationSettings(
        notifyOnComplete: notifyOnComplete, notifyOnError: notifyOnError,
        ntfyEnabled: ntfyEnabled, ntfyURL: ntfyURL,
        ntfyTitleTemplate: ntfyTitleTemplate, ntfyMessageTemplate: ntfyMessageTemplate,
        webhookEnabled: webhookEnabled, webhookURL: webhookURL,
        webhookIncludeFullPaths: webhookIncludeFullPaths)
}
```

Update internal references to the summary type to `NotificationSummaryBuilder.DestinationNotificationSummary`.

- [ ] **Step 6: Run the new tests + full suite — expect PASS**

```bash
cd FilmCan && xcodegen generate >/dev/null && cd ..
xcodebuild test -project FilmCan/FilmCan.xcodeproj -scheme FilmCan -destination 'platform=macOS' 2>&1 | grep -E "error:|Executed [0-9]+ tests|SUCCEEDED|FAILED" | tail -5
```
Expected: `** TEST SUCCEEDED **`, ≥152 tests, 0 failures.

- [ ] **Step 7: Commit**

```bash
git add FilmCan/Sources/Models/NotificationSettings.swift \
        FilmCan/Sources/Services/NotificationSummaryBuilder.swift \
        FilmCan/Tests/NotificationSummaryBuilderTests.swift \
        FilmCan/Sources/ViewModels/TransferViewModel.swift \
        FilmCan/FilmCan.xcodeproj/project.pbxproj
git commit -m "refactor(vm): extract NotificationSummaryBuilder (pure notification formatting)"
```

---

## Task 2: Extract `NotificationDispatcher` (send orchestration)

Moves the side-effecting send funcs out. No new behavioral tests (sends hit concrete singletons — out of scope to mock); covered indirectly by the build + the summary tests from Task 1.

**Files:**
- Create: `FilmCan/Sources/Services/NotificationDispatcher.swift`
- Modify: `TransferViewModel.swift` (`sendSourceNotifications` 611, `sendAggregatedNotifications` 650, `sendNtfySummary` 824, `sendWebhookSummary` 835)

- [ ] **Step 1: Create the dispatcher**

`FilmCan/Sources/Services/NotificationDispatcher.swift`. Move the bodies of `sendAggregatedNotifications`, `sendNtfySummary`, `sendWebhookSummary` verbatim as `static` funcs, replacing `@AppStorage` reads with `settings.` and taking `settings: NotificationSettings`. `sendSourceNotifications` becomes the entry point that calls `NotificationSummaryBuilder.destinationSummary` — but it needs the async totals, so it takes a closure `summaryFor: (TransferResult) async -> NotificationSummaryBuilder.DestinationNotificationSummary` supplied by the VM (which owns the async counting).

```swift
import Foundation

enum NotificationDispatcher {

    static func sendSource(
        source: String,
        config: BackupConfiguration,
        results: [TransferResult],
        settings: NotificationSettings,
        summaryFor: (TransferResult) async -> NotificationSummaryBuilder.DestinationNotificationSummary
    ) async {
        if config.webhookTemplateFormatVersion >= 2 {
            sendAggregated(source: source, config: config, results: results, settings: settings)
            return
        }
        for result in results {
            let summary = await summaryFor(result)
            guard !summary.wasPaused else { continue }
            if summary.allSuccess && settings.notifyOnComplete {
                NotificationService.shared.notify(title: summary.title, body: summary.body)
            } else if !summary.allSuccess && settings.notifyOnError {
                NotificationService.shared.notify(title: summary.title, body: summary.body)
            }
            if settings.ntfyEnabled, !settings.ntfyURL.isEmpty { sendNtfy(summary, settings) }
            if settings.webhookEnabled, !settings.webhookURL.isEmpty { sendWebhook(summary, settings) }
        }
    }

    // sendAggregated: MOVE VERBATIM body of sendAggregatedNotifications,
    //   @AppStorage -> settings.* ; signature (source:config:results:settings:)
    // sendNtfy / sendWebhook: MOVE VERBATIM bodies of sendNtfySummary /
    //   sendWebhookSummary, taking (_ summary:, _ settings:).
}
```

- [ ] **Step 2: Point the VM at the dispatcher**

Delete the four send funcs from the VM. Replace the single call site of `sendSourceNotifications(...)` (find with `grep -n sendSourceNotifications TransferViewModel.swift`) with:

```swift
await NotificationDispatcher.sendSource(
    source: source, config: config, results: results,
    settings: makeNotificationSettings(),
    summaryFor: { await self.destinationNotificationSummary(source: source, config: config, result: $0) })
```

- [ ] **Step 3: Build + full suite — expect PASS**

```bash
cd FilmCan && xcodegen generate >/dev/null && cd ..
xcodebuild test -project FilmCan/FilmCan.xcodeproj -scheme FilmCan -destination 'platform=macOS' 2>&1 | grep -E "error:|Executed [0-9]+ tests|SUCCEEDED|FAILED" | tail -5
```
Expected: SUCCEEDED, 0 failures.

- [ ] **Step 4: Commit**

```bash
git add FilmCan/Sources/Services/NotificationDispatcher.swift \
        FilmCan/Sources/ViewModels/TransferViewModel.swift \
        FilmCan/FilmCan.xcodeproj/project.pbxproj
git commit -m "refactor(vm): extract NotificationDispatcher (send orchestration)"
```

---

## Task 3: Extract `BackupLogWriter`

Internal-only log I/O. Pure helpers get tests; I/O funcs move verbatim.

**Files:**
- Create: `FilmCan/Sources/Utilities/BackupLogWriter.swift`
- Create: `FilmCan/Tests/BackupLogWriterTests.swift`
- Modify: `TransferViewModel.swift` (`resolvedLogFilePath` 1156, `writeFanOutLogs` 1211, `mergeWarning` 1269, `netflixReportLogPath` 1276, `writeCustomLog` 1297, `appSupportLogDirectory` 1354, `ensureWritableLogPath` 1365)

- [ ] **Step 1: Write the failing test (pure helpers)**

`FilmCan/Tests/BackupLogWriterTests.swift`:

```swift
import XCTest
@testable import FilmCan

final class BackupLogWriterTests: XCTestCase {

    func test_mergeWarning_concatenatesNonEmpty() {
        XCTAssertEqual(BackupLogWriter.mergeWarning(nil, "b"), "b")
        XCTAssertEqual(BackupLogWriter.mergeWarning("a", "b"), "a\nb")
    }

    func test_ensureWritableLogPath_createsParentAndIsWritable() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let path = dir.appendingPathComponent("logs/run.log").path
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertTrue(BackupLogWriter.ensureWritableLogPath(path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("logs").path))
    }
}
```

> Note: confirm `mergeWarning`'s exact separator by reading `TransferViewModel.swift:1269` before finalizing the expected string; adjust the assertion to match the real implementation.

- [ ] **Step 2: Run — expect FAIL (type missing)**

```bash
cd FilmCan && xcodegen generate >/dev/null && cd ..
xcodebuild test -project FilmCan/FilmCan.xcodeproj -scheme FilmCan -destination 'platform=macOS' \
  -only-testing:FilmCanTests/BackupLogWriterTests 2>&1 | tail -15
```
Expected: compile error — `BackupLogWriter` not found.

- [ ] **Step 3: Create `BackupLogWriter`**

`FilmCan/Sources/Utilities/BackupLogWriter.swift` — an `enum` with `static` funcs. Move verbatim the bodies of `resolvedLogFilePath`, `writeFanOutLogs`, `mergeWarning`, `netflixReportLogPath`, `writeCustomLog`, `appSupportLogDirectory`, `ensureWritableLogPath`. These already take their inputs as parameters or use only `FileManager`/`config`. Any internal call between them becomes `Self.`. They reference `LogItemizeParser` (already extracted) and `FilmCanPaths`/`LogFileNamer`/`LogFolderNamer` (already standalone) — no VM state needed.

- [ ] **Step 4: Point the VM at the writer**

Delete the seven funcs from the VM. Update their call sites (find each: `grep -nE "resolvedLogFilePath|writeFanOutLogs|netflixReportLogPath|writeCustomLog" TransferViewModel.swift`) to `BackupLogWriter.<fn>(...)`. Signatures are unchanged, so call sites only gain the `BackupLogWriter.` prefix.

- [ ] **Step 5: Run new tests + full suite — expect PASS**

```bash
cd FilmCan && xcodegen generate >/dev/null && cd ..
xcodebuild test -project FilmCan/FilmCan.xcodeproj -scheme FilmCan -destination 'platform=macOS' 2>&1 | grep -E "error:|Executed [0-9]+ tests|SUCCEEDED|FAILED" | tail -5
```
Expected: SUCCEEDED, ≥154 tests, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add FilmCan/Sources/Utilities/BackupLogWriter.swift \
        FilmCan/Tests/BackupLogWriterTests.swift \
        FilmCan/Sources/ViewModels/TransferViewModel.swift \
        FilmCan/FilmCan.xcodeproj/project.pbxproj
git commit -m "refactor(vm): extract BackupLogWriter (log path resolution + writing)"
```

---

## Task 4: Extract `SourceFilterMatching` (pure filter helpers)

**Files:**
- Create: `FilmCan/Sources/Utilities/SourceFilterMatching.swift`
- Create: `FilmCan/Tests/SourceFilterMatchingTests.swift`
- Modify: `TransferViewModel.swift` (`matchesPattern` 578, `hasCustomFilterPatterns` 589, `normalizedPatterns` 605; `volumeName` 569 stays — it reads volume metadata, leave it)

- [ ] **Step 1: Write the failing test**

`FilmCan/Tests/SourceFilterMatchingTests.swift`:

```swift
import XCTest
@testable import FilmCan

final class SourceFilterMatchingTests: XCTestCase {

    func test_normalizedPatterns_trimsAndDropsEmpty() {
        XCTAssertEqual(
            SourceFilterMatching.normalizedPatterns(["  *.mov ", "", "   ", "*.wav"]),
            ["*.mov", "*.wav"])
    }

    func test_matchesPattern_globCaseInsensitive() {
        XCTAssertTrue(SourceFilterMatching.matchesPattern("CLIP.MOV", pattern: "*.mov"))
        XCTAssertFalse(SourceFilterMatching.matchesPattern("clip.wav", pattern: "*.mov"))
    }
}
```

> Note: read `matchesPattern` at `TransferViewModel.swift:578` to confirm glob semantics (case sensitivity, `fnmatch` vs custom) and adjust the assertions to the real behavior before running.

- [ ] **Step 2: Run — expect FAIL (type missing)**

```bash
cd FilmCan && xcodegen generate >/dev/null && cd ..
xcodebuild test -project FilmCan/FilmCan.xcodeproj -scheme FilmCan -destination 'platform=macOS' \
  -only-testing:FilmCanTests/SourceFilterMatchingTests 2>&1 | tail -15
```
Expected: compile error — `SourceFilterMatching` not found.

- [ ] **Step 3: Create `SourceFilterMatching`**

`enum SourceFilterMatching` with `static` funcs; move `matchesPattern`, `hasCustomFilterPatterns`, `normalizedPatterns` verbatim. Internal calls become `Self.`.

- [ ] **Step 4: Point the VM at it**

Delete the three funcs; prefix call sites with `SourceFilterMatching.` (find: `grep -nE "matchesPattern|hasCustomFilterPatterns|normalizedPatterns" TransferViewModel.swift`). Note `hasCustomFilterPatterns` is also referenced in views — verify with `grep -rn hasCustomFilterPatterns FilmCan/Sources/Views`; if a view calls a VM method of that name, **keep a thin forwarder** on the VM (`func hasCustomFilterPatterns(...) { SourceFilterMatching.hasCustomFilterPatterns(...) }`) so the view is untouched.

- [ ] **Step 5: Run new tests + full suite — expect PASS**

```bash
cd FilmCan && xcodegen generate >/dev/null && cd ..
xcodebuild test -project FilmCan/FilmCan.xcodeproj -scheme FilmCan -destination 'platform=macOS' 2>&1 | grep -E "error:|Executed [0-9]+ tests|SUCCEEDED|FAILED" | tail -5
```
Expected: SUCCEEDED, ≥156 tests, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add FilmCan/Sources/Utilities/SourceFilterMatching.swift \
        FilmCan/Tests/SourceFilterMatchingTests.swift \
        FilmCan/Sources/ViewModels/TransferViewModel.swift \
        FilmCan/FilmCan.xcodeproj/project.pbxproj
git commit -m "refactor(vm): extract SourceFilterMatching (pure filter/pattern helpers)"
```

---

## Task 5: Extract `HistoryRecorder`

Touches the `results` artery (read-only) and the history store (`ConfigurationStorage`/wherever `recordHistory` persists). The recorder takes inputs and returns/persists records; the VM still owns `results`.

**Files:**
- Create: `FilmCan/Sources/Services/HistoryRecorder.swift`
- Modify: `TransferViewModel.swift` (`recordHistory` 1405, `hashRoots` 1392, `manifestUnsealedWarning` 914, `patchDestResultToSuccess` 1713)

- [ ] **Step 1: Read the cluster first**

```bash
sed -n '1392,1474p;1713,1730p' FilmCan/Sources/ViewModels/TransferViewModel.swift
grep -rn "recordHistory\|manifestUnsealedWarning\|patchDestResultToSuccess" FilmCan/Sources/Views FilmCan/Tests
```
Confirm: which of these read VM `@Published` state vs. parameters, and whether any are called from views/tests. `manifestUnsealedWarning` is `static` and may be referenced by views — if so, keep a forwarder.

- [ ] **Step 2: Create `HistoryRecorder`**

`HistoryRecorder` owns the history persistence dependency (the same store `recordHistory` currently uses — inject it via `init`). Move `recordHistory`, `hashRoots`, and `manifestUnsealedWarning` bodies verbatim; convert any VM-state reads into parameters of `record(...)`. `patchDestResultToSuccess` mutates `results` — keep it in the VM (it edits the artery) but have it call `HistoryRecorder` only for the record side if needed.

> No new unit test is required if `recordHistory` is already integration-covered; if `RepairFailedDestTests`/`DataIntegrityTests` exercise it, the full suite is the guard. Add a focused `HistoryRecorderTests` only if Step 1 shows uncovered pure logic (e.g. `hashRoots`).

- [ ] **Step 3: Point the VM at it; keep forwarders for any view/test-facing API**

- [ ] **Step 4: Build + full suite — expect PASS**

```bash
cd FilmCan && xcodegen generate >/dev/null && cd ..
xcodebuild test -project FilmCan/FilmCan.xcodeproj -scheme FilmCan -destination 'platform=macOS' 2>&1 | grep -E "error:|Executed [0-9]+ tests|SUCCEEDED|FAILED" | tail -5
```
Expected: SUCCEEDED, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add FilmCan/Sources/Services/HistoryRecorder.swift \
        FilmCan/Sources/ViewModels/TransferViewModel.swift \
        FilmCan/FilmCan.xcodeproj/project.pbxproj
git commit -m "refactor(vm): extract HistoryRecorder"
```

---

## Task 6: Extract `DuplicatePromptCoordinator` (with VM forwarders — no view churn)

The duplicate + unreadable prompt flow has **8 view bindings** in `BackupEditorView.swift` (`activeDuplicatePrompt`, `pendingUnreadableFiles`, `submitDuplicateResolution`, `cancelRunFromDuplicatePrompt`, `resolveUnreadable`). To avoid editing the view, the coordinator owns the state and logic; the VM keeps the view-facing surface as forwarders and republishes the coordinator's changes.

**Files:**
- Create: `FilmCan/Sources/ViewModels/DuplicatePromptCoordinator.swift`
- Modify: `TransferViewModel.swift` (`resolveDuplicate` 428, `submitDuplicateResolution` 442, `presentNextDuplicatePrompt` 475, `resetDuplicatePromptState` 486, `cancelRunFromDuplicatePrompt` 877, `resolveUnreadable` 884; the state vars `activeDuplicatePrompt` 32, `pendingUnreadableFiles` 83, and the private continuation/cache vars)

- [ ] **Step 1: Create the coordinator as an `ObservableObject`**

```swift
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

    // MOVE VERBATIM: resolveDuplicate, submitDuplicateResolution,
    //   presentNextDuplicatePrompt, reset(), resolveUnreadable bodies.
    //   reset() = current resetDuplicatePromptState body + unreadableContinuation = nil.
    //   Drop `duplicatePromptCancelled` handling here — cancellation stays in the VM.
}
```

Move `PendingDuplicatePrompt` (find its definition: `grep -n "struct PendingDuplicatePrompt" TransferViewModel.swift`) alongside or into this file.

- [ ] **Step 2: VM owns the coordinator and forwards**

In `TransferViewModel`:

```swift
@Published var duplicates = DuplicatePromptCoordinator()
private var duplicatesObserver: AnyCancellable?
```

In `init`, bridge child `objectWillChange` so existing `transferViewModel.activeDuplicatePrompt` bindings still refresh:

```swift
duplicatesObserver = duplicates.objectWillChange.sink { [weak self] _ in
    self?.objectWillChange.send()
}
```

Replace the removed stored properties with computed forwarders so views and `BackupEditorView` bindings compile unchanged:

```swift
var activeDuplicatePrompt: DuplicatePrompt? {
    get { duplicates.activeDuplicatePrompt }
    set { duplicates.activeDuplicatePrompt = newValue }
}
var pendingUnreadableFiles: [String] {
    get { duplicates.pendingUnreadableFiles }
    set { duplicates.pendingUnreadableFiles = newValue }
}
func resolveDuplicate(prompt: DuplicatePrompt) async -> DuplicateResolution {
    await duplicates.resolveDuplicate(prompt: prompt)
}
func submitDuplicateResolution(action: OrganizationPreset.DuplicatePolicy, applyToAll: Bool, counterTemplate: String? = nil) {
    duplicates.submitDuplicateResolution(action: action, applyToAll: applyToAll, counterTemplate: counterTemplate)
}
func resolveUnreadable(proceed: Bool) { duplicates.resolveUnreadable(proceed: proceed) }
```

`cancelRunFromDuplicatePrompt` stays in the VM (it calls `cancelAll()`, an artery op) and delegates the resolution part: `duplicates.submitDuplicateResolution(action: .skip, applyToAll: true, counterTemplate: nil)`. Its `duplicatePromptCancelled` flag stays in the VM. Replace internal VM calls to `resetDuplicatePromptState()` with `duplicates.reset()`, and the `unreadableHandler`/`resolveDuplicate` closures passed into the engine with calls into `duplicates`.

> `$transferViewModel.activeDuplicatePrompt` in `BackupEditorView.swift:95` needs a `Binding`; the computed `var` with a setter above supports `$`-binding through `@ObservedObject`/`@StateObject`. Verify the sheet still presents after this task by building — if the binding fails to compile, the setter is missing.

- [ ] **Step 3: Build + full suite — expect PASS**

```bash
cd FilmCan && xcodegen generate >/dev/null && cd ..
xcodebuild test -project FilmCan/FilmCan.xcodeproj -scheme FilmCan -destination 'platform=macOS' 2>&1 | grep -E "error:|Executed [0-9]+ tests|SUCCEEDED|FAILED" | tail -5
```
Expected: SUCCEEDED, 0 failures. (No view file changed — confirm with `git status`.)

- [ ] **Step 4: Commit**

```bash
git add FilmCan/Sources/ViewModels/DuplicatePromptCoordinator.swift \
        FilmCan/Sources/ViewModels/TransferViewModel.swift \
        FilmCan/FilmCan.xcodeproj/project.pbxproj
git commit -m "refactor(vm): extract DuplicatePromptCoordinator (VM forwards, views unchanged)"
```

---

## Task 7: Extract `RepairCoordinator`

`retryFailedDestinationFromSibling` and `repairFailedDest` drive sibling/source repair and mutate `results`/`progress` (arteries). The coordinator performs the copy/verify and returns the outcome; the VM applies it to `results`.

**Files:**
- Create: `FilmCan/Sources/Services/RepairCoordinator.swift`
- Modify: `TransferViewModel.swift` (`retryFailedDestinationFromSibling` 1569, `repairFailedDest` 1644, `patchDestResultToSuccess` 1713)

- [ ] **Step 1: Read the cluster + callers first**

```bash
sed -n '1569,1730p' FilmCan/Sources/ViewModels/TransferViewModel.swift
grep -rn "retryFailedDestinationFromSibling\|repairFailedDest" FilmCan/Sources/Views FilmCan/Tests
```
`RepairFailedDestTests` exercises these — it is the safety net. Note exactly which `@Published` each method mutates; those mutations stay in the VM.

- [ ] **Step 2: Create `RepairCoordinator`**

Move the *work* (locate sibling via `SiblingDestSource`, run `CustomCopierService`/verify, build a result) into `RepairCoordinator` as `async` funcs that take the failed `TransferResult` + config + sources and **return** a patched `TransferResult` (or a small outcome value). Keep the `@Published` mutations (`results[i] = ...`, `progress` updates, `patchDestResultToSuccess`) in the VM, applied to the returned value.

- [ ] **Step 3: Point the VM methods at the coordinator**

The VM's `retryFailedDestinationFromSibling` / `repairFailedDest` keep their signatures (views/tests call them) but become thin: call `RepairCoordinator`, then apply the result to the arteries. No view edits.

- [ ] **Step 4: Run `RepairFailedDestTests` then full suite — expect PASS**

```bash
cd FilmCan && xcodegen generate >/dev/null && cd ..
xcodebuild test -project FilmCan/FilmCan.xcodeproj -scheme FilmCan -destination 'platform=macOS' \
  -only-testing:FilmCanTests/RepairFailedDestTests 2>&1 | grep -E "Executed [0-9]+ tests|SUCCEEDED|FAILED" | tail -3
xcodebuild test -project FilmCan/FilmCan.xcodeproj -scheme FilmCan -destination 'platform=macOS' 2>&1 | grep -E "error:|Executed [0-9]+ tests|SUCCEEDED|FAILED" | tail -5
```
Expected: both SUCCEEDED, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add FilmCan/Sources/Services/RepairCoordinator.swift \
        FilmCan/Sources/ViewModels/TransferViewModel.swift \
        FilmCan/FilmCan.xcodeproj/project.pbxproj
git commit -m "refactor(vm): extract RepairCoordinator"
```

---

## Done criteria

- `wc -l FilmCan/Sources/ViewModels/TransferViewModel.swift` is materially smaller (target: under ~1100 lines).
- Full suite green at every commit; net new unit tests for previously-uncovered pure logic (notification formatting, log path/merge, filter matching).
- `git status` shows **no** file under `FilmCan/Sources/Views/` modified across the whole plan.
- The VM retains only: run loop (`startTransfer`/`runFanOut`/concurrent), cancellation, progress dictionaries + tracking, and `@Published` view state — its legitimate coordinator role.

## Self-review notes

- Each extracted type is reached only through parameters/returns; none reach back into VM `@Published` state (arteries stay in the VM). ✓
- View-facing API (`activeDuplicatePrompt`, `pendingUnreadableFiles`, `submitDuplicateResolution`, `resolveUnreadable`, `hasCustomFilterPatterns`, `manifestUnsealedWarning`) preserved via forwarders — Tasks 4/5/6 each include a grep to catch view/test callers before deleting. ✓
- Names are consistent across tasks: `NotificationSettings`, `NotificationSummaryBuilder.DestinationNotificationSummary`, `NotificationDispatcher.sendSource`, `BackupLogWriter`, `SourceFilterMatching`, `HistoryRecorder`, `DuplicatePromptCoordinator.reset()`, `RepairCoordinator`. ✓
- TDD applies to the pure extractions (Tasks 1,3,4); Tasks 2,5,6,7 are behavior-preserving moves guarded by the existing integration suite (`RepairFailedDestTests`, `DataIntegrityTests`, `CustomCopierServiceE2ETests`) + build. ✓
