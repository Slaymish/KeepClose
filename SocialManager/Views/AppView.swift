import SwiftUI

@main struct KeepCloseApp: App {
    @State private var store = RelationshipStore()
    @State private var appLock = AppLockController()
    #if os(macOS)
    private let updater = AppUpdater()
    #endif
    var body: some Scene {
        WindowGroup { ProtectedAppView().environment(store).environment(appLock).modifier(KeepCloseSyncLifecycle()) }
        #if os(macOS)
        .commands {
            CommandGroup(after: .appInfo) { CheckForUpdatesView(updater: updater) }
        }
        #endif
    }
}

struct AppView: View {
    @Environment(RelationshipStore.self) private var store
    @Environment(AppLockController.self) private var appLock
    @State private var page: String? = "Today"
    @State private var editing: Person?
    @State private var showingAdd = false
    @State private var categoryFilter: String?
    @State private var importProvider: ImportProvider?
    var body: some View {
        @Bindable var store = store
        NavigationSplitView {
            List(selection: $page) {
                Label("Today", systemImage: "sun.max").tag("Today")
                Label("People", systemImage: "person.2").tag("People")
                Label("Preferences", systemImage: "slider.horizontal.3").tag("Preferences")
            }
            .navigationTitle("Keep Close")
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            NavigationStack {
                Group {
                    if page == "Preferences" { preferences }
                    else if store.people.isEmpty { emptyState }
                    else if page == "People" { peopleList }
                    else { today }
                }
                .navigationTitle(page ?? "Today")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) { importMenu }
                    ToolbarItem(placement: .primaryAction) { Button("Add person", systemImage: "plus") { showingAdd = true } }
                }
            }
        }
        .tint(.teal)
        .sheet(isPresented: $showingAdd) { PersonEditor(person: Person(name: "")) }
        .sheet(item: $editing) { PersonEditor(person: $0) }
        .sheet(item: $importProvider) { AgentImportView(provider: $0) }
        .alert("Something needs attention", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: { Text(store.error ?? "") }
        #if os(macOS)
        .frame(minWidth: 760, minHeight: 560)
        #endif
    }
    private var importMenu: some View {
        Menu {
            ForEach(ImportProvider.allCases) { provider in
                Button("\(store.hasImported(provider) ? "Update" : "Import") from \(provider.title)…") { importProvider = provider }
            }
        } label: {
            #if os(macOS)
            HStack(spacing: 6) { Image(systemName: "square.and.arrow.down"); Text(store.hasImported(.chatgpt) ? "Update from ChatGPT" : "Import from ChatGPT") }
            #else
            Label(store.hasImported(.chatgpt) ? "Update from ChatGPT" : "Import from ChatGPT", systemImage: "square.and.arrow.down")
            #endif
        }
    }
    private var emptyState: some View {
        ContentUnavailableView {
            Label("Make room for your people", systemImage: "person.2.circle")
        } description: {
            Text("Start with one person. Choose who they are to you and what you'd like for the relationship, and add a few things you enjoy doing together. You can change your mind any time.")
        } actions: {
            Button("Import from ChatGPT") { importProvider = .chatgpt }.buttonStyle(.borderedProminent)
            Button("Add a person yourself") { showingAdd = true }.buttonStyle(.bordered)
        }
    }
    private var today: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if store.due.isEmpty { quietToday } else { opportunities }
                ideasWorthRemembering
                Text("Suggestions come from what you record here: notes, shared interests, things you've enjoyed together. Nothing is sent anywhere unless you copy an import prompt yourself.")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding(28).frame(maxWidth: 820, alignment: .leading).frame(maxWidth: .infinity)
        }
    }
    private var opportunities: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("A moment with someone").font(.largeTitle.bold())
                Text(store.due.count == 1 ? "One way in, if you feel like it." : "A few ways in. Pick one, or none.").foregroundStyle(.secondary)
            }
            ForEach(Array(store.due.prefix(3))) { person in
                PersonCard(person: person, edit: { editing = person })
            }
            if store.due.count > 3 {
                Text("\(store.due.count - 3) more people have something ready when you want it. They'll keep.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }
    private var quietToday: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Nothing needs doing today").font(.largeTitle.bold())
            Text("That's the good outcome, not a gap to fill. If you'd like company anyway, these are open.")
                .foregroundStyle(.secondary)
            ForEach(store.quietSuggestions) { person in
                QuietSuggestionRow(person: person) { editing = person }
            }
            if store.quietSuggestions.isEmpty {
                Text("Add something you enjoy doing with someone and Keep Close will surface it as an idea rather than a reminder.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("See your people") { page = "People" }.buttonStyle(.bordered)
            }
        }
    }
    /// Rituals and ideas that exist even when nobody is "due". Optional, never urgent.
    @ViewBuilder private var ideasWorthRemembering: some View {
        if !store.rituals.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Patterns worth keeping").font(.headline)
                ForEach(store.rituals.prefix(4)) { ritual in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: "repeat").foregroundStyle(.teal)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(ritual.title)
                            if !ritual.note.isEmpty { Text(ritual.note).font(.caption).foregroundStyle(.secondary) }
                            Text(ritual.days == nil ? "No set frequency" : "Roughly every \(ritual.days!) days").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(ritual.who).font(.caption).foregroundStyle(.secondary)
                    }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.teal.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }
    private var peopleList: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    Button("Everyone") { categoryFilter = nil }.buttonStyle(.bordered).tint(categoryFilter == nil ? .teal : .gray)
                    ForEach(Array(Set(store.people.flatMap { $0.relationshipTypes + $0.contexts })).sorted(), id: \.self) { tag in
                        Button(tag) { categoryFilter = categoryFilter == tag ? nil : tag }.buttonStyle(.bordered).tint(categoryFilter == tag ? .teal : .gray)
                    }
                }.padding()
            }
            List {
                ForEach(IntentionGroup.order, id: \.self) { intention in
                    let people = store.people.filter { $0.intention == intention && (categoryFilter == nil || ($0.relationshipTypes + $0.contexts).contains(categoryFilter!)) }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                    if !people.isEmpty {
                        Section {
                            ForEach(people) { person in
                                NavigationLink {
                                    ScrollView { PersonCard(person: person, edit: { editing = person }, showsHistory: true).padding(24) }
                                } label: { PersonRow(person: person) }
                            }
                        } header: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(intention.title)
                                Text(IntentionGroup.blurb(intention)).font(.caption).foregroundStyle(.secondary).textCase(nil)
                            }
                        }
                    }
                }
            }
        }
    }
    private var preferences: some View {
        Form {
            Section("App lock") {
                Toggle("Require authentication to open Keep Close", isOn: Binding(get: { appLock.enabled }, set: { enabled in Task { await appLock.authenticate(enabled ? .enable : .disable) } }))
                    .disabled(appLock.authenticating)
                Text("Use Face ID or Touch ID where available, with your device passcode or Mac login password as the fallback. The app locks when you leave it.").font(.caption).foregroundStyle(.secondary)
                if appLock.enabled { Button("Lock now", systemImage: "lock") { appLock.lock() } }
                if let message = appLock.message { Text(message).font(.caption).foregroundStyle(.red) }
                Text("This protects the app's screens. Local agents retain access through your CLI.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Notification privacy") {
                Toggle("Show names only in unlocked previews", isOn: Binding(get: { store.includeNamesInReminders }, set: { value in Task { await store.setNotificationNames(value) } }))
                    .disabled(store.reminderBusy)
                Text(store.previewPrivacyMessage).font(.caption).foregroundStyle(.secondary)
                Button("Open notification settings") { store.openNotificationSettings() }
                Text("Choose Show Previews → When Unlocked for Keep Close. Keep that setting selected for named reminders already scheduled by the OS. Turn off names here to keep all reminders generic.").font(.caption).foregroundStyle(.secondary)
            }
            Section("A gentle nudge") {
                Toggle("Daily reminder", isOn: Binding(get: { store.reminderEnabled }, set: { value in Task { await store.setReminder(value) } }))
                .disabled(store.reminderBusy)
                DatePicker("Reminder time", selection: Binding(get: {
                    Calendar.current.date(from: DateComponents(year: 2001, month: 1, day: 1, hour: store.reminderHour, minute: store.reminderMinute)) ?? .now
                }, set: { date in
                    let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                    store.reminderHour = parts.hour ?? 18; store.reminderMinute = parts.minute ?? 0
                    Task { await store.setReminder(store.reminderEnabled) }
                }), displayedComponents: .hourAndMinute)
                .disabled(store.reminderBusy)
                if !store.reminderMessage.isEmpty { Text(store.reminderMessage).font(.caption).foregroundStyle(.secondary) }
                Text("One quiet reminder a day at most, inviting you to open Keep Close if it suits. It never counts up, never escalates, and skipping it means nothing.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Device sync") {
                NavigationLink("Sync with your other device") { KeepCloseSyncSettings() }
            }
            Section("What leaves this device") {
                Text("Relationships, notes, memories and ideas are saved locally. If you enable Device sync, shared records are exchanged automatically with your paired device on the same network.")
                Text("Nothing is sent to ChatGPT, Claude or anywhere else automatically. When you copy an import prompt, it contains your notes and recorded context — only share it with a chat you're happy to have that information.").font(.callout)
                Text("The app opens your chosen contact app. You send the message yourself, then log it here if you want to.").font(.callout)
            }
        }.formStyle(.grouped)
    }
}

enum IntentionGroup {
    static let order: [RelationshipIntention] = [.grow, .maintain, .unsure, .space]
    static func blurb(_ intention: RelationshipIntention) -> String {
        switch intention {
        case .grow: "You'd like to invest more here."
        case .maintain: "Let this stay part of your life."
        case .unsure: "Still deciding what fits."
        case .space: "No nudges to reach out. Their messages can still reach you."
        }
    }
}

struct Avatar: View {
    let name: String
    var body: some View {
        Text(name.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined())
            .font(.headline).foregroundStyle(.teal).frame(width: 44, height: 44)
            .background(.teal.opacity(0.1), in: Circle()).accessibilityHidden(true)
    }
}

struct PersonRow: View {
    let person: Person
    var body: some View {
        HStack(spacing: 14) {
            Avatar(name: person.name)
            VStack(alignment: .leading, spacing: 4) {
                Text(person.name).font(.headline)
                Text((person.relationshipTypes + person.contexts).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !person.visibleIdeas.isEmpty {
                Label("\(person.visibleIdeas.count)", systemImage: "sparkles").font(.caption).foregroundStyle(.teal)
                    .accessibilityLabel("\(person.visibleIdeas.count) recorded ways to connect")
            }
            Text(person.paused ? "Paused" : person.suggestion().title).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
        }.padding(.vertical, 6)
    }
}

/// A light row used when nothing is pressing: an invitation, not an instruction.
struct QuietSuggestionRow: View {
    @Environment(RelationshipStore.self) private var store
    let person: Person
    let edit: () -> Void
    private var current: Person { store.people.first { $0.id == person.id } ?? person }
    var body: some View {
        let person = current
        let opportunity = person.bestOpportunity()
        Button(action: edit) {
            HStack(alignment: .top, spacing: 12) {
                Avatar(name: person.name)
                VStack(alignment: .leading, spacing: 4) {
                    Text(person.name).font(.headline)
                    Text(opportunity?.prompt ?? person.suggestion().title).font(.callout)
                    if let reason = opportunity?.reason, !reason.isEmpty {
                        Text(reason).font(.caption).foregroundStyle(.secondary)
                    }
                    if let opportunity { Text(opportunity.provenance).font(.caption2).foregroundStyle(.secondary) }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(.background, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(.primary.opacity(0.1)))
        }.buttonStyle(.plain)
    }
}

struct PersonCard: View {
    @Environment(RelationshipStore.self) private var store
    @Environment(\.openURL) private var openURL
    let person: Person
    let edit: () -> Void
    var showsHistory = false
    @State private var logKind: ContactKind?
    @State private var openFailed = false
    @State private var editingContext = false
    private var current: Person { store.people.first { $0.id == person.id } ?? person }
    var body: some View {
        let person = current
        let suggestion = person.suggestion()
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Avatar(name: person.name)
                VStack(alignment: .leading, spacing: 4) {
                    Text(person.name).font(.title2.bold())
                    Text(person.intention.title).font(.subheadline).foregroundStyle(.teal)
                }
                Spacer()
                Button("Edit", action: edit).buttonStyle(.borderless)
            }
            if !(person.relationshipTypes + person.contexts).isEmpty {
                Text((person.relationshipTypes + person.contexts).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
            }
            contextHighlights(person)
            VStack(alignment: .leading, spacing: 6) {
                Text(suggestion.title).font(.headline)
                Text(suggestion.reason).font(.callout).foregroundStyle(.secondary)
                if let opportunity = suggestion.opportunity, !opportunity.grounded {
                    Text("Nothing else recorded about this yet. Edit the idea if it isn't right.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let date = suggestion.nextDate, !suggestion.ready {
                    Text("Next gentle prompt: \(date.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.secondary)
                }
            }.padding().frame(maxWidth: .infinity, alignment: .leading).background(.teal.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            if !person.context.isEmpty { Text(person.context).font(.callout) }
            if !person.contacts.isEmpty {
                Text("Last connection: \(person.lastContact.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "nothing logged yet")\(person.lastIncoming.map { " · they last reached out \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ViewThatFits(in: .horizontal) {
                HStack { actions(person) }
                VStack(alignment: .leading, spacing: 12) { actions(person) }
            }
            if let opportunity = suggestion.opportunity, suggestion.ready {
                feedbackRow(person, opportunity)
            }
            if !person.importSources.isEmpty {
                Text("Imported from \(person.importSources.joined(separator: ", "))").font(.caption2).foregroundStyle(.secondary)
            }
            if showsHistory, !person.contacts.isEmpty { history(person) }
            if !showsHistory, !person.contacts.isEmpty {
                DisclosureGroup("Connection history (\(person.contacts.count))") { historyList(person) }.font(.callout)
            }
        }.padding(22).background(.background, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(.primary.opacity(0.12)))
            .sheet(item: $logKind) { kind in ContactLogger(person: current, initialKind: kind) }
            .sheet(isPresented: $editingContext) { ConnectionContextView(person: current) }
            .alert("Couldn't open the contact app", isPresented: $openFailed) { Button("OK", role: .cancel) {} } message: { Text("Check this person's contact details, or reach out using your usual app.") }
    }
    /// Names, interests and memories, so a suggestion has something human behind it.
    @ViewBuilder private func contextHighlights(_ person: Person) -> some View {
        if !person.interests.isEmpty || !person.memories.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if !person.interests.isEmpty {
                    Text(person.interests.prefix(4).map(\.name).joined(separator: " · ")).font(.callout)
                }
                ForEach(person.memories.suffix(2)) { memory in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "bookmark").font(.caption).foregroundStyle(.teal)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(memory.text).font(.callout)
                            Text(memory.provenance).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                Button(person.connection.isEmpty ? "Add what you share" : "Ways to connect (\(person.visibleIdeas.count))") { editingContext = true }.buttonStyle(.borderless).font(.callout)
            }
        } else {
            Button("Add something you share") { editingContext = true }.buttonStyle(.borderless).font(.callout)
        }
    }
    @ViewBuilder private func feedbackRow(_ person: Person, _ opportunity: ConnectionOpportunity) -> some View {
        HStack(spacing: 12) {
            Button("Useful") { store.update(person.id) { $0.recordFeedback(.helpful, ideaId: opportunity.ideaId) } }.buttonStyle(.borderless).font(.caption)
            Button("I did this") { store.update(person.id) { $0.recordFeedback(.done, ideaId: opportunity.ideaId) } }.buttonStyle(.borderless).font(.caption)
            Button("Not for me") { store.update(person.id) { $0.dismissIdea(opportunity.ideaId); $0.recordFeedback(.notForMe, ideaId: opportunity.ideaId) } }.buttonStyle(.borderless).font(.caption)
            Spacer()
            Text("Only stored on this device").font(.caption2).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder private func actions(_ person: Person) -> some View {
        if person.suggestion().action == .reflect { Button("Choose a direction", action: edit).buttonStyle(.borderedProminent) }
        if person.method != .inPerson && !person.address.isEmpty {
            Button(person.pendingIncoming.isEmpty ? "Open \(person.method.rawValue)" : "Open to reply", systemImage: "arrow.up.forward.app") { launch(person) }.buttonStyle(.borderedProminent)
        }
        Button("Log contact", systemImage: "checkmark") { logKind = person.pendingIncoming.isEmpty ? .outreach : .reply }.buttonStyle(.bordered)
        Button("They reached out") { logKind = .incoming }.buttonStyle(.bordered)
        if person.suggestion().ready {
            Menu("Later") {
                Button("Tomorrow") { snooze(person, 1) }
                Button("In three days") { snooze(person, 3) }
                Button("Next week") { snooze(person, 7) }
            }.buttonStyle(.bordered)
        }
    }
    @ViewBuilder private func history(_ person: Person) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Connection history").font(.headline)
            historyList(person)
        }
    }
    @ViewBuilder private func historyList(_ person: Person) -> some View {
        ForEach(person.contacts.sorted { $0.date > $1.date }) { entry in
            VStack(alignment: .leading, spacing: 4) {
                Text("\(entry.kind.title) · \(entry.date.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.secondary)
                if entry.kind == .conversation { Text("Started by: \(entry.initiator.rawValue)").font(.caption).foregroundStyle(.secondary) }
                if !entry.note.isEmpty { Text(entry.note) }
                if entry.kind == .incoming && entry.resolvedAt == nil {
                    Button("No reply needed") { store.update(person.id) { $0.resolveIncoming(entry.id) } }.buttonStyle(.borderless)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
        }
    }
    private func snooze(_ person: Person, _ days: Int) {
        let until = Calendar.current.date(byAdding: .day, value: days, to: .now) ?? .now
        store.update(person.id) { person in
            person.snooze(until: until)
            if let idea = person.suggestion().opportunity { person.recordFeedback(.snoozed, ideaId: idea.ideaId) }
        }
    }
    private func launch(_ person: Person) {
        let scheme = person.method == .email ? "mailto" : person.method == .call ? "tel" : "sms"
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "?#&"))
        guard let encoded = person.address.addingPercentEncoding(withAllowedCharacters: allowed), let url = URL(string: "\(scheme):\(encoded)") else { openFailed = true; return }
        openURL(url) { accepted in if !accepted { openFailed = true } }
    }
}

struct ContactLogger: View {
    @Environment(RelationshipStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let person: Person
    @State private var kind: ContactKind
    @State private var initiator: Initiator = .unknown
    @State private var contactDate = Date.now
    @State private var note = ""
    init(person: Person, initialKind: ContactKind) { self.person = person; _kind = State(initialValue: initialKind) }
    var body: some View {
        NavigationStack {
            Form {
                Picker("What happened?", selection: $kind) { ForEach(ContactKind.allCases, id: \.self) { Text($0.title).tag($0) } }
                if kind == .conversation {
                    Picker("Who started it?", selection: $initiator) {
                        Text("Me").tag(Initiator.me); Text("Them").tag(Initiator.them)
                        Text("Both / naturally").tag(Initiator.mutual); Text("Not sure").tag(Initiator.unknown)
                    }
                }
                DatePicker("When", selection: $contactDate, in: ...Date.now, displayedComponents: .date)
                TextField("Something to remember (optional)", text: $note, axis: .vertical)
                Text(kind == .incoming ? "This creates a reply suggestion. If you already replied, log a reply or catch-up too." : kind == .ambient ? "Seeing each other in passing won't restart the rhythm for a proper connection." : kind == .reply ? "This records your reply and closes earlier incoming messages. You don't need to wait for another reply." : "Record what actually happened. A catch-up counts whoever started it.").font(.caption).foregroundStyle(.secondary)
            }.formStyle(.grouped).navigationTitle("Contact with \(person.name)")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") {
                        if store.update(person.id, change: { $0.recordContact(at: contactDate, note: note, kind: kind, initiator: kind == .conversation ? initiator : nil) }) { dismiss() }
                    } }
                }
        }
        #if os(macOS)
        .frame(width: 520, height: 380)
        #endif
    }
}

/// Review and edit what Keep Close remembers, and the ways of connecting it can offer.
struct ConnectionContextView: View {
    @Environment(RelationshipStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let person: Person
    @State private var editingIdea: ConnectionIdea?
    @State private var editingMemory: ConnectionMemory?
    @State private var editingInterest: ConnectionInterest?
    @State private var newRitual = ""
    @State private var newRitualDays = 7
    @State private var showingDismissed = false
    private var current: Person { store.people.first { $0.id == person.id } ?? person }
    var body: some View {
        let person = current
        NavigationStack {
            Form {
                Section {
                    Text("These stay on this device. Suggestions use them so a prompt can mention something real instead of counting days.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Ways to connect") {
                    if person.visibleIdeas.isEmpty {
                        Text("Nothing recorded yet. Add something you enjoy doing together, or import ideas from ChatGPT or Claude.").foregroundStyle(.secondary)
                    }
                    ForEach(person.visibleIdeas) { idea in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(idea.title).font(.headline)
                            if !idea.reason.isEmpty { Text(idea.reason).font(.callout).foregroundStyle(.secondary) }
                            HStack(spacing: 8) {
                                Text(idea.kind.title).font(.caption2).foregroundStyle(.secondary)
                                Text(idea.provenance).font(.caption2).foregroundStyle(.secondary)
                            }
                            HStack(spacing: 14) {
                                Button("Edit") { editingIdea = idea }.buttonStyle(.borderless).font(.caption)
                                Button("Set aside") { store.update(person.id) { $0.dismissIdea(idea.id); $0.recordFeedback(.notForMe, ideaId: idea.id) } }.buttonStyle(.borderless).font(.caption)
                                Button("Delete", role: .destructive) { store.update(person.id) { $0.removeIdea(idea.id) } }.buttonStyle(.borderless).font(.caption)
                            }
                        }.padding(.vertical, 4)
                    }
                    Button("Add a way to connect", systemImage: "plus") { editingIdea = ConnectionIdea(kind: .sharedActivity, activity: "", sources: [.me], confidence: .known) }
                    if person.dismissedIdeaCount > 0 {
                        DisclosureGroup(showingDismissed ? "Set aside (\(person.dismissedIdeaCount))" : "\(person.dismissedIdeaCount) set aside", isExpanded: $showingDismissed) {
                            ForEach(person.ideas.filter(\.dismissed)) { idea in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(idea.activity).font(.callout)
                                        Text("Imports won't suggest this again").font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("Bring back") { store.update(person.id) { $0.restoreIdea(idea.id) } }.buttonStyle(.borderless).font(.caption)
                                }
                            }
                            Text("Set-aside ideas stay set aside even when an agent imports them again.").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Shared interests") {
                    ForEach(person.interests) { interest in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(interest.name)
                                if !interest.detail.isEmpty { Text(interest.detail).font(.caption).foregroundStyle(.secondary) }
                                Text(interest.provenance).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Edit") { editingInterest = interest }.buttonStyle(.borderless).font(.caption)
                            Button("Delete", role: .destructive) { store.update(person.id) { $0.removeInterest(interest.id) } }.buttonStyle(.borderless).font(.caption)
                        }
                    }
                    Button("Add an interest", systemImage: "plus") { editingInterest = ConnectionInterest(name: "", confidence: .known) }
                }
                Section("Things worth remembering") {
                    ForEach(person.memories) { memory in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(memory.text).font(.callout)
                            Text(memory.provenance + (memory.date.map { " · \($0.formatted(date: .abbreviated, time: .omitted))" } ?? ""))
                                .font(.caption2).foregroundStyle(.secondary)
                            HStack(spacing: 14) {
                                Button("Edit") { editingMemory = memory }.buttonStyle(.borderless).font(.caption)
                                Button("Forget", role: .destructive) { store.update(person.id) { $0.forgetMemory(memory.id) } }.buttonStyle(.borderless).font(.caption)
                            }
                        }.padding(.vertical, 3)
                    }
                    Button("Add a memory", systemImage: "plus") { editingMemory = ConnectionMemory(text: "", confidence: .known) }
                }
                Section("Recurring patterns") {
                    ForEach(person.rituals) { ritual in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ritual.title)
                                if !ritual.note.isEmpty { Text(ritual.note).font(.caption).foregroundStyle(.secondary) }
                                Text(ritual.days == nil ? "No set frequency" : "Roughly every \(ritual.days!) days").font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Delete", role: .destructive) { store.update(person.id) { $0.removeRitual(ritual.id) } }.buttonStyle(.borderless).font(.caption)
                        }
                    }
                    HStack {
                        TextField("A regular game night, a Sunday walk…", text: $newRitual)
                        Button("Add") {
                            let title = newRitual.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !title.isEmpty else { return }
                            store.update(person.id) { $0.addRitual(title: title, days: newRitualDays) }
                            newRitual = ""
                        }.disabled(newRitual.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    Stepper("Roughly every \(newRitualDays) days", value: $newRitualDays, in: 1...365)
                    Text("A pattern is a standing invitation, not a calendar commitment. Keep Close never treats a missed one as a failure.").font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped).navigationTitle("About \(person.name)")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .sheet(item: $editingIdea) { IdeaEditor(person: current, idea: $0) }
                .sheet(item: $editingMemory) { MemoryEditor(person: current, memory: $0) }
                .sheet(item: $editingInterest) { InterestEditor(person: current, interest: $0) }
        }
        #if os(macOS)
        .frame(width: 620, height: 700)
        #endif
    }
}

struct IdeaEditor: View {
    @Environment(RelationshipStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let person: Person
    @State var idea: ConnectionIdea
    @State private var timingChoice: String
    @State private var cadenceChoice: String
    private var exists: Bool { person.connection.idea(idea.id) != nil }
    init(person: Person, idea: ConnectionIdea) {
        self.person = person
        _idea = State(initialValue: idea)
        _timingChoice = State(initialValue: idea.timing?.rawValue ?? "none")
        _cadenceChoice = State(initialValue: idea.cadenceDays.map(String.init) ?? "none")
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("What you'd enjoy") {
                    TextField("A walk along the canal, a board game evening…", text: $idea.activity, axis: .vertical)
                    Picker("Kind", selection: $idea.kind) { ForEach(IdeaKind.allCases) { Text($0.title).tag($0) } }
                    TextField("How you'd put it (optional)", text: $idea.reminder)
                    Text("Leave the wording empty and Keep Close repeats your own phrase rather than writing one for you.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Why it might be welcome") {
                    TextField("Something you both enjoyed, or a shared interest", text: $idea.reason, axis: .vertical)
                    Picker("Usually suits", selection: $timingChoice) {
                        Text("No particular time").tag("none")
                        ForEach(IdeaTiming.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    Picker("Come round again", selection: $cadenceChoice) {
                        Text("Use my overall rhythm").tag("none")
                        ForEach([7, 14, 30, 90], id: \.self) { Text("Roughly every \($0) days").tag(String($0)) }
                    }
                    if let source = idea.sources.first, source != .me {
                        Text("Currently marked as \(source.attribution). Saving your edits marks it as yours.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section {
                    Button("Set this aside", role: .destructive) {
                        store.update(person.id) { $0.dismissIdea(idea.id); $0.recordFeedback(.notForMe, ideaId: idea.id) }
                        dismiss()
                    }
                    Text("Setting aside keeps the idea out of suggestions and stops imports bringing it back. It doesn't count as anything.").font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped).navigationTitle(exists ? "Edit idea" : "New idea")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") {
                        let timing = IdeaTiming(rawValue: timingChoice)
                        let cadence = Int(cadenceChoice)
                        let activity = idea.activity.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !activity.isEmpty else { return }
                        store.update(person.id) { person in
                            if person.updateIdea(idea.id, activity: activity, reminder: idea.reminder, reason: idea.reason, kind: idea.kind, timing: .some(timing), cadenceDays: .some(cadence), occasions: idea.occasions) { return }
                            person.addIdea(kind: idea.kind, activity: activity, reminder: idea.reminder, reason: idea.reason, timing: timing, occasions: idea.occasions, cadenceDays: cadence)
                        }
                        dismiss()
                    }.disabled(idea.activity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }
        }
        #if os(macOS)
        .frame(width: 540, height: 520)
        #endif
    }
}

struct MemoryEditor: View {
    @Environment(RelationshipStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let person: Person
    @State var memory: ConnectionMemory
    @State private var hasDate: Bool
    @State private var date: Date
    private var exists: Bool { person.memories.contains { $0.id == memory.id } }
    init(person: Person, memory: ConnectionMemory) {
        self.person = person
        _memory = State(initialValue: memory)
        _hasDate = State(initialValue: memory.date != nil)
        _date = State(initialValue: memory.date ?? .now)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Something you remember") {
                    TextField("What happened, or something you'd like to ask about", text: $memory.text, axis: .vertical).lineLimit(3...6)
                }
                Section {
                    Toggle("Add a date", isOn: $hasDate)
                    if hasDate { DatePicker("Around", selection: $date, in: ...Date.now, displayedComponents: .date) }
                    Text("Dates are optional. A rough memory without a date is still useful.").font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped).navigationTitle(exists ? "Edit memory" : "New memory")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") {
                        let text = memory.text.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !text.isEmpty else { return }
                        store.update(person.id) { person in
                            if person.updateMemory(memory.id, text: text, date: .some(hasDate ? date : nil)) { return }
                            person.addMemory(text, date: hasDate ? date : nil)
                        }
                        dismiss()
                    }.disabled(memory.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }
        }
        #if os(macOS)
        .frame(width: 520, height: 360)
        #endif
    }
}

struct InterestEditor: View {
    @Environment(RelationshipStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let person: Person
    @State var interest: ConnectionInterest
    private var exists: Bool { person.interests.contains { $0.id == interest.id } }
    var body: some View {
        NavigationStack {
            Form {
                Section("What you share") {
                    TextField("Board games, running, old films…", text: $interest.name)
                    TextField("Anything worth remembering about it (optional)", text: $interest.detail, axis: .vertical)
                }
            }.formStyle(.grouped).navigationTitle(exists ? "Edit interest" : "New interest")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") {
                        let name = interest.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty else { return }
                        store.update(person.id) { person in
                            if person.updateInterest(interest.id, name: name, detail: interest.detail) { return }
                            person.addInterest(name, detail: interest.detail)
                        }
                        dismiss()
                    }.disabled(interest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }
        }
        #if os(macOS)
        .frame(width: 520, height: 300)
        #endif
    }
}

struct CategoryChips: View {
    let options: [String]
    @Binding var selection: [String]
    @State private var custom = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))], alignment: .leading, spacing: 8) {
                ForEach(Array(Set(options + selection)).sorted(), id: \.self) { tag in
                    Button {
                        if selection.contains(tag) { selection.removeAll { $0 == tag } } else { selection.append(tag) }
                    } label: {
                        HStack(spacing: 5) { if selection.contains(tag) { Image(systemName: "checkmark") }; Text(tag) }.frame(maxWidth: .infinity).padding(.vertical, 6)
                    }.buttonStyle(.bordered).tint(selection.contains(tag) ? .teal : .gray)
                    .accessibilityLabel(tag).accessibilityValue(selection.contains(tag) ? "Selected" : "Not selected")
                }
            }
            HStack {
                TextField("Your own category", text: $custom)
                Button("Add") {
                    let value = custom.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !value.isEmpty && !selection.contains(value) { selection.append(value) }; custom = ""
                }.disabled(custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(.vertical, 6)
    }
}

struct PersonEditor: View {
    @Environment(RelationshipStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var person: Person
    private let original: Person
    init(person: Person) { _person = State(initialValue: person); original = person }
    @State private var deleting = false
    private var exists: Bool { store.people.contains { $0.id == person.id } }
    var body: some View {
        NavigationStack {
            Form {
                Section { TextField("Name", text: $person.name) }
                Section("Who are they to you?") {
                    CategoryChips(options: Person.typeOptions, selection: $person.relationshipTypes)
                    Text("Choose more than one, or add your own. A colleague can be a close friend too.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Where your lives overlap") { CategoryChips(options: Person.contextOptions, selection: $person.contexts) }
                Section("What would you like for this relationship?") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(RelationshipIntention.allCases, id: \.self) { intention in
                            Button { person.chooseIntention(intention) } label: {
                                HStack { if person.intention == intention { Image(systemName: "checkmark") }; Text(intention.title) }.frame(maxWidth: .infinity).padding(.vertical, 8)
                            }.buttonStyle(.bordered).tint(person.intention == intention ? .teal : .gray)
                            .accessibilityValue(person.intention == intention ? "Selected" : "Not selected")
                        }
                    }
                    Text(intentionExplanation).font(.caption).foregroundStyle(.secondary)
                }
                Section("Keep the nuance") { TextField("Things to remember, ask about, or understand", text: $person.context, axis: .vertical).lineLimit(3...6) }
                Section("How you connect") {
                    Picker("Prefer", selection: $person.method) { ForEach(ContactMethod.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    if person.method != .inPerson { TextField(person.method == .email ? "Email address" : "Phone number", text: $person.address) }
                }
                Section {
                    Text("\(person.rhythmIsCustom ? "Your rhythm" : "Starting rhythm"): every \(person.rhythmDays) days").font(.callout)
                    DisclosureGroup("Adjust the rhythm") {
                        Stepper("Every \(person.rhythmDays) days", value: Binding(get: { person.rhythmDays }, set: { person.rhythmDays = $0; person.rhythmIsCustom = true }), in: 1...365)
                        Button("Use suggested rhythm (\(person.suggestedRhythm) days)") { person.applySuggestedRhythm() }
                        Text("A rhythm decides when a gentle prompt appears, not what you should say or whether you should reach out. Nothing becomes overdue here. Actual contact history determines the next suggestion.").font(.caption).foregroundStyle(.secondary)
                    }
                    Toggle("Pause all suggestions", isOn: $person.paused)
                }
                if exists { Section { Button("Delete person", role: .destructive) { deleting = true } } }
            }.formStyle(.grouped).navigationTitle(exists ? "Edit person" : "Add person")
                .onChange(of: person.relationshipTypes) { _, _ in refreshRhythm() }
                .onChange(of: person.contexts) { _, _ in refreshRhythm() }
                .onChange(of: person.intention) { _, _ in refreshRhythm() }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") {
                        person.name = person.name.trimmingCharacters(in: .whitespacesAndNewlines); person.address = person.address.trimmingCharacters(in: .whitespacesAndNewlines)
                        person.circle = person.relationshipTypes.joined(separator: ", ")
                        person.intentionChosen = true
                        if store.save(person, expected: original.name.isEmpty ? nil : original) { dismiss() }
                    }.disabled(person.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }
                .confirmationDialog("Delete \(person.name) and their contact history?", isPresented: $deleting, titleVisibility: .visible) {
                    Button("Delete person", role: .destructive) { if store.delete(original) { dismiss() } }
                }
        }
        #if os(macOS)
        .frame(width: 580, height: 740)
        #endif
    }
    private var intentionExplanation: String {
        switch person.intention {
        case .space: "No proactive outreach reminders. Incoming messages can still prompt a reply, and nothing is counted as missed."
        case .grow: "Suggestions lean towards time together, calls and shared activities."
        case .maintain: "Suggestions stay small: a message, a quick call, a shared interest to pick up."
        case .unsure: "You'll be invited to decide when it feels right. Newly imported people start here."
        }
    }
    private func refreshRhythm() { if !person.rhythmIsCustom { person.applySuggestedRhythm() } }
}

/// Provenance shown wherever recorded context appears, so what you know stays
/// distinguishable from what you suspect and what an agent proposed.
extension ConnectionMemory {
    var provenance: String {
        let origin = IdeaSource.strongest(sources)
        let label: String
        switch origin {
        case .me: label = "You recorded this"
        case .them: label = "From something they said"
        case .memory: label = "From remembered conversations"
        case .agent: label = "Suggested by \(sources.contains(.agent) ? "an agent" : "someone else")"
        case .unsure: label = "Unconfirmed"
        }
        switch confidence {
        case .known: return label
        case .unsure: return "\(label), not confirmed"
        case .suggested: return "\(label), unverified"
        }
    }
}
extension ConnectionInterest {
    var provenance: String {
        let origin = IdeaSource.strongest(sources)
        switch confidence {
        case .known: return "From your notes"
        case .unsure: return origin == .agent ? "An agent's recollection, unconfirmed" : "A recollection, unconfirmed"
        case .suggested: return "Suggested, unverified"
        }
    }
}
extension ConnectionIdea {
    var provenance: String {
        let origin = IdeaSource.strongest(sources)
        switch confidence {
        case .known: return origin == .me || origin == .them ? "Yours" : "From your notes"
        case .unsure: return "Unconfirmed recollection"
        case .suggested: return origin == .agent ? "Agent suggestion" : "Suggested"
        }
    }
}
extension ConnectionRitual {
    var who: String { confidence == .known ? "Yours" : "Suggested" }
}
