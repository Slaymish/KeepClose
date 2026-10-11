import XCTest
@testable import SocialManagerCore

final class SuggestionTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
    func testIncomingPrioritizesReplyWithoutPretendingWeConnected() {
        var person = Person(name: "Alex", createdAt: now)
        person.recordContact(at: now, kind: .incoming)
        XCTAssertNil(person.lastContact)
        XCTAssertEqual(person.lastIncoming, now)
        XCTAssertEqual(person.suggestion(at: now, calendar: calendar).action, .reply)
        XCTAssertTrue(person.isDue(at: now, calendar: calendar))
        person.recordContact(at: now.addingTimeInterval(60), kind: .reply)
        XCTAssertTrue(person.pendingIncoming.isEmpty)
        XCTAssertFalse(person.isDue(at: now.addingTimeInterval(60), calendar: calendar))
    }
    func testAmbientDoesNotResetConnectionRhythm() {
        var person = Person(name: "Alex", createdAt: now)
        person.recordContact(at: now, kind: .ambient)
        XCTAssertNil(person.lastContact)
        XCTAssertTrue(person.isDue(at: now, calendar: calendar))
    }
    func testSpaceAllowsReplyButSuppressesProactiveActions() {
        var person = Person(name: "Alex", createdAt: now)
        person.intention = .space
        XCTAssertFalse(person.isDue(at: now, calendar: calendar))
        XCTAssertEqual(person.suggestion(at: now, calendar: calendar).action, .giveSpace)
        person.recordContact(at: now, kind: .incoming)
        XCTAssertTrue(person.isDue(at: now, calendar: calendar))
        person.paused = true
        XCTAssertFalse(person.isDue(at: now, calendar: calendar))
    }
    func testTwoUnansweredAttemptsSuggestRoomAndResponseRestoresRhythm() {
        var person = Person(name: "Alex", rhythmDays: 7, createdAt: now)
        person.recordContact(at: now.addingTimeInterval(-20 * 86400))
        person.recordContact(at: now.addingTimeInterval(-10 * 86400))
        XCTAssertEqual(person.suggestion(at: now, calendar: calendar).action, .giveSpace)
        XCTAssertFalse(person.isDue(at: now, calendar: calendar))
        person.recordContact(at: now, kind: .conversation, initiator: .them)
        XCTAssertEqual(person.suggestion(at: now, calendar: calendar).action, .later)
    }
    func testThemInitiatingDoesNotTriggerPrematureNudge() {
        var person = Person(name: "Alex", rhythmDays: 7, createdAt: now)
        for days in [21, 14, 7] {
            person.recordContact(at: now.addingTimeInterval(Double(-days * 86400)), kind: .conversation, initiator: .them)
        }
        XCTAssertEqual(person.suggestion(at: now, calendar: calendar).action, .takeInitiative)
        person.recordContact(at: now, kind: .conversation, initiator: .them)
        XCTAssertEqual(person.suggestion(at: now, calendar: calendar).action, .later)
    }
    func testGrowUnsureAndEditableCategoryDefaults() {
        var person = Person(name: "Alex", createdAt: now)
        person.intention = .grow; person.contexts = ["Online", "Work"]; person.relationshipTypes = ["Colleague", "Friend"]
        person.applySuggestedRhythm()
        XCTAssertEqual(person.suggestion(at: now, calendar: calendar).action, .timeTogether)
        XCTAssertLessThan(person.rhythmDays, 21)
        person.intention = .unsure
        XCTAssertEqual(person.suggestion(at: now, calendar: calendar).action, .reflect)
    }
    func testBackdatedIncomingAfterLoggedReplyIsAlreadyResolved() {
        var person = Person(name: "Alex", createdAt: now)
        person.recordContact(at: now, kind: .reply)
        person.recordContact(at: now.addingTimeInterval(-3600), kind: .incoming)
        XCTAssertTrue(person.pendingIncoming.isEmpty)
    }
    func testReplyOnlyClosesEarlierIncomingAndSnoozeRespected() {
        var person = Person(name: "Alex", createdAt: now)
        person.recordContact(at: now.addingTimeInterval(-3600), kind: .incoming)
        person.recordContact(at: now, kind: .incoming)
        person.recordContact(at: now.addingTimeInterval(-1800), kind: .reply)
        XCTAssertEqual(person.pendingIncoming.count, 1)
        person.deferContact(until: now.addingTimeInterval(86400))
        XCTAssertFalse(person.isDue(at: now, calendar: calendar))
        person.resolveIncoming(person.pendingIncoming[0].id, at: now)
        XCTAssertTrue(person.pendingIncoming.isEmpty)
    }
    func testLegacyRecordsPreserveNotesRhythmAndDontInferMissingReplies() throws {
        let id = UUID()
        let entry: [String: Any] = ["id": UUID().uuidString, "date": now.timeIntervalSinceReferenceDate - 86400, "note": "Old contact"]
        let legacy: [String: Any] = ["id": id.uuidString, "name": "Alex", "circle": "Custom relationship", "rhythmDays": 19, "method": "Message", "address": "", "context": "Private nuance", "createdAt": now.timeIntervalSinceReferenceDate, "contacts": [entry, entry.merging(["id": UUID().uuidString]) { _, new in new }], "paused": false, "deferrals": 0]
        let person = try JSONDecoder().decode(Person.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(person.id, id)
        XCTAssertEqual(person.context, "Private nuance")
        XCTAssertEqual(person.relationshipTypes, ["Custom relationship"])
        XCTAssertEqual(person.rhythmDays, 19)
        XCTAssertTrue(person.rhythmIsCustom)
        XCTAssertFalse(person.contacts[0].tracksResponse)
        XCTAssertNotEqual(person.suggestion(at: now.addingTimeInterval(30 * 86400), calendar: calendar).action, .giveSpace)
        XCTAssertEqual(try JSONDecoder().decode(Person.self, from: JSONEncoder().encode(person)), person)
    }
    func testIncomingAndItsCatchUpCountAsOneInitiation() {
        var person = Person(name: "Alex", rhythmDays: 7, createdAt: now)
        for days in [21, 14] {
            let at = now.addingTimeInterval(Double(-days * 86400))
            person.recordContact(at: at, kind: .incoming)
            person.recordContact(at: at.addingTimeInterval(60), kind: .conversation, initiator: .them)
        }
        XCTAssertEqual(person.suggestion(at: now, calendar: calendar).action, .hello)
    }
    func testReplySuggestionsSortFirst() {
        let old = Person(name: "Old", createdAt: now.addingTimeInterval(-86400))
        var reply = Person(name: "Reply", createdAt: now)
        reply.recordContact(at: now, kind: .incoming)
        XCTAssertEqual([old, reply].suggestedPeople(at: now, calendar: calendar).first?.name, "Reply")
    }
}
