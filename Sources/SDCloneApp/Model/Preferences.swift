import Foundation
import AppKit
import UserNotifications

/// Preferenze lette fuori dalle viste (le viste usano `@AppStorage` con le stesse chiavi).
enum Preferences {
    static let notifyKey = "notifyWhenDone"
    static let soundKey = "playSound"
    static let badgeKey = "dockProgress"

    static var notifyWhenDone: Bool { UserDefaults.standard.object(forKey: notifyKey) as? Bool ?? true }
    static var playSound: Bool { UserDefaults.standard.object(forKey: soundKey) as? Bool ?? true }
    static var dockProgress: Bool { UserDefaults.standard.object(forKey: badgeKey) as? Bool ?? true }
}

/// Notifica di fine lavoro quando l'app non e' in primo piano.
@MainActor
enum Notifier {
    /// Solo dentro un pacchetto .app: senza bundle identifier il centro notifiche non e' disponibile.
    private static var available: Bool { Bundle.main.bundleIdentifier != nil && !Snapshot.isActive }

    static func requestPermission() {
        guard available else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(run: JobRun, outcome: JobRun.Outcome) {
        guard available else { return }
        let content = UNMutableNotificationContent()
        content.title = run.title
        switch outcome {
        case .success:
            content.body = run.kind == .restore ? "La scheda è verificata ed espulsa." : "«\(run.file.lastPathComponent)» è pronto."
        case .failed(let message):
            content.body = String(message.prefix(180))
        case .cancelled:
            content.body = "Hai annullato l'operazione."
        }
        content.sound = nil   // il suono, se attivo, lo suona gia' l'app
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
