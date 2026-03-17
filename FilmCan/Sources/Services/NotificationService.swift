import Foundation
import UserNotifications
import AppKit

class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()
    
    private var isAuthorized = false
    private var presentationOptions: UNNotificationPresentationOptions = [.banner, .list, .sound, .badge]
    
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
                self.isAuthorized = true
                self.updatePresentationOptions(settings)
            case .denied:
                self.isAuthorized = false
            case .ephemeral:
                self.isAuthorized = false
            @unknown default:
                self.isAuthorized = false
            }
        }
    }
    
    private func requestAuthorization() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                self.isAuthorized = granted
            }
        }
    }
    
    func notify(title: String, body: String, identifier: String = UUID().uuidString) {
        let center = UNUserNotificationCenter.current()
        
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || 
                  settings.authorizationStatus == .provisional else {
                return
            }

            self.updatePresentationOptions(settings)
            
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            if #available(macOS 12.0, *) {
                content.interruptionLevel = .active
            }

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: trigger
            )

            center.add(request, withCompletionHandler: nil)
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
                self.requestAuthorization()
                completion()
            } else if settings.authorizationStatus == .denied {
                completion()
            } else {
                self.isAuthorized = true
                completion()
            }
        }
    }

    // CRITICAL: Show notifications even when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler(presentationOptions)
    }
    
    // Handle notification tap
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
        }
        
        completionHandler()
    }

    private func updatePresentationOptions(_ settings: UNNotificationSettings) {
        if #available(macOS 10.14, *) {
            switch settings.alertStyle {
            case .banner:
                presentationOptions = [.banner, .list, .sound, .badge]
            case .alert:
                presentationOptions = [.banner, .list, .sound, .badge]
            case .none:
                presentationOptions = [.list, .sound, .badge]
            @unknown default:
                presentationOptions = [.banner, .list, .sound, .badge]
            }
        } else {
            presentationOptions = [.banner, .list, .sound, .badge]
        }
    }
}
