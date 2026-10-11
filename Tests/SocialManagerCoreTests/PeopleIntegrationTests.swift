import XCTest
@testable import SocialManagerCore

final class PeopleIntegrationTests: XCTestCase {
    let zone = TimeZone(identifier: "Pacific/Auckland")!
    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0) -> Date {
        var c = Calendar(identifier: .gregorian); c.timeZone = zone
        return c.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }
    func repository() -> RelationshipRepository { RelationshipRepository(directory: FileManager.default.temporaryDirectory.appendingPathComponent("keepclose-test-" + UUID().uuidString)) }
    func testBirthdayValidatesDatesAndAllowsUnknownYear() throws {
        XCTAssertThrowsError(try Birthday(month: 4, day: 31)); XCTAssertThrowsError(try Birthday(month: 2, day: 29, year: 2001))
        XCTAssertThrowsError(try Birthday(month: 0, day: 1)); XCTAssertThrowsError(try Birthday(month: 1, day: 0))
        XCTAssertNil(try Birthday(month: 2, day: 29).year)
        XCTAssertThrowsError(try JSONDecoder().decode(Birthday.self, from: Data("{\"month\":13,\"day\":3}".utf8)))
    }
    func testLeapDayAndYearRollover() throws {
        let b = try Birthday(month: 2, day: 29)
        XCTAssertEqual(b.occurrence(in: 2027, timeZone: zone), date(2027, 2, 28))
        XCTAssertEqual(b.occurrence(in: 2028, timeZone: zone), date(2028, 2, 29))
        XCTAssertEqual(b.nextDate(after: date(2027, 2, 28, 23), timeZone: zone), date(2027, 2, 28))
        XCTAssertEqual(b.nextDate(after: date(2027, 3, 1), timeZone: zone), date(2028, 2, 29))
    }
    func testGiftLeadCrossesYearAndDSTUsingLocalDays() throws {
        var p = Person(name: "Example"); p.birthday = try Birthday(month: 1, day: 5)
        let notices = BirthdayPlanner.notices(people: [p], after: date(2026, 12, 20), timeZone: zone)
        XCTAssertEqual(notices.first?.date, date(2026, 12, 22, 9)); XCTAssertEqual(notices.first?.kind, .gift)
        p.birthday = try Birthday(month: 10, day: 3)
        let dst = BirthdayPlanner.notices(people: [p], after: date(2026, 9, 18), timeZone: zone)
        XCTAssertEqual(dst.first?.date, date(2026, 9, 19, 9))
        XCTAssertEqual(dst[1].date, date(2026, 10, 3, 9))
    }
    func testPastRemindersAreNotDeliveredLate() throws {
        var p = Person(name: "Example"); p.birthday = try Birthday(month: 10, day: 11)
        let notices = BirthdayPlanner.notices(people: [p], after: date(2026, 10, 11, 10), timeZone: zone)
        XCTAssertTrue(notices.allSatisfy { $0.date > date(2026, 10, 11, 10) })
        XCTAssertFalse(notices.contains { $0.date == date(2026, 10, 11, 9) })
    }
    func testGiftDefaultsAndBoundaries() throws {
        var p = Person(name: "Example"); p.birthday = try Birthday(month: 10, day: 25)
        let now = date(2026, 10, 1)
        XCTAssertTrue(BirthdayPlanner.notices(people: [p], after: now, timeZone: zone).contains { $0.kind == .gift })
        p.relationshipTypes = ["Colleague"]
        XCTAssertFalse(BirthdayPlanner.notices(people: [p], after: now, timeZone: zone).contains { $0.kind == .gift })
        p.giftReminder = .on
        XCTAssertTrue(p.hasGiftReminder)
        p.intention = .space; XCTAssertTrue(BirthdayPlanner.notices(people: [p], after: now).isEmpty)
        p.intention = .maintain; p.paused = true; XCTAssertTrue(BirthdayPlanner.notices(people: [p], after: now).isEmpty)
        p.paused = false; p.birthdayReminder = false
        XCTAssertTrue(BirthdayPlanner.notices(people: [p], after: now).allSatisfy { $0.kind == .gift })
        p.giftReminder = .off; XCTAssertTrue(BirthdayPlanner.notices(people: [p], after: now).isEmpty)
    }
    func testBirthdayPrivacyAndIdentifier() throws {
        let notice = BirthdayNotice(personID: UUID(), name: "Private Name\n", date: date(2026, 10, 25), kind: .birthday)
        XCTAssertFalse(notice.id.contains("Private")); XCTAssertFalse(BirthdayReminderText.title.contains("Private"))
        for policy in [ReminderPreviewPolicy.always, .never, .unknown] { XCTAssertFalse(BirthdayReminderText.body(for: notice, includeNames: true, policy: policy).contains("Private")) }
        XCTAssertFalse(BirthdayReminderText.body(for: notice, includeNames: false, policy: .whenUnlocked).contains("Private"))
        let named = BirthdayReminderText.body(for: notice, includeNames: true, policy: .whenUnlocked)
        XCTAssertTrue(named.contains("Private Name")); XCTAssertFalse(named.contains("\n"))
    }
    func testUniqueAddressMatchesAndNameRequiresReview() {
        let contact = SystemContactSnapshot(id: "test", name: "Example Mum", phones: ["+64 21 123 456"])
        var p = Person(name: "My Mum", address: "+64 (21) 123-456")
        XCTAssertEqual(ContactsIntegration.match(contact, people: [p], deviceID: "device").automaticID, p.id)
        p.address = ""; p.name = " Example  Múm "
        let match = ContactsIntegration.match(contact, people: [p], deviceID: "device")
        XCTAssertEqual(match.reason, .name); XCTAssertNil(match.automaticID)
        var other = p; other.id = UUID()
        XCTAssertEqual(ContactsIntegration.match(contact, people: [p, other], deviceID: "device").candidates.count, 2)
    }
    func testAmbiguousAddressNeverAutomaticallyMatches() {
        let c = SystemContactSnapshot(id: "test", name: "Example", emails: ["EXAMPLE@example.invalid"])
        let a = Person(name: "A", method: .email, address: "example@example.invalid")
        let b = Person(name: "B", method: .email, address: "example@example.invalid")
        XCTAssertNil(ContactsIntegration.match(c, people: [a, b], deviceID: "device").automaticID)
    }
    func testFollowingChangesPreservesManualEditsPermanently() throws {
        var c = SystemContactSnapshot(id: "test", name: "Example", emails: ["first@example.invalid"], birthday: try Birthday(month: 2, day: 3))
        var p = ContactsIntegration.newPerson(c, deviceID: "device", follow: true)
        c.name = "Contacts rename"; c.emails = ["second@example.invalid"]; c.birthday = try Birthday(month: 2, day: 4)
        ContactsIntegration.apply(c, to: &p, deviceID: "device", follow: true)
        XCTAssertEqual(p.name, c.name); XCTAssertEqual(p.address, c.preferredAddress); XCTAssertEqual(p.birthday, c.birthday)
        p.name = "My name"; p.address = "my@example.invalid"; p.birthday = nil
        c.name = "Later name"; c.emails = []; c.birthday = nil
        ContactsIntegration.apply(c, to: &p, deviceID: "device", follow: true)
        c.birthday = try Birthday(month: 7, day: 8)
        ContactsIntegration.apply(c, to: &p, deviceID: "device", follow: true)
        XCTAssertEqual(p.name, "My name"); XCTAssertEqual(p.address, "my@example.invalid"); XCTAssertNil(p.birthday)
        XCTAssertEqual(p.contacts.count, 0); XCTAssertEqual(p.intention, .unsure)
    }
    func testFirstLinkPreservesExistingUserFields() throws {
        var p = Person(name: "Mum", method: .message, address: "my phone"); p.birthday = try Birthday(month: 3, day: 4)
        var c = SystemContactSnapshot(id: "test", name: "Other name", emails: ["other@example.invalid"], birthday: try Birthday(month: 5, day: 6))
        ContactsIntegration.apply(c, to: &p, deviceID: "device", follow: true)
        c.name = "Mum"; c.birthday = p.birthday
        ContactsIntegration.apply(c, to: &p, deviceID: "device", follow: true)
        c.name = "Still other"; c.birthday = nil
        ContactsIntegration.apply(c, to: &p, deviceID: "device", follow: true)
        XCTAssertEqual(p.name, "Mum"); XCTAssertEqual(p.address, "my phone"); XCTAssertEqual(p.birthday, try Birthday(month: 3, day: 4))
    }
    func testContactImportPreservesPreferredCallsAndInPerson() {
        var c = SystemContactSnapshot(id: "example", name: "Example", phones: ["000001"], emails: ["example@example.invalid"])
        var caller = Person(name: "Example", method: .call)
        ContactsIntegration.apply(c, to: &caller, deviceID: "one", follow: true)
        XCTAssertEqual(caller.method, .call); XCTAssertEqual(caller.address, "000001")
        c.phones = ["000002"]
        ContactsIntegration.apply(c, to: &caller, deviceID: "one", follow: true)
        XCTAssertEqual(caller.method, .call); XCTAssertEqual(caller.address, "000002")
        var inPerson = Person(name: "Example", method: .inPerson)
        ContactsIntegration.apply(c, to: &inPerson, deviceID: "one", follow: true)
        XCTAssertEqual(inPerson.method, .inPerson); XCTAssertTrue(inPerson.address.isEmpty)
        ContactsIntegration.apply(c, to: &inPerson, deviceID: "one", follow: true)
        XCTAssertEqual(inPerson.method, .inPerson)
    }
    func testContactsImportIdempotenceDeviceScopeAndMissingContacts() throws {
        let repo = repository(); defer { try? FileManager.default.removeItem(at: repo.directory) }
        let c = SystemContactSnapshot(id: "test", name: "Example", emails: ["example@example.invalid"])
        let choice = ContactImportChoice(contact: c, personID: nil, follow: true)
        try repo.importContacts([choice], deviceID: "one", expected: [])
        let first = try repo.people()
        try repo.importContacts([choice], deviceID: "one", expected: first)
        XCTAssertEqual(try repo.people(), first)
        XCTAssertEqual(ContactsIntegration.match(c, people: first, deviceID: "two").reason, .address)
        try repo.refreshContacts([], deviceID: "one"); XCTAssertEqual(try repo.people(), first)
        XCTAssertThrowsError(try repo.importContacts([choice], deviceID: "one", expected: []))
    }
    func testReadOnlyLinksAreNotRefreshed() throws {
        let repo = repository(); defer { try? FileManager.default.removeItem(at: repo.directory) }
        var c = SystemContactSnapshot(id: "test", name: "Example")
        try repo.importContacts([ContactImportChoice(contact: c, personID: nil, follow: false)], deviceID: "one", expected: [])
        c.name = "Changed"
        try repo.refreshContacts([c], deviceID: "one")
        XCTAssertEqual(try repo.people().first?.name, "Example")
    }
    func testMergePreservesHistoryPlansContextBoundariesAndAliases() throws {
        var a = Person(name: "Mum", address: "one", context: "First note")
        var b = Person(name: "Mum duplicate", address: "two", context: "Second note")
        let invitation = b.recordContact(note: "Invited", kind: .outreach)
        let plan = ConnectionPlan(title: "Dinner", date: .now); b.plans.append(plan)
        a.birthday = try Birthday(month: 3, day: 4); b.birthday = try Birthday(month: 5, day: 6)
        b.intention = .space; b.paused = true; b.snoozedUntil = .distantFuture
        a.addIdea(activity: "A game evening"); b.addIdea(activity: "A game evening")
        b.connection.ideas[0].dismissed = true
        let merge = try PeopleMerge(keeping: a, merging: b, useSourceBirthday: true)
        let p = merge.combined
        XCTAssertEqual(p.id, a.id); XCTAssertEqual(p.name, a.name); XCTAssertEqual(p.birthday, b.birthday)
        XCTAssertTrue(p.context.contains("Second note")); XCTAssertTrue(p.contacts.contains { $0.id == invitation })
        XCTAssertEqual(p.plans, [plan]); XCTAssertEqual(p.intention, .space); XCTAssertTrue(p.paused)
        XCTAssertEqual(p.alternateContactDetails.first?.address, "two"); XCTAssertTrue(p.mergedPersonIDs.contains(b.id))
        XCTAssertTrue(p.connection.ideas.allSatisfy(\.dismissed)); XCTAssertEqual(p.snoozedUntil, .distantFuture)
    }
    func testMergeReconcilesActualResponsesAcrossBothHistories() throws {
        var a = Person(name: "Example"); var b = Person(name: "Example duplicate")
        b.recordContact(at: date(2026, 10, 1), kind: .incoming)
        a.recordContact(at: date(2026, 10, 2), kind: .conversation)
        let merged = try PeopleMerge(keeping: a, merging: b).combined
        XCTAssertTrue(merged.pendingIncoming.isEmpty)
        XCTAssertEqual(merged.contacts.count, 2)
        var corrected = merged
        corrected.removeContact(a.contacts[0].id)
        XCTAssertEqual(corrected.pendingIncoming.count, 1)
    }
    func testMergeBackupUndoAndStaleGuard() throws {
        let repo = repository(); defer { try? FileManager.default.removeItem(at: repo.directory) }
        let a = Person(name: "A"); let b = Person(name: "B")
        try repo.modifyPeople { $0 = [a, b] }
        let plan = try PeopleMerge(keeping: a, merging: b)
        try repo.merge(plan); XCTAssertEqual(try repo.people(), [plan.combined])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: repo.directory.appendingPathComponent("backups").path).count, 1)
        try repo.undoMerge(plan); XCTAssertEqual(Set(try repo.people().map(\.id)), Set([a.id, b.id]))
        try repo.merge(plan)
        try repo.modifyPeople { $0[0].context = "A later edit" }
        XCTAssertThrowsError(try repo.undoMerge(plan)); XCTAssertEqual(try repo.people()[0].context, "A later edit")
        XCTAssertThrowsError(try repo.merge(plan))
    }
    func testOldImportIDResolvesMergedPerson() throws {
        let a = Person(name: "Mum"); let b = Person(name: "Other Mum")
        let merged = try PeopleMerge(keeping: a, merging: b).combined
        let json = "{\"version\":1,\"source\":\"chatgpt\",\"people\":[{\"id\":\"" + b.id.uuidString + "\",\"name\":\"Other Mum\",\"notes\":\"A new note\"}]}"
        let plan = try AgentImportPlan.make(batch: AgentImportBatch.parse(Data(json.utf8)), existing: [merged])
        XCTAssertEqual(plan.changes.first?.person.id, a.id); XCTAssertEqual(plan.changes.first?.person.name, a.name)
    }
    func testLegacyPersonDefaultsAndNewRoundTrip() throws {
        let p = Person(name: "Example")
        let encoder = JSONEncoder(); let decoder = JSONDecoder()
        var json = try JSONSerialization.jsonObject(with: encoder.encode(p)) as! [String: Any]
        for key in ["birthday", "birthdayReminder", "giftReminder", "contactLinks", "mergedPersonIDs", "alternateContactDetails"] { json.removeValue(forKey: key) }
        let old = try decoder.decode(Person.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(old.birthday); XCTAssertTrue(old.birthdayReminder); XCTAssertEqual(old.giftReminder, .automatic); XCTAssertTrue(old.contactLinks.isEmpty)
        var updated = old; updated.birthday = try Birthday(month: 7, day: 8)
        updated.contactLinks = [SystemContactLink(deviceID: "one", contact: SystemContactSnapshot(id: "example", name: "Example"), followsChanges: true)]
        XCTAssertEqual(try decoder.decode(Person.self, from: encoder.encode(updated)), updated)
    }
}
