import Foundation
import Darwin

/// Fresh metadata, including inode replacement and nanosecond change times; never URL's cached resource values.
public struct FileStamp: Equatable, Sendable {
    private let device: Int32
    private let inode: UInt64
    public let size: Int64
    private let modified: timespec
    private let changed: timespec

    public init?(at url: URL) {
        var info = stat()
        guard stat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { return nil }
        device = info.st_dev
        inode = info.st_ino
        size = info.st_size
        modified = info.st_mtimespec
        changed = info.st_ctimespec
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.device == rhs.device && lhs.inode == rhs.inode && lhs.size == rhs.size
            && lhs.modified.tv_sec == rhs.modified.tv_sec && lhs.modified.tv_nsec == rhs.modified.tv_nsec
            && lhs.changed.tv_sec == rhs.changed.tv_sec && lhs.changed.tv_nsec == rhs.changed.tv_nsec
    }
}

public enum FileRead {
    /// Check before opening, then bound every read as the file may grow after the metadata check.
    public static func data(at url: URL, maximumBytes: Int) throws -> Data {
        guard let stamp = FileStamp(at: url), stamp.size <= maximumBytes else { throw CocoaError(.fileReadTooLarge) }
        let descriptor = open(url.path, O_RDONLY | O_NONBLOCK)
        guard descriptor >= 0 else { throw CocoaError(.fileReadUnknown) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_size <= maximumBytes else { throw CocoaError(.fileReadTooLarge) }
        var data = Data()
        while let chunk = try handle.read(upToCount: min(65_536, maximumBytes + 1 - data.count)), !chunk.isEmpty {
            try Task.checkCancellation()
            data.append(chunk)
            guard data.count <= maximumBytes else { throw CocoaError(.fileReadTooLarge) }
        }
        return data
    }
}
