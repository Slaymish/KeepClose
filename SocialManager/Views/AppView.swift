import SwiftUI

@main struct KeepCloseApp: App {
    @State private var store = RelationshipStore()
    @State private var appLock = AppLockController()
    #if os(macOS)
    private let updater = AppUpdater()
    #endif
    var body: some Scene {
        WindowGroup { ProtectedAppView().environment(store).environment(appLock) }
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
            Text("Start with one person. Choose who they are to you and what you'd like for the relationship; you can change your mind any time.")
        } actions: {
            Button("Import from ChatGPT") { importProvider = .chatgpt }.buttonStyle(.borderedProminent)
            Button("Add a person yourself") { showingAdd = true }.buttonStyle(.bordered)
        }
    }
    private var today: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("A little connection goes a long way.").font(.largeTitle.bold())
                    Text(store.due.isEmpty ? "No suggested actions today. You can still connect with anyone in People." : "Choose one small next step that feels doable.")
                        .foregroundStyle(.secondary)
                }
                if store.due.isEmpty {
                    Label("Room to choose your own pace", systemImage: "checkmark.circle").font(.title3).padding(.vertical)
                    Button("See your people") { page = "People" }
                } else {
                    ForEach(Array(store.due.prefix(3))) { person in
                        PersonCard(person: person, edit: { editing = person })
                    }
                    if store.due.count > 3 { Text("\(store.due.count - 3) more people have suggested next steps. Start with these, or choose someone in People.").font(.callout).foregroundStyle(.secondary) }
                }
                Text("Log what actually happened: a message from either of you, a reply, or time together. Suggestions use what you record.")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding(28).frame(maxWidth: 800, alignment: .leading).frame(maxWidth: .infinity)
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
                ForEach(RelationshipIntention.allCases, id: \.self) { intention in
                    let people = store.people.filter { $0.intention == intention && (categoryFilter == nil || ($0.relationshipTypes + $0.contexts).contains(categoryFilter!)) }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                    if !people.isEmpty {
                        Section(intention.title) {
                            ForEach(people) { person in
                                NavigationLink {
                                    ScrollView { PersonCard(person: person, edit: { editing = person }).padding(24) }
                                } label: { PersonRow(person: person) }
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
                Text("One reminder each day, even when nobody is due. It invites you to check in; it doesn't escalate if you skip it.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Your information") {
                Text("Relationships and notes are saved locally on this device. This first version doesn't sync between your iPhone and Mac.")
                Text("The app opens your chosen contact app. You send the message yourself, then log it here.")
            }
        }.formStyle(.grouped)
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
            Text(person.suggestion().title).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
        }.padding(.vertical, 6)
    }
}

struct PersonCard: View {
    @Environment(RelationshipStore.self) private var store
    @Environment(\.openURL) private var openURL
    let person: Person
    let edit: () -> Void
    @State private var logKind: ContactKind?
    @State private var openFailed = false
    private var current: Person { store.people.first { $0.id == person.id } ?? person }
    var body: some View {
        let person = current
        let suggestion = person.suggestion()
        VStack(alignment: .leading, spacing: 18) {
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
            VStack(alignment: .leading, spacing: 6) {
                Text(suggestion.title).font(.headline)
                Text(suggestion.reason).font(.callout).foregroundStyle(.secondary)
                if let date = suggestion.nextDate { Text("Next suggestion: \(date.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.secondary) }
            }.padding().frame(maxWidth: .infinity, alignment: .leading).background(.teal.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            if let last = person.lastContact { Text("Last connection: \(last.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.secondary) }
            if let last = person.lastIncoming { Text("They last reached out: \(last.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.secondary) }
            if !person.context.isEmpty { Text(person.context) }
            if !person.importSources.isEmpty { Text("Imported from \(person.importSources.joined(separator: ", "))").font(.caption).foregroundStyle(.secondary) }
            if person.deferrals >= 2 && suggestion.ready {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Make the next step smaller").font(.headline)
                    Text(person.smallStep)
                    Text("If this rhythm doesn't fit, edit it or pause check-ins.").font(.caption).foregroundStyle(.secondary)
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack { actions(person) }
                VStack(alignment: .leading, spacing: 12) { actions(person) }
            }
            if !person.contacts.isEmpty {
                DisclosureGroup("Connection history (\(person.contacts.count))") {
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
                }.font(.callout)
            }
        }.padding(22).background(.background, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(.primary.opacity(0.12)))
            .sheet(item: $logKind) { kind in ContactLogger(person: current, initialKind: kind) }
            .alert("Couldn't open the contact app", isPresented: $openFailed) { Button("OK", role: .cancel) {} } message: { Text("Check this person's contact details, or reach out using your usual app.") }
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
                Button("Tomorrow") { snooze(1) }
                Button("In 3 days") { snooze(3) }
                Button("Next week") { snooze(7) }
            }.buttonStyle(.bordered)
        }
    }
    private func snooze(_ days: Int) {
        store.update(person.id) { $0.deferContact(until: Calendar.current.date(byAdding: .day, value: days, to: .now)!) }
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
                TextField("A note for next time (optional)", text: $note, axis: .vertical)
                Text(kind == .incoming ? "This creates a reply suggestion. If you already replied, log a reply or catch-up too." : kind == .ambient ? "Seeing each other in passing won't reset the rhythm for a proper connection." : kind == .reply ? "This records your reply and closes earlier incoming messages. You don't need to wait for another reply." : "Record what actually happened. A catch-up counts whoever started it.").font(.caption).foregroundStyle(.secondary)
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
                            Button { person.intention = intention } label: {
                                HStack { if person.intention == intention { Image(systemName: "checkmark") }; Text(intention.title) }.frame(maxWidth: .infinity).padding(.vertical, 8)
                            }.buttonStyle(.bordered).tint(person.intention == intention ? .teal : .gray)
                            .accessibilityValue(person.intention == intention ? "Selected" : "Not selected")
                        }
                    }
                    Text(person.intention == .space ? "No proactive outreach reminders. Incoming messages can still prompt a reply." : "You can change your mind any time. These choices guide suggestions, not a relationship score.").font(.caption).foregroundStyle(.secondary)
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
                        Text("Suggestions are editable starting points. Shared everyday settings allow more room between intentional catch-ups; Grow suggests a shorter rhythm. Actual contact history determines the next action.").font(.caption).foregroundStyle(.secondary)
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
    private func refreshRhythm() { if !person.rhythmIsCustom { person.applySuggestedRhythm() } }
}
