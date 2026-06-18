# P0 Integrity Fix — Design Spec

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix three release-blocking bugs identified in the 2026-06-18 audit: duplicate policy not wired through `CustomCopierService`, `increment` mode data loss due to wrong verify path, and unreadable source files silently ignored.

**Architecture:** All three fixes converge on the `CustomCopierService` → `FanOutCopier` interface. No new abstractions; extend existing types and add one new sheet view.

**Source:** Audit report `AUDIT_REPORT.md` (2026-06-18), sections 3.1, 3.2, 3.3.

---

## Affected Files

| File | Role |
|---|---|
| `FilmCan/Sources/Services/DestWriter.swift` | `finalize` returns actual written path |
| `FilmCan/Sources/Services/FanOutCopier.swift` | Use returned path; `writtenRelPath`; `unreadableHandler` |
| `FilmCan/Sources/Services/CustomCopierService.swift` | Wire policy + resolver + `unreadableHandler` |
| `FilmCan/Sources/ViewModels/TransferViewModel.swift` | `pendingUnreadableFiles`, continuation, `resolveUnreadable` |
| `FilmCan/Sources/Views/Sheets/UnreadableFilesSheet.swift` | New — pre-flight confirmation sheet |
| `FilmCan/Tests/CustomCopierServiceE2ETests.swift` | New — E2E tests via the adapter |

---

## Bug 3.2 — `increment` mode verifies and may delete the wrong file

### Root cause

`DestWriter.finalize` resolves an `effectiveDestURL` (e.g. `A001_001.mov`) in `increment` mode but returns `void`. `FanOutCopier` builds `DestWriterResult.writtenFilePath` from the **original** `destFileURL.path`. Paranoid verify then re-reads that original path — which is the pre-existing file, not the newly written one. If the hashes differ, it deletes the pre-existing file.

### Fix A — `DestWriter.finalize` returns `String`

Change signature to `@discardableResult func finalize(...) throws -> String`. Return `effectiveDestURL.path` after the `rename(2)` succeeds. Existing callers that ignore the result still compile.

### Fix B — `DestWriterResult` carries `writtenRelPath`

Add `writtenRelPath: String` field. The writer task, which already has `rollFolder` in scope, derives it:

```swift
let actualPath = try await writer.finalize(
    fileHash: destHash, sourceSize: sourceSize,
    conflictPolicy: conflictPolicy,
    counterTemplate: config.duplicateCounterTemplate)

let writtenRelPath: String
if actualPath.hasPrefix(rollFolder + "/") {
    writtenRelPath = String(actualPath.dropFirst(rollFolder.count + 1))
} else {
    writtenRelPath = sourceName  // fallback: non-increment case, paths match
}

return DestWriterResult(
    ...,
    writtenFilePath: actualPath,
    writtenRelPath: writtenRelPath
)
```

### Fix C — MHL uses `writtenRelPath`, verify uses `writtenFilePath`

In `drainVerifies`, replace `relPath: c.sourceName` with `relPath: r.writtenRelPath`:

```swift
try? await writer.append(
    relPath: r.writtenRelPath, size: c.sourceSize,
    hash: r.destHashFromStream ?? c.verifiedSourceHash,
    mtime: c.srcMtime)
```

Paranoid re-read already uses `r.writtenFilePath` — once it carries the actual path, this is automatically correct.

---

## Bug 3.1 — Duplicate policy not transmitted to `FanOutCopier`

### Root cause

`CustomCopierService.runCopyFanOut` builds `fanOutConfig` without setting `duplicatePolicy`, `duplicateCounterTemplate`, or `duplicateResolver`. Engine defaults: `duplicatePolicy = .overwrite`, `duplicateResolver = nil`. The UI can show Skip/Ask/Increment but every run silently overwrites.

### Fix — Wire fields + adapter

After the existing `fanOutConfig` initializer call, add:

```swift
fanOutConfig.duplicatePolicy = duplicatePolicy
fanOutConfig.duplicateCounterTemplate = duplicateCounterTemplate
if let duplicateResolver {
    fanOutConfig.duplicateResolver = { @Sendable conflicts in
        guard let first = conflicts.first else { return duplicatePolicy }
        let prompt = DuplicatePrompt(
            sourcePath: first.fileName,
            destinationPath: first.resolvedPath,
            isDirectory: false,
            counterTemplate: duplicateCounterTemplate,
            canVerifyWithHashList: false,
            hashListMissing: false)
        return await duplicateResolver(prompt).action
    }
}
```

The adapter bridges `[ConflictScanner.Conflict] → DuplicatePolicy` (FanOutCopier batch) to `DuplicatePrompt → DuplicateResolution` (existing per-file UI resolver). One prompt is shown for the first conflict; the returned action applies to all.

---

## Bug 3.3 — Unreadable source files silently ignored

### Root cause

`FileEnumerator.enumerateFiles` populates `EnumerationResult.unreadable` since Plan 4, but `FanOutCopier.run()` reads only `enumResult.entries` and discards `unreadable`. A backup completes "successfully" with files missing.

### Fix A — `FanOutCopier.Configuration` callback

Add field:

```swift
var unreadableHandler: (@Sendable ([String]) async -> Bool)? = nil
```

In `run()`, immediately after enumeration:

```swift
if !enumResult.unreadable.isEmpty {
    if let handler = config.unreadableHandler {
        guard await handler(enumResult.unreadable) else { throw Error.cancelled }
    } else {
        throw Error.sourceReadFailed(
            "Cannot read \(enumResult.unreadable.count) item(s): "
            + enumResult.unreadable.prefix(5).joined(separator: ", "))
    }
}
```

No handler (tests, repair path) → hard fail. Handler present → user decides.

### Fix B — `CustomCopierService.runCopyFanOut` adds `unreadableHandler` param

```swift
unreadableHandler: (@Sendable ([String]) async -> Bool)? = nil,
```

Wire into `fanOutConfig.unreadableHandler = unreadableHandler`.

### Fix C — `TransferViewModel` creates the handler

```swift
@Published var pendingUnreadableFiles: [String] = []
private var unreadableContinuation: CheckedContinuation<Bool, Never>?

func resolveUnreadable(proceed: Bool) {
    let c = unreadableContinuation
    unreadableContinuation = nil
    pendingUnreadableFiles = []
    c?.resume(returning: proceed)
}
```

In the `runCopyFanOut` call:

```swift
unreadableHandler: { [weak self] paths async -> Bool in
    guard let self else { return false }
    return await withCheckedContinuation { continuation in
        Task { @MainActor [weak self] in
            guard let self else { continuation.resume(returning: false); return }
            self.unreadableContinuation = continuation
            self.pendingUnreadableFiles = paths
        }
    }
},
```

### Fix D — `UnreadableFilesSheet` view

New file `FilmCan/Sources/Views/Sheets/UnreadableFilesSheet.swift`:

```swift
struct UnreadableFilesSheet: View {
    let paths: [String]
    let onContinue: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("\(paths.count) item(s) could not be read and will be skipped:")
                .font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(paths, id: \.self) { path in
                        Text((path as NSString).lastPathComponent)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxHeight: 200)
            HStack {
                Button("Cancel", role: .cancel, action: onCancel)
                Spacer()
                Button("Continue Anyway", action: onContinue)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}
```

Shown via `.sheet(isPresented:)` in `BackupEditorView.swift` immediately after the existing `DuplicatePromptSheet` sheet at line 95. `isPresented` binds to `!transferViewModel.pendingUnreadableFiles.isEmpty`.

---

## Tests — `CustomCopierServiceE2ETests.swift`

All tests use real temp directories and `CustomCopierService.runCopyFanOut` (not `FanOutCopier` directly). Use `hashListStyle: .ascMHL`, `verifyMode: .paranoid`.

1. **`test_skipPolicy_throughService_doesNotOverwriteUnmanifestedFile`**
   - Pre-place file at dest with content "old"
   - Run with `duplicatePolicy: .skip`
   - Assert dest still contains "old"

2. **`test_overwritePolicy_throughService_replacesUnmanifestedFile`**
   - Pre-place file at dest with content "old"
   - Run with `duplicatePolicy: .overwrite`
   - Assert dest contains new content

3. **`test_incrementPolicy_throughService_allInvariants`**
   - Pre-place file at dest with content "old" (unmanifested)
   - Run with `duplicatePolicy: .increment`, `verifyMode: .paranoid`
   - Assert original file exists and unchanged
   - Assert new suffixed file exists with copied content
   - Assert no crash / no deletion of original
   - Assert MHL contains suffixed filename, not original

4. **`test_unreadableHandler_cancelAbortsRun`**
   - Create unreadable dir in source (chmod 000)
   - Run with handler that always returns false
   - Assert result is cancelled / no files copied to dest

5. **`test_unreadableHandler_confirmProceedsWithReadableFiles`**
   - Create readable + unreadable files in source
   - Run with handler that returns true
   - Assert readable files are copied; unreadable not present at dest

---

## Invariants

- `DestWriter.finalize` must return the path that `rename(2)` succeeded at.
- `DestWriterResult.writtenFilePath` is always the path that exists on disk after the copy task.
- `DestWriterResult.writtenRelPath` is always the manifest-relative name for the MHL entry.
- MHL entry filename matches the file on disk.
- No file is deleted unless its hash mismatched the file that was actually written in this run.
- A run with unreadable sources and no `unreadableHandler` always throws before writing any data.
