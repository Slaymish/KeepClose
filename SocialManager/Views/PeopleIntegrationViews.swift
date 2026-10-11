import SwiftUI

struct BirthdayFields: View {
    @Binding var person: Person
    @Binding var birthdayValid: Bool
    @State private var month = 1
    @State private var day = 1
    @State private var includeYear = false
    @State private var year = 2000
    private var monthNames: [String] { var c = Calendar(identifier: .gregorian); c.locale = .current; return c.monthSymbols }
    private var valid: Birthday? { try? Birthday(month: month, day: day, year: includeYear ? year : nil) }
    var body: some View {
        Section("Birthday (optional)") {
            Toggle("Remember their birthday", isOn: Binding(get: { person.birthday != nil }, set: { person.birthday = $0 ? (valid ?? (try? Birthday(month: 1, day: 1))) : nil; birthdayValid = !$0 || valid != nil }))
            if person.birthday != nil {
                Picker("Month", selection: $month) {
                    ForEach(1...12, id: \.self) { Text(monthNames[$0 - 1]).tag($0) }
                }
                Picker("Day", selection: $day) { ForEach(1...31, id: \.self) { Text(String($0)).tag($0) } }
                Toggle("Include birth year", isOn: $includeYear)
                if includeYear {
                    TextField("Birth year", value: $year, format: .number.grouping(.never))
                }
                if valid == nil { Text("That date doesn't exist. Choose another day.").foregroundStyle(.red) }
                Toggle("Birthday-day reminder", isOn: $person.birthdayReminder)
                Picker("Gift thought two weeks before", selection: $person.giftReminder) { ForEach(GiftReminder.allCases, id: \.self) { Text($0.title).tag($0) } }
                Text("Enable birthday notifications in Preferences on each device. Give Space and paused suggestions silence these reminders too.").font(.caption).foregroundStyle(.secondary)
                if month == 2 && day == 29 { Text("In non-leap years, we'll remember this on February 28.").font(.caption).foregroundStyle(.secondary) }
            }
        }
        .onAppear { if let b = person.birthday { month = b.month; day = b.day; year = b.year ?? 2000; includeYear = b.year != nil } }
        .onChange(of: month) { _, _ in update() }.onChange(of: day) { _, _ in update() }
        .onChange(of: year) { _, _ in update() }.onChange(of: includeYear) { _, _ in update() }
    }
    private func update() {
        birthdayValid = person.birthday == nil || valid != nil
        if person.birthday != nil, let valid { person.birthday = valid }
    }
}

struct UpcomingBirthdays: View {
    @Environment(RelationshipStore.self) private var store
    private var upcoming: [(person: Person, date: Date)] { store.upcomingBirthdays }
    var body: some View {
        if !upcoming.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("Birthdays soon").font(.title3.weight(.semibold))
                ForEach(Array(upcoming.prefix(5)), id: \.person.id) { item in
                    NavigationLink(value: item.person.id) {
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: "gift").foregroundStyle(.secondary).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.person.name).font(.headline)
                                Text(Calendar.current.isDateInToday(item.date) ? "Birthday today" : item.date.formatted(.dateTime.month(.wide).day())).foregroundStyle(.secondary)
                                if !Calendar.current.isDateInToday(item.date), item.person.hasGiftReminder {
                                    Text("A little time to think about a gift, if you'd like.").font(.callout).foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                        }.padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain)
                }
                if upcoming.count > 5 { Text("More birthdays are in your people's details.").font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}

struct BirthdayPreferences: View {
    @Environment(BirthdayReminders.self) private var birthdays
    @Environment(RelationshipStore.self) private var store
    var body: some View {
        Section("Birthdays") {
            Toggle("Birthday and gift reminders on this device", isOn: Binding(get: { birthdays.enabled }, set: { value in Task { await birthdays.setEnabled(value, people: store.people, names: store.includeNamesInReminders) } })).disabled(birthdays.busy)
            DatePicker("Birthday reminder time", selection: Binding(get: { Calendar.current.date(from: DateComponents(year: 2001, month: 1, day: 1, hour: birthdays.hour, minute: birthdays.minute)) ?? .now }, set: { date in Task { await birthdays.setTime(date, people: store.people, names: store.includeNamesInReminders) } }), displayedComponents: .hourAndMinute).disabled(birthdays.busy)
            Text("Add a birthday in a person's details. Gift thoughts arrive two weeks ahead for friends and family; you can change this for each person.").font(.caption).foregroundStyle(.secondary)
            Text("Reminders are queued up to two years ahead, with the nearest 60 retained. Opening Keep Close refreshes future dates and applies your edits. Notification permission and these settings belong to this device.").font(.caption).foregroundStyle(.secondary)
            if !birthdays.message.isEmpty { Text(birthdays.message).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

struct ContactsImportView: View {
    @Environment(RelationshipStore.self) private var store
    @Environment(ContactsController.self) private var contacts
    @Environment(\.dismiss) private var dismiss
    @State private var expected: [Person] = []
    @State private var selected = Set<String>()
    @State private var targets: [String: String] = [:]
    @State private var follow = true
    @State private var search = ""
    @State private var result: String?
    private var visible: [SystemContactSnapshot] { contacts.contacts.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.preferredAddress.localizedCaseInsensitiveContains(search) } }
    private var unresolved: Bool { selected.contains { targets[$0] == nil } }
    @State private var matching: SystemContactSnapshot?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Choose who belongs here").font(.title2.weight(.semibold))
                    Text("Import only the people you want. Linked names, contact details and birthdays can follow Contacts changes; your Keep Close edits take precedence. Nothing is written back to Contacts.").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Toggle("Keep linked people updated from Contacts", isOn: $follow)
                    if let result {
                        Label(result, systemImage: "checkmark").font(.headline)
                        Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
                    } else if !contacts.loaded {
                        Button("Choose from Contacts") { Task { await contacts.load(requestPermission: true); prepare() } }.buttonStyle(.borderedProminent).disabled(contacts.busy)
                        if contacts.busy { ProgressView() }
                        Button("Open Contacts privacy settings") { contacts.openSettings() }
                    } else {
                        if contacts.limited {
                            Text("Contacts access is limited to people you've allowed.").font(.caption).foregroundStyle(.secondary)
                            Button("Allow more contacts in system settings") { contacts.openSettings() }
                        }
                        Button { selected = Set(contacts.contacts.map(\.id)) } label: { Text("Select all").frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()) }.buttonStyle(.borderless)
                        Button { selected = [] } label: { Text("Select none").frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()) }.buttonStyle(.borderless)
                        Text(String(selected.count) + " selected").font(.callout).foregroundStyle(.secondary)
                        if unresolved { Text("Review possible duplicates before importing.").font(.callout).foregroundStyle(.secondary) }
                    }
                    if let message = contacts.message { Text(message).font(.callout).foregroundStyle(.secondary) }
                }
                if contacts.loaded && result == nil {
                        ForEach(visible) { contact in
                            Section {
                                Toggle(isOn: Binding(get: { selected.contains(contact.id) }, set: { if $0 { selected.insert(contact.id) } else { selected.remove(contact.id) } })) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(contact.name).font(.headline).fixedSize(horizontal: false, vertical: true)
                                        if !contact.preferredAddress.isEmpty { Text(contact.preferredAddress).font(.caption).foregroundStyle(.secondary) }
                                        if let birthday = contact.birthday { Text("Birthday: " + birthday.label).font(.caption).foregroundStyle(.secondary) }
                                    }
                                }
                                if selected.contains(contact.id) {
                                    let match = ContactsIntegration.match(contact, people: expected, deviceID: contacts.deviceID)
                                    if match.reason == .linked { Text("Already linked to " + targetName(contact) + ". Re-importing updates this person.").font(.callout).foregroundStyle(.secondary) }
                                    else {
                                        Button { matching = contact } label: {
                                            HStack {
                                                Text(targets[contact.id] == nil ? "Choose a match…" : targetName(contact))
                                                Spacer(minLength: 8)
                                                Image(systemName: "chevron.right").accessibilityHidden(true)
                                            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                                        }.buttonStyle(.borderless).accessibilityLabel("Keep Close person for " + contact.name + ": " + targetName(contact))
                                        if match.reason == .name || match.candidates.count > 1 { Text("Possible duplicate — choose the right person or add someone new.").font(.caption).foregroundStyle(.secondary) }
                                        else if match.automaticID != nil { Text("Matched by a unique phone number or email.").font(.caption).foregroundStyle(.secondary) }
                                    }
                                }
                            }
                        }
                        if contacts.contacts.isEmpty { Text("No contacts are available. You can allow more contacts in system settings.").foregroundStyle(.secondary) }
                }
            }
            .searchable(text: $search, prompt: "Find a contact")
            .navigationTitle("Import Contacts")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Import selected") { apply() }.disabled(selected.isEmpty || unresolved || contacts.busy || result != nil) }
            }
            .sheet(item: $matching) { contact in
                ContactMatchChoiceView(contact: contact, people: expected, deviceID: contacts.deviceID) { targets[contact.id] = $0 }
            }
            .task { expected = store.people; await contacts.load(requestPermission: false); prepare() }
        }
        #if os(macOS)
        .frame(width: 650, height: 700)
        #endif
    }
    private func targetName(_ contact: SystemContactSnapshot) -> String {
        guard let target = targets[contact.id] else { return "Choose a match" }
        if target == "new" { return "Add as a new person" }
        return expected.first { $0.id.uuidString == target }?.name ?? "Choose a match"
    }
    private func prepare() {
        guard contacts.loaded else { return }
        expected = store.people
        for contact in contacts.contacts {
            let match = ContactsIntegration.match(contact, people: expected, deviceID: contacts.deviceID)
            targets[contact.id] = match.automaticID?.uuidString ?? (match.reason == .none ? "new" : nil)
        }
    }
    private func apply() {
        let choices = contacts.contacts.filter { selected.contains($0.id) }.map { ContactImportChoice(contact: $0, personID: targets[$0.id].flatMap(UUID.init(uuidString:)), follow: follow) }
        if store.importContacts(choices, deviceID: contacts.deviceID, expected: expected) { result = "Your selected contacts are here." }
        else { selected = []; prepare() }
    }
}

struct ContactMatchChoiceView: View {
    @Environment(\.dismiss) private var dismiss
    let contact: SystemContactSnapshot
    let people: [Person]
    let deviceID: String
    let choose: (String) -> Void
    @State private var search = ""
    private var candidates: Set<UUID> { Set(ContactsIntegration.match(contact, people: people, deviceID: deviceID).candidates) }
    private var visible: [Person] { people.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.address.localizedCaseInsensitiveContains(search) }.sorted { a, b in
        if candidates.contains(a.id) != candidates.contains(b.id) { return candidates.contains(a.id) }
        return a.name.localizedStandardCompare(b.name) == .orderedAscending
    } }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Who is " + contact.name + " in Keep Close?").font(.headline)
                    Button("Add as a new person") { choose("new"); dismiss() }
                }
                Section("Your people") {
                    ForEach(visible) { person in
                        Button { choose(person.id.uuidString); dismiss() } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(person.name).font(.headline)
                                if !person.address.isEmpty { Text(person.address).font(.caption).foregroundStyle(.secondary) }
                                if !person.context.isEmpty { Text(person.context).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                                if candidates.contains(person.id) { Text("Possible match").font(.caption).foregroundStyle(.secondary) }
                            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.borderless)
                    }
                }
            }.searchable(text: $search, prompt: "Find an existing person")
                .navigationTitle("Choose a person")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        #if os(macOS)
        .frame(width: 560, height: 550)
        #endif
    }
}

struct PersonMergeView: View {
    @Environment(RelationshipStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let person: Person
    @State private var otherID: UUID?
    @State private var search = ""
    @State private var sourceBirthday: Bool?
    @State private var merged: PeopleMerge?
    @State private var failure: String?
    private var other: Person? { store.people.first { $0.id == otherID } }
    private var birthdayConflict: Bool { if let a = person.birthday, let b = other?.birthday { return a != b }; return false }
    var body: some View {
        NavigationStack {
            Group {
                if merged != nil || other != nil {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) { review }
                            .padding(24).frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    List {
                        Section {
                            Text("Choose a duplicate of " + person.name).font(.title2.weight(.semibold))
                            Text("You'll review what is kept before merging.").foregroundStyle(.secondary)
                        }
                        Section {
                            ForEach(store.people.filter { $0.id != person.id && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) { other in
                                Button { otherID = other.id; sourceBirthday = nil } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(other.name).font(.headline)
                                        Text([other.address, other.context].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                                }.buttonStyle(.borderless)
                            }
                        }
                    }.searchable(text: $search, prompt: "Find the duplicate")
                }
            }.navigationTitle("Merge people")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        #if os(macOS)
        .frame(width: 600, height: 600)
        #endif
    }
    @ViewBuilder private var review: some View {
        if let merged {
            Label("Together in one place", systemImage: "checkmark").font(.title2)
            Text("Both histories, notes, plans and contact links are now with " + merged.kept.name + ".")
            Button("Undo merge") { if store.undoMerge(merged) { self.merged = nil; otherID = nil; failure = nil } }
            Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
        } else if let other {
            Text("Keep " + person.name).font(.title2.weight(.semibold))
            Text("Merge " + other.name + " into this person. Both histories, context, plans and Contacts links will be kept. Your chosen person's name, contact preference and rhythm stay in place. Give Space, pause and set-aside ideas remain respected.").foregroundStyle(.secondary)
            Text(String(person.contacts.count + other.contacts.count) + " contact records · " + String(person.plans.count + other.plans.count) + " plans").font(.callout)
            if let a = person.birthday, let b = other.birthday, a != b {
                Picker("Birthday to keep", selection: $sourceBirthday) {
                    Text("Choose birthday…").tag(Optional<Bool>.none)
                    Text(a.label).tag(Optional(false)); Text(b.label).tag(Optional(true))
                }
            }
            if !person.address.isEmpty && !other.address.isEmpty && person.address != other.address { Text("Preferred contact: " + person.address + ". The other contact detail will be retained too.").font(.callout) }
            Text("A private backup is made before merging. Undo is available here until either person changes again.").font(.caption).foregroundStyle(.secondary)
            Button("Merge people") {
                do { let plan = try PeopleMerge(keeping: person, merging: other, useSourceBirthday: sourceBirthday == true); if store.merge(plan) { merged = plan } }
                catch { failure = error.localizedDescription }
            }.buttonStyle(.borderedProminent).disabled(birthdayConflict && sourceBirthday == nil)
            Button("Choose someone else") { otherID = nil; sourceBirthday = nil }
        }
        if let failure { Text(failure).foregroundStyle(.red) }
    }
}
