import Foundation
import OSLog

enum PreviewImageClient {
    static func images(for document: URL) async -> [String: String] {
        await withCheckedContinuation { continuation in
            let request = Request(continuation)
            request.connection.remoteObjectInterface = NSXPCInterface(with: PreviewImageProtocol.self)
            request.connection.resume()
            let proxy = request.connection.remoteObjectProxyWithErrorHandler { error in request.finish([:], failure: error.localizedDescription) }
            guard let service = proxy as? PreviewImageProtocol else { request.finish([:], failure: "Invalid image helper interface"); return }
            service.images(for: document) { request.finish($0) }
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) { request.finish([:], failure: "Image helper timed out") }
        }
    }

    private final class Request: @unchecked Sendable {
        let connection = NSXPCConnection(serviceName: "com.stephanepaquet.Markify.PreviewImages")
        private let lock = NSLock()
        private var continuation: CheckedContinuation<[String: String], Never>?

        init(_ continuation: CheckedContinuation<[String: String], Never>) { self.continuation = continuation }

        func finish(_ images: [String: String], failure: String? = nil) {
            lock.lock()
            let pending = continuation
            continuation = nil
            lock.unlock()
            guard let pending else { return }
            if let failure { Logger(subsystem: "com.stephanepaquet.Markify", category: "QuickLook").error("\(failure, privacy: .public)") }
            pending.resume(returning: images)
            connection.invalidate()
        }
    }
}
