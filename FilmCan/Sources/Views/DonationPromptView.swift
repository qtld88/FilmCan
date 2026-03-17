import SwiftUI

struct DonationPromptView: View {
    let transferCount: Int
    let onSkip: () -> Void
    let onDonated: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    introCopy
                    wireTransferCard
                    donationLinks
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
            footerButtons
        }
        .padding(24)
        .frame(minWidth: 520, minHeight: 620)
        .background(FilmCanTheme.backgroundGradient)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Support FilmCan")
                .font(FilmCanFont.title(26))
                .foregroundColor(FilmCanTheme.textPrimary)
            Text("Thanks for using FilmCan to keep your backups safe.")
                .font(FilmCanFont.body(14))
                .foregroundColor(FilmCanTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var introCopy: some View {
        VStack(alignment: .leading, spacing: 8) {
            if transferCount > 0 {
                Text("You have completed \(transferCount) transfers.")
                    .font(FilmCanFont.label(14))
                    .foregroundColor(FilmCanTheme.textPrimary)
            }
            Text("If FilmCan saves you time, please consider supporting development with a donation.")
                .font(FilmCanFont.body(14))
                .foregroundColor(FilmCanTheme.textSecondary)
        }
    }

    private var wireTransferCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Best for EU: Wire Transfer")
                .font(FilmCanFont.label(14))
                .foregroundColor(FilmCanTheme.textPrimary)
            VStack(alignment: .leading, spacing: 6) {
                labeledLine(label: "Recipient", value: "Quentin Devillers")
                labeledLine(label: "IBAN", value: "DE35100110012624820251", monospaced: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FilmCanTheme.panel)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(FilmCanTheme.cardStroke, lineWidth: 1)
        )
        .cornerRadius(12)
    }

    private var donationLinks: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Other Ways to Donate")
                .font(FilmCanFont.label(14))
                .foregroundColor(FilmCanTheme.textPrimary)
            DonationLinkRow(
                title: "Liberapay",
                subtitle: "liberapay.com/FilmCan",
                url: "https://liberapay.com/FilmCan",
                tint: Color(hexString: "#F6C25C")
            )
            DonationLinkRow(
                title: "PayPal",
                subtitle: "paypal.com/donate",
                url: "https://www.paypal.com/donate/?hosted_button_id=W5LXAQ8ENHUQN",
                tint: Color(hexString: "#0070E0")
            )
            DonationLinkRow(
                title: "Buy Me a Coffee",
                subtitle: "buymeacoffee.com/filmcan",
                url: "https://buymeacoffee.com/filmcan",
                tint: Color(hexString: "#FFDD00")
            )
            DonationLinkRow(
                title: "Ko-fi",
                subtitle: "ko-fi.com/filmcan",
                url: "https://ko-fi.com/filmcan",
                tint: Color(hexString: "#FFC900")
            )
            DonationLinkRow(
                title: "Tipeee",
                subtitle: "en.tipeee.com/filmcan",
                url: "https://en.tipeee.com/filmcan",
                tint: Color(hexString: "#FF4D4D")
            )
            DonationLinkRow(
                title: "GitHub Sponsors",
                subtitle: "github.com/sponsors/qtld88",
                url: "https://github.com/sponsors/qtld88",
                tint: Color(hexString: "#EA4AAA")
            )
        }
    }

    private var footerButtons: some View {
        HStack {
            Button("Skip") {
                onSkip()
            }
            .buttonStyle(.plain)
            .foregroundColor(FilmCanTheme.textSecondary)
            Spacer()
            Button("I already donated") {
                onDonated()
            }
            .buttonStyle(.borderedProminent)
            .tint(FilmCanTheme.brandYellow)
            .controlSize(.large)
        }
        .padding(.top, 6)
    }

    private func labeledLine(label: String, value: String, monospaced: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label + ":")
                .font(FilmCanFont.body(12))
                .foregroundColor(FilmCanTheme.textSecondary)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(monospaced ? .system(.body, design: .monospaced) : FilmCanFont.body(13))
                .foregroundColor(FilmCanTheme.textPrimary)
        }
    }
}

private struct DonationLinkRow: View {
    let title: String
    let subtitle: String
    let url: String
    let tint: Color
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            guard let target = URL(string: url) else { return }
            openURL(target)
        } label: {
            HStack {
                Text(title)
                    .font(FilmCanFont.label(13))
                Spacer()
                Text(subtitle)
                    .font(FilmCanFont.body(11))
                    .foregroundColor(FilmCanTheme.textSecondary)
            }
            .foregroundColor(FilmCanTheme.textPrimary)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(tint)
        .controlSize(.large)
    }
}
