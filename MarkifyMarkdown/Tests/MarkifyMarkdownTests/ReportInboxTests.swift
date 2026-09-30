import Foundation
import Testing
@testable import MarkifyMarkdown

struct ReportInboxTests {
    @Test func roundTripAndURLValidation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let inbox = ReportInbox(directory: directory)
        let report = MarkifyReport(text: "# café 🌻\r\n\r\nNo final newline", title: "A & B", baseDirectory: "/private/tmp")
        let id = try inbox.write(report)
        #expect(try inbox.read(id) == report)
        #expect(try ReportInbox.id(from: ReportInbox.url(for: id)) == id)
        #expect(try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? Int == 0o700)
        #expect(try FileManager.default.attributesOfItem(atPath: inbox.file(for: id).path)[.posixPermissions] as? Int == 0o600)
        #expect(throws: (any Error).self) { try ReportInbox.id(from: URL(string: "markify://view?id=../secret")!) }
        #expect(throws: (any Error).self) { try ReportInbox.id(from: URL(string: ReportInbox.url(for: id).absoluteString + "&id=" + id.uuidString)!) }
        try inbox.remove(id)
        #expect(throws: (any Error).self) { try inbox.read(id) }
    }

    @Test func rejectsSymlinksVersionsAndOversizedReports() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let inbox = ReportInbox(directory: directory)
        let id = try inbox.write(.init(text: "original"))
        let alias = UUID()
        try FileManager.default.createSymbolicLink(at: inbox.file(for: alias), withDestinationURL: inbox.file(for: id))
        #expect(throws: (any Error).self) { try inbox.read(alias) }
        #expect(try inbox.read(id).text == "original")
        var unsupported = MarkifyReport(text: "test")
        unsupported.version = 2
        try JSONEncoder().encode(unsupported).write(to: inbox.file(for: id))
        #expect(throws: (any Error).self) { try inbox.read(id) }
        #expect(throws: (any Error).self) { try inbox.write(.init(text: String(repeating: "x", count: ReportInbox.maximumBytes))) }
        #expect(throws: (any Error).self) { try inbox.write(.init(text: "test", baseDirectory: "relative")) }
    }
}
