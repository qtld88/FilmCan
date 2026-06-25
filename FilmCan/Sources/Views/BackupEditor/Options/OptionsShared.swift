import SwiftUI

/// Shared layout constants for Options UI components.
enum OptionsLayout {
    static let iconWidth: CGFloat = 32
    static let spacing: CGFloat = 20
    static let toggleWidth: CGFloat = 60
    static let menuWidth: CGFloat = 140
    static let textWidth: CGFloat = 320
    static let basicTextWidth: CGFloat = 268
}

/// Resolves the effective text width for an options row, accounting for available space
/// and reserved room for icon, toggle, and spacing.
func optionsResolvedTextWidth(_ base: CGFloat, availableWidth: CGFloat) -> CGFloat {
    guard availableWidth > 0 else { return base }
    let minWidth: CGFloat = 180
    let reserved = OptionsLayout.iconWidth + OptionsLayout.toggleWidth + OptionsLayout.spacing * 2 + 24
    let maxForText = max(minWidth, availableWidth - reserved)
    return min(base, maxForText)
}

/// Resolves the effective menu width for an options row, accounting for available space,
/// the resolved text width, and reserved room for icon and spacing.
func optionsResolvedMenuWidth(_ base: CGFloat, textWidth: CGFloat, availableWidth: CGFloat) -> CGFloat {
    guard availableWidth > 0 else { return base }
    let minWidth: CGFloat = 120
    let reserved = OptionsLayout.iconWidth + OptionsLayout.spacing * 2 + textWidth + 16
    let maxForMenu = max(minWidth, availableWidth - reserved)
    return min(base, maxForMenu)
}

/// A shared options row with icon, title, subtitle, toggle, and optional help text/info popover.
@ViewBuilder
func optionsRow(
    icon: String,
    iconColor: Color,
    title: String,
    subtitle: String,
    isOn: Binding<Bool>,
    textWidth: CGFloat? = nil,
    helpText: String? = nil,
    info: InfoPopoverContent? = nil,
    availableWidth: CGFloat
) -> some View {
    let resolvedTextWidth = optionsResolvedTextWidth(textWidth ?? OptionsLayout.textWidth, availableWidth: availableWidth)
    let row = HStack(spacing: OptionsLayout.spacing) {
        Image(systemName: icon)
            .font(.title3)
            .foregroundColor(iconColor)
            .frame(width: OptionsLayout.iconWidth)
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(title)
                    .font(FilmCanFont.label(13))
                    .foregroundColor(FilmCanTheme.textPrimary)
                if let info {
                    InfoPopoverButton(content: info)
                }
            }
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(FilmCanFont.body(11))
                    .foregroundColor(FilmCanTheme.textSecondary)
            }
        }
        .frame(width: resolvedTextWidth, alignment: .leading)
        Toggle("", isOn: isOn)
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .scaleEffect(0.8)
            .tint(FilmCanTheme.toggleTint)
            .frame(width: OptionsLayout.toggleWidth, alignment: .leading)
    }
    if let helpText {
        AnyView(row.help(helpText))
    } else {
        AnyView(row)
    }
}
