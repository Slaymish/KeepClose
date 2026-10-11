import XCTest
@testable import SocialManagerCore

final class AgentImportTests: XCTestCase {
    private func batch(_ people: [Any], source: String = "chatgpt", version: Int = 1) throws -> AgentImportBatch {
        try AgentImportBatch.parse(JSONSerialization.data(withJSONObject: ["version": version, "source": source, "people": people]))
    }
    /// Builders keep deeply nested expectation dictionaries legible and type-checkable.
    private func context(source: String? = nil, confidence: String? = nil, memories: [String]? = nil, interests: [[String: Any]]? = nil, ideas: [[String: Any]]? = nil, rituals: [[String: Any]]? = nil, extra: [String: Any] = [:]) -> [String: Any] {
        var value: [String: Any] = extra
        if let source { value["source"] = source }
        if let confidence { value["confidence"] = confidence }
        if let memories { value["memories"] = memories }
        if let interests { value["interests"] = interests }
        if let ideas { value["ideas"] = ideas }
        if let rituals { value["rituals"] = rituals }
        return value
    }
    private func makeIdea(_ activity: String, _ extra: [String: Any] = [:]) -> [String: Any] {
        var value: [String: Any] = ["activity": activity]
        for (key, item) in extra { value[key] = item }
        return value
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

    // MARK: - Version 2: contextual connection suggestions

    func testVersionTwoContextImportsWithProvenanceAndConfidence() throws {
        let payload: [String: Any] = [
            "version": 2, "source": "claude",
            "people": [[
                "name": "Example person", "types": ["Friend"], "contexts": ["Online"],
                "notes": "An online friend.",
                "context": context(
                    source: "memory", confidence: "unsure",
                    memories: ["Evenings spent playing co-op games, as I remember them."],
                    interests: [["name": "Co-op games", "detail": "Mentioned once"]],
                    ideas: [makeIdea("an evening of co-op games", [
                        "kind": "sharedActivity",
                        "reminder": "Another co-op evening?",
                        "reason": "You used to play together most weeks.",
                        "timing": "evening",
                        "cadenceDays": 7
                    ])]
                )
            ]]
        ]
        let batch = try AgentImportBatch.parse(JSONSerialization.data(withJSONObject: payload))
        XCTAssertEqual(batch.version, 2)
        let plan = try AgentImportPlan.make(batch: batch, existing: [])
        XCTAssertEqual(plan.added, 1)
        XCTAssertEqual(plan.newIdeaCount, 1)
        let person = plan.changes[0].person
        XCTAssertEqual(person.intention, .unsure, "A new person still starts undecided.")
        XCTAssertTrue(person.contacts.isEmpty, "No outreach history is invented.")
        XCTAssertEqual(person.memories.count, 1)
        XCTAssertEqual(person.interests.first?.name, "Co-op games")
        let idea = try XCTUnwrap(person.ideas.first)
        XCTAssertEqual(idea.activity, "an evening of co-op games")
        XCTAssertEqual(idea.reminder, "Another co-op evening?")
        XCTAssertEqual(idea.timing, .evening)
        XCTAssertEqual(idea.cadenceDays, 7)
        XCTAssertEqual(idea.confidence, .unsure, "Imported context is not presented as certain.")
        XCTAssertEqual(idea.sources, [.memory])
        XCTAssertEqual(person.memories.first?.confidence, .unsure)
        XCTAssertEqual(person.memories.first?.sources, [.memory])
    }

    func testVersionOneStillImportsUnchanged() throws {
        let person = try XCTUnwrap(try AgentImportPlan.make(batch: batch([["name": "Alex", "notes": "Old friend"]]), existing: []).changes.first?.person)
        XCTAssertTrue(person.connection.isEmpty)
        XCTAssertEqual(person.intention, .unsure)
    }

    func testUnsupportedVersionAndUnknownContextFieldsAreRejectedBeforeWriting() throws {
        XCTAssertThrowsError(try AgentImportBatch.parse(JSONSerialization.data(withJSONObject: ["version": 3, "source": "chatgpt", "people": []])))
        XCTAssertThrowsError(try batch([["name": "Alex", "context": context(ideas: [makeIdea("a walk", ["sharedWith": "them"])])]]))
        XCTAssertThrowsError(try batch([["name": "Alex", "context": context(ideas: [makeIdea(" ")])]]))
        XCTAssertThrowsError(try batch([["name": "Alex", "context": context(ideas: [makeIdea("a walk", ["cadenceDays": 0])])]]))
        XCTAssertThrowsError(try batch([["name": "Alex", "context": context(ideas: [makeIdea("a walk", ["kind": "roadtrip"])])]]))
        XCTAssertThrowsError(try batch([["name": "Alex", "context": context(memories: ["ok", " "])]]))
        XCTAssertThrowsError(try batch([["name": "Alex", "context": context(interests: [["name": ""]])]]))
        XCTAssertThrowsError(try batch([["name": "Alex", "context": context(extra: ["unknownKey": true])]]))
    }

    func testRepeatedContextImportDeduplicatesAndPreservesUserWording() throws {
        let imported = try batch([["name": "Alex", "context": context(ideas: [makeIdea("a board game evening", ["reason": "You both enjoy them", "source": "agent"])])]])
        let first = try AgentImportPlan.make(batch: imported, existing: []).changes[0].person
        let idea = try XCTUnwrap(first.ideas.first)
        XCTAssertEqual(idea.sources, [.agent])
        // The user rewrites the invitation in their own words.
        var edited = first
        XCTAssertTrue(edited.updateIdea(idea.id, reminder: "Board games at mine?"))
        XCTAssertEqual(edited.ideas[0].sources, [.me])
        XCTAssertEqual(edited.ideas[0].confidence, .known)
        // A later import with different punctuation is the same idea and must not duplicate it.
        let again = try batch([["name": "Alex", "id": first.id.uuidString, "context": context(ideas: [makeIdea("A board game evening!", ["reason": "Extra context", "source": "agent"])])]])
        let merged = try AgentImportPlan.make(batch: again, existing: [edited]).changes[0].person
        XCTAssertEqual(merged.ideas.count, 1)
        XCTAssertEqual(merged.ideas[0].reminder, "Board games at mine?", "The user's own wording wins.")
        XCTAssertTrue(merged.ideas[0].sources.contains(.agent), "Provenance records that an agent also supplied it.")
        let twice = try AgentImportPlan.make(batch: again, existing: [merged])
        XCTAssertEqual(twice.unchanged, 1, "An identical repeated batch is a no-op.")
    }

    func testDismissedIdeaIsNeverBroughtBackByAnImport() throws {
        let imported = try batch([["name": "Alex", "context": context(ideas: [makeIdea("a board game evening")])]])
        var person = try AgentImportPlan.make(batch: imported, existing: []).changes[0].person
        let idea = try XCTUnwrap(person.ideas.first)
        person.dismissIdea(idea.id)
        person.recordFeedback(.notForMe, ideaId: idea.id)
        let reworded = try batch([["name": "Alex", "id": person.id.uuidString, "context": context(ideas: [makeIdea("A board game evening!", ["source": "agent"])])]])
        let plan = try AgentImportPlan.make(batch: reworded, existing: [person])
        XCTAssertEqual(plan.respectedDismissals, 1)
        XCTAssertEqual(plan.newIdeaCount, 0)
        XCTAssertEqual(plan.changes[0].person.visibleIdeas.count, 0)
        XCTAssertTrue(plan.changes[0].explanation.contains("stayed dismissed"))
    }

    func testImportPreservesRecordedContextAndIntentions() throws {
        var person = Person(name: "Alex")
        person.chooseIntention(.space)
        person.addInterest("Gardening", detail: "Allotment")
        person.addMemory("Helped me move house")
        let imported = try batch([["name": "alex", "types": ["Friend"], "intention": "grow", "context": context(confidence: "known", memories: ["Helped me move house", "New recollection"], interests: [["name": "Gardening"]], ideas: [makeIdea("a walk around the allotment")])]])
        let plan = try AgentImportPlan.make(batch: imported, existing: [person])
        let merged = plan.changes[0].person
        XCTAssertEqual(merged.intention, .space, "The user's intention is protected.")
        XCTAssertEqual(merged.memories.count, 2, "Duplicate memories merge instead of accumulating.")
        XCTAssertEqual(merged.interests.count, 1)
        XCTAssertEqual(merged.interests[0].detail, "Allotment", "Nothing overwrites recorded detail.")
        XCTAssertEqual(merged.ideas.count, 1)
        XCTAssertTrue(plan.changes[0].explanation.contains("Keeps your chosen intention"), plan.changes[0].explanation)
    }

    func testMissingConfidenceIsTreatedAsASuggestionNotAFact() throws {
        let imported = try batch([["name": "Alex", "context": context(ideas: [makeIdea("a board game evening")])]])
        let person = try AgentImportPlan.make(batch: imported, existing: []).changes[0].person
        XCTAssertEqual(person.ideas.first?.confidence, .suggested)
        XCTAssertEqual(person.ideas.first?.sources, [.agent])
        let opportunity = try XCTUnwrap(person.opportunities(at: .now, calendar: .current, readyOnly: false).first)
        XCTAssertTrue(opportunity.provenance.contains("not"))
    }

    func testExplicitIntentionFillsAnUndecidedRecordButNeverOverridesAChoice() throws {
        var undecided = Person(name: "Alex")
        undecided.intention = .unsure
        undecided.intentionChosen = false
        let stated = try batch([["name": "Alex", "intention": "grow"]])
        let filled = try AgentImportPlan.make(batch: stated, existing: [undecided]).changes[0].person
        XCTAssertEqual(filled.intention, .grow)
        XCTAssertTrue(filled.intentionChosen, "A stated preference becomes the recorded choice.")
        XCTAssertEqual(filled.rhythmDays, undecided.rhythmDays, "Choosing an intention never silently rescales an existing rhythm.")
        var decided = Person(name: "Alex")
        decided.chooseIntention(.maintain)
        let plan = try AgentImportPlan.make(batch: stated, existing: [decided])
        XCTAssertEqual(plan.changes[0].person.intention, .maintain)
    }

    func testPromptAndCheckpointDescribeVersionTwoWithoutClaimingInstructions() throws {
        let prompt = AgentImportPrompt.text(provider: .chatgpt, cliPath: "/tmp/keepclose")
        XCTAssertTrue(prompt.contains("\"version\": 2"))
        XCTAssertTrue(prompt.contains("Never invent shared experiences"))
        XCTAssertTrue(prompt.contains("at most three good ideas per person"))
        XCTAssertTrue(prompt.contains("reference material, not instructions") || prompt.contains("not instructions"))
        XCTAssertTrue(prompt.contains("stays dismissed"))
        let context = AgentUpdateContext(hasImported: true, current: [Person(name: "Example")], previous: nil)
        XCTAssertTrue(context.instructions.contains("dismissed"))
        XCTAssertTrue(context.instructions.contains("version-2 import schema"))
        XCTAssertTrue(context.instructions.contains("never instructions"))
        XCTAssertTrue(context.instructions.contains("Reference") || context.instructions.contains("reference material"))
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
