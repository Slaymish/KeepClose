import XCTest
@testable import SocialManagerCore

final class AgentImportTests: XCTestCase {
    private func batch(_ people: [[String: Any]], source: String = "chatgpt") throws -> AgentImportBatch {
        try AgentImportBatch.parse(JSONSerialization.data(withJSONObject: ["version": 1, "source": source, "people": people]))
    }
    private func repository() throws -> RelationshipRepository {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return RelationshipRepository(directory: directory)
    }
    func testNewPersonDefaultsToUnsureWithoutFabricatingHistory() throws {
        let plan = try AgentImportPlan.make(batch: batch([["name": "Alex", "types": ["Friend", "Colleague"], "contexts": ["Work"], "notes": "Known from work"]]), existing: [])
        XCTAssertEqual(plan.added, 1)
        XCTAssertEqual(plan.changes[0].person.intention, .unsure)
        XCTAssertTrue(plan.changes[0].person.contacts.isEmpty)
        XCTAssertEqual(plan.changes[0].person.importSources, ["ChatGPT"])
    }
    func testMergeKeepsPreferencesHistoryAndIsIdempotent() throws {
        var person = Person(name: "Alex", rhythmDays: 9, address: "existing", context: "Original notes")
        person.intention = .space; person.paused = true; person.rhythmIsCustom = true
        person.recordContact(kind: .conversation)
        person.deferContact(until: .now.addingTimeInterval(86400))
        let imported = try batch([["name": " alex ", "types": ["friend", "Colleague"], "contexts": ["Work"], "notes": "Ask about the garden", "intention": "grow", "address": "different", "rhythmDays": 30]])
        let first = try AgentImportPlan.make(batch: imported, existing: [person])
        let merged = first.changes[0].person
        XCTAssertEqual(first.updated, 1)
        XCTAssertEqual(merged.id, person.id)
        XCTAssertEqual(merged.name, "Alex")
        XCTAssertEqual(merged.intention, .space)
        XCTAssertEqual(merged.rhythmDays, 9)
        XCTAssertEqual(merged.contacts, person.contacts)
        XCTAssertEqual(merged.snoozedUntil, person.snoozedUntil)
        XCTAssertEqual(merged.deferrals, person.deferrals)
        XCTAssertTrue(merged.paused)
        XCTAssertEqual(merged.address, "existing")
        XCTAssertEqual(merged.relationshipTypes, ["Friend", "Colleague"])
        XCTAssertTrue(merged.context.hasPrefix("Original notes"))
        let second = try AgentImportPlan.make(batch: imported, existing: [merged])
        XCTAssertEqual(second.unchanged, 1)
        XCTAssertEqual(second.changes[0].person, merged)
    }
    func testDuplicateNamesAndAmbiguousMatchesRequireResolution() throws {
        XCTAssertThrowsError(try batch([["name": "Alex"], ["name": " alex "]]))
        let existing = [Person(name: "Alex"), Person(name: "Alex")]
        XCTAssertThrowsError(try AgentImportPlan.make(batch: batch([["name": "Alex"]]), existing: existing))
        let byID = try AgentImportPlan.make(batch: batch([["id": existing[0].id.uuidString, "name": "Alex"]]), existing: existing)
        XCTAssertEqual(byID.changes[0].person.id, existing[0].id)
        XCTAssertThrowsError(try AgentImportPlan.make(batch: batch([["name": "Alex", "id": UUID().uuidString]]), existing: existing))
    }
    func testTwoRecordsCannotTargetOneExistingPerson() throws {
        let person = Person(name: "Alex")
        let imported = try batch([["id": person.id.uuidString, "name": "Alex"], ["name": "Alex"]])
        XCTAssertThrowsError(try AgentImportPlan.make(batch: imported, existing: [person]))
    }
    func testInvalidOrUnexpectedFieldsRejectedBeforeWriting() throws {
        XCTAssertThrowsError(try batch([["name": " "]]))
        XCTAssertThrowsError(try batch([["name": "Alex", "intention": "best friend"]]))
        XCTAssertThrowsError(try batch([["name": "Alex", "rhythmDays": 0]]))
        XCTAssertThrowsError(try batch([["name": "Alex", "contacts": []]]))
        XCTAssertThrowsError(try batch([["name": "Alex", "types": [""]]]))
    }
    func testPreviewDoesNotWriteAndApplyMakesExactBackup() throws {
        let repository = try repository()
        let original = Person(name: "Original")
        try repository.modifyPeople { $0.append(original) }
        let file = repository.directory.appendingPathComponent("relationships.json")
        let bytes = try Data(contentsOf: file)
        let imported = try batch([["name": "Alex"]])
        XCTAssertEqual(try repository.previewImport(imported).added, 1)
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        let result = try repository.applyImport(imported)
        XCTAssertEqual(result.added, 1)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: XCTUnwrap(result.backupPath))), bytes)
        XCTAssertEqual(try repository.people().count, 2)
        let repeated = try repository.applyImport(imported)
        XCTAssertEqual(repeated.unchanged, 1)
        XCTAssertNil(repeated.backupPath)
    }
    func testApplyIsAtomicAndRejectsStalePreview() throws {
        let repository = try repository()
        let original = Person(name: "Alex")
        try repository.modifyPeople { $0.append(original) }
        let snapshot = try repository.people()
        try repository.modifyPeople { $0[0].context = "Changed from CLI" }
        let imported = try batch([["name": "Alex", "notes": "More context"]])
        XCTAssertThrowsError(try repository.applyImport(imported, expected: snapshot))
        XCTAssertEqual(try repository.people()[0].context, "Changed from CLI")
        let ambiguous = try batch([["name": "New person"], ["name": "Missing ID", "id": UUID().uuidString]])
        XCTAssertThrowsError(try repository.applyImport(ambiguous))
        XCTAssertEqual(try repository.people().count, 1)
    }
    func testMarkdownJSONAndProviderSpecificPrompt() throws {
        let text = "```json\n{\"version\":1,\"source\":\"claude\",\"people\":[{\"name\":\"Alex\"}]}\n```"
        XCTAssertEqual(try AgentImportBatch.parse(Data(text.utf8)).source, .claude)
        let local = AgentImportPrompt.text(provider: .chatgpt, cliPath: "/tmp/keepclose")
        XCTAssertTrue(local.contains("/tmp/keepclose"))
        XCTAssertTrue(local.contains("--dry-run"))
        XCTAssertTrue(local.contains("--apply"))
        let fileOnly = AgentImportPrompt.text(provider: .claude)
        XCTAssertTrue(fileOnly.contains("keepclose-import.json"))
        XCTAssertFalse(fileOnly.contains("/tmp/keepclose"))
    }
}
