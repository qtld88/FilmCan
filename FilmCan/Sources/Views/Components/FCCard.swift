import SwiftUI

enum FCRadius {
    static let card: CGFloat = 10
    static let inner: CGFloat = 8
    static let control: CGFloat = 6
    static let bar: CGFloat = 4
}

enum FCStroke {
    static let hairline: CGFloat = 1
}

enum FCCardRole {
    case data
    case settings

    var background: Color {
        switch self {
        case .data: return FilmCanTheme.panel
        case .settings: return FilmCanTheme.settingsCard
        }
    }

    var stroke: Color {
        switch self {
        case .data: return FilmCanTheme.textPrimary.opacity(0.3)
        case .settings: return FilmCanTheme.textPrimary.opacity(0.2)
        }
    }
}

struct FCCardSurface: ViewModifier {
    var role: FCCardRole = .data
    var strokeColor: Color? = nil
    var lineWidth: CGFloat = FCStroke.hairline
    var dash: [CGFloat] = []

    func body(content: Content) -> some View {
        content
            .padding(12)
            .background(role.background)
            .cornerRadius(FCRadius.card)
            .overlay(
                RoundedRectangle(cornerRadius: FCRadius.card)
                    .strokeBorder(strokeColor ?? role.stroke, style: StrokeStyle(lineWidth: lineWidth, dash: dash))
            )
    }
}

extension View {
    func fcCardSurface(
        role: FCCardRole = .data,
        strokeColor: Color? = nil,
        lineWidth: CGFloat = FCStroke.hairline,
        dash: [CGFloat] = []
    ) -> some View {
        modifier(FCCardSurface(role: role, strokeColor: strokeColor, lineWidth: lineWidth, dash: dash))
    }
}

struct FCCardHeader: View {
    let title: String
    var trailing: String? = nil
    var role: FCCardRole = .data
    var dot: Color? = nil
    var icon: String? = nil
    var accent: Color? = nil
    var showsDivider: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let dot {
                    Circle().fill(dot).frame(width: 8, height: 8)
                }
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(accent ?? FilmCanTheme.textTertiary)
                }
                Text(title)
                    .font(FCType.itemTitle)
                    .foregroundColor(role == .data ? FilmCanTheme.textPrimary : FilmCanTheme.textSecondary)
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(FCType.metaStrong)
                        .foregroundColor(FilmCanTheme.textSecondary)
                }
            }
            if showsDivider {
                Rectangle()
                    .fill(accent ?? role.stroke)
                    .frame(height: accent == nil ? FCStroke.hairline : 2)
            }
        }
    }
}

struct FCCard<Content: View>: View {
    let title: String
    var trailing: String? = nil
    var role: FCCardRole = .data
    var dot: Color? = nil
    var icon: String? = nil
    var accent: Color? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FCCardHeader(title: title, trailing: trailing, role: role, dot: dot, icon: icon, accent: accent)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fcCardSurface(role: role)
    }
}
