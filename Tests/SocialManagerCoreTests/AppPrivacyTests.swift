import XCTest
@testable import SocialManagerCore

final class AppPrivacyTests: XCTestCase {
    func testEnabledLockStartsLockedAndRequiresSuccessfulAuthentication() {
        var session = AppLockSession(enabled: true)
        XCTAssertTrue(session.isLocked)
        let attempt = session.beginAuthentication()
        XCTAssertTrue(session.isLocked)
        XCTAssertTrue(session.authenticationSucceeded(.unlock, attempt: attempt))
        XCTAssertFalse(session.isLocked)
        session.lock()
        XCTAssertTrue(session.isLocked)
    }
    func testBackgroundingInvalidatesAuthenticationCompletion() {
        var session = AppLockSession(enabled: true)
        let attempt = session.beginAuthentication()
        session.lock()
        XCTAssertFalse(session.authenticationSucceeded(.unlock, attempt: attempt))
        XCTAssertTrue(session.isLocked)
    }
    func testOnlyFreshAuthenticationChangesLockPreference() {
        var session = AppLockSession(enabled: false)
        let stale = session.beginAuthentication()
        let current = session.beginAuthentication()
        XCTAssertFalse(session.authenticationSucceeded(.enable, attempt: stale))
        XCTAssertFalse(session.enabled)
        XCTAssertTrue(session.authenticationSucceeded(.enable, attempt: current))
        XCTAssertTrue(session.enabled)
        session.lock()
        XCTAssertFalse(session.authenticationSucceeded(.disable, attempt: current))
        XCTAssertTrue(session.enabled)
        let disable = session.beginAuthentication()
        XCTAssertTrue(session.authenticationSucceeded(.disable, attempt: disable))
        XCTAssertFalse(session.enabled)
        XCTAssertFalse(session.isLocked)
    }
    func testSuccessfulAuthenticationCannotBeReplayed() {
        var session = AppLockSession(enabled: true)
        let attempt = session.beginAuthentication()
        XCTAssertTrue(session.authenticationSucceeded(.unlock, attempt: attempt))
        XCTAssertFalse(session.authenticationSucceeded(.disable, attempt: attempt))
        XCTAssertTrue(session.enabled)
    }
    func testNamesOnlyIncludedWithWhenUnlockedPreviewPolicy() {
        let names = ["Alex", "Sam"]
        for policy: ReminderPreviewPolicy in [.always, .never, .unknown] {
            let text = PrivateReminderText.make(names: names, includeNames: true, policy: policy)
            XCTAssertFalse(text.body.contains("Alex"))
            XCTAssertFalse(text.body.contains("Sam"))
            XCTAssertTrue(text.body.contains("Someone"))
        }
        let unlocked = PrivateReminderText.make(names: names, includeNames: true, policy: .whenUnlocked)
        XCTAssertTrue(unlocked.body.contains("Alex, Sam"))
        XCTAssertFalse(PrivateReminderText.title.contains("Alex"))
        XCTAssertFalse(PrivateReminderText.hiddenBody.contains("Alex"))
    }
    func testDisablingNamesAndEmptySuggestionsRemainGeneric() {
        XCTAssertFalse(PrivateReminderText.make(names: ["Alex"], includeNames: false, policy: .whenUnlocked).body.contains("Alex"))
        XCTAssertTrue(PrivateReminderText.make(names: [], includeNames: true, policy: .whenUnlocked).body.contains("Someone"))
    }
    func testNamesAreBoundedAndControlCharactersRemoved() {
        let text = PrivateReminderText.make(names: ["Alex\n", "Sam", "Pat", "Hidden fourth"], includeNames: true, policy: .whenUnlocked)
        XCTAssertFalse(text.body.contains("\n"))
        XCTAssertFalse(text.body.contains("Hidden fourth"))
    }
    func testAppLockPersistsAcrossRepositoryInstancesAndMalformedSettingsThrow() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = RelationshipRepository(directory: directory)
        XCTAssertFalse(try first.appLockEnabled())
        try first.setAppLockEnabled(true)
        let second = RelationshipRepository(directory: directory)
        XCTAssertTrue(try second.appLockEnabled())
        try second.setAppLockEnabled(false)
        XCTAssertFalse(try first.appLockEnabled())
        try Data("broken".utf8).write(to: directory.appendingPathComponent("app-lock.json"))
        XCTAssertThrowsError(try second.appLockEnabled())
    }
    func testLegacyReminderSettingsDecodeAndPrivacyChoiceIsPreserved() throws {
        let json = "{\"revision\":\"00000000-0000-0000-0000-000000000000\",\"enabled\":true,\"hour\":18,\"minute\":0}"
        XCTAssertTrue(try JSONDecoder().decode(ReminderPreferences.self, from: Data(json.utf8)).includeNames)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = RelationshipRepository(directory: directory)
        _ = try repository.setReminder(enabled: true, hour: 18, minute: 0, includeNames: false)
        _ = try repository.setReminder(enabled: true, hour: 9, minute: 30)
        XCTAssertFalse(try repository.preferences().includeNames)
    }
}
