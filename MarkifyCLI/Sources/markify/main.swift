import Foundation
import AppKit
import MarkifyMarkdown
import OKFKit

private let usage = """
Usage:
  markify check BUNDLE
  markify export FILE --html --output OUTPUT
  markify view [FILE | -] [--title TITLE] [--base DIRECTORY]
  markify --help

check: Validate an OKF bundle. Warnings and information do not fail the command.
export: Write a self-contained HTML page from a .md, .markdown, or .mdx file.
view: Open UTF-8 Markdown as an untitled Rendered document. Omitted FILE reads stdin.
Exit status: 0 success, 1 validation or file error, 2 invalid arguments.
"""

@main struct MarkifyCommand {
    static func main() {
        exit(run(Array(CommandLine.arguments.dropFirst())))
    }

    static func run(_ arguments: [String], stdin: FileHandle = .standardInput, inbox: ReportInbox = ReportInbox(),
                    launch: (URL) throws -> Void = openMarkify) -> Int32 {
        if arguments == ["--help"] || arguments == ["-h"] { print(usage); return 0 }
        guard let command = arguments.first else { return invalidArguments() }
        do {
            switch command {
            case "view":
                var input: String?, title: String?, base: String?
                var index = 1
                while index < arguments.count {
                    let argument = arguments[index]
                    if argument == "--title" || argument == "--base" {
                        guard index + 1 < arguments.count, !["--title", "--base"].contains(arguments[index + 1]) else { return invalidArguments() }
                        if argument == "--title" {
                            guard title == nil else { return invalidArguments() }
                            title = arguments[index + 1]
                        } else {
                            guard base == nil else { return invalidArguments() }
                            base = arguments[index + 1]
                        }
                        index += 2
                    } else {
                        guard input == nil, argument == "-" || !argument.hasPrefix("-") else { return invalidArguments() }
                        input = argument
                        index += 1
                    }
                }
                let file = input.flatMap { $0 == "-" ? nil : fileURL($0) }
                let handle = try file.map { try FileHandle(forReadingFrom: $0) } ?? stdin
                defer { if file != nil { try? handle.close() } }
                let data = try ReportInbox.readInput(handle)
                guard let source = String(data: data, encoding: .utf8) else { throw CLIError("Expected UTF-8 Markdown") }
                let directory = base.map(fileURL) ?? file?.deletingLastPathComponent() ?? fileURL(".")
                let id = try inbox.write(.init(text: source, title: title, baseDirectory: directory.path))
                try launch(ReportInbox.url(for: id))
                return 0
            case "check":
                guard arguments.count == 2 else { return invalidArguments() }
                let root = fileURL(arguments[1])
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                    throw CLIError("Not a directory: \(root.path)")
                }
                let bundle = OKFBundle.load(root: root)
                guard !bundle.truncated else { throw CLIError("Bundle exceeds the 5,000-file validation limit: \(root.path)") }
                guard !bundle.documents.isEmpty else { throw CLIError("No Markdown files found in bundle: \(root.path)") }
                try verifyReadableMarkdown(in: root)
                let diagnostics = OKFValidator.validate(bundle: bundle)
                for diagnostic in diagnostics {
                    let path = diagnostic.path.map { root.appendingPathComponent(String($0.dropFirst())).path } ?? root.path
                    print("\(path): \(diagnostic.severity): \(diagnostic.message)")
                }
                return diagnostics.contains { $0.severity == .error } ? 1 : 0
            case "export":
                guard arguments.count == 5, arguments[2] == "--html",
                      (arguments[3] == "--output" || arguments[3] == "-o") else { return invalidArguments() }
                let input = fileURL(arguments[1]), output = fileURL(arguments[4])
                guard ["md", "markdown", "mdx"].contains(input.pathExtension.lowercased()) else {
                    throw CLIError("Expected a .md, .markdown, or .mdx file: \(input.path)")
                }
                guard input.standardizedFileURL != output.standardizedFileURL else {
                    throw CLIError("Output must differ from the source file")
                }
                let source = try String(contentsOf: input, encoding: .utf8)
                let context = MarkdownPage.Context(source: source, documentURL: input, destination: output,
                                                   fallbackTitle: input.deletingPathExtension().lastPathComponent)
                try MarkdownPage.html(context).write(to: output, atomically: true, encoding: .utf8)
                return 0
            default: return invalidArguments()
            }
        } catch {
            errorLine("markify: \(error.localizedDescription)")
            return 1
        }
    }

    private static func openMarkify(_ url: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        // Target the running copy. Launch Services may otherwise choose a different installed build,
        // whose short-lived single-instance handoff can lose a second rapid request while quitting.
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: "com.stephanepaquet.Markify")
            .filter { !$0.isTerminated }.min { ($0.launchDate ?? .distantPast) < ($1.launchDate ?? .distantPast) }
        process.arguments = running?.bundleURL.map { ["-a", $0.path, url.absoluteString] }
            ?? ["-b", "com.stephanepaquet.Markify", url.absoluteString]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CLIError("Could not open Markify. Install the app: https://github.com/spaquet/markify/releases/latest") }
    }

    private static func fileURL(_ path: String) -> URL {
        URL(fileURLWithPath: path, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)).standardizedFileURL
    }

    private static func verifyReadableMarkdown(in root: URL) throws {
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { throw CLIError("Cannot scan bundle: \(root.path)") }
        while let url = files.nextObject() as? URL {
            guard url.pathExtension.lowercased() == "md",
                  try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            _ = try String(contentsOf: url, encoding: .utf8)
        }
    }

    private static func invalidArguments() -> Int32 {
        errorLine(usage)
        return 2
    }

    private static func errorLine(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}

private struct CLIError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
