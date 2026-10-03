import Foundation
import MarkifyMarkdown

// Markify's help is written once, as Markdown in help/, and built into two places:
//
// - the app's Apple Help Book, Markify/Resources/Markify.help (indexed afterwards by hiutil in scripts/build-help.sh),
// - the website: docs/help/*.html, plus pages whose frontmatter names a `web` path (docs/faq.html, docs/legal.html),
//   with docs/sitemap.xml, docs/robots.txt, docs/llms.txt and docs/llms-full.txt.
//
// Links between pages are written as `other.md` and images as `screens/<name>` (from docs/images/screens); both
// are rewritten for each output. Usage: swift run --package-path Tools/HelpBuilder HelpBuilder [repository root]

let site = "https://spaquet.github.io/markify/"
let repository = "https://github.com/spaquet/markify"
let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath).standardizedFileURL
let fm = FileManager.default

struct Page {
    let slug: String
    let title: String
    let description: String
    let order: Int
    let keywords: String
    /// The page's path under docs/.
    let web: String
    let schema: String?
    let license: Bool
    /// The Markdown without its frontmatter.
    let body: String
    let lastModified: String

    var app: String { slug + ".html" }
}

// MARK: Reading

func frontmatter(_ text: String) -> (fields: [String: String], body: String) {
    guard text.hasPrefix("---\n"), let end = text.range(of: "\n---\n", range: text.index(text.startIndex, offsetBy: 4)..<text.endIndex) else { return ([:], text) }
    var fields: [String: String] = [:]
    for line in text[text.index(text.startIndex, offsetBy: 4)..<end.lowerBound].split(separator: "\n") {
        guard let colon = line.firstIndex(of: ":") else { continue }
        fields[String(line[..<colon]).trimmingCharacters(in: .whitespaces)] = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
    }
    return (fields, String(text[end.upperBound...]))
}

func lastModified(_ url: URL) -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["-C", root.path, "log", "-1", "--format=%cs", "--", url.path]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()
    try? process.run()
    process.waitUntilExit()
    let date = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return date.isEmpty ? ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withFullDate]) : date
}

let helpFolder = root.appendingPathComponent("help")
let pages: [Page] = try fm.contentsOfDirectory(at: helpFolder, includingPropertiesForKeys: nil)
    .filter { $0.pathExtension == "md" }
    .map { url in
        let (fields, body) = frontmatter(try String(contentsOf: url, encoding: .utf8))
        let slug = url.deletingPathExtension().lastPathComponent
        guard let title = fields["title"], let description = fields["description"] else { fatalError("\(url.lastPathComponent) needs a title and a description") }
        return Page(slug: slug, title: title, description: description, order: Int(fields["order"] ?? "") ?? 99,
                    keywords: fields["keywords"] ?? "", web: fields["web"] ?? "help/\(slug).html", schema: fields["schema"],
                    license: fields["license"] == "true", body: body, lastModified: lastModified(url))
    }
    .sorted { ($0.order, $0.slug) < ($1.order, $1.slug) }
let bySlug = Dictionary(uniqueKeysWithValues: pages.map { ($0.slug, $0) })

let licenseText = try String(contentsOf: root.appendingPathComponent("LICENSE"), encoding: .utf8)

// MARK: Rendering

enum Target { case app, web }

/// A path from one file under a root to another under the same root.
func relative(_ target: String, from page: String) -> String {
    let from = page.split(separator: "/").dropLast()
    let to = target.split(separator: "/")
    var shared = 0
    while shared < min(from.count, to.count - 1), from[from.startIndex + shared] == to[shared] { shared += 1 }
    return (Array(repeating: "..", count: from.count - shared) + to[shared...].map(String.init)).joined(separator: "/")
}

/// Screenshots the pages show, copied into the Help Book.
let usedImages = Set(pages.flatMap { page in
    try! NSRegularExpression(pattern: #"\(screens/([^)\s]+)\)"#).matches(in: page.body, range: NSRange(page.body.startIndex..., in: page.body))
        .map { (page.body as NSString).substring(with: $0.range(at: 1)) }
})

func render(_ page: Page, for target: Target) -> String {
    let options = MarkdownHTML.Options(
        image: { source in
            guard source.hasPrefix("screens/") else { return source }
            return target == .app ? "images/" + source.dropFirst("screens/".count) : relative("images/" + source, from: page.web)
        },
        link: { destination in
            // The Welcome tour opens in the app from the Help Book; on the website it's the file on GitHub.
            if destination == "markify://welcome", target == .web { return "\(repository)/blob/main/Markify/Resources/Welcome.md" }
            let parts = destination.split(separator: "#", maxSplits: 1).map(String.init)
            guard let file = parts.first, file.hasSuffix(".md"), let linked = bySlug[String(file.dropLast(3))] else { return destination }
            let fragment = parts.count > 1 ? "#" + parts[1] : ""
            return (target == .app ? linked.app : relative(linked.web, from: page.web)) + fragment
        })
    var html = MarkdownHTML.render(page.body, options: options).body
    if page.license {
        html = html.replacingOccurrences(of: "<div id=\"license-text\" class=\"license\"></div>", with: "<div id=\"license-text\" class=\"license\">\(licenseHTML(licenseText))</div>")
    }
    // External links open in the browser from the Help Viewer and in a new context from the website.
    return html.replacingOccurrences(of: "<a href=\"http", with: "<a rel=\"noopener\" href=\"http")
}

/// The LICENSE file as HTML: blank lines split blocks, `---` is a rule, a short line without a final period is a
/// heading, and `- ` lines are a list. The website's script builds the same markup from the live file on GitHub.
func licenseHTML(_ text: String) -> String {
    var html = ""
    for block in text.components(separatedBy: "\n\n") {
        let lines = block.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard let first = lines.first else { continue }
        if lines == ["---"] { html += "<hr>"; continue }
        if lines.count == 1, first.count < 60, !first.hasSuffix("."), !first.hasSuffix(":") {
            html += "<h3>\(MarkdownHTML.escape(first))</h3>"
            continue
        }
        let prose = lines.prefix { !$0.hasPrefix("- ") }
        let items = lines.dropFirst(prose.count)
        if !prose.isEmpty { html += "<p>\(MarkdownHTML.escape(prose.joined(separator: " ")))</p>" }
        if !items.isEmpty { html += "<ul>" + items.map { "<li>\(MarkdownHTML.escape(String($0.dropFirst(2))))</li>" }.joined() + "</ul>" }
    }
    return html
}

func plainText(_ html: String) -> String {
    html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
        .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&amp;", with: "&")
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespaces)
}

func json(_ value: Any) -> String {
    let data = try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
    // Safe inside <script>: no "</" can close the element.
    return String(data: data, encoding: .utf8)!.replacingOccurrences(of: "</", with: "<\\/")
}

/// Question and answer pairs of an FAQ page: each `###` heading and the text up to the next heading.
func faqEntries(_ page: Page) -> [(question: String, answer: String)] {
    var entries: [(String, String)] = []
    var question: String?
    var answer: [String] = []
    func flush() {
        guard let question else { return }
        let text = plainText(MarkdownHTML.render(answer.joined(separator: "\n"), options: .init(link: { $0 })).body)
        entries.append((question, text))
    }
    for line in page.body.components(separatedBy: "\n") {
        if line.hasPrefix("#") {
            flush()
            question = line.hasPrefix("### ") ? String(line.dropFirst(4)) : nil
            answer = []
        } else {
            answer.append(line)
        }
    }
    flush()
    return entries
}

// MARK: The Help Book

func appPage(_ page: Page, index: Int) -> String {
    let previous = index > 0 ? pages[index - 1] : nil
    let next = index + 1 < pages.count ? pages[index + 1] : nil
    var head = "<meta charset=\"utf-8\">\n<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n"
    if page.slug == "index" {
        head += "<meta name=\"AppleTitle\" content=\"Markify Help\">\n<meta name=\"AppleIcon\" content=\"images/icon.png\">\n"
    }
    head += "<meta name=\"description\" content=\"\(MarkdownHTML.escape(page.description))\">\n"
    head += "<meta name=\"keywords\" content=\"\(MarkdownHTML.escape(page.keywords))\">\n"
    head += "<title>\(MarkdownHTML.escape(page.title))</title>\n<link rel=\"stylesheet\" href=\"help.css\">\n"
    var body = "<a name=\"\(page.slug)\"></a>\n"
    if page.slug != "index" { body += "<nav class=\"crumbs\" aria-label=\"Breadcrumb\"><a href=\"index.html\">Markify Help</a></nav>\n" }
    body += "<main>\n<article>\n\(render(page, for: .app))"
    if page.slug == "index" { body += topics(for: .app, from: page) }
    body += "</article>\n</main>\n<nav class=\"pager\" aria-label=\"Previous and next topics\">"
    if let previous { body += "<a rel=\"prev\" href=\"\(previous.app)\">← \(MarkdownHTML.escape(previous.title))</a>" } else { body += "<span></span>" }
    if let next { body += "<a rel=\"next\" href=\"\(next.app)\">\(MarkdownHTML.escape(next.title)) →</a>" }
    body += "</nav>\n"
    return "<!doctype html>\n<html lang=\"en\">\n<head>\n\(head)</head>\n<body>\n\(body)</body>\n</html>\n"
}

func topics(for target: Target, from page: Page) -> String {
    var html = "<h2 id=\"topics\">Topics</h2>\n<ul class=\"topics\">\n"
    for topic in pages where topic.slug != "index" {
        let href = target == .app ? topic.app : relative(topic.web, from: page.web)
        let data = target == .web ? " data-search=\"\(MarkdownHTML.escape((topic.title + " " + topic.description + " " + topic.keywords).lowercased()))\"" : ""
        html += "<li\(data)><a href=\"\(href)\"><strong>\(MarkdownHTML.escape(topic.title))</strong><span>\(MarkdownHTML.escape(topic.description))</span></a></li>\n"
    }
    return html + "</ul>\n"
}

let book = root.appendingPathComponent("Markify/Resources/Markify.help")
let bookResources = book.appendingPathComponent("Contents/Resources/en.lproj")
try? fm.removeItem(at: book)
try fm.createDirectory(at: bookResources.appendingPathComponent("images"), withIntermediateDirectories: true)
for (index, page) in pages.enumerated() {
    try appPage(page, index: index).write(to: bookResources.appendingPathComponent(page.app), atomically: true, encoding: .utf8)
}
try helpCSS.write(to: bookResources.appendingPathComponent("help.css"), atomically: true, encoding: .utf8)
for image in usedImages.sorted() {
    try fm.copyItem(at: root.appendingPathComponent("docs/images/screens/\(image)"), to: bookResources.appendingPathComponent("images/\(image)"))
}
try fm.copyItem(at: root.appendingPathComponent("docs/images/favicon.png"), to: bookResources.appendingPathComponent("images/icon.png"))
let bookInfo: [String: Any] = [
    "CFBundleDevelopmentRegion": "en",
    "CFBundleIdentifier": "com.stephanepaquet.Markify.help",
    "CFBundleInfoDictionaryVersion": "6.0",
    "CFBundleName": "Markify Help",
    "CFBundlePackageType": "BNDL",
    "CFBundleShortVersionString": "1",
    "CFBundleSignature": "hbwr",
    "CFBundleVersion": "1",
    "HPDBookAccessPath": "index.html",
    "HPDBookIndexPath": "Markify.helpindex",
    "HPDBookTitle": "Markify Help",
    "HPDBookType": "3",
    "HPDBookIconPath": "images/icon.png",
]
try PropertyListSerialization.data(fromPropertyList: bookInfo, format: .xml, options: 0)
    .write(to: book.appendingPathComponent("Contents/Info.plist"))

// MARK: The website

/// The appearance button's moon and sun; assets/site.js shows the one that switches away from the current theme.
let themeIcons = """
<svg class="moon" viewBox="0 0 24 24" aria-hidden="true"><path fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round" d="M20.5 14.2A8.5 8.5 0 1 1 9.8 3.5a7 7 0 0 0 10.7 10.7z"/></svg><svg class="sun" viewBox="0 0 24 24" aria-hidden="true"><g fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="12" r="4.2"/><path d="M12 2.5v2M12 19.5v2M4.6 4.6l1.4 1.4M18 18l1.4 1.4M2.5 12h2M19.5 12h2M4.6 19.4 6 18M18 6l1.4-1.4"/></g></svg>
"""

func webPage(_ page: Page, index: Int) -> String {
    let url = site + page.web
    let isIndex = page.slug == "index"
    let docTitle = isIndex ? "Markify Help — User guide for the Mac Markdown editor" : "\(page.title) — Markify Help"
    let up = relative("index.html", from: page.web)
    let helpHome = relative("help/index.html", from: page.web)
    let content = render(page, for: .web)

    var graph: [[String: Any]] = []
    var crumbs: [[String: Any]] = [["@type": "ListItem", "position": 1, "name": "Markify", "item": site]]
    if !isIndex, page.web.hasPrefix("help/") {
        crumbs.append(["@type": "ListItem", "position": 2, "name": "Help", "item": site + "help/"])
    }
    crumbs.append(["@type": "ListItem", "position": crumbs.count + 1, "name": isIndex ? "Help" : page.title, "item": url])
    graph.append(["@type": "BreadcrumbList", "itemListElement": crumbs])
    if page.schema == "faq" {
        graph.append(["@type": "FAQPage", "mainEntity": faqEntries(page).map {
            ["@type": "Question", "name": $0.question, "acceptedAnswer": ["@type": "Answer", "text": $0.answer]]
        }])
    } else {
        graph.append(["@type": "TechArticle", "headline": page.title, "description": page.description, "dateModified": page.lastModified,
                      "inLanguage": "en", "url": url, "keywords": page.keywords,
                      "author": ["@type": "Person", "name": "Stéphane Paquet", "url": "https://github.com/spaquet"],
                      "about": ["@type": "SoftwareApplication", "name": "Markify", "operatingSystem": "macOS 26", "applicationCategory": "ProductivityApplication", "url": site]])
    }

    var head = """
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>\(MarkdownHTML.escape(docTitle))</title>
    <meta name="description" content="\(MarkdownHTML.escape(page.description))">
    <meta name="theme-color" content="#F7F5F0" media="(prefers-color-scheme: light)">
    <meta name="theme-color" content="#0C0C0E" media="(prefers-color-scheme: dark)">
    <script>(()=>{const r=document.documentElement;r.classList.add('js');let t=null;try{t=localStorage.getItem('markify.theme')}catch{}if(t==='light'||t==='dark')r.dataset.theme=t;r.dataset.resolved=r.dataset.theme||(matchMedia('(prefers-color-scheme: dark)').matches?'dark':'light')})()</script>
    <link rel="canonical" href="\(url)">
    <meta property="og:site_name" content="Markify">
    <meta property="og:type" content="article">
    <meta property="og:url" content="\(url)">
    <meta property="og:title" content="\(MarkdownHTML.escape(docTitle))">
    <meta property="og:description" content="\(MarkdownHTML.escape(page.description))">
    <meta property="og:image" content="\(site)images/og-image.jpg">
    <meta property="og:image:alt" content="Markify — Markdown, without the markup. A single-page Markdown editor for Mac.">
    <meta name="twitter:card" content="summary_large_image">
    <link rel="icon" type="image/png" sizes="64x64" href="\(up.replacingOccurrences(of: "index.html", with: ""))images/favicon.png?v=2">
    <link rel="apple-touch-icon" href="\(up.replacingOccurrences(of: "index.html", with: ""))images/app-icon.png?v=2">
    <link rel="alternate" type="text/markdown" href="\(repository)/blob/main/help/\(page.slug).md" title="Markdown source">
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Newsreader:ital,opsz,wght@0,6..72,400;0,6..72,600;0,6..72,700;1,6..72,400&family=JetBrains+Mono:wght@500;700&display=swap" rel="stylesheet">
    <link rel="stylesheet" href="\(relative("assets/pages.css", from: page.web))">
    <script type="application/ld+json">\(json(["@context": "https://schema.org", "@graph": graph]))</script>

    """

    let assetBase = up.replacingOccurrences(of: "index.html", with: "")
    var nav = "<nav class=\"toc\" aria-label=\"Help topics\">\n<p class=\"toc-title\"><a href=\"\(helpHome)\">Markify Help</a></p>\n<ul>\n"
    for topic in pages where topic.slug != "index" {
        let current = topic.slug == page.slug ? " aria-current=\"page\"" : ""
        nav += "<li><a href=\"\(relative(topic.web, from: page.web))\"\(current)>\(MarkdownHTML.escape(topic.title))</a></li>\n"
    }
    nav += "</ul>\n</nav>\n"

    let previous = index > 0 ? pages[index - 1] : nil
    let next = index + 1 < pages.count ? pages[index + 1] : nil
    var pager = "<nav class=\"pager\" aria-label=\"Previous and next topics\">"
    if let previous { pager += "<a rel=\"prev\" href=\"\(relative(previous.web, from: page.web))\"><span>Previous</span>\(MarkdownHTML.escape(previous.title))</a>" } else { pager += "<span></span>" }
    if let next { pager += "<a rel=\"next\" href=\"\(relative(next.web, from: page.web))\"><span>Next</span>\(MarkdownHTML.escape(next.title))</a>" }
    pager += "</nav>\n"

    var crumbTrail = "<nav class=\"crumbs\" aria-label=\"Breadcrumb\"><ol><li><a href=\"\(up)\">Markify</a></li>"
    if !isIndex, page.web.hasPrefix("help/") { crumbTrail += "<li><a href=\"\(helpHome)\">Help</a></li>" }
    crumbTrail += "<li><span aria-current=\"page\">\(isIndex ? "Help" : MarkdownHTML.escape(page.title))</span></li></ol></nav>\n"

    var article = content
    if isIndex {
        article += """
        <div class="search" role="search">
        <label for="topic-filter">Filter topics</label>
        <input id="topic-filter" type="search" placeholder="Try “table”, “export” or “update”" autocomplete="off" aria-describedby="topic-count">
        <p id="topic-count" class="count" aria-live="polite"></p>
        </div>

        """
        article += topics(for: .web, from: page)
    }
    article += "<p class=\"edit\">Updated \(page.lastModified) · <a rel=\"noopener\" href=\"\(repository)/blob/main/help/\(page.slug).md\">Suggest a change on GitHub</a></p>\n"

    var scripts = ""
    if isIndex {
        scripts += """
        <script>
        (() => {
          const input = document.getElementById('topic-filter'), items = [...document.querySelectorAll('.topics li')], count = document.getElementById('topic-count');
          input.addEventListener('input', () => {
            const words = input.value.toLowerCase().split(/\\s+/).filter(Boolean);
            let shown = 0;
            items.forEach(li => { const hit = words.every(w => li.dataset.search.includes(w)); li.hidden = !hit; if (hit) shown++; });
            count.textContent = words.length ? (shown ? `${shown} topic${shown === 1 ? '' : 's'} found` : 'No topics found. Try the FAQ.') : '';
          });
        })();
        </script>

        """
    }
    if page.license {
        // The license shown is built into the page; this refreshes it from GitHub so it always matches the repository.
        scripts += """
        <script>
        (() => {
          const box = document.getElementById('license-text');
          const esc = s => s.replace(/[&<>"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
          fetch('https://raw.githubusercontent.com/spaquet/markify/main/LICENSE', { cache: 'no-cache' })
            .then(r => r.ok ? r.text() : Promise.reject())
            .then(text => {
              box.innerHTML = text.split(/\\n\\s*\\n/).map(block => {
                const lines = block.split('\\n').map(l => l.trim()).filter(Boolean);
                if (!lines.length) return '';
                if (lines.length === 1 && lines[0] === '---') return '<hr>';
                const one = lines[0];
                if (lines.length === 1 && one.length < 60 && !/[.:]$/.test(one)) return `<h3>${esc(one)}</h3>`;
                const cut = lines.findIndex(l => l.startsWith('- ')), prose = cut < 0 ? lines : lines.slice(0, cut), items = cut < 0 ? [] : lines.slice(cut);
                return (prose.length ? `<p>${esc(prose.join(' '))}</p>` : '') + (items.length ? '<ul>' + items.map(l => `<li>${esc(l.slice(2))}</li>`).join('') + '</ul>' : '');
              }).join('');
            })
            .catch(() => {});
        })();
        </script>

        """
    }

    return """
    <!doctype html>
    <html lang="en">
    <head>
    \(head)</head>
    <body>
    <a class="skip" href="#content">Skip to content</a>
    <header class="nav">
      <nav class="cap glass" aria-label="Main">
        <a class="brand" href="\(up)"><img src="\(assetBase)images/app-icon.png?v=2" alt="" width="30" height="30">Markify</a>
        <a class="link" href="\(helpHome)"\(page.web.hasPrefix("help/") ? " aria-current=\"true\"" : "")>Help</a>
        <a class="link hide-s" href="\(relative("faq.html", from: page.web))"\(page.web == "faq.html" ? " aria-current=\"page\"" : "")>FAQ</a>
        <a class="link hide-s" href="\(relative("compare.html", from: page.web))">Compare</a>
        <a class="link hide-s" href="\(relative("okf.html", from: page.web))">OKF</a>
        <button class="theme-btn" type="button" aria-label="Switch appearance">\(themeIcons)</button>
        <a class="btn btn-accent" href="\(up)#download">Download</a>
      </nav>
    </header>
    <div class="layout wrap">
    \(nav)<main id="content" tabindex="-1">
    \(crumbTrail)<article>
    \(article)</article>
    \(pager)</main>
    </div>
    <footer>
      <div class="wrap">
        <span>© 2026 Markify · by <a href="https://github.com/spaquet">Stéphane Paquet</a></span>
        <nav aria-label="Footer">
          <a href="\(helpHome)">Help</a>
          <a href="\(relative("faq.html", from: page.web))">FAQ</a>
          <a href="\(relative("compare.html", from: page.web))">Compare</a>
          <a href="\(repository)">Source</a>
          <a href="\(repository)/releases">Releases</a>
          <a href="\(relative("okf.html", from: page.web))">Open Knowledge Format</a>
          <a href="\(repository)/issues">Issues</a>
          <a href="\(relative("known-issues.html", from: page.web))">Known issues</a>
          <a href="https://github.com/sponsors/spaquet">Sponsor</a>
          <a href="\(relative("legal.html", from: page.web))">Legal &amp; privacy</a>
        </nav>
      </div>
    </footer>
    <script src="\(relative("assets/site.js", from: page.web))?v=3" defer></script>
    \(scripts)</body>
    </html>

    """
}

let docs = root.appendingPathComponent("docs")
let webHelp = docs.appendingPathComponent("help")
try? fm.removeItem(at: webHelp)
try fm.createDirectory(at: webHelp, withIntermediateDirectories: true)
try fm.createDirectory(at: docs.appendingPathComponent("assets"), withIntermediateDirectories: true)
for (index, page) in pages.enumerated() {
    try webPage(page, index: index).write(to: docs.appendingPathComponent(page.web), atomically: true, encoding: .utf8)
}
try pagesCSS.write(to: docs.appendingPathComponent("assets/pages.css"), atomically: true, encoding: .utf8)

// MARK: Crawlers and AI assistants

let homeModified = lastModified(docs.appendingPathComponent("index.html"))
var sitemap = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n"
sitemap += "<url><loc>\(site)</loc><lastmod>\(homeModified)</lastmod><priority>1.0</priority></url>\n"
sitemap += "<url><loc>\(site)okf.html</loc><lastmod>\(lastModified(docs.appendingPathComponent("okf.html")))</lastmod><priority>0.8</priority></url>\n"
sitemap += "<url><loc>\(site)compare.html</loc><lastmod>\(lastModified(docs.appendingPathComponent("compare.html")))</lastmod><priority>0.7</priority></url>\n"
sitemap += "<url><loc>\(site)known-issues.html</loc><lastmod>\(lastModified(docs.appendingPathComponent("known-issues.html")))</lastmod><priority>0.5</priority></url>\n"
for page in pages {
    let loc = page.web == "help/index.html" ? site + "help/" : site + page.web
    sitemap += "<url><loc>\(loc)</loc><lastmod>\(page.lastModified)</lastmod><priority>\(page.slug == "index" || page.schema == "faq" ? "0.8" : "0.6")</priority></url>\n"
}
sitemap += "</urlset>\n"
try sitemap.write(to: docs.appendingPathComponent("sitemap.xml"), atomically: true, encoding: .utf8)

try """
# Markify's website. Everyone, including AI crawlers, is welcome to read it.
User-agent: *
Allow: /

Sitemap: \(site)sitemap.xml

""".write(to: docs.appendingPathComponent("robots.txt"), atomically: true, encoding: .utf8)

func webURL(_ page: Page) -> String { page.web == "help/index.html" ? site + "help/" : site + page.web }

var llms = """
# Markify

> Markify is a free, source-available Markdown editor for macOS 26 (Apple silicon and Intel). It shows a document on one page with two lenses over the same text — a rendered lens and a Markdown lens, switched with ⌘/ — instead of a split preview. It follows CommonMark and GitHub Flavored Markdown and adds callouts, LaTeX math, footnotes, Mermaid diagrams, YAML frontmatter and MDX files; exports self-contained HTML and paginated PDF; uses on-device Apple Intelligence for proofreading, rewriting and generation; and reads and edits Open Knowledge Format (OKF) bundles. Documents are plain .md files saved exactly as written.

- Website: \(site)
- Download: \(repository)/releases/latest (markify-as.dmg for Apple silicon, markify-intel.dmg for Intel)
- Source code: \(repository)
- License: MIT with the Commons Clause (free to use, including at work; resale restricted): \(site)legal.html

## Help

"""
for page in pages where page.schema != "faq" && !page.license {
    llms += "- [\(page.title)](\(webURL(page))): \(page.description)\n"
}
llms += "\n## FAQ and legal\n\n"
for page in pages where page.schema == "faq" || page.license {
    llms += "- [\(page.title)](\(webURL(page))): \(page.description)\n"
}
llms += "\n## Optional\n\n- [Markify compared with other Markdown editors](\(site)compare.html): Features side by side with Typora, Obsidian, iA Writer and Bear.\n- [Open Knowledge Format in Markify](\(site)okf.html): How Markify reads, browses and maintains OKF knowledge bundles.\n- [Full help as one Markdown file](\(site)llms-full.txt)\n"
try llms.write(to: docs.appendingPathComponent("llms.txt"), atomically: true, encoding: .utf8)

var full = "# Markify Help\n\nThe complete Markify user guide as Markdown. Source: \(repository)/tree/main/help\n"
for page in pages {
    // Page links point at the website so they work outside the help folder.
    let body = page.body.replacingOccurrences(of: #"\]\(([a-z-]+)\.md"#, with: "](\(site)help/$1.html", options: .regularExpression)
        .replacingOccurrences(of: "(screens/", with: "(\(site)images/screens/")
    full += "\n---\n\nURL: \(webURL(page))\n\n" + body.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
}
for page in pages where page.web != "help/\(page.slug).html" {
    full = full.replacingOccurrences(of: "\(site)help/\(page.slug).html", with: site + page.web)
}
try full.write(to: docs.appendingPathComponent("llms-full.txt"), atomically: true, encoding: .utf8)

print("Built \(pages.count) help pages into \(book.path) and \(webHelp.path).")
