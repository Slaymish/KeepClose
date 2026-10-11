import SwiftUI

@main struct KeepCloseApp: App {
    @State private var store = RelationshipStore()
    @State private var appLock = AppLockController()
    @State private var contacts = ContactsController()
    @State private var birthdays = BirthdayReminders()
    #if os(macOS)
    private let updater = AppUpdater()
    #endif
    var body: some Scene {
        WindowGroup { ProtectedAppView().environment(store).environment(appLock).environment(contacts).environment(birthdays).modifier(KeepCloseSyncLifecycle()) }
        #if os(macOS)
        .commands {
            CommandGroup(after: .appInfo) { CheckForUpdatesView(updater: updater) }
        }
        #endif
    }
}

enum AppPage: String, CaseIterable, Identifiable {
    case today = "Today", people = "People", preferences = "Preferences"
    var id: String { rawValue }
    var icon: String { switch self { case .today: "sun.max"; case .people: "person.2"; case .preferences: "slider.horizontal.3" } }
}

struct AppView: View {
    @Environment(RelationshipStore.self) private var store
    @Environment(AppLockController.self) private var appLock
    @Environment(ContactsController.self) private var contacts
    @Environment(BirthdayReminders.self) private var birthdays
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var appearance
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var page: AppPage? = .today
    @State private var showingContacts = false
    @State private var showingAdd = false
    @State private var importProvider: ImportProvider?
    var body: some View {
        Group {
            #if os(macOS)
            NavigationSplitView {
                List(AppPage.allCases, selection: $page) { item in
                    Label(item.rawValue, systemImage: item.icon).tag(item)
                }
                .navigationTitle("Keep Close")
                .navigationSplitViewColumnWidth(min: 160, ideal: 190)
            } detail: { screen(page ?? .today) }
            .frame(minWidth: 680, minHeight: 540)
            #else
            TabView {
                ForEach(AppPage.allCases) { item in
                    screen(item).tabItem { Label(item.rawValue, systemImage: item.icon) }
                }
            }
            #endif
        }
        #if DEBUG
        .preferredColorScheme(CommandLine.arguments.contains("--demo-dark") ? .dark : CommandLine.arguments.contains("--demo-light") ? .light : nil)
        .dynamicTypeSize(CommandLine.arguments.contains("--demo-large-type") ? .accessibility3 : typeSize)
        #endif
        .tint(appearance == .dark ? Color(red: 0.86, green: 0.69, blue: 0.47) : Color(red: 0.43, green: 0.30, blue: 0.18))
        .sheet(isPresented: $showingAdd) { PersonEditor(person: Person(name: "")) }
        .sheet(item: $importProvider) { AgentImportView(provider: $0) }
        .sheet(isPresented: $showingContacts) { ContactsImportView() }
        .task { await contacts.followChanges(); store.reload() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await contacts.followChanges(); store.reload(); await birthdays.refresh(people: store.people, names: store.includeNamesInReminders) } } }
        .onReceive(NotificationCenter.default.publisher(for: ContactsController.changedNotification)) { _ in Task { await contacts.followChanges(); store.reload() } }
        .alert("Couldn't save that change", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: { Text(store.error ?? "") }
    }
    private func screen(_ page: AppPage) -> some View {
        NavigationStack {
            Group {
                switch page {
                case .today: TodayView(add: { showingAdd = true }, importPeople: { importProvider = .chatgpt })
                case .people: PeopleView(add: { showingAdd = true })
                case .preferences: preferences
                }
            }
            .navigationTitle(page.rawValue)
            .navigationDestination(for: UUID.self) { PersonDetail(personId: $0) }
            .toolbar {
                if page != .preferences {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button("Import from Contacts…") { showingContacts = true }
                            Divider()
                            ForEach(ImportProvider.allCases) { provider in
                                Button("\(store.hasImported(provider) ? "Update" : "Import") from \(provider.title)…") { importProvider = provider }
                            }
                        } label: { Label("Import or update people", systemImage: "square.and.arrow.down") }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button("Add person", systemImage: "plus") { showingAdd = true }
                    }
                }
            }
        }
    }
    private var preferences: some View {
        Form {
            BirthdayPreferences()
            Section("Contacts") {
                Button("Choose people from Contacts…") { showingContacts = true }
                Button("Refresh linked contacts") { Task { await contacts.followChanges(); store.reload() } }.disabled(contacts.busy)
                Button("Open Contacts privacy settings") { contacts.openSettings() }
                Text("Import all available contacts or select just a few. Links follow changes without replacing your own edits. Contacts access is optional and managed separately on each device.").font(.caption).foregroundStyle(.secondary)
                if let message = contacts.message { Text(message).font(.caption).foregroundStyle(.secondary) }
            }
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
                Toggle("Daily reminder", isOn: Binding(get: { store.reminderRequested }, set: { value in Task { await store.setReminder(value) } }))
                .disabled(store.reminderBusy)
                DatePicker("Reminder time", selection: Binding(get: {
                    Calendar.current.date(from: DateComponents(year: 2001, month: 1, day: 1, hour: store.reminderHour, minute: store.reminderMinute)) ?? .now
                }, set: { date in
                    let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                    store.reminderHour = parts.hour ?? 18; store.reminderMinute = parts.minute ?? 0
                    Task { await store.setReminder(store.reminderRequested) }
                }), displayedComponents: .hourAndMinute)
                .disabled(store.reminderBusy)
                if !store.reminderMessage.isEmpty { Text(store.reminderMessage).font(.caption).foregroundStyle(.secondary) }
                Text("Only when there is an opportunity worth suggesting. Open Keep Close to refresh the next reminder; nothing repeats while the app is closed.").font(.footnote).foregroundStyle(.secondary)
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


/// A small receipt survives the card disappearing. Undo removes only this event.
struct ConnectionReceipt {
    let personId: UUID
    let entryId: UUID
    let text: String
}
struct ReceiptView: View {
    @Environment(RelationshipStore.self) private var store
    @Binding var receipt: ConnectionReceipt?
    var body: some View {
        if let item = receipt {
            ViewThatFits(in: .horizontal) {
                HStack { Text(item.text); Spacer(); controls(item) }
                VStack(alignment: .leading, spacing: 10) { Text(item.text); controls(item) }
            }
            .font(.callout).padding(16)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
            .accessibilityElement(children: .contain)
        }
    }
    private func controls(_ item: ConnectionReceipt) -> some View {
        HStack {
            Button("Undo") {
                if store.update(item.personId, change: { person in
                    guard person.removeContact(item.entryId) else { throw RepositoryError.missing }
                }) { receipt = nil }
            }.buttonStyle(.borderless)
            Button("Dismiss", systemImage: "xmark") { receipt = nil }.labelStyle(.iconOnly).buttonStyle(.borderless)
        }
    }
}

struct TodayView: View {
    @Environment(RelationshipStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let add: () -> Void
    let importPeople: () -> Void
    @State private var receipt: ConnectionReceipt?
    private var upcoming: [(person: Person, plan: ConnectionPlan)] {
        store.people.filter { !$0.paused && $0.intention != .space }
            .flatMap { person in person.activePlans.filter { $0.date >= Calendar.current.startOfDay(for: .now) }.map { (person: person, plan: $0) } }
            .sorted { $0.plan.date < $1.plan.date }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                ReceiptView(receipt: $receipt)
                if store.people.isEmpty {
                    QuietState(icon: "person.2", title: "A little closer", text: "Start with someone you'd like to share more of life with. One person is enough.")
                    ViewThatFits {
                        HStack { welcomeActions }
                        VStack(alignment: .leading, spacing: 12) { welcomeActions }
                    }
                } else if store.due.isEmpty {
                    if store.upcomingBirthdays.isEmpty {
                        QuietState(icon: "sun.max", title: "Room for your day", text: "No particular opportunities to suggest today. Enjoy whatever the day brings.")
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("A little thought").font(.system(.largeTitle, design: .serif, weight: .semibold))
                            Text("An occasion to remember, in your own way.").foregroundStyle(.secondary)
                        }
                    }
                    NavigationLink("Browse your people") { PeopleView(add: add).navigationTitle("People") }.buttonStyle(.bordered)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("A little time together").font(.system(.largeTitle, design: .serif, weight: .semibold))
                        Text("Something that might fit your day. Take it or leave it.").foregroundStyle(.secondary)
                    }
                    ForEach(Array(store.due.prefix(3))) { person in
                        OpportunityCard(person: person, showsPerson: true) { receipt = $0 }
                    }
                }
                UpcomingBirthdays()
                if !upcoming.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Coming up").font(.title3.weight(.semibold))
                        ForEach(Array(upcoming.prefix(3)), id: \.plan.id) { item in
                            NavigationLink(value: item.person.id) {
                                HStack(alignment: .top, spacing: 14) {
                                    Image(systemName: "calendar").foregroundStyle(.secondary).accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.person.name).font(.headline)
                                        Text(item.plan.title)
                                        Text(item.plan.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(24).frame(maxWidth: 720, alignment: .leading).frame(maxWidth: .infinity, alignment: .center)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: store.due.map(\.id))
        }
    }
    private var welcomeActions: some View {
        Group {
            Button("Add someone", action: add).buttonStyle(.borderedProminent)
            Button("Bring in remembered context", action: importPeople).buttonStyle(.bordered)
        }
    }
}

struct QuietState: View {
    let icon: String
    let title: String
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: icon).font(.system(size: 32, weight: .light)).foregroundStyle(.secondary).accessibilityHidden(true)
            Text(title).font(.system(.largeTitle, design: .serif, weight: .semibold))
            Text(text).font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(.vertical, 28)
    }
}

struct PeopleView: View {
    @Environment(RelationshipStore.self) private var store
    let add: () -> Void
    @State private var search = ""
    @State private var category: String?
    @State private var intention: RelationshipIntention?
    private var categories: [String] { Array(Set(store.people.flatMap { $0.relationshipTypes + $0.contexts })).sorted() }
    private var filtered: [Person] {
        store.people.filter { person in
            (intention == nil || person.intention == intention) &&
            (category == nil || (person.relationshipTypes + person.contexts).contains(category!)) &&
            (search.isEmpty || ([person.name, person.context] + person.relationshipTypes + person.contexts + person.interests.map(\.name)).contains { $0.localizedStandardContains(search) })
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    var body: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { filters; Spacer(minLength: 0) }
                VStack(alignment: .leading, spacing: 10) { filters }
            }.padding(.horizontal, 20).padding(.vertical, 12)
            if filtered.isEmpty {
                ContentUnavailableView {
                    Label(store.people.isEmpty ? "Your people, in one place" : "No matching people", systemImage: "person.2")
                } description: {
                    Text(store.people.isEmpty ? "Add someone you'd like to keep close." : "Try another name or change the filters.")
                } actions: {
                    if store.people.isEmpty { Button("Add someone", action: add) }
                    else { Button("Clear search and filters") { search = ""; category = nil; intention = nil } }
                }
            } else {
                List(filtered) { person in
                    NavigationLink(value: person.id) { PersonRow(person: person) }
                }.listStyle(.plain)
            }
        }
        .searchable(text: $search, prompt: "Find a person or shared interest")
    }
    private var filters: some View {
        Group {
            Menu {
                Button("All intentions") { intention = nil }
                ForEach(RelationshipIntention.allCases, id: \.self) { choice in
                    Button(choice.title) { intention = choice }
                }
            } label: { Label(intention?.title ?? "All intentions", systemImage: "line.3.horizontal.decrease") }
            Menu {
                Button("All categories") { category = nil }
                ForEach(categories, id: \.self) { value in Button(value) { category = value } }
            } label: { Text(category ?? "All categories") }
            if intention != nil || category != nil {
                Button("Clear") { intention = nil; category = nil }.buttonStyle(.borderless)
            }
        }.font(.callout)
    }
}

struct Avatar: View {
    let name: String
    @ScaledMetric private var size = 44.0
    var body: some View {
        Text(name.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined())
            .font(.callout.weight(.medium)).foregroundStyle(.primary)
            .frame(width: min(size, 64), height: min(size, 64))
            .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
            .accessibilityHidden(true)
    }
}

struct PersonRow: View {
    let person: Person
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Avatar(name: person.name)
            VStack(alignment: .leading, spacing: 5) {
                Text(person.name).font(.headline).fixedSize(horizontal: false, vertical: true)
                if let context = person.listContext {
                    Text(context).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
                let suggestion = person.suggestion()
                if suggestion.ready {
                    Label(suggestion.title, systemImage: suggestion.action == .reply ? "bubble.left" : "leaf")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                if person.paused || person.intention == .space {
                    Text(person.paused ? "Suggestions paused" : "Giving space").font(.caption).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }
}

extension Person {
    var listContext: String? {
        if let interest = interests.first(where: { $0.confidence == .known }) { return interest.name }
        if let memory = memories.last(where: { $0.confidence == .known }) { return memory.text }
        let note = context.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty { return note }
        return relationshipTypes.isEmpty ? nil : relationshipTypes.prefix(2).joined(separator: " · ")
    }
}

struct OpportunityCard: View {
    @Environment(RelationshipStore.self) private var store
    @Environment(\.openURL) private var openURL
    let person: Person
    var showsPerson = false
    let acknowledged: (ConnectionReceipt) -> Void
    @State private var openFailed = false
    @State private var showingPlan = false
    var body: some View {
        let suggestion = person.suggestion()
        VStack(alignment: .leading, spacing: 18) {
            if showsPerson {
                NavigationLink(value: person.id) {
                    HStack(alignment: .top, spacing: 12) {
                        Avatar(name: person.name)
                        Text(person.name).font(.title2.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
                    }
                }.buttonStyle(.plain).accessibilityHint("Open this person's details")
            }
            VStack(alignment: .leading, spacing: 8) {
                if let idea = suggestion.opportunity, idea.confidence != .known {
                    Text(idea.confidence == .unsure ? "If this still fits" : "An idea to consider").font(.caption).foregroundStyle(.secondary)
                }
                Text(suggestion.title).font(.title3.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                if !suggestion.reason.isEmpty, suggestion.opportunity?.confidence == .known || suggestion.opportunity == nil {
                    Text(suggestion.reason).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { connectionActions(suggestion); Spacer(minLength: 0); choiceActions(suggestion) }
                VStack(alignment: .leading, spacing: 14) { connectionActions(suggestion); choiceActions(suggestion) }
            }
            if let opportunity = suggestion.opportunity {
                DisclosureGroup("About this idea") {
                    VStack(alignment: .leading, spacing: 8) {
                        if opportunity.confidence != .known, !opportunity.reason.isEmpty { Text(opportunity.reason).font(.callout) }
                        Text(opportunity.provenance).font(.caption).foregroundStyle(.secondary)
                        if let timing = opportunity.timing { Text(timing.title).font(.caption).foregroundStyle(.secondary) }
                        Button(person.helpfulIdeas.contains(opportunity.id) ? "Saved as useful" : "This idea is useful") { store.update(person.id) { $0.recordFeedback(.helpful, ideaId: opportunity.ideaId) } }
                            .buttonStyle(.borderless).font(.callout).disabled(person.helpfulIdeas.contains(opportunity.id))
                        Button("I did this") { store.update(person.id) { $0.recordFeedback(.done, ideaId: opportunity.ideaId) } }
                            .buttonStyle(.borderless).font(.callout)
                        Text("Remember the activity without adding a contact log.").font(.caption).foregroundStyle(.secondary)
                    }.padding(.top, 8)
                }.font(.callout).foregroundStyle(.secondary)
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(.primary.opacity(0.12), lineWidth: 1))
            .sheet(isPresented: $showingPlan) { PlanEditor(person: person, opportunity: suggestion.opportunity) }
            .alert("Couldn't open the contact app", isPresented: $openFailed) { Button("OK", role: .cancel) {} } message: { Text("Use your usual app, or check this person's contact details.") }
    }
    private func connectionActions(_ suggestion: RelationshipSuggestion) -> some View {
        Group {
            if let url = person.contactURL {
                Button(suggestion.action == .reply ? "Open to reply" : "Open \(person.method.rawValue)", systemImage: "arrow.up.forward.app") {
                    openURL(url) { accepted in if !accepted { openFailed = true } }
                }.buttonStyle(.bordered)
            }
            Menu(suggestion.action == .reply ? "I replied…" : "I reached out…") {
                if suggestion.action == .reply {
                    Button("Reply sent") { record(.reply, suggestion) }
                } else {
                    Button("Message or invitation sent") { record(.outreach, suggestion) }
                }
                Button("We spent time together") { record(.conversation, suggestion) }
                Button("We made a plan…") { showingPlan = true }
            }.buttonStyle(.bordered)
        }
    }
    private func choiceActions(_ suggestion: RelationshipSuggestion) -> some View {
        Group {
            Menu("Later") {
                ForEach([1, 3, 7], id: \.self) { days in
                    Button(days == 1 ? "Tomorrow" : days == 3 ? "In a few days" : "Next week") {
                        store.update(person.id) {
                            $0.snooze(until: Calendar.current.date(byAdding: .day, value: days, to: .now) ?? .now)
                            $0.recordFeedback(.snoozed, ideaId: suggestion.opportunity?.ideaId, action: suggestion.action)
                        }
                    }
                }
            }
            Button(suggestion.action == .reply ? "Leave it here" : "Not for me") {
                store.update(person.id) { current in
                    if suggestion.action == .reply { for entry in current.pendingIncoming { current.resolveIncoming(entry.id) } }
                    else if let opportunity = suggestion.opportunity {
                        if opportunity.isRitual, let i = current.connection.rituals.firstIndex(where: { $0.id == opportunity.id }) { current.connection.rituals[i].dismissed = true }
                        else { current.dismissIdea(opportunity.id) }
                        current.recordFeedback(.notForMe, ideaId: opportunity.id)
                    } else { current.recordFeedback(.notForMe, action: suggestion.action) }
                }
            }.buttonStyle(.borderless)
        }.font(.callout)
    }
    private func record(_ kind: ContactKind, _ suggestion: RelationshipSuggestion) {
        var entry: UUID?
        if store.update(person.id, change: { current in
            entry = current.recordContact(kind: kind, ideaId: suggestion.opportunity?.ideaId)
        }), let entry {
            acknowledged(ConnectionReceipt(personId: person.id, entryId: entry,
                text: kind == .outreach ? "You've reached out to \(person.name). That's enough for now." : kind == .reply ? "Reply recorded. Nothing more needed." : "Time with \(person.name), remembered."))
        }
    }
}

extension Person {
    var contactURL: URL? {
        guard method != .inPerson, !address.isEmpty else { return nil }
        let scheme = method == .email ? "mailto" : method == .call ? "tel" : "sms"
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "?#&"))
        guard let encoded = address.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "\(scheme):\(encoded)")
    }
}

struct PersonDetail: View {
    @Environment(RelationshipStore.self) private var store
    @Environment(\.openURL) private var openURL
    let personId: UUID
    @Environment(ContactsController.self) private var contacts
    @State private var showingMerge = false
    @State private var editing: Person?
    @State private var showingContext = false
    @State private var logKind: ContactKind?
    @State private var correcting: ContactEntry?
    @State private var showingPlan = false
    @State private var editingPlan: ConnectionPlan?
    @State private var receipt: ConnectionReceipt?
    @State private var openFailed = false
    var body: some View {
        if let person = store.people.first(where: { $0.id == personId }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(alignment: .top, spacing: 14) {
                        Avatar(name: person.name)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(person.name).font(.largeTitle.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                            Text(person.intention.title).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    if let birthday = person.birthday { Label(birthday.label, systemImage: "gift").foregroundStyle(.secondary) }
                    ReceiptView(receipt: $receipt)
                    if person.suggestion().ready {
                        OpportunityCard(person: person) { receipt = $0 }
                    } else if !person.pendingOutreach.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("You've reached out", systemImage: "paperplane").font(.headline)
                            Text("Your message is sent. Nothing else needed here.").foregroundStyle(.secondary)
                            DisclosureGroup("When you'd like new ideas") {
                                Text("If the invitation no longer needs to stay open, you can allow new ideas without recording a reply.").font(.callout).foregroundStyle(.secondary)
                                Button("Allow new ideas") { store.update(person.id) { current in for entry in current.pendingOutreach { current.resolveOutreach(entry.id) } } }
                            }.font(.callout)
                        }
                    } else if person.activePlans.isEmpty {
                        Text(person.suggestion().title).foregroundStyle(.secondary)
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) { detailActions(person) }
                        VStack(alignment: .leading, spacing: 12) { detailActions(person) }
                    }
                    if !person.activePlans.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Plans together").font(.title3.weight(.semibold))
                            ForEach(person.activePlans) { plan in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(plan.title).font(.headline)
                                    Text(plan.date.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary)
                                    ViewThatFits {
                                        HStack(spacing: 14) { planActions(plan, person) }
                                        VStack(alignment: .leading, spacing: 12) { planActions(plan, person) }
                                    }
                                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
                            }
                        }
                    }
                    Divider()
                    DisclosureGroup("What you share") {
                        VStack(alignment: .leading, spacing: 12) {
                            if !person.context.isEmpty { Text(person.context) }
                            ForEach(person.interests) { interest in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(interest.name).font(.headline)
                                    if !interest.detail.isEmpty { Text(interest.detail).font(.callout) }
                                    Text(interest.provenance).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            ForEach(person.memories.suffix(3)) { memory in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(memory.text)
                                    Text(memory.provenance).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Button("Edit memories, interests and ideas") { showingContext = true }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 12)
                    }
                    DisclosureGroup("Details") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text((person.relationshipTypes + person.contexts).joined(separator: " · "))
                            if !person.importSources.isEmpty { Text("Remembered with \(person.importSources.joined(separator: ", "))") }
                            Text(person.paused ? "Suggestions paused" : "Ideas may return after your \(person.rhythmDays)-day rhythm. This is a preference, never a deadline.")
                            ForEach(person.alternateContactDetails) { detail in Text(detail.method.rawValue + ": " + detail.address) }
                            ForEach(person.contactLinks.filter { $0.deviceID == contacts.deviceID }) { link in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Linked to Contacts: " + link.contact.name)
                                    ForEach(Array(Set(link.contact.phones + link.contact.emails)).sorted(), id: \.self) { address in
                                        if address != person.address { Text(address).textSelection(.enabled) }
                                    }
                                    Toggle("Follow Contacts changes", isOn: Binding(get: { link.followsChanges }, set: { value in store.update(person.id) { current in if let i = current.contactLinks.firstIndex(where: { $0.id == link.id }) { current.contactLinks[i].followsChanges = value } }; if value { Task { await contacts.followChanges(); store.reload() } } }))
                                    Button("Unlink contact") { store.update(person.id) { $0.contactLinks.removeAll { $0.id == link.id } } }
                                }
                            }
                            Button("Edit preferences") { editing = person }
                            Button("Merge with another person…") { showingMerge = true }
                        }.font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 12)
                    }
                    DisclosureGroup("Remembered moments") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Only what you've chosen to record. Unrecorded time together matters just as much.").font(.caption).foregroundStyle(.secondary)
                            ForEach(person.contacts.sorted { $0.date > $1.date }) { entry in
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(entry.kind.title).font(.callout.weight(.medium))
                                        Text(entry.date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                                        if !entry.note.isEmpty { Text(entry.note).font(.callout) }
                                        if entry.kind == .incoming && entry.resolvedAt == nil {
                                            Button("No reply needed") { store.update(person.id) { $0.resolveIncoming(entry.id) } }.font(.callout)
                                        }
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                    Menu {
                                        Button("Correct…") { correcting = entry }
                                        Button("Remove this log", role: .destructive) { store.update(person.id) { $0.removeContact(entry.id) } }
                                    } label: { Label("Change log", systemImage: "ellipsis") }.labelStyle(.iconOnly)
                                }.padding(.vertical, 6)
                            }
                            ForEach(person.plans.filter { $0.status == .cancelled }) { plan in
                                Text("\(plan.title) · Set aside").font(.callout).foregroundStyle(.secondary)
                            }
                        }.padding(.top, 12)
                    }
                }.padding(24).frame(maxWidth: 720, alignment: .leading).frame(maxWidth: .infinity)
            }
            .navigationTitle(person.name)
            .toolbar { ToolbarItem(placement: .primaryAction) { Button("Edit") { editing = person } } }
            .sheet(item: $editing) { PersonEditor(person: $0) }
            .sheet(isPresented: $showingMerge) { PersonMergeView(person: person) }
            .sheet(isPresented: $showingContext) { ConnectionContextView(person: person) }
            .sheet(item: $logKind) { ContactLogger(person: person, initialKind: $0) }
            .sheet(item: $correcting) { ContactLogger(person: person, initialKind: $0.kind, original: $0) }
            .sheet(isPresented: $showingPlan) { PlanEditor(person: person) }
            .sheet(item: $editingPlan) { PlanEditor(person: person, original: $0) }
            .alert("Couldn't open the contact app", isPresented: $openFailed) { Button("OK", role: .cancel) {} } message: { Text("Use your usual app, or check this person's contact details.") }
        } else {
            ContentUnavailableView("This person is no longer here", systemImage: "person")
        }
    }
    private func detailActions(_ person: Person) -> some View {
        Group {
            if !person.suggestion().ready, let url = person.contactURL {
                Button("Open \(person.method.rawValue)", systemImage: "arrow.up.forward.app") { openURL(url) { if !$0 { openFailed = true } } }.buttonStyle(.bordered)
            }
            Menu("Remember a moment") { ForEach(ContactKind.allCases) { kind in Button(kind.title) { logKind = kind } } }.buttonStyle(.bordered)
            Button("Add a plan") { showingPlan = true }.buttonStyle(.borderless)
        }.font(.callout)
    }
    private func planActions(_ plan: ConnectionPlan, _ person: Person) -> some View {
        Group {
            if plan.date <= .now {
                Button("We spent time together") {
                    var entry: UUID?
                    if store.update(person.id, change: { entry = $0.finishPlan(plan.id, at: plan.date) }), let entry {
                        receipt = ConnectionReceipt(personId: person.id, entryId: entry, text: "Time together, remembered.")
                    }
                }
            }
            Button("Change…") { editingPlan = plan }
            Button("Set aside") { store.update(person.id) { $0.cancelPlan(plan.id) } }
        }.font(.callout).buttonStyle(.borderless)
    }
}

struct ContactLogger: View {
    @Environment(RelationshipStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let person: Person
    let original: ContactEntry?
    @State private var kind: ContactKind
    @State private var initiator: Initiator
    @State private var contactDate: Date
    @State private var note: String
    init(person: Person, initialKind: ContactKind, original: ContactEntry? = nil) {
        self.person = person; self.original = original
        _kind = State(initialValue: original?.kind ?? initialKind)
        _initiator = State(initialValue: original?.initiator ?? .unknown)
        _contactDate = State(initialValue: original?.date ?? .now)
        _note = State(initialValue: original?.note ?? "")
    }
    var body: some View {
        NavigationStack {
            Form {
                Picker("What happened?", selection: $kind) { ForEach(ContactKind.allCases) { Text($0.title).tag($0) } }
                Text(explanation).font(.callout).foregroundStyle(.secondary)
                DisclosureGroup("Date and a note (optional)") {
                    DatePicker("When", selection: $contactDate, in: ...Date.now, displayedComponents: [.date, .hourAndMinute])
                    TextField("Something to remember", text: $note, axis: .vertical)
                    if kind == .conversation {
                        Picker("Who started it? (optional)", selection: $initiator) {
                            Text("Not recorded").tag(Initiator.unknown); Text("Me").tag(Initiator.me)
                            Text("Them").tag(Initiator.them); Text("Both / naturally").tag(Initiator.mutual)
                        }
                    }
                }
            }.formStyle(.grouped).navigationTitle(original == nil ? "Remember a moment" : "Correct this moment")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") {
                        if store.update(person.id, change: { current in
                            if let original {
                                guard current.correctContact(original, date: contactDate, note: note, kind: kind, initiator: initiator) else { throw RepositoryError.conflict }
                            } else { current.recordContact(at: contactDate, note: note, kind: kind, initiator: kind == .conversation ? initiator : nil) }
                        }) { dismiss() }
                    } }
                }
        }
        #if os(macOS)
        .frame(width: 520, height: 430)
        #endif
    }
    private var explanation: String {
        switch kind {
        case .outreach: "Sending a message is already a good moment. New invitations will wait; there's no need to record a reply."
        case .incoming: "Keep a reply open if you'd like. You can leave it here whenever you choose."
        case .conversation: "A conversation, a game, a walk — time you actually shared."
        case .reply: "Your reply is enough. It closes earlier incoming messages."
        case .ambient: "An everyday moment. Remember it if you'd like; it doesn't change when other ideas appear."
        }
    }
}

struct PlanEditor: View {
    @Environment(RelationshipStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let person: Person
    let opportunity: ConnectionOpportunity?
    let original: ConnectionPlan?
    @State private var title: String
    @State private var date: Date
    init(person: Person, opportunity: ConnectionOpportunity? = nil, original: ConnectionPlan? = nil) {
        self.person = person; self.opportunity = opportunity; self.original = original
        _title = State(initialValue: original?.title ?? opportunity?.activity ?? "")
        _date = State(initialValue: original?.date ?? Calendar.current.date(byAdding: .day, value: 1, to: .now)!)
    }
    var body: some View {
        NavigationStack {
            Form {
                TextField("What have you arranged?", text: $title, axis: .vertical)
                DatePicker("When", selection: $date, displayedComponents: [.date, .hourAndMinute])
                Text("For something you've agreed together. An invitation you've sent can simply stay a sent message. A plan doesn't record contact or create extra reminders.")
                    .font(.callout).foregroundStyle(.secondary)
            }.formStyle(.grouped).navigationTitle(original == nil ? "A plan with \(person.name)" : "Change your plan")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") {
                        if store.update(person.id, change: { current in
                            if let original {
                                guard let i = current.plans.firstIndex(where: { $0 == original }) else { throw RepositoryError.conflict }
                                current.plans[i].title = title.trimmingCharacters(in: .whitespacesAndNewlines); current.plans[i].date = date
                            } else { current.addPlan(title: title, date: date, ideaId: opportunity?.ideaId) }
                        }) { dismiss() }
                    }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || original == nil && date < .now) }
                }
        }
        #if os(macOS)
        .frame(width: 520, height: 340)
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
                                if ritual.dismissed { Text("Set aside").font(.caption).foregroundStyle(.secondary) }
                                if !ritual.note.isEmpty { Text(ritual.note).font(.caption).foregroundStyle(.secondary) }
                                Text(ritual.days == nil ? "No set frequency" : "Roughly every \(ritual.days!) days").font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if ritual.dismissed { Button("Bring back") { store.update(person.id) { $0.restoreRitual(ritual.id) } }.buttonStyle(.borderless).font(.caption) }
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
                    }.buttonStyle(.bordered).tint(selection.contains(tag) ? .accentColor : .gray)
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
    @State private var firstIdea = ""
    @State private var birthdayValid = true
    private var exists: Bool { store.people.contains { $0.id == person.id } }
    var body: some View {
        NavigationStack {
            Form {
                Section { TextField("Name", text: $person.name) }
                if !exists {
                    Section("Something you'd like to do together (optional)") {
                        TextField("A game evening, a walk, a project…", text: $firstIdea, axis: .vertical)
                        Text("One idea is enough. You can add or change it later.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                BirthdayFields(person: $person, birthdayValid: $birthdayValid)
                Section("Keep the nuance") {
                    TextField("Something worth remembering (optional)", text: $person.context, axis: .vertical).lineLimit(2...6)
                }
                Section {
                    DisclosureGroup("Relationship preferences") {
                        Picker("Intention", selection: Binding(get: { person.intention }, set: { person.chooseIntention($0) })) {
                            ForEach(RelationshipIntention.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        Text(intentionExplanation).font(.caption).foregroundStyle(.secondary)
                        DisclosureGroup("Categories") {
                            Text("Who they are to you").font(.subheadline)
                            CategoryChips(options: Person.typeOptions, selection: $person.relationshipTypes)
                            Text("Where your lives overlap").font(.subheadline)
                            CategoryChips(options: Person.contextOptions, selection: $person.contexts)
                        }
                        DisclosureGroup("Contact details") {
                            Picker("Prefer", selection: $person.method) { ForEach(ContactMethod.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                            if person.method != .inPerson { TextField(person.method == .email ? "Email address" : "Phone number", text: $person.address) }
                        }
                        DisclosureGroup("Suggestion rhythm") {
                            Stepper("Every \(person.rhythmDays) days", value: Binding(get: { person.rhythmDays }, set: { person.rhythmDays = $0; person.rhythmIsCustom = true }), in: 1...365)
                            Button("Use starting rhythm (\(person.suggestedRhythm) days)") { person.applySuggestedRhythm() }
                            Text("Only a preference for when ideas may return. You don't need a schedule to care about someone.").font(.caption).foregroundStyle(.secondary)
                        }
                        Toggle("Pause all suggestions", isOn: $person.paused)
                    }
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
                        if !exists, !firstIdea.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { person.addIdea(activity: firstIdea) }
                        if store.save(person, expected: original.name.isEmpty ? nil : original) { dismiss() }
                    }.disabled(person.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !birthdayValid) }
                }
                .confirmationDialog("Delete \(person.name) and their contact history?", isPresented: $deleting, titleVisibility: .visible) {
                    Button("Delete person", role: .destructive) { if store.delete(original) { dismiss() } }
                }
        }
        #if os(macOS)
        .frame(width: 580, height: 600)
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
