# Read-Only Source Lock Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the operator manually remount a source card **read-only** (so nothing — Finder, other apps, the OS — can modify it before offload is confirmed) and later **unlock** it back to read-write, all **without root** via DiskArbitration.

**Architecture:** A new `VolumeRemounter` utility mirrors the existing `DriveEjector` DiskArbitration pattern: unmount the volume, then re-mount the *same* DADisk with (`rdonly`) or without arguments. A per-source lock state lives in `SourceListView`; context-menu **Lock read-only** / **Unlock (make writable)** actions drive it, and the source row shows a lock badge when read-only.

**Tech Stack:** Swift 5.9, DiskArbitration (`DADiskUnmount`, `DADiskMountWithArguments`), SwiftUI, `AppKit` (`NSAlert`).

## ⚠️ Feasibility gate

This entire feature rests on one unverified assumption: **a user-owned removable volume can be remounted `rdonly` via DiskArbitration without root.** This is ~80% likely but exFAT/FAT camera cards are exactly where mount-flag updates get refused. **Task 1 is a hardware spike that must pass before Tasks 2–4 are built.** If the spike fails (dissenter / requires root), STOP and escalate — do not build UI on a broken foundation. Fallback options are listed at the end of Task 1.

DiskArbitration cannot be unit-tested (it needs a real removable device), so this feature's verification is **manual-QA-heavy by nature**. Only the pure `LockState` model gets automated tests.

---

## File Structure

- Create `FilmCan/Sources/Utilities/VolumeRemounter.swift` — DiskArbitration remount (rdonly / rw).
- Create `FilmCan/Sources/Models/VolumeLockState.swift` — pure enum + tests target.
- Create `FilmCan/Tests/VolumeLockStateTests.swift` — unit tests for the pure model.
- Modify `FilmCan/Sources/Views/SourceListView.swift` — lock/unlock actions + badge.

---

## Task 1: Feasibility spike — `VolumeRemounter` (HARDWARE-GATED)

**Files:**
- Create: `FilmCan/Sources/Utilities/VolumeRemounter.swift`

- [ ] **Step 1: Implement the remounter**

Create `FilmCan/Sources/Utilities/VolumeRemounter.swift`. This mirrors `DriveEjector`'s session/context/continuation plumbing. The two-hop flow is: resolve the volume's `DADisk` → `DADiskUnmount` (volume only, NOT whole disk) → on success, `DADiskMountWithArguments` the same disk with or without the `rdonly` argument. The mount arguments array is NULL-terminated; the `rdonly` `CFString` is retained inside the context so it outlives the async hop.

```swift
import Foundation
import DiskArbitration

/// Remounts a single volume read-only or read-write via DiskArbitration.
/// No root required for user-owned removable media (same tier as DriveEjector).
///
/// Flow: unmount the volume (not the whole disk), then re-mount the same DADisk
/// with the `rdonly` mount argument (read-only) or none (read-write).
enum VolumeRemounter {

    enum RemountError: LocalizedError {
        case sessionUnavailable
        case diskLookupFailed
        case unmountRefused(String)
        case mountRefused(String)

        var errorDescription: String? {
            switch self {
            case .sessionUnavailable: return "Couldn't reach the disk subsystem. Try again."
            case .diskLookupFailed:   return "Couldn't identify the drive for this path."
            case .unmountRefused(let why): return "The drive is in use and couldn't be remounted. \(why)"
            case .mountRefused(let why):   return "The drive was unmounted but couldn't be remounted. \(why)"
            }
        }
    }

    /// Remount the volume backing `volumeURL` read-only.
    static func remountReadOnly(volumeURL: URL) async -> Result<Void, RemountError> {
        await remount(volumeURL: volumeURL, readOnly: true)
    }

    /// Remount the volume backing `volumeURL` read-write.
    static func remountReadWrite(volumeURL: URL) async -> Result<Void, RemountError> {
        await remount(volumeURL: volumeURL, readOnly: false)
    }

    // MARK: - Core

    private static func remount(volumeURL: URL, readOnly: Bool) async -> Result<Void, RemountError> {
        await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "com.filmcan.app.remount")
            queue.async {
                guard let session = DASessionCreate(kCFAllocatorDefault) else {
                    continuation.resume(returning: .failure(.sessionUnavailable)); return
                }
                DASessionSetDispatchQueue(session, queue)

                guard let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, volumeURL as CFURL) else {
                    DASessionSetDispatchQueue(session, nil)
                    continuation.resume(returning: .failure(.diskLookupFailed)); return
                }

                let ctx = RemountContext(session: session, disk: disk,
                                         readOnly: readOnly, continuation: continuation)
                let raw = Unmanaged.passRetained(ctx).toOpaque()
                DADiskUnmount(disk, DADiskUnmountOptions(kDADiskUnmountOptionDefault), unmountCallback, raw)
            }
        }
    }

    private final class RemountContext {
        let session: DASession
        let disk: DADisk
        let readOnly: Bool
        // Retain the mount-arg string for the lifetime of the async mount call.
        let rdonlyArg = "rdonly" as CFString
        let continuation: CheckedContinuation<Result<Void, RemountError>, Never>
        init(session: DASession, disk: DADisk, readOnly: Bool,
             continuation: CheckedContinuation<Result<Void, RemountError>, Never>) {
            self.session = session; self.disk = disk
            self.readOnly = readOnly; self.continuation = continuation
        }
        func finish(_ r: Result<Void, RemountError>) {
            DASessionSetDispatchQueue(session, nil)
            continuation.resume(returning: r)
        }
    }

    private static func dissenterMessage(_ dissenter: DADissenter) -> String {
        if let s = DADissenterGetStatusString(dissenter) { return s as String }
        return "(error \(String(format: "0x%08X", DADissenterGetStatus(dissenter))))"
    }

    // Unmount done → mount the same disk with/without rdonly.
    private static let unmountCallback: DADiskUnmountCallback = { _, dissenter, context in
        guard let context else { return }
        let ctx = Unmanaged<RemountContext>.fromOpaque(context).takeUnretainedValue()
        if let dissenter {
            Unmanaged<RemountContext>.fromOpaque(context).release()
            ctx.finish(.failure(.unmountRefused(dissenterMessage(dissenter))))
            return
        }
        let options = DADiskMountOptions(kDADiskMountOptionDefault)
        if ctx.readOnly {
            // NULL-terminated array of CFString mount arguments.
            var args: [Unmanaged<CFString>?] = [Unmanaged.passUnretained(ctx.rdonlyArg), nil]
            args.withUnsafeMutableBufferPointer { buf in
                DADiskMountWithArguments(ctx.disk, nil, options, mountCallback, context, buf.baseAddress)
            }
        } else {
            DADiskMount(ctx.disk, nil, options, mountCallback, context)
        }
    }

    // Mount done → terminal; release the retained context.
    private static let mountCallback: DADiskMountCallback = { _, dissenter, context in
        guard let context else { return }
        let ctx = Unmanaged<RemountContext>.fromOpaque(context).takeRetainedValue()
        if let dissenter {
            ctx.finish(.failure(.mountRefused(dissenterMessage(dissenter))))
        } else {
            ctx.finish(.success(()))
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild build -project FilmCan/FilmCan.xcodeproj -scheme FilmCan -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: HARDWARE SPIKE — verify no-root remount actually works**

There is no automated test for DiskArbitration. Add a temporary debug button OR use an lldb/REPL harness to call, on a **real exFAT SD card** mounted at `/Volumes/<card>`:

```swift
await VolumeRemounter.remountReadOnly(volumeURL: URL(fileURLWithPath: "/Volumes/<card>"))
```

Verify ALL of:
- Returns `.success`.
- The card is still mounted at `/Volumes/<card>` (not ejected).
- `mount | grep <card>` shows `read-only`.
- `touch /Volumes/<card>/x` fails with "Read-only file system".
- Then `remountReadWrite(...)` returns `.success` and `touch` succeeds again.
- No password prompt appeared, app is **not** running as root.

Repeat on a **FAT32** card and an **APFS/HFS+** SSD if available.

**GATE:**
- ✅ If all pass → remove the debug harness, commit, proceed to Task 2.
- ❌ If `.unmountRefused` (card busy) → document; Task 2 must surface a clear "close other apps using the card" message. Still proceed.
- ❌ If `.mountRefused` with a permission/root dissenter on rdonly → **STOP. Escalate to the human.** The no-root approach is not viable for that filesystem; options are (a) ship the feature only for filesystems that permit it, (b) defer the feature, (c) reopen the privileged-helper decision (out of scope for the signal-only track). Do not proceed to UI.

- [ ] **Step 4: Commit (only if spike passed)**

```bash
git add FilmCan/Sources/Utilities/VolumeRemounter.swift
git commit -m "feat(readonly-lock): add VolumeRemounter (DiskArbitration, no root)"
```

---

## Task 2: Lock-state model + tests

**Files:**
- Create: `FilmCan/Sources/Models/VolumeLockState.swift`
- Test: `FilmCan/Tests/VolumeLockStateTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `FilmCan/Tests/VolumeLockStateTests.swift`:

```swift
import XCTest
@testable import FilmCan

final class VolumeLockStateTests: XCTestCase {

    func test_isReadOnly_onlyWhenLocked() {
        XCTAssertFalse(VolumeLockState.writable.isReadOnly)
        XCTAssertFalse(VolumeLockState.working.isReadOnly)
        XCTAssertTrue(VolumeLockState.readOnly.isReadOnly)
    }

    func test_canLock_onlyFromWritable() {
        XCTAssertTrue(VolumeLockState.writable.canLock)
        XCTAssertFalse(VolumeLockState.readOnly.canLock)
        XCTAssertFalse(VolumeLockState.working.canLock)
    }

    func test_canUnlock_onlyFromReadOnly() {
        XCTAssertTrue(VolumeLockState.readOnly.canUnlock)
        XCTAssertFalse(VolumeLockState.writable.canUnlock)
        XCTAssertFalse(VolumeLockState.working.canUnlock)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project FilmCan/FilmCan.xcodeproj -scheme FilmCan -destination 'platform=macOS' -only-testing:FilmCanTests/VolumeLockStateTests`
Expected: FAIL — `cannot find 'VolumeLockState' in scope`.

- [ ] **Step 3: Write the model**

Create `FilmCan/Sources/Models/VolumeLockState.swift`:

```swift
import Foundation

/// UI-facing lock state of a source volume.
enum VolumeLockState: Equatable {
    /// Normal, read-write.
    case writable
    /// Remount in progress (lock or unlock) — actions disabled.
    case working
    /// Remounted read-only by the operator.
    case readOnly

    var isReadOnly: Bool { self == .readOnly }
    var canLock: Bool { self == .writable }
    var canUnlock: Bool { self == .readOnly }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project FilmCan/FilmCan.xcodeproj -scheme FilmCan -destination 'platform=macOS' -only-testing:FilmCanTests/VolumeLockStateTests`
Expected: PASS — 3/3.

- [ ] **Step 5: Commit**

```bash
git add FilmCan/Sources/Models/VolumeLockState.swift FilmCan/Tests/VolumeLockStateTests.swift
git commit -m "feat(readonly-lock): add VolumeLockState model"
```

---

## Task 3: Lock / Unlock context-menu actions

**Files:**
- Modify: `FilmCan/Sources/Views/SourceListView.swift` (`sourceRow` contextMenu ~line 295; add lock-state store + handlers near `ejectVolume` ~line 494)

- [ ] **Step 1: Add per-source lock-state store**

In `SourceListView`, add a state dictionary keyed by volume root, alongside the other `@State` properties near the top of the struct:

```swift
    @State private var lockStates: [String: VolumeLockState] = [:]
```

- [ ] **Step 2: Add the lock/unlock handlers**

Add these methods next to `ejectVolume(for:onSuccess:)` (~line 494) in `SourceListView`:

```swift
    private func lockState(for path: String) -> VolumeLockState {
        guard let root = volumeRootPath(for: path) else { return .writable }
        return lockStates[root] ?? .writable
    }

    private func lockReadOnly(_ path: String) {
        guard let root = volumeRootPath(for: path) else {
            ejectErrorMessage = "This source isn't on a lockable volume."
            return
        }
        let url = URL(fileURLWithPath: root)
        lockStates[root] = .working
        Task { @MainActor in
            switch await VolumeRemounter.remountReadOnly(volumeURL: url) {
            case .success:
                lockStates[root] = .readOnly
            case .failure(let error):
                lockStates[root] = .writable
                ejectErrorMessage = error.errorDescription
                DebugLog.warn("Lock read-only failed for \(root): \(error)")
            }
        }
    }

    private func unlockWritable(_ path: String) {
        guard let root = volumeRootPath(for: path) else { return }
        let url = URL(fileURLWithPath: root)
        lockStates[root] = .working
        Task { @MainActor in
            switch await VolumeRemounter.remountReadWrite(volumeURL: url) {
            case .success:
                lockStates[root] = .writable
            case .failure(let error):
                lockStates[root] = .readOnly
                ejectErrorMessage = error.errorDescription
                DebugLog.warn("Unlock failed for \(root): \(error)")
            }
        }
    }
```

- [ ] **Step 3: Add menu items to the source-row context menu**

In `sourceRow`, extend the `.contextMenu` block (~line 295) so it reads:

```swift
        .contextMenu {
            Button("Remove source from this backup") {
                removeSource(source.path)
            }
            Button("Remove and eject source from this backup") {
                removeAndEjectSource(source.path)
            }
            Divider()
            let state = lockState(for: source.path)
            if state.canLock {
                Button("Lock read-only") { lockReadOnly(source.path) }
            }
            if state.canUnlock {
                Button("Unlock (make writable)") { unlockWritable(source.path) }
            }
        }
```

- [ ] **Step 4: Build**

Run: `xcodebuild build -project FilmCan/FilmCan.xcodeproj -scheme FilmCan -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add FilmCan/Sources/Views/SourceListView.swift
git commit -m "feat(readonly-lock): lock/unlock source volume from context menu"
```

---

## Task 4: Read-only badge on the source row

**Files:**
- Modify: `FilmCan/Sources/Views/SourceListView.swift` (`sourceRow` VStack, after `CardSealBadge` ~line 284)

- [ ] **Step 1: Add the badge**

In `sourceRow`, immediately after the `CardSealBadge(sourcePath: source.path)` line (~284), add:

```swift
                if lockState(for: source.path).isReadOnly {
                    Label("Read-only (locked)", systemImage: "lock.fill")
                        .font(FilmCanFont.body(11))
                        .foregroundColor(FilmCanTheme.textSecondary)
                }
```

- [ ] **Step 2: Build**

Run: `xcodebuild build -project FilmCan/FilmCan.xcodeproj -scheme FilmCan -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add FilmCan/Sources/Views/SourceListView.swift
git commit -m "feat(readonly-lock): show lock badge on read-only source"
```

---

## Manual QA (real hardware — gating)

On a real exFAT SD card at `/Volumes/<card>`:

1. Add the card as a source. Right-click → **Lock read-only**. → badge shows 🔒 "Read-only (locked)"; `touch /Volumes/<card>/x` fails; card stays mounted.
2. Right-click → **Unlock (make writable)**. → badge clears; `touch` succeeds.
3. Lock, then run a backup. → backup reads + verifies fine from a read-only source (FilmCan only reads sources).
4. Lock a card that another app is actively writing (open a large file). → `.unmountRefused`; a clear error alert; state falls back to writable (not stuck on "working").
5. Lock, then **eject** the card. → eject still works from the read-only state.
6. Lock, physically pull + re-insert the card. → it comes back read-write (lock does not persist across re-insert); FilmCan shows writable. Confirm no stale 🔒.
7. FAT32 + APFS cards: repeat 1–2. Note any filesystem that refuses (feeds the Task 1 gate outcome).

---

## Out of scope (YAGNI)

- Persisting lock state across app relaunch or card re-insert (a re-inserted card auto-mounts read-write; that's fine).
- Auto-locking on add or during copy (decided: manual only).
- Any privileged-helper / root path (signal-only track).
- Locking destination volumes (sources only).

## Self-Review Notes

- **Spec coverage:** manual lock button (Task 3), unlock action (Task 3), no-root remount (Task 1), read-only badge (Task 4), graceful failure fallback (Task 3 handlers reset state + alert). ✅
- **Type consistency:** `VolumeLockState.{writable,working,readOnly}` + `.canLock/.canUnlock/.isReadOnly` used identically in Tasks 2–4. `VolumeRemounter.remountReadOnly/remountReadWrite` signatures match their call sites. `volumeRootPath(for:)` is the existing private helper in `SourceListView` (line ~520). ✅
- **Feasibility honesty:** Task 1 is an explicit hardware gate with a STOP condition; no UI is built before remount-rdonly is proven no-root. ✅
- **No placeholders:** every code step is complete; the only manual steps (hardware spike, QA) are unavoidable for DiskArbitration and are marked as such. ✅
