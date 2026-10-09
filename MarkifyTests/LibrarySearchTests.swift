import AppKit
import CoreSpotlight
import MarkifyMarkdown
import Testing
@testable import Markify

struct LibrarySearchTests {
    @Test func searchableTextUsesModelAndPreservesSource() {
        let source = "---\ntitle: Hidden metadata\n---\n# A **heading**\nSome **important** text and [a link](target.md).\n```swift\nlet secret = 42\n```\n"
        let model = MarkdownModel(source)
        let text = SearchNote.searchableText(model)
        #expect(text.contains("Some important text and a link"))
        #expect(text.contains("let secret = 42"))
        #expect(!text.contains("Hidden metadata"))
        #expect(!text.contains("target.md"))
        #expect(model.source == source)
    }

    @Test func snippetsKeepUTF16OffsetsAndNeverInventRelatedRanges() {
        let url = URL(fileURLWithPath: "/tmp/note.md")
        let note = SearchNote(url: url, title: "Note", description: "An outline", type: nil, tags: [], roots: [], scopes: [], modified: .distantPast)
        let source = "# Intro\n😀 café\n## Details\nA NEEDLE here and another needle.\n"
        let result = SearchMatch.make(note: note, source: source, query: "needle", headings: true)
        #expect(result.line == 4)
        #expect(result.count == 2)
        #expect(result.heading == "Details")
        #expect(result.sourceRange == (source as NSString).range(of: "NEEDLE"))
        #expect(result.ranges.count == 2)
        for range in result.ranges { #expect((result.snippet as NSString).substring(with: range).lowercased() == "needle") }
        let separated = SearchMatch.make(note: note, source: source, query: "details needle", headings: true)
        #expect(separated.line == 3)
        #expect(separated.count == 3)
        #expect(!separated.related)
        #expect(SearchMatch.literalRanges(in: source, query: " needle ") == SearchMatch.literalRanges(in: source, query: "needle"))
        let related = SearchMatch.make(note: note, source: source, query: "navigation", headings: true)
        #expect(related.related)
        #expect(related.sourceRange == nil)
        #expect(related.line == nil)
        let title = SearchMatch.make(note: note, source: source, query: "Note", headings: false)
        #expect(!title.related)
        #expect(title.sourceRange == nil)
    }

    @Test func rootMembershipUsesComponentsAndFilterValuesAreEscaped() {
        #expect(SearchNote.contains(URL(fileURLWithPath: "/tmp/docs"), URL(fileURLWithPath: "/tmp/docs/nested/a.md")))
        #expect(!SearchNote.contains(URL(fileURLWithPath: "/tmp/docs"), URL(fileURLWithPath: "/tmp/docs-other/a.md")))
        #expect(SearchSession.filter(attribute: "markifyTags", value: "a\"b\\c") == "markifyTags == \"a\\\"b\\\\c\"")
    }

    @Test func resolvedPathsFollowSymlinksAndRefreshOnReplace() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("first"), second = root.appendingPathComponent("second")
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: first)
        #expect(SearchNote.identifier(link) == SearchNote.identifier(first))
        #expect(SearchNote.contains(link, first.appendingPathComponent("a.md")))
        try FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: second)
        ResolvedPaths.replace(with: [link])
        #expect(SearchNote.identifier(link) == SearchNote.identifier(second))
    }

    /// An isolated domain proves the actual Spotlight predicates, including multi-valued nested memberships.
    @Test @MainActor func spotlightLifecycleAndScopedFullTextSearch() async throws {
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let domain = "markifytest" + token
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(domain)
        let nested = root.appendingPathComponent("Guides/Deep")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = [root.appendingPathComponent("README.md"), nested.appendingPathComponent("README.markdown"), nested.appendingPathComponent("Widget.mdx")]
        for (number, file) in files.enumerated() {
            try "---\ntitle: Search fixture \(number)\ntype: Reference\ntags: [spotlight-test]\ndescription: A fixture\n---\n# Guide\n\n\(String(repeating: "Unrelated paragraph.\n", count: 30))\n\(token) at the bottom.\n".write(to: file, atomically: true, encoding: .utf8)
        }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("node_modules"), withIntermediateDirectories: true)
        try token.write(to: root.appendingPathComponent("node_modules/skipped.md"), atomically: true, encoding: .utf8)
        let folders = [SearchFolder(path: root.path, bookmark: Data(), kind: "Library"), SearchFolder(path: nested.path, bookmark: Data(), kind: "Project")]
        let worker = SpotlightWorker(name: domain, domain: domain, persistenceKey: nil)
        let snapshot = try await worker.refresh(folders: folders, options: SearchOptions(), rebuild: true) { _ in }
        #expect(snapshot.notes.count == 3)
        #expect(snapshot.notes.first { $0.id == SearchNote.identifier(files[1]) }?.roots.count == 2)
        #expect(snapshot.notes.allSatisfy { $0.type == "Reference" && $0.tags == ["spotlight-test"] })
        do {
            let found = try await eventually(query: token, domain: domain, count: 3)
            #expect(Set(found) == Set(snapshot.notes.map(\.id)))
            let scoped = try await eventually(query: token, domain: domain, scope: folders[1].id, count: 2)
            #expect(Set(scoped) == Set(snapshot.notes.filter { $0.roots.contains(folders[1].id) }.map(\.id)))
            let folderScoped = try await eventually(query: token, domain: domain, scope: SearchNote.identifier(root.appendingPathComponent("Guides")), count: 2)
            #expect(Set(folderScoped) == Set(scoped))
            let filtered = try await eventually(query: token, domain: domain, tag: "spotlight-test", count: 3)
            #expect(filtered.count == 3)
            _ = try await eventually(query: token, domain: domain, type: "Reference", count: 3)
            _ = try await eventually(query: "Deep", domain: domain, count: 2)
            let context = await worker.matches(snapshot.notes, query: token, options: SearchOptions())
            #expect(context.allSatisfy { $0.sourceRange != nil && ($0.line ?? 0) > 30 })
            // External edit, deletion and move: refresh updates the existing physical-note identifier and removes old entries.
            try "# Changed\nreplacement \(token)\n".write(to: files[0], atomically: true, encoding: .utf8)
            try FileManager.default.removeItem(at: files[1])
            let moved = root.appendingPathComponent("Moved.mdx")
            try FileManager.default.moveItem(at: files[2], to: moved)
            let refreshed = try await worker.refresh(folders: folders, options: SearchOptions(), rebuild: false) { _ in }
            #expect(refreshed.notes.count == 2)
            let afterMove = try await eventually(query: token, domain: domain, count: 2)
            #expect(Set(afterMove) == Set(refreshed.notes.map(\.id)))
            let removedRoot = try await worker.refresh(folders: [folders[0]], options: SearchOptions(), rebuild: false) { _ in }
            #expect(removedRoot.notes.allSatisfy { $0.roots == [folders[0].id] })
            var options = SearchOptions(); options.extensions = ["md"]
            let mdOnly = try await worker.refresh(folders: [folders[0]], options: options, rebuild: false) { _ in }
            #expect(mdOnly.notes.count == 1)
            _ = try await eventually(query: token, domain: domain, count: 1)
            _ = try await worker.refresh(folders: [], options: options, rebuild: false) { _ in }
            _ = try await eventually(query: token, domain: domain, count: 0)
            _ = try await worker.refresh(folders: folders, options: SearchOptions(), rebuild: true) { _ in }
            _ = try await eventually(query: token, domain: domain, count: 2)
            let denied = SearchFolder(path: root.appendingPathComponent("Denied").path, bookmark: Data("invalid bookmark".utf8), kind: "Project")
            let accessCheck = try await worker.refresh(folders: folders + [denied], options: SearchOptions(), rebuild: false) { _ in }
            #expect(accessCheck.status[denied.id] == "Access expired")
            #expect(accessCheck.notes.count == 2)
            var withoutMetadata = SearchOptions(); withoutMetadata.metadata = false; withoutMetadata.headings = false
            let stripped = try await worker.refresh(folders: folders, options: withoutMetadata, rebuild: false) { _ in }
            #expect(stripped.notes.allSatisfy { $0.type == nil && $0.tags.isEmpty })
            _ = try await eventually(query: token, domain: domain, tag: "spotlight-test", count: 0)
            try await worker.delete()
            _ = try await eventually(query: token, domain: domain, count: 0)
        } catch {
            try? await worker.delete()
            throw error
        }
    }

    @MainActor private func eventually(query text: String, domain: String, scope: String? = nil, type: String? = nil, tag: String? = nil, count: Int) async throws -> [String] {
        var last: [String] = []
        for _ in 0..<60 {
            let context = CSUserQueryContext()
            context.enableRankedResults = true
            context.disableSemanticSearch = true
            context.filterQueries = [SearchSession.filter(attribute: "domainIdentifier", value: domain)]
            if let scope { context.filterQueries.append(SearchSession.filter(attribute: "markifyScopes", value: scope)) }
            if let type { context.filterQueries.append(SearchSession.filter(attribute: "markifyType", value: type)) }
            if let tag { context.filterQueries.append(SearchSession.filter(attribute: "markifyTags", value: tag)) }
            let query = CSUserQuery(userQueryString: text, userQueryContext: context)
            var results: [String] = []
            for try await result in query.results { results.append(result.item.uniqueIdentifier) }
            last = results
            if results.count == count { return results }
            try await Task.sleep(for: .milliseconds(500))
        }
        Issue.record("Spotlight returned \(last.count) items, expected \(count); IDs: \(last)")
        return last
    }
}
