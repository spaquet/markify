import AppKit
import SwiftUI
import Security

/// Redirects are followed explicitly so every hop stays HTTPS and secrets stay at their origin.
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
            throw RemoteOpenError("Enter an HTTPS URL without embedded credentials.")
        }
    }

    func fetch(_ url: URL, credential: RemoteCredential? = nil, accept: String? = nil) async throws -> (Data, HTTPURLResponse) {
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var current = url
        for _ in 0..<10 {
            try Self.validate(current)
            var request = URLRequest(url: current)
            request.setValue("Markify", forHTTPHeaderField: "User-Agent")
            if let credential { try credential.apply(to: &request) }
            if let accept { request.setValue(accept, forHTTPHeaderField: "Accept") }
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
                    ? "Access was denied. Choose credentials below and retry, or replace expired credentials. The server may also have reached its request limit."
                    : response.statusCode == 404 ? "The file or repository was not found. Private resources may require credentials." : "The server returned HTTP \(response.statusCode). Check the URL and try again.")
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
        guard (mime.isEmpty || mime.hasPrefix("text/") || mime == "application/octet-stream" || mime == "application/vnd.github.raw+json"),
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

    static func load(_ source: URL, client: PublicURLClient = PublicURLClient(), credential: RemoteCredential? = nil) async throws -> Self {
        try PublicURLClient.validate(source)
        let parsed = RemoteAddress(source)
        let raw = try credential != nil && parsed.isGit && parsed.filePath != nil ? parsed.fileAPI() : rawURL(source)
        let (data, response) = try await client.fetch(raw, credential: credential, accept: credential != nil && parsed.github ? "application/vnd.github.raw+json" : nil)
        return Self(text: try decode(data, response: response, requested: source), source: source,
                    base: (parsed.isGit ? try rawURL(source) : (response.url ?? raw)).deletingLastPathComponent())
    }
}

struct RepositoryFile: Identifiable, Hashable {
    let path: String
    let url: URL
    var id: String { path }
}

enum PublicRepository {
    static func files(_ url: URL, client: PublicURLClient = PublicURLClient(), credential: RemoteCredential? = nil) async throws -> [RepositoryFile] {
        try PublicURLClient.validate(url)
        let parsed = RemoteAddress(url)
        guard parsed.isGit, let project = parsed.project else { throw RemoteOpenError("Enter a GitHub or GitLab repository URL.") }
        let github = parsed.github
        let encoded = project.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        var origin = URLComponents(url: url, resolvingAgainstBaseURL: true)!
        origin.path = ""; origin.query = nil; origin.fragment = nil
        let host = origin.url!.absoluteString
        let api = github ? "https://api.github.com/repos/\(project)" : "\(host)/api/v4/projects/\(encoded)"
        func json(_ address: String) async throws -> Any {
            let (data, _) = try await client.fetch(URL(string: address)!, credential: credential)
            return try JSONSerialization.jsonObject(with: data)
        }
        guard let metadata = try await json(api) as? [String: Any],
              let branch = metadata["default_branch"] as? String else { throw RemoteOpenError("No default branch was found in this repository.") }
        let ref = (parsed.branch ?? branch).addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
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
                  parsed.filePath == nil || path.hasPrefix(parsed.filePath! + "/"),
                  let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "?#%"))),
                  let target = URL(string: root + encodedPath) else { return nil }
            return RepositoryFile(path: path, url: target)
        }.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }
}

struct RemoteAddress {
    let url: URL
    let github: Bool
    let isGit: Bool
    let project: String?
    let branch: String?
    let filePath: String?
    let isFile: Bool
    init(_ url: URL) {
        self.url = url
        let parts = url.pathComponents.filter { $0 != "/" }
        github = url.host?.lowercased() == "github.com"
        isGit = github || url.host?.lowercased().contains("gitlab") == true || parts.contains("-")
        let marker = github ? (parts.count > 2 ? 2 : parts.count) : (parts.firstIndex(of: "-") ?? parts.count)
        project = isGit && marker >= 2 ? parts.prefix(marker).joined(separator: "/").replacingOccurrences(of: #"\.git$"#, with: "", options: .regularExpression) : nil
        let rest = Array(parts.dropFirst(marker + (github ? 0 : 1)))
        // ponytail: branch is one URL segment; use a percent-encoded slash for branch names containing slashes.
        branch = rest.count >= 2 && ["blob", "tree", "raw"].contains(rest[0]) ? rest[1] : nil
        filePath = branch != nil && rest.count > 2 ? rest.dropFirst(2).joined(separator: "/") : nil
        isFile = ["md", "markdown", "mdx"].contains(url.pathExtension.lowercased())
    }
    var provider: String { github ? "GitHub" : isGit ? "GitLab" : "HTTPS" }
    var origin: URL { URL(string: "https://\(url.host!)\(url.port.map { ":\($0)" } ?? "")")! }
    var credentialOrigin: URL { github ? URL(string: "https://api.github.com")! : origin }
    func fileAPI() throws -> URL {
        guard let project, let branch, let filePath else { throw RemoteOpenError("Use a GitHub or GitLab file URL with a branch and path.") }
        let encode = { (s: String) in s.addingPercentEncoding(withAllowedCharacters: .alphanumerics)! }
        if github {
            let path = filePath.split(separator: "/").map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#%")))! }.joined(separator: "/")
            return URL(string: "https://api.github.com/repos/\(project)/contents/\(path)?ref=\(encode(branch))")!
        }
        return URL(string: "\(origin.absoluteString)/api/v4/projects/\(encode(project))/repository/files/\(encode(filePath))/raw?ref=\(encode(branch))")!
    }
}

struct RemoteCredential: Codable, Sendable {
    let origin: URL
    let kind: String
    let account: String
    let secret: String
    static func sameOrigin(_ a: URL, _ b: URL) -> Bool {
        a.scheme?.lowercased() == b.scheme?.lowercased() && a.host?.lowercased() == b.host?.lowercased() && (a.port ?? 443) == (b.port ?? 443)
    }
    func apply(to request: inout URLRequest) throws {
        guard let url = request.url, Self.sameOrigin(origin, url) else {
            throw RemoteOpenError("The server redirected to a different origin. Credentials were not sent. Open the destination separately if you trust it.")
        }
        guard !secret.contains("\r"), !secret.contains("\n"), !account.contains("\r"), !account.contains("\n"), kind != "basic" || !account.contains(":") else {
            throw RemoteOpenError("The credentials contain invalid characters.")
        }
        if kind == "basic" {
            request.setValue("Basic " + Data("\(account):\(secret)".utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
        } else if kind == "gitlab" {
            request.setValue(secret, forHTTPHeaderField: "PRIVATE-TOKEN")
        } else {
            request.setValue("Bearer " + secret, forHTTPHeaderField: "Authorization")
        }
    }
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "net.markify.open-url." + origin.absoluteString,
         kSecAttrAccount as String: kind + ":" + account]
    }
    func save() throws {
        let data = try JSONEncoder().encode(self)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw RemoteOpenError("Could not save credentials in Keychain.") }
        } else if status != errSecSuccess { throw RemoteOpenError("Could not update credentials in Keychain.") }
    }
    static func saved(origin: URL) throws -> [Self] {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "net.markify.open-url." + origin.absoluteString,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitAll]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let rows = result as? [Data] else { throw RemoteOpenError("Could not read saved credentials from Keychain.") }
        return try rows.map { try JSONDecoder().decode(Self.self, from: $0) }
    }
    func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw RemoteOpenError("Could not remove saved credentials from Keychain.") }
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

    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var urlFocused: Bool
    @State private var access = "public"
    @State private var username = ""
    @State private var secret = ""
    @State private var remember = false
    @State private var saved: [RemoteCredential] = []
    private var parsed: RemoteAddress? {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              (try? PublicURLClient.validate(url)) != nil else { return nil }
        return RemoteAddress(url)
    }
    private var dark: Bool { colorScheme == .dark }
    private var panel: Color { dark ? Color(white: 0.165) : Color(red: 0.965, green: 0.961, blue: 0.953) }
    private var field: Color { dark ? .black.opacity(0.22) : .white }
    private var mismatch: Bool { parsed.map { repository ? (!$0.isGit || $0.isFile) : $0.isGit && !$0.isFile } ?? false }
    private var credential: RemoteCredential? {
        guard let parsed, access != "public", access != "account" else { return nil }
        return RemoteCredential(origin: parsed.isGit ? parsed.credentialOrigin : parsed.origin,
                                kind: access == "token" ? (parsed.github ? "bearer" : "gitlab") : access,
                                account: access == "basic" ? username : "token", secret: secret)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    Image(systemName: "globe").font(.system(size: 20)).foregroundStyle(.blue)
                        .frame(width: 40, height: 40).background(field, in: RoundedRectangle(cornerRadius: 11))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Open from URL").font(.system(size: 15, weight: .semibold))
                        Text("A Markdown file on the web, or a GitHub / GitLab repository.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 10) {
                    modeCard(false, title: "File", subtitle: "Open one Markdown document", icon: "doc.text")
                    modeCard(true, title: "Repository", subtitle: "Browse its files and folders", icon: "point.3.connected.trianglepath.dotted")
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(parsed.map { $0.github ? "GH" : $0.isGit ? "GL" : "↗" } ?? "↗")
                            .font(.system(size: 9, weight: .bold)).foregroundStyle(.blue)
                            .frame(width: 20, height: 20).background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                        TextField(repository ? "https://github.com/owner/repo" : "https://…/document.md", text: $address)
                            .font(.system(size: 12.5, design: .monospaced)).textFieldStyle(.plain)
                            .focused($urlFocused).accessibilityLabel(repository ? "Repository URL" : "File URL").onSubmit { start() }
                        if address.isEmpty {
                            Button("Paste") { address = NSPasteboard.general.string(forType: .string) ?? "" }.controlSize(.small)
                        } else {
                            Button { address = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                                .buttonStyle(.plain).accessibilityLabel("Clear URL")
                        }
                    }.padding(.horizontal, 10).frame(height: 38).background(field, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(urlFocused ? Color.blue.opacity(0.6) : Color.primary.opacity(0.12), lineWidth: urlFocused ? 3 : 0.5))
                    if let parsed {
                        HStack(spacing: 6) {
                            Text(parsed.provider).fontWeight(.semibold).foregroundStyle(parsed.github ? Color.primary : parsed.isGit ? .orange : .blue)
                            Text(parsed.project ?? parsed.url.host ?? "")
                            if let branch = parsed.branch { Text("·"); Label(branch, systemImage: "arrow.triangle.branch") }
                        }.font(.system(size: 12))
                        if let path = parsed.filePath ?? (parsed.isGit ? nil : parsed.url.path) {
                            Text(path).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(.secondary).lineLimit(2)
                        }
                    } else if address.isEmpty {
                        HStack {
                            Text("Try").foregroundStyle(.secondary)
                            Button(repository ? "github.com/owner/repo" : "github.com/…/README.md") {
                                address = repository ? "https://github.com/spaquet/markify" : "https://github.com/spaquet/markify/blob/main/README.md"
                            }.buttonStyle(.plain).padding(.horizontal, 8).padding(.vertical, 3).background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                        }.font(.system(size: 11.5))
                    } else {
                        notice("Enter a full https:// address without embedded credentials.", color: .red)
                    }
                    if mismatch {
                        HStack {
                            Text(repository ? "Use a GitHub or GitLab repository address, or open this as a file." : "This links to a repository. Browse its files instead?")
                            Spacer()
                            Button(repository ? "Open as File" : "Browse Repository") { repository.toggle() }.controlSize(.small)
                        }.font(.system(size: 12)).padding(10).background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                    }
                    if let error { notice(error, color: .orange) }
                }
                if let parsed, !mismatch {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Access").fontWeight(.semibold).foregroundStyle(.secondary)
                            Spacer()
                            Text(access == "public" ? "● Public" : secret.isEmpty ? "● Credentials required" : "● Credentials set").foregroundStyle(access == "public" ? Color.green : .blue)
                                .padding(.horizontal, 8).padding(.vertical, 3).background((access == "public" ? Color.green : .blue).opacity(0.12), in: Capsule())
                        }.font(.system(size: 11.5))
                        VStack(spacing: 0) {
                            accessRow("public", title: "Public", subtitle: "No credentials are sent")
                            Divider()
                            if parsed.isGit {
                                accessRow("account", title: "\(parsed.provider) account", subtitle: "Sign in once, works for every repo you can read")
                                if access == "account" {
                                    Text("Browser sign-in is not configured for this build. Use a personal access token below.")
                                        .font(.system(size: 11.5)).foregroundStyle(.secondary).padding(.leading, 42).padding(.trailing, 14).padding(.bottom, 12)
                                }
                                Divider()
                                accessRow("token", title: "Personal access token", subtitle: parsed.github ? "Fine-grained token with Contents: read" : "Token with read_api for repository browsing")
                            } else {
                                accessRow("basic", title: "Username & password", subtitle: "HTTP Basic authentication")
                                Divider()
                                accessRow("bearer", title: "Bearer token", subtitle: "Sent as an Authorization header")
                            }
                            if credential != nil {
                                VStack(alignment: .leading, spacing: 8) {
                                    if access == "basic" {
                                        TextField("Username", text: $username).textContentType(.username).textFieldStyle(.roundedBorder)
                                    }
                                    SecureField(access == "basic" ? "Password" : parsed.github ? "github_pat_…" : parsed.isGit ? "glpat-…" : "Token", text: $secret)
                                        .textContentType(access == "basic" ? .password : nil).textFieldStyle(.roundedBorder)
                                    Toggle("Remember in Keychain for \(parsed.url.host ?? "this host")", isOn: $remember).toggleStyle(.checkbox).font(.system(size: 11.5))
                                    if parsed.isGit {
                                        Link("Create a token…", destination: URL(string: parsed.github ? "https://github.com/settings/personal-access-tokens/new" : parsed.origin.absoluteString + "/-/user_settings/personal_access_tokens")!).font(.system(size: 11.5))
                                    }
                                }.padding(.leading, 42).padding(.trailing, 14).padding(.bottom, 12)
                            }
                            ForEach(saved.indices, id: \.self) { index in
                                Divider()
                                HStack {
                                    Button("Use saved \(saved[index].kind) · \(saved[index].account)") {
                                        let value = saved[index]
                                        access = value.kind == "gitlab" || parsed.isGit ? "token" : value.kind
                                        username = value.account; secret = value.secret; remember = false
                                    }.buttonStyle(.plain)
                                    Spacer()
                                    Button("Remove") {
                                        do { try saved[index].remove(); saved.remove(at: index); secret = ""; remember = false }
                                        catch { self.error = error.localizedDescription }
                                    }.controlSize(.small)
                                }.font(.system(size: 11.5)).padding(12)
                            }
                        }.background(dark ? Color.white.opacity(0.05) : .white, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.primary.opacity(0.08), lineWidth: 0.5))
                    }
                }
                if let files {
                    TextField("Search files", text: $search).textFieldStyle(.roundedBorder)
                    if files.isEmpty { Text("No Markdown files found.").foregroundStyle(.secondary) }
                    List(files.filter { search.isEmpty || $0.path.localizedCaseInsensitiveContains(search) }, selection: $selected) { file in
                        Label(file.path, systemImage: "doc.text").tag(file.id)
                    }.frame(height: 200).clipShape(RoundedRectangle(cornerRadius: 10))
                }
                if busy { HStack { ProgressView().controlSize(.small); Text(repository && files == nil ? "Loading files…" : "Opening file…") }.font(.caption) }
            }.padding(24)
            Divider()
            HStack(spacing: 14) {
                Text(parsed.map { access == "public" ? "Only a read request is sent to \($0.url.host ?? "the host")." : "Credentials are sent only to \($0.credentialOrigin.host ?? "the host"). Saved only when you choose." } ?? "Paste a link to a file or repository.")
                    .font(.system(size: 11.5)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                Button("Cancel") { work?.cancel(); dismiss() }.keyboardShortcut(.cancelAction)
                Button(repository && files == nil ? "Browse" : "Open") { start() }.buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(busy || parsed == nil || mismatch || access == "account" || (access != "public" && secret.isEmpty) || (access == "basic" && username.isEmpty) || (repository && files != nil && selected == nil))
            }.buttonBorderShape(.capsule).padding(.horizontal, 24).padding(.vertical, 14)
        }.frame(width: 600).background(panel)
            .onChange(of: address) { reset() }
            .onChange(of: parsed?.credentialOrigin) { loadSaved() }
            .onChange(of: repository) { reset() }
            .onChange(of: access) { reset() }
            .onChange(of: username) { reset() }
            .onChange(of: secret) { reset() }
            .onDisappear { work?.cancel() }
    }

    private func modeCard(_ mode: Bool, title: String, subtitle: String, icon: String) -> some View {
        Button { repository = mode } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).frame(width: 28, height: 28).foregroundStyle(repository == mode ? .white : Color.primary)
                    .background(repository == mode ? .blue : .primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).fontWeight(.semibold)
                    Text(subtitle).font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }.padding(12).background(repository == mode ? Color.blue.opacity(0.12) : field, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(repository == mode ? Color.blue : .primary.opacity(0.1), lineWidth: repository == mode ? 1.5 : 0.5))
        }.buttonStyle(.plain).accessibilityAddTraits(repository == mode ? .isSelected : [])
    }
    private func accessRow(_ value: String, title: String, subtitle: String) -> some View {
        Button { access = value } label: {
            HStack(spacing: 12) {
                Image(systemName: access == value ? "largecircle.fill.circle" : "circle").foregroundStyle(access == value ? Color.blue : .secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                    Text(subtitle).font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(.horizontal, 14).padding(.vertical, 10).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(access == value ? .isSelected : [])
    }
    private func notice(_ text: String, color: Color) -> some View {
        Label(text, systemImage: "exclamationmark.triangle").font(.system(size: 12)).foregroundStyle(color)
            .padding(10).frame(maxWidth: .infinity, alignment: .leading).background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 10)).textSelection(.enabled)
    }
    private func loadSaved() {
        secret = ""; username = ""; access = "public"; remember = false; saved = []
        guard let parsed else { return }
        do { saved = try RemoteCredential.saved(origin: parsed.credentialOrigin) }
        catch { self.error = error.localizedDescription }
    }

    private func reset() {
        work?.cancel(); busy = false; files = nil; selected = nil; search = ""; error = nil
    }

    private func start() {
        guard !busy, parsed != nil, !mismatch, access != "account", access == "public" || !secret.isEmpty, access != "basic" || !username.isEmpty else { return }
        error = nil
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            error = "Enter a valid HTTPS URL."; return
        }
        let credentials = credential
        let persist = remember
        busy = true
        work = Task { @MainActor in
            do {
                if repository && files == nil {
                    let found = try await PublicRepository.files(url, credential: credentials)
                    try Task.checkCancellation()
                    if persist { try credentials?.save(); saved = try RemoteCredential.saved(origin: parsed!.credentialOrigin) }
                    files = found
                    selected = found.first(where: { $0.path.lowercased() == "readme.md" })?.id ?? found.first?.id
                } else {
                    let target = repository ? files?.first(where: { $0.id == selected })?.url : url
                    guard let target else { busy = false; return }
                    let remote = try await RemoteMarkdown.load(target, credential: credentials)
                    try Task.checkCancellation()
                    if persist { try credentials?.save() }
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
