import SwiftUI
import Combine
import Sparkle

/// Sparkle's updater. The feed (`SUFeedURL`) and the EdDSA public key (`SUPublicEDKey`) are in Info.plist;
/// the release workflow publishes `appcast.xml` (universal), `appcast-arm64.xml` and `appcast-intel.xml` with each GitHub release.
@MainActor
enum Updates {
    /// Tests launch the app as their host; they never check for updates.
    private static let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    /// Sparkle refuses to start, with an alert at every launch, until `SUPublicEDKey` holds a real EdDSA key
    /// (scripts/setup-sparkle-keys.sh writes it). Builds without one simply don't update.
    private static let hasSigningKey = (Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String)
        .flatMap { Data(base64Encoded: $0) }?.count == 32

    static let controller = SPUStandardUpdaterController(startingUpdater: hasSigningKey && !isTesting, updaterDelegate: UpdateFeed.shared, userDriverDelegate: nil)
    static var updater: SPUUpdater { controller.updater }
}

/// Each Mac reads the appcast for its own processor: Apple silicon `appcast-arm64.xml`, Intel `appcast-intel.xml`.
/// `appcast.xml` (the Info.plist feed, universal) is what builds from before the split read, so it stays for them.
/// The choice is made by the running app, so a universal install moves to its processor's archive on the next check.
final class UpdateFeed: NSObject, SPUUpdaterDelegate {
    static let shared = UpdateFeed()
    static let appleSiliconFeed = "https://github.com/spaquet/markify/releases/latest/download/appcast-arm64.xml"
    static let intelFeed = "https://github.com/spaquet/markify/releases/latest/download/appcast-intel.xml"

    /// `hw.optional.arm64` is 1 on Apple silicon, including while the app runs translated under Rosetta.
    static var isAppleSilicon: Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 && value == 1
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        Self.isAppleSilicon ? Self.appleSiliconFeed : Self.intelFeed
    }
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
