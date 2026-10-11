import Foundation

public enum ContactMethod: String, Codable, CaseIterable, Sendable {
    case message = "Message", call = "Call", email = "Email", inPerson = "In person"
}
public enum RelationshipIntention: String, Codable, CaseIterable, Sendable {
    case grow, maintain, space, unsure
    public var title: String { switch self { case .grow: "Grow"; case .maintain: "Maintain"; case .space: "Give more space"; case .unsure: "Unsure" } }
}
public enum ContactKind: String, Codable, CaseIterable, Sendable, Identifiable {
    public var id: String { rawValue }
    case outreach, incoming, conversation, reply, ambient
    public var title: String { switch self { case .outreach: "Message or invitation sent"; case .incoming: "They reached out"; case .conversation: "We spent time together"; case .reply: "I replied"; case .ambient: "Everyday contact" } }
}
public enum Initiator: String, Codable, CaseIterable, Sendable { case me, them, mutual, unknown }

/// How much we actually know about a piece of relationship context.
///
/// The app keeps this separate from the text itself so an AI recollection is never
/// presented as something the user established. Newly imported context defaults to
/// `unsure`; only the user promotes it to `known`.
public enum KnowledgeConfidence: String, Codable, CaseIterable, Sendable {
    case known, unsure, suggested
    public var title: String {
        switch self {
        case .known: "Something I know"
        case .unsure: "A recollection"
        case .suggested: "An idea to consider"
        }
    }
    /// Highest trust wins when the same context arrives from several sources.
    public var rank: Int { switch self { case .known: 2; case .unsure: 1; case .suggested: 0 } }
    public static func strongest(_ values: some Sequence<KnowledgeConfidence>) -> KnowledgeConfidence {
        values.max { $0.rank < $1.rank } ?? .unsure
    }
}
public enum IdeaSource: String, Codable, CaseIterable, Sendable {
    case me, them, memory, agent, unsure
    public var title: String {
        switch self {
        case .me: "You mentioned this"
        case .them: "They suggested this"
        case .memory: "From your conversations"
        case .agent: "An idea from your agent"
        case .unsure: "Not sure where this came from"
        }
    }
    public var rank: Int { switch self { case .me: 3; case .them: 3; case .memory: 2; case .agent: 1; case .unsure: 0 } }
    public static func strongest(_ values: some Sequence<IdeaSource>) -> IdeaSource {
        values.max { $0.rank < $1.rank } ?? .unsure
    }
    /// Merge provenance from several sources, keeping the order stable.
    public static func merge(_ values: [IdeaSource], _ added: [IdeaSource]) -> [IdeaSource] {
        var result = values
        for source in added where !result.contains(source) { result.append(source) }
        return result
    }
    /// Wording used when the app explains where something came from.
    public var attribution: String {
        switch self {
        case .me: "your note"
        case .them: "something they said"
        case .memory: "remembered context"
        case .agent: "an agent suggestion"
        case .unsure: "unconfirmed context"
        }
    }
}
public enum IdeaKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case sharedActivity, async, call, ritual, visit, gesture, conversation
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .sharedActivity: "Spend time together"
        case .async: "Send something"
        case .call: "Talk"
        case .ritual: "Keep a ritual"
        case .visit: "See each other"
        case .gesture: "A small gesture"
        case .conversation: "Ask about something"
        }
    }
}
public enum IdeaTiming: String, Codable, CaseIterable, Sendable, Identifiable {
    case anytime, weekday, evening, weekend, freeTime
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .anytime: "Whenever suits"
        case .weekday: "A weekday"
        case .evening: "An evening"
        case .weekend: "A weekend"
        case .freeTime: "When you have a free hour"
        }
    }
}
/// Gentle patterns such as "games on a Thursday". These are prompts to keep something
/// going, never calendar obligations, and they never contain claims about someone else.
public struct ConnectionRitual: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var note: String
    public var days: Int?
    public var sources: [IdeaSource]
    public var confidence: KnowledgeConfidence
    public var dismissed: Bool
    public init(id: UUID = UUID(), title: String, note: String = "", days: Int? = nil, sources: [IdeaSource] = [.me], confidence: KnowledgeConfidence = .known) {
        self.id = id
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        self.days = days.map { min(max($0, 1), 365) }
        self.sources = sources
        self.confidence = confidence
        dismissed = false
    }
    private enum CodingKeys: String, CodingKey { case id, title, note, days, sources, confidence, dismissed }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        days = try c.decodeIfPresent(Int.self, forKey: .days)
        sources = try c.decodeIfPresent([IdeaSource].self, forKey: .sources) ?? [.unsure]
        confidence = try c.decodeIfPresent(KnowledgeConfidence.self, forKey: .confidence) ?? .unsure
        dismissed = try c.decodeIfPresent(Bool.self, forKey: .dismissed) ?? false
    }
    /// How often the pattern might come round again, when the user or an import said so.
    public var cadenceDays: Int {
        if let days { return min(max(days, 1), 365) }
        return 14
    }
    public mutating func update(title: String, note: String, days: Int?) {
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        self.days = days.map { min(max($0, 1), 365) }
        confidence = .known
        sources = IdeaSource.merge([.me], sources)
    }
}
/// A way of connecting: somewhere to start when "we should catch up" needs a shape.
public struct ConnectionIdea: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var kind: IdeaKind
    public var activity: String
    public var reminder: String
    public var reason: String
    public var timing: IdeaTiming?
    public var occasions: [String]
    public var cadenceDays: Int?
    public var sources: [IdeaSource]
    public var confidence: KnowledgeConfidence
    public var dismissed: Bool
    public var askedAt: Date?
    public var lastNote: Date?
    public init(id: UUID = UUID(), kind: IdeaKind = .sharedActivity, activity: String, reminder: String = "", reason: String = "", timing: IdeaTiming? = nil, occasions: [String] = [], cadenceDays: Int? = nil, sources: [IdeaSource] = [.me], confidence: KnowledgeConfidence = .known, askedAt: Date? = nil, lastNote: Date? = nil) {
        self.id = id
        self.kind = kind
        let text = activity.trimmingCharacters(in: .whitespacesAndNewlines)
        self.activity = text
        let reminderText = reminder.trimmingCharacters(in: .whitespacesAndNewlines)
        self.reminder = reminderText.isEmpty ? ConnectionIdea.defaultReminder(kind: kind, activity: text) : reminderText
        self.reason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        self.timing = timing
        self.occasions = ConnectionIdea.clean(occasions)
        self.cadenceDays = cadenceDays.map { min(max($0, 1), 365) }
        self.sources = sources
        self.confidence = confidence
        dismissed = false
        self.askedAt = askedAt
        self.lastNote = lastNote
    }
    private enum CodingKeys: String, CodingKey { case id, kind, activity, reminder, reason, timing, occasions, cadenceDays, sources, confidence, dismissed, askedAt, lastNote }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try c.decodeIfPresent(IdeaKind.self, forKey: .kind) ?? .sharedActivity
        activity = try c.decodeIfPresent(String.self, forKey: .activity) ?? ""
        reminder = try c.decodeIfPresent(String.self, forKey: .reminder) ?? ""
        if reminder.isEmpty { reminder = ConnectionIdea.defaultReminder(kind: kind, activity: activity) }
        reason = try c.decodeIfPresent(String.self, forKey: .reason) ?? ""
        timing = try c.decodeIfPresent(IdeaTiming.self, forKey: .timing)
        occasions = try c.decodeIfPresent([String].self, forKey: .occasions) ?? []
        cadenceDays = try c.decodeIfPresent(Int.self, forKey: .cadenceDays)
        sources = try c.decodeIfPresent([IdeaSource].self, forKey: .sources) ?? [.unsure]
        confidence = try c.decodeIfPresent(KnowledgeConfidence.self, forKey: .confidence) ?? .unsure
        dismissed = try c.decodeIfPresent(Bool.self, forKey: .dismissed) ?? false
        askedAt = try c.decodeIfPresent(Date.self, forKey: .askedAt)
        lastNote = try c.decodeIfPresent(Date.self, forKey: .lastNote)
    }
    /// Fallback wording when no invitation text was given. Kept plain on purpose: the app
    /// would rather repeat the user's own phrase than invent a sentence about them.
    public static func defaultReminder(kind: IdeaKind, activity: String) -> String {
        let text = activity.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "A way to connect" }
        switch kind {
        case .call: return "A call: \(text)"
        case .conversation: return "Ask about \(text)"
        default: return text
        }
    }
    static func clean(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && $0.count <= 80 && seen.insert($0.lowercased()).inserted }
    }
    /// Stable identity for de-duplication. Uses the kind plus the words of the activity so
    /// that a re-import of the same evening in different phrasing is recognised as one idea.
    public var fingerprint: String {
        let kindAndActivity = "\(kind.rawValue)|\(AgentImportBatch.normalized(activity))"
        return AgentImportBatch.fingerprint(kindAndActivity)
    }
    public func matches(_ other: ConnectionIdea) -> Bool { fingerprint == other.fingerprint }
    /// Short label used in the interface: what the idea asks of the user.
    public var title: String { reminder.isEmpty ? activity : reminder }
    public var isActionable: Bool { !dismissed && !activity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    /// Merge imported knowledge into an existing idea without overwriting the user's own words.
    public mutating func merge(imported: ConnectionIdea) {
        sources = IdeaSource.merge(sources, imported.sources)
        confidence = KnowledgeConfidence.strongest([confidence, imported.confidence])
        if timing == nil { timing = imported.timing }
        if cadenceDays == nil { cadenceDays = imported.cadenceDays }
        occasions = ConnectionIdea.clean(occasions + imported.occasions)
        if reason.isEmpty { reason = imported.reason }
        else if !imported.reason.isEmpty && !reason.localizedCaseInsensitiveContains(imported.reason) && !imported.reason.localizedCaseInsensitiveContains(reason) {
            // Keep both explanations only when they add something; the app shows them as one line each.
            reason += "\n" + imported.reason
        }
        if reminder.isEmpty { reminder = imported.reminder }
    }
    public mutating func mergeRemembered(_ remembered: ConnectionIdea) {
        merge(imported: remembered)
        if activity.isEmpty { activity = remembered.activity }
        if kind.rawValue.isEmpty { kind = remembered.kind }
    }
}

public struct ContactEntry: Identifiable, Codable, Equatable, Sendable {
    public var id = UUID()
    public var date: Date
    public var note: String
    public var kind: ContactKind = .outreach
    public var initiator: Initiator = .me
    public var resolvedAt: Date?
    public var tracksResponse = true
    public var ideaId: UUID?
    /// Links automatic reply resolution to its event, so correcting a log can reopen it.
    public var responseEntryId: UUID?
    public init(date: Date, note: String, kind: ContactKind = .outreach, initiator: Initiator = .me) {
        self.date = date; self.note = note; self.kind = kind; self.initiator = initiator
    }
    private enum CodingKeys: String, CodingKey { case id, date, note, kind, initiator, resolvedAt, tracksResponse, ideaId, responseEntryId }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id); date = try c.decode(Date.self, forKey: .date); note = try c.decode(String.self, forKey: .note)
        kind = try c.decodeIfPresent(ContactKind.self, forKey: .kind) ?? .outreach
        initiator = try c.decodeIfPresent(Initiator.self, forKey: .initiator) ?? (kind == .incoming ? .them : .me)
        resolvedAt = try c.decodeIfPresent(Date.self, forKey: .resolvedAt)
        ideaId = try c.decodeIfPresent(UUID.self, forKey: .ideaId)
        responseEntryId = try c.decodeIfPresent(UUID.self, forKey: .responseEntryId)
        tracksResponse = try c.decodeIfPresent(Bool.self, forKey: .tracksResponse) ?? c.contains(.kind)
    }
}
/// A commitment is separate from both an invitation and time actually spent together.
public struct ConnectionPlan: Identifiable, Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable { case planned, happened, cancelled }
    public var id: UUID
    public var title: String
    public var date: Date
    public var ideaId: UUID?
    public var status: Status
    public var completedContactId: UUID?
    public init(id: UUID = UUID(), title: String, date: Date, ideaId: UUID? = nil) {
        self.id = id; self.title = title; self.date = date; self.ideaId = ideaId; status = .planned
    }
}

public struct RelationshipSuggestion: Codable, Equatable, Sendable {
    public enum Action: String, Codable, Sendable { case reply, hello, takeInitiative, timeTogether, giveSpace, reflect, paused, later }
    public var action: Action
    public var title: String
    public var reason: String
    public var ready: Bool
    public var nextDate: Date?
    /// Set when this suggestion came from a recorded way of connecting, so the
    /// interface can show the context behind it and offer feedback on it.
    public var opportunity: ConnectionOpportunity?
}
/// A concrete, grounded way of connecting with someone, with the context behind it.
public struct ConnectionOpportunity: Codable, Equatable, Sendable, Identifiable {
    public var ideaId: UUID
    public var activity: String
    public var kind: IdeaKind
    public var prompt: String
    public var reason: String
    public var timing: IdeaTiming?
    /// True when the app knows about something shared that this idea relates to.
    public var grounded: Bool
    public var sources: [IdeaSource]
    public var confidence: KnowledgeConfidence
    public var isRitual: Bool
    public var ready: Bool
    public var nextDate: Date?
    public var id: UUID { ideaId }
    /// One honest sentence about how well-founded this is. Never claims to know someone's availability.
    public var provenance: String {
        let origin = IdeaSource.strongest(sources)
        switch confidence {
        case .known: return origin == .me || origin == .them ? "Based on something you recorded" : "Based on context in your notes"
        case .unsure: return "A recollection, not confirmed"
        case .suggested: return origin == .agent ? "An idea from your agent, not something confirmed" : "An idea to consider, not something confirmed"
        }
    }
}
/// Optional context behind a suggestion, surfaced so an AI can suggest better ways to connect.
public struct ConnectionMemory: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var text: String
    public var date: Date?
    public var sources: [IdeaSource]
    public var confidence: KnowledgeConfidence
    public var userEdited: Bool
    public init(id: UUID = UUID(), text: String, date: Date? = nil, sources: [IdeaSource] = [.me], confidence: KnowledgeConfidence = .known, userEdited: Bool = false) {
        self.id = id
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.date = date
        self.sources = sources
        self.confidence = confidence
        self.userEdited = userEdited
    }
    private enum CodingKeys: String, CodingKey { case id, text, date, sources, confidence, userEdited }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        date = try c.decodeIfPresent(Date.self, forKey: .date)
        sources = try c.decodeIfPresent([IdeaSource].self, forKey: .sources) ?? [.unsure]
        confidence = try c.decodeIfPresent(KnowledgeConfidence.self, forKey: .confidence) ?? .unsure
        userEdited = try c.decodeIfPresent(Bool.self, forKey: .userEdited) ?? false
    }
    public mutating func merge(imported: ConnectionMemory) {
        guard !userEdited else { return }
        sources = Array(Set(sources + imported.sources))
        confidence = KnowledgeConfidence.strongest([confidence, imported.confidence])
        if date == nil { date = imported.date }
    }
    public var fingerprint: String { AgentImportBatch.fingerprint(text) }
}
/// A topic, hobby or shared interest that suggestions can be grounded in.
public struct ConnectionInterest: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var detail: String
    public var sources: [IdeaSource]
    public var confidence: KnowledgeConfidence
    public var userEdited: Bool
    public init(id: UUID = UUID(), name: String, detail: String = "", sources: [IdeaSource] = [.me], confidence: KnowledgeConfidence = .known, userEdited: Bool = false) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.detail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        self.sources = sources
        self.confidence = confidence
        self.userEdited = userEdited
    }
    private enum CodingKeys: String, CodingKey { case id, name, detail, sources, confidence, userEdited }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        detail = try c.decodeIfPresent(String.self, forKey: .detail) ?? ""
        sources = try c.decodeIfPresent([IdeaSource].self, forKey: .sources) ?? [.unsure]
        confidence = try c.decodeIfPresent(KnowledgeConfidence.self, forKey: .confidence) ?? .unsure
        userEdited = try c.decodeIfPresent(Bool.self, forKey: .userEdited) ?? false
    }
    public mutating func merge(imported: ConnectionInterest) {
        guard !userEdited else { return }
        sources = Array(Set(sources + imported.sources))
        confidence = KnowledgeConfidence.strongest([confidence, imported.confidence])
        if detail.isEmpty { detail = imported.detail }
    }
    public var fingerprint: String { AgentImportBatch.fingerprint(name) }
}
/// Storage limits for recorded context. Generous enough for real life, bounded enough
/// that a runaway import cannot bloat local storage.
public struct ConnectionLimits: Equatable, Sendable {
    public var memories: Int
    public var interests: Int
    public var ideas: Int
    public var rituals: Int
    public var feedback: Int
    public init(memories: Int = 60, interests: Int = 60, ideas: Int = 60, rituals: Int = 20, feedback: Int = 100) {
        self.memories = memories; self.interests = interests; self.ideas = ideas; self.rituals = rituals; self.feedback = feedback
    }
}
/// Durable relationship context: the things worth remembering, and the ways of
/// connecting that might suit. Never invented by the app; only recorded or imported.
public struct ConnectionContext: Codable, Equatable, Sendable {
    public var memories: [ConnectionMemory] = []
    public var interests: [ConnectionInterest] = []
    public var ideas: [ConnectionIdea] = []
    public var rituals: [ConnectionRitual] = []
    public init(memories: [ConnectionMemory] = [], interests: [ConnectionInterest] = [], ideas: [ConnectionIdea] = [], rituals: [ConnectionRitual] = []) {
        self.memories = memories; self.interests = interests; self.ideas = ideas; self.rituals = rituals
    }
    private enum CodingKeys: String, CodingKey { case memories, interests, ideas, rituals }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        memories = try c.decodeIfPresent([ConnectionMemory].self, forKey: .memories) ?? []
        interests = try c.decodeIfPresent([ConnectionInterest].self, forKey: .interests) ?? []
        ideas = try c.decodeIfPresent([ConnectionIdea].self, forKey: .ideas) ?? []
        rituals = try c.decodeIfPresent([ConnectionRitual].self, forKey: .rituals) ?? []
    }
    public var isEmpty: Bool { memories.isEmpty && interests.isEmpty && ideas.isEmpty && rituals.isEmpty }
    public var hasActionableIdea: Bool { ideas.contains(where: \.isActionable) || rituals.contains { !$0.dismissed && !$0.title.isEmpty } }
    /// Lowercased words from shared interests, used to ground suggestion copy.
    public var interestKeywords: Set<String> {
        Set(interests.flatMap { interest in
            interest.name.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        }.filter { $0.count >= 3 })
    }
    /// Every activity already offered for this person, so imports do not propose the same thing twice.
    public var knownActivityTexts: [String] { ideas.map(\.activity) }
    public mutating func merge(_ imported: ConnectionContext) {
        mergeMemories(imported.memories)
        mergeInterests(imported.interests)
        mergeIdeas(imported.ideas)
        mergeRituals(imported.rituals)
        trim(to: Person.contextLimits)
    }
    /// Keep local storage bounded without silently discarding context the user is considering.
    public mutating func trim(to limits: ConnectionLimits = Person.contextLimits) {
        trimDismissedFirst(&ideas, limit: limits.ideas)
        trimDismissedFirst(&rituals, limit: limits.rituals)
        if memories.count > limits.memories { memories.removeFirst(memories.count - limits.memories) }
        if interests.count > limits.interests { interests.removeFirst(interests.count - limits.interests) }
    }
    private func trimDismissedFirst(_ list: inout [ConnectionIdea], limit: Int) {
        guard list.count > limit else { return }
        for index in list.indices.filter({ list[$0].dismissed }).reversed() where list.count > limit { list.remove(at: index) }
        while list.count > limit { list.removeFirst() }
    }
    private func trimDismissedFirst(_ list: inout [ConnectionRitual], limit: Int) {
        guard list.count > limit else { return }
        for index in list.indices.filter({ list[$0].dismissed }).reversed() where list.count > limit { list.remove(at: index) }
        while list.count > limit { list.removeFirst() }
    }
    private mutating func mergeMemories(_ incoming: [ConnectionMemory]) {
        for memory in incoming {
            guard !memory.text.isEmpty else { continue }
            if let index = memories.firstIndex(where: { $0.fingerprint == memory.fingerprint }) { memories[index].merge(imported: memory) }
            else { memories.append(memory) }
        }
    }
    private mutating func mergeInterests(_ incoming: [ConnectionInterest]) {
        for interest in incoming {
            guard !interest.name.isEmpty else { continue }
            if let index = interests.firstIndex(where: { $0.fingerprint == interest.fingerprint }) { interests[index].merge(imported: interest) }
            else { interests.append(interest) }
        }
    }
    private mutating func mergeIdeas(_ incoming: [ConnectionIdea]) {
        for idea in incoming {
            guard !idea.activity.isEmpty else { continue }
            // An existing or previously dismissed idea stays as it is: re-importing it is not new consent.
            guard !ideas.contains(where: { $0.isActionable && $0.matches(idea) }), !ideas.contains(where: { $0.dismissed && $0.matches(idea) }) else { continue }
            ideas.append(idea)
        }
    }
    private mutating func mergeRituals(_ incoming: [ConnectionRitual]) {
        for ritual in incoming {
            let fingerprint = AgentImportBatch.fingerprint(ritual.title)
            guard !fingerprint.isEmpty else { continue }
            if rituals.contains(where: { AgentImportBatch.fingerprint($0.title) == fingerprint }) { continue }
            rituals.append(ritual)
        }
    }
    public func idea(_ id: UUID) -> ConnectionIdea? { ideas.first { $0.id == id } }
    public var visibleIdeas: [ConnectionIdea] { ideas.filter(\.isActionable) }
    public var dismissedCount: Int { ideas.filter(\.dismissed).count }
}
/// Explicit, low-effort feedback about whether a suggestion was useful.
/// Only what the user chooses to mark is stored; silently ignoring a suggestion means nothing.
public struct SuggestionFeedback: Identifiable, Codable, Equatable, Sendable {
    public enum Signal: String, Codable, CaseIterable, Sendable {
        case helpful, notForMe, snoozed, done
        public var title: String {
            switch self {
            case .helpful: "This is useful"
            case .notForMe: "Not for me"
            case .snoozed: "Not now"
            case .done: "I did this"
            }
        }
    }
    public var id: UUID
    public var ideaId: UUID?
    public var action: RelationshipSuggestion.Action?
    public var signal: Signal
    public var at: Date
    public init(id: UUID = UUID(), ideaId: UUID? = nil, action: RelationshipSuggestion.Action? = nil, signal: Signal, at: Date = .now) {
        self.id = id; self.ideaId = ideaId; self.action = action; self.signal = signal; self.at = at
    }
    private enum CodingKeys: String, CodingKey { case id, ideaId, action, signal, at }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        ideaId = try c.decodeIfPresent(UUID.self, forKey: .ideaId)
        action = try c.decodeIfPresent(RelationshipSuggestion.Action.self, forKey: .action)
        signal = try c.decodeIfPresent(Signal.self, forKey: .signal) ?? .helpful
        at = try c.decodeIfPresent(Date.self, forKey: .at) ?? .now
    }
}

public struct Person: Identifiable, Codable, Equatable, Sendable {
    public static let typeOptions = ["Friend", "Family", "Colleague", "Partner", "Acquaintance"]
    public static let contextOptions = ["Work", "Flatmate", "Online", "Hobby", "Nearby", "Another city"]
    /// Kept short on purpose: feedback is a light signal, not a profile.
    public static let contextLimits = ConnectionLimits()
    public static let feedbackLimit = 100
    public static let ideaLimit = 60
    public static let memoryLimit = 60
    public var id = UUID()
    public var name: String
    public var circle: String // Preserve the original free-form label.
    public var relationshipTypes: [String] = ["Friend"]
    public var contexts: [String] = []
    public var importSources: [String] = []
    public var intention: RelationshipIntention = .maintain
    /// True once the user has chosen an intention. An imported stated preference may fill
    /// an undecided record, but never overrides a choice the user made.
    public var intentionChosen = true
    public var rhythmDays: Int
    public var rhythmIsCustom = false
    public var method: ContactMethod
    public var address: String
    public var context: String // Personal notes, separate from context tags.
    public var createdAt: Date
    public var contacts: [ContactEntry] = []
    public var snoozedUntil: Date?
    public var deferrals = 0
    public var paused = false
    public var connection = ConnectionContext()
    public var feedback: [SuggestionFeedback] = []
    public var plans: [ConnectionPlan] = []
    public var birthday: Birthday?
    public var birthdayReminder = true
    public var giftReminder: GiftReminder = .automatic
    public var contactLinks: [SystemContactLink] = []
    public var alternateContactDetails: [PersonContactDetail] = []
    public var mergedPersonIDs: [UUID] = []

    public init(name: String, circle: String = "Friend", rhythmDays: Int = 14, method: ContactMethod = .message, address: String = "", context: String = "", createdAt: Date = .now) {
        self.name = name; self.circle = circle; self.relationshipTypes = [circle]; self.rhythmDays = max(1, rhythmDays)
        self.method = method; self.address = address; self.context = context; self.createdAt = createdAt
        // A record still sitting at unsure has not been decided; any other value is a choice.
        self.intentionChosen = Self.derivedIntentionChosen(intention)
    }
    /// One rule for both new and saved records: only an undecided intention may be filled in.
    static func derivedIntentionChosen(_ intention: RelationshipIntention, explicit: Bool? = nil) -> Bool {
        explicit ?? (intention != .unsure)
    }
    private enum CodingKeys: String, CodingKey { case id, name, circle, relationshipTypes, contexts, importSources, intention, intentionChosen, rhythmDays, rhythmIsCustom, method, address, context, createdAt, contacts, snoozedUntil, deferrals, paused, connection, feedback, plans, birthday, birthdayReminder, giftReminder, contactLinks, mergedPersonIDs, alternateContactDetails }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id); name = try c.decode(String.self, forKey: .name)
        circle = try c.decodeIfPresent(String.self, forKey: .circle) ?? "Friend"
        relationshipTypes = try c.decodeIfPresent([String].self, forKey: .relationshipTypes) ?? [circle]
        contexts = try c.decodeIfPresent([String].self, forKey: .contexts) ?? []
        importSources = try c.decodeIfPresent([String].self, forKey: .importSources) ?? []
        intention = try c.decodeIfPresent(RelationshipIntention.self, forKey: .intention) ?? .maintain
        // Existing saved records treat their intention as a deliberate choice; a record still
        // sitting at unsure may be filled in by a stated preference.
        intentionChosen = Self.derivedIntentionChosen(intention, explicit: try c.decodeIfPresent(Bool.self, forKey: .intentionChosen))
        rhythmDays = try c.decode(Int.self, forKey: .rhythmDays)
        rhythmIsCustom = try c.decodeIfPresent(Bool.self, forKey: .rhythmIsCustom) ?? true // Never change existing schedules on upgrade.
        method = try c.decode(ContactMethod.self, forKey: .method); address = try c.decode(String.self, forKey: .address)
        context = try c.decode(String.self, forKey: .context); createdAt = try c.decode(Date.self, forKey: .createdAt)
        contacts = try c.decodeIfPresent([ContactEntry].self, forKey: .contacts) ?? []
        snoozedUntil = try c.decodeIfPresent(Date.self, forKey: .snoozedUntil)
        deferrals = try c.decodeIfPresent(Int.self, forKey: .deferrals) ?? 0
        paused = try c.decodeIfPresent(Bool.self, forKey: .paused) ?? false
        connection = try c.decodeIfPresent(ConnectionContext.self, forKey: .connection) ?? ConnectionContext()
        feedback = try c.decodeIfPresent([SuggestionFeedback].self, forKey: .feedback) ?? []
        plans = try c.decodeIfPresent([ConnectionPlan].self, forKey: .plans) ?? []
        birthday = try c.decodeIfPresent(Birthday.self, forKey: .birthday)
        birthdayReminder = try c.decodeIfPresent(Bool.self, forKey: .birthdayReminder) ?? true
        giftReminder = try c.decodeIfPresent(GiftReminder.self, forKey: .giftReminder) ?? .automatic
        contactLinks = try c.decodeIfPresent([SystemContactLink].self, forKey: .contactLinks) ?? []
        mergedPersonIDs = try c.decodeIfPresent([UUID].self, forKey: .mergedPersonIDs) ?? []
        alternateContactDetails = try c.decodeIfPresent([PersonContactDetail].self, forKey: .alternateContactDetails) ?? []
    }
    /// Records a deliberate choice, so later imports cannot silently change it.
    public mutating func chooseIntention(_ value: RelationshipIntention) {
        intention = value
        intentionChosen = true
    }
    public var suggestedRhythm: Int {
        let types = relationshipTypes.map { $0.lowercased() }
        var days = types.contains("partner") ? 7 : types.contains("acquaintance") ? 30 : 14
        if contexts.contains(where: { ["work", "flatmate", "nearby"].contains($0.lowercased()) }) { days = max(days, 21) }
        if intention == .grow { days = max(3, days / 2) }
        if intention == .space { days = max(days, 45) }
        return days
    }
    public mutating func applySuggestedRhythm() { rhythmDays = suggestedRhythm; rhythmIsCustom = false }
    public var lastContact: Date? { contacts.filter { [.outreach, .conversation, .reply].contains($0.kind) }.map(\.date).max() }
    public var lastIncoming: Date? { contacts.filter { $0.kind == .incoming || $0.kind == .conversation && $0.initiator == .them }.map(\.date).max() }
    public var pendingIncoming: [ContactEntry] { contacts.filter { $0.kind == .incoming && $0.resolvedAt == nil } }
    public func nextDue(calendar: Calendar = .current) -> Date {
        let regular = lastContact.map { calendar.date(byAdding: .day, value: max(1, rhythmDays), to: $0)! } ?? createdAt
        return max(regular, snoozedUntil ?? .distantPast)
    }
    public func isReady(at now: Date = .now, calendar: Calendar = .current) -> Bool {
        calendar.startOfDay(for: nextDue(calendar: calendar)) <= calendar.startOfDay(for: now)
    }
    public func isDue(at now: Date = .now, calendar: Calendar = .current) -> Bool { suggestion(at: now, calendar: calendar).ready }
    @discardableResult public mutating func recordContact(at date: Date = .now, note: String = "", kind: ContactKind = .outreach, initiator: Initiator? = nil, ideaId: UUID? = nil) -> UUID {
        let starter = initiator ?? (kind == .incoming ? .them : kind == .conversation ? .unknown : kind == .ambient ? .mutual : kind == .reply ? .them : .me)
        var entry = ContactEntry(date: date, note: note, kind: kind, initiator: starter)
        entry.ideaId = ideaId
        contacts.append(entry)
        reconcileResponses()
        if [.outreach, .reply, .conversation].contains(kind) { snoozedUntil = nil; deferrals = 0 }
        return entry.id
    }
    mutating func reconcileResponses() {
        for i in contacts.indices where contacts[i].kind == .incoming {
            // A manual resolution (and legacy resolution without a link) is authoritative.
            guard contacts[i].resolvedAt == nil || contacts[i].responseEntryId != nil else { continue }
            let response = contacts.filter { [.reply, .conversation].contains($0.kind) && $0.date >= contacts[i].date }
                .min { $0.date < $1.date }
            contacts[i].resolvedAt = response?.date
            contacts[i].responseEntryId = response?.id
        }
    }
    public mutating func resolveIncoming(_ id: UUID, at date: Date = .now) {
        if let i = contacts.firstIndex(where: { $0.id == id && $0.kind == .incoming }) {
            contacts[i].resolvedAt = date; contacts[i].responseEntryId = nil
        }
    }
    /// An explicit choice to allow new opportunities; it never invents a response.
    public mutating func resolveOutreach(_ id: UUID, at date: Date = .now) {
        if let i = contacts.firstIndex(where: { $0.id == id && $0.kind == .outreach }) { contacts[i].resolvedAt = date }
    }
    public var pendingOutreach: [ContactEntry] {
        contacts.filter { entry in
            entry.kind == .outreach && entry.tracksResponse && entry.resolvedAt == nil &&
            !contacts.contains { [.incoming, .reply, .conversation].contains($0.kind) && $0.date >= entry.date }
        }
    }
    @discardableResult public mutating func removeContact(_ id: UUID) -> Bool {
        guard contacts.contains(where: { $0.id == id }) else { return false }
        contacts.removeAll { $0.id == id }
        for i in plans.indices where plans[i].completedContactId == id { plans[i].status = .planned; plans[i].completedContactId = nil }
        reconcileResponses()
        return true
    }
    @discardableResult public mutating func correctContact(_ original: ContactEntry, date: Date, note: String, kind: ContactKind, initiator: Initiator) -> Bool {
        guard let i = contacts.firstIndex(where: { $0 == original }) else { return false }
        contacts[i].date = date; contacts[i].note = note; contacts[i].kind = kind
        contacts[i].initiator = kind == .conversation ? initiator : kind == .incoming || kind == .reply ? .them : kind == .ambient ? .mutual : .me
        if kind != original.kind || date != original.date {
            contacts[i].resolvedAt = nil; contacts[i].responseEntryId = nil
        }
        if kind != .conversation {
            for index in plans.indices where plans[index].completedContactId == original.id {
                plans[index].status = .planned; plans[index].completedContactId = nil
            }
        }
        reconcileResponses()
        return true
    }
    public var activePlans: [ConnectionPlan] { plans.filter { $0.status == .planned }.sorted { $0.date < $1.date } }
    @discardableResult public mutating func addPlan(title: String, date: Date, ideaId: UUID? = nil) -> ConnectionPlan? {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let plan = ConnectionPlan(title: title, date: date, ideaId: ideaId)
        plans.append(plan)
        return plan
    }
    @discardableResult public mutating func finishPlan(_ id: UUID, at date: Date = .now, now: Date = .now) -> UUID? {
        guard let i = plans.firstIndex(where: { $0.id == id && $0.status == .planned }), date <= now else { return nil }
        let entry = recordContact(at: date, note: plans[i].title, kind: .conversation, initiator: .mutual, ideaId: plans[i].ideaId)
        plans[i].status = .happened; plans[i].completedContactId = entry
        return entry
    }
    public mutating func cancelPlan(_ id: UUID) {
        if let i = plans.firstIndex(where: { $0.id == id && $0.status == .planned }) { plans[i].status = .cancelled }
    }

    /// Postpone without keeping count. There is no persistence score, so choosing to wait
    /// never accumulates as a mark against the relationship.
    public mutating func snooze(until date: Date) { snoozedUntil = date }
    public mutating func deferContact(until date: Date) { snooze(until: date) }
    public var smallStep: String {
        if !pendingIncoming.isEmpty { return "A short acknowledgement is enough to start a reply." }
        switch method {
        case .message: return "Send a quick hello. You don't need a big update."
        case .call: return "Send a message asking when a short call would suit."
        case .email: return "A two-line email is enough to open the conversation."
        case .inPerson: return "Suggest a coffee or a short walk."
        }
    }

    // MARK: - Recorded context

    public var memories: [ConnectionMemory] { connection.memories }
    public var interests: [ConnectionInterest] { connection.interests }
    public var ideas: [ConnectionIdea] { connection.ideas }
    public var rituals: [ConnectionRitual] { connection.rituals }
    public var visibleIdeas: [ConnectionIdea] { connection.visibleIdeas }
    public var dismissedIdeaCount: Int { connection.dismissedCount }

    @discardableResult
    public mutating func addIdea(kind: IdeaKind = .sharedActivity, activity: String, reminder: String = "", reason: String = "", timing: IdeaTiming? = nil, occasions: [String] = [], cadenceDays: Int? = nil, source: IdeaSource = .me, confidence: KnowledgeConfidence = .known) -> ConnectionIdea? {
        let idea = ConnectionIdea(kind: kind, activity: activity, reminder: reminder, reason: reason, timing: timing, occasions: occasions, cadenceDays: cadenceDays, sources: [source], confidence: confidence)
        guard idea.isActionable else { return nil }
        if connection.ideas.contains(where: { $0.isActionable && $0.matches(idea) }) { return nil }
        connection.ideas.append(idea)
        trimIdeas()
        return idea
    }
    /// Edit the user's own idea. Editing marks it as the user's own knowledge.
    @discardableResult
    public mutating func updateIdea(_ id: UUID, activity: String? = nil, reminder: String? = nil, reason: String? = nil, kind: IdeaKind? = nil, timing: IdeaTiming?? = nil, cadenceDays: Int?? = nil, occasions: [String]? = nil) -> Bool {
        guard let index = connection.ideas.firstIndex(where: { $0.id == id }) else { return false }
        if let activity { connection.ideas[index].activity = activity.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let reminder { connection.ideas[index].reminder = reminder.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let reason { connection.ideas[index].reason = reason.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let kind { connection.ideas[index].kind = kind }
        if let timing { connection.ideas[index].timing = timing }
        if let cadenceDays { connection.ideas[index].cadenceDays = cadenceDays.map { min(max($0, 1), 365) } }
        if let occasions { connection.ideas[index].occasions = ConnectionIdea.clean(occasions) }
        connection.ideas[index].reminder = connection.ideas[index].reminder.isEmpty ? ConnectionIdea.defaultReminder(kind: connection.ideas[index].kind, activity: connection.ideas[index].activity) : connection.ideas[index].reminder
        connection.ideas[index].confidence = .known
        connection.ideas[index].sources = [.me]
        return true
    }
    /// Dismiss without deleting, so imports know not to bring it back.
    @discardableResult
    public mutating func dismissIdea(_ id: UUID) -> Bool {
        guard let index = connection.ideas.firstIndex(where: { $0.id == id }) else { return false }
        connection.ideas[index].dismissed = true
        return true
    }
    @discardableResult
    public mutating func restoreIdea(_ id: UUID) -> Bool {
        guard let index = connection.ideas.firstIndex(where: { $0.id == id }) else { return false }
        connection.ideas[index].dismissed = false
        feedback.removeAll { $0.ideaId == id && $0.signal == .notForMe }
        return true
    }
    @discardableResult
    public mutating func removeIdea(_ id: UUID) -> Bool {
        let before = connection.ideas.count
        connection.ideas.removeAll { $0.id == id }
        return connection.ideas.count != before
    }
    private mutating func trimIdeas() {
        connection.trim(to: Self.contextLimits)
    }

    @discardableResult
    public mutating func addMemory(_ text: String, date: Date? = nil, source: IdeaSource = .me, confidence: KnowledgeConfidence = .known) -> ConnectionMemory? {
        let memory = ConnectionMemory(text: text, date: date, sources: [source], confidence: confidence)
        guard !memory.text.isEmpty else { return nil }
        if connection.memories.contains(where: { $0.fingerprint == memory.fingerprint }) { return nil }
        connection.memories.append(memory)
        connection.trim(to: Self.contextLimits)
        return memory
    }
    @discardableResult
    public mutating func updateMemory(_ id: UUID, text: String? = nil, date: Date?? = nil) -> Bool {
        guard let index = connection.memories.firstIndex(where: { $0.id == id }) else { return false }
        if let text { connection.memories[index].text = text.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let date { connection.memories[index].date = date }
        connection.memories[index].confidence = .known
        connection.memories[index].userEdited = true
        return true
    }
    @discardableResult
    public mutating func forgetMemory(_ id: UUID) -> Bool {
        let before = connection.memories.count
        connection.memories.removeAll { $0.id == id }
        return connection.memories.count != before
    }

    @discardableResult
    public mutating func addInterest(_ name: String, detail: String = "", source: IdeaSource = .me, confidence: KnowledgeConfidence = .known) -> ConnectionInterest? {
        let interest = ConnectionInterest(name: name, detail: detail, sources: [source], confidence: confidence)
        guard !interest.name.isEmpty else { return nil }
        if connection.interests.contains(where: { $0.fingerprint == interest.fingerprint }) { return nil }
        connection.interests.append(interest)
        return interest
    }
    @discardableResult
    public mutating func updateInterest(_ id: UUID, name: String? = nil, detail: String? = nil) -> Bool {
        guard let index = connection.interests.firstIndex(where: { $0.id == id }) else { return false }
        if let name { connection.interests[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let detail { connection.interests[index].detail = detail.trimmingCharacters(in: .whitespacesAndNewlines) }
        connection.interests[index].confidence = .known
        connection.interests[index].userEdited = true
        return true
    }
    @discardableResult
    public mutating func removeInterest(_ id: UUID) -> Bool {
        let before = connection.interests.count
        connection.interests.removeAll { $0.id == id }
        return connection.interests.count != before
    }

    @discardableResult
    public mutating func addRitual(title: String, note: String = "", days: Int? = nil, source: IdeaSource = .me) -> ConnectionRitual? {
        let ritual = ConnectionRitual(title: title, note: note, days: days, sources: [source], confidence: source == .agent ? .suggested : .known)
        guard !ritual.title.isEmpty else { return nil }
        let fingerprint = AgentImportBatch.fingerprint(ritual.title)
        guard !connection.rituals.contains(where: { AgentImportBatch.fingerprint($0.title) == fingerprint }) else { return nil }
        connection.rituals.append(ritual)
        return ritual
    }
    @discardableResult public mutating func restoreRitual(_ id: UUID) -> Bool {
        guard let index = connection.rituals.firstIndex(where: { $0.id == id }) else { return false }
        connection.rituals[index].dismissed = false
        feedback.removeAll { $0.ideaId == id && $0.signal == .notForMe }
        return true
    }
    @discardableResult
    public mutating func removeRitual(_ id: UUID) -> Bool {
        let before = connection.rituals.count
        connection.rituals.removeAll { $0.id == id }
        return connection.rituals.count != before
    }

    // MARK: - Feedback

    /// Record an explicit signal. Ignoring a suggestion records nothing at all.
    public mutating func recordFeedback(_ signal: SuggestionFeedback.Signal, ideaId: UUID? = nil, action: RelationshipSuggestion.Action? = nil, at date: Date = .now) {
        feedback.append(SuggestionFeedback(ideaId: ideaId, action: action, signal: signal, at: date))
        if feedback.count > Self.feedbackLimit { feedback.removeFirst(feedback.count - Self.feedbackLimit) }
    }
    public func lastFeedback(forIdea id: UUID) -> SuggestionFeedback? { feedback.last { $0.ideaId == id } }
    /// The user has said this specific idea isn't for them. Respect it permanently.
    public func passedOnIdea(_ id: UUID) -> Bool { feedback.contains { $0.ideaId == id && $0.signal == .notForMe } }
    public var lastActioned: Date? { feedback.filter { $0.signal != .helpful }.map(\.at).max() }
    public var helpfulIdeas: Set<UUID> { Set(feedback.filter { $0.signal == .helpful || $0.signal == .done }.compactMap(\.ideaId)) }
    /// Action-level feedback, used when no idea was attached (for example a plain check-in).
    public func passedOnAction(_ action: RelationshipSuggestion.Action) -> Bool { feedback.contains { $0.ideaId == nil && $0.action == action && $0.signal == .notForMe } }
    public var openToIdeas: Bool { connection.hasActionableIdea }

    // MARK: - Suggestions

    /// Every idea worth offering right now, best first, with the reasoning attached.
    /// Ways of connecting worth offering right now, best first. `readyOnly` is false when
    /// the caller also wants ideas that are still waiting their turn (for quiet suggestions).
    public func opportunities(at now: Date = .now, calendar: Calendar = .current, limit: Int = 3, readyOnly: Bool = true) -> [ConnectionOpportunity] {
        // Giving space or pausing means no proactive ideas at all, however good they are.
        guard !paused, intention != .space, pendingOutreach.isEmpty, activePlans.isEmpty, snoozedUntil.map({ calendar.startOfDay(for: $0) > calendar.startOfDay(for: now) }) != true else { return [] }
        let lastContactDate = lastContact
        let interestWords = connection.interestKeywords
        let recentText = contacts.sorted { $0.date > $1.date }.prefix(8).map { $0.note.lowercased() }.joined(separator: " ")
        var candidates: [(opportunity: ConnectionOpportunity, score: Int)] = []
        for idea in connection.ideas where idea.isActionable {
            if passedOnIdea(idea.id) || !isWorthOffering(idea) { continue }
            let readyAt = ideaReadyAt(idea, calendar: calendar)
            let ready = calendar.startOfDay(for: readyAt) <= calendar.startOfDay(for: now)
            let text = idea.activity.lowercased()
            let sharedGround = !interestWords.isEmpty && interestWords.contains { text.contains($0) }
            let recentMention = recentText.contains(idea.activity.lowercased())
            var score = 0
            let kind = idea.kind
            switch intention {
            case .grow:
                if kind == .sharedActivity || kind == .visit || kind == .ritual { score += 30 }
                if kind == .call { score += 12 }
                if kind == .async { score += 6 }
                if kind == .gesture { score += 4 }
            case .maintain:
                // Opening a small exchange suits maintaining; a private gesture is lower effort still.
                if kind == .async || kind == .conversation { score += 24 }
                if kind == .call { score += 18 }
                if kind == .gesture { score += 14 }
                if kind == .ritual { score += 10 }
                if kind == .sharedActivity { score += 8 }
            case .space, .unsure:
                if kind == .ritual { score += 10 }
                if kind == .async || kind == .gesture { score += 8 }
                if kind == .sharedActivity || kind == .visit { score += 4 }
            }
            if sharedGround { score += 20 }
            if recentMention { score += 14 }
            if helpfulIdeas.contains(idea.id) { score += 16 }
            if let timing = idea.timing, timingMatches(timing, at: now, calendar: calendar) { score += 10 }
            if idea.confidence == .suggested { score -= 6 }
            if !ready { score -= 24 }
            if let lastContactDate {
                let days = calendar.dateComponents([.day], from: lastContactDate, to: now).day ?? 0
                if days >= rhythmDays { score += min(12, days - rhythmDays + 6) }
            }
            candidates.append((ConnectionOpportunity(ideaId: idea.id, activity: idea.activity, kind: idea.kind, prompt: idea.reminder.isEmpty ? idea.activity : idea.reminder, reason: idea.reason, timing: idea.timing, grounded: sharedGround || recentMention || !idea.reason.isEmpty, sources: idea.sources, confidence: idea.confidence, isRitual: false, ready: ready, nextDate: ready ? nil : readyAt), score))
        }
        for ritual in connection.rituals where !ritual.dismissed && !ritual.title.isEmpty && !passedOnIdea(ritual.id) {
            guard isSafeConnectionText([ritual.title, ritual.note].joined(separator: " ")),
                  ritual.confidence == .known || !ritual.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let readyAt = ritualReadyAt(ritual, calendar: calendar)
            let ready = calendar.startOfDay(for: readyAt) <= calendar.startOfDay(for: now)
            var score = 20
            if !ready { score -= 24 }
            candidates.append((ConnectionOpportunity(ideaId: ritual.id, activity: ritual.title, kind: .ritual, prompt: ritual.title, reason: ritual.note, timing: nil, grounded: !ritual.note.isEmpty, sources: ritual.sources, confidence: ritual.confidence, isRitual: true, ready: ready, nextDate: ready ? nil : readyAt), score))
        }
        return candidates
            .filter { !readyOnly || $0.opportunity.ready }
            .sorted { left, right in
                if left.score != right.score { return left.score > right.score }
                return left.opportunity.ideaId.uuidString < right.opportunity.ideaId.uuidString
            }
            .prefix(limit).map(\.opportunity)
    }
    /// The single best way to connect right now, if there is one worth mentioning.
    /// Ideas still waiting their turn are not "best": they are simply not due yet.
    public func bestOpportunity(at now: Date = .now, calendar: Calendar = .current) -> ConnectionOpportunity? {
        opportunities(at: now, calendar: calendar, limit: 8).first
    }
    /// True when something could be offered today. Used to keep quiet lists honest:
    /// an idea the user has just acted on is not an invitation.
    public func hasReadyIdea(at now: Date = .now, calendar: Calendar = .current) -> Bool {
        !opportunities(at: now, calendar: calendar, limit: 1).isEmpty
    }
    /// When an idea becomes available again. Only an actual outcome (doing it, or setting it
    /// aside for now) moves this clock; marking something useful does not postpone it.
    ///
    /// A completed activity waits its stated cadence, or the person's rhythm if none was set.
    /// A deferral uses snoozedUntil rather than starting the activity cadence.
    private func ideaReadyAt(_ idea: ConnectionIdea, calendar: Calendar) -> Date {
        guard let outcome = lastOutcome(forIdea: idea.id) else { return createdAt }
        let cadence = idea.cadenceDays ?? rhythmDays
        return calendar.date(byAdding: .day, value: cadence, to: outcome) ?? outcome
    }
    /// Rituals are tracked by when they were last kept, not by unrelated one-to-one contact.
    private func ritualReadyAt(_ ritual: ConnectionRitual, calendar: Calendar) -> Date {
        let base = lastOutcome(forIdea: ritual.id) ?? createdAt
        return calendar.date(byAdding: .day, value: ritual.cadenceDays, to: base) ?? base
    }
    private func lastOutcome(forIdea id: UUID) -> Date? {
        let explicit = feedback.filter { $0.ideaId == id && $0.signal == .done }.map(\.at)
        let shared = contacts.filter { $0.ideaId == id && $0.kind == .conversation }.map(\.date)
        return (explicit + shared).max()
    }
    private func timingMatches(_ timing: IdeaTiming, at date: Date, calendar: Calendar) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        let hour = calendar.component(.hour, from: date)
        let isWeekend = weekday == 1 || weekday == 7
        switch timing {
        case .anytime: return true
        case .weekend: return isWeekend
        case .weekday: return !isWeekend
        case .evening: return hour >= 17 || hour <= 4
        case .freeTime: return isWeekend || hour < 9 || hour >= 17
        }
    }

    public func suggestion(at now: Date = .now, calendar: Calendar = .current) -> RelationshipSuggestion {
        func result(_ action: RelationshipSuggestion.Action, _ title: String, _ reason: String, _ ready: Bool, _ date: Date? = nil, _ opportunity: ConnectionOpportunity? = nil) -> RelationshipSuggestion {
            .init(action: action, title: title, reason: reason, ready: ready, nextDate: date, opportunity: opportunity)
        }
        if paused { return result(.paused, "Check-ins paused", "Your notes and history are still here.", false) }
        if let snooze = snoozedUntil, calendar.startOfDay(for: snooze) > calendar.startOfDay(for: now) {
            return result(.later, "Time you've set aside", "You postponed this suggestion until \(snooze.formatted(date: .abbreviated, time: .omitted)).", false, snooze)
        }
        if !pendingIncoming.isEmpty {
            return result(.reply, "Reply to \(name)", "A message you recorded is open, if you’d like to reply. You can also leave it here.", true)
        }
        if intention == .space { return result(.giveSpace, "Give this relationship room", "You chose more space. There are no proactive outreach reminders; incoming messages can still prompt a reply.", false) }
        let ready = isReady(at: now, calendar: calendar)
        if !pendingOutreach.isEmpty {
            return result(.later, "You've reached out", "Your message is sent. There's nothing else to do here; new ideas can wait.", false)
        }
        if !activePlans.isEmpty {
            return result(.later, "You have something planned", "Enjoy the time you've arranged. No extra invitation needed.", false)
        }
        let idea = bestOpportunity(at: now, calendar: calendar)
        if let idea, ready {
            return grounded(idea, action(for: idea), now: now, calendar: calendar)
        }
        if !ready {
            let next = nextDue(calendar: calendar)
            // A recorded way of connecting can still be worth showing while the rhythm waits.
            let reason = "There is no particular opportunity to suggest today."
            return result(.later, idea?.prompt ?? "Room until your next check-in", reason, false, next, idea)
        }
        if intention == .unsure {
            return result(.reflect, "No particular idea right now", "You can keep this relationship open without choosing a direction.", false)
        }
        if passedOnAction(.hello) || passedOnAction(.timeTogether) {
            return result(.later, "No particular idea right now", "You've set the simple hello aside. Your people are still here whenever you want them.", false)
        }
        // A fallback lives on the person's page, never as an invented personalised opportunity.
        return result(.hello, "Say hello, if you feel like it", "There isn't a specific idea recorded for this person yet.", false)
    }
    /// Broad category tags and an arbitrary agent sentence do not establish shared history.
    private func isWorthOffering(_ idea: ConnectionIdea) -> Bool {
        let generic = ["make time together", "spend time together", "catch up", "a catch up", "send a hello", "send a small hello", "connect", "reconnect"]
        guard !generic.contains(AgentImportBatch.fingerprint(idea.activity)) else { return false }
        // Preserve imported text for review, but never automatically offer pressure or intimacy.
        guard isSafeConnectionText([idea.activity, idea.reminder, idea.reason].joined(separator: " ")) else { return false }
        if idea.confidence == .known { return true }
        let words = connection.interestKeywords
        let text = idea.activity.lowercased()
        return !idea.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || words.contains { text.contains($0) }
    }
    private func isSafeConnectionText(_ text: String) -> Bool {
        let wording = text.lowercased()
        let pressure = ["hug them", "give them a hug", "ask for a hug", "kiss them", "cuddle", "physical affection", "romantic intimacy", "sexual intimacy", "convince them", "keep messaging", "keep calling", "show up uninvited"]
        return !pressure.contains(where: wording.contains)
    }
    private func action(for idea: ConnectionOpportunity) -> RelationshipSuggestion.Action {
        if idea.isRitual { return .timeTogether }
        switch idea.kind {
        case .sharedActivity, .visit, .ritual: return .timeTogether
        case .call, .async, .gesture, .conversation: return .hello
        }
    }
    /// Turn a grounded idea into suggestion copy. Only states what the app actually knows.
    private func grounded(_ idea: ConnectionOpportunity, _ action: RelationshipSuggestion.Action, now: Date, calendar: Calendar) -> RelationshipSuggestion {
        // Unknown memories remain labelled as ideas; do not turn an agent's rationale into fact.
        let reason = idea.confidence == .known ? idea.reason : "An idea to consider, if it fits."
        return .init(action: action, title: idea.prompt, reason: reason, ready: true, nextDate: nil, opportunity: idea)
    }

}

public extension Array where Element == Person {
    /// People with a ready next step, reply requests first, then by the longest wait.
    func suggestedPeople(at now: Date = .now, calendar: Calendar = .current) -> [Person] {
        filter { $0.isDue(at: now, calendar: calendar) }.sorted {
            let left = $0.suggestion(at: now, calendar: calendar), right = $1.suggestion(at: now, calendar: calendar)
            if (left.action == .reply) != (right.action == .reply) { return left.action == .reply }
            if $0.lastActioned != $1.lastActioned { return ($0.lastActioned ?? .distantPast) < ($1.lastActioned ?? .distantPast) }
            if $0.nextDue(calendar: calendar) != $1.nextDue(calendar: calendar) { return $0.nextDue(calendar: calendar) < $1.nextDue(calendar: calendar) }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
    /// Everyone who has a recorded way of connecting, ready or not. Used for quiet suggestions.
    func peopleWithIdeas() -> [Person] { filter(\.openToIdeas) }
}
