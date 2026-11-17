import AppKit

/// One app-wide source of `.filmCanDriveListChanged`: a periodic tick plus volume
/// mount / unmount / rename. Each main window attaches on appear and detaches on
/// disappear; the timer and the workspace observers exist once, however many
/// windows are open (they used to be one set per window, each posting the same
/// global notification to every window).
@MainActor
final class DriveListTicker {
    static let shared = DriveListTicker()

    private let interval: TimeInterval
    private let center: NotificationCenter
    private var timer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []
    private(set) var attachedCount = 0

    init(interval: TimeInterval = 6, center: NotificationCenter = .default) {
        self.interval = interval
        self.center = center
    }

    var isRunning: Bool { timer != nil }
    var workspaceObserverCount: Int { workspaceObservers.count }

    func attach() {
        attachedCount += 1
        guard attachedCount == 1 else { return }
        let center = self.center
        let post: @Sendable () -> Void = {
            center.post(name: .filmCanDriveListChanged, object: nil)
        }
        let t = Timer(timeInterval: interval, repeats: true) { _ in post() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification,
                     NSWorkspace.didRenameVolumeNotification] {
            workspaceObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { _ in post() })
        }
    }

    func detach() {
        guard attachedCount > 0 else { return }
        attachedCount -= 1
        guard attachedCount == 0 else { return }
        timer?.invalidate()
        timer = nil
        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach { workspace.removeObserver($0) }
        workspaceObservers.removeAll()
    }
}
