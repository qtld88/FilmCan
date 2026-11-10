import AppKit
import SwiftUI

/// Several main windows can be open (File › New Window). Menu hotkeys are broadcast
/// through NotificationCenter, so every window hears them: only the frontmost main
/// window may act, or ⌘B would start the same backup once per window.
@MainActor
enum MainWindowTarget {
    nonisolated static let sceneId = "main"
    private static let windows = NSHashTable<NSWindow>.weakObjects()

    static func register(_ window: NSWindow) { windows.add(window) }

    static var frontmost: NSWindow? {
        NSApp.orderedWindows.first { windows.contains($0) && $0.isVisible }
            ?? NSApp.orderedWindows.first { windows.contains($0) }
    }

    /// True when `window` should handle a broadcast hotkey. An unknown window
    /// (not yet attached) acts only when no main window is registered.
    static func shouldHandle(in window: NSWindow?) -> Bool {
        guard let window else { return frontmost == nil }
        return frontmost === window
    }
}

/// Reports the hosting `NSWindow` once the view is attached, and registers it as a main window.
struct MainWindowReader: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = ReaderView()
        view.onWindow = { found in
            MainWindowTarget.register(found)
            if window !== found { window = found }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ReaderView: NSView {
        var onWindow: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            DispatchQueue.main.async { [weak self] in self?.onWindow?(window) }
        }
    }
}
