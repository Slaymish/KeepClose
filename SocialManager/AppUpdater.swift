#if os(macOS)
import SwiftUI
import Sparkle

@MainActor final class AppUpdater: ObservableObject {
    @Published var canCheck = false
    private let controller: SPUStandardUpdaterController
    init() {
        // Local debug builds do not phone home or replace the developer's running build.
        #if DEBUG
        let start = false
        #else
        let start = true
        #endif
        controller = SPUStandardUpdaterController(startingUpdater: start, updaterDelegate: nil, userDriverDelegate: nil)
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheck)
    }
    func check() { controller.checkForUpdates(nil) }
}
struct CheckForUpdatesView: View {
    @ObservedObject var updater: AppUpdater
    var body: some View { Button("Check for Updates…") { updater.check() }.disabled(!updater.canCheck) }
}
#endif
