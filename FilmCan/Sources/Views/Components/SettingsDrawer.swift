import SwiftUI

enum SettingsDrawerLayout {
    /// Max height of the open content panel. Floors at 160pt so it stays usable on short windows.
    static func openCap(windowHeight: CGFloat, isWide: Bool) -> CGFloat {
        let factor: CGFloat = isWide ? 0.45 : 0.55
        return max(160, windowHeight * factor)
    }
}

/// Rectangle with the two top corners chamfered — a binder/folder-tab silhouette.
struct FolderTabShape: Shape {
    var chamfer: CGFloat = 10

    func path(in rect: CGRect) -> Path {
        let c = min(chamfer, min(rect.width, rect.height) / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + c))
        p.addLine(to: CGPoint(x: rect.minX + c, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - c, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + c))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

struct SettingsFolderTab: View {
    let title: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(isActive ? .semibold : .regular))
                .foregroundColor(isActive ? FilmCanTheme.textPrimary : FilmCanTheme.textSecondary)
                .lineLimit(1)
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
                .background(
                    FolderTabShape(chamfer: 10)
                        .fill(isActive ? FilmCanTheme.panel : FilmCanTheme.card)
                )
                .overlay(
                    FolderTabShape(chamfer: 10)
                        .stroke(isActive ? FilmCanTheme.cardStrokeStrong : FilmCanTheme.cardStroke,
                                lineWidth: 1)
                )
                .offset(y: isActive ? -3 : 0)
        }
        .buttonStyle(.plain)
    }
}
