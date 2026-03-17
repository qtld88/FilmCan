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
