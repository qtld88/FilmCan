import SwiftUI

/// The one line that says what goes where: `CITIZENK › Day02 › A003   128 GB · 412 files · 2 drives`.
struct BackupSummaryRow: View {
    let summary: BackupSummary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            HStack(spacing: 6) {
                ForEach(Array(summary.breadcrumb.enumerated()), id: \.offset) { index, name in
                    if index > 0 {
                        Text("›")
                            .font(FCType.body)
                            .foregroundColor(FilmCanTheme.textTertiary)
                    }
                    let isLast = index == summary.breadcrumb.count - 1
                    Text(name)
                        .font(isLast ? FCType.bodyStrong : FCType.body)
                        .foregroundColor(isLast ? FilmCanTheme.textPrimary : FilmCanTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            Text(summary.detail)
                .font(FCType.meta)
                .foregroundColor(FilmCanTheme.textSecondary)
                .lineLimit(1)
                .layoutPriority(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(FilmCanTheme.card))
        .accessibilityElement(children: .combine)
    }
}
