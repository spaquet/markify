import Foundation
import Sentry

/// Counts how often a view's body runs and leaves a Sentry breadcrumb when it runs in a burst. An app-hang report
/// taken inside a body (MARKIFY-13) then shows whether SwiftUI was re-evaluating the view in a loop or one update
/// was slow. The breadcrumb is added while the burst is still running, so a hang caught during it carries it.
@MainActor enum UpdateRate {
    /// Body updates within one second that count as a burst; typing and scrolling stay well below it.
    static let burst = 60
    private static var windows: [String: (start: TimeInterval, count: Int)] = [:]

    static func tick(_ view: String) {
        let now = ProcessInfo.processInfo.systemUptime
        var window = windows[view] ?? (now, 0)
        if now - window.start >= 1 { window = (now, 0) }
        window.count += 1
        windows[view] = window
        if window.count == burst || window.count == burst * 10 {
            let crumb = Breadcrumb(level: .warning, category: "ui.update")
            crumb.message = "\(view).body ran \(window.count) times in \(Int((now - window.start) * 1000)) ms"
            SentrySDK.addBreadcrumb(crumb)
        }
    }
}
