import SwiftUI

/// Shown above the demo movie: says what is made up, and removes it all in one click.
struct DemoBanner: View {
    let canStop: Bool
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .foregroundColor(FilmCanTheme.brandYellow)
            VStack(alignment: .leading, spacing: 2) {
                Text("Demo: made-up cards and drives")
                    .font(FCType.bodyStrong)
                    .foregroundColor(FilmCanTheme.textPrimary)
                Text("They are folders on this Mac. Start the backup: the copy and the check are real.")
                    .font(FCType.meta)
                    .foregroundColor(FilmCanTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Button("Stop the demo", action: onStop)
                .disabled(!canStop)
                .help(canStop ? "Removes the demo movie, its made-up cards and drives, and its history"
                              : "Wait for the backup to finish, or stop it first")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(FilmCanTheme.brandYellow.opacity(0.10))
        .overlay(alignment: .bottom) { Divider().background(FilmCanTheme.cardStroke) }
    }
}
