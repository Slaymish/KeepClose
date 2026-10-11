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
    public var title: String { switch self { case .outreach: "I reached out"; case .incoming: "They reached out"; case .conversation: "We caught up"; case .reply: "I replied"; case .ambient: "Everyday contact" } }
}
public enum Initiator: String, Codable, CaseIterable, Sendable { case me, them, mutual, unknown }
public struct ContactEntry: Identifiable, Codable, Equatable, Sendable {
    public var id = UUID()
    public var date: Date
    public var note: String
    public var kind: ContactKind = .outreach
    public var initiator: Initiator = .me
    public var resolvedAt: Date?
    public var tracksResponse = true
    public init(date: Date, note: String, kind: ContactKind = .outreach, initiator: Initiator = .me) {
        self.date = date; self.note = note; self.kind = kind; self.initiator = initiator
    }
    private enum CodingKeys: String, CodingKey { case id, date, note, kind, initiator, resolvedAt, tracksResponse }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id); date = try c.decode(Date.self, forKey: .date); note = try c.decode(String.self, forKey: .note)
        kind = try c.decodeIfPresent(ContactKind.self, forKey: .kind) ?? .outreach
        initiator = try c.decodeIfPresent(Initiator.self, forKey: .initiator) ?? (kind == .incoming ? .them : .me)
        resolvedAt = try c.decodeIfPresent(Date.self, forKey: .resolvedAt)
        tracksResponse = try c.decodeIfPresent(Bool.self, forKey: .tracksResponse) ?? c.contains(.kind)
    }
}
public struct RelationshipSuggestion: Codable, Equatable, Sendable {
    public enum Action: String, Codable, Sendable { case reply, hello, takeInitiative, timeTogether, giveSpace, reflect, paused, later }
    public var action: Action
    public var title: String
    public var reason: String
    public var ready: Bool
    public var nextDate: Date?
}

public struct Person: Identifiable, Codable, Equatable, Sendable {
    public static let typeOptions = ["Friend", "Family", "Colleague", "Partner", "Acquaintance"]
    public static let contextOptions = ["Work", "Flatmate", "Online", "Hobby", "Nearby", "Another city"]
    public var id = UUID()
    public var name: String
    public var circle: String // Preserve the original free-form label.
    public var relationshipTypes: [String] = ["Friend"]
    public var contexts: [String] = []
    public var importSources: [String] = []
    public var intention: RelationshipIntention = .maintain
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

    public init(name: String, circle: String = "Friend", rhythmDays: Int = 14, method: ContactMethod = .message, address: String = "", context: String = "", createdAt: Date = .now) {
        self.name = name; self.circle = circle; self.relationshipTypes = [circle]; self.rhythmDays = max(1, rhythmDays)
        self.method = method; self.address = address; self.context = context; self.createdAt = createdAt
    }
    private enum CodingKeys: String, CodingKey { case id, name, circle, relationshipTypes, contexts, importSources, intention, rhythmDays, rhythmIsCustom, method, address, context, createdAt, contacts, snoozedUntil, deferrals, paused }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id); name = try c.decode(String.self, forKey: .name)
        circle = try c.decodeIfPresent(String.self, forKey: .circle) ?? "Friend"
        relationshipTypes = try c.decodeIfPresent([String].self, forKey: .relationshipTypes) ?? [circle]
        contexts = try c.decodeIfPresent([String].self, forKey: .contexts) ?? []
        importSources = try c.decodeIfPresent([String].self, forKey: .importSources) ?? []
        intention = try c.decodeIfPresent(RelationshipIntention.self, forKey: .intention) ?? .maintain
        rhythmDays = try c.decode(Int.self, forKey: .rhythmDays)
        rhythmIsCustom = try c.decodeIfPresent(Bool.self, forKey: .rhythmIsCustom) ?? true // Never change existing schedules on upgrade.
        method = try c.decode(ContactMethod.self, forKey: .method); address = try c.decode(String.self, forKey: .address)
        context = try c.decode(String.self, forKey: .context); createdAt = try c.decode(Date.self, forKey: .createdAt)
        contacts = try c.decodeIfPresent([ContactEntry].self, forKey: .contacts) ?? []
        snoozedUntil = try c.decodeIfPresent(Date.self, forKey: .snoozedUntil)
        deferrals = try c.decodeIfPresent(Int.self, forKey: .deferrals) ?? 0
        paused = try c.decodeIfPresent(Bool.self, forKey: .paused) ?? false
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
    public func suggestion(at now: Date = .now, calendar: Calendar = .current) -> RelationshipSuggestion {
        let next = nextDue(calendar: calendar)
        let ready = calendar.startOfDay(for: next) <= calendar.startOfDay(for: now)
        func result(_ action: RelationshipSuggestion.Action, _ title: String, _ reason: String, _ ready: Bool, _ date: Date? = nil) -> RelationshipSuggestion {
            .init(action: action, title: title, reason: reason, ready: ready, nextDate: date)
        }
        if paused { return result(.paused, "Check-ins paused", "Your notes and history are still here.", false) }
        if let snooze = snoozedUntil, calendar.startOfDay(for: snooze) > calendar.startOfDay(for: now) {
            return result(.later, "Time you've set aside", "You postponed this suggestion until \(snooze.formatted(date: .abbreviated, time: .omitted)).", false, snooze)
        }
        if !pendingIncoming.isEmpty {
            return result(.reply, "Reply to \(name)", "They reached out and you haven't logged a reply. Replying comes before starting another conversation.", true)
        }
        if intention == .space { return result(.giveSpace, "Give this relationship room", "You chose more space. There are no proactive outreach reminders; incoming messages can still prompt a reply.", false) }
        let response = contacts.filter { [.incoming, .conversation, .reply].contains($0.kind) }.map(\.date).max() ?? .distantPast
        let unanswered = contacts.filter { $0.kind == .outreach && $0.tracksResponse && $0.date > response }.count
        if unanswered >= 2 { return result(.giveSpace, "Give them room", "You've logged \(unanswered) outreach attempts without a later logged response or conversation. This is based only on what you recorded. Consider waiting; you can still reach out manually.", false) }
        if !ready { return result(.later, "Room until your next check-in", "Your last logged connection starts the next \(rhythmDays)-day rhythm.", false, next) }
        if intention == .unsure { return result(.reflect, "Decide what feels right", "You're unsure what you want for this relationship. Choose a direction, or keep it open without rushing to reach out.", true) }
        let starts = contacts.filter { entry in
            guard [.incoming, .outreach, .conversation].contains(entry.kind), [.me, .them].contains(entry.initiator) else { return false }
            // An incoming message plus its catch-up is one initiation, not two.
            return !(entry.kind == .conversation && entry.initiator == .them && contacts.contains { $0.kind == .incoming && $0.resolvedAt == entry.date })
        }.sorted { $0.date > $1.date }.prefix(3)
        if starts.count == 3 && starts.allSatisfy({ $0.initiator == .them }) {
            return result(.takeInitiative, "Take the initiative", "They started the last three recorded contacts. Your \(rhythmDays)-day check-in is ready; you could start this one.", true)
        }
        if intention == .grow { return result(.timeTogether, "Make time together", "You want to grow this relationship. Suggest a call, coffee, game or time together that fits \(contexts.isEmpty ? "how you connect" : contexts.joined(separator: ", ")).", true) }
        return result(.hello, "Send a small hello", "You want to maintain this relationship. Your chosen \(rhythmDays)-day rhythm is ready for a little connection.", true)
    }
    public func isDue(at now: Date = .now, calendar: Calendar = .current) -> Bool { suggestion(at: now, calendar: calendar).ready }
    public mutating func recordContact(at date: Date = .now, note: String = "", kind: ContactKind = .outreach, initiator: Initiator? = nil) {
        let starter = initiator ?? (kind == .incoming ? .them : kind == .conversation ? .unknown : kind == .ambient ? .mutual : kind == .reply ? .them : .me)
        var entry = ContactEntry(date: date, note: note, kind: kind, initiator: starter)
        if kind == .incoming {
            entry.resolvedAt = contacts.filter { [.reply, .conversation].contains($0.kind) && $0.date >= date }.map(\.date).min()
        }
        contacts.append(entry)
        if kind == .reply || kind == .conversation {
            for i in contacts.indices where contacts[i].kind == .incoming && contacts[i].date <= date && contacts[i].resolvedAt == nil { contacts[i].resolvedAt = date }
        }
        if [.outreach, .reply, .conversation].contains(kind) { snoozedUntil = nil; deferrals = 0 }
    }
    public mutating func resolveIncoming(_ id: UUID, at date: Date = .now) {
        if let i = contacts.firstIndex(where: { $0.id == id && $0.kind == .incoming }) { contacts[i].resolvedAt = date }
    }
    public mutating func deferContact(until date: Date) { snoozedUntil = date; deferrals += 1 }
    public var smallStep: String {
        if !pendingIncoming.isEmpty { return "A short acknowledgement is enough to start a reply." }
        switch method {
        case .message: return "Send a quick hello. You don't need a big update."
        case .call: return "Send a message asking when a short call would suit."
        case .email: return "A two-line email is enough to open the conversation."
        case .inPerson: return "Suggest a coffee or a short walk."
        }
    }
}

public extension Array where Element == Person {
    func suggestedPeople(at now: Date = .now, calendar: Calendar = .current) -> [Person] {
        filter { $0.isDue(at: now, calendar: calendar) }.sorted {
            let left = $0.suggestion(at: now, calendar: calendar), right = $1.suggestion(at: now, calendar: calendar)
            if (left.action == .reply) != (right.action == .reply) { return left.action == .reply }
            return $0.nextDue(calendar: calendar) < $1.nextDue(calendar: calendar)
        }
    }
}
