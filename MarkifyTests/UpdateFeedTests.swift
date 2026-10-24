import Foundation
import Testing
@testable import Markify

@MainActor struct UpdateFeedTests {
    /// Sparkle calls the feed delegate by this selector; a renamed method would be ignored without any error.
    @Test func delegateAnswersSparklesFeedSelector() {
        #expect(UpdateFeed.shared.responds(to: NSSelectorFromString("feedURLStringForUpdater:")))
    }

    @Test func architecturesHaveTheirOwnFeeds() {
        #expect(UpdateFeed.appleSiliconFeed.hasSuffix("/appcast-arm64.xml"))
        #expect(UpdateFeed.intelFeed.hasSuffix("/appcast-intel.xml"))
    }
}
