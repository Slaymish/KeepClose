import XCTest
@testable import SocialManagerCore

/// Behavioural tests for the shift from rhythm reminders to grounded opportunities.
final class ConnectionContextTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
    /// 1_800_000_000 is a Wednesday at 03:20 UTC.
    func person(ready: Bool = true, intention: RelationshipIntention = .maintain) -> Person {
        // A recorded contact 20 days ago leaves the 14-day rhythm ready; recording today does not.
        var person = Person(name: "Example person", rhythmDays: 14, createdAt: now.addingTimeInterval(-60 * 86400))
        person.intention = intention
        person.recordContact(at: ready ? now.addingTimeInterval(-20 * 86400) : now, kind: .conversation)
        return person
    }

    func testIdeaGroundedInSharedInterestBecomesTheSuggestion() {
        var person = person()
        person.addInterest("Board games", detail: "They keep a stack of them")
        person.addIdea(kind: .sharedActivity, activity: "an evening of board games", reason: "You both enjoy board games", timing: .weekend)
        let suggestion = person.suggestion(at: now, calendar: calendar)
        XCTAssertEqual(suggestion.action, .timeTogether)
        XCTAssertTrue(suggestion.ready)
        XCTAssertEqual(suggestion.title, "an evening of board games")
        XCTAssertTrue(suggestion.reason.contains("You both enjoy board games"))
        XCTAssertFalse(suggestion.reason.lowercased().contains("haven't"))
        XCTAssertEqual(suggestion.opportunity?.ideaId, person.visibleIdeas.first?.id)
    }

    func testSuggestionNeverClaimsAnotherPersonsAvailabilityOrFeelings() {
        var person = person()
        person.addIdea(kind: .sharedActivity, activity: "a walk along the canal", reason: "You enjoyed it last time")
        let text = [person.suggestion(at: now, calendar: calendar).title, person.suggestion(at: now, calendar: calendar).reason].joined(separator: " ")
        for claim in ["they want", "they'd love", "they miss", "they are free", "they'll be", "they would like", "they're expecting", "they will"] {
            XCTAssertFalse(text.lowercased().contains(claim), "Suggestion claims something about the other person: \(claim)")
        }
    }

    func testIdeaWaitsWhenRhythmIsNotReadyAndSurfacesWhenItIs() {
        var person = person(ready: false)
        person.addIdea(kind: .sharedActivity, activity: "a board game evening")
        let waiting = person.suggestion(at: now, calendar: calendar)
        XCTAssertFalse(waiting.ready)
        XCTAssertEqual(waiting.action, .later)
        XCTAssertEqual(waiting.title, "a board game evening", "A recorded idea is still worth showing while the rhythm waits.")
        XCTAssertFalse(waiting.reason.lowercased().contains("overdue"))
        let later = calendar.date(byAdding: .day, value: 15, to: now)!
        let surfaced = person.suggestion(at: later, calendar: calendar)
        XCTAssertTrue(surfaced.ready)
        XCTAssertEqual(surfaced.title, "a board game evening")
    }

    func testPassingOnAnIdeaIsRespectedAndDoesNotResurface() {
        var person = person()
        let idea = try! XCTUnwrap(person.addIdea(activity: "a board game evening"))
        XCTAssertEqual(person.suggestion(at: now, calendar: calendar).title, "a board game evening")
        person.dismissIdea(idea.id)
        person.recordFeedback(.notForMe, ideaId: idea.id)
        let after = person.suggestion(at: now, calendar: calendar)
        XCTAssertNotEqual(after.title, "a board game evening")
        XCTAssertTrue(person.visibleIdeas.isEmpty)
        XCTAssertTrue(person.passedOnIdea(idea.id))
        XCTAssertEqual(person.dismissedIdeaCount, 1)
    }

    func testDoneAndSnoozedFeedbackDelayAnIdeaWithoutGuilt() {
        var person = person()
        let idea = try! XCTUnwrap(person.addIdea(activity: "a board game evening", cadenceDays: 30))
        person.recordFeedback(.done, ideaId: idea.id, at: now)
        let soon = calendar.date(byAdding: .day, value: 5, to: now)!
        XCTAssertTrue(person.opportunities(at: soon, calendar: calendar).isEmpty)
        let later = calendar.date(byAdding: .day, value: 31, to: now)!
        XCTAssertTrue(person.opportunities(at: later, calendar: calendar).contains { $0.ideaId == idea.id })
    }

    func testHelpfulFeedbackMakesAPreferredIdeaWin() {
        var person = person(intention: .maintain)
        // A small gesture scores below an async message for a maintain relationship by default.
        let gesture = try! XCTUnwrap(person.addIdea(kind: .gesture, activity: "send a photo of the garden", cadenceDays: 1))
        let message = try! XCTUnwrap(person.addIdea(kind: .async, activity: "share a podcast episode", cadenceDays: 1))
        XCTAssertEqual(person.bestOpportunity(at: now, calendar: calendar)?.ideaId, message.id)
        person.recordFeedback(.helpful, ideaId: gesture.id, at: now)
        XCTAssertEqual(person.bestOpportunity(at: now, calendar: calendar)?.ideaId, gesture.id, "Something the user marked useful comes first.")
        XCTAssertTrue(person.opportunities(at: now, calendar: calendar).contains { $0.ideaId == message.id }, "Nothing is hidden by preferring one idea.")
    }

    func testIdeasWithACadenceWaitTheirTurn() {
        var person = person()
        // An idea with no cadence is available as soon as it is recorded.
        let open = try! XCTUnwrap(person.addIdea(activity: "a board game evening"))
        XCTAssertEqual(person.bestOpportunity(at: now, calendar: calendar)?.ideaId, open.id)
        // One with a stated rhythm waits that long after it last happened.
        let seasonal = try! XCTUnwrap(person.addIdea(kind: .visit, activity: "a long weekend together", cadenceDays: 180))
        person.recordFeedback(.done, ideaId: seasonal.id, at: now)
        XCTAssertFalse(person.opportunities(at: now, calendar: calendar).contains { $0.ideaId == seasonal.id })
        let all = person.opportunities(at: now, calendar: calendar, readyOnly: false)
        XCTAssertEqual(all.first { $0.ideaId == seasonal.id }?.ready, false)
        XCTAssertEqual(person.bestOpportunity(at: now, calendar: calendar)?.ideaId, open.id, "An idea waiting its turn is not offered.")
        XCTAssertTrue(person.hasReadyIdea(at: now, calendar: calendar))
        XCTAssertTrue(person.opportunities(at: calendar.date(byAdding: .day, value: 181, to: now)!, calendar: calendar).contains { $0.ideaId == seasonal.id })
    }

    func testGiveSpaceHasNoProactiveIdeasButStillAllowsAReply() {
        var person = person(intention: .space)
        _ = person.addIdea(activity: "a board game evening")
        let space = person.suggestion(at: now, calendar: calendar)
        XCTAssertEqual(space.action, .giveSpace)
        XCTAssertNil(space.opportunity)
        XCTAssertTrue(person.opportunities(at: now, calendar: calendar).isEmpty)
        person.recordContact(at: now, kind: .incoming)
        XCTAssertEqual(person.suggestion(at: now, calendar: calendar).action, .reply)
    }

    func testPausedSuppressesEverythingAndKeepsContext() {
        var person = person()
        person.addIdea(activity: "a board game evening")
        person.paused = true
        XCTAssertEqual(person.suggestion(at: now, calendar: calendar).action, .paused)
        XCTAssertTrue(person.opportunities(at: now, calendar: calendar).isEmpty)
        XCTAssertEqual(person.visibleIdeas.count, 1)
    }

    func testOpenOutreachStaysQuietUntilARecordedResponse() {
        var person = person(ready: true)
        person.recordContact(at: now.addingTimeInterval(-40 * 86400), kind: .outreach)
        person.recordContact(at: now.addingTimeInterval(-30 * 86400), kind: .incoming)
        person.recordContact(at: now.addingTimeInterval(-30 * 86400), kind: .reply)
        XCTAssertEqual(person.suggestion(at: now, calendar: calendar).action, .hello, "A reply resets the run, so a maintain relationship simply offers a small hello.")
        person.recordContact(at: now.addingTimeInterval(-20 * 86400), kind: .outreach)
        person.recordContact(at: now.addingTimeInterval(-10 * 86400), kind: .outreach)
        let room = person.suggestion(at: now, calendar: calendar)
        XCTAssertEqual(room.action, .later)
        XCTAssertFalse(room.ready)
        XCTAssertEqual(room.title, "You've reached out")
    }

    func testSettingAGenericSuggestionAsideIsRespected() {
        var person = person()
        XCTAssertEqual(person.suggestion(at: now, calendar: calendar).action, .hello)
        person.recordFeedback(.notForMe, action: .hello)
        let after = person.suggestion(at: now, calendar: calendar)
        XCTAssertEqual(after.action, .later)
        XCTAssertFalse(after.ready)
        XCTAssertFalse(after.reason.lowercased().contains("should"))
    }

    func testLegacyRecordsDecodeWithoutContextAndRoundTrip() throws {
        let id = UUID()
        let legacy: [String: Any] = ["id": id.uuidString, "name": "Example legacy", "circle": "Friend", "rhythmDays": 19, "method": "Message", "address": "", "context": "Private nuance", "createdAt": now.timeIntervalSinceReferenceDate, "contacts": [], "paused": false, "deferrals": 2]
        let person = try JSONDecoder().decode(Person.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertTrue(person.connection.isEmpty)
        XCTAssertTrue(person.feedback.isEmpty)
        XCTAssertEqual(person.deferrals, 2, "Existing data is preserved, even fields the app no longer uses.")
        XCTAssertEqual(try JSONDecoder().decode(Person.self, from: JSONEncoder().encode(person)), person)
    }

    func testSnoozeDoesNotAccumulateAsAFailureCount() {
        var person = person()
        person.snooze(until: now.addingTimeInterval(86400))
        person.snooze(until: now.addingTimeInterval(2 * 86400))
        person.snooze(until: now.addingTimeInterval(3 * 86400))
        XCTAssertEqual(person.deferrals, 0)
        XCTAssertFalse(person.isDue(at: now, calendar: calendar))
    }

    func testRitualsSurfaceReadyAndWaitOtherwise() {
        var person = Person(name: "Example person", rhythmDays: 14, createdAt: now.addingTimeInterval(-30 * 86400))
        person.intention = .maintain
        let ritual = try! XCTUnwrap(person.addRitual(title: "Thursday game night", note: "A standing invitation", days: 7))
        XCTAssertEqual(person.bestOpportunity(at: now, calendar: calendar)?.isRitual, true, "A newly recorded pattern can be offered straight away.")
        XCTAssertEqual(person.bestOpportunity(at: now, calendar: calendar)?.ideaId, ritual.id)
        person.recordFeedback(.done, ideaId: ritual.id, at: now)
        let soon = calendar.date(byAdding: .day, value: 3, to: now)!
        XCTAssertTrue(person.opportunities(at: soon, calendar: calendar).isEmpty)
        let later = calendar.date(byAdding: .day, value: 8, to: now)!
        XCTAssertTrue(person.opportunities(at: later, calendar: calendar).contains { $0.ideaId == ritual.id })
    }

    func testContextLimitsBoundStorageWithoutDroppingPendingIdeasFirst() {
        var person = person()
        for index in 0..<(Person.ideaLimit + 10) {
            person.addIdea(activity: "idea number \(index)")
        }
        XCTAssertEqual(person.ideas.count, Person.ideaLimit)
        XCTAssertTrue(person.ideas.allSatisfy { !$0.dismissed })
        // Dismissed entries are trimmed before anything still being considered.
        person.dismissIdea(person.ideas[0].id)
        person.addIdea(activity: "one more idea")
        XCTAssertEqual(person.ideas.count, Person.ideaLimit)
        XCTAssertFalse(person.ideas.contains { $0.id == person.ideas.first?.id && $0.dismissed })
    }

    func testFeedbackIsBounded() {
        var person = person()
        for _ in 0..<(Person.feedbackLimit + 20) { person.recordFeedback(.helpful) }
        XCTAssertEqual(person.feedback.count, Person.feedbackLimit)
    }
}
