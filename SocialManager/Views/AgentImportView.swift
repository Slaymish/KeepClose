import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct AgentImportView: View {
    @Environment(RelationshipStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let provider: ImportProvider
    @State private var copied = false
    @State private var choosingFile = false
    @State private var payload = ""
    @State private var batch: AgentImportBatch?
    @State private var plan: AgentImportPlan?
    @State private var originalPeople: [Person] = []
    @State private var selected = Set<Int>()
    /// Ideas the user has chosen to set aside during this review, by record index.
    @State private var setAside = Set<String>()
    @State private var failure: String?
    @State private var result: AgentImportResult?
    @State private var prompt = ""
    private var operation: String { store.hasImported(provider) ? "Update" : "Import" }
    private static var cliPath: String? {
        #if os(macOS)
        var folder = Bundle.main.bundleURL.deletingLastPathComponent()
        while folder.path != "/" {
            let script = folder.appendingPathComponent("scripts/keepclose")
            if FileManager.default.fileExists(atPath: script.path) { return script.path }
            folder.deleteLastPathComponent()
        }
        #endif
        return nil
    }
    var body: some View {
        NavigationStack {
            Form {
                if let result {
                    Section {
                        Label("Your people are updated", systemImage: "checkmark.circle.fill").font(.title2).foregroundStyle(.teal)
                        Text("\(result.added) added · \(result.updated) merged · \(result.unchanged) already here")
                        if result.newIdeas > 0 { Text("\(result.newIdeas) new \(result.newIdeas == 1 ? "idea" : "ideas") to review. Nothing is being scheduled.").foregroundStyle(.secondary) }
                        Text("You can choose a direction for anyone marked Unsure, and edit or set aside any idea in People.").foregroundStyle(.secondary)
                        if result.backupPath != nil { Text("A backup was saved before changing existing data.").font(.caption).foregroundStyle(.secondary) }
                        Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
                    }
                } else {
                    Section("1. Ask \(provider.title)") {
                        Text(operation == "Update" ? "Share your current records and edits with your agent, update its accessible memories, and bring new people or context back." : "Ask your agent to collect the people it knows about from accessible memories and conversations.")
                        Text("The copied prompt includes your current people, notes, memories, ideas and contact history. Only share it with a chat you want to have that information. Copying it sends nothing by itself.").font(.caption).foregroundStyle(.secondary)
                        Button(copied ? "Prompt copied" : "Copy prompt for \(provider.title)", systemImage: copied ? "checkmark" : "doc.on.doc") { copyPrompt() }.buttonStyle(.borderedProminent)
                        Text(Self.cliPath == nil ? "Paste the prompt into a chat. Bring the returned file or JSON back here." : "Paste the prompt into a chat. A local agent can import directly through the CLI; other chats can return a file to bring back here.").font(.callout).foregroundStyle(.secondary)
                        DisclosureGroup("Read the prompt") { Text(prompt).font(.caption).textSelection(.enabled) }
                    }
                    Section("2. Bring back the result") {
                        Button("Choose import file…", systemImage: "doc") { choosingFile = true }
                        DisclosureGroup("Or paste JSON") {
                            TextEditor(text: $payload).font(.system(.caption, design: .monospaced)).frame(height: 150)
                            Button("Preview pasted result") { preview(Data(payload.utf8)) }.disabled(payload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        Text("Preview additions and merges before importing. Existing intentions, rhythms, history and your own wording stay as you set them.").font(.caption).foregroundStyle(.secondary)
                    }
                    if let failure { Section { Label(failure, systemImage: "exclamationmark.circle").foregroundStyle(.red) } }
                    if let plan {
                        Section("3. Choose what to keep") {
                            Text("\(plan.added) new · \(plan.updated) merge · \(plan.unchanged) already here\(plan.newIdeaCount > 0 ? " · \(plan.newIdeaCount) new ideas" : "")")
                            if plan.respectedDismissals > 0 {
                                Text("\(plan.respectedDismissals) \(plan.respectedDismissals == 1 ? "idea" : "ideas") you set aside stayed set aside.").font(.caption).foregroundStyle(.teal)
                            }
                            Button("Refresh preview") { refreshPreview() }
                            if plan.changes.isEmpty { Text("No people were included. Ask your agent to return the people it can identify.").foregroundStyle(.secondary) }
                            ForEach(Array(plan.changes.enumerated()), id: \.offset) { index, change in
                                VStack(alignment: .leading, spacing: 8) {
                                    Toggle(isOn: Binding(get: { selected.contains(index) }, set: { enabled in if enabled { selected.insert(index) } else { selected.remove(index) } })) {
                                        Text("\(change.person.name) · \(change.action == "add" ? "New" : change.action == "merge" ? "Merge" : "Already here")").font(.headline)
                                    }.disabled(change.action == "unchanged")
                                    Text(change.explanation).font(.caption).foregroundStyle(.secondary)
                                    if !change.newIdeas.isEmpty {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Ideas to consider").font(.caption).foregroundStyle(.secondary)
                                            ForEach(change.newIdeas, id: \.self) { activity in
                                                Toggle(activity, isOn: Binding(get: { !setAside.contains("\(index)|\(activity)") }, set: { keep in
                                                    let key = "\(index)|\(activity)"
                                                    if keep { setAside.remove(key) } else { setAside.insert(key) }
                                                })).font(.callout)
                                            }
                                            Text("Unchecked ideas are set aside, so they won't be suggested again or brought back by later imports. Clearing a suggested activity never deletes anything you recorded yourself.").font(.caption2).foregroundStyle(.secondary)
                                        }
                                    }
                                    DisclosureGroup("Details") {
                                        Text((change.person.relationshipTypes + change.person.contexts).joined(separator: " · ")).font(.callout)
                                        Text("Intention: \(change.person.intention.title) · Rhythm: \(change.person.rhythmDays) days").font(.caption).foregroundStyle(.secondary)
                                        if !change.person.address.isEmpty { Text("\(change.person.method.rawValue): \(change.person.address)").font(.caption) }
                                        if !change.person.interests.isEmpty { Text("Interests: \(change.person.interests.map(\.name).joined(separator: ", "))").font(.caption) }
                                        if !change.person.memories.isEmpty { Text("Memories: \(change.person.memories.map(\.text).joined(separator: " · "))").font(.caption).foregroundStyle(.secondary) }
                                        if !change.person.context.isEmpty { Text(change.person.context).font(.callout).textSelection(.enabled) }
                                    }
                                }.padding(.vertical, 6)
                            }
                            Button("Apply \(selected.count) \(selected.count == 1 ? "person" : "people")") { apply() }.buttonStyle(.borderedProminent)
                        }
                    }
                }
            }.formStyle(.grouped).navigationTitle("\(operation) from \(provider.title)")
                .task { loadPrompt() }
                .onChange(of: payload) { _, _ in plan = nil; batch = nil; selected = []; setAside = [] }
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(result == nil ? "Close" : "Done") { dismiss() } } }
                .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.json, .plainText], allowsMultipleSelection: false) { selection in
                    do {
                        guard let url = try selection.get().first else { return }
                        let scoped = url.startAccessingSecurityScopedResource()
                        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                        let handle = try FileHandle(forReadingFrom: url)
                        defer { try? handle.close() }
                        preview(try handle.read(upToCount: 2_000_001) ?? Data())
                    } catch { plan = nil; batch = nil; selected = []; setAside = []; failure = "Couldn't read the import file: \(error.localizedDescription)" }
                }
        }
        #if os(macOS)
        .frame(width: 660, height: 720)
        #endif
    }
    private func loadPrompt() {
        do { prompt = try store.agentPrompt(provider, cliPath: Self.cliPath) }
        catch { failure = error.localizedDescription; prompt = "" }
    }
    private func copyPrompt() {
        loadPrompt()
        guard !prompt.isEmpty else { return }
        #if os(macOS)
        NSPasteboard.general.clearContents()
        copied = NSPasteboard.general.setString(prompt, forType: .string)
        #else
        UIPasteboard.general.string = prompt; copied = true
        #endif
    }
    private func preview(_ data: Data) {
        failure = nil; plan = nil; batch = nil; selected = []; setAside = []
        do {
            let imported = try AgentImportBatch.parse(data)
            let preview = try store.previewImport(imported)
            batch = imported; plan = preview.0; originalPeople = preview.1
            selected = Set(preview.0.changes.indices.filter { preview.0.changes[$0].action != "unchanged" })
        } catch { failure = "Couldn't preview this import: \(error.localizedDescription)" }
    }
    private func refreshPreview() {
        guard let batch else { return }
        do {
            let preview = try store.previewImport(batch)
            plan = preview.0; originalPeople = preview.1
            selected = selected.filter { preview.0.changes.indices.contains($0) && preview.0.changes[$0].action != "unchanged" }
            failure = nil
        } catch { plan = nil; selected = []; failure = error.localizedDescription }
    }
    private func apply() {
        guard var batch else { return }
        let kept = batch.people.enumerated().filter { selected.contains($0.offset) }
        batch.people = kept.map { index, record in
            var record = record
            let aside = setAside.filter { $0.hasPrefix("\(index)|") }.map { String($0.dropFirst("\(index)|".count)) }
            if !aside.isEmpty, var context = record.context {
                context.ideas = (context.ideas ?? []).filter { !aside.contains($0.activity) }
                record.context = context
            }
            return record
        }
        do { result = try store.applyImport(batch, expected: originalPeople); failure = nil }
        catch { failure = error.localizedDescription }
    }
}
