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

/// Bottom-docked settings drawer. Folder tabs pinned to the bottom; selecting a tab
/// grows `content` upward (height-capped, internally scrollable). Push layout.
struct SettingsDrawer<Tab: Hashable, Content: View, Preset: View>: View {
    let tabs: [Tab]
    let title: (Tab) -> String
    @Binding var selection: Tab
    @Binding var isCollapsed: Bool
    let isWide: Bool
    let windowHeight: CGFloat
    @ViewBuilder let content: () -> Content
    @ViewBuilder let presetSelector: () -> Preset

    var body: some View {
        VStack(spacing: 0) {
            if !isCollapsed {
                contentPanel
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: SettingsDrawerLayout.openCap(windowHeight: windowHeight, isWide: isWide))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            tabStrip
        }
    }

    private var contentPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title(selection))
                    .font(.headline)
                    .foregroundColor(FilmCanTheme.textPrimary)
                Spacer(minLength: 12)
                presetSelector()
            }
            Divider().background(FilmCanTheme.cardStroke)
            ScrollView { content().frame(maxWidth: .infinity, alignment: .leading) }
        }
        .padding(16)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 0,
                                   bottomTrailingRadius: 0, topTrailingRadius: 10)
                .fill(FilmCanTheme.panel)
        )
        .overlay(
            UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 0,
                                   bottomTrailingRadius: 0, topTrailingRadius: 10)
                .stroke(FilmCanTheme.cardStroke, lineWidth: 1)
        )
    }

    private var tabStrip: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(tabs, id: \.self) { tab in
                SettingsFolderTab(title: title(tab), isActive: tab == selection && !isCollapsed) {
                    if tab == selection {
                        withAnimation(.easeInOut(duration: 0.2)) { isCollapsed.toggle() }
                    } else {
                        selection = tab
                        if isCollapsed {
                            withAnimation(.easeInOut(duration: 0.2)) { isCollapsed = false }
                        }
                    }
                }
            }
            Spacer(minLength: 8)
            if isCollapsed { presetSelector() }
        }
        .padding(.horizontal, 12)
        .padding(.top, isCollapsed ? 8 : 0)
        .background(FilmCanTheme.background)
    }
}
