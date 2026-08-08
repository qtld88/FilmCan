import SwiftUI

/// Surfaces `ConfigurationStorage`'s persistence failures. Nothing else reads them, so
/// without this strip a quarantined file silently blocks every later `save()` and the
/// user keeps editing settings that are no longer written to disk.
struct StorageErrorBanner: View {
    let loadError: String?
    let saveError: String?

    /// A load failure blocks `save()` for the rest of the session; a save failure may
    /// clear itself on the next successful write.
    private var isBlocking: Bool { loadError != nil }

    private var headline: String {
        isBlocking
            ? "FilmCan has stopped saving your settings"
            : "Your last change could not be saved"
    }

    private var details: [String] {
        [loadError, saveError]
            .compactMap { $0 }
            .flatMap { $0.components(separatedBy: "\n") }
            .filter { !$0.isEmpty }
    }

    private var tint: Color {
        isBlocking ? FilmCanTheme.brandRed : FilmCanTheme.brandOrange
    }

    var body: some View {
        if !details.isEmpty {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(tint)
                    .font(.system(size: 12, weight: .semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline)
                        .font(FilmCanFont.label(12))
                        .foregroundColor(FilmCanTheme.textPrimary)
                    ForEach(Array(details.enumerated()), id: \.offset) { _, detail in
                        Text(detail)
                            .font(FilmCanFont.body(11))
                            .foregroundColor(FilmCanTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.18))
            .background(FilmCanTheme.sidebar)
            .overlay(alignment: .bottom) {
                Divider()
                    .background(FilmCanTheme.cardStroke)
            }
        }
    }
}
