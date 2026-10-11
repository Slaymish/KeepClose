import SwiftUI
@preconcurrency import UserNotifications

@MainActor @Observable final class BirthdayReminders {
    var enabled: Bool
    var hour: Int
    var minute: Int
    var busy = false
    var message = ""
    private let defaults: UserDefaults
    private let center = UNUserNotificationCenter.current()
    private var queuedRefresh: (people: [Person], names: Bool, requestPermission: Bool)?
    private var lastNotices: [BirthdayNotice]?
    private var lastNames = false
    private var lastPolicy: ReminderPreviewPolicy = .unknown
    init() {
        #if DEBUG
        defaults = CommandLine.arguments.contains("--demo") ? UserDefaults(suiteName: "KeepCloseBirthdayDemo")! : .standard
        #else
        defaults = .standard
        #endif
        enabled = defaults.bool(forKey: "birthday-reminders")
        hour = defaults.object(forKey: "birthday-hour") == nil ? 9 : min(23, max(0, defaults.integer(forKey: "birthday-hour")))
        minute = min(59, max(0, defaults.integer(forKey: "birthday-minute")))
    }
    func setEnabled(_ enabled: Bool, people: [Person], names: Bool) async {
        self.enabled = enabled; defaults.set(enabled, forKey: "birthday-reminders"); lastNotices = nil
        await refresh(people: people, names: names, requestPermission: enabled)
    }
    func setTime(_ date: Date, people: [Person], names: Bool) async {
        hour = Calendar.current.component(.hour, from: date); minute = Calendar.current.component(.minute, from: date)
        defaults.set(hour, forKey: "birthday-hour"); defaults.set(minute, forKey: "birthday-minute"); lastNotices = nil
        await refresh(people: people, names: names)
    }
    func refresh(people: [Person], names: Bool, requestPermission: Bool = false) async {
        #if DEBUG
        if CommandLine.arguments.contains("--demo") { message = "Notifications aren't scheduled in this fictional preview."; return }
        #endif
        guard !busy else {
            queuedRefresh = (people, names, requestPermission || queuedRefresh?.requestPermission == true)
            return
        }
        busy = true
        defer {
            busy = false
            if let queued = queuedRefresh {
                queuedRefresh = nil
                Task { await refresh(people: queued.people, names: queued.names, requestPermission: queued.requestPermission) }
            }
        }
        if requestPermission {
            do { _ = try await center.requestAuthorization(options: [.alert, .sound]) }
            catch { message = "Couldn't request notifications: " + error.localizedDescription }
        }
        let settings = await center.notificationSettings()
        let policy: ReminderPreviewPolicy
        switch settings.showPreviewsSetting {
        case .whenAuthenticated: policy = .whenUnlocked
        case .always: policy = .always
        case .never: policy = .never
        @unknown default: policy = .unknown
        }
        let authorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        let all = enabled && authorized ? BirthdayPlanner.notices(people: people, hour: hour, minute: minute) : []
        // Reserve room for the separate opportunity reminder. The OS queue is finite.
        let notices = Array(all.prefix(60))
        guard lastNotices != notices || lastNames != names || lastPolicy != policy else { return }
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.identifier.hasPrefix("birthday-") }.map(\.identifier))
        let delivered = await center.deliveredNotifications()
        center.removeDeliveredNotifications(withIdentifiers: delivered.filter { $0.request.identifier.hasPrefix("birthday-") }.map { $0.request.identifier })
        guard enabled && authorized else {
            message = enabled ? "Birthday reminders are requested. Allow notifications in system settings to schedule them." : "Birthday reminders are off on this device."
            lastNotices = notices; lastNames = names; lastPolicy = policy; return
        }
        do {
            for notice in notices {
                let content = UNMutableNotificationContent()
                content.title = BirthdayReminderText.title
                content.body = BirthdayReminderText.body(for: notice, includeNames: names, policy: policy)
                content.categoryIdentifier = "birthday-occasion"; content.sound = .default
                var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .current
                var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: notice.date)
                parts.calendar = calendar; parts.timeZone = calendar.timeZone
                try await center.add(UNNotificationRequest(identifier: notice.id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
            }
            let retained = await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix("birthday-") }.count
            guard retained == notices.count else { message = "The system retained fewer reminders than requested. Open Keep Close again to refresh them."; lastNotices = nil; return }
            lastNotices = notices; lastNames = names; lastPolicy = policy
            message = notices.isEmpty ? "No birthday reminders to schedule yet." : "Scheduled " + String(notices.count) + " upcoming birthday and gift reminders. They can arrive while the app is closed."
            if all.count > 60 { message += " The nearest 60 are queued; open Keep Close to refresh later dates." }
        } catch { lastNotices = nil; message = "Couldn't schedule birthday reminders: " + error.localizedDescription }
    }
}
