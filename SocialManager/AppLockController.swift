import SwiftUI
import LocalAuthentication
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// `LAContext` isn't `Sendable`. Keep Close creates, evaluates and invalidates it from the main
/// actor only, so this unchecked conformance records the single owner the compiler can't infer.
/// Evaluation runs through a nonisolated method so the context is never sent across isolation.
private struct AuthenticationContext: @unchecked Sendable {
    let value: LAContext
    func evaluate(reason: String) async throws -> Bool {
        try await value.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
    }
}

@MainActor @Observable final class AppLockController {
    private var session: AppLockSession
    var authenticating = false
    var message: String?
    var obscured = false
    private var context: AuthenticationContext?
    private var activeAttempt: UInt64?
    private let repository = RelationshipRepository()
    init() {
        do { session = AppLockSession(enabled: try repository.appLockEnabled()) }
        catch {
            session = AppLockSession(enabled: true)
            message = "Couldn't read the app lock setting. Authenticate to access Keep Close: \(error.localizedDescription)"
        }
    }
    var enabled: Bool { session.enabled }
    var locked: Bool { session.isLocked }
    var unlockLabel: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        switch context.biometryType {
        case .faceID: return "Unlock with Face ID"
        case .touchID: return "Unlock with Touch ID"
        default: return "Unlock with device authentication"
        }
    }
    func authenticate(_ intent: AppLockSession.Intent) async {
        guard !authenticating else { return }
        message = nil
        let context = AuthenticationContext(value: LAContext())
        var error: NSError?
        guard context.value.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            message = error?.localizedDescription ?? "Set a device passcode or login password before enabling app lock."
            return
        }
        let attempt = session.beginAuthentication()
        self.context = context; activeAttempt = attempt; authenticating = true
        defer {
            if activeAttempt == attempt { self.context = nil; activeAttempt = nil; authenticating = false }
        }
        let reason: String
        switch intent {
        case .enable: reason = "Enable authentication before viewing your relationships."
        case .disable: reason = "Turn off the Keep Close app lock."
        case .unlock: reason = "Unlock your relationships in Keep Close."
        }
        do {
            let granted = try await context.evaluate(reason: reason)
            guard activeAttempt == attempt else { return }
            var authenticated = session
            if granted && authenticated.authenticationSucceeded(intent, attempt: attempt) {
                if authenticated.enabled != session.enabled { try repository.setAppLockEnabled(authenticated.enabled) }
                session = authenticated
            } else { message = "Authentication didn't complete. Your app lock setting hasn't changed." }
        } catch {
            guard activeAttempt == attempt else { return }
            let code = (error as? LAError)?.code
            if code != .userCancel && code != .systemCancel && code != .appCancel { message = error.localizedDescription }
        }
    }
    func lock() {
        context?.value.invalidate(); context = nil; activeAttempt = nil; authenticating = false
        session.lock(); message = nil
    }
    func phaseChanged(_ phase: ScenePhase) {
        obscured = enabled && phase != .active
        if enabled && (phase == .background || phase == .inactive && !authenticating) { lock() }
    }
}

struct ProtectedAppView: View {
    @Environment(AppLockController.self) private var appLock
    @Environment(RelationshipStore.self) private var store
    @Environment(BirthdayReminders.self) private var birthdays
    @Environment(\.scenePhase) private var phase
    var body: some View {
        ZStack {
            if appLock.locked { LockedAppView() }
            else { AppView().accessibilityHidden(appLock.obscured).allowsHitTesting(!appLock.obscured) }
            if appLock.obscured {
                lockCover.accessibilityHidden(true)
            }
        }
        .transaction { $0.disablesAnimations = appLock.locked || appLock.obscured }
        .task { await store.watchChanges() }
        .task {
            // The lock gates screens; already-authorized local reminders keep reflecting edits.
            while !Task.isCancelled {
                await birthdays.refresh(people: store.people, names: store.includeNamesInReminders)
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            }
        }
        .onChange(of: store.people) { _, _ in Task { await birthdays.refresh(people: store.people, names: store.includeNamesInReminders) } }
        .onChange(of: store.includeNamesInReminders) { _, _ in Task { await birthdays.refresh(people: store.people, names: store.includeNamesInReminders) } }
        .onChange(of: phase, initial: true) { _, phase in
            appLock.phaseChanged(phase)
            if phase == .active { Task { await store.refreshNotificationPrivacy(); await birthdays.refresh(people: store.people, names: store.includeNamesInReminders) } }
        }
        .onChange(of: appLock.enabled) { _, _ in appLock.phaseChanged(phase) }
        #if os(macOS)
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.sessionDidResignActiveNotification)) { _ in appLock.lock() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)) { _ in appLock.lock() }
        #else
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in appLock.lock() }
        #endif
        #if os(macOS)
        .frame(minWidth: 760, minHeight: 560)
        #endif
    }
    private var lockCover: some View {
        VStack(spacing: 12) { Image(systemName: "lock.fill").font(.largeTitle); Text("Keep Close").font(.title2.bold()) }
            .frame(maxWidth: .infinity, maxHeight: .infinity).background(.background).ignoresSafeArea()
    }
}
struct LockedAppView: View {
    @Environment(AppLockController.self) private var appLock
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.fill").font(.system(size: 42)).foregroundStyle(.teal)
            Text("Keep Close is locked").font(.title.bold())
            Text("Authenticate to view your people and notes.").foregroundStyle(.secondary)
            Button(appLock.authenticating ? "Authenticating…" : appLock.unlockLabel) { Task { await appLock.authenticate(.unlock) } }.buttonStyle(.borderedProminent).disabled(appLock.authenticating)
            Text("Your device passcode or login password is available as a fallback.").font(.caption).foregroundStyle(.secondary)
            if let message = appLock.message { Text(message).foregroundStyle(.red).font(.callout) }
        }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity).background(.background)
    }
}
