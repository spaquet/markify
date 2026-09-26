import SwiftUI
import Combine
import Sparkle

/// Sparkle's updater. The feed (`SUFeedURL`) and the EdDSA public key (`SUPublicEDKey`) are in Info.plist;
/// the release workflow publishes `appcast.xml` with each GitHub release.
@MainActor
enum Updates {
    /// Tests launch the app as their host; they never check for updates.
    private static let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    static let controller = SPUStandardUpdaterController(startingUpdater: !isTesting, updaterDelegate: nil, userDriverDelegate: nil)
    static var updater: SPUUpdater { controller.updater }
}

/// Mirrors `SPUUpdater.canCheckForUpdates`, which is false while a check or an install is under way.
@MainActor
final class UpdateState: ObservableObject {
    @Published private(set) var canCheckForUpdates = false

    init(updater: SPUUpdater = Updates.updater) {
        updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheckForUpdates)
    }
}

struct CheckForUpdatesButton: View {
    @StateObject private var state = UpdateState()

    var body: some View {
        Button("Check for Updates…") { Updates.updater.checkForUpdates() }
            .disabled(!state.canCheckForUpdates)
    }
}
