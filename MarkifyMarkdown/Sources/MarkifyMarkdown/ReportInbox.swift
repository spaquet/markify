import Foundation
import Darwin

/// Local, one-shot report handoff shared by Markify and its bundled CLI.
public struct MarkifyReport: Codable, Sendable, Equatable {
    public var version = 1
    public let text: String
    public let title: String?
    public let baseDirectory: String?

    public init(text: String, title: String? = nil, baseDirectory: String? = nil) {
        self.text = text
        self.title = title
        self.baseDirectory = baseDirectory
    }

    public func validate() throws {
        guard version == 1 else { throw ReportError("Unsupported report version") }
        if let baseDirectory {
            var directory: ObjCBool = false
            guard baseDirectory.hasPrefix("/"), FileManager.default.fileExists(atPath: baseDirectory, isDirectory: &directory), directory.boolValue else {
                throw ReportError("Report base must be an existing absolute directory")
            }
        }
    }
}

public struct ReportError: LocalizedError {
    public let errorDescription: String?
    public init(_ message: String) { errorDescription = message }
}

public struct ReportInbox: Sendable {
    public static let maximumBytes = 10 * 1024 * 1024
    public let directory: URL

    public init(directory: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Caches/com.stephanepaquet.Markify/Inbox", isDirectory: true)) {
        self.directory = directory
    }

    public func write(_ report: MarkifyReport) throws -> UUID {
        try report.validate()
        let data = try JSONEncoder().encode(report)
        guard data.count <= Self.maximumBytes else { throw ReportError("Report exceeds the 10 MiB limit") }
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let values = try directory.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        guard values.isSymbolicLink != true, values.isDirectory == true else { throw ReportError("Invalid report inbox") }
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        // Abandoned dispatches expire; only our UUID envelopes are eligible.
        for file in try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .isSymbolicLinkKey]) {
            guard file.pathExtension == "json", UUID(uuidString: file.deletingPathExtension().lastPathComponent) != nil,
                  let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .isSymbolicLinkKey]),
                  values.isSymbolicLink != true, let date = values.contentModificationDate, date < Date().addingTimeInterval(-86400) else { continue }
            try? manager.removeItem(at: file)
        }
        let id = UUID()
        try data.write(to: file(for: id), options: [.atomic])
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file(for: id).path)
        return id
    }

    public func read(_ id: UUID) throws -> MarkifyReport {
        guard try directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw ReportError("Invalid report inbox") }
        let descriptor = Darwin.open(file(for: id).path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { throw ReportError("Report is missing, already opened, or unreadable") }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_size <= Self.maximumBytes else { throw ReportError("Invalid report file or report exceeds the 10 MiB limit") }
        let data = try Self.readInput(handle)
        let report = try JSONDecoder().decode(MarkifyReport.self, from: data)
        try report.validate()
        return report
    }

    public func remove(_ id: UUID) throws { try FileManager.default.removeItem(at: file(for: id)) }
    public func file(for id: UUID) -> URL { directory.appendingPathComponent(id.uuidString + ".json") }

    public static func url(for id: UUID) -> URL {
        var components = URLComponents()
        components.scheme = "markify"
        components.host = "view"
        components.queryItems = [URLQueryItem(name: "id", value: id.uuidString)]
        return components.url!
    }

    /// Pipes can return short reads before EOF; never truncate a streamed report.
    public static func readInput(_ handle: FileHandle) throws -> Data {
        var result = Data()
        while let chunk = try handle.read(upToCount: min(65536, maximumBytes + 1 - result.count)), !chunk.isEmpty {
            result.append(chunk)
            guard result.count <= maximumBytes else { throw ReportError("Report exceeds the 10 MiB limit") }
        }
        return result
    }

    public static func id(from url: URL) throws -> UUID {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "markify", components.host == "view", components.path.isEmpty,
              components.fragment == nil, components.user == nil, components.password == nil, components.port == nil,
              let items = components.queryItems, items.count == 1, items[0].name == "id",
              let value = items[0].value, let id = UUID(uuidString: value) else { throw ReportError("Invalid Markify report URL") }
        return id
    }
}
