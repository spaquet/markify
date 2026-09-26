import Foundation
import Testing
@testable import OKFKit

/// The spec's Attested Computation example (§10.2).
private let revenue = """
---
type: Attested Computation
title: Revenue for fiscal year
description: Recognized revenue for a fiscal year, per Finance's definition.
status: stable
runtime: bigquery
parameters:
  - { name: year, type: integer, required: true }
executor:
  resource: references/skills/run-on-bq.md
  receipt: [job_id, executed_sql, result]
attester:
  resource: references/attesters/revenue.py
generated: { by: reference_agent/gemini-2.5-pro, at: 2026-06-20T22:53:05Z }
verified: { by: human:ahormati, at: 2026-06-25T09:00:00Z }
stale_after: 2026-09-23T00:00:00Z
sources:
  - id: rev-policy
    resource: https://wiki.acme/finance/revenue-recognition
    title: Revenue recognition policy
x-owner: finance
---

# Computation

    SELECT SUM(amount) AS revenue

The computation binds only the declared `parameters`.[^rev-policy]

[^rev-policy]: Revenue recognition policy

"""

struct ConceptTests {
    @Test func parsesTheSpecExample() throws {
        let concept = try #require(try OKFConcept.parse(source: revenue)?.get())
        #expect(concept.type == "Attested Computation")
        #expect(concept.isConcept && concept.isAttestedComputation)
        #expect(concept.runtime == "bigquery")
        #expect(concept.parameters == [OKFParameter(name: "year", type: "integer", required: true)])
        #expect(concept.executorResource == "references/skills/run-on-bq.md")
        #expect(concept.receipt == ["job_id", "executed_sql", "result"])
        #expect(concept.attesterResource == "references/attesters/revenue.py")
        #expect(concept.generated?.by == .agent(producer: "reference_agent", version: "gemini-2.5-pro"))
        #expect(concept.sources.first?.id == "rev-policy")
        #expect(concept.status == .stable)
        #expect(concept.extensionKeys == ["x-owner"])
    }

    @Test func bareVerifiedMappingIsOneElementList() throws {
        let concept = try #require(try OKFConcept.parse(source: revenue)?.get())
        #expect(concept.verified.count == 1)
        #expect(concept.verified.first?.by == .human("ahormati"))
        #expect(concept.trustTier == .humanReviewed)
    }

    @Test func trustTiers() throws {
        #expect(try OKFConcept(yaml: "type: Metric").trustTier == .unverified)
        let machine = "type: Metric\nverified:\n  - { by: process:nightly, at: 2026-06-26T02:00:00Z }\n"
        #expect(try OKFConcept(yaml: machine).trustTier == .machineConfirmed)
        let both = machine + "  - { by: human:ana, at: 2026-06-27T02:00:00Z }\n"
        let concept = try OKFConcept(yaml: both)
        #expect(concept.trustTier == .humanReviewed)
        #expect(concept.lastVerified?.by == .human("ana"))
    }

    @Test func staleness() throws {
        let concept = try OKFConcept(yaml: "type: Metric\nstale_after: 2026-09-23T00:00:00Z")
        #expect(!concept.isStale(at: OKFTimestamp.parse("2026-09-22T23:59:59Z")!))
        #expect(concept.isStale(at: OKFTimestamp.parse("2026-09-23T00:00:00Z")!))
    }

    @Test func statusDefaultsToStable() throws {
        #expect(try OKFConcept(yaml: "type: Playbook").status == .stable)
        #expect(try OKFConcept(yaml: "type: Playbook\nstatus: Draft").status == .draft)
        #expect(try OKFConcept(yaml: "type: Playbook\nstatus: retired").status == .other("retired"))
    }

    @Test func invalidYAMLIsReportedNotThrownAway() {
        guard case .failure(.invalidYAML)? = OKFConcept.parse(source: "---\ntype: [unclosed\n---\n") else {
            Issue.record("Expected invalid YAML")
            return
        }
    }

    @Test func plainNotesAreNotConcepts() throws {
        #expect(OKFConcept.parse(source: "# Hello") == nil)
        #expect(try OKFConcept(yaml: "tags: [a]").isConcept == false)
        #expect(try OKFConcept(yaml: "").isConcept == false)
    }

    @Test func actors() {
        #expect(OKFActor("human:ahormati") == .human("ahormati"))
        #expect(OKFActor("process:finance-nightly") == .process("finance-nightly"))
        #expect(OKFActor("reference_agent/gemini-2.5-pro") == .agent(producer: "reference_agent", version: "gemini-2.5-pro"))
        #expect(OKFActor("team:ga4-docs") == .other("team:ga4-docs"))
        #expect(OKFActor("human:ana").description == "human:ana")
    }
}

struct FrontmatterTests {
    @Test func locatesBlockWithUTF16Offsets() throws {
        let source = "---\ntitle: Café 😀\n---\nBody"
        let block = try #require(FrontmatterBlock.locate(in: source))
        #expect(block.yaml == "title: Café 😀\n")
        #expect((source as NSString).substring(from: block.blockRange.upperBound) == "Body")
    }

    @Test func emptyAndMissingBlocks() {
        #expect(FrontmatterBlock.locate(in: "---\n---\nx")?.yaml == "")
        #expect(FrontmatterBlock.locate(in: "---\nno close") == nil)
        #expect(FrontmatterBlock.locate(in: "text\n---\n") == nil)
    }
}

struct LinkTests {
    @Test func extractsLinksOutsideCode() {
        let body = """
        See [orders](/tables/orders.md "Orders") and [n](./other.md).
        ![img](pic.png) and `[not](a.md)` and [web](https://example.com).

        ```
        [skip](skip.md)
        ```
        [ref]: ../neighbor.md
        [^note]: A footnote
        """
        let links = OKFLinks.extract(from: body)
        #expect(links.map(\.target) == ["/tables/orders.md", "./other.md", "https://example.com", "../neighbor.md"])
        #expect(links.filter(\.isExternal).count == 1)
    }

    @Test func resolvesAbsoluteAndRelative() {
        let root = URL(fileURLWithPath: "/b")
        let document = URL(fileURLWithPath: "/b/metrics/revenue.md")
        #expect(OKFLinks.resolve("/tables/orders.md", from: document, bundleRoot: root)?.path == "/b/tables/orders.md")
        #expect(OKFLinks.resolve("../computations/revenue.md#top", from: document, bundleRoot: root)?.path == "/b/computations/revenue.md")
        #expect(OKFLinks.resolve("My%20Note.md", from: document, bundleRoot: root)?.path == "/b/metrics/My Note.md")
        #expect(OKFLinks.resolve("https://x.com", from: document, bundleRoot: root) == nil)
        #expect(OKFLinks.resolve("#section", from: document, bundleRoot: root) == nil)
    }

    @Test func relativePaths() {
        let from = URL(fileURLWithPath: "/b/metrics", isDirectory: true)
        #expect(OKFLinks.relativePath(to: URL(fileURLWithPath: "/b/metrics/a.md"), from: from) == "a.md")
        #expect(OKFLinks.relativePath(to: URL(fileURLWithPath: "/b/tables/o.md"), from: from) == "../tables/o.md")
    }
}

struct EditingTests {
    @Test func replacesOnlyTheTouchedKey() {
        let yaml = "# owner: finance\ntype: Metric\nverified: { by: process:x, at: 2026-06-26T02:00:00Z }\ntags:\n  - a\n- b\nx-extra: 1\n"
        let edited = OKFEditing.setting("tags", to: "tags: [c]", in: yaml)
        #expect(edited == "# owner: finance\ntype: Metric\nverified: { by: process:x, at: 2026-06-26T02:00:00Z }\ntags: [c]\nx-extra: 1\n")
        #expect(OKFEditing.setting("status", to: "status: draft", in: "type: A") == "type: A\nstatus: draft\n")
        #expect(OKFEditing.setting("type", to: nil, in: "type: A\ntitle: B\n") == "title: B\n")
    }

    @Test func addsVerificationKeepingEarlierOnes() throws {
        let yaml = "type: Metric\nverified: { by: process:nightly, at: 2026-06-26T02:00:00Z }\ntitle: Revenue\n"
        let stamp = OKFStamp(by: .human("ana"), at: OKFTimestamp.parse("2026-09-25T10:00:00Z"))
        let edited = try OKFEditing.addingVerification(stamp, to: yaml)
        #expect(edited == """
        type: Metric
        verified:
          - { by: process:nightly, at: 2026-06-26T02:00:00Z }
          - { by: human:ana, at: 2026-09-25T10:00:00Z }
        title: Revenue

        """)
        #expect(try OKFConcept(yaml: edited).trustTier == .humanReviewed)
    }

    @Test func statusEdits() {
        #expect(OKFEditing.settingStatus(.stable, in: "type: A\n") == "type: A\n")
        #expect(OKFEditing.settingStatus(.deprecated, in: "type: A\nstatus: draft\n") == "type: A\nstatus: deprecated\n")
    }

    @Test func scalarsQuoteWhenNeeded() {
        #expect(OKFEditing.scalar("human:ana") == "human:ana")
        #expect(OKFEditing.scalar("Incident response: data") == "\"Incident response: data\"")
        #expect(OKFEditing.scalar("yes") == "\"yes\"")
        #expect(OKFEditing.scalar("a, b") == "\"a, b\"")
    }

    @Test func templateParses() throws {
        let template = OKFEditing.conceptTemplate(type: "Playbook", title: "On-call: alerts", author: .human("ana"))
        let concept = try #require(try OKFConcept.parse(source: template)?.get())
        #expect(concept.type == "Playbook")
        #expect(concept.title == "On-call: alerts")
        #expect(concept.status == .draft)
        #expect(concept.generated?.by == .human("ana"))
    }

    @Test func logEntries() {
        let calendar = Calendar(identifier: .gregorian)
        let day = DateComponents(calendar: calendar, year: 2026, month: 9, day: 25).date!
        let created = OKFEditing.appendingLogEntry("Added [Revenue](/metrics/revenue.md).", date: day, calendar: calendar, to: nil)
        #expect(created == "# Directory Update Log\n\n## 2026-09-25\n* **Update**: Added [Revenue](/metrics/revenue.md).\n")
        let sameDay = OKFEditing.appendingLogEntry("Second.", label: "Creation", date: day, calendar: calendar, to: created)
        #expect(sameDay.contains("## 2026-09-25\n* **Creation**: Second.\n* **Update**"))
        let older = "# Directory Update Log\n\n## 2026-05-22\n* **Update**: Old.\n"
        let next = OKFEditing.appendingLogEntry("New.", date: day, calendar: calendar, to: older)
        #expect(next == "# Directory Update Log\n\n## 2026-09-25\n* **Update**: New.\n\n## 2026-05-22\n* **Update**: Old.\n")
        #expect(OKFValidator.validate(source: next, kind: .log).isEmpty)
    }
}

struct ValidatorTests {
    @Test func conformanceErrors() {
        #expect(OKFValidator.validate(source: "# No frontmatter", kind: .concept).map(\.severity) == [.error])
        #expect(OKFValidator.validate(source: "---\ntitle: x\n---\n", kind: .concept).map(\.severity) == [.error])
        #expect(OKFValidator.validate(source: "---\ntype: Anything New\nx-custom: 1\n---\n", kind: .concept).isEmpty)
    }

    @Test func softGuidance() {
        let source = "---\ntype: Metric\nstatus: retired\ngenerated: { at: 2026-06-20 }\nstale_after: 2026-01-01T00:00:00Z\n---\n"
        let found = OKFValidator.validate(source: source, kind: .concept, now: OKFTimestamp.parse("2026-09-25T00:00:00Z")!)
        #expect(!found.contains { $0.severity == .error })
        #expect(found.contains { $0.message.contains("Unknown status") })
        #expect(found.contains { $0.message.contains("missing `by`") })
        #expect(found.contains { $0.message.contains("UTC offset") })
        #expect(found.contains { $0.message.hasPrefix("Stale since") })
    }

    @Test func specExampleIsClean() {
        let found = OKFValidator.validate(source: revenue, kind: .concept, now: OKFTimestamp.parse("2026-07-01T00:00:00Z")!)
        #expect(found.isEmpty)
    }

    @Test func indexAndLogStructure() {
        #expect(OKFValidator.validate(source: "---\nokf_version: \"0.2\"\n---\n# A\n", kind: .index, isBundleRoot: true).isEmpty)
        #expect(OKFValidator.validate(source: "---\nokf_version: \"0.2\"\n---\n", kind: .index, isBundleRoot: false).count == 1)
        #expect(OKFValidator.validate(source: "---\ntitle: x\n---\n", kind: .index, isBundleRoot: true).count == 1)
        let log = "# Log\n\n## 2026-05-01\n* a\n\n## May 22\n* b\n\n## 2026-06-01\n"
        let found = OKFValidator.validate(source: log, kind: .log)
        #expect(found.map(\.severity).sorted() == [.warning, .error])
    }
}

struct BundleTests {
    private func makeBundle() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("okf-\(UUID().uuidString)", isDirectory: true)
        let files: [String: String] = [
            "index.md": "---\nokf_version: \"0.2\"\n---\n# Tables\n\n* [Orders](tables/orders.md)\n",
            "tables/orders.md": "---\ntype: BigQuery Table\ntitle: Orders\ndescription: One row per order.\n---\nJoins [customers](/tables/customers.md).\n",
            "tables/customers.md": "---\ntype: BigQuery Table\ntitle: Customers\n---\nSee [orders](./orders.md) and [ghost](/tables/ghost.md).\n",
            "playbooks/freshness.md": "---\ntype: Playbook\n---\nCheck the [orders table](/tables/orders.md).\n",
            "playbooks/notes.md": "No frontmatter here.\n",
            "tables/log.md": "# Log\n\n## 2026-09-01\n* **Update**: x\n"
        ]
        for (path, text) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        return root
    }

    @Test func findsRootFromDeclaredVersion() throws {
        let root = try makeBundle()
        defer { try? FileManager.default.removeItem(at: root) }
        let found = OKFBundle.findRoot(for: root.appendingPathComponent("tables/orders.md"))
        #expect(OKFBundle.key(found) == OKFBundle.key(root))
        #expect(OKFBundle.declaredVersion(at: root) == "0.2")
    }

    @Test func fallsBackToBoundaryThenFolder() throws {
        let root = try makeBundle()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.removeItem(at: root.appendingPathComponent("index.md"))
        let file = root.appendingPathComponent("tables/orders.md")
        #expect(OKFBundle.key(OKFBundle.findRoot(for: file, boundary: root)) == OKFBundle.key(root))
        #expect(OKFBundle.key(OKFBundle.findRoot(for: file, boundary: root.appendingPathComponent("playbooks")))
                == OKFBundle.key(root.appendingPathComponent("tables")))
    }

    @Test func scansLinksAndBacklinks() throws {
        let root = try makeBundle()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = OKFBundle.load(root: root)
        #expect(bundle.okfVersion == "0.2")
        #expect(bundle.documents.count == 6)
        #expect(bundle.concepts.count == 4)
        let orders = root.appendingPathComponent("tables/orders.md")
        #expect(bundle.document(for: orders)?.conceptID == "tables/orders")
        #expect(Set(bundle.backlinks(to: orders).map(\.path)) == ["/index.md", "/tables/customers.md", "/playbooks/freshness.md"])
        let customers = try #require(bundle.document(for: root.appendingPathComponent("tables/customers.md")))
        #expect(bundle.brokenLinks(in: customers).map(\.target) == ["/tables/ghost.md"])
    }

    @Test func validatesBundle() throws {
        let root = try makeBundle()
        defer { try? FileManager.default.removeItem(at: root) }
        let found = OKFValidator.validate(bundle: OKFBundle.load(root: root))
        #expect(found.filter { $0.severity == .error }.map(\.path) == ["/playbooks/notes.md"])
        #expect(found.contains { $0.severity == .info && $0.path == "/tables/customers.md" })
    }

    @Test func rendersIndex() throws {
        let root = try makeBundle()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = OKFBundle.load(root: root)
        let tables = OKFEditing.renderIndex(directory: root.appendingPathComponent("tables"), bundle: bundle)
        #expect(tables == "# BigQuery Table\n\n* [Customers](customers.md)\n* [Orders](orders.md) - One row per order.\n")
        let top = OKFEditing.renderIndex(directory: root, bundle: bundle, existing: "---\nokf_version: \"0.2\"\n---\nold")
        #expect(top == "---\nokf_version: \"0.2\"\n---\n\n# Directories\n\n* [playbooks](playbooks/) - 2 concepts\n* [tables](tables/) - 2 concepts\n")
        #expect(OKFValidator.validate(source: top, kind: .index, isBundleRoot: true).isEmpty)
    }
}
