import SwiftUI

struct NetflixValidationInfo: Identifiable {
    let id = UUID()
    let issues: [NetflixNameValidator.Issue]
}

/// Non-blocking pre-flight warning for Netflix-prohibited roll names. Lets the user
/// auto-fix (rename the source folders), run anyway, or cancel.
struct NetflixValidationSheet: View {
    let info: NetflixValidationInfo
    let onAutoFix: () -> Void
    let onRunAnyway: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Netflix naming issues")
                .font(.headline)
            Text("Netflix Ingest requires roll names without certain characters, and each roll must be unique.")
                .font(.caption)
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(info.issues.enumerated()), id: \.offset) { _, issue in
                    switch issue {
                    case .prohibitedChars(let name, let chars):
                        Text("• “\(name)” contains prohibited characters: \(chars)")
                            .font(.callout)
                    case .duplicateRoll(let name):
                        Text("• Duplicate roll name: “\(name)”")
                            .font(.callout)
                    }
                }
            }
            Text("Auto-fix renames the affected source folders on disk (prohibited characters → “_”, duplicates get a numeric suffix).")
                .font(.caption)
                .foregroundColor(.secondary)
            HStack {
                Button("Cancel", role: .cancel, action: onCancel)
                Spacer()
                Button("Run anyway", action: onRunAnyway)
                Button("Auto-fix & run", action: onAutoFix)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 440)
    }
}
