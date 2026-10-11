import Foundation
import Testing
import NativeSync
import NativeCore
@testable import SocialManagerCore

struct DeviceSyncTests {
    func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("FictionalSync-" + UUID().uuidString) }
    @Test func offlinePersonFieldsAndHistoryMergeAndDeviceLockDoesNotTravel() throws {
        let aURL = directory(), bURL = directory()
        defer { try? FileManager.default.removeItem(at: aURL); try? FileManager.default.removeItem(at: bURL) }
        let a = RelationshipRepository(directory: aURL), b = RelationshipRepository(directory: bURL), group = UUID()
        let person = Person(name: "Fictional Rowan")
        try a.modifyPeople { $0.append(person) }
        try a.setAppLockEnabled(true)
        let first = try a.joinSync(groupID: group)
        _ = try b.joinSync(groupID: group); _ = try b.exchangeSync(groupID: group, remote: first)
        #expect(try b.people() == [person])
        #expect(try !b.appLockEnabled())
        try a.modifyPeople {
            $0[0].name = "Fictional Rowan corrected"
            $0[0].contacts.append(ContactEntry(date: Date(timeIntervalSince1970: 1_800_000_000), note: "Fictional Mac conversation", kind: .conversation, initiator: .mutual))
        }
        try b.modifyPeople {
            $0[0].context = "Fictional phone note"
            $0[0].contacts.append(ContactEntry(date: Date(timeIntervalSince1970: 1_800_000_001), note: "Fictional phone reply", kind: .reply, initiator: .me))
        }
        let bState = try b.exchangeSync(groupID: group, remote: nil)
        let merged = try a.exchangeSync(groupID: group, remote: bState)
        _ = try b.exchangeSync(groupID: group, remote: merged)
        #expect(merged.conflicts.isEmpty)
        #expect(try a.people() == b.people())
        #expect(try a.people()[0].name == "Fictional Rowan corrected")
        #expect(try a.people()[0].context == "Fictional phone note")
        #expect(try a.people()[0].contacts.count == 2)
        #expect(try a.appLockEnabled())
        #expect(try !b.appLockEnabled())
        try a.modifyPeople { $0.removeAll() }
        let deleted = try a.exchangeSync(groupID: group, remote: nil)
        _ = try b.exchangeSync(groupID: group, remote: deleted)
        #expect(try b.people().isEmpty)
    }
    @Test func conflictsRequireReviewAndNormalEditsCannotEraseAlternatives() throws {
        let aURL = directory(), bURL = directory()
        defer { try? FileManager.default.removeItem(at: aURL); try? FileManager.default.removeItem(at: bURL) }
        let a = RelationshipRepository(directory: aURL), b = RelationshipRepository(directory: bURL), group = UUID()
        try a.modifyPeople { $0.append(Person(name: "Fictional Rowan")) }
        _ = try b.joinSync(groupID: group)
        _ = try b.exchangeSync(groupID: group, remote: a.joinSync(groupID: group))
        try a.modifyPeople { $0[0].context = "Mac note" }; try b.modifyPeople { $0[0].context = "Phone note" }
        let state = try a.exchangeSync(groupID: group, remote: b.exchangeSync(groupID: group, remote: nil))
        let conflict = try #require(state.conflicts.first)
        #expect(throws: SyncFailure.self) { try a.modifyPeople { $0[0].name = "Unreviewed edit" } }
        let choice = try #require(conflict.versions.first)
        let resolved = try a.resolveSync(record: conflict.id, versionID: choice.id)
        _ = try b.exchangeSync(groupID: group, remote: resolved)
        #expect(resolved.conflicts.isEmpty)
        #expect(try a.people() == b.people())
    }
    @Test func reminderRequestsAndAgentCheckpointsTravelButStatusRemainsLocal() throws {
        let aURL = directory(), bURL = directory()
        defer { try? FileManager.default.removeItem(at: aURL); try? FileManager.default.removeItem(at: bURL) }
        let a = RelationshipRepository(directory: aURL), b = RelationshipRepository(directory: bURL), group = UUID()
        _ = try a.setReminder(enabled: true, hour: 9, minute: 15, includeNames: false)
        try a.saveStatus(ReminderStatus(state: "scheduled", message: "Fictional status"))
        let batch = try AgentImportBatch.parse(Data(#"{"version":1,"source":"chatgpt","people":[]}"#.utf8))
        _ = try a.applyImport(batch)
        _ = try b.joinSync(groupID: group)
        _ = try b.exchangeSync(groupID: group, remote: a.joinSync(groupID: group))
        let prefs = try b.preferences()
        #expect(prefs.enabled && prefs.hour == 9 && !prefs.includeNames)
        #expect(try b.reminderStatus().state == "unknown")
        #expect(FileManager.default.fileExists(atPath: bURL.appendingPathComponent("agent-checkpoint-chatgpt.json").path))
        // Revision tokens are local scheduling signals, not conflicting user preferences.
        _ = try a.setReminder(enabled: true, hour: 10, minute: 15)
        _ = try b.setReminder(enabled: true, hour: 9, minute: 45)
        let state = try a.exchangeSync(groupID: group, remote: b.exchangeSync(groupID: group, remote: nil))
        let merged = try a.preferences()
        #expect(state.conflicts.isEmpty && merged.hour == 10 && merged.minute == 45)
    }
    @Test func pendingDeviceWriteRecoversBeforeAnotherCLIEdit() throws {
        let aURL = directory(), bURL = directory()
        defer { try? FileManager.default.removeItem(at: aURL); try? FileManager.default.removeItem(at: bURL) }
        let a = RelationshipRepository(directory: aURL), b = RelationshipRepository(directory: bURL), group = UUID()
        try a.modifyPeople { $0.append(Person(name: "Fictional Rowan")) }
        var pending = try a.joinSync(groupID: group)
        _ = try b.joinSync(groupID: group); _ = try b.exchangeSync(groupID: group, remote: pending)
        try b.modifyPeople { $0[0].context = "Incoming phone edit" }
        try pending.merge(b.exchangeSync(groupID: group, remote: nil))
        try NativeJSON.encode(pending).write(to: aURL.appendingPathComponent("device-sync.json.pending"))
        try a.modifyPeople { $0.append(Person(name: "Fictional CLI addition")) }
        let people = try a.people()
        #expect(people.count == 2 && people.contains { $0.context == "Incoming phone edit" })
        #expect(!FileManager.default.fileExists(atPath: aURL.appendingPathComponent("device-sync.json.pending").path))
    }
    @Test func unknownFuturePersonFieldsRejectWithoutChangingStoreOrJournal() throws {
        let aURL = directory(), bURL = directory()
        defer { try? FileManager.default.removeItem(at: aURL); try? FileManager.default.removeItem(at: bURL) }
        let a = RelationshipRepository(directory: aURL), b = RelationshipRepository(directory: bURL), group = UUID()
        try a.modifyPeople { $0.append(Person(name: "Fictional Rowan")) }
        let original = try a.joinSync(groupID: group)
        _ = try b.joinSync(groupID: group); _ = try b.exchangeSync(groupID: group, remote: original)
        var peer = try b.exchangeSync(groupID: group, remote: nil)
        var projected = peer.projection
        let key = try #require(projected.keys.first { $0.hasPrefix("person/") })
        var object = try JSONSerialization.jsonObject(with: projected[key]!) as! [String: Any]
        object["unsupportedFutureField"] = "must be retained, not silently dropped"
        projected[key] = try JSONSerialization.data(withJSONObject: object, options: .sortedKeys)
        try peer.reconcile(projected)
        let before = try Data(contentsOf: aURL.appendingPathComponent("relationships.json"))
        #expect(throws: SyncFailure.self) { try a.exchangeSync(groupID: group, remote: peer) }
        #expect(try Data(contentsOf: aURL.appendingPathComponent("relationships.json")) == before)
        #expect(!FileManager.default.fileExists(atPath: aURL.appendingPathComponent("device-sync.json.pending").path))
        #expect(try a.exchangeSync(groupID: group, remote: nil) == original)
    }

}
