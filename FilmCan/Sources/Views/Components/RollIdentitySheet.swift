import SwiftUI

/// Shown when a roll with the same name already exists at a destination from a prior
/// run. Presents the engine's recommendation (resume the same card vs save as a new
/// "-N" roll) pre-selected, while letting the user override.
struct RollIdentitySheet: View {
    let prompt: RollIdentityPrompt
    /// `true` to resume into the existing roll, `false` to save as a new roll.
    let onDecision: (_ isResume: Bool) -> Void

    private var recommendIsResume: Bool { prompt.recommendation != .newCard }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("A roll named “\(prompt.rollName)” already exists")
                .font(.headline)
            Text(explanation)
                .fixedSize(horizontal: false, vertical: true)
            if let recorded = prompt.recordedVolumeName {
                Text("Existing roll came from “\(recorded)”\(lastSeenSuffix)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            HStack {
                Spacer()
                Button("Save as “\(prompt.proposedNewName)”") { onDecision(false) }
                    .keyboardShortcut(recommendIsResume ? nil : .defaultAction)
                Button("Resume “\(prompt.rollName)”") { onDecision(true) }
                    .keyboardShortcut(recommendIsResume ? .defaultAction : nil)
            }
        }
        .padding(20)
        .frame(width: 470)
    }

    private var explanation: String {
        switch prompt.recommendation {
        case .resumeSameCard:
            return "This looks like the SAME card (matching volume “\(prompt.sourceVolumeName)”). Recommended: Resume — only new or changed files are added to the existing roll."
        case .newCard:
            return "This is a DIFFERENT card from the one already backed up under this name. Recommended: save it as “\(prompt.proposedNewName)” so the two cards stay separate, each with its own checksums."
        case .unknown:
            return "We can't confirm whether this is the same card (no identity was recorded, or the card has no stable ID). Resume if it's the same card; otherwise save it as “\(prompt.proposedNewName)” to keep them separate."
        }
    }

    private var lastSeenSuffix: String {
        guard let date = prompt.recordedLastSeen else { return "" }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return " · last backup \(f.string(from: date))"
    }
}
