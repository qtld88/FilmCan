# Fan-Out Copy — Smoke QA Checklist

## Prerequisites
- [ ] Build passes with `xcodebuild`
- [ ] All unit tests pass

## 1. Foundation models
- [ ] `Constants.ringCapBytesPerDest()` returns values between 64MB–256MB depending on RAM
- [ ] `VerifyMode` descriptions render in SwiftUI pickers
- [ ] `DestStatus` states transition correctly (pending → active → complete | failed)

## 2. Drive classification
- [ ] `DriveSpeedClassifier.expectedSpeedMBps` returns plausible speeds for internal SSD, external HDD, USB2, exFAT
- [ ] `slowestDestClass` correctly ranks exFAT < HDD < network < unknown < SSD < NVMe
- [ ] `requiresFullFsync` returns `true` for all external and exFAT volumes

## 3. File system hardening
- [ ] `F_NOCACHE` is set on source and dest file handles during copy (no crash on pre-HFS+ drives)
- [ ] `F_FULLFSYNC` fires on dest handles when `requiresFullFsync` is true
- [ ] `chunkSizeOverride` overrides default buffer sizes

## 4. Bounded channel
- [ ] Backpressure works: sending more than capacity blocks
- [ ] `finish()` unblocks all waiting producers/consumers
- [ ] `AsyncSequence` iteration produces all sent elements

## 5. MHL hashlist
- [ ] Writer produces valid XML with `<hashlist>`, `<file>`, `<hash>` elements
- [ ] Incremental flush writes entries in batches of 5
- [ ] `cancel()` removes the file entirely
- [ ] Reader parses back the same entries

## 6. DestWriter
- [ ] Temp file uses `.filmcan-<uuid>-<name>` pattern
- [ ] On success, temp file atomically replaces target
- [ ] No temp files left after successful copy

## 7. FanOutCopier end-to-end
- [ ] Copies file to 2+ destinations simultaneously
- [ ] Content matches source on all destinations
- [ ] No temp files remain on any destination
- [ ] MHL file generated when `mhlBasePath` is set
- [ ] `sourceNotFound` error when source is missing
- [ ] `noDestinations` error when destination list is empty

## 8. Dry run
- [ ] `DryRunReport` correctly estimates transfer times from drive classification
- [ ] Speed disparity warnings fire when ratio > 3×
- [ ] `formattedSummary` displays readable output

## 9. Views
- [ ] `DryRunSheet` shows per-destination estimates
- [ ] `MultiDestSummaryView` updates progress tiles live
- [ ] `DestResultRow` displays success/failure with stats
- [ ] `DestPickerView` supports search and multi-select
- [ ] `TotalTransfersEditMode` allows editing destination configs

## 10. Webhook notification
- [ ] `sendDestNotification` fires per-destination ntfy message
- [ ] Payload includes destination name, path, status, bytes, verify mode

## Known issues (pre-existing)
_List any pre-existing warnings or skipped tests here._
