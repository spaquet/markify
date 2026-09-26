# Open Knowledge Format (OKF) support

Status: Implemented (P1–P5) · Target spec: OKF v0.2 · Tracking since 2026-09-25

## Why

Google's [Open Knowledge Format](https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md) (OKF, v0.1 on 2026-06-12, v0.2 current) packages knowledge for AI agents as a **bundle**: a directory of Markdown files with YAML frontmatter, cross-linked with plain Markdown links. Markify already opens and renders every OKF file. Supporting OKF means understanding what the frontmatter and the directory mean, so people can read, review and maintain bundles in Markify.

OKF is conventions, not syntax. The source stays plain Markdown: Markify must never rewrite YAML it did not change.

## The format in one page

- **Bundle**: a directory tree. `index.md` (directory listing) and `log.md` (update history) are reserved at any level; every other `.md` file is a **concept**. A concept's ID is its bundle path without `.md`.
- **Frontmatter**: `type` is the only required key (free-form: `Metric`, `Playbook`, `BigQuery Table`, …). Recommended: `title`, `description`, `resource` (URI), `tags`.
- **Provenance**: `sources` (list of `{ resource, id, title, author, usage_count, last_modified }`) plus a shared `usage_window: { from, to }`. Per-claim attribution uses footnotes keyed by `sources[].id`.
- **Trust**: `generated: { by, at }`; `verified:` list of `{ by, at }` (a bare mapping counts as a one-element list). Trust tier: no `verified` → unverified; only non-human verifiers → machine-confirmed; any `human:` verifier → human-reviewed.
- **Lifecycle**: `status: draft | stable | deprecated` (absent → stable); `stale_after` (stale when `now >= stale_after`).
- **Actors**: `<producer>/<version>` for agents, `human:<id>`, `process:<id>`.
- **Links**: bundle-absolute `/path/concept.md` (recommended) or relative. Broken links are allowed.
- **Attested Computation** (`type: Attested Computation`): `runtime` (required), `parameters`, `computation`, `executor { resource, receipt }`, `attester { resource }`.
- **Index**: `# Heading` sections of `* [Title](url) - description`. No frontmatter, except `okf_version` in the bundle-root `index.md`.
- **Log**: `## YYYY-MM-DD` headings, newest first, with entries such as `* **Update**: …`.
- **Conformance**: every concept has parseable frontmatter with a non-empty `type`, and reserved files follow their structure. Consumers must not reject a bundle for missing optional fields, unknown types or keys, broken links, or a missing `index.md`.
- Timestamps are ISO 8601 with an explicit offset (`2026-06-30T14:00:00Z`).

## Requirements

### R1 Reading (a concept on its own)
- R1.1 Parse the full frontmatter, including nested maps and lists, with a real YAML parser.
- R1.2 In the Rendered lens, the frontmatter chip row shows the concept's `type`, a `draft` or `deprecated` status, a stale warning, the trust tier, and a clickable `resource` link, next to the existing tags and date.
- R1.3 Plain notes without a `type` look exactly as they do today.
- R1.4 ⌘-click a link to follow it: web links open in the browser; `.md` links open in Markify, with `/…` resolved against the bundle root.

### R2 Bundles
- R2.1 Find the bundle root: the nearest ancestor whose `index.md` declares `okf_version`; otherwise the library folder when the file is inside it; otherwise the file's folder.
- R2.2 Scan the bundle in the background and build the link graph.
- R2.3 The sidebar's Knowledge section shows backlinks to the current concept, its issues, and bundle-wide issues. Clicking one opens that file.
- R2.4 The validator reports errors (non-conformant files), warnings (SHOULD-level problems) and info (broken links, staleness). It never refuses a bundle.
- R2.5 The Library list uses the frontmatter `title` and `description` when present.

### R3 Authoring
- R3.1 A slash-menu "Concept" template inserts OKF frontmatter.
- R3.2 Knowledge menu actions:
  - **Make Concept**: adds `type`.
  - **Mark Verified**: appends `{ by: human:<id>, at: <now> }` to `verified`.
  - **Status**: draft, stable or deprecated.
  - **Add Log Entry…**: writes to the directory's `log.md`.
  - **Rebuild Index**: rewrites the directory's `index.md`.
- R3.3 The verifier ID is set in Settings › General › Knowledge (default: the macOS short user name).
- R3.4 Every frontmatter change is a targeted splice of the affected key, applied as one undoable edit. Comments, key order and unknown keys survive.

### R4 Apple Intelligence
- R4.1 In an OKF document, "Suggest title, type & tags" also suggests a one-sentence `description`, and a `type` when none is written, preferring types the bundle already uses.
- R4.2 Keeping any frontmatter suggestion merges it key by key; other keys (`date`, `verified`, `sources`, …) are never lost. `type` is never overwritten.
- R4.3 Keeping AI text in a concept (Keep, Accept, or typing past a review) sets `generated: { by: apple-intelligence/macos-<version>, at: <now> }`, in the same undo step as the kept text where possible. Settings › Intelligence › "Record AI edits in OKF concepts" turns it off.

### R5 Complete bundle support
- R5.1 **File › Open Bundle Folder…** (⇧⌘O) remembers the folder as a security-scoped bookmark, so every file in it is reachable across launches. A granted folder is a bundle even without `okf_version`.
- R5.2 The sidebar browses the bundle by folder, type or tag (the tag view is built from frontmatter, §3.1). The search field filters concepts by title, description and tag.
- R5.3 The sidebar shows the current concept's provenance: last change and author, last verification, `sources` with their credibility signals (author, usage count, last modified), and v0.1 `# Citations` when there are no `sources`.
- R5.4 Attested Computations show their contract (runtime, parameters, computation, executor with receipt fields, attester) as links. Nothing is executed.
- R5.5 Path-valued fields (`resource`, `sources[].resource`, `computation`, `executor.resource`, `attester.resource`) count as links: they create backlinks and are checked for missing targets. Scope descriptors and URLs are ignored.
- R5.6 Footnotes keyed to a `sources` id show that source in their tooltip.
- R5.7 After Rename or Move To, Markify offers to update links to the moved file across the bundle, and the moved file's own relative links. Each link keeps its style (absolute or relative).
- R5.8 Typing `](` or `](/` suggests the bundle's concept paths.
- R5.9 The bundle is watched for changes on disk and rescanned.
- R5.10 Typing in a concept's body records `generated: { by: human:<id>, at: <now> }` after a pause, at most once a day. Settings › General › Knowledge › "Record my edits in OKF concepts" turns it off.
- R5.11 HTML export rewrites bundle-absolute links as relative paths from the exported file.
- R5.12 v0.1 bundles: `timestamp` stands in for `generated.at`, and `# Citations` for `sources`. A bundle targeting an unknown `okf_version` gets a notice and is read best effort. Index entries are checked for sections, links and descriptions.

### Out of scope
- Running Attested Computations (executors, receipts, attesters). Markify shows the contract but executes nothing.
- A graph visualization.
- Zip or tarball bundles (§3). Unpack them first.

## Design

### OKFKit (`OKFKit/`)
A local Swift package with no UI, depending only on [Yams](https://github.com/jpsim/Yams), and tested with Swift Testing (`swift test --package-path OKFKit`).

| File | Role |
|---|---|
| `FrontmatterBlock.swift` | Splits a source into YAML and body, keeping UTF-16 offsets for the editor. |
| `Concept.swift` | `OKFConcept`: typed fields, unknown key names, `trustTier`, `isStale(at:)`. |
| `Actor.swift` | `OKFActor` (agent, human, process, other). |
| `Links.swift` | Extracts Markdown links from a body (skipping code) and resolves bundle-absolute and relative targets. |
| `Bundle.swift` | `OKFBundle`: root discovery, scan, documents, backlinks. |
| `Validator.swift` | Per-document and bundle diagnostics following §11. |
| `Editing.swift` | YAML key splicing, verification stamps, index and log rendering, the concept template. |

Spec-version knowledge lives only in OKFKit (`OKF.specVersion`). Readers are tolerant: unknown versions are consumed on a best-effort basis.

### App layer
- `Markify/Knowledge.swift`: bundle loading, folder access (`BundleAccess`), file watching (`BundleWatcher`), link following, log and index writes, and the sidebar browser and concept details.
- `NativeEditor.swift`: chip row badges, ⌘-click link following, bundle root for resolving `/` links.
- `ContentView.swift`: Knowledge menu, sidebar wiring, Library titles.
- `SettingsView.swift`: the verifier ID.

## Decisions
- Yams over a hand-written parser: OKF depends on nested flow mappings (`{ by: …, at: … }`), which break line-based parsers. Yams only reads; writes are text splices, so formatting survives.
- The existing lightweight `Frontmatter` parser keeps driving tags, title and date. It stays lenient while the YAML is half-typed, which Yams is not.
- Bundle features are limited by the App Sandbox to folders Markify can reach (the library, or panel-granted folders).
- `index.md` and `log.md` are only written by explicit commands, never automatically.

## Phases
1. **P1 Reader**: OKFKit model and validator, chip badges, link following.
2. **P2 Bundle**: scan, backlinks, issues, Library titles.
3. **P3 Authoring**: template, verify and status actions, log and index commands, settings.
4. **P4 AI**: type and description suggestions, merged frontmatter, `generated` stamps.
5. **P5 Complete**: Open Bundle Folder, bundle browser, provenance and computation panels, link rewriting on move, link completion, file watching, human `generated` stamps, export links, v0.1 fallbacks.
