import Foundation

import NativeSecurity

/// Compatibility name; the library models the UI gate, and this app owns OS authentication and privacy.
public typealias AppLockSession = AuthenticationGate

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
