import SwiftUI

/// Renders a list of DestResult rows, surfacing a "Retry" button on each
/// failed result that opens RetryRepairSheet. The repair itself is delegated
/// to the supplied closure so this panel stays UI-only.
struct FailedDestRetryPanel: View {
    let results: [DestResult]
    let sourcePaths: [String]
    let onRepair: (_ failed: DestResult, _ sibling: DestResult, _ choice: RetryRepairSheet.RepairChoice) -> Void

    @State private var pending: DestResult?
    @State private var pendingSibling: DestResult?
    @State private var pendingSourceAvailable: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(results, id: \.destinationPath) { result in
                let hasSibling = !result.success && pickFastestSurvivingSibling(failed: result) != nil
                DestResultRow(
                    result: result,
                    onRetry: hasSibling ? { presentRetry(for: result) } : nil
                )
            }
        }
        .sheet(item: Binding(
            get: { pending },
            set: { newValue in if newValue == nil { pending = nil; pendingSibling = nil } }
        )) { failed in
            if let sibling = pendingSibling {
                RetryRepairSheet(
                    failedDest: failed,
                    siblingDest: sibling,
                    sourceAvailable: pendingSourceAvailable,
                    onPick: { choice in
                        // Hand back to caller; caller will run async and update @Published results.
                        // We close the sheet immediately so the row's spinner + status badge
                        // (driven by the published results) becomes visible.
                        onRepair(failed, sibling, choice)
                        pending = nil
                        pendingSibling = nil
                    },
                    onCancel: {
                        pending = nil
                        pendingSibling = nil
                    }
                )
            }
        }
    }

    private func presentRetry(for failed: DestResult) {
        guard let sibling = pickFastestSurvivingSibling(failed: failed) else {
            return
        }
        pendingSibling = sibling
        pendingSourceAvailable = sourcePaths.allSatisfy { FileManager.default.fileExists(atPath: $0) }
        pending = failed
    }

    private func pickFastestSurvivingSibling(failed: DestResult) -> DestResult? {
        let candidates = results.filter { $0.success && $0.destinationPath != failed.destinationPath }
        guard !candidates.isEmpty else { return nil }
        return candidates.max(by: { left, right in
            let lSpeed = DriveSpeedClassifier.expectedSpeedMBps(DriveSpeedClassifier.info(for: left.destinationPath))
            let rSpeed = DriveSpeedClassifier.expectedSpeedMBps(DriveSpeedClassifier.info(for: right.destinationPath))
            return lSpeed < rSpeed
        })
    }
}

extension DestResult: Identifiable {
    var id: String { destinationPath }
}
