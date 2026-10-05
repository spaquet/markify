# Anonymous editor performance telemetry

Status: proposal for future implementation. This document adds no instrumentation and changes no collection behavior.

## Purpose

Understand how document size and composition affect Markify's performance, without sending document content or identifying documents. Useful questions include:

- How do parsing, styling and initial display scale with source line count?
- Are documents containing tables, Mermaid or math slower than ordinary text Markdown of similar size?
- Does a release improve or regress performance in either lens?
- Are delays caused by editor work, renderer queues or uncached resources?

Start with sampled document presentation and its parse/style work. Add renderer details and sampled editing measurements only when the initial data leaves a specific question unanswered.

## Existing foundation

[MarkifyApp.init](Markify/MarkifyApp.swift) starts Sentry when a DSN exists and the app is not running as a test host. It sets `sendDefaultPii = false`, `tracesSampleRate = 0.1`, and separately configures profiling with `sessionSampleRate = 0.1` and a trace lifecycle. These are separate sampling settings; the trace rate does not mean ten percent of users or document opens are currently measured.

The resolved Sentry Cocoa dependency is currently **9.30.0** in [Package.resolved](Markify.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved). There are no custom editor spans yet. Reuse this dependency and verify the tracing and query APIs against the installed SDK when implementing.

[PerformanceAuditTests](MarkifyTests/PerformanceAuditTests.swift) already measures parsing, full styling and incremental styling locally with `ContinuousClock`, plus other editor workloads. Reuse its definitions and workloads for validation rather than creating a parallel benchmark system.

## Current partial refresh and caching

Partial refresh already exists, but parsing, styling and drawing have different boundaries:

- **Parsing:** character edits increment `MarkdownTextView.textVersion`; `model` reuses the cached model until the version or MDX mode changes. The next model request after a text edit rebuilds the full model. Styling-only changes do not invalidate it. There is no incremental parser today.
- **Typing:** `Coordinator.textDidChange` calls `style(..., incremental: true)`. `changedStyledParagraph(key:)` takes a paragraph-only styling path for a single eligible edit with unchanged style settings and suitable old/new paragraph models. Structural constructs and multiple edits fall back to full-document styling in a scratch text storage. `applyChangedAttributes` then writes only changed attribute runs to the live storage, preserving unaffected layout where possible. This reduces styling/layout work, but does not remove the full parse after a text edit.
- **Drawing:** TextKit 2 lays out the viewport as needed; layout fragments draw their own decorations. This avoids eagerly drawing every paragraph in the document.
- **Asset completion:** Mermaid, local images and HTML schedule a coalesced restyle on the next run-loop turn. The `restyle` callback installed by `makeNSView` calls ordinary full styling, so these updates are not currently block-only styling updates. Display math completion sets `needsDisplay` instead. Cached assets avoid repeated expensive renderer work during subsequent passes.

| Cache | Key and lifetime |
| --- | --- |
| Parsed Markdown | Per editor, text version and MDX mode; reused by styling, drawing and interaction. |
| Mermaid | Shared renderer, diagram source and dark/light appearance; deduplicates pending requests and keeps bounded settled results. Owners release unused diagrams. |
| Math | Per editor, formula source, size and appearance; inline formula and display-image caches have count/memory limits. `retainMath` drops entries no longer needed by the model or appearance. |
| HTML import | Per editor, width, accent and final HTML including inlined images; retains pending/completed/failure state with count and memory limits. Obsolete blocks are released. |
| Local images | Per editor, URL with file stamps for change detection; pending work is deduplicated, decoded images are bounded by a memory budget, and unused images are released. |
| Remote images | Shared `RemoteImages` state keyed by URL, with deduplicated requests and a memory budget; owner subscriptions release resources when no longer needed. |

These are in-memory rendering caches, not persistent document identities. Their source-bearing keys must stay out of telemetry. Measure paragraph styling, full fallback and asset-triggered restyles separately before considering more granular refresh changes.

## Document composition

Derive composition from the **full, cached** [MarkdownTextView.model](Markify/NativeEditor.swift) and [MarkdownModel](MarkifyMarkdown/Sources/MarkifyMarkdown/MarkdownModel.swift). Do not parse again, scan Markdown with regular expressions, or classify from an incremental paragraph model. The latter intentionally omits the rest of the document.

Use independent presence flags so one document can contain tables, diagrams and math together. A single exclusive document type would hide these combinations.

| Proposed field | Existing source and definition |
| --- | --- |
| `document.lines_bucket` | Source line count, including blank lines. Use Foundation line enumeration; treat CRLF as one terminator, an empty source as zero lines, and a trailing terminator as ending the last line rather than adding a phantom line. Never count visual wrapped lines. |
| `document.bytes_bucket` | UTF-8 source size; this is source text size, not total linked asset size. |
| `document.has_tables` | `!model.tables.isEmpty`. Tables are in a separate collection, not a `Kind.table` span. |
| `document.tables_bucket` | `model.tables.count`. Optional later: total cells in rows excluding `Row.separator`. |
| `document.has_mermaid` | A `.codeBlock(language: ..., fenced: true)` span whose language lowercased equals `mermaid`, matching `NativeEditor.style` exactly. |
| `document.mermaid_bucket` | Number of those Mermaid spans, whether rendering succeeds or fails. |
| `document.has_math` | At least one `.mathBlock` or `.inlineMath` span. |
| `document.math_blocks_bucket` / `document.inline_math_bucket` | Count the two kinds separately because their rendering paths differ. |
| `document.has_images` | At least one `.image` span. Covers Markdown images; images inside raw HTML are covered by the HTML flag, not discovered through a new scan. |
| `document.has_code` | At least one `.codeBlock` other than a recognized Mermaid fence. Inline code remains ordinary text formatting. |
| `document.has_html` | At least one `.htmlBlock` or `.inlineHTML` span. |
| `document.has_mdx` | At least one `.mdxBlock` span; keep MDX mode as a separate boolean because an MDX document may contain only ordinary Markdown. |
| `document.text_only` | No tables, Mermaid, math, Markdown images, other code blocks, HTML or MDX blocks. Headings, emphasis, links, lists, tasks, quotes, callouts, footnotes and frontmatter are allowed. This means text-oriented Markdown, not a claim that the source contains only prose. |

Presence describes recognized source syntax, not what is currently visible, loaded or successfully rendered. Avoid summing all spans into an element total: containers overlap their children. Counts must refer to explicit kinds or collections.

Suggested fixed buckets:

- Lines: `0`, `1–99`, `100–499`, `500–999`, `1000–4999`, `5000–9999`, `10000+`.
- UTF-8 bytes: `0`, `1–1023`, `1024–10239`, `10240–102399`, `102400–1048575`, `1048576+`.
- Element counts: `0`, `1`, `2–5`, `6–20`, `21+`.

Keep exact counts in memory only and send bucket labels. Collect composition once per sampled source version, outside the measured operation where possible. Reuse that snapshot for related spans. Attribute a timing to the source version that actually produced it, not to a later edit.

## Measurement locations

Names below are proposed fixed operation names, never document titles or paths. Timings should use a monotonic clock; Sentry spans represent elapsed wall time, including waits where noted.

| Proposed operation | Code to instrument | Meaning and limits |
| --- | --- | --- |
| `document.decode` (optional) | [MarkifyDocument.init(configuration:)](Markify/MarkifyDocument.swift) | Decode the supplied regular-file contents as UTF-8. The file wrapper already exists here: this does **not** measure complete disk I/O or open-to-display time. |
| `editor.present` | [NativeEditor.makeNSView(context:)](Markify/NativeEditor.swift) | Start when editor construction begins. End when the initial viewport has completed its drawing pass for the captured source version. This is editor presentation time, not time from the user's Finder/open command. |
| `markdown.parse` | [MarkdownTextView.model](Markify/NativeEditor.swift), around the cache-miss `MarkdownModel(string, mdx:)` construction | Measure actual model construction, including extension detection, cmark work, walking and sorting. Cache hits are not parses. Keep Sentry in the app layer; the Markdown package stays UI-free and telemetry-free. |
| `editor.style` | [NativeEditor.style(_:incremental:using:)](Markify/NativeEditor.swift) | Measure an accepted styling pass through attribute application. Separate full, incremental paragraph and incremental full-document paths. Reentrant requests that merely defer a restyle are not completed style operations. Recursive scratch-view styling must not become a second top-level editor event. |
| `editor.tables` (later) | [MarkdownTextView.refreshTables()](Markify/NativeEditor.swift) | Measure visible table layout and cell-view maintenance. This can include `ensureLayout` for the viewport and margin; it does not represent all tables in the document. |
| `editor.lens_switch` (later) | [NativeEditor.updateNSView(_:context:)](Markify/NativeEditor.swift) | Start for an actual lens change and end after the resulting viewport drawing pass. This method also handles source, theme and search changes, which must not be labeled lens switches. |
| `mermaid.queue` / `mermaid.render` (later) | [MermaidRenderer.state(of:dark:owner:onChange:), start(), render(_:), finish(_:_:)](Markify/Mermaid.swift) | Distinguish request-to-job-start from JavaScript rendering plus snapshot completion. Record cache hits separately. The shared renderer serializes work across windows and exports, so queue time matters. |
| `math.inline` / `math.block` (later) | [MarkdownTextView.inlineFormula(_:size:dark:) and displayMath(_:dark:)](Markify/NativeEditor.swift) | Inline math constructs a formula synchronously on a miss. Display math schedules a worker; finish at its completion, not when the requesting method returns. Capture cache status and bounded outcomes. |
| `html.import` (later) | [MarkdownTextView.renderHTML(_:width:)](Markify/NativeEditor.swift) | On a cache miss, measure through the `NSAttributedString.loadFromHTML` completion and accepted result. Returning a placeholder is not completion. Mark stale results separately. |
| `image.load` (later) | [MarkdownTextView.image(for:embed:) and RemoteImages](Markify/NativeEditor.swift) | Separate local decode, remote wait and cache hit only if images emerge as a cause of delays. No URL, path or image metadata enters telemetry. |

### What “render time” means

`style()` returning is **not** proof that the document has rendered. TextKit 2 lays out the viewport as needed, and Mermaid, display math, HTML and remote images may still be pending.

For the first implementation, report `editor.present` as **initial viewport drawing**, allowing placeholders. The drawing boundary is [MarkdownLayoutFragment.draw(at:in:)](Markify/MarkdownLayoutFragment.swift), which calls [MarkdownTextView.drawDecorations(anchoredIn:)](Markify/NativeEditor.swift). A single fragment callback does not prove that the viewport is complete. Establish a one-shot, view-level completion boundary for the initial visible fragments and validate it before shipping this metric. Drawing completion is an application-side proxy, not proof that pixels reached the physical display.

Do not force `ensureLayout` over the whole document merely to obtain a measurement. That would change the behavior being measured and defeat viewport layout. Do not send a span for every fragment or draw call.

If later needed, add a separate **initial viewport assets settled** measurement: wait only for the assets required by the captured viewport and source version. Include bounded outcomes such as `success`, `failed`, `cancelled`, `stale`, or `timeout`; missing or disabled remote images must not leave a trace open indefinitely. Assets outside the viewport do not block it. Never label either metric “whole document fully rendered.”

## Sampling and event shape

Keep the existing ten-percent trace sampling as the starting point. Let child spans inherit the root decision; do not independently sample each phase. Avoid computing extra counts for unsampled traces.

Initially create one fixed-name presentation transaction per editor creation. Include `editor.lens = rendered|markdown`, `document.mdx_mode`, and the composition fields above. Keep the parse/style spans nested so their work is not added twice to an overall elapsed duration. A renderer cache hit must not fabricate a render duration.

Do not create a transaction for every keystroke, scroll or redraw. If editing telemetry is later justified, sample and cap it per editor session; distinguish paragraph styling from full-document fallback and label restyle reasons with a fixed allowlist.

Use only trace-local correlation. A source-version counter can stay local to reject stale completions; never transmit a document hash, persistent document ID or identity derived from a filename. Renderer jobs shared between windows should be timed once, with consumer wait time attributed separately when necessary.

## Privacy requirements before implementation ships

- Allowlist every transmitted custom field. Send fixed operation names, bucket labels, booleans, durations and bounded outcome/cache labels only.
- Exclude source, titles, filenames, paths, links, image URLs, code language strings other than fixed classification, math expressions, diagram source, frontmatter values and footnote labels. Do not send source-derived hashes or screenshots.
- Never use renderer cache keys as telemetry identifiers: Mermaid keys contain diagram source and HTML/math caches also contain source material. Renderer error messages can echo content; report a fixed failure category instead.
- Audit the **complete outgoing envelope**, including automatic breadcrumbs, network spans, exception descriptions and profiling metadata. `sendDefaultPii = false` does not sanitize arbitrary custom fields or guarantee anonymity. Sentry still receives the network connection's IP address; check server-side handling before describing data as anonymous.
- Preserve DSN/test-host guards. Confirm configuration and project-side scrubbing using an inspected development payload before production collection.
- Update the app disclosure in [help/legal.md](help/legal.md) and related wording in [help/faq.md](help/faq.md). Review “no usage analytics” claims against the final scope. Run `scripts/build-help.sh` with those future changes; no disclosure change is needed for this proposal alone.

## Validation and intended reports

Before shipping, add a small composition test covering text-only Markdown, tables, mixed-case Mermaid fences, inline/block math and mixed documents. Cover bucket boundaries, empty text and CRLF line endings. Verify that syntax-looking text inside ordinary code fences does not become a table/math/diagram flag and that incremental paragraph models do not determine full-document composition.

Use the existing performance audit workloads to check instrumentation overhead and confirm that source text, selection, undo, cached parsing and lazy layout remain unchanged. Exercise asynchronous success, failure, cancellation and stale completion. Inspect an outgoing payload containing deliberately recognizable private text and paths; none should appear in the transmitted envelope. Validate the initial viewport boundary with multiple visible fragments and pending assets.

In Sentry, compare median and p95 presentation/parse/style durations by release, lens and size bucket, then filter independently on tables, Mermaid and math. Display sample counts alongside percentiles; small groups and repeated opens do not represent distinct users or documents. Verify that the selected custom fields can be queried and grouped in the current Sentry project before expanding collection.

## Apple measurements and Sentry

Custom Sentry instrumentation is the direct route to pairing a document's composition with a particular operation's timing. Apple signposts can mark the same boundaries for local Instruments investigations; they do not automatically become Sentry spans.

MetricKit is complementary system diagnostics and aggregated performance data. Apple's documentation states that daily metric reports are supported on macOS 26 and later. Aggregated daily reports cannot replace per-operation composition/timing pairs. Defer any MetricKit bridge until there is a specific system metric to collect, and verify what the installed Sentry SDK actually forwards rather than assuming that it imports all metrics or custom signposts.

References for implementation:

- [Sentry Cocoa SDK](https://github.com/getsentry/sentry-cocoa)
- [Sentry Apple custom instrumentation](https://docs.sentry.io/platforms/apple/tracing/instrumentation/custom-instrumentation/)
- [Apple MetricKit](https://developer.apple.com/documentation/metrickit)
- [Apple MXMetricManager report availability](https://developer.apple.com/documentation/metrickit/mxmetricmanager)
