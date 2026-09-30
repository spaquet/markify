import Foundation
import MarkifyMarkdown
import Testing
@testable import markify

struct ViewTests {
    @Test func fileStdinArgumentsAndLaunchFailure() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let inbox = ReportInbox(directory: folder.appendingPathComponent("Inbox"))
        let file = folder.appendingPathComponent("my report.md")
        let source = "# café 🌻\r\n\r\nNo final newline"
        try Data(source.utf8).write(to: file)
        var received: MarkifyReport?
        let launch: (URL) throws -> Void = { received = try inbox.read(ReportInbox.id(from: $0)) }
        #expect(MarkifyCommand.run(["view", file.path, "--title", "$(not shell code)"], inbox: inbox, launch: launch) == 0)
        #expect(received?.text == source && received?.title == "$(not shell code)")
        #expect(received?.baseDirectory == folder.path)
        #expect(try String(contentsOf: file, encoding: .utf8) == source)
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        #expect(MarkifyCommand.run(["view", "-", "--base", folder.path], stdin: handle, inbox: inbox, launch: launch) == 0)
        #expect(received?.text == source && received?.baseDirectory == folder.path)
        try handle.seek(toOffset: 0)
        #expect(MarkifyCommand.run(["view"], stdin: handle, inbox: inbox, launch: launch) == 0)
        #expect(received?.baseDirectory == FileManager.default.currentDirectoryPath)
        for arguments in [["view", "--title"], ["view", "--unknown"], ["view", "a", "b"], ["view", "--title", "--base", folder.path], ["view", "--base", folder.path, "--base", folder.path]] {
            #expect(MarkifyCommand.run(arguments, inbox: inbox, launch: launch) == 2)
        }
        #expect(MarkifyCommand.run(["view", file.path, "--base", folder.appendingPathComponent("missing").path], inbox: inbox, launch: launch) == 1)
        #expect(MarkifyCommand.run(["view", file.path], inbox: inbox, launch: { _ in throw ReportError("Launch denied") }) == 1)
        try Data([0xff]).write(to: file)
        #expect(MarkifyCommand.run(["view", file.path], inbox: inbox, launch: launch) == 1)
    }
}
