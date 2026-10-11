import Foundation
import NativeCore

/// A birthday is a calendar date, not a timestamp. The year is optional.
public struct Birthday: Codable, Equatable, Hashable, Sendable {
    public let month: Int
    public let day: Int
    public let year: Int?
    public init(month: Int, day: Int, year: Int? = nil) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let y = year ?? 2000 // Allows a yearless February 29.
        guard (1...9999).contains(y), let date = calendar.date(from: DateComponents(year: y, month: month, day: day)),
              calendar.component(.month, from: date) == month, calendar.component(.day, from: date) == day else {
            throw RepositoryError.invalid("Choose a valid birthday.")
        }
        self.month = month; self.day = day; self.year = year
    }
    private enum CodingKeys: String, CodingKey { case month, day, year }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(month: c.decode(Int.self, forKey: .month), day: c.decode(Int.self, forKey: .day), year: c.decodeIfPresent(Int.self, forKey: .year))
    }
    /// February 29 is observed on February 28 in years without that date.
    public func occurrence(in year: Int, timeZone: TimeZone = .current) -> Date {
        var c = Calendar(identifier: .gregorian); c.timeZone = timeZone
        var d = c.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
        if c.component(.month, from: d) != month { d = c.date(from: DateComponents(year: year, month: month, day: 28, hour: 12))! }
        return c.startOfDay(for: d)
    }
    public func nextDate(after now: Date = .now, timeZone: TimeZone = .current) -> Date {
        var c = Calendar(identifier: .gregorian); c.timeZone = timeZone
        let year = c.component(.year, from: now)
        let date = occurrence(in: year, timeZone: timeZone)
        return date >= c.startOfDay(for: now) ? date : occurrence(in: year + 1, timeZone: timeZone)
    }
    public var label: String {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = c.date(from: DateComponents(year: year ?? 2000, month: month, day: day, hour: 12))!
        let f = DateFormatter(); f.calendar = c; f.timeZone = c.timeZone
        f.setLocalizedDateFormatFromTemplate(year == nil ? "MMMMd" : "yMMMMd")
        return f.string(from: date)
    }
}
public enum GiftReminder: String, Codable, CaseIterable, Sendable {
    case automatic, on, off
    public var title: String { switch self { case .automatic: "For friends and family"; case .on: "On"; case .off: "Off" } }
}
extension Person {
    public var hasGiftReminder: Bool {
        giftReminder == .on || giftReminder == .automatic && relationshipTypes.contains { ["friend", "family"].contains($0.lowercased()) }
    }
}
public struct BirthdayNotice: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable { case birthday, gift }
    public let personID: UUID
    public let name: String
    public let date: Date
    public let kind: Kind
    public var id: String { "birthday-" + personID.uuidString + "-" + kind.rawValue + "-" + String(Int(date.timeIntervalSince1970)) }
}
public enum BirthdayPlanner {
    /// Calendar arithmetic preserves local wall-clock time across DST and year boundaries.
    public static func notices(people: [Person], after now: Date = .now, hour: Int = 9, minute: Int = 0, timeZone: TimeZone = .current) -> [BirthdayNotice] {
        guard (0...23).contains(hour), (0...59).contains(minute) else { return [] }
        var c = Calendar(identifier: .gregorian); c.timeZone = timeZone
        let year = c.component(.year, from: now)
        return people.filter { !$0.paused && $0.intention != .space }.flatMap { person -> [BirthdayNotice] in
            guard let birthday = person.birthday else { return [] }
            return (year...year + 2).flatMap { y -> [BirthdayNotice] in
                let day = birthday.occurrence(in: y, timeZone: timeZone)
                let birthdayDate = c.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
                var result = person.birthdayReminder ? [BirthdayNotice(personID: person.id, name: person.name, date: birthdayDate, kind: .birthday)] : []
                if person.hasGiftReminder, let gift = c.date(byAdding: .day, value: -14, to: birthdayDate) {
                    result.append(BirthdayNotice(personID: person.id, name: person.name, date: gift, kind: .gift))
                }
                return result.filter { $0.date > now && $0.date < c.date(byAdding: .year, value: 2, to: now)! }
            }
        }.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
    }
}

/// Only the fields actually used by Keep Close. Never imports contact notes or history.
public struct SystemContactSnapshot: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var phones: [String]
    public var emails: [String]
    public var birthday: Birthday?
    public init(id: String, name: String, phones: [String] = [], emails: [String] = [], birthday: Birthday? = nil) {
        self.id = id; self.name = name; self.phones = phones; self.emails = emails; self.birthday = birthday
    }
    public var preferredAddress: String { emails.first ?? phones.first ?? "" }
    public var preferredMethod: ContactMethod { emails.isEmpty ? .message : .email }
    public func address(for method: ContactMethod) -> String {
        switch method { case .email: emails.first ?? ""; case .message, .call: phones.first ?? ""; case .inPerson: "" }
    }
}
public struct SystemContactLink: Codable, Equatable, Sendable, Identifiable {
    public var deviceID: String
    public var contact: SystemContactSnapshot
    public var followsChanges: Bool
    public var overrides: [String]?
    public var importedAddress: String?
    public var importedMethod: ContactMethod?
    public var id: String { deviceID + ":" + contact.id }
    public init(deviceID: String, contact: SystemContactSnapshot, followsChanges: Bool) {
        self.deviceID = deviceID; self.contact = contact; self.followsChanges = followsChanges
    }
}
public struct ContactMatch: Equatable, Sendable {
    public enum Reason: String, Sendable { case linked, address, name, none }
    public var reason: Reason
    public var candidates: [UUID]
    public var automaticID: UUID? { [.linked, .address].contains(reason) && candidates.count == 1 ? candidates.first : nil }
}
public enum ContactsIntegration {
    public static func normalizedName(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")).split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
    private static func email(_ value: String) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    private static func phone(_ value: String) -> String { String(value.filter { $0.isNumber }) }
    public static func match(_ contact: SystemContactSnapshot, people: [Person], deviceID: String) -> ContactMatch {
        let linked = people.filter { $0.contactLinks.contains { $0.deviceID == deviceID && $0.contact.id == contact.id } }.map(\.id)
        if !linked.isEmpty { return ContactMatch(reason: .linked, candidates: linked) }
        let addresses = people.filter { person in
            var phones = person.contactLinks.flatMap { $0.contact.phones }
            var emails = person.contactLinks.flatMap { $0.contact.emails }
            if person.method == .email { emails.append(person.address) } else { phones.append(person.address) }
            for detail in person.alternateContactDetails {
                if detail.method == .email { emails.append(detail.address) } else { phones.append(detail.address) }
            }
            return contact.emails.contains { item in !email(item).isEmpty && emails.contains { email($0) == email(item) } } ||
                contact.phones.contains { item in !phone(item).isEmpty && phones.contains { phone($0) == phone(item) } }
        }.map(\.id)
        if !addresses.isEmpty { return ContactMatch(reason: .address, candidates: addresses) }
        let names = people.filter { normalizedName($0.name) == normalizedName(contact.name) }.map(\.id)
        return ContactMatch(reason: names.isEmpty ? .none : .name, candidates: names)
    }
    /// Three-way update: only fields still equal to their previous imported value follow Contacts.
    public static func apply(_ contact: SystemContactSnapshot, to person: inout Person, deviceID: String, follow: Bool) {
        let index = person.contactLinks.firstIndex { $0.deviceID == deviceID && $0.contact.id == contact.id }
        if let index {
            let previous = person.contactLinks[index].contact
            let previousMethod = person.contactLinks[index].importedMethod ?? previous.preferredMethod
            let previousAddress = person.contactLinks[index].importedAddress ?? previous.preferredAddress
            let nextAddress = contact.address(for: previousMethod)
            var overrides = Set(person.contactLinks[index].overrides ?? [])
            if person.name != previous.name { overrides.insert("name") }
            if person.address != previousAddress || person.method != previousMethod { overrides.insert("address") }
            if person.birthday != previous.birthday { overrides.insert("birthday") }
            if !overrides.contains("name") { person.name = contact.name }
            if !overrides.contains("address") {
                person.address = nextAddress; person.method = previousMethod
            }
            if !overrides.contains("birthday") { person.birthday = contact.birthday }
            person.contactLinks[index] = SystemContactLink(deviceID: deviceID, contact: contact, followsChanges: follow)
            person.contactLinks[index].overrides = overrides.sorted()
            person.contactLinks[index].importedAddress = nextAddress
            person.contactLinks[index].importedMethod = previousMethod
        } else {
            let importedAddress = contact.address(for: person.method)
            if person.address.isEmpty && person.method != .inPerson { person.address = importedAddress }
            if person.birthday == nil { person.birthday = contact.birthday }
            var link = SystemContactLink(deviceID: deviceID, contact: contact, followsChanges: follow)
            var protected: [String] = []
            if person.name != contact.name { protected.append("name") }
            if person.address != importedAddress { protected.append("address") }
            if person.birthday != contact.birthday { protected.append("birthday") }
            link.overrides = protected; link.importedAddress = importedAddress; link.importedMethod = person.method
            person.contactLinks.append(link)
        }
    }
    public static func newPerson(_ contact: SystemContactSnapshot, deviceID: String, follow: Bool) -> Person {
        var person = Person(name: contact.name, circle: "")
        person.relationshipTypes = []; person.intention = .unsure; person.intentionChosen = false; person.method = contact.preferredMethod
        apply(contact, to: &person, deviceID: deviceID, follow: follow)
        return person
    }
}

public struct PersonContactDetail: Codable, Equatable, Sendable, Identifiable {
    public var method: ContactMethod
    public var address: String
    public var id: String { method.rawValue + ":" + address }
    public init(method: ContactMethod, address: String) { self.method = method; self.address = address }
}
public struct PeopleMerge: Sendable {
    public let kept: Person
    public let removed: Person
    public let combined: Person
    public init(keeping target: Person, merging source: Person, useSourceBirthday: Bool = false) throws {
        guard target.id != source.id else { throw RepositoryError.invalid("Choose two different people.") }
        var p = target
        func union<T: Identifiable & Equatable>(_ a: [T], _ b: [T]) throws -> [T] {
            var result = a
            for item in b {
                if let old = result.first(where: { $0.id == item.id }) {
                    guard old == item else { throw RepositoryError.invalid("These records have conflicting versions of the same saved item. Resolve the difference before merging.") }
                } else { result.append(item) }
            }
            return result
        }
        func strings<T: Equatable>(_ a: [T], _ b: [T]) -> [T] { a + b.filter { !a.contains($0) } }
        p.relationshipTypes = strings(p.relationshipTypes, source.relationshipTypes)
        p.contexts = strings(p.contexts, source.contexts); p.importSources = strings(p.importSources, source.importSources)
        p.circle = p.relationshipTypes.joined(separator: ", ")
        if p.context.isEmpty { p.context = source.context }
        else if !source.context.isEmpty && p.context != source.context { p.context += "\n\n" + source.context }
        if p.address.isEmpty { p.address = source.address; p.method = source.method }
        p.alternateContactDetails = strings(p.alternateContactDetails, source.alternateContactDetails)
        if !source.address.isEmpty && (p.address != source.address || p.method != source.method) {
            p.alternateContactDetails = strings(p.alternateContactDetails, [PersonContactDetail(method: source.method, address: source.address)])
        }
        if p.birthday == nil || useSourceBirthday { p.birthday = source.birthday }
        p.birthdayReminder = p.birthdayReminder && source.birthdayReminder
        if source.giftReminder == .off { p.giftReminder = .off }
        p.paused = p.paused || source.paused
        if source.intention == .space { p.intention = .space; p.intentionChosen = true }
        p.snoozedUntil = [p.snoozedUntil, source.snoozedUntil].compactMap { $0 }.max()
        p.createdAt = min(p.createdAt, source.createdAt)
        p.contacts = try union(p.contacts, source.contacts)
        p.reconcileResponses()
        p.plans = try union(p.plans, source.plans)
        p.feedback = try union(p.feedback, source.feedback)
        p.connection.memories = try union(p.connection.memories, source.connection.memories)
        p.connection.interests = try union(p.connection.interests, source.connection.interests)
        p.connection.ideas = try union(p.connection.ideas, source.connection.ideas)
        p.connection.rituals = try union(p.connection.rituals, source.connection.rituals)
        // A duplicate idea that was set aside must not return through the other record.
        for i in p.connection.ideas.indices {
            if p.connection.ideas.contains(where: { $0.dismissed && $0.kind == p.connection.ideas[i].kind && AgentImportBatch.normalized($0.activity) == AgentImportBatch.normalized(p.connection.ideas[i].activity) }) { p.connection.ideas[i].dismissed = true }
        }
        for i in p.connection.rituals.indices {
            if p.connection.rituals.contains(where: { $0.dismissed && AgentImportBatch.normalized($0.title) == AgentImportBatch.normalized(p.connection.rituals[i].title) }) { p.connection.rituals[i].dismissed = true }
        }
        p.contactLinks = try union(p.contactLinks, source.contactLinks)
        p.mergedPersonIDs = strings(strings(p.mergedPersonIDs, source.mergedPersonIDs), [source.id])
        kept = target; removed = source; combined = p
    }
}
public extension RelationshipRepository {
    /// Backup and merge happen under the same repository transaction / shared file lock.
    func merge(_ plan: PeopleMerge) throws {
        try modifyPeople { people in
            guard people.first(where: { $0.id == plan.kept.id }) == plan.kept,
                  people.first(where: { $0.id == plan.removed.id }) == plan.removed else { throw RepositoryError.conflict }
            let backups = directory.appendingPathComponent("backups", isDirectory: true)
            try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: backups.path)
            try AtomicFile.write(NativeJSON.encode(people, dates: .deferredToDate, formatting: [.prettyPrinted, .sortedKeys]), to: backups.appendingPathComponent("before-merge-" + UUID().uuidString + ".json"))
            people.removeAll { $0.id == plan.removed.id }
            people[people.firstIndex(where: { $0.id == plan.kept.id })!] = plan.combined
        }
    }
    func undoMerge(_ plan: PeopleMerge) throws {
        try modifyPeople { people in
            guard let i = people.firstIndex(where: { $0.id == plan.combined.id }), people[i] == plan.combined,
                  !people.contains(where: { $0.id == plan.removed.id }) else { throw RepositoryError.conflict }
            people[i] = plan.kept; people.append(plan.removed)
        }
    }
}

public struct ContactImportChoice: Sendable {
    public var contact: SystemContactSnapshot
    public var personID: UUID?
    public var follow: Bool
    public init(contact: SystemContactSnapshot, personID: UUID?, follow: Bool) { self.contact = contact; self.personID = personID; self.follow = follow }
}
public extension RelationshipRepository {
    func importContacts(_ choices: [ContactImportChoice], deviceID: String, expected: [Person]) throws {
        try modifyPeople { people in
            guard people == expected else { throw RepositoryError.conflict }
            for choice in choices {
                let match = ContactsIntegration.match(choice.contact, people: people, deviceID: deviceID)
                if let id = choice.personID ?? match.automaticID {
                    guard let i = people.firstIndex(where: { $0.id == id }) else { throw RepositoryError.missing }
                    // Linking one system contact to two people would make following changes ambiguous.
                    guard match.reason != .linked || match.candidates == [id] else { throw RepositoryError.invalid("This contact is already linked to another person.") }
                    ContactsIntegration.apply(choice.contact, to: &people[i], deviceID: deviceID, follow: choice.follow)
                } else { people.append(ContactsIntegration.newPerson(choice.contact, deviceID: deviceID, follow: choice.follow)) }
            }
            if people != expected && !expected.isEmpty {
                let backups = directory.appendingPathComponent("backups", isDirectory: true)
                try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: backups.path)
                try AtomicFile.write(NativeJSON.encode(expected, dates: .deferredToDate, formatting: [.prettyPrinted, .sortedKeys]), to: backups.appendingPathComponent("before-contacts-" + UUID().uuidString + ".json"))
            }
        }
    }
    func refreshContacts(_ contacts: [SystemContactSnapshot], deviceID: String) throws {
        let byID = Dictionary(grouping: contacts, by: \.id).compactMapValues { $0.first }
        try modifyPeople { people in
            for i in people.indices {
                for link in people[i].contactLinks where link.deviceID == deviceID && link.followsChanges {
                    // Missing, limited-access and deleted contacts never delete Keep Close data.
                    if let current = byID[link.contact.id] { ContactsIntegration.apply(current, to: &people[i], deviceID: deviceID, follow: true) }
                }
            }
        }
    }
}

public enum BirthdayReminderText {
    public static let title = "An occasion to remember"
    public static let hiddenBody = "An occasion is coming up. Open Keep Close for the details."
    public static func body(for notice: BirthdayNotice, includeNames: Bool, policy: ReminderPreviewPolicy) -> String {
        guard includeNames, policy == .whenUnlocked else { return hiddenBody }
        let name = String(notice.name.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.map(String.init).joined().prefix(80))
        guard !name.isEmpty else { return hiddenBody }
        return notice.kind == .birthday ? "It's " + name + "'s birthday today. A little thought, in your own way." : name + "'s birthday is in two weeks. Perhaps think about a gift, if you'd like."
    }
}
