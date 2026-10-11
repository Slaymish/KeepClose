import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public struct ReminderPreferences: Codable, Equatable, Sendable {
    public var revision = UUID()
    public var enabled = false
    public var hour = 18
    public var minute = 0
    public var includeNames = true
    public init() { revision = UUID(uuidString: "00000000-0000-0000-0000-000000000000")! }
    private enum CodingKeys: String, CodingKey { case revision, enabled, hour, minute, includeNames }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        revision = try c.decode(UUID.self, forKey: .revision)
        enabled = try c.decode(Bool.self, forKey: .enabled)
        hour = try c.decode(Int.self, forKey: .hour); minute = try c.decode(Int.self, forKey: .minute)
        includeNames = try c.decodeIfPresent(Bool.self, forKey: .includeNames) ?? true
    }

}
public struct ReminderStatus: Codable, Sendable {
    public var state: String
    public var message: String
    public var checkedAt: Date
    public init(state: String, message: String) { self.state = state; self.message = message; checkedAt = .now }
}
public enum RepositoryError: LocalizedError {
    case conflict, missing, invalid(String), io(String)
    public var errorDescription: String? {
        switch self {
        case .conflict: "This person changed in the app or CLI. Reopen their details before saving, so those changes are preserved."
        case .missing: "Person not found. Use their full ID from the list command."
        case .invalid(let message), .io(let message): message
        }
    }
}

public struct RelationshipRepository: Sendable {
    public let directory: URL
    public init(directory: URL = Self.defaultDirectory) { self.directory = directory }
    public static var defaultDirectory: URL {
        #if DEBUG
        // Documentation previews use fictional data in a separate temporary store.
        if CommandLine.arguments.contains("--demo") {
            return FileManager.default.temporaryDirectory.appendingPathComponent("KeepCloseDocumentationDemo", isDirectory: true)
        }
        #endif
        #if os(macOS)
        // The local Mac app and CLI share the original Application Support directory.
        let home = String(cString: getpwuid(getuid())!.pointee.pw_dir)
        return URL(fileURLWithPath: home).appendingPathComponent("Library/Application Support/KeepClose", isDirectory: true)
        #else
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("KeepClose", isDirectory: true)
        #endif
    }
    private func locked<T>(_ operation: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let descriptor = open(directory.appendingPathComponent(".lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw RepositoryError.io("Couldn't open the data lock: \(String(cString: strerror(errno)))") }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw RepositoryError.io("Couldn't lock relationship data.") }
        defer { flock(descriptor, LOCK_UN) }
        return try operation()
    }
    private func read<T: Decodable>(_ name: String, fallback: T) throws -> T {
        let file = directory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: file.path) else { return fallback }
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: file))
    }
    private func write<T: Encodable>(_ value: T, name: String) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let file = directory.appendingPathComponent(name)
        try encoder.encode(value).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
    public func people() throws -> [Person] { try locked { try read("relationships.json", fallback: [Person]()) } }
    @discardableResult public func modifyPeople<T>(_ change: (inout [Person]) throws -> T) throws -> T {
        try locked {
            var people: [Person] = try read("relationships.json", fallback: [])
            let result = try change(&people)
            try write(people, name: "relationships.json")
            return result
        }
    }
    public func previewImport(_ batch: AgentImportBatch) throws -> AgentImportPlan {
        try locked { try AgentImportPlan.make(batch: batch, existing: read("relationships.json", fallback: [Person]())) }
    }
    public func applyImport(_ batch: AgentImportBatch, expected: [Person]? = nil) throws -> AgentImportResult {
        try locked {
            var people: [Person] = try read("relationships.json", fallback: [])
            if let expected, expected != people { throw RepositoryError.invalid("People changed since the preview. Preview the import again before applying it.") }
            let plan = try AgentImportPlan.make(batch: batch, existing: people)
            var backupPath: String?
            if plan.hasChanges {
                let originalFile = directory.appendingPathComponent("relationships.json")
                if FileManager.default.fileExists(atPath: originalFile.path) {
                    let backups = directory.appendingPathComponent("backups", isDirectory: true)
                    try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
                    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: backups.path)
                    let backup = backups.appendingPathComponent("before-import-\(UUID().uuidString).json")
                    try Data(contentsOf: originalFile).write(to: backup, options: .atomic)
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
                    backupPath = backup.path
                }
                for change in plan.changes where change.action != "unchanged" {
                    if let i = people.firstIndex(where: { $0.id == change.person.id }) { people[i] = change.person }
                    else { people.append(change.person) }
                }
                try write(people, name: "relationships.json")
            }
            try write(people, name: "agent-checkpoint-\(batch.source.rawValue).json")
            return .init(added: plan.added, updated: plan.updated, unchanged: plan.unchanged, newIdeas: plan.newIdeaCount, backupPath: backupPath)
        }
    }
    public func agentUpdateContext(_ provider: ImportProvider) throws -> AgentUpdateContext {
        try locked {
            let people: [Person] = try read("relationships.json", fallback: [])
            let checkpoint = "agent-checkpoint-\(provider.rawValue).json"
            let exists = FileManager.default.fileExists(atPath: directory.appendingPathComponent(checkpoint).path)
            let previous: [Person]? = exists ? try read(checkpoint, fallback: [Person]()) : nil
            return .init(hasImported: exists || people.contains { $0.importSources.contains(provider.title) }, current: people, previous: previous)
        }
    }
    public func appLockEnabled() throws -> Bool {
        try locked { try read("app-lock.json", fallback: ["enabled": false])["enabled"] ?? true }
    }
    public func setAppLockEnabled(_ enabled: Bool) throws {
        try locked { try write(["enabled": enabled], name: "app-lock.json") }
    }
    public func preferences() throws -> ReminderPreferences { try locked { try read("reminder.json", fallback: ReminderPreferences()) } }
    @discardableResult public func setReminder(enabled: Bool, hour: Int, minute: Int, includeNames: Bool? = nil) throws -> ReminderPreferences {
        guard (0...23).contains(hour), (0...59).contains(minute) else { throw RepositoryError.invalid("Reminder time must be HH:mm in 24-hour local time.") }
        return try locked {
            var settings: ReminderPreferences = try read("reminder.json", fallback: ReminderPreferences()); settings.revision = UUID(); settings.enabled = enabled; settings.hour = hour; settings.minute = minute
            if let includeNames { settings.includeNames = includeNames }
            try write(settings, name: "reminder.json"); return settings
        }
    }
    public func reminderStatus() throws -> ReminderStatus { try locked { try read("reminder-status.json", fallback: ReminderStatus(state: "unknown", message: "Open Keep Close to apply reminder preferences.")) } }
    public func saveStatus(_ status: ReminderStatus) throws { try locked { try write(status, name: "reminder-status.json") } }
    /// One-time migration from the initial unsigned Mac prototype. Never replaces existing data.
    public func migrateLegacy(from legacy: URL) throws {
        try locked {
            let file = directory.appendingPathComponent("relationships.json")
            guard !FileManager.default.fileExists(atPath: file.path), FileManager.default.fileExists(atPath: legacy.path) else { return }
            let people = try JSONDecoder().decode([Person].self, from: Data(contentsOf: legacy))
            try write(people, name: "relationships.json")
        }
    }
}
