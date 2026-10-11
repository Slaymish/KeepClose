import Foundation
import SocialManagerCore
import NativeCore
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
                // Subcommand flags take no value; everything else expects one.
                if ["yes", "launch", "apply", "dry-run", "add", "edit", "dismiss", "restore", "remove", "forget"].contains(key) { values[key] = "true" }
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
    func list(_ key: String) -> [String]? {
        guard let value = values[key] else { return nil }
        return value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
    func flag(_ key: String) -> Bool { values[key] != nil }
    /// Exactly one of the named subcommand flags, so a command can never half-apply.
    func subcommand(_ keys: [String]) throws -> String {
        let chosen = keys.filter { values[$0] != nil }
        guard chosen.count == 1, let name = chosen.first else {
            throw CLIError(message: "Use one of \(keys.map { "--\($0)" }.joined(separator: ", ")).")
        }
        return name
    }
}
func emit<T: Encodable>(_ value: T) throws {
    print(String(decoding: try NativeJSON.encode(value, formatting: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
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
        guard let intention = RelationshipIntention(rawValue: value) else { throw CLIError(message: "Intention must be grow, maintain, space or unsure.") }; person.chooseIntention(intention)
    }
    if let value = options.values["notes"] {
        guard options.values["context"] == nil else { throw CLIError(message: "Use --notes or --context, not both.") }; person.context = value
    }
    if let value = options.values["context"] { person.context = value }
    if let value = options.values["address"] { person.address = value.trimmingCharacters(in: .whitespacesAndNewlines) }
    if let value = options.values["birthday"] {
        if value == "none" { person.birthday = nil }
        else {
            let parts = value.split(separator: "-", omittingEmptySubsequences: false).compactMap { Int($0) }
            guard parts.count == value.split(separator: "-", omittingEmptySubsequences: false).count, [2, 3].contains(parts.count) else { throw CLIError(message: "Birthday must be MM-DD, YYYY-MM-DD or none.") }
            person.birthday = try Birthday(month: parts[parts.count - 2], day: parts[parts.count - 1], year: parts.count == 3 ? parts[0] : nil)
        }
    }
    if let value = options.values["birthday-reminder"] {
        guard ["on", "off"].contains(value) else { throw CLIError(message: "Birthday reminder must be on or off.") }; person.birthdayReminder = value == "on"
    }
    if let value = options.values["gift-reminder"] {
        guard let reminder = GiftReminder(rawValue: value) else { throw CLIError(message: "Gift reminder must be automatic, on or off.") }; person.giftReminder = reminder
    }
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
func parseDate(_ value: String, label: String) throws -> Date {
    guard let date = ISO8601DateFormatter().date(from: value) else { throw CLIError(message: "Use an ISO 8601 date for \(label), e.g. 2026-03-01T00:00:00Z.") }
    return date
}
func choose<T: RawRepresentable>(_ value: String?, _ options: [T], label: String) throws -> T? where T.RawValue == String {
    guard let value else { return nil }
    guard let match = options.first(where: { $0.rawValue == value }) else {
        throw CLIError(message: "\(label) must be one of \(options.map(\.rawValue).joined(separator: ", ")).")
    }
    return match
}
func uid(_ value: String?, label: String) throws -> UUID {
    guard let value, let id = UUID(uuidString: value) else { throw CLIError(message: "Supply a full \(label) UUID.") }
    return id
}
func applyContextCommand(_ command: String, options: Options, to person: inout Person) throws {
    switch command {
    case "idea":
        let action = try options.subcommand(["add", "edit", "dismiss", "restore", "remove"])
        switch action {
        case "add":
            guard let activity = options.values["activity"] else { throw CLIError(message: "idea add requires --activity.") }
            let kind = try choose(options.values["kind"], IdeaKind.allCases, label: "kind") ?? .sharedActivity
            let timing = try choose(options.values["timing"], IdeaTiming.allCases, label: "timing")
            let source = try choose(options.values["source"], IdeaSource.allCases, label: "source") ?? .me
            let confidence = try choose(options.values["confidence"], KnowledgeConfidence.allCases, label: "confidence") ?? .known
            var cadence: Int?
            if let value = options.values["cadence"] {
                guard let days = Int(value), (1...365).contains(days) else { throw CLIError(message: "--cadence must be between 1 and 365 days.") }
                cadence = days
            }
            guard person.addIdea(kind: kind, activity: activity, reminder: options.values["reminder"] ?? "", reason: options.values["reason"] ?? "", timing: timing, occasions: options.list("occasions") ?? [], cadenceDays: cadence, source: source, confidence: confidence) != nil else {
                throw CLIError(message: "That way of connecting is empty or is already recorded for this person.")
            }
        case "edit":
            let id = try uid(options.values["idea"], label: "--idea")
            var timing: IdeaTiming?? = .none
            if options.flag("timing") || options.values["timing"] != nil { timing = .some(try choose(options.values["timing"], IdeaTiming.allCases, label: "timing")) }
            var cadence: Int?? = .none
            if let value = options.values["cadence"] {
                if value == "none" { cadence = .some(nil) } else {
                    guard let days = Int(value), (1...365).contains(days) else { throw CLIError(message: "--cadence must be between 1 and 365 days, or none.") }
                    cadence = .some(days)
                }
            }
            let kind = try choose(options.values["kind"], IdeaKind.allCases, label: "kind")
            guard person.updateIdea(id, activity: options.values["activity"], reminder: options.values["reminder"], reason: options.values["reason"], kind: kind, timing: timing, cadenceDays: cadence, occasions: options.list("occasions")) else {
                throw CLIError(message: "No recorded idea has that ID.")
            }
        case "dismiss", "restore", "remove":
            let id = try uid(options.values["idea"], label: "--idea")
            let changed: Bool
            switch action {
            case "dismiss":
                changed = person.dismissIdea(id)
                if changed { person.recordFeedback(.notForMe, ideaId: id) }
            case "restore": changed = person.restoreIdea(id)
            default: changed = person.removeIdea(id)
            }
            guard changed else { throw CLIError(message: "No recorded idea has that ID.") }
        default: break
        }
    case "memory":
        let action = try options.subcommand(["add", "edit", "forget"])
        switch action {
        case "add":
            guard let text = options.values["text"] ?? options.values["note"] else { throw CLIError(message: "memory add requires --text.") }
            let source = try choose(options.values["source"], IdeaSource.allCases, label: "source") ?? .me
            let confidence = try choose(options.values["confidence"], KnowledgeConfidence.allCases, label: "confidence") ?? .known
            let date = try options.values["date"].map { try parseDate($0, label: "--date") }
            guard person.addMemory(text, date: date, source: source, confidence: confidence) != nil else { throw CLIError(message: "That memory is empty or is already recorded for this person.") }
        case "edit":
            let id = try uid(options.values["memory"], label: "--memory")
            var date: Date?? = .none
            if let value = options.values["date"] { date = .some(try parseDate(value, label: "--date")) }
            guard person.updateMemory(id, text: options.values["text"] ?? options.values["note"], date: date) else { throw CLIError(message: "No recorded memory has that ID.") }
        default:
            let id = try uid(options.values["memory"], label: "--memory")
            guard person.forgetMemory(id) else { throw CLIError(message: "No recorded memory has that ID.") }
        }
    case "interest":
        let action = try options.subcommand(["add", "edit", "remove"])
        switch action {
        case "add":
            guard let name = options.values["name"] ?? options.values["activity"] else { throw CLIError(message: "interest add requires --name.") }
            let source = try choose(options.values["source"], IdeaSource.allCases, label: "source") ?? .me
            let confidence = try choose(options.values["confidence"], KnowledgeConfidence.allCases, label: "confidence") ?? .known
            guard person.addInterest(name, detail: options.values["detail"] ?? "", source: source, confidence: confidence) != nil else { throw CLIError(message: "That interest is empty or is already recorded for this person.") }
        case "edit":
            let id = try uid(options.values["interest"], label: "--interest")
            guard person.updateInterest(id, name: options.values["name"], detail: options.values["detail"]) else { throw CLIError(message: "No recorded interest has that ID.") }
        default:
            let id = try uid(options.values["interest"], label: "--interest")
            guard person.removeInterest(id) else { throw CLIError(message: "No recorded interest has that ID.") }
        }
    case "ritual":
        let action = try options.subcommand(["add", "remove"])
        switch action {
        case "add":
            guard let title = options.values["title"] ?? options.values["name"] else { throw CLIError(message: "ritual add requires --title.") }
            var days: Int?
            if let value = options.values["days"] {
                guard let parsed = Int(value), (1...365).contains(parsed) else { throw CLIError(message: "--days must be between 1 and 365.") }
                days = parsed
            }
            let source = try choose(options.values["source"], IdeaSource.allCases, label: "source") ?? .me
            guard person.addRitual(title: title, note: options.values["note"] ?? "", days: days, source: source) != nil else { throw CLIError(message: "That ritual is empty or is already recorded for this person.") }
        default:
            let id = try uid(options.values["ritual"], label: "--ritual")
            guard person.removeRitual(id) else { throw CLIError(message: "No recorded ritual has that ID.") }
        }
    case "pass":
        let ideaId = try options.values["idea"].map { try uid($0, label: "--idea") }
        if let ideaId {
            guard person.dismissIdea(ideaId) else { throw CLIError(message: "No recorded idea has that ID.") }
            person.recordFeedback(.notForMe, ideaId: ideaId)
        } else {
            guard person.openToIdeas else { throw CLIError(message: "\(person.name) has no recorded ways of connecting to set aside. Use --idea, or update your intention.") }
            person.recordFeedback(.notForMe, action: person.suggestion().action)
        }
    case "useful":
        let ideaId = try options.values["idea"].map { try uid($0, label: "--idea") }
        person.recordFeedback(.helpful, ideaId: ideaId, action: person.suggestion().action)
    default: break
    }
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
keepclose log ID [--kind KIND] [--initiator WHO] [--at ISO8601] [--note TEXT] [--idea IDEA_UUID]
keepclose resolve ID --entry ENTRY_UUID Leave an incoming or outgoing message here
keepclose unlog ID --entry ENTRY_UUID   Remove a mistaken contact log
keepclose plan ID --title TEXT --at ISO8601 [--idea IDEA_UUID]
keepclose plan ID --complete PLAN_UUID [--at ISO8601]
keepclose plan ID --cancel PLAN_UUID
keepclose merge SOURCE --into DEST [--birthday source|destination] [--yes] Preview or apply a backed-up merge
keepclose context ID                    Recorded context and current ways to connect
keepclose idea ID --add --activity TEXT [--kind KIND] [--reminder TEXT] [--reason TEXT]
                                        [--timing TIMING] [--cadence DAYS] [--occasions 'a,b']
keepclose idea ID --edit --idea IDEA_UUID [--activity TEXT] [--reminder TEXT] [--reason TEXT]
                                        [--kind KIND] [--timing TIMING|anytime] [--cadence DAYS|none]
keepclose idea ID --dismiss --idea IDEA_UUID   Set a way of connecting aside; imports respect this
keepclose idea ID --restore|--remove --idea IDEA_UUID
keepclose memory ID --add --text TEXT [--date ISO8601] [--source SOURCE] [--confidence LEVEL]
keepclose memory ID --edit --memory MEMORY_UUID [--text TEXT] [--date ISO8601]
keepclose memory ID --forget --memory MEMORY_UUID
keepclose interest ID --add --name TEXT [--detail TEXT] [--source SOURCE] [--confidence LEVEL]
keepclose interest ID --edit --interest INTEREST_UUID [--name TEXT] [--detail TEXT]
keepclose interest ID --remove --interest INTEREST_UUID
keepclose ritual ID --add --title TEXT [--note TEXT] [--days N] [--source SOURCE]
keepclose ritual ID --remove --ritual RITUAL_UUID
keepclose useful ID [--idea IDEA_UUID]  Note that a suggestion is useful (local only)
keepclose pass ID [--idea IDEA_UUID]    Set a suggestion aside without guilt; nothing is logged
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
        --method (message/call/email/in-person), --address, --notes,
        --birthday MM-DD|YYYY-MM-DD|none, --birthday-reminder on|off, --gift-reminder automatic|on|off.
Idea kinds: sharedActivity, async, call, ritual, visit, gesture, conversation.
Idea timing: anytime, weekday, evening, weekend, freeTime.
Source (where context came from): me, them, memory, agent, unsure.
Confidence (how well it is known): known, unsure, suggested.
Context is stored locally and only leaves the device in a prompt you copy yourself.
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
    let fields = ["name", "circle", "types", "contexts", "intention", "rhythm", "days", "method", "address", "context", "notes", "birthday", "birthday-reminder", "gift-reminder"]
    switch command {
    case "merge":
        try options.allow(["into", "yes", "birthday"], positional: 1)
        guard let destination = options.values["into"] else { throw CLIError(message: "Use merge SOURCE --into DEST. Omit --yes to preview first.") }
        let people = try repository.people()
        let source = people[try index(identifier(options.positional[0]), in: people)]
        let target = people[try index(identifier(destination), in: people)]
        let birthdayChoice = options.values["birthday"] ?? "destination"
        guard ["source", "destination"].contains(birthdayChoice) else { throw CLIError(message: "Birthday choice must be source or destination.") }
        let plan = try PeopleMerge(keeping: target, merging: source, useSourceBirthday: birthdayChoice == "source")
        if options.flag("yes") { try repository.merge(plan) }
        try emit(plan.combined)
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
            struct Preview: Encodable {
                let dryRun: Bool
                let added: Int
                let updated: Int
                let unchanged: Int
                let newIdeas: Int
                let respectedDismissals: Int
                let changes: [AgentImportChange]
            }
            try emit(Preview(dryRun: true, added: plan.added, updated: plan.updated, unchanged: plan.unchanged, newIdeas: plan.newIdeaCount, respectedDismissals: plan.respectedDismissals, changes: plan.changes))
        }
    case "path": try options.allow([], positional: 0); try emit(["directory": repository.directory.path])
    case "list", "due", "suggestions":
        try options.allow([], positional: 0)
        let people = try repository.people()
        if command == "suggestions" { try emit(people.suggestedPeople().map { Advice(person: $0, suggestion: $0.suggestion()) }) }
        else { try emit(command == "due" ? people.suggestedPeople() : people) }
    case "context":
        try options.allow([], positional: 1)
        let people = try repository.people(); let person = people[try index(try identifier(options.positional[0]), in: people)]
        struct ContextView: Encodable { let person: Person; let opportunities: [ConnectionOpportunity] }
        try emit(ContextView(person: person, opportunities: person.opportunities()))
    case "show", "suggest":
        try options.allow([], positional: 1); let id = try identifier(options.positional[0]); let people = try repository.people(); let person = people[try index(id, in: people)]; if command == "suggest" { try emit(Advice(person: person, suggestion: person.suggestion())) } else { try emit(person) }
    case "add":
        try options.allow(fields, positional: 0)
        guard options.values["name"] != nil else { throw CLIError(message: "add requires --name.") }
        var person = Person(name: ""); try apply(options, to: &person)
        try repository.modifyPeople { $0.append(person) }; try emit(person)
    case "update", "log", "snooze", "pause", "resume", "delete", "resolve", "unlog", "plan":
        let allowed = command == "update" ? fields : command == "log" ? ["at", "note", "kind", "initiator", "idea"] : ["resolve", "unlog"].contains(command) ? ["entry"] : command == "plan" ? ["title", "at", "idea", "complete", "cancel"] : command == "snooze" ? ["days"] : command == "delete" ? ["yes"] : []
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
                let ideaId = try options.values["idea"].map(identifier)
                if let ideaId { guard people[i].ideas.contains(where: { $0.id == ideaId }) || people[i].rituals.contains(where: { $0.id == ideaId }) else { throw CLIError(message: "Idea not found for this person.") } }
                people[i].recordContact(at: at, note: options.values["note"] ?? "", kind: kind, initiator: initiator, ideaId: ideaId)
            case "resolve":
                guard let value = options.values["entry"] else { throw CLIError(message: "resolve requires --entry ENTRY_UUID.") }
                let entry = try identifier(value)
                guard let contact = people[i].contacts.first(where: { $0.id == entry && [.incoming, .outreach].contains($0.kind) }) else { throw CLIError(message: "Message entry not found for this person.") }
                if contact.kind == .incoming { people[i].resolveIncoming(entry) } else { people[i].resolveOutreach(entry) }
            case "unlog":
                guard let value = options.values["entry"], people[i].removeContact(try identifier(value)) else { throw CLIError(message: "Contact entry not found for this person.") }
            case "plan":
                if let value = options.values["complete"] {
                    guard options.values["cancel"] == nil, options.values["title"] == nil, options.values["idea"] == nil else { throw CLIError(message: "Use --complete with only an optional --at.") }
                    let at = try options.values["at"].map(date) ?? .now
                    guard people[i].finishPlan(try identifier(value), at: at) != nil else { throw CLIError(message: "Active plan not found or contact date is in the future.") }
                } else if let value = options.values["cancel"] {
                    guard options.values["title"] == nil, options.values["at"] == nil, options.values["idea"] == nil else { throw CLIError(message: "Use --cancel on its own.") }
                    let planId = try identifier(value)
                    guard people[i].activePlans.contains(where: { $0.id == planId }) else { throw CLIError(message: "Active plan not found.") }
                    people[i].cancelPlan(planId)
                } else {
                    guard let title = options.values["title"], let value = options.values["at"] else { throw CLIError(message: "A plan needs --title and --at.") }
                    let at = try date(value)
                    guard at >= .now else { throw CLIError(message: "New plans need a future date; log past shared time as conversation.") }
                    let ideaId = try options.values["idea"].map(identifier)
                    if let ideaId { guard people[i].ideas.contains(where: { $0.id == ideaId }) || people[i].rituals.contains(where: { $0.id == ideaId }) else { throw CLIError(message: "Idea not found for this person.") } }
                    guard people[i].addPlan(title: title, date: at, ideaId: ideaId) != nil else { throw CLIError(message: "A plan needs a title.") }
                }
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
    case "idea", "memory", "interest", "ritual", "pass", "useful":
        let contextKeys = ["add", "edit", "dismiss", "restore", "remove", "forget", "idea", "memory", "interest", "ritual", "activity", "reminder", "reason", "kind", "timing", "cadence", "occasions", "text", "note", "date", "name", "detail", "title", "days", "source", "confidence"]
        try options.allow(command == "pass" || command == "useful" ? ["idea"] : contextKeys, positional: 1)
        let id = try identifier(options.positional[0])
        struct CommandResult: Encodable {
            let person: UUID
            let command: String
            let personName: String
            let action: String
            let ideas: [ConnectionIdea]
            let memories: [ConnectionMemory]
            let interests: [ConnectionInterest]
            let rituals: [ConnectionRitual]
            let feedback: [SuggestionFeedback]
        }
        let result = try repository.modifyPeople { people -> CommandResult in
            let i = try index(id, in: people)
            try applyContextCommand(command, options: options, to: &people[i])
            let action = options.flag("add") ? "add" : options.flag("edit") ? "edit" : options.flag("dismiss") ? "dismiss" : options.flag("restore") ? "restore" : options.flag("remove") ? "remove" : options.flag("forget") ? "forget" : command == "pass" ? "setAside" : command == "useful" ? "noted" : command
            return CommandResult(person: people[i].id, command: command, personName: people[i].name, action: action, ideas: people[i].ideas, memories: people[i].memories, interests: people[i].interests, rituals: people[i].rituals, feedback: people[i].feedback)
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
