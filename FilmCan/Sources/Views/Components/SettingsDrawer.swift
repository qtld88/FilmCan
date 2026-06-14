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
    private let sideMargin: CGFloat = 24
    private let cardRadius: CGFloat = 10

    var body: some View {
        // The tab strip lives on the main dark background. Opening pulls up a single
        // glued unit — the active title pill on top of the gray body — as one card
        // (margined, rounded like the data cards). The inactive tabs stay low on the
        // dark background.
        let bodyH = SettingsDrawerLayout.openCap(windowHeight: windowHeight, isWide: isWide)
        ZStack(alignment: .bottom) {
            if !isCollapsed {
                pulledCard(height: bodyH)
                    .transition(.move(edge: .bottom))
            }
            bottomStrip
        }
        .frame(maxWidth: .infinity)
        .frame(height: isCollapsed ? stripHeight : bodyH, alignment: .bottom)
        .background(FilmCanTheme.background.ignoresSafeArea(edges: .bottom))
        .clipped()
    }

    /// Switch tabs. If already open, close the current card (slide down) first, then
    /// pull the new one up — distinct motions, not a swap.
    private func handleTap(_ tab: Tab) {
        if tab == selection {
            withAnimation(drawerAnimation) { isCollapsed.toggle() }
        } else if isCollapsed {
            selection = tab
            withAnimation(drawerAnimation) { isCollapsed = false }
        } else {
            withAnimation(drawerAnimation) { isCollapsed = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
                selection = tab
                withAnimation(drawerAnimation) { isCollapsed = false }
            }
        }
    }

    /// One glued card: active title pill on top + gray body. Slides as a single unit.
    private func pulledCard(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title(selection))
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(FilmCanTheme.textPrimary)
                .lineLimit(1)
                .padding(.vertical, 10)
                .padding(.horizontal, 18)
                .background(
                    UnevenRoundedRectangle(topLeadingRadius: cardRadius, topTrailingRadius: cardRadius)
                        .fill(FilmCanTheme.drawerSurface)
                )
                .padding(.leading, 6)
                // Overlap the body top by 1pt so pill and body read as one piece.
                .padding(.bottom, -1)
                .zIndex(1)

            VStack(alignment: .leading, spacing: 12) {
                HStack { Spacer(minLength: 12); presetSelector() }
                ScrollView { content().frame(maxWidth: .infinity, alignment: .leading) }
            }
            .padding(16)
            .padding(.bottom, stripHeight - 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: cardRadius).fill(FilmCanTheme.drawerSurface))
            .overlay(
                RoundedRectangle(cornerRadius: cardRadius)
                    .stroke(FilmCanTheme.cardStrokeStrong, lineWidth: 1)
            )
        }
        .padding(.horizontal, sideMargin)
        .frame(height: height, alignment: .top)
    }

    private var bottomStrip: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(tabs, id: \.self) { tab in
                SettingsFolderTab(title: title(tab), isActive: false) {
                    handleTap(tab)
                }
                // Hide the active tab while its card is pulled out.
                .opacity(!isCollapsed && tab == selection ? 0 : 1)
            }
            Spacer(minLength: 8)
            if isCollapsed { presetSelector() }
        }
        .padding(.horizontal, sideMargin)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: stripHeight, alignment: .bottom)
    }
}
