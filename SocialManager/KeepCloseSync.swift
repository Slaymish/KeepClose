import SwiftUI
import CoreFoundation
import NativeCore
import NativeSync
import NativeUI

@MainActor enum KeepCloseSync {
    static var isPreview: Bool { CommandLine.arguments.contains("--demo") }
    static let service = SyncService(namespace: RelationshipRepository.syncNamespace,
        serviceType: "_keepclose._tcp", repository: RelationshipRepository())
    static func title(_ key: String) -> String {
        if key == "settings/reminder" { return "Reminder preferences" }
        if key.hasPrefix("checkpoint/") { return "Agent update checkpoint" }
        let version = service.conflicts.first { $0.id == key }?.versions.first { $0.payload != nil }
        if let bytes = version?.payload, let person = try? NativeJSON.decode(Person.self, from: bytes, dates: .deferredToDate) {
            return person.name
        }
        return "Relationship"
    }
    static func description(_ version: SyncVersion) -> String {
        guard let bytes = version.payload else { return "Deleted record" }
        guard let object = try? JSONSerialization.jsonObject(with: bytes) else { return "Saved record" }
        func label(_ key: String) -> String {
            let known = ["context": "Personal notes", "contexts": "Shared contexts", "types": "Relationship types",
                         "importSources": "Imported from", "includeNames": "Names in unlocked notification previews"]
            if let title = known[key] { return title }
            return key.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression).capitalized
        }
        func describe(_ value: Any, key: String = "", indent: String = "") -> String {
            if let dictionary = value as? [String: Any] {
                return dictionary.keys.sorted().map { field in
                    indent + label(field) + ": " + describe(dictionary[field]!, key: field, indent: indent + "  ")
                }.joined(separator: "\n")
            }
            if let array = value as? [Any] {
                if array.isEmpty { return "None" }
                return "\n" + array.enumerated().map { offset, child in
                    indent + "\(offset + 1). " + describe(child, indent: indent + "  ")
                }.joined(separator: "\n")
            }
            if let number = value as? NSNumber {
                if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "Yes" : "No" }
                if ["date", "createdAt", "resolvedAt", "completedAt", "cancelledAt", "plannedAt", "at"].contains(key) {
                    return Date(timeIntervalSinceReferenceDate: number.doubleValue).formatted()
                }
                return number.stringValue
            }
            if value is NSNull { return "None" }
            return String(describing: value)
        }
        return describe(object)
    }
}

struct KeepCloseSyncSettings: View {
    var body: some View {
        #if DEBUG
        if CommandLine.arguments.contains("--demo") {
            ContentUnavailableView("Fictional preview", systemImage: "network", description: Text("Device sync is disabled for preview data."))
        } else { settings }
        #else
        settings
        #endif
    }
    @ViewBuilder private var settings: some View {
        if KeepCloseSync.isPreview {
            Text("Device sync is unavailable in the fictional preview.")
        } else {
            SyncSettingsView(service: KeepCloseSync.service, recordTitle: KeepCloseSync.title,
                             versionDescription: KeepCloseSync.description)
        }
    }
}

/// The UI lock hides records; previously authorised device sync remains independent of screen authentication.
struct KeepCloseSyncLifecycle: ViewModifier {
    @Environment(\.scenePhase) private var phase
    func body(content: Content) -> some View {
        content.onChange(of: phase, initial: true) { _, phase in
            guard !KeepCloseSync.isPreview else { return }
            #if DEBUG
            // Fictional previews must never join a real paired-device session.
            if CommandLine.arguments.contains("--demo") { return }
            #endif
            #if os(iOS)
            if phase == .active { KeepCloseSync.service.start() }
            else if phase == .background { KeepCloseSync.service.stop() }
            #else
            if phase == .active { KeepCloseSync.service.start() }
            #endif
        }
    }
}
