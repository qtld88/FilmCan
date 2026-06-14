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

/// Browser-style tab pill: rounded top, near-flat bottom so it reads as a folder
/// handle. When active it rises and scales slightly — as if the folder is being
/// pulled up out of the drawer.
struct SettingsFolderTab: View {
    let title: String
    let isActive: Bool
    let action: () -> Void

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 14, bottomLeadingRadius: 3,
                               bottomTrailingRadius: 3, topTrailingRadius: 14)
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: isActive ? .semibold : .medium))
                .foregroundColor(isActive ? FilmCanTheme.textPrimary : FilmCanTheme.textSecondary)
                .lineLimit(1)
                .padding(.vertical, 10)
                .padding(.horizontal, 18)
                .background(shape.fill(isActive ? FilmCanTheme.drawerSurface : FilmCanTheme.panel))
                .overlay(
                    shape.stroke(isActive ? FilmCanTheme.cardStrokeStrong : FilmCanTheme.cardStroke,
                                 lineWidth: 1)
                )
                .scaleEffect(isActive ? 1.05 : 1, anchor: .bottom)
                .offset(y: isActive ? -5 : 0)
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

    private var drawerAnimation: Animation { .spring(response: 0.38, dampingFraction: 0.82) }

    var body: some View {
        // Tab strip sits ON TOP of the gray body. Opening grows the drawer upward:
        // the strip rides up on the gray while the body is pulled up from below the
        // window frame — like physically pulling a hidden card out of the drawer.
        VStack(spacing: 0) {
            tabStrip
            if !isCollapsed {
                contentPanel
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: SettingsDrawerLayout.openCap(windowHeight: windowHeight, isWide: isWide))
                    .transition(.move(edge: .bottom))
            }
        }
        // Drawer base grey runs the full height — including down behind the closed
        // tab strip to the window's bottom edge.
        .background(FilmCanTheme.drawerSurface.ignoresSafeArea(edges: .bottom))
        // Clip so the body is hidden below the frame until pulled up.
        .clipped()
    }

    /// Switch tabs. If already open, close the current card first, then pull the new
    /// one up — so the user sees the old slide down and the new slide up.
    private func handleTap(_ tab: Tab) {
        if tab == selection {
            withAnimation(drawerAnimation) { isCollapsed.toggle() }
        } else if isCollapsed {
            selection = tab
            withAnimation(drawerAnimation) { isCollapsed = false }
        } else {
            withAnimation(drawerAnimation) { isCollapsed = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                selection = tab
                withAnimation(drawerAnimation) { isCollapsed = false }
            }
        }
    }

    private var contentPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title(selection))
                    .font(.title3.weight(.semibold))
                    .foregroundColor(FilmCanTheme.textPrimary)
                Spacer(minLength: 12)
                presetSelector()
            }
            Divider().background(FilmCanTheme.cardStroke)
            ScrollView { content().frame(maxWidth: .infinity, alignment: .leading) }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FilmCanTheme.drawerSurface)
    }

    private var tabStrip: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(tabs, id: \.self) { tab in
                SettingsFolderTab(title: title(tab), isActive: tab == selection && !isCollapsed) {
                    handleTap(tab)
                }
            }
            Spacer(minLength: 8)
            if isCollapsed { presetSelector() }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }
}
