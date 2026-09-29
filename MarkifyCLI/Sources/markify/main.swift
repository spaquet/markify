import Foundation
import MarkifyMarkdown
import OKFKit

private let usage = """
Usage:
  markify check BUNDLE
  markify export FILE --html --output OUTPUT
  markify --help

check: Validate an OKF bundle. Warnings and information do not fail the command.
export: Write a self-contained HTML page from a .md, .markdown, or .mdx file.
Exit status: 0 success, 1 validation or file error, 2 invalid arguments.
"""

@main struct MarkifyCommand {
    static func main() {
        exit(run(Array(CommandLine.arguments.dropFirst())))
    }

    static func run(_ arguments: [String]) -> Int32 {
        if arguments == ["--help"] || arguments == ["-h"] { print(usage); return 0 }
        guard let command = arguments.first else { return invalidArguments() }
        do {
            switch command {
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
