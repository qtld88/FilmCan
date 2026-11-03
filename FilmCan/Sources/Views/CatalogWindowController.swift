import AppKit
import SwiftUI

@MainActor
final class CatalogWindowController {
    static let shared = CatalogWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(
                rootView: CatalogView().environmentObject(MediaCatalogStore.shared))
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
