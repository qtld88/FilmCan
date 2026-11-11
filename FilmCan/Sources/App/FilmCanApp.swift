import SwiftUI
import AppKit

@main
struct FilmCanApp: App {
    @StateObject private var appState = AppState.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    
    var body: some Scene {
        WindowGroup(id: MainWindowTarget.sceneId) {
            MainView()
                .frame(minWidth: 500, minHeight: 500)
                .modifier(InitialWindowSizer())
                .environmentObject(appState)
                .environmentObject(appState.storage)
        }
        .handlesExternalEvents(matching: [])
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

                Menu("New Movie Like") {
                    NewMovieMenuItems(appState: appState, storage: appState.storage)
                }

                NewWindowMenuItems()
            }
            
            CommandGroup(after: .newItem) {
                Button("Start Backup (Run Now)") {
                    NotificationCenter.default.post(name: .filmCanHotkeyRunNow, object: nil)
                }
                .keyboardShortcut("b", modifiers: .command)
                
                Button("Add Source…") {
                    NotificationCenter.default.post(name: .filmCanHotkeyAddSource, object: nil)
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                
                Button("Add Destination…") {
                    NotificationCenter.default.post(name: .filmCanHotkeyAddDestination, object: nil)
                }
                .keyboardShortcut("o", modifiers: [.command, .option])
                
                Button("Refresh Drives") {
                    NotificationCenter.default.post(name: .filmCanHotkeyRefreshDrives, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
            }

            CommandGroup(after: .windowArrangement) {
                Button("Catalog") {
                    NotificationCenter.default.post(name: .filmCanShowCatalogPane, object: nil)
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])

                Button("Open Catalog in Window") {
                    CatalogWindowController.shared.show()
                }
            }

            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    UpdaterService.shared.checkForUpdates()
                }
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

/// File › New Window / New Quick Copy Window.
private struct NewWindowMenuItems: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Divider()
        Button("New Window") {
            QuickCopyCoordinator.shared.userOpenedMainWindow()
            openWindow(id: MainWindowTarget.sceneId)
        }
        .keyboardShortcut("n", modifiers: [.command, .option])

        Button("New Quick Copy Window") {
            QuickCopyCoordinator.shared.openEmpty()
        }
        .keyboardShortcut("n", modifiers: [.command, .shift])
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Finder → Services → FilmCan Copy. Refresh the registry at every launch so
        // the entry appears without a logout.
        NSApp.servicesProvider = QuickCopyServiceProvider.shared
        NSUpdateDynamicServices()
        _ = QuickCopyCoordinator.shared   // instantiate early so its window-key observer is registered
    }

    /// Dock-icon drop of files/folders.
    func application(_ application: NSApplication, open urls: [URL]) {
        QuickCopyCoordinator.shared.open(paths: urls.filter(\.isFileURL).map(\.path))
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag, QuickCopyCoordinator.shared.revealHiddenMainWindowIfNeeded() { return false }
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = QuickCopyServiceProvider.shared
        FinderEjectGuard.start()
        #if DEBUG
        DemoMode.launch()
        #endif
        // Ensure app is properly registered as a regular app (in dock)
        NSApp.setActivationPolicy(.regular)
        
        // Disable window tabbing menu items (not used in FilmCan)
        NSWindow.allowsAutomaticWindowTabbing = false
        
        // Activate the app (bring to front)
        NSApp.activate(ignoringOtherApps: true)
        
        // Before anything reads a secret: rescue any left in UserDefaults by a build
        // older than the Keychain switch, and erase the plaintext copy.
        SecretsMigration.run()

        // Initialize notification service
        let notificationService = NotificationService.shared

        // Request authorization
        notificationService.ensureAuthorized()

        // Starts Sparkle's background update scheduler (skipped under XCTest —
        // the test host launches the real app, and tests shouldn't depend on
        // network reachability to the production update feed)
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            _ = UpdaterService.shared
        }

        #if DEBUG
        // Skip under XCTest — the background timer firing into the test host's
        // launch/teardown intermittently crashed the runner at bootstrap.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            MainThreadWatchdog.shared.start()
        }
        #endif
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        NotificationService.shared.clearBadge()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false  // Keep app running in background
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        #if DEBUG
        if DemoSettings.isActive { return .terminateNow }
        #endif
        let transferViewModel = TransferViewModel.shared
        let quickCopy = QuickCopyCoordinator.shared
        let progress = transferViewModel.progress
        let isBusy = transferViewModel.hasActiveTransfers()
            || quickCopy.hasRunningQuickCopy
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
            quickCopy.cancelAllRunning()
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

    /// Quick Copy windows can be key on a service launch; never size or track them.
    private static func mainWindow() -> NSWindow? {
        func isQuickCopy(_ w: NSWindow) -> Bool { w.delegate is QuickCopyCoordinator }
        if let key = NSApp.keyWindow, !isQuickCopy(key) { return key }
        return NSApp.windows.first { $0.isVisible && !isQuickCopy($0) }
    }

    private func applyInitialSize() {
        guard !didApply else { return }
        guard let window = Self.mainWindow() else { return }
        window.tabbingMode = .disallowed
        // File › New Window: offset from the existing window instead of covering it.
        if let other = MainWindowTarget.otherVisibleWindow(than: window) {
            window.setFrame(other.frame, display: false)
            window.setFrameTopLeftPoint(NSPoint(x: other.frame.minX + 28, y: other.frame.maxY - 28))
            didApply = true
            return
        }
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
        guard let window = Self.mainWindow() else { return }
        let center = NotificationCenter.default
        let save: (Notification) -> Void = { _ in
            savedFrame = NSStringFromRect(window.frame)
        }
        observers.append(center.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main, using: save))
        observers.append(center.addObserver(forName: NSWindow.didEndLiveResizeNotification, object: window, queue: .main, using: save))
        observers.append(center.addObserver(forName: NSWindow.didMoveNotification, object: window, queue: .main, using: save))
    }
}
