import Foundation
import Testing
@testable import MarkifyMarkdown

private func html(_ source: String, mdx: Bool = false, options: MarkdownHTML.Options = .init()) -> String {
    MarkdownHTML.render(source, mdx: mdx, options: options).body
}

@Suite struct MarkdownHTMLTests {
    @Test func escapesTextAndCode() {
        let out = html("a < b & \"c\"\n\n`<div>`\n\n```\nif a < b {}\n```\n")
        #expect(out.contains("<p>a &lt; b &amp; &quot;c&quot;</p>"))
        #expect(out.contains("<code>&lt;div&gt;</code>"))
        #expect(out.contains("<code>if a &lt; b {}</code>"))
    }

    @Test func headingsKeepFormattingAndGetUniqueIDs() {
        let result = MarkdownHTML.render("# Hello *world*\n\n## Notes\n\n## Notes\n")
        #expect(result.body.contains("<h1 id=\"hello-world\">Hello <em>world</em></h1>"))
        #expect(result.body.contains("<h2 id=\"notes\">Notes</h2>"))
        #expect(result.body.contains("<h2 id=\"notes-1\">Notes</h2>"))
        #expect(result.firstHeading == "Hello world")
    }

    @Test func frontmatterIsLeftOut() {
        let out = html("---\ntitle: T\ntags: [a]\n---\n# Body\n")
        #expect(!out.contains("title"))
        #expect(out.hasPrefix("<h1"))
    }

    @Test func inlineStyles() {
        let out = html("**b** *i* ~~s~~ [l](x.md \"t\") ![alt *x*](a%20b.png)")
        #expect(out.contains("<strong>b</strong> <em>i</em> <del>s</del>"))
        #expect(out.contains("<a href=\"x.md\" title=\"t\">l</a>"))
        #expect(out.contains("<img src=\"a%20b.png\" alt=\"alt x\">"))
    }

    @Test func linkAndImageHooks() {
        let options = MarkdownHTML.Options(image: { "data:" + $0 }, link: { "../" + $0 })
        let out = html("[l](x.md) ![](i.png)", options: options)
        #expect(out.contains("href=\"../x.md\""))
        #expect(out.contains("src=\"data:i.png\""))
    }

    @Test func rawHTMLUsesImageAndLinkHooks() {
        let options = MarkdownHTML.Options(image: { "data:" + $0 }, link: { "../" + $0 })
        let out = html("<p><a href=\"page.md\"><img src='images/pic.png' alt='Photo'></a></p>\n\n# <img src=\"icon.png\"> Title\n", options: options)
        #expect(out.contains("href=\"../page.md\""))
        #expect(out.contains("src='data:images/pic.png'"))
        #expect(out.contains("src=\"data:icon.png\""))
    }

    @Test func tightAndLooseLists() {
        let tight = html("- a\n- b\n")
        #expect(tight.contains("<li>a\n</li>"))
        let loose = html("- a\n\n- b\n")
        #expect(loose.contains("<li><p>a</p>\n</li>"))
        let ordered = html("3. a\n4. b\n")
        #expect(ordered.contains("<ol start=\"3\">"))
    }

    @Test func taskLists() {
        let out = html("- [x] done\n- [ ] todo\n")
        #expect(out.contains("<ul class=\"tasks\">"))
        #expect(out.contains("<input type=\"checkbox\" disabled checked aria-label=\"Done\"> done"))
        #expect(out.contains("<input type=\"checkbox\" disabled aria-label=\"Not done\"> todo"))
    }

    @Test func tablesWithAlignment() {
        let out = html("| a | b |\n|:--|--:|\n| 1 | **2** |\n")
        #expect(out.contains("<th scope=\"col\" style=\"text-align:left\">a</th>"))
        #expect(out.contains("<td style=\"text-align:right\"><strong>2</strong></td>"))
    }

    @Test func callouts() {
        let out = html("> [!WARNING]\n> Careful *now*.\n")
        #expect(out.contains("<div class=\"callout callout-warning\" role=\"note\" aria-label=\"Warning\">"))
        #expect(out.contains("<p class=\"callout-title\">Warning</p>"))
        #expect(out.contains("<p>Careful <em>now</em>.</p>"))
        #expect(!out.contains("[!WARNING]"))
        #expect(html("> plain\n").contains("<blockquote>"))
    }

    @Test func mathUsesHookOrFallsBack() {
        let plain = html("Inline $x^2$ here.\n\n$$\n\\int f\n$$\n")
        #expect(plain.contains("<span class=\"math\"><code>x^2</code></span>"))
        #expect(plain.contains("<div class=\"math display\"><code>\\int f</code></div>"))
        let hooked = html("$a<b$", options: .init(math: { latex, display in "[\(display):\(latex)]" }))
        #expect(hooked.contains("[false:a<b]"))
        #expect(!html("Costs $5 and $10.").contains("math"))
    }

    @Test func mathInCodeStaysCode() {
        let out = html("`$x$`\n")
        #expect(out.contains("<code>$x$</code>"))
    }

    @Test func footnotes() {
        let out = html("One[^a] and two[^b], again[^a].\n\n[^a]: First *note*.\n[^b]: Second.\n")
        #expect(out.contains("<a href=\"#fn-a\" id=\"fnref-a\" aria-describedby=\"footnotes-label\">1</a>"))
        #expect(out.contains("<a href=\"#fn-b\" id=\"fnref-b\" aria-describedby=\"footnotes-label\">2</a>"))
        #expect(out.contains("id=\"fnref-a-2\""))
        #expect(out.contains("<li id=\"fn-a\"><p>First <em>note</em>. <a href=\"#fnref-a\""))
        #expect(out.contains("<li id=\"fn-b\"><p>Second."))
        #expect(!out.contains("[^"))
        #expect(html("Missing[^x].").contains("Missing[^x]."))
    }

    @Test func diagramsUseHook() {
        let source = "```mermaid\ngraph TD; A-->B\n```\n"
        #expect(html(source).contains("<pre><span class=\"code-label\" aria-hidden=\"true\">mermaid</span><code class=\"language-mermaid\">graph TD; A--&gt;B</code></pre>"))
        let out = html(source, options: .init(diagram: { language, code in language == "mermaid" ? "<svg>\(code.count)</svg>" : nil }))
        #expect(out.contains("<figure class=\"diagram\"><svg>15</svg></figure>"))
    }

    @Test func mdxBlocksShowAsCode() {
        let out = html("import X from 'x'\n\n# Title\n\n<X prop=\"1\" />\n", mdx: true)
        #expect(out.contains("<pre class=\"mdx\"><code>import X from 'x'</code></pre>"))
        #expect(out.contains("<pre class=\"mdx\"><code>&lt;X prop=&quot;1&quot; /&gt;</code></pre>"))
    }

    @Test func rendersTheSharedFixture() {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../MarkifyTests/Fixtures/editor-fixture.md").standardized
        let source = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let out = html(source)
        #expect(!out.isEmpty)
        #expect(!out.contains("\u{E000}"))
        #expect(!out.contains("\u{E002}"))
    }
}
