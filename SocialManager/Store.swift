import SwiftUI
import UserNotifications
#if os(macOS)
import AppKit
#else
import UIKit
#endif

private final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

@MainActor @Observable final class RelationshipStore {
    var people: [Person] = []
    var error: String?
    var reminderEnabled = false
    var reminderBusy = false
    var reminderHour = 18
    var reminderMinute = 0
    var reminderMessage = ""
    var includeNamesInReminders = true
    var previewPrivacyMessage = "Choose Show Previews → When Unlocked to show names only after unlocking."
    private var previewPolicy: ReminderPreviewPolicy = .unknown
    private var lastPrivacyCheck = Date.distantPast
    private var lastAttemptedNames: [String] = []
    private let repository = RelationshipRepository()
    private var attemptedReminderRevision: UUID?
    private var lastReadError: String?
    private let center = UNUserNotificationCenter.current()
    private let notificationPresenter = NotificationPresenter()

    init() {
        center.delegate = notificationPresenter
        center.setNotificationCategories([UNNotificationCategory(identifier: "relationship-check-in", actions: [], intentIdentifiers: [], hiddenPreviewsBodyPlaceholder: PrivateReminderText.hiddenBody, options: [])])
        #if DEBUG
        if CommandLine.arguments.contains("--demo") { seedDocumentationDemo() }
        #endif
        reload()
    }
    var due: [Person] { people.suggestedPeople() }
    func reload() {
        do { people = try repository.people(); lastReadError = nil }
        catch {
            let message = "Couldn't load relationships: \(error.localizedDescription). The saved file has been left untouched."
            if lastReadError != message { self.error = message; lastReadError = message }
        }
    }
    func watchChanges() async {
        // The CLI and app can be open together. Always read before mutations as well.
        while !Task.isCancelled {
            reload()
            do {
                let preferences = try repository.preferences()
                reminderHour = preferences.hour; reminderMinute = preferences.minute
                includeNamesInReminders = preferences.includeNames
                if Date.now.timeIntervalSince(lastPrivacyCheck) >= 30 { await refreshNotificationPrivacy() }
                if preferences.revision != attemptedReminderRevision || preferences.enabled && lastAttemptedNames != reminderNames(preferences) {
                    await applyReminder(preferences)
                }
            } catch { reminderMessage = "Couldn't read reminder settings: \(error.localizedDescription)" }
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
        }
    }
    @discardableResult func save(_ person: Person, expected: Person? = nil) -> Bool {
        do {
            try repository.modifyPeople { people in
                if let i = people.firstIndex(where: { $0.id == person.id }) {
                    guard let expected, people[i] == expected else { throw RepositoryError.conflict }
                    people[i] = person
                } else {
                    guard expected == nil else { throw RepositoryError.missing }
                    people.append(person)
                }
            }
            reload(); return true
        } catch { self.error = "Couldn't save changes: \(error.localizedDescription)"; return false }
    }
    @discardableResult func update(_ id: UUID, change: (inout Person) -> Void) -> Bool {
        do {
            try repository.modifyPeople { people in
                guard let i = people.firstIndex(where: { $0.id == id }) else { throw RepositoryError.missing }
                change(&people[i])
            }
            reload(); return true
        } catch { self.error = error.localizedDescription; return false }
    }
    @discardableResult func delete(_ person: Person) -> Bool {
        do {
            try repository.modifyPeople { people in
                guard let i = people.firstIndex(where: { $0.id == person.id }) else { throw RepositoryError.missing }
                guard people[i] == person else { throw RepositoryError.conflict }
                people.remove(at: i)
            }
            reload(); return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func hasImported(_ provider: ImportProvider) -> Bool {
        people.contains { $0.importSources.contains(provider.title) } || ((try? repository.agentUpdateContext(provider).hasImported) ?? false)
    }
    func agentPrompt(_ provider: ImportProvider, cliPath: String?) throws -> String {
        AgentImportPrompt.text(provider: provider, cliPath: cliPath, context: try repository.agentUpdateContext(provider))
    }
    func previewImport(_ batch: AgentImportBatch) throws -> (AgentImportPlan, [Person]) {
        let people = try repository.people()
        return (try AgentImportPlan.make(batch: batch, existing: people), people)
    }
    func applyImport(_ batch: AgentImportBatch, expected: [Person]) throws -> AgentImportResult {
        let result = try repository.applyImport(batch, expected: expected)
        reload()
        return result
    }
    func setReminder(_ enabled: Bool) async {
        guard !reminderBusy else { return }
        do {
            let preferences = try repository.setReminder(enabled: enabled, hour: reminderHour, minute: reminderMinute)
            await applyReminder(preferences, requestPermission: enabled)
        } catch { self.error = error.localizedDescription }
    }
    private func applyReminder(_ preferences: ReminderPreferences, requestPermission: Bool = false) async {
        guard !reminderBusy else { return }
        reminderBusy = true
        defer { reminderBusy = false }
        attemptedReminderRevision = preferences.revision
        lastAttemptedNames = reminderNames(preferences)
        if !preferences.enabled {
            center.removePendingNotificationRequests(withIdentifiers: ["daily-check-in"])
            reminderEnabled = false
            report("disabled", "Daily reminder is off.")
            return
        }
        do {
            var settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined || requestPermission && settings.authorizationStatus != .denied {
                guard try await center.requestAuthorization(options: [.alert, .sound]) else {
                    reminderEnabled = false
                    report("denied", "Allow Keep Close notifications in system settings, then enable the reminder again.")
                    return
                }
                settings = await center.notificationSettings()
            }
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                reminderEnabled = false
                report("denied", "Allow Keep Close notifications in system settings, then enable the reminder again.")
                return
            }
            updatePrivacyMessage(settings)
            let names = reminderNames(preferences)
            let text = PrivateReminderText.make(names: names, includeNames: preferences.includeNames, policy: previewPolicy)
            let content = UNMutableNotificationContent()
            content.title = PrivateReminderText.title
            content.body = text.body
            content.categoryIdentifier = "relationship-check-in"
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: preferences.hour, minute: preferences.minute), repeats: true)
            try await center.add(UNNotificationRequest(identifier: "daily-check-in", content: content, trigger: trigger))
            center.removeDeliveredNotifications(withIdentifiers: ["daily-check-in"])
            reminderEnabled = await center.pendingNotificationRequests().contains { $0.identifier == "daily-check-in" }
            report(reminderEnabled ? "scheduled" : "failed", reminderEnabled ? String(format: "Daily reminder scheduled for %02d:%02d local time.", preferences.hour, preferences.minute) : "The system didn't retain the reminder request.")
        } catch {
            reminderEnabled = false
            let nsError = error as NSError
            let message: String
            if nsError.domain == UNErrorDomain && nsError.code == UNError.Code.notificationsNotAllowed.rawValue {
                message = "macOS or iOS refused notification access. Allow Keep Close in Notifications settings. For a Mac development build, use scripts/run-mac.sh to launch the fully signed app."
            } else { message = "Couldn't schedule the reminder: \(error.localizedDescription) (\(nsError.domain) \(nsError.code))." }
            report("failed", message)
            self.error = message
        }
    }
    private func reminderNames(_ preferences: ReminderPreferences) -> [String] {
        let date = Calendar.current.nextDate(after: .now, matching: DateComponents(hour: preferences.hour, minute: preferences.minute), matchingPolicy: .nextTime) ?? .now
        return Array(people.suggestedPeople(at: date).prefix(3)).map(\.name)
    }
    private func updatePrivacyMessage(_ settings: UNNotificationSettings) {
        lastPrivacyCheck = .now
        switch settings.showPreviewsSetting {
        case .whenAuthenticated: previewPolicy = .whenUnlocked
        case .always: previewPolicy = .always
        case .never: previewPolicy = .never
        @unknown default: previewPolicy = .unknown
        }
        if !includeNamesInReminders { previewPrivacyMessage = "All reminders use generic wording, with no names." }
        else if previewPolicy == .whenUnlocked { previewPrivacyMessage = "The OS shows names after device authentication. Locked previews say ‘Someone is ready for a little connection.’" }
        else { previewPrivacyMessage = "Reminders use generic wording with your current preview setting. Choose When Unlocked in system notification settings to show names after unlocking." }
    }
    func refreshNotificationPrivacy() async {
        let previous = previewPolicy
        updatePrivacyMessage(await center.notificationSettings())
        if previous != previewPolicy {
            do {
                let preferences = try repository.preferences()
                if preferences.enabled { await applyReminder(preferences) }
            } catch { self.error = error.localizedDescription }
        }
    }
    func setNotificationNames(_ enabled: Bool) async {
        guard !reminderBusy else { return }
        do {
            let preferences = try repository.preferences()
            let updated = try repository.setReminder(enabled: preferences.enabled, hour: preferences.hour, minute: preferences.minute, includeNames: enabled)
            includeNamesInReminders = enabled
            await applyReminder(updated)
            updatePrivacyMessage(await center.notificationSettings())
        } catch { self.error = error.localizedDescription }
    }
    func openNotificationSettings() {
        #if os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(url) }
        #else
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        #endif
    }
    private func report(_ state: String, _ message: String) {
        reminderMessage = message
        do { try repository.saveStatus(ReminderStatus(state: state, message: message)) }
        catch { self.error = "Couldn't save reminder status: \(error.localizedDescription)" }
    }
}

#if DEBUG
extension RelationshipStore {
    private func seedDocumentationDemo() {
        let daysAgo: (Int) -> Date = { Date.now.addingTimeInterval(Double(-$0) * 86400) }
        var alex = Person(name: "Alex Chen", context: "Met through the climbing club. Ask how the new route went.")
        alex.intention = .grow; alex.contexts = ["Hobby", "Nearby"]
        alex.recordContact(at: daysAgo(20), note: "Coffee after climbing", kind: .conversation, initiator: .mutual)
        var sam = Person(name: "Sam Rivera", context: "An old university friend. We both love films and long walks.")
        sam.contexts = ["Another city"]
        sam.recordContact(at: daysAgo(2), note: "Asked how things are going", kind: .incoming)
        var jordan = Person(name: "Jordan Lee", context: "We worked together on a community project. Ask about the garden.")
        jordan.contexts = ["Online"]
        jordan.recordContact(at: daysAgo(24), note: "Caught up over a call", kind: .conversation, initiator: .them)
        do { try repository.modifyPeople { $0 = [alex, sam, jordan] } }
        catch { self.error = error.localizedDescription }
    }
}
#endif
