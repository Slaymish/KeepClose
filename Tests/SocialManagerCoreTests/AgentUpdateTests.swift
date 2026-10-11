import XCTest
@testable import SocialManagerCore

final class AgentUpdateTests: XCTestCase {
    func testRoundTripCarriesRenameAndDoesNotUndoCorrection() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let repository = RelationshipRepository(directory: dir)
        let original = try AgentImportBatch.parse(Data(#"{"version":1,"source":"chatgpt","people":[{"name":"Example old spelling","notes":"Hiking friend"}]}"#.utf8))
        XCTAssertFalse(try repository.agentUpdateContext(.chatgpt).hasImported)
        _ = try repository.applyImport(original)
        let id = try XCTUnwrap(repository.people().first?.id)
        try repository.modifyPeople { $0[0].name = "Example corrected spelling"; $0[0].intention = .space }
        let context = try repository.agentUpdateContext(.chatgpt)
        XCTAssertTrue(context.hasImported)
        XCTAssertEqual(context.previous?.first?.name, "Example old spelling")
        XCTAssertEqual(context.current.first?.name, "Example corrected spelling")
        let prompt = AgentImportPrompt.text(provider: .chatgpt, context: context)
        XCTAssertTrue(prompt.contains("Example old spelling"))
        XCTAssertTrue(prompt.contains("Example corrected spelling"))
        XCTAssertTrue(prompt.contains(id.uuidString))
        let update = try AgentImportBatch.parse(JSONSerialization.data(withJSONObject: ["version":1,"source":"chatgpt","people":[["id":id.uuidString,"name":"Example old spelling","notes":"New context"]]]))
        _ = try repository.applyImport(update)
        let person = try XCTUnwrap(repository.people().first)
        XCTAssertEqual(person.name, "Example corrected spelling")
        XCTAssertEqual(person.intention, .space)
        XCTAssertTrue(person.context.contains("New context"))
        XCTAssertEqual(try repository.people().count, 1)
        XCTAssertEqual(try repository.agentUpdateContext(.chatgpt).previous?.first, person)
        XCTAssertFalse(try repository.agentUpdateContext(.claude).hasImported)
    }
    func testDeletedPeopleAndLegacyImportsAreExplainedWithoutChangingCheckpointOnCopy() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let repository = RelationshipRepository(directory: dir)
        var legacy = Person(name: "Example legacy")
        legacy.importSources = ["Claude"]
        try repository.modifyPeople { $0.append(legacy) }
        let initial = try repository.agentUpdateContext(.claude)
        XCTAssertTrue(initial.hasImported)
        XCTAssertNil(initial.previous)
        XCTAssertTrue(initial.instructions.contains("No historical checkpoint"))
        let empty = try AgentImportBatch.parse(Data(#"{"version":1,"source":"claude","people":[]}"#.utf8))
        _ = try repository.applyImport(empty)
        try repository.modifyPeople { $0.removeAll() }
        let context = try repository.agentUpdateContext(.claude)
        XCTAssertTrue(context.instructions.contains("Example legacy"))
        XCTAssertEqual(context.previous?.count, 1)
        _ = AgentImportPrompt.text(provider: .claude, context: context)
        XCTAssertEqual(try repository.agentUpdateContext(.claude).previous?.count, 1)
        _ = try repository.applyImport(empty)
        XCTAssertEqual(try repository.agentUpdateContext(.claude).previous?.count, 0)
        XCTAssertTrue(try repository.agentUpdateContext(.claude).hasImported)
    }
}
