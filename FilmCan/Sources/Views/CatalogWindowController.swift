import AppKit
import SwiftUI

@MainActor
final class CatalogWindowController {
    static let shared = CatalogWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(
                rootView: CatalogWindowRoot().environmentObject(MediaCatalogStore.shared))
            let w = NSWindow(contentViewController: hosting)
            w.title = "Catalog"
            w.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            w.setContentSize(NSSize(width: 760, height: 560))
            w.isReleasedWhenClosed = false
            w.setFrameAutosaveName("CatalogWindow")
            w.center()
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension CatalogScope {
    /// The selected movie tab, or nil when none is selected.
    @MainActor
    static func selected(in appState: AppState) -> CatalogScope? {
        guard let id = appState.selectedConfigId,
              let config = appState.storage.configurations.first(where: { $0.id == id })
        else { return nil }
        return CatalogScope(configId: id, movieName: config.name)
    }
}

/// The standalone Catalog window follows the selected movie tab too.
private struct CatalogWindowRoot: View {
    @ObservedObject private var appState = AppState.shared

    var body: some View {
        let scope = CatalogScope.selected(in: appState)
        CatalogView(scope: scope)
            .navigationTitle(scope.map { "Catalog — \($0.movieName)" } ?? "Catalog")
    }
}
