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
                .scaleEffect(isActive ? 1.04 : 1, anchor: .bottom)
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

    private var drawerAnimation: Animation { .spring(response: 0.38, dampingFraction: 0.85) }
    private let stripHeight: CGFloat = 56

    var body: some View {
        // The tab strip lives on the main dark background. The gray body is a
        // separate layer BEHIND the strip that slides up from below the window
        // frame. Only the selected tab is lifted up to ride on the body's top edge —
        // the others stay low, in front of the rising gray. Like pulling one folder
        // out of a drawer.
        let bodyH = SettingsDrawerLayout.openCap(windowHeight: windowHeight, isWide: isWide)
        ZStack(alignment: .bottom) {
            contentPanel(height: bodyH)
                .offset(y: isCollapsed ? bodyH : 0)
            tabStrip(lift: isCollapsed ? 0 : bodyH - stripHeight)
        }
        .frame(maxWidth: .infinity)
        .frame(height: isCollapsed ? stripHeight : bodyH, alignment: .bottom)
        .background(FilmCanTheme.background.ignoresSafeArea(edges: .bottom))
        .clipped()
    }

    /// Switch tabs. If already open, fully close the current card (slide down) before
    /// pulling the new one up — so the two motions read as distinct, not a swap.
    private func handleTap(_ tab: Tab) {
        if tab == selection {
            withAnimation(drawerAnimation) { isCollapsed.toggle() }
        } else if isCollapsed {
            selection = tab
            withAnimation(drawerAnimation) { isCollapsed = false }
        } else {
            withAnimation(drawerAnimation) { isCollapsed = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
                selection = tab
                withAnimation(drawerAnimation) { isCollapsed = false }
            }
        }
    }

    private func contentPanel(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Spacer(minLength: 12)
                presetSelector()
            }
            ScrollView { content().frame(maxWidth: .infinity, alignment: .leading) }
        }
        .padding(.horizontal, 16)
        // Top inset clears the lifted active tab; bottom inset clears the front strip.
        .padding(.top, 46)
        .padding(.bottom, stripHeight + 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: height, alignment: .top)
        .background(FilmCanTheme.drawerSurface)
    }

    private func tabStrip(lift: CGFloat) -> some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(tabs, id: \.self) { tab in
                let active = tab == selection && !isCollapsed
                SettingsFolderTab(title: title(tab), isActive: active) {
                    handleTap(tab)
                }
                .offset(y: active ? -lift : 0)
            }
            Spacer(minLength: 8)
            if isCollapsed { presetSelector() }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: stripHeight, alignment: .bottom)
    }
}
