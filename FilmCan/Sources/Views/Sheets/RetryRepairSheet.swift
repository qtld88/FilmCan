import SwiftUI

struct RetryRepairSheet: View {
    enum RepairChoice {
        case fromSource
        case fromSibling
    }

    let failedDest: DestResult
    let siblingDest: DestResult
    let sourceAvailable: Bool
    let onPick: (RepairChoice) -> Void
    let onCancel: () -> Void

    @State private var selection: RepairChoice = .fromSource

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .foregroundColor(.orange)
                    .font(.title2)
                Text("Retry failed destination").font(.title2)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(failedDest.displayName).font(.headline)
                if let reason = failedDest.failureReason {
                    Text(reason.displayMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)

            Divider()

            if sourceAvailable {
                Text("Source still attached. Read from which?")
                    .font(.callout)
                Picker("", selection: $selection) {
                    Text("Source (card stays attached, slower if card is far)")
                        .tag(RepairChoice.fromSource)
                    Text("Sibling: \(siblingDest.displayName) (faster, releases source)")
                        .tag(RepairChoice.fromSibling)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill").foregroundColor(.blue)
                    Text("Source unavailable. Repairing from sibling: \(siblingDest.displayName).")
                        .font(.callout)
                }
                .onAppear { selection = .fromSibling }
            }

            HStack {
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Retry") { onPick(selection) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 460, minHeight: 240)
    }
}
