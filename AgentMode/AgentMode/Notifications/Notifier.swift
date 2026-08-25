import Foundation
import UserNotifications

/// Local notifications for the events in section 12 of the brief.
final class Notifier {
    static let shared = Notifier()

    private init() {}

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    enum Event {
        case agentFinished(name: String, runtime: String)
        case batteryThreshold(percent: Int)
        case agentModeStopped
        case sleepRestored
        case sleepingNow
        case lidModeRecovered

        var title: String {
            switch self {
            case .agentFinished:    return "Agent finished"
            case .batteryThreshold: return "Battery threshold reached"
            case .agentModeStopped: return "Agent Mode stopped"
            case .sleepRestored:    return "Normal sleep restored"
            case .sleepingNow:      return "Putting Mac to sleep"
            case .lidModeRecovered: return "Sleep settings recovered"
            }
        }

        var body: String {
            switch self {
            case .agentFinished(let name, let runtime):
                return "\(name) completed after \(runtime)."
            case .batteryThreshold(let percent):
                return "Battery is at \(percent)%. Agent Mode released its keep-awake to protect the battery."
            case .agentModeStopped:
                return "No monitored agents remain. Your Mac will sleep normally."
            case .sleepRestored:
                return "Your previous sleep settings are back in effect."
            case .sleepingNow:
                return "All agents finished and you're on battery — sleeping to save power."
            case .lidModeRecovered:
                return "A previous session ended without restoring sleep settings. They have been restored now."
            }
        }
    }

    func post(_ event: Event) {
        guard AppSettings.shared.notificationsEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = event.title
        content.body = event.body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
