import Foundation

/// Models the UI lock only. Relationship storage remains available to the local CLI.
public struct AppLockSession: Sendable {
    public enum Intent: Sendable { case unlock, enable, disable }
    public private(set) var enabled: Bool
    public private(set) var unlocked = false
    private var generation: UInt64 = 0
    public init(enabled: Bool) { self.enabled = enabled }
    public var isLocked: Bool { enabled && !unlocked }
    public mutating func beginAuthentication() -> UInt64 { generation &+= 1; return generation }
    @discardableResult public mutating func authenticationSucceeded(_ intent: Intent, attempt: UInt64) -> Bool {
        guard attempt == generation else { return false }
        switch intent {
        case .enable: enabled = true; unlocked = true
        case .disable: enabled = false; unlocked = false
        case .unlock: guard enabled else { return false }; unlocked = true
        }
        generation &+= 1 // A successful authentication result can be consumed only once.
        return true
    }
    public mutating func lock() { generation &+= 1; unlocked = false }
}

public enum ReminderPreviewPolicy: Sendable { case whenUnlocked, always, never, unknown }
public struct PrivateReminderText: Equatable, Sendable {
    public static let title = "A small moment to connect"
    public static let hiddenBody = "Someone is ready for a little connection."
    public var body: String
    public static func make(names: [String], includeNames: Bool, policy: ReminderPreviewPolicy) -> Self {
        guard includeNames, policy == .whenUnlocked, !names.isEmpty else { return .init(body: hiddenBody + " Open Keep Close to choose a next step.") }
        // Limit length and remove control characters from user-supplied names.
        let safe = names.prefix(3).map { String($0.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.map(String.init).joined().prefix(80)) }.filter { !$0.isEmpty }
        guard !safe.isEmpty else { return .init(body: hiddenBody) }
        return .init(body: "A little connection with \(safe.joined(separator: ", "))? Open Keep Close for your next step.")
    }
}
