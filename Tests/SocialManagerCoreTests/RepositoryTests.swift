import XCTest
@testable import SocialManagerCore

final class RepositoryTests: XCTestCase {
    private func temporaryRepository() throws -> RelationshipRepository {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return RelationshipRepository(directory: directory)
    }
    func testIndependentWritersKeepBothChanges() throws {
        let first = try temporaryRepository()
        let second = RelationshipRepository(directory: first.directory)
        try first.modifyPeople { $0.append(Person(name: "A")) }
        try second.modifyPeople { $0.append(Person(name: "B")) }
        XCTAssertEqual(try first.people().map(\.name), ["A", "B"])
    }
    func testFailedTransactionDoesNotWrite() throws {
        let repository = try temporaryRepository()
        try repository.modifyPeople { $0.append(Person(name: "A")) }
        XCTAssertThrowsError(try repository.modifyPeople { people in
            people.removeAll()
            throw RepositoryError.conflict
        })
        XCTAssertEqual(try repository.people().count, 1)
    }
    func testCorruptDataIsPreserved() throws {
        let repository = try temporaryRepository()
        _ = try repository.people()
        let file = repository.directory.appendingPathComponent("relationships.json")
        let corrupt = Data("broken json".utf8)
        try corrupt.write(to: file)
        XCTAssertThrowsError(try repository.modifyPeople { $0.append(Person(name: "A")) })
        XCTAssertEqual(try Data(contentsOf: file), corrupt)
    }
    func testLegacyMigrationNeverReplacesSharedData() throws {
        let repository = try temporaryRepository()
        let legacy = repository.directory.appendingPathComponent("legacy.json")
        _ = try repository.people()
        try JSONEncoder().encode([Person(name: "Legacy")]).write(to: legacy)
        try repository.migrateLegacy(from: legacy)
        XCTAssertEqual(try repository.people().map(\.name), ["Legacy"])
        try repository.modifyPeople { $0[0].name = "Edited" }
        try repository.migrateLegacy(from: legacy)
        XCTAssertEqual(try repository.people().map(\.name), ["Edited"])
    }
    func testReminderSettingsPersistAndValidateTime() throws {
        let repository = try temporaryRepository()
        let saved = try repository.setReminder(enabled: true, hour: 9, minute: 30)
        XCTAssertEqual(try repository.preferences(), saved)
        XCTAssertThrowsError(try repository.setReminder(enabled: true, hour: 24, minute: 0))
        XCTAssertEqual(try repository.preferences(), saved)
    }
}
