import XCTest
@testable import SocialManagerCore

final class PersonTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
    func testNewPersonReadyAndPauseSuppresses() {
        var person = Person(name: "Sam", createdAt: now)
        person.addIdea(activity: "an evening of Stardew Valley")
        XCTAssertTrue(person.isDue(at: now, calendar: calendar))
        person.paused = true
        XCTAssertFalse(person.isDue(at: now, calendar: calendar))
    }
    func testActualContactResetsDeferralsAndStartsRhythm() {
        var person = Person(name: "Sam", rhythmDays: 14, createdAt: now)
        person.addIdea(activity: "an evening of Stardew Valley")
        person.deferContact(until: now.addingTimeInterval(30 * 86400))
        person.recordContact(at: now, kind: .conversation)
        XCTAssertEqual(person.deferrals, 0)
        XCTAssertNil(person.snoozedUntil)
        XCTAssertEqual(person.nextDue(calendar: calendar), calendar.date(byAdding: .day, value: 14, to: now))
        XCTAssertFalse(person.isDue(at: now, calendar: calendar))
        XCTAssertTrue(person.isDue(at: now.addingTimeInterval(14 * 86400), calendar: calendar))
    }
    func testSnoozeCannotMakeFutureRhythmEarlier() {
        var person = Person(name: "Sam", rhythmDays: 14, createdAt: now)
        person.addIdea(activity: "an evening of Stardew Valley")
        person.recordContact(at: now, kind: .conversation)
        person.deferContact(until: now.addingTimeInterval(86400))
        XCTAssertEqual(person.nextDue(calendar: calendar), now.addingTimeInterval(14 * 86400))
    }
    func testBackdatedEntryDoesNotReplaceLatestContact() {
        var person = Person(name: "Sam", createdAt: now)
        person.addIdea(activity: "an evening of Stardew Valley")
        person.recordContact(at: now, kind: .conversation)
        person.recordContact(at: now.addingTimeInterval(-86400))
        XCTAssertEqual(person.lastContact, now)
    }
    func testDueIsCalendarDayAndPersistenceRoundTrips() throws {
        var person = Person(name: "Sam", createdAt: now)
        person.addIdea(activity: "an evening of Stardew Valley")
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        person.deferContact(until: tomorrow)
        XCTAssertFalse(person.isDue(at: now, calendar: calendar))
        XCTAssertTrue(person.isDue(at: calendar.startOfDay(for: tomorrow), calendar: calendar))
        XCTAssertEqual(try JSONDecoder().decode(Person.self, from: JSONEncoder().encode(person)), person)
    }
}
