import Foundation
import os

/// Resolves security-scoped bookmarks once per launch.
///
/// Each resolution is a synchronous XPC round trip to ScopedBookmarksAgent; under memory
/// pressure one call took over two seconds on the main thread (MARKIFY-1Q). The same bookmark
/// data resolves to the same URL for the life of the process, so callers share one answer.
/// Failures are not kept, so a folder on a volume mounted later still resolves.
/// Starting and stopping access stays with each caller.
enum Bookmarks {
    struct Resolved: Sendable { let url: URL; let stale: Bool }

    private static let cache = OSAllocatedUnfairLock<[Data: Resolved]>(initialState: [:])

    static func resolve(_ data: Data) -> Resolved? {
        guard !data.isEmpty else { return nil }
        if let cached = cache.withLock({ $0[data] }) { return cached }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, bookmarkDataIsStale: &stale) else { return nil }
        let resolved = Resolved(url: url, stale: stale)
        cache.withLock { $0[data] = resolved }
        return resolved
    }

    /// The URL of a bookmark that resolved and is not stale.
    static func url(_ data: Data) -> URL? {
        guard let resolved = resolve(data), !resolved.stale else { return nil }
        return resolved.url
    }
}
