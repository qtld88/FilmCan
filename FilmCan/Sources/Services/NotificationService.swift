import Foundation
import UserNotifications
import os
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()
    
    private var isAuthorized = false
    private var presentationOptions: UNNotificationPresentationOptions = [.banner, .sound, .badge]
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "FilmCan", category: "NotificationService")
    private let badgeCountDefaultsKey = "FilmCan.notificationBadgeCount"
    
    private override init() {
        super.init()
        setupNotifications()
    }
    
    private func setupNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.requestAuthorization()
                }
            case .authorized, .provisional:
                DispatchQueue.main.async {
                    self.isAuthorized = true
                }
                self.updatePresentationOptions(settings)
            case .denied:
                DispatchQueue.main.async {
                    self.isAuthorized = false
                }
            case .ephemeral:
                DispatchQueue.main.async {
                    self.isAuthorized = false
                }
            @unknown default:
                DispatchQueue.main.async {
                    self.isAuthorized = false
                }
            }
        }
    }
    
    private func requestAuthorization(completion: @escaping (_ granted: Bool) -> Void = { _ in }) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error {
                self.logger.error("Notification authorization request failed: \(error.localizedDescription, privacy: .public)")
            }
            DispatchQueue.main.async {
                self.isAuthorized = granted
                completion(granted)
            }
        }
    }
    
    func notify(title: String, body: String, identifier: String = UUID().uuidString) {
        let center = UNUserNotificationCenter.current()
        
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                self.updatePresentationOptions(settings)
                self.scheduleNotification(
                    title: title,
                    body: body,
                    identifier: identifier
                )
            case .notDetermined:
                self.requestAuthorization { granted in
                    guard granted else { return }
                    center.getNotificationSettings { postAuthSettings in
                        self.updatePresentationOptions(postAuthSettings)
                        self.scheduleNotification(
                            title: title,
                            body: body,
                            identifier: identifier
                        )
                    }
                }
            case .denied, .ephemeral:
                return
            @unknown default:
                return
            }
        }
    }
    
    func notifyCompletion(result: TransferResult) {
        let summary = TransferResultSummary(
            result: result,
            counts: (transferred: result.filesTransferred, skipped: result.filesSkipped)
        )
        if result.success {
            notify(
                title: "Backup Complete",
                body: "\(result.configurationName): \(summary.filesTransferred) files transferred"
            )
        } else {
            notify(
                title: "Backup Failed",
                body: "\(result.configurationName): \(result.errorMessage ?? "Unknown error")"
            )
        }
    }

    func ensureAuthorized(completion: @escaping () -> Void = {}) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            if settings.authorizationStatus == .notDetermined {
                self.requestAuthorization { _ in
                    completion()
                }
            } else if settings.authorizationStatus == .denied {
                completion()
            } else {
                DispatchQueue.main.async {
                    self.isAuthorized = true
                    completion()
                }
            }
        }
    }

    // CRITICAL: Show notifications even when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        DispatchQueue.main.async {
            completionHandler(self.presentationOptions)
        }
    }
    
    // Handle notification tap
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        DispatchQueue.main.async {
#if canImport(AppKit)
            NSApp.activate(ignoringOtherApps: true)
#endif
            self.clearBadge()
        }
        
        completionHandler()
    }

    private func updatePresentationOptions(_ settings: UNNotificationSettings) {
        #if os(macOS)
        if #available(macOS 10.14, *) {
            switch settings.alertStyle {
            case .banner:
                presentationOptions = [.banner, .sound, .badge]
            case .alert:
                presentationOptions = [.banner, .sound, .badge]
            case .none:
                presentationOptions = [.sound, .badge]
            @unknown default:
                presentationOptions = [.banner, .sound, .badge]
            }
        } else {
            presentationOptions = [.banner, .sound, .badge]
        }
        #else
        presentationOptions = [.banner, .sound, .badge]
        #endif
    }

    private func scheduleNotification(title: String, body: String, identifier: String) {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let shouldShowBadge = !isAppActive()
        let badgeCount = shouldShowBadge ? bumpBadgeCount() : 0

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if shouldShowBadge {
            content.badge = NSNumber(value: badgeCount)
        }
        if #available(iOS 15.0, macOS 12.0, *) {
            content.interruptionLevel = .active
        }

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )

        DispatchQueue.main.async {
            center.add(request) { error in
                if let error {
                    self.logger.error("Failed to schedule notification: \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        DispatchQueue.main.async {
            if shouldShowBadge {
                self.applyBadge(count: badgeCount)
            } else {
                self.clearBadge()
            }
        }
    }

    private func bumpBadgeCount() -> Int {
        let defaults = UserDefaults.standard
        let next = defaults.integer(forKey: badgeCountDefaultsKey) + 1
        defaults.set(next, forKey: badgeCountDefaultsKey)
        return next
    }

    func clearBadge() {
        let defaults = UserDefaults.standard
        defaults.set(0, forKey: badgeCountDefaultsKey)
        applyBadge(count: 0)
    }

    private func applyBadge(count: Int) {
        #if canImport(AppKit)
        NSApp.dockTile.badgeLabel = count > 0 ? String(count) : nil
        #endif
        if #available(iOS 16.0, macOS 13.0, *) {
            UNUserNotificationCenter.current().setBadgeCount(count, withCompletionHandler: nil)
        }
    }

    private func isAppActive() -> Bool {
        #if canImport(AppKit)
        return NSApp.isActive
        #elseif canImport(UIKit)
        return UIApplication.shared.applicationState == .active
        #else
        return false
        #endif
    }
}
