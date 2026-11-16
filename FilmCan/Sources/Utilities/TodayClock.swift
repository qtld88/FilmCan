import AppKit
import Combine
import Foundation

/// Publishes the current date again whenever the calendar day changes, so folder
/// previews follow the `{date}` token the engine resolves at run time instead of
/// keeping the date the window was opened on.
@MainActor
final class TodayClock: ObservableObject {
    static let shared = TodayClock()

    @Published private(set) var today = Date()

    private var observers: [NSObjectProtocol] = []

    init() {
        // A Mac asleep over midnight may only learn the new day on wake.
        let triggers: [(NotificationCenter, Notification.Name)] = [
            (.default, .NSCalendarDayChanged),
            (.default, .NSSystemClockDidChange),
            (NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification),
        ]
        observers = triggers.map { center, name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
        }
    }

    func refresh(now: Date = Date()) {
        guard !Calendar.current.isDate(now, inSameDayAs: today) else { return }
        today = now
    }
}
