import SwiftUI

/// Shown when the user runs a backup whose data is already present at every
/// destination. Instead of adding a history card, FilmCan offers the same
/// integrity check as History's "Check data".
struct AlreadyBackedUpInfo: Identifiable {
    let id = UUID()
    let sources: [String]
    let destinations: [String]
    let fileCount: Int
}

struct AlreadyBackedUpSheet: View {
    let info: AlreadyBackedUpInfo
    let onVerify: (AlreadyBackedUpInfo) async -> (total: Int, missing: Int, mismatched: Int)
    let onDone: () -> Void

    @State private var verifying = false
    @State private var result: (total: Int, missing: Int, mismatched: Int)?

    private var destNames: String {
        info.destinations.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(FilmCanTheme.brandGreen)
                    .font(.title2)
                Text("Already backed up")
                    .font(.headline)
            }

            Text("All \(info.fileCount) file\(info.fileCount == 1 ? "" : "s") are already present at \(destNames). Nothing was copied.")
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let r = result {
                let ok = r.missing == 0 && r.mismatched == 0
                HStack(spacing: 8) {
                    Image(systemName: ok ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(ok ? FilmCanTheme.brandGreen : FilmCanTheme.brandRed)
                    if ok {
                        Text("Verified \(r.total) file\(r.total == 1 ? "" : "s") — all match.")
                    } else {
                        Text("\(r.total) checked · \(r.missing) missing · \(r.mismatched) mismatched.")
                            .foregroundColor(FilmCanTheme.brandRed)
                    }
                }
                .font(.callout)
            }

            HStack {
                Button {
                    Task {
                        verifying = true
                        result = await onVerify(info)
                        verifying = false
                    }
                } label: {
                    if verifying {
                        HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Verifying…") }
                    } else {
                        Text(result == nil ? "Verify data" : "Verify again")
                    }
                }
                .disabled(verifying)

                Spacer()
                Button("Done", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
