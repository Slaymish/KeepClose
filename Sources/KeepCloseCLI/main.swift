import Foundation
import SocialManagerCore
import AppKit

struct CLIError: LocalizedError { let message: String; var errorDescription: String? { message } }
struct Options {
    var values: [String: String] = [:]
    var positional: [String] = []
    init(_ args: [String]) throws {
        var i = 0
        while i < args.count {
            let arg = args[i]
            if arg.hasPrefix("--") {
                let key = String(arg.dropFirst(2))
                guard values[key] == nil else { throw CLIError(message: "Duplicate option --\(key)") }
                if ["yes", "launch", "apply", "dry-run"].contains(key) { values[key] = "true" }
                else {
                    i += 1
                    guard i < args.count, !args[i].hasPrefix("--") else { throw CLIError(message: "Missing value for --\(key)") }
                    values[key] = args[i]
                }
            } else { positional.append(arg) }
            i += 1
        }
    }
    func allow(_ keys: [String], positional count: Int) throws {
        let unknown = values.keys.filter { !keys.contains($0) && $0 != "data-dir" }
        guard unknown.isEmpty, positional.count == count else { throw CLIError(message: "Unexpected arguments: \(unknown.joined(separator: ", ")). Run keepclose help for usage.") }
    }
    func int(_ key: String, fallback: Int) throws -> Int {
        guard let value = values[key] else { return fallback }
        guard let number = Int(value) else { throw CLIError(message: "--\(key) must be an integer.") }; return number
    }
}
func emit<T: Encodable>(_ value: T) throws {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
    print(String(decoding: try encoder.encode(value), as: UTF8.self))
}
func date(_ value: String) throws -> Date {
    guard let date = ISO8601DateFormatter().date(from: value) else { throw CLIError(message: "Use an ISO 8601 timestamp with timezone, e.g. 2026-10-11T02:00:00Z.") }; return date
}
func identifier(_ value: String) throws -> UUID {
    guard let id = UUID(uuidString: value) else { throw CLIError(message: "Use a full person UUID from keepclose list.") }; return id
}
func index(_ id: UUID, in people: [Person]) throws -> Int {
    guard let i = people.firstIndex(where: { $0.id == id }) else { throw RepositoryError.missing }; return i
}
func apply(_ options: Options, to person: inout Person) throws {
    guard !(options.values["circle"] != nil && options.values["types"] != nil) else { throw CLIError(message: "Use --types or --circle, not both.") }
    if let name = options.values["name"] {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CLIError(message: "Name cannot be blank.") }
        person.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if let value = options.values["circle"] { person.circle = value; person.relationshipTypes = [value] }
    if let value = options.values["types"] { person.relationshipTypes = tags(value); person.circle = person.relationshipTypes.joined(separator: ", ") }
    if let value = options.values["contexts"] { person.contexts = tags(value) }
    if let value = options.values["intention"] {
        guard let intention = RelationshipIntention(rawValue: value) else { throw CLIError(message: "Intention must be grow, maintain, space or unsure.") }; person.intention = intention
    }
    if let value = options.values["notes"] {
        guard options.values["context"] == nil else { throw CLIError(message: "Use --notes or --context, not both.") }; person.context = value
    }
    if let value = options.values["context"] { person.context = value }
    if let value = options.values["address"] { person.address = value.trimmingCharacters(in: .whitespacesAndNewlines) }
    if options.values["days"] != nil {
        let days = try options.int("days", fallback: 14)
        guard (1...365).contains(days) else { throw CLIError(message: "--days must be between 1 and 365.") }; person.rhythmDays = days; person.rhythmIsCustom = true
    }
    if let rhythm = options.values["rhythm"] {
        guard rhythm == "auto" || rhythm == "custom" else { throw CLIError(message: "--rhythm must be auto or custom.") }
        guard !(rhythm == "auto" && options.values["days"] != nil) else { throw CLIError(message: "Choose --rhythm auto or --days, not both.") }
        person.rhythmIsCustom = rhythm == "custom"
    }
    if !person.rhythmIsCustom { person.applySuggestedRhythm() }
    if let value = options.values["method"] {
        let methods: [String: ContactMethod] = ["message": .message, "call": .call, "email": .email, "in-person": .inPerson]
        guard let method = methods[value] else { throw CLIError(message: "Method must be message, call, email or in-person.") }; person.method = method
    }
}
func tags(_ value: String) -> [String] {
    var seen = Set<String>()
    return value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
}
func launchArguments() -> [String] {
    // Prefer this project's fully signed build when multiple development builds are registered.
    var folder = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.resolvingSymlinksInPath().deletingLastPathComponent()
    while folder.path != "/" {
        let app = folder.appendingPathComponent(".build-xcode/Build/Products/Debug/SocialManager.app")
        if FileManager.default.fileExists(atPath: folder.appendingPathComponent("SocialManager.xcodeproj").path), FileManager.default.fileExists(atPath: app.path) { return [app.path] }
        folder.deleteLastPathComponent()
    }
    return ["-b", "app.keepclose.KeepClose"]
}
struct Advice: Encodable { let person: Person; let suggestion: RelationshipSuggestion }
let help = """
Keep Close — agent-friendly CLI. Results are JSON; errors go to stderr with exit code 1.

keepclose list                         All people, including notes and history
keepclose due                          All people ready today (uncapped)
keepclose show ID                      One person's details
keepclose suggest ID                   Person and explained next action
keepclose suggestions                  All ready actions, with reasons
keepclose add --name NAME [fields]      Add a person
keepclose update ID [fields]            Change only supplied fields
keepclose log ID [--kind KIND] [--initiator WHO] [--at ISO8601] [--note TEXT]
keepclose resolve ID --entry ENTRY_UUID Mark an incoming message as needing no reply
keepclose snooze ID --days N            Postpone from today (1–365 days)
keepclose pause ID                      Pause check-ins
keepclose resume ID                     Resume the existing rhythm
keepclose delete ID --yes               Delete person and history
keepclose open ID                       Open preferred contact app; does not log contact
keepclose reminders                    Requested schedule and last app-reported status
keepclose reminders on [--time HH:mm] [--names when-unlocked|never] [--launch]
keepclose reminders off [--launch]
keepclose import FILE [--dry-run]       Preview an agent JSON import (default)
keepclose import FILE --apply           Atomically import; backs up existing data
keepclose import-prompt --source chatgpt|claude
keepclose path                         Shared data directory

Fields: --name, --types 'Friend,Colleague', --contexts 'Work,Online',
        --intention (grow/maintain/space/unsure), --rhythm (auto/custom), --days (1–365),
        --method (message/call/email/in-person), --address, --notes.
Aliases: --circle sets one relationship label; --context is a notes field.
Contact kinds: outreach (default), incoming, conversation, reply, ambient.
--initiator (me/them/mutual/unknown) is for conversation logs.
Incoming contact prompts a reply; reply/conversation closes older incoming messages.
Everyday/ambient contact doesn't restart the connection rhythm. Use an empty quoted value to clear a text field.
Global: --data-dir PATH isolates a dataset (use for tests).
IDs are full UUIDs. Dates in output use ISO 8601; storage format is internal.
Reminder changes are applied by the app when running; --launch opens it.
Notification permission must be granted in the app. CLI cannot bypass it.
"""
do {
    let args = Array(CommandLine.arguments.dropFirst())
    let command = args.first ?? "help"
    if command == "help" || command == "--help" { print(help); exit(0) }
    let options = try Options(Array(args.dropFirst()))
    let repository = RelationshipRepository(directory: options.values["data-dir"].map { URL(fileURLWithPath: $0, isDirectory: true) } ?? RelationshipRepository.defaultDirectory)
    let fields = ["name", "circle", "types", "contexts", "intention", "rhythm", "days", "method", "address", "context", "notes"]
    switch command {
    case "import-prompt":
        try options.allow(["source"], positional: 0)
        guard let source = options.values["source"].flatMap(ImportProvider.init(rawValue:)) else { throw CLIError(message: "Use --source chatgpt or claude.") }
        var folder = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.resolvingSymlinksInPath().deletingLastPathComponent()
        var cli: String?
        while folder.path != "/" {
            let script = folder.appendingPathComponent("scripts/keepclose")
            if FileManager.default.fileExists(atPath: script.path) { cli = script.path; break }
            folder.deleteLastPathComponent()
        }
        try emit(["source": source.rawValue, "prompt": AgentImportPrompt.text(provider: source, cliPath: cli ?? CommandLine.arguments[0], context: try repository.agentUpdateContext(source))])
    case "import":
        try options.allow(["apply", "dry-run"], positional: 1)
        guard !(options.values["apply"] != nil && options.values["dry-run"] != nil) else { throw CLIError(message: "Choose --apply or --dry-run, not both.") }
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: options.positional[0]))
        defer { try? handle.close() }
        let batch = try AgentImportBatch.parse(handle.read(upToCount: 2_000_001) ?? Data())
        if options.values["apply"] != nil { try emit(repository.applyImport(batch)) }
        else {
            let plan = try repository.previewImport(batch)
            struct Preview: Encodable { let dryRun: Bool; let added: Int; let updated: Int; let unchanged: Int; let changes: [AgentImportChange] }
            try emit(Preview(dryRun: true, added: plan.added, updated: plan.updated, unchanged: plan.unchanged, changes: plan.changes))
        }
    case "path": try options.allow([], positional: 0); try emit(["directory": repository.directory.path])
    case "list", "due", "suggestions":
        try options.allow([], positional: 0)
        let people = try repository.people()
        if command == "suggestions" { try emit(people.suggestedPeople().map { Advice(person: $0, suggestion: $0.suggestion()) }) }
        else { try emit(command == "due" ? people.suggestedPeople() : people) }
    case "show", "suggest":
        try options.allow([], positional: 1); let id = try identifier(options.positional[0]); let people = try repository.people(); let person = people[try index(id, in: people)]; if command == "suggest" { try emit(Advice(person: person, suggestion: person.suggestion())) } else { try emit(person) }
    case "add":
        try options.allow(fields, positional: 0)
        guard options.values["name"] != nil else { throw CLIError(message: "add requires --name.") }
        var person = Person(name: ""); try apply(options, to: &person)
        try repository.modifyPeople { $0.append(person) }; try emit(person)
    case "update", "log", "snooze", "pause", "resume", "delete", "resolve":
        let allowed = command == "update" ? fields : command == "log" ? ["at", "note", "kind", "initiator"] : command == "resolve" ? ["entry"] : command == "snooze" ? ["days"] : command == "delete" ? ["yes"] : []
        try options.allow(allowed, positional: 1)
        let id = try identifier(options.positional[0])
        let result = try repository.modifyPeople { people -> Person in
            let i = try index(id, in: people)
            switch command {
            case "update":
                guard !options.values.filter({ $0.key != "data-dir" }).isEmpty else { throw CLIError(message: "Specify at least one field to update.") }
                try apply(options, to: &people[i])
            case "log":
                let at = try options.values["at"].map(date) ?? .now
                guard at <= .now else { throw CLIError(message: "Contact dates cannot be in the future.") }
                guard let kind = ContactKind(rawValue: options.values["kind"] ?? "outreach") else { throw CLIError(message: "Unknown contact kind. Run keepclose help.") }
                var initiator: Initiator?
                if let value = options.values["initiator"] {
                    guard kind == .conversation, let parsed = Initiator(rawValue: value) else { throw CLIError(message: "--initiator is me/them/mutual/unknown and only applies to conversation logs.") }; initiator = parsed
                }
                people[i].recordContact(at: at, note: options.values["note"] ?? "", kind: kind, initiator: initiator)
            case "resolve":
                guard let value = options.values["entry"] else { throw CLIError(message: "resolve requires --entry ENTRY_UUID.") }
                let entry = try identifier(value)
                guard people[i].contacts.contains(where: { $0.id == entry && $0.kind == .incoming }) else { throw CLIError(message: "Incoming entry not found for this person.") }
                people[i].resolveIncoming(entry)
            case "snooze":
                guard options.values["days"] != nil else { throw CLIError(message: "snooze requires --days.") }
                let days = try options.int("days", fallback: 1)
                guard (1...365).contains(days) else { throw CLIError(message: "--days must be between 1 and 365.") }
                people[i].deferContact(until: Calendar.current.date(byAdding: .day, value: days, to: .now)!)
            case "pause": people[i].paused = true
            case "resume": people[i].paused = false
            case "delete": guard options.values["yes"] != nil else { throw CLIError(message: "Deletion requires --yes and has no undo.") }
            default: break
            }
            let result = people[i]
            if command == "delete" { people.remove(at: i) }; return result
        }
        try emit(result)
    case "open":
        try options.allow([], positional: 1); let people = try repository.people(); let person = people[try index(identifier(options.positional[0]), in: people)]
        guard person.method != .inPerson, !person.address.isEmpty else { throw CLIError(message: "This person has no contact app or address configured.") }
        let scheme = person.method == .email ? "mailto" : person.method == .call ? "tel" : "sms"
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "?#&"))
        guard let address = person.address.addingPercentEncoding(withAllowedCharacters: allowed), let url = URL(string: "\(scheme):\(address)"), NSWorkspace.shared.open(url) else { throw CLIError(message: "Couldn't open the preferred contact app.") }
        try emit(["opened": true, "contactLogged": false])
    case "reminders":
        try options.allow(["time", "names", "launch"], positional: options.positional.isEmpty ? 0 : 1)
        if let action = options.positional.first {
            guard ["on", "off"].contains(action) else { throw CLIError(message: "Use reminders, reminders on, or reminders off.") }
            let previous = try repository.preferences()
            let time = options.values["time"] ?? String(format: "%02d:%02d", previous.hour, previous.minute)
            let parts = time.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { throw CLIError(message: "Use --time HH:mm.") }
            let names: Bool?
            if let value = options.values["names"] {
                guard value == "when-unlocked" || value == "never" else { throw CLIError(message: "--names must be when-unlocked or never.") }; names = value == "when-unlocked"
            } else { names = nil }
            _ = try repository.setReminder(enabled: action == "on", hour: hour, minute: minute, includeNames: names)
            try repository.saveStatus(ReminderStatus(state: "pending", message: "Open Keep Close to apply this requested schedule."))
            if options.values["launch"] != nil {
                guard options.values["data-dir"] == nil else { throw CLIError(message: "Schedule saved to the isolated dataset. --launch only works with the default app dataset.") }
                let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/open"); process.arguments = launchArguments(); try process.run(); process.waitUntilExit()
                guard process.terminationStatus == 0 else { throw CLIError(message: "Schedule saved, but couldn't launch Keep Close. Open the built app manually.") }
            }
        } else if options.values["time"] != nil || options.values["names"] != nil || options.values["launch"] != nil { throw CLIError(message: "Use reminders on/off to change the schedule.") }
        struct Output: Encodable { let requested: ReminderPreferences; let actual: ReminderStatus }
        try emit(Output(requested: repository.preferences(), actual: repository.reminderStatus()))
    case "migrate-legacy":
        try options.allow(["file"], positional: 0)
        guard let path = options.values["file"] else { throw CLIError(message: "Supply --file PATH for the legacy relationships JSON. Existing data is never replaced.") }
        let legacy = URL(fileURLWithPath: path)
        try repository.migrateLegacy(from: legacy); try emit(["migratedOrAlreadyPresent": true])
    default: throw CLIError(message: "Unknown command \(command). Run keepclose help.")
    }
} catch {
    let message = "keepclose: \(error.localizedDescription)\n"
    FileHandle.standardError.write(Data(message.utf8)); exit(1)
}
