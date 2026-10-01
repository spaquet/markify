import AppKit
import SwiftUI

/// Public, credential-free downloads. Redirects are followed explicitly so every hop stays HTTPS.
final class PublicURLClient: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let configuration: URLSessionConfiguration

    init(configuration: URLSessionConfiguration = .ephemeral) {
        let configuration = configuration.copy() as! URLSessionConfiguration
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        self.configuration = configuration
        super.init()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust
            ? .performDefaultHandling : .cancelAuthenticationChallenge, nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    static func validate(_ url: URL) throws {
        guard url.scheme?.lowercased() == "https", url.host?.isEmpty == false, url.user == nil, url.password == nil else {
            throw RemoteOpenError("Enter a public HTTPS URL without credentials.")
        }
    }

    func fetch(_ url: URL) async throws -> (Data, HTTPURLResponse) {
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var current = url
        for _ in 0..<10 {
            try Self.validate(current)
            var request = URLRequest(url: current)
            request.setValue("Markify", forHTTPHeaderField: "User-Agent")
            let (bytes, response) = try await session.bytes(for: request)
            guard let response = response as? HTTPURLResponse else { throw RemoteOpenError("Invalid server response.") }
            if [301, 302, 303, 307, 308].contains(response.statusCode),
               let location = response.value(forHTTPHeaderField: "Location"),
               let next = URL(string: location, relativeTo: current)?.absoluteURL {
                bytes.task.cancel()
                current = next
                continue
            }
            guard (200..<300).contains(response.statusCode) else {
                throw RemoteOpenError(response.statusCode == 401 || response.statusCode == 403
                    ? "This resource is unavailable publicly, or the server's request limit was reached."
                    : "The server returned HTTP \(response.statusCode). Check the URL and try again.")
            }
            var data = Data()
            for try await byte in bytes {
                guard data.count < 10_000_000 else { throw RemoteOpenError("This response exceeds the 10 MB limit.") }
                data.append(byte)
            }
            return (data, response)
        }
        throw RemoteOpenError("Too many redirects.")
    }
}

struct RemoteOpenError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct RemoteMarkdown {
    let text: String
    let source: URL
    let base: URL

    static func rawURL(_ url: URL) throws -> URL {
        try PublicURLClient.validate(url)
        var components = URLComponents(url: url, resolvingAgainstBaseURL: true)!
        let parts = url.pathComponents.filter { $0 != "/" }
        if url.host?.lowercased() == "github.com", parts.count >= 5, parts[2] == "blob" {
            components.host = "raw.githubusercontent.com"
            components.path = "/" + ([parts[0], parts[1]] + parts.dropFirst(3)).joined(separator: "/")
            components.query = nil
            components.fragment = nil
        } else if let range = components.path.range(of: "/-/blob/") {
            components.path.replaceSubrange(range, with: "/-/raw/")
            components.query = nil
            components.fragment = nil
        }
        return components.url!
    }

    static func decode(_ data: Data, response: HTTPURLResponse, requested: URL) throws -> String {
        let mime = response.mimeType?.lowercased() ?? ""
        guard (mime.isEmpty || mime.hasPrefix("text/") || mime == "application/octet-stream"),
              mime != "text/html",
              let text = String(data: data, encoding: .utf8), !text.contains("\0") else {
            throw RemoteOpenError("This URL did not return a UTF-8 Markdown file.")
        }
        let start = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !start.hasPrefix("<!doctype html"), !start.hasPrefix("<html"),
              ["md", "markdown", "mdx"].contains(requested.pathExtension.lowercased()) ||
              ["text/markdown", "text/x-markdown"].contains(mime) else {
            throw RemoteOpenError("This URL did not return a Markdown file. Use a file URL ending in .md, .markdown or .mdx.")
        }
        return text
    }

    static func load(_ source: URL, client: PublicURLClient = PublicURLClient()) async throws -> Self {
        let raw = try rawURL(source)
        let (data, response) = try await client.fetch(raw)
        return Self(text: try decode(data, response: response, requested: raw), source: source,
                    base: (response.url ?? raw).deletingLastPathComponent())
    }
}

struct RepositoryFile: Identifiable, Hashable {
    let path: String
    let url: URL
    var id: String { path }
}

enum PublicRepository {
    static func files(_ url: URL, client: PublicURLClient = PublicURLClient()) async throws -> [RepositoryFile] {
        try PublicURLClient.validate(url)
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2 else { throw RemoteOpenError("Enter a GitHub or GitLab repository URL.") }
        let github = url.host?.lowercased() == "github.com"
        guard !github || parts.count == 2 else { throw RemoteOpenError("Enter the repository URL, without a file or branch path.") }
        guard !parts.contains("-"), url.query == nil, url.fragment == nil else {
            throw RemoteOpenError("Enter the repository URL, without a file or branch path.")
        }
        let project = parts.joined(separator: "/").replacingOccurrences(of: #"\.git$"#, with: "", options: .regularExpression)
        let encoded = project.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        var origin = URLComponents(url: url, resolvingAgainstBaseURL: true)!
        origin.path = ""; origin.query = nil; origin.fragment = nil
        let host = origin.url!.absoluteString
        let api = github ? "https://api.github.com/repos/\(project)" : "\(host)/api/v4/projects/\(encoded)"
        func json(_ address: String) async throws -> Any {
            let (data, _) = try await client.fetch(URL(string: address)!)
            return try JSONSerialization.jsonObject(with: data)
        }
        guard let metadata = try await json(api) as? [String: Any],
              let branch = metadata["default_branch"] as? String else { throw RemoteOpenError("No default branch was found in this public repository.") }
        let ref = branch.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        let root = github ? "https://github.com/\(project)/blob/\(ref)/" : "\(host)/\(project)/-/blob/\(ref)/"
        var entries: [[String: Any]] = []
        if github {
            guard let tree = try await json(api + "/git/trees/\(ref)?recursive=1") as? [String: Any],
                  let rows = tree["tree"] as? [[String: Any]] else { throw RemoteOpenError("Could not read the repository file list.") }
            guard tree["truncated"] as? Bool != true else { throw RemoteOpenError("This repository is too large to browse. Open a file URL instead.") }
            entries = rows
        } else {
            var page = 1
            while true {
                guard let rows = try await json(api + "/repository/tree?ref=\(ref)&recursive=true&per_page=100&page=\(page)") as? [[String: Any]] else {
                    throw RemoteOpenError("Could not read the repository file list.")
                }
                entries += rows
                if rows.count < 100 { break }
                guard page < 100 else { throw RemoteOpenError("This repository is too large to browse. Open a file URL instead.") }
                page += 1
            }
        }
        return entries.compactMap { entry in
            guard entry["type"] as? String == "blob", let path = entry["path"] as? String,
                  ["md", "markdown", "mdx"].contains((path as NSString).pathExtension.lowercased()),
                  let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                  let target = URL(string: root + encodedPath) else { return nil }
            return RepositoryFile(path: path, url: target)
        }.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }
}

struct OpenURLView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var repository = false
    @State private var address = ""
    @State private var files: [RepositoryFile]?
    @State private var selected: RepositoryFile.ID?
    @State private var search = ""
    @State private var busy = false
    @State private var error: String?
    @State private var work: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Open URL").font(.headline)
            Picker("Source", selection: $repository) {
                Text("File").tag(false)
                Text("Repository").tag(true)
            }.pickerStyle(.segmented)
            TextField("https://…", text: $address).textFieldStyle(.roundedBorder)
                .accessibilityLabel(repository ? "Repository URL" : "File URL")
                .onSubmit { start() }
            Text(repository ? "Public GitHub or GitLab repository. Browse its default branch." : "Public HTTPS Markdown file, including GitHub and GitLab file links.")
                .font(.caption).foregroundStyle(.secondary)
            if let files {
                TextField("Search files", text: $search).textFieldStyle(.roundedBorder)
                if files.isEmpty { Text("No Markdown files found.").foregroundStyle(.secondary) }
                List(files.filter { search.isEmpty || $0.path.localizedCaseInsensitiveContains(search) }, selection: $selected) { file in
                    Text(file.path).tag(file.id)
                }.frame(height: 240)
            }
            if busy { HStack { ProgressView().controlSize(.small); Text(files == nil && repository ? "Loading files…" : "Opening file…") } }
            if let error { Text(error).foregroundStyle(.red).font(.callout).textSelection(.enabled) }
            HStack {
                Spacer()
                Button("Cancel") { work?.cancel(); dismiss() }.keyboardShortcut(.cancelAction)
                Button(repository && files == nil ? "Browse" : "Open") { start() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(busy || address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (repository && files != nil && selected == nil))
            }
        }.padding(24).frame(width: 470)
            .onChange(of: address) { reset() }
            .onChange(of: repository) { reset() }
            .onDisappear { work?.cancel() }
    }

    private func reset() {
        work?.cancel(); busy = false; files = nil; selected = nil; search = ""; error = nil
    }

    private func start() {
        guard !busy else { return }
        error = nil
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            error = "Enter a valid HTTPS URL."; return
        }
        busy = true
        work = Task { @MainActor in
            do {
                if repository && files == nil {
                    let found = try await PublicRepository.files(url)
                    try Task.checkCancellation()
                    files = found
                    selected = found.first(where: { $0.path.lowercased() == "readme.md" })?.id ?? found.first?.id
                } else {
                    let target = repository ? files?.first(where: { $0.id == selected })?.url : url
                    guard let target else { busy = false; return }
                    let remote = try await RemoteMarkdown.load(target)
                    try Task.checkCancellation()
                    _ = try MarkifyDocument.makeUntitled(report: .init(text: remote.text, title: target.deletingPathExtension().lastPathComponent),
                                                        sourceURL: remote.source, remoteBase: remote.base, display: true)
                    NSApp.activate()
                    dismiss()
                }
                busy = false
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
                busy = false
            }
        }
    }
}
