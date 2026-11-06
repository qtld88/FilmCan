import SwiftUI
import AppKit

enum AppearanceDefaults {
    static let accentHex = "#FFC900"
    static let accentMode = "kodak"
    static let accentKodak = "#FFC900"
    static let accentFuji = "#3DAA4A"
    static let accentSony = "#F4F2EE"
    static let accentRed = "#ED1C24"
    static let accentArri = "#015CA5"
    static let successHex = "#3B9953"
    static let backgroundHex = "#1B1B1B"
    static let sidebarHex = "#1F1F1F"
    static let panelHex = "#2A2A2A"
    static let textHex = "#F4F2EE"
}

enum FilmCanTheme {
    private static func color(for key: String, defaultHex: String) -> Color {
        let stored = UserDefaults.standard.string(forKey: key)
        return Color(hexString: stored ?? defaultHex)
    }

    static var background: Color {
        color(for: "appearanceBackgroundHex", defaultHex: AppearanceDefaults.backgroundHex)
    }

    static var backgroundGradient: LinearGradient {
        LinearGradient(colors: [background, background], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static var sidebar: Color {
        color(for: "appearanceSidebarHex", defaultHex: AppearanceDefaults.sidebarHex)
    }
    static var panel: Color {
        color(for: "appearancePanelHex", defaultHex: AppearanceDefaults.panelHex)
    }
    static var card: Color {
        panel
    }
    /// Settings card grey — darker than `panel`/`card` so the settings card reads as
    /// distinct from the Copy From / Save To data cards.
    static var settingsCard: Color {
        sidebar
    }
    static var cardStroke: Color {
        textPrimary.opacity(0.2)
    }
    static var cardStrokeStrong: Color {
        textPrimary.opacity(0.3)
    }
    static var textPrimary: Color {
        color(for: "appearanceTextHex", defaultHex: AppearanceDefaults.textHex)
    }
    static var textSecondary: Color {
        textPrimary.opacity(0.75)
    }
    static var textTertiary: Color {
        textPrimary.opacity(0.55)
    }
    static var brandYellow: Color {
        let mode = UserDefaults.standard.string(forKey: "appearanceAccentMode") ?? AppearanceDefaults.accentMode
        if mode == "system" {
            return Color.accentColor
        }
        return color(for: "appearanceAccentHex", defaultHex: AppearanceDefaults.accentHex)
    }
    static var brandOrange: Color {
        Color(hex: 0xF28C28)
    }
    static var brandRed: Color {
        Color(hex: 0xE45141)
    }
    static var brandGreen: Color {
        color(for: "appearanceSuccessHex", defaultHex: AppearanceDefaults.successHex)
    }
    static var brandBlue: Color {
        Color(hex: 0x5BA7FF)
    }
    static var toggleTint: Color {
        brandYellow
    }
    static var highlight: Color {
        brandYellow.opacity(0.2)
    }

    // Fill green #3B9953 is 4.0:1 on a card (fails WCAG AA); text needs 4.5:1.
    static var successText: Color {
        let stored = UserDefaults.standard.string(forKey: "appearanceSuccessHex")
        if stored == nil || stored?.uppercased() == AppearanceDefaults.successHex {
            return Color(hex: 0x52B86B)
        }
        return brandGreen
    }
    // brandRed is 3.8:1 on a card; this shade is 5.2:1.
    static var dangerText: Color {
        Color(hex: 0xF2786A)
    }
}

// Bars sit on different backgrounds (window vs card): drawing every segment over the
// opaque track keeps the translucent "to copy" colour identical in both windows.
enum FCCapacity {
    static let track = Color(hex: 0x3A3A3C)
    static let free = track
    static let used = Color(hex: 0x8A8A8E)
    static let toCopyOpacity = 0.6

    static func toCopyColor(ratioToAvailable: Double?, backupFraction: Double, alreadyStored: Bool) -> Color {
        if alreadyStored { return FilmCanTheme.brandGreen }
        if let ratio = ratioToAvailable, ratio > 1.0 { return FilmCanTheme.brandRed }
        if backupFraction > 0.8 { return FilmCanTheme.brandRed }
        if backupFraction > 0.6 { return FilmCanTheme.brandOrange }
        return FilmCanTheme.brandGreen
    }
}

enum FCHistoryCard {
    static let outer = Color(hex: 0x383838)
    static let middle = Color(white: 0.4)
    static let inner = Color(hex: 0x383838)
    static let strokeStrong = Color(white: 0.12)
    // Black on #3B9953 is 5.87:1; the light text colour was 3.2:1.
    static let stickerText = Color.black

    enum Source {
        static let outerRadius: CGFloat = 40
        static let innerRadius: CGFloat = 35
    }
    enum Destination {
        static let outerRadius: CGFloat = 26
        static let middleRadius: CGFloat = 20
        static let coreRadius: CGFloat = 15
    }
}

struct FCPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        FCPrimaryButtonBody(configuration: configuration)
    }

    private struct FCPrimaryButtonBody: View {
        let configuration: ButtonStyle.Configuration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(FilmCanFont.label(13))
                .foregroundColor(isEnabled ? .black : FilmCanTheme.textTertiary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(FilmCanTheme.brandYellow.opacity(isEnabled ? 1 : 0.3))
                )
                .opacity(configuration.isPressed ? 0.8 : 1)
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

enum FilmCanFont {
    private static func font(named names: [String], size: CGFloat, weight: Font.Weight) -> Font {
        for name in names {
            if NSFont(name: name, size: size) != nil {
                return .custom(name, size: size)
            }
        }
        return .system(size: size, weight: weight, design: .default)
    }

    static func title(_ size: CGFloat) -> Font {
        return font(
            named: ["SpaceGrotesk-Bold", "Space Grotesk Bold", "AvenirNext-Heavy", "Avenir Next Heavy"],
            size: size,
            weight: .bold
        )
    }

    static func label(_ size: CGFloat) -> Font {
        return font(
            named: ["SpaceGrotesk-SemiBold", "Space Grotesk SemiBold", "AvenirNext-DemiBold", "Avenir Next Demi Bold"],
            size: size,
            weight: .semibold
        )
    }

    static func body(_ size: CGFloat) -> Font {
        return font(
            named: ["SpaceGrotesk-Regular", "Space Grotesk", "AvenirNext-Regular", "Avenir Next"],
            size: size,
            weight: .regular
        )
    }
}

private extension Color {
    init(hex: Int) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue)
    }
}
