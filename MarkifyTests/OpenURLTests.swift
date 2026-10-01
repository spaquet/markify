import AppKit
import MarkifyMarkdown
import Testing
@testable import Markify

@Suite(.serialized) @MainActor struct OpenURLTests {
    @Test func publicHTTPSAndRawFileURLs() throws {
        for address in ["http://example.com/a.md", "https://user:password@example.com/a.md", "file:///tmp/a.md"] {
            #expect(throws: RemoteOpenError.self) { try PublicURLClient.validate(URL(string: address)!) }
        }
        #expect(try RemoteMarkdown.rawURL(URL(string: "https://github.com/spaquet/markify/blob/main/help/getting-started.md?plain=1")!).absoluteString == "https://raw.githubusercontent.com/spaquet/markify/main/help/getting-started.md")
        #expect(try RemoteMarkdown.rawURL(URL(string: "https://gitlab.com/group/subgroup/project/-/blob/main/README.md")!).absoluteString == "https://gitlab.com/group/subgroup/project/-/raw/main/README.md")
    }

    @Test func rejectsHTMLAndNonMarkdownResponses() throws {
        let url = URL(string: "https://example.com/note.md")!
        func response(_ mime: String) -> HTTPURLResponse {
            HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": mime])!
        }
        let source = "# Café 🌻\r\n\r\nSome text."
        #expect(try RemoteMarkdown.decode(Data(source.utf8), response: response("text/plain"), requested: url) == source)
        for (body, mime) in [("<html>Error</html>", "text/plain"), ("<!DOCTYPE html>Oops", "text/plain"), ("# Text", "text/html"), ("{}", "application/json"), ("binary\0", "text/plain")] {
            #expect(throws: RemoteOpenError.self) { try RemoteMarkdown.decode(Data(body.utf8), response: response(mime), requested: url) }
        }
        #expect(throws: RemoteOpenError.self) {
            try RemoteMarkdown.decode(Data("Text".utf8), response: response("text/plain"), requested: URL(string: "https://example.com/page")!)
        }
    }

    @Test func refusesDowngradeRedirect() {
        let client = PublicURLClient()
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: URL(string: "https://example.com/a.md")!)
        let response = HTTPURLResponse(url: task.originalRequest!.url!, statusCode: 302, httpVersion: nil, headerFields: nil)!
        client.urlSession(session, task: task, willPerformHTTPRedirection: response,
                          newRequest: URLRequest(url: URL(string: "http://example.com/a.md")!)) { request in
            #expect(request == nil)
        }
    }

    @Test func publicRepositoryAndDownload() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PublicURLFixture.self]
        let client = PublicURLClient(configuration: configuration)
        for address in ["https://github.com/example/repository", "https://gitlab.com/group/subgroup/repository"] {
            let files = try await PublicRepository.files(URL(string: address)!, client: client)
            #expect(files.map(\.path) == ["docs/guide.md", "README.md"].sorted { $0.localizedStandardCompare($1) == .orderedAscending })
            let remote = try await RemoteMarkdown.load(files.first(where: { $0.path == "README.md" })!.url, client: client)
            #expect(remote.text == "# Public README\n")
            #expect(remote.source == files.first(where: { $0.path == "README.md" })!.url)
            #expect(!remote.base.isFileURL)
        }
        await #expect(throws: RemoteOpenError.self) { try await client.fetch(URL(string: "https://example.com/missing.md")!) }
        await #expect(throws: RemoteOpenError.self) { try await client.fetch(URL(string: "https://example.com/downgrade.md")!) }
    }

    @Test func credentialsStayAtOrigin() throws {
        let credential = RemoteCredential(origin: URL(string: "https://example.com")!, kind: "basic", account: "reader", secret: "secret")
        var request = URLRequest(url: URL(string: "https://example.com/private.md")!)
        try credential.apply(to: &request)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Basic " + Data("reader:secret".utf8).base64EncodedString())
        for address in ["https://other.example.com/private.md", "http://example.com/private.md", "https://example.com:444/private.md"] {
            var redirected = URLRequest(url: URL(string: address)!)
            #expect(throws: RemoteOpenError.self) { try credential.apply(to: &redirected) }
            #expect(redirected.value(forHTTPHeaderField: "Authorization") == nil)
        }
    }

    @Test func protectedProviderURLs() async throws {
        let source = URL(string: "https://github.com/example/repository/blob/release/docs/README.md")!
        let parsed = RemoteAddress(source)
        #expect(try parsed.fileAPI().absoluteString == "https://api.github.com/repos/example/repository/contents/docs/README.md?ref=release")
        let gitlab = RemoteAddress(URL(string: "https://gitlab.acme.dev/group/subgroup/project/-/blob/release/docs/README.md")!)
        #expect(gitlab.project == "group/subgroup/project")
        #expect(try gitlab.fileAPI().absoluteString == "https://gitlab.acme.dev/api/v4/projects/group%2Fsubgroup%2Fproject/repository/files/docs%2FREADME%2Emd/raw?ref=release")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PublicURLFixture.self]
        let client = PublicURLClient(configuration: configuration)
        let credential = RemoteCredential(origin: parsed.credentialOrigin, kind: "bearer", account: "token", secret: "test-token")
        let remote = try await RemoteMarkdown.load(source, client: client, credential: credential)
        #expect(remote.text == "# Public README\n")
        #expect(remote.base.absoluteString == "https://raw.githubusercontent.com/example/repository/release/docs/")
        let gitlabCredential = RemoteCredential(origin: gitlab.credentialOrigin, kind: "gitlab", account: "token", secret: "gitlab-test-token")
        let gitlabRemote = try await RemoteMarkdown.load(gitlab.url, client: client, credential: gitlabCredential)
        #expect(gitlabRemote.text == "# Private GitLab README\n")
        let branchFiles = try await PublicRepository.files(URL(string: "https://gitlab.acme.dev/group/project/-/tree/release/docs")!, client: client, credential: gitlabCredential)
        #expect(branchFiles.map(\.path) == ["docs/guide.md"])
        await #expect(throws: RemoteOpenError.self) { try await client.fetch(URL(string: "https://example.com/cross-origin.md")!, credential: RemoteCredential(origin: URL(string: "https://example.com")!, kind: "bearer", account: "token", secret: "test")) }
    }

    @Test func remotePathsAndUntitledSource() throws {
        let base = URL(string: "https://raw.githubusercontent.com/owner/repo/main/docs/")!
        #expect(MarkdownTextView.imageURL("../assets/a%20b.png", document: nil, baseDirectory: base).absoluteString == "https://raw.githubusercontent.com/owner/repo/main/assets/a%20b.png")
        #expect(MarkdownTextView.imageURL("/logo.png", document: nil, baseDirectory: base).absoluteString == "https://raw.githubusercontent.com/logo.png")
        let context = DocumentExport.Context(source: "", documentURL: nil, bundleRoot: nil, destination: URL(fileURLWithPath: "/tmp/export.html"), fallbackTitle: "Remote", baseDirectory: base)
        #expect(DocumentExport.linkTarget("other.md#section", context: context) == base.absoluteString + "other.md#section")
        #expect(DocumentExport.linkTarget("#section", context: context) == "#section")
        #expect(DocumentExport.imageSource("../image.png", context: context) == "https://raw.githubusercontent.com/owner/repo/main/image.png")
        #expect(LinkSummaryStore.key("other.md#section", from: nil, root: nil, baseDirectory: base) == base.absoluteString + "other.md")
        let source = URL(string: "https://github.com/owner/repo/blob/main/docs/README.md")!
        let document = try MarkifyDocument.makeUntitled(report: .init(text: "# Remote"), sourceURL: source, remoteBase: base)
        defer { document.close() }
        #expect(document.fileURL == nil)
        #expect(try document.fileWrapper(ofType: "net.daringfireball.markdown").regularFileContents == Data("# Remote".utf8))
        #expect(MarkifyDocument.newDocument().sourceURL == nil)
    }
}

private final class PublicURLFixture: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        let body: String
        var status = 200
        var headers = ["Content-Type": "application/json"]
        if url.host == "gitlab.acme.dev" {
            #expect(request.value(forHTTPHeaderField: "PRIVATE-TOKEN") == "gitlab-test-token")
        }
        if url.path.contains("/repository/tree"), url.host == "gitlab.acme.dev" {
            #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "ref" })?.value == "release")
        }
        if url.path.contains("/contents/") {
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
            #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github.raw+json")
        }
        if url.path.contains("/repository/files/") {
            body = "# Private GitLab README\n"; headers["Content-Type"] = "text/plain"
        } else if url.path.hasSuffix("cross-origin.md") {
            status = 302; headers["Location"] = "https://other.example.com/private.md"; body = ""
        } else if url.path.hasSuffix("missing.md") {
            status = 404; body = "Not found"
        } else if url.path.hasSuffix("downgrade.md") {
            status = 302; headers["Location"] = "http://example.com/file.md"; body = ""
        } else if url.path.contains("/git/trees/") {
            body = #"{"truncated":false,"tree":[{"path":"README.md","type":"blob"},{"path":"docs/guide.md","type":"blob"},{"path":"image.png","type":"blob"}]}"#
        } else if url.path.hasSuffix("/repository/tree") {
            body = #"[{"path":"README.md","type":"blob"},{"path":"docs/guide.md","type":"blob"},{"path":"image.png","type":"blob"}]"#
        } else if url.path.hasSuffix("README.md") {
            body = "# Public README\n"; headers["Content-Type"] = "text/plain"
        } else {
            body = #"{"default_branch":"main"}"#
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}
