import SwiftUI
@preconcurrency import Contacts
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor @Observable final class ContactsController {
    var contacts: [SystemContactSnapshot] = []
    var busy = false
    var message: String?
    var loaded = false
    var limited = false
    let deviceID: String
    private let repository = RelationshipRepository()
    static let changedNotification = Notification.Name.CNContactStoreDidChange
    init() {
        #if DEBUG
        if CommandLine.arguments.contains("--demo") { deviceID = "demo-device"; return }
        #endif
        if let existing = UserDefaults.standard.string(forKey: "contacts-device-id") { deviceID = existing }
        else { let id = UUID().uuidString; deviceID = id; UserDefaults.standard.set(id, forKey: "contacts-device-id") }
    }
    func load(requestPermission: Bool) async {
        guard !busy else { return }
        busy = true; message = nil; loaded = false; contacts = []; defer { busy = false }
        #if DEBUG
        if CommandLine.arguments.contains("--demo") {
            contacts = [SystemContactSnapshot(id: "demo-noah", name: "Noah Bennett", emails: ["noah@example.invalid"], birthday: try? Birthday(month: 10, day: 25)),
                        SystemContactSnapshot(id: "demo-mum", name: "Mum", phones: ["000001"], birthday: try? Birthday(month: 12, day: 8)),
                        SystemContactSnapshot(id: "demo-mum-2", name: "Mum", phones: ["000002"])]
            loaded = true; return
        }
        #endif
        do {
            let state = CNContactStore.authorizationStatus(for: .contacts)
            if state == .notDetermined && requestPermission {
                guard try await CNContactStore().requestAccess(for: .contacts) else { message = "Contacts access wasn't granted. You can still add people yourself."; return }
            }
            let current = CNContactStore.authorizationStatus(for: .contacts)
            var permitted = current == .authorized
            #if os(iOS)
            if #available(iOS 18.0, *) { limited = current == .limited; permitted = permitted || limited }
            #endif
            guard permitted else {
                if requestPermission { message = "Allow Contacts access in system settings to choose people to import." }
                return
            }
            contacts = try await Task.detached(priority: .userInitiated) {
                let keys: [CNKeyDescriptor] = [CNContactIdentifierKey as CNKeyDescriptor, CNContactGivenNameKey as CNKeyDescriptor,
                    CNContactFamilyNameKey as CNKeyDescriptor, CNContactMiddleNameKey as CNKeyDescriptor, CNContactNamePrefixKey as CNKeyDescriptor,
                    CNContactNameSuffixKey as CNKeyDescriptor, CNContactNicknameKey as CNKeyDescriptor, CNContactOrganizationNameKey as CNKeyDescriptor,
                    CNContactPhoneNumbersKey as CNKeyDescriptor, CNContactEmailAddressesKey as CNKeyDescriptor, CNContactBirthdayKey as CNKeyDescriptor]
                var result: [SystemContactSnapshot] = []
                let request = CNContactFetchRequest(keysToFetch: keys); request.unifyResults = true
                try CNContactStore().enumerateContacts(with: request) { contact, _ in
                    let full = [contact.namePrefix, contact.givenName, contact.middleName, contact.familyName, contact.nameSuffix].filter { !$0.isEmpty }.joined(separator: " ")
                    let name = full.isEmpty ? (contact.nickname.isEmpty ? contact.organizationName : contact.nickname) : full
                    guard !name.isEmpty else { return }
                    let birthday = contact.birthday.flatMap { parts -> Birthday? in
                        guard let m = parts.month, let d = parts.day else { return nil }
                        return try? Birthday(month: m, day: d, year: parts.year)
                    }
                    result.append(SystemContactSnapshot(id: contact.identifier, name: name, phones: contact.phoneNumbers.map { $0.value.stringValue }, emails: contact.emailAddresses.map { String($0.value) }, birthday: birthday))
                }
                return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            }.value
            loaded = true
        } catch { message = "Couldn't read Contacts: " + error.localizedDescription }
    }
    func followChanges() async {
        guard (try? repository.people().contains { $0.contactLinks.contains { $0.deviceID == deviceID && $0.followsChanges } }) == true else { return }
        await load(requestPermission: false)
        guard loaded, message == nil else { return }
        do {
            let before = try repository.people()
            // Avoid writing unchanged data every time the app becomes active.
            var preview = before
            for i in preview.indices {
                for link in preview[i].contactLinks where link.deviceID == deviceID && link.followsChanges {
                    if let current = contacts.first(where: { $0.id == link.contact.id }) { ContactsIntegration.apply(current, to: &preview[i], deviceID: deviceID, follow: true) }
                }
            }
            if before != preview { try repository.refreshContacts(contacts, deviceID: deviceID) }
        } catch { message = "Couldn't update linked people: " + error.localizedDescription }
    }
    func openSettings() {
        #if os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts") { NSWorkspace.shared.open(url) }
        #else
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        #endif
    }
}
