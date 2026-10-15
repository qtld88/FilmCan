import AppKit
import SwiftUI

/// Owns the Quick Copy windows. One window per request; each has its own
/// `QuickCopySession` (and so its own background `TransferViewModel`).
@MainActor
final class QuickCopyCoordinator: NSObject, NSWindowDelegate {
    static let shared = QuickCopyCoordinator()

    /// A request arriving this soon after process start means FilmCan was
    /// launched BY the quick copy (Services/Dock), not opened by the user.
    private static let launchWindow: TimeInterval = 10

    private let processStart = Date()
    private var sessions: [UUID: QuickCopySession] = [:]

    /// True when FilmCan was started for a quick copy → auto-quit at the end.
    private(set) var launchedForQuickCopy = false

    var hasRunningQuickCopy: Bool { sessions.values.contains { $0.isRunning } }

    func cancelAllRunning() {
        sessions.values.forEach { $0.stop() }
    }

    // MARK: Requests

    /// Entry point for both the Services menu and Dock drops.
    func open(paths: [String]) {
        let existing = paths.filter { FileManager.default.fileExists(atPath: $0) }
        guard !existing.isEmpty else { return }

        if sessions.isEmpty, !launchedForQuickCopy,
           Date().timeIntervalSince(processStart) < Self.launchWindow {
            launchedForQuickCopy = true
        }
        if launchedForQuickCopy { scheduleMainWindowHiding() }

        let session = QuickCopySession(paths: existing)
        session.onFinished = { [weak self] in self?.reap() }
        sessions[session.id] = session
        present(session)
    }

    // MARK: Windows

    private func present(_ session: QuickCopySession) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "FilmCan Copy"
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.minSize = NSSize(width: 520, height: 480)
        window.delegate = self
        window.contentView = NSHostingView(rootView: QuickCopyWindowView(session: session))
        window.center()
        session.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func session(for window: NSWindow) -> QuickCopySession? {
        sessions.values.first { $0.window === window }
    }

    private func isQuickCopyWindow(_ window: NSWindow) -> Bool {
        sessions.values.contains { $0.window === window }
    }

    // MARK: NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let session = session(for: sender), session.isRunning else { return true }
        let alert = NSAlert()
        alert.messageText = "Stop the copy?"
        alert.informativeText = "Closing this window stops the copy. Run Quick Copy again to resume — only what is missing is copied."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Stop")
        if alert.runModal() == .alertSecondButtonReturn {
            session.stop()
            return true
        }
        return false
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let session = session(for: window) else { return }
        session.windowClosed = true
        reap()
    }

    // MARK: Lifecycle

    /// Forget sessions whose window is gone AND whose run has ended, then quit if
    /// FilmCan only exists for the quick copy and nothing else runs.
    private func reap() {
        for (id, session) in sessions where session.windowClosed && !session.isRunning {
            sessions.removeValue(forKey: id)
        }
        quitIfIdle()
    }

    private func quitIfIdle() {
        guard launchedForQuickCopy, sessions.isEmpty else { return }
        guard !TransferViewModel.shared.hasActiveTransfers() else { return }
        NSApp.terminate(nil)
    }

    // MARK: Main window

    /// SwiftUI's `WindowGroup` opens the main window at launch; hide it when the
    /// launch was for a quick copy. The window can be created slightly after the
    /// request, so retry a few times (fallback agreed in the spec: brief flash).
    private func scheduleMainWindowHiding() {
        for delay in [0.0, 0.25, 0.75, 1.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.hideMainWindows()
            }
        }
    }

    private func hideMainWindows() {
        guard launchedForQuickCopy else { return }
        for window in NSApp.windows
        where window.isVisible && window.styleMask.contains(.titled)
            && !(window is NSPanel) && !isQuickCopyWindow(window) {
            window.orderOut(nil)
        }
    }

    /// The user wants the real app (Dock click with no window, "Edit in FilmCan…"):
    /// stop auto-quitting and bring the main window back.
    func showMainWindow() {
        launchedForQuickCopy = false
        NSApp.activate(ignoringOtherApps: true)
        if let hidden = NSApp.windows.first(where: { !isQuickCopyWindow($0) && $0.styleMask.contains(.titled)
                                                      && !($0 is NSPanel) }) {
            hidden.makeKeyAndOrderFront(nil)
        } else {
            NSApp.sendAction(#selector(NSResponder.newWindowForTab(_:)), to: nil, from: nil)
        }
    }
}
