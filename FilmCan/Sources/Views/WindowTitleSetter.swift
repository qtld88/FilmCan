import SwiftUI
import AppKit

struct WindowTitleSetter: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                window.title = title
                window.titleVisibility = .hidden
                window.titlebarAppearsTransparent = true
                window.styleMask.insert(.fullSizeContentView)
                window.backgroundColor = NSColor(FilmCanTheme.sidebar)
                if window.toolbar != nil {
                    window.toolbar = nil
                }
            }
        }
    }
}
