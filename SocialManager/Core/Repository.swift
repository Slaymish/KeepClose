import Foundation
import NativeCore
import NativeSync

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
        // Retain the original unsandboxed Mac app/CLI path and iOS sandbox path.
        return try! AppDirectories.applicationSupportURL(appID: "KeepClose", realHomeOnMac: true)
    }
    private func locked<T>(_ operation: () throws -> T) throws -> T {
        try LocalFileLock.withExclusiveLock(at: directory.appendingPathComponent(".lock")) {
            try syncJournal.recover(apply: applySyncProjection)
            return try operation()
        }
    }
    private func read<T: Decodable>(_ name: String, fallback: T) throws -> T {
        let file = directory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: file.path) else { return fallback }
        return try NativeJSON.decode(T.self, from: Data(contentsOf: file), dates: .deferredToDate)
    }
    private func write<T: Encodable>(_ value: T, name: String) throws {
        let file = directory.appendingPathComponent(name)
        if Self.sharedFiles.values.contains(name) || name == "relationships.json" {
            var proposed = try syncProjection()
            if name == "relationships.json" {
                let people = try NativeJSON.decode([Person].self, from: NativeJSON.encode(value, dates: .deferredToDate), dates: .deferredToDate)
                proposed = proposed.filter { !$0.key.hasPrefix("person/") }
                for person in people { proposed["person/" + person.id.uuidString] = try syncEncode(person) }
            } else if let key = Self.sharedFiles.first(where: { $0.value == name })?.key {
                if key == "settings/reminder" {
                    var settings = try NativeJSON.decode(ReminderPreferences.self, from: NativeJSON.encode(value, dates: .deferredToDate), dates: .deferredToDate)
                    settings.revision = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
                    proposed[key] = try syncEncode(settings)
                } else { proposed[key] = try syncEncode(value) }
            }
            try syncJournal.validateEdit(proposed)
        }
        try AtomicFile.write(NativeJSON.encode(value, dates: .deferredToDate, formatting: [.prettyPrinted, .sortedKeys]), to: file)
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
            for change in plan.changes where change.action != "unchanged" {
                if let i = people.firstIndex(where: { $0.id == change.person.id }) { people[i] = change.person }
                else { people.append(change.person) }
            }
            var proposed = try syncProjection().filter { !$0.key.hasPrefix("person/") }
            for person in people { proposed["person/" + person.id.uuidString] = try syncEncode(person) }
            proposed["checkpoint/" + batch.source.rawValue] = try syncEncode(people)
            try syncJournal.validateEdit(proposed) // Preflight the whole import before changing people or its checkpoint.
            var backupPath: String?
            if plan.hasChanges {
                let originalFile = directory.appendingPathComponent("relationships.json")
                if FileManager.default.fileExists(atPath: originalFile.path) {
                    let backups = directory.appendingPathComponent("backups", isDirectory: true)
                    try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
                    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: backups.path)
                    let backup = backups.appendingPathComponent("before-import-\(UUID().uuidString).json")
                    try AtomicFile.write(Data(contentsOf: originalFile), to: backup)
                    backupPath = backup.path
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
            let people = try NativeJSON.decode([Person].self, from: Data(contentsOf: legacy), dates: .deferredToDate)
            try write(people, name: "relationships.json")
        }
    }
}


extension RelationshipRepository: LocalSyncRepository {
    public static let syncNamespace = "app.keepclose.records.v1"
    private static let sharedFiles = ["settings/reminder": "reminder.json",
        "checkpoint/chatgpt": "agent-checkpoint-chatgpt.json", "checkpoint/claude": "agent-checkpoint-claude.json"]
    private var syncJournal: SyncJournal { SyncJournal(url: directory.appendingPathComponent("device-sync.json"), namespace: Self.syncNamespace) }
    private func syncEncode<T: Encodable>(_ value: T) throws -> Data {
        try NativeJSON.encode(value, dates: .deferredToDate, formatting: .sortedKeys)
    }
    private func syncProjection() throws -> [String: Data] {
        let people: [Person] = try read("relationships.json", fallback: [])
        guard Set(people.map(\.id)).count == people.count else { throw SyncFailure.invalid }
        var result: [String: Data] = [:]
        for person in people { result["person/" + person.id.uuidString] = try syncEncode(person) }
        for (key, name) in Self.sharedFiles where FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path) {
            // Do not export implicit defaults from a new device.
            let bytes = try Data(contentsOf: directory.appendingPathComponent(name))
            if key == "settings/reminder" {
                var settings = try NativeJSON.decode(ReminderPreferences.self, from: bytes, dates: .deferredToDate)
                settings.revision = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
                result[key] = try syncEncode(settings)
            }
            else { result[key] = try syncEncode(NativeJSON.decode([Person].self, from: bytes, dates: .deferredToDate)) }
        }
        return result
    }
    private func validateSyncProjection(_ records: [String: Data]) throws {
        for (key, bytes) in records {
            if key.hasPrefix("person/") {
                let person = try syncDecode(Person.self, bytes)
                guard key == "person/" + person.id.uuidString else { throw SyncFailure.invalid }
            } else if key == "settings/reminder" {
                let settings = try syncDecode(ReminderPreferences.self, bytes)
                guard (0...23).contains(settings.hour), (0...59).contains(settings.minute) else { throw SyncFailure.invalid }
            } else if Self.sharedFiles[key] != nil {
                let people = try syncDecode([Person].self, bytes)
                guard Set(people.map(\.id)).count == people.count else { throw SyncFailure.invalid }
            } else { throw SyncFailure.invalid }
        }
    }
    /// Reject fields this app cannot preserve, rather than silently dropping data from a newer peer.
    private func syncDecode<T: Codable>(_ type: T.Type, _ bytes: Data) throws -> T {
        let value = try NativeJSON.decode(type, from: bytes, dates: .deferredToDate)
        func check(_ source: Any, _ encoded: Any) throws {
            if let a = source as? [String: Any], let b = encoded as? [String: Any] {
                guard Set(a.keys).isSubset(of: Set(b.keys)) else { throw SyncFailure.invalid }
                for (key, child) in a { if let other = b[key] { try check(child, other) } }
            } else if let a = source as? [Any], let b = encoded as? [Any] {
                guard a.count == b.count else { throw SyncFailure.invalid }
                for (child, other) in zip(a, b) { try check(child, other) }
            }
        }
        try check(JSONSerialization.jsonObject(with: bytes, options: .fragmentsAllowed),
                  JSONSerialization.jsonObject(with: syncEncode(value), options: .fragmentsAllowed))
        return value
    }
    private func applySyncProjection(_ records: [String: Data]) throws {
        try validateSyncProjection(records)
        let people = try records.filter { $0.key.hasPrefix("person/") }.sorted { $0.key < $1.key }
            .map { try syncDecode(Person.self, $0.value) }
        var files: [String: Data] = ["relationships.json": try NativeJSON.encode(people, dates: .deferredToDate, formatting: [.prettyPrinted, .sortedKeys])]
        for (key, name) in Self.sharedFiles {
            if key == "settings/reminder", let bytes = records[key] {
                var settings = try syncDecode(ReminderPreferences.self, bytes)
                let current: ReminderPreferences = try read(name, fallback: ReminderPreferences())
                let unchanged = settings.enabled == current.enabled && settings.hour == current.hour
                    && settings.minute == current.minute && settings.includeNames == current.includeNames
                settings.revision = unchanged ? current.revision : UUID()
                files[name] = try syncEncode(settings)
            } else { files[name] = records[key] }
        }
        for name in ["relationships.json"] + Array(Self.sharedFiles.values).sorted() {
            let file = directory.appendingPathComponent(name)
            let original = FileManager.default.fileExists(atPath: file.path) ? try Data(contentsOf: file) : nil
            let next = files[name]
            if let original, let next {
                // Ignore formatting differences: syncing an unchanged record must not create endless backups.
                let a = try JSONSerialization.jsonObject(with: original)
                let b = try JSONSerialization.jsonObject(with: next)
                if NSDictionary(dictionary: ["value": a]).isEqual(to: ["value": b]) { continue }
            } else if original == next { continue }
            if let original {
                let backups = directory.appendingPathComponent("backups", isDirectory: true)
                try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: backups.path)
                try AtomicFile.write(original, to: backups.appendingPathComponent("before-sync-\(UUID().uuidString)-\(name)"))
            }
            if let next { try AtomicFile.write(next, to: file) }
            else if original != nil { try FileManager.default.removeItem(at: file) }
        }
    }
    public func storedSync() throws -> SyncReplica? { try locked { try syncJournal.storedState(apply: applySyncProjection) } }
    public func joinSync(groupID: UUID) throws -> SyncReplica {
        try locked { try syncJournal.join(groupID: groupID, readCurrent: syncProjection, validate: validateSyncProjection, apply: applySyncProjection) }
    }
    public func exchangeSync(groupID: UUID, remote: SyncReplica?) throws -> SyncReplica {
        try locked {
            if let remote {
                try remote.validate()
                for (key, versions) in remote.records {
                    guard key.hasPrefix("person/") || Self.sharedFiles[key] != nil else { throw SyncFailure.invalid }
                    for version in versions {
                        if let bytes = version.payload { try validateSyncProjection([key: bytes]) }
                    }
                }
            }
            return try syncJournal.exchange(groupID: groupID, remote: remote, readCurrent: syncProjection, validate: validateSyncProjection, apply: applySyncProjection)
        }
    }
    public func resolveSync(record: String, versionID: UUID) throws -> SyncReplica {
        try locked { try syncJournal.resolve(record, versionID: versionID, readCurrent: syncProjection, validate: validateSyncProjection, apply: applySyncProjection) }
    }
}
