import XCTest
@testable import SocialManagerCore

final class ConnectionLifecycleTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
    func example() -> Person {
        var person = Person(name: "Example friend", rhythmDays: 14, createdAt: now.addingTimeInterval(-60 * 86400))
        person.addInterest("Stardew Valley")
        person.addIdea(activity: "another evening of Stardew Valley", reminder: "Stardew Valley one evening?", reason: "You enjoyed playing together")
        return person
    }
    func testInvitationIsSuccessfulWithoutPretendingActivityHappened() throws {
        var person = example()
        let idea = try XCTUnwrap(person.suggestion(at: now, calendar: calendar).opportunity)
        let entry = person.recordContact(at: now, kind: .outreach, ideaId: idea.id)
        XCTAssertEqual(person.contacts.count, 1)
        XCTAssertEqual(person.contacts.first?.kind, .outreach)
        XCTAssertEqual(person.contacts.first?.ideaId, idea.id)
        XCTAssertTrue(person.feedback.isEmpty, "Sending an invitation is not doing the activity.")
        for days in [0, 15, 365] {
            let later = now.addingTimeInterval(Double(days * 86400))
            XCTAssertFalse(person.suggestion(at: later, calendar: calendar).ready)
            XCTAssertTrue(person.opportunities(at: later, calendar: calendar).isEmpty)
            XCTAssertTrue([person].suggestedPeople(at: later, calendar: calendar).isEmpty)
        }
        XCTAssertTrue(person.removeContact(entry))
        XCTAssertTrue(person.suggestion(at: now, calendar: calendar).ready)
    }
    func testAResponseReopensPossibilitiesWithoutInferringFeelings() {
        var person = example()
        person.recordContact(at: now.addingTimeInterval(-30 * 86400), kind: .outreach)
        person.recordContact(at: now.addingTimeInterval(-20 * 86400), kind: .incoming)
        XCTAssertEqual(person.suggestion(at: now, calendar: calendar).action, .reply)
        person.resolveIncoming(person.pendingIncoming[0].id, at: now)
        XCTAssertTrue(person.pendingOutreach.isEmpty)
        XCTAssertTrue(person.suggestion(at: now, calendar: calendar).ready)
    }
    func testExplicitlyLeavingInvitationHereDoesNotInventAReply() {
        var person = example()
        let entry = person.recordContact(at: now.addingTimeInterval(-20 * 86400), kind: .outreach)
        person.resolveOutreach(entry, at: now)
        XCTAssertTrue(person.pendingOutreach.isEmpty)
        XCTAssertEqual(person.contacts.count, 1)
        XCTAssertEqual(person.contacts[0].kind, .outreach)
        XCTAssertTrue(person.suggestion(at: now, calendar: calendar).ready)
    }
    func testPlanIsDistinctFromInvitationAndTimeTogether() throws {
        var person = example()
        let ideaId = person.ideas[0].id
        let plan = try XCTUnwrap(person.addPlan(title: "A shared game evening", date: now.addingTimeInterval(86400), ideaId: ideaId))
        XCTAssertTrue(person.contacts.isEmpty)
        XCTAssertNil(person.lastContact)
        XCTAssertFalse(person.suggestion(at: now, calendar: calendar).ready)
        XCTAssertFalse(person.suggestion(at: now.addingTimeInterval(30 * 86400), calendar: calendar).ready, "A past plan is not overdue work.")
        let entry = try XCTUnwrap(person.finishPlan(plan.id, at: now, now: now))
        XCTAssertEqual(person.contacts[0].kind, .conversation)
        XCTAssertEqual(person.contacts[0].ideaId, ideaId)
        XCTAssertTrue(person.activePlans.isEmpty)
        XCTAssertTrue(person.opportunities(at: now, calendar: calendar).isEmpty, "Doing an activity moves its clock, even without a cadence.")
        XCTAssertTrue(person.removeContact(entry))
        XCTAssertEqual(person.activePlans.map(\.id), [plan.id])
        person.cancelPlan(plan.id)
        XCTAssertTrue(person.contacts.isEmpty)
        XCTAssertTrue(person.suggestion(at: now, calendar: calendar).ready)
    }
    func testFutureContactCannotBeCreatedByFinishingPlan() throws {
        var person = example()
        let date = Date.now.addingTimeInterval(86400)
        let plan = try XCTUnwrap(person.addPlan(title: "A walk", date: date))
        XCTAssertNil(person.finishPlan(plan.id, at: date))
        XCTAssertTrue(person.contacts.isEmpty)
    }
    func testCorrectionAndUndoReopenOnlyAutomaticallyResolvedIncoming() throws {
        var person = example()
        let incoming = person.recordContact(at: now.addingTimeInterval(-3600), kind: .incoming)
        let reply = person.recordContact(at: now, kind: .reply)
        XCTAssertTrue(person.pendingIncoming.isEmpty)
        let original = try XCTUnwrap(person.contacts.first { $0.id == reply })
        XCTAssertTrue(person.correctContact(original, date: now, note: "In passing", kind: .ambient, initiator: .mutual))
        XCTAssertEqual(person.pendingIncoming.map(\.id), [incoming])
        XCTAssertFalse(person.correctContact(original, date: now, note: "Stale edit", kind: .reply, initiator: .them))
        person.resolveIncoming(incoming, at: now)
        let second = person.recordContact(at: now, kind: .reply)
        person.removeContact(second)
        XCTAssertTrue(person.pendingIncoming.isEmpty, "Explicit no-reply-needed survives undo.")
    }
    func testSnoozeAndSetAsideAreDifferentAndKeepDurableContext() {
        var person = example()
        let id = person.ideas[0].id
        person.snooze(until: now.addingTimeInterval(3 * 86400))
        person.recordFeedback(.snoozed, ideaId: id, at: now)
        XCTAssertTrue(person.opportunities(at: now, calendar: calendar).isEmpty)
        XCTAssertTrue(person.suggestion(at: now.addingTimeInterval(4 * 86400), calendar: calendar).ready)
        person.dismissIdea(id)
        person.recordFeedback(.notForMe, ideaId: id, at: now)
        XCTAssertFalse(person.suggestion(at: now.addingTimeInterval(40 * 86400), calendar: calendar).ready)
        XCTAssertFalse(person.interests.isEmpty)
        XCTAssertEqual(person.deferrals, 0)
    }
    func testLimitedContextAndGenericImportedIdeasDoNotManufactureWork() {
        var person = Person(name: "Example acquaintance", createdAt: now)
        person.chooseIntention(.grow); person.contexts = ["Nearby"]
        person.addIdea(activity: "Make time together", reason: "Nearby", source: .agent, confidence: .suggested)
        XCTAssertFalse(person.suggestion(at: now, calendar: calendar).ready)
        XCTAssertTrue(person.opportunities(at: now, calendar: calendar).isEmpty)
        XCTAssertFalse(person.suggestion(at: now, calendar: calendar).reason.contains("Nearby"))
        person.addIdea(activity: "an evening playing a game", source: .agent, confidence: .suggested)
        XCTAssertTrue(person.opportunities(at: now, calendar: calendar).isEmpty, "An unsupported agent activity stays in the editor, not Today.")
    }
    func testImportedRationaleIsNotAssertedAsKnownSharedHistory() {
        var person = Person(name: "Example person", createdAt: now)
        person.addIdea(activity: "a website work session", reason: "You both love website design", source: .agent, confidence: .suggested)
        let suggestion = person.suggestion(at: now, calendar: calendar)
        XCTAssertTrue(suggestion.ready)
        XCTAssertFalse(suggestion.reason.contains("both love"))
        XCTAssertEqual(suggestion.opportunity?.confidence, .suggested)
    }
    func testMaintainHasEqualStandingAndEmptyCollectionIsQuiet() {
        var maintain = example()
        var grow = example()
        maintain.name = "A maintained friendship"; grow.name = "Z growing friendship"
        maintain.chooseIntention(.maintain); grow.chooseIntention(.grow)
        XCTAssertTrue(maintain.suggestion(at: now, calendar: calendar).ready)
        XCTAssertEqual([grow, maintain].suggestedPeople(at: now, calendar: calendar).first?.id, maintain.id)
        XCTAssertTrue([Person]().suggestedPeople(at: now).isEmpty)
        maintain.chooseIntention(.space)
        XCTAssertTrue(maintain.opportunities(at: now).isEmpty)
    }
    func testPressureIsKeptOutOfAutomaticSuggestionsWithoutDeletingContext() {
        var person = example()
        person.connection.ideas = []
        person.addIdea(activity: "ask for a hug", reason: "Physical affection might help", source: .agent, confidence: .suggested)
        person.addIdea(activity: "keep messaging until they answer", reason: "Convince them to meet", source: .agent, confidence: .suggested)
        XCTAssertTrue(person.opportunities(at: now, calendar: calendar).isEmpty)
        XCTAssertEqual(person.visibleIdeas.count, 2, "The original import remains available for review.")
    }
    func testLegacyEventsAndNewFieldsDecodeWithoutRewritingUserData() throws {
        var person = example()
        person.recordContact(at: now, kind: .outreach)
        let encoded = try JSONEncoder().encode(person)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "plans")
        var contacts = try XCTUnwrap(object["contacts"] as? [[String: Any]])
        contacts[0].removeValue(forKey: "kind"); contacts[0].removeValue(forKey: "tracksResponse")
        contacts[0].removeValue(forKey: "ideaId"); contacts[0].removeValue(forKey: "responseEntryId")
        object["contacts"] = contacts
        let legacy = try JSONDecoder().decode(Person.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertTrue(legacy.plans.isEmpty)
        XCTAssertTrue(legacy.pendingOutreach.isEmpty, "Old undirected history does not prove an open invitation.")
        XCTAssertEqual(legacy.contacts.count, 1)
        XCTAssertTrue(legacy.suggestion(at: now.addingTimeInterval(30 * 86400), calendar: calendar).ready)
    }
    func testOnlyExplicitRestoreBringsAnIdeaBack() throws {
        var person = example()
        let id = person.ideas[0].id
        person.dismissIdea(id); person.recordFeedback(.notForMe, ideaId: id, at: now)
        person.updateIdea(id, reason: "An edited reason")
        XCTAssertTrue(person.opportunities(at: now, calendar: calendar).isEmpty, "Editing must not silently restore an idea.")
        XCTAssertTrue(person.restoreIdea(id))
        XCTAssertFalse(person.passedOnIdea(id))
        XCTAssertEqual(person.bestOpportunity(at: now, calendar: calendar)?.id, id)
    }
    func testCorrectingAPlanLogToAnInvitationRestoresPlan() throws {
        var person = example()
        let plan = try XCTUnwrap(person.addPlan(title: "Game night", date: now))
        let id = try XCTUnwrap(person.finishPlan(plan.id, at: now, now: now))
        let original = try XCTUnwrap(person.contacts.first { $0.id == id })
        XCTAssertTrue(person.correctContact(original, date: now, note: "It was only an invitation", kind: .outreach, initiator: .me))
        XCTAssertEqual(person.activePlans.map(\.id), [plan.id])
        XCTAssertEqual(person.pendingOutreach.map(\.id), [id])
    }
    func testEditingOnlyTheNoteKeepsAnExplicitResolution() throws {
        var person = example()
        let id = person.recordContact(at: now, kind: .incoming)
        person.resolveIncoming(id, at: now)
        let original = try XCTUnwrap(person.contacts.first { $0.id == id })
        XCTAssertTrue(person.correctContact(original, date: now, note: "Just sharing a photo", kind: .incoming, initiator: .them))
        XCTAssertTrue(person.pendingIncoming.isEmpty)
    }
    func testRitualSafetyAndExplicitRestore() throws {
        var person = example()
        person.connection.ideas = []
        person.connection.rituals.append(ConnectionRitual(title: "Ask for a hug", note: "Physical affection", sources: [.agent], confidence: .suggested))
        XCTAssertTrue(person.opportunities(at: now, calendar: calendar).isEmpty)
        let ritual = try XCTUnwrap(person.addRitual(title: "A shared game evening", days: 7))
        let index = try XCTUnwrap(person.connection.rituals.firstIndex { $0.id == ritual.id })
        person.connection.rituals[index].dismissed = true
        person.recordFeedback(.notForMe, ideaId: ritual.id, at: now)
        XCTAssertTrue(person.opportunities(at: now, calendar: calendar).isEmpty)
        XCTAssertTrue(person.restoreRitual(ritual.id))
        XCTAssertEqual(person.bestOpportunity(at: now, calendar: calendar)?.id, ritual.id)
    }
    func testNewFieldsRoundTripAndImportsPreserveLifecycle() throws {
        var person = example()
        person.recordContact(at: now, kind: .outreach, ideaId: person.ideas[0].id)
        person.addPlan(title: "Game night", date: now.addingTimeInterval(86400), ideaId: person.ideas[0].id)
        let data = try JSONEncoder().encode(person)
        XCTAssertEqual(try JSONDecoder().decode(Person.self, from: data), person)
        let json = """
        {"version":2,"source":"chatgpt","people":[{"id":"\(person.id)","name":"Example friend","notes":"New context"}]}
        """
        let batch = try AgentImportBatch.parse(Data(json.utf8))
        let merged = try AgentImportPlan.make(batch: batch, existing: [person]).changes[0].person
        XCTAssertEqual(merged.contacts, person.contacts)
        XCTAssertEqual(merged.plans, person.plans)
        XCTAssertFalse(merged.suggestion(at: now, calendar: calendar).ready)
    }
}
