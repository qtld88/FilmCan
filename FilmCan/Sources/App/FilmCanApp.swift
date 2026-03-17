import SwiftUI
import AppKit

@main
struct FilmCanApp: App {
    @StateObject private var appState = AppState.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    
    var body: some Scene {
        WindowGroup {
            MainView()
                .frame(minWidth: 500, minHeight: 500)
                .modifier(InitialWindowSizer())
                .environmentObject(appState)
                .environmentObject(appState.storage)
                .environmentObject(appState.rsyncService)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("Quit FilmCan") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }

            CommandGroup(replacing: .newItem) {
                Button("New Backup") {
                    _ = appState.createNewConfig()
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            
            CommandGroup(after: .newItem) {
                Button("Start Backup (Run Now)") {
                    NotificationCenter.default.post(name: .filmCanHotkeyRunNow, object: nil)
                }
                .keyboardShortcut("b", modifiers: .command)
                
                Button("Add Source") {
                    NotificationCenter.default.post(name: .filmCanHotkeyAddSource, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)
                
                Button("Add Destination") {
                    NotificationCenter.default.post(name: .filmCanHotkeyAddDestination, object: nil)
                }
                .keyboardShortcut("d", modifiers: .command)
                
                Button("Refresh Drives") {
                    NotificationCenter.default.post(name: .filmCanHotkeyRefreshDrives, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
            }
            
            CommandGroup(replacing: .help) {
                Button("FilmCan Help") {
                    if let url = URL(string: "https://www.filmcan.eu/docs") {
                        NSWorkspace.shared.open(url)
                    }
                }
                
                Button("Guided Tour") {
                    NotificationCenter.default.post(name: .filmCanRestartTour, object: nil)
                }
            }
        }
        
        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure app is properly registered as a regular app (in dock)
        NSApp.setActivationPolicy(.regular)
        
        // Disable window tabbing menu items (not used in FilmCan)
        NSWindow.allowsAutomaticWindowTabbing = false
        
        // Activate the app (bring to front)
        NSApp.activate(ignoringOtherApps: true)
        
        // Initialize notification service
        let notificationService = NotificationService.shared
        
        // Request authorization
        notificationService.ensureAuthorized()
        
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false  // Keep app running in background
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let transferViewModel = TransferViewModel.shared
        let progress = transferViewModel.progress
        let isBusy = transferViewModel.isTransferring
            || progress.isRunning
            || progress.verificationPhase == .verifying
            || progress.verificationPhase == .generatingHashList
            || progress.sourceHashingActive

        guard isBusy else { return .terminateNow }

        let alert = NSAlert()
        alert.messageText = "Quit FilmCan?"
        alert.informativeText = "A transfer or verification is in progress. Quitting now will cancel it."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Quit and Cancel")

        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            transferViewModel.cancelAll()
            return .terminateNow
        }
        return .terminateCancel
    }
    
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
}

private struct InitialWindowSizer: ViewModifier {
    @AppStorage("mainWindowFrame") private var savedFrame: String = ""
    @State private var didApply = false
    @State private var observers: [NSObjectProtocol] = []

    func body(content: Content) -> some View {
        content
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    applyInitialSize()
                    registerWindowObservers()
                }
            }
    }

    private func applyInitialSize() {
        guard !didApply else { return }
        guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }) else { return }
        window.tabbingMode = .disallowed
        if !savedFrame.isEmpty {
            let restored = NSRectFromString(savedFrame).standardized
            if restored.width > 100, restored.height > 100 {
                window.setFrame(restored, display: true)
                didApply = true
                return
            }
        }
        let screen = window.screen ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }
        let width = visibleFrame.width * 0.92
        let height = visibleFrame.height * 0.92
        let origin = NSPoint(
            x: visibleFrame.midX - width / 2,
            y: visibleFrame.midY - height / 2
        )
        let targetFrame = NSRect(origin: origin, size: NSSize(width: width, height: height))
        window.setFrame(targetFrame, display: true)
        didApply = true
    }

    private func registerWindowObservers() {
        guard observers.isEmpty else { return }
        guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }) else { return }
        let center = NotificationCenter.default
        let save: (Notification) -> Void = { _ in
            savedFrame = NSStringFromRect(window.frame)
        }
        observers.append(center.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main, using: save))
        observers.append(center.addObserver(forName: NSWindow.didEndLiveResizeNotification, object: window, queue: .main, using: save))
        observers.append(center.addObserver(forName: NSWindow.didMoveNotification, object: window, queue: .main, using: save))
    }
}
