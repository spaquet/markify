# Performance audit — completed 5 October 2026

This report preserves the 4 October baseline and records the verified optimization results on `optimize`. The fifteen original findings below describe baseline source, including historical line numbers; the implementation-status table records what changed. This audit does not certify whole-app responsiveness, memory or energy behavior.

Baseline: `b0d6ee6539169ed5dd4b03eaf076f9f3cd3ee3dd`, including the existing uncommitted document-refresh and project changes. Measurements use an Apple M1 Max, macOS 27.2 (26B5091g), Xcode 27.1 (27A9269), arm64, Release optimization with `ENABLE_TESTABILITY=YES`. Existing changes were preserved.

## Measurement method

`MarkifyTests/PerformanceAuditTests.swift` is an opt-in diagnostic. It measures synchronous operations on MainActor using `ContinuousClock`, normally with three samples. It uses the actual `MarkdownTextView`, model, style implementation, table overlays and document-refresh implementation. Synthetic prose includes emphasis and links; tables contain three columns with numeric values and formatted links. No network images or Mermaid renders run in these workloads.

The edit measurement inserts a character in text storage, then calls the same incremental style pass used by `Coordinator.textDidChange`. The table edit additionally runs `refreshTables()`. This measures synchronous work, not the complete key-to-screen latency: SwiftUI updates, queued refreshes, drawing, autosave and telemetry are excluded. Full-style samples reuse an editor; the first is cold and subsequent samples reuse its parsed model. Initial table overlays and cold HTML import have one sample. The baseline ran all workloads sequentially in one host without draining the run loop; accumulated objects and importer reentrancy can affect timings. After measurements isolate HTML in a separate host. Editor workloads still run sequentially, and the table viewport is at the top of the document. These are diagnostic observations, not regression thresholds or statistically stable percentiles.

Reproduce from the repository root:

```sh
TEST_RUNNER_MARKIFY_PERFORMANCE_AUDIT=1 xcodebuild -quiet \
  -project Markify.xcodeproj -scheme Markify -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  '-only-testing:MarkifyTests/PerformanceAuditTests/measureHTMLImport()' \
  -parallel-testing-enabled NO \
  test CODE_SIGNING_ALLOWED=NO ENABLE_TESTABILITY=YES
```

Run that command again in a separate invocation with `measureEditorWork()` in place of `measureHTMLImport()`. The parentheses are part of Swift Testing's identifier: omitting them selected zero tests despite exit 0. Confirm `totalTestCount > 0`, `result: Passed` and zero failures with `xcrun xcresulttool get test-results summary --path <bundle>`.

Use Xcode's default DerivedData, per AGENTS.md. Editor samples go to `/private/tmp/markify-performance-audit.json`; HTML samples go to `/private/tmp/markify-performance-html-audit.json`. `TEST_RUNNER_` forwards the flag into the test host as `MARKIFY_PERFORMANCE_AUDIT`; ordinary test runs skip this diagnostic. Release normally disables testability, so the explicit override is necessary. This build override does not change project settings.

Apple describes noticeable discrete-interaction delays at approximately 50–100 ms and recommends keeping main-thread screen-update work below roughly 5 ms. These are useful responsiveness reference points, not hardware-independent guarantees. [Apple: Improving app responsiveness](https://developer.apple.com/documentation/xcode/improving-app-responsiveness), [Apple: Understanding user interface responsiveness](https://developer.apple.com/documentation/xcode/understanding-user-interface-responsiveness).

The baseline diagnostic passed: **1 test, 0 failures**, in `/private/tmp/markify-performance-audit-progress.xcresult`. Raw samples are preserved in [performance-audit-results.json](performance-audit-results.json). Times below are median milliseconds unless marked as a single sample. Sizes are UTF-8 bytes, with KB shown in decimal units.

| Workload | Size | Operation | Time |
| --- | --- | --- | ---: |
| 100 rich paragraphs | 7.3 KB | Edit + incremental style | 37.3 ms |
| 1,000 rich paragraphs | 73.0 KB | Edit + incremental style | 370.8 ms |
| 5,000 rich paragraphs | 365.0 KB | Edit + incremental style | 2,370.0 ms |
| 5,000 rich paragraphs | 365.0 KB | Word count alone | 91.0 ms |
| 500 inline groups on one line | 18.5 KB | Parse | 149.8 ms |
| 1,500 inline groups on one line | 55.5 KB | Parse | 1,293.6 ms |
| 50 table body rows | 2.8 KB | Edit + style + overlays | 133.9 ms |
| 200 table body rows | 11.4 KB | Edit + style + overlays | 1,320.1 ms |
| 500 table body rows | 28.8 KB | Edit + style + overlays | 7,418.8 ms |
| 500 table body rows | 28.8 KB | Refresh unchanged overlays | 5,145.6 ms |
| 500 table body rows | 28.8 KB | Initial overlays, single sample | 9,509.3 ms |
| 1,500 inline formulas | 40.5 KB | Warm full style | 59.3 ms |
| One HTML block | 106 B | Cold full style, single sample | 364.7 ms |
| Unchanged local file | 1.2 MB | Cached-file refresh, 10 samples | 0.087 ms |

The strongest confirmed blockers are table maintenance, whole-document edit styling, and long-line parsing. Tripling long-line groups from 500 to 1,500 increased parse time approximately 8.6×. Quadrupling table body rows from 50 to 200 increased unchanged overlay refresh from 57.2 ms to 844.9 ms, approximately 14.8×. Both observations agree with the nested scans visible in source, though they do not attribute all cost to one function. The cheap warm local-file read does not establish low idle energy or rule out slow-volume stalls; unconditional reads and wakeups remain a source-supported gap. Warm math parsing scaled roughly linearly in this workload, so the extension-overlap concern is a follow-up risk rather than a demonstrated math-parser bottleneck.

The first Release attempt could not compile tests because Release disables testability. A subsequent run ended with `Test crashed with signal term` and a launch-session expiry in Xcode's logs; its cause was not established and no timings from that run are reported. After persisting results per workload, the full diagnostic completed successfully. No production settings or app code were changed to obtain these results.

Validation after the diagnostic: all **3 existing IncrementalStyleTests passed**, and the diagnostic was **skipped without its opt-in flag**, in `/private/tmp/markify-performance-audit-checks.xcresult`. These cover equality with a full style pass, unchanged attributes above the edit, and stable viewport/page height while typing. The individual fixture performance filter did not select a test in that invocation; the fixture guard discussed below was inspected in source, not executed. At baseline, the full test suite was not run; the final checks above supersede that validation limit. `git diff --check` passed.

## Verified after-results — 5 October

Successful samples are saved separately in [performance-audit-results-after.json](performance-audit-results-after.json), leaving [performance-audit-results.json](performance-audit-results.json) unchanged. The after file contains 37 editor measurements and two HTML measurements. Production changes through `f20421e` and the corrected diagnostic in `e09a13b` were exercised; the pending user version and ReportTests edits were preserved. The host and Release/testability settings match the baseline.

| Workload / operation | Baseline median | After median |
| --- | ---: | ---: |
| 100 rich paragraphs, edit + incremental style | 37.31 ms | 4.98 ms |
| 1,000 rich paragraphs, edit + incremental style | 370.78 ms | 42.48 ms |
| 5,000 rich paragraphs, edit + incremental style | 2,370.01 ms | 209.27 ms |
| 5,000 rich paragraphs, full style | 1,057.78 ms | 1,075.88 ms |
| 5,000 rich paragraphs, parse | 179.73 ms | 172.32 ms |
| 500 inline groups on one line, parse | 149.77 ms | 9.02 ms |
| 1,500 inline groups on one line, parse | 1,293.57 ms | 27.19 ms |
| 50 table rows, edit + style + overlays | 133.91 ms | 7.02 ms |
| 200 table rows, edit + style + overlays | 1,320.10 ms | 17.31 ms |
| 500 table rows, edit + style + overlays | 7,418.85 ms | 38.19 ms |
| 500 table rows, unchanged overlays | 5,145.64 ms | 3.01 ms |
| 500 table rows, initial overlays (one sample) | 9,509.33 ms | 74.25 ms |
| 1,500 inline formulas, warm full style | 59.26 ms | 53.02 ms |
| Unchanged local file, explicit refresh (10 samples) | 0.087 ms | 0.003 ms |

The original uncached word-count probe remains approximately 91 ms for 5,000 paragraphs. ContentView now caches against its String binding: a cold count is 22.61 ms and a warm lookup is below 0.001 ms in this diagnostic. The cached probes capture the binding-equivalent String outside the clock; repeatedly fetching `NSTextView.string` would measure a different operation. The refresh probe calls the explicit synchronous test path: its first sample reads the baseline, subsequent samples return at the identity gate. It does not measure scheduled worker turnaround, timer wakeups or idle energy.

Cold HTML submission took **92.55 ms**, and style-to-import completion took **253.28 ms**, each one sample in the isolated host. Baseline synchronous HTML style took 364.7 ms; asynchronous submission and completion are different operations, so this is not a like-for-like speedup claim. Completion includes the polling interval and is not key-to-frame latency.

Result bundles in default DerivedData (`Markify-fgujxgddrpvorxeunwaujojtnrqa/Logs/Test`):

- `Test-Markify-2026.10.05_00-53-15--0700.xcresult`: isolated Release HTML, **1 passed, 0 failed, 0 skipped**, no runtime warnings.
- `Test-Markify-2026.10.05_01-03-30--0700.xcresult`: isolated Release editor, **1 passed, 0 failed, 0 skipped**, no runtime warnings.

The earlier mixed-workload Release attempt crashed while yielding for HTML completion (`Test-Markify-2026.10.05_00-17-37--0700.xcresult`; `Markify-2026-10-05-002012.ips`). Its main-thread stack included Swift executor checks and WebKit RemoteLayerTree frames. The crash did not reproduce in the isolated HTML run; no root cause or production crash fix is claimed. Its partial timings are excluded from the after file. A subsequent isolated editor attempt stalled during polling setup and was stopped: the diagnostic used abstract `NSDocument`, whose default `fileWrapper` is unsuitable for the new native-baseline path. Supplying a concrete fixture implementation made the complete editor diagnostic pass; this is a diagnostic correction, not an application change. The sample also showed a swallowed exception thread, without identifying the earlier WebKit crash.

Table maintenance and long-line conversion improved substantially in these workloads. Whole-model parsing remains synchronous: the 5,000-paragraph edit is still about 209 ms, above the 50–100 ms interaction reference. Full style is not faster. Three samples cannot establish p95 or worst-case latency, and viewport-limited table results do not certify scrolling near the end, resizing or animated hover.

## Final required checks

- Complete Debug `MarkifyTests` target: **172 top-level tests passed, 0 failures**, **2 opt-in diagnostics skipped**, no runtime warnings. Parameterized executions produce 175 passes in the device summary. Bundle: `Test-Markify-2026.10.05_01-05-03--0700.xcresult`; log: `/private/tmp/markify-resumed-final-app.log`. The test tree confirms both `measureEditorWork()` and `measureHTMLImport()` skipped without the flag.
- `swift test --package-path MarkifyMarkdown`: **46 passed**, log `/private/tmp/markify-resumed-final-markdown.log`.
- `swift test --package-path OKFKit`: **37 passed**, log `/private/tmp/markify-resumed-final-okf.log`.
- `scripts/build-help.sh --check`: **passed**, regenerated/indexed the current 19-page help source set, log `/private/tmp/markify-resumed-final-help.log`. Concurrent user website/legal changes were preserved; generated date/index output accompanies this report.
- `git diff --check`: **passed**. Baseline JSON SHA-256 remains `0fb08df3dd138f5573c216ce1bc08ff67926ffb0359a40d6e9adff1170a6fb0f`.

Release HTML/editor build logs are `/private/tmp/markify-resumed-release-html.log` and `/private/tmp/markify-resumed-release-editor-verified.log`. Builds still emit the existing Sentry script-output and test-source Swift concurrency warnings; successful result bundles have no runtime warnings. These checks do not include UI automation or Instruments, Intel/macOS 26, battery or normally launched telemetry/update measurements. No push or deployment was performed.

## Implementation status of all fifteen findings

“Implemented” means the source change and relevant automated checks are present; the scenario measurements in the release-follow-up table remain necessary.

| ID | Status and implementation | Remaining ceiling / validation |
| --- | --- | --- |
| 1 | Partial: safe prose edits style a translated paragraph slice; inline formulas and code tokens reuse bounded caches (`a3ef7e8`, `17c6d7c`). | The full new model still parses synchronously. Block/container, Find, multiple-edit and context changes fall back to full style; cold inline math remains synchronous. |
| 2 | Implemented: widths/row lookups cached, unchanged cell presentations reused, overlays limited to viewport neighbors, footnote context invalidated, hover heights limited to affected rows (`afd433a`, `73346c8`, `483779c`, `86fd9c0`, `6ddb24e`). | Row enumeration still runs during hover; bottom scrolling, resize, navigation and memory plateau need profiling. |
| 3 | Implemented: indexed Unicode source boundaries and occupied extension ranges (`a34f52f`, `5ee257d`). | Long-line samples improve from superlinear to approximately linear in this workload; complete parsing remains synchronous. Unicode/source-offset package regressions remain covered. |
| 4 | Partial: identity-gated, coalesced off-main polling and disk baseline; five-second fallback with tolerance (`5de2453`, `56ab78b`, `f95d6bf`). | Attachment metadata, explicit test/manual refresh, prompt rereads, merge validation, Versions and native revert retain synchronous work. No slow-volume or idle-energy trace. |
| 5 | Implemented: bounded streamed image reads, 2048-pixel thumbnails, four jobs, consumer cancellation and 64-entry/64 MB caches (`4f9048a`). | Repeated-document memory plateau and decoded-resource lifetimes have not been measured. |
| 6 | Partial: async local image preparation and supported async HTML import; weak/stale completions, source/count/byte budgets; bounded worker display math (`797f9df`, `17c6d7c`, `6ddb24e`). | HTML submission still costs 92.55 ms cold on this host; previous mixed-host crash remains unexplained. File copy, paste conversion and cold inline math are synchronous. |
| 7 | Implemented: editor/table-cell observer teardown (`afd433a`, `73346c8`). | No retained-observer allocation graph or repeated-open/close plateau measurement. |
| 8 | Partial: shared in-flight bundle scans, consumer cancellation, immutable results, bounded cancellable chunk reads and 50 MB aggregate source budget (`cb78c0b`, `4913d7e`, `f95d6bf`). | Cancellation within a single parse/validation is coarse; snapshots are not a persistent cross-refresh cache. A file growing past preflight can be skipped without marking the bundle truncated. |
| 9 | Implemented: unchanged notes reused by file identity/configuration, reconciliation retained and progress publication throttled (`2565709`). | Enumeration remains a full pass; large-library event bursts, metadata reliability and snapshot-copy cost need profiling. |
| 10 | Partial: cancellation between enrichment files and enrichment outside the indexing actor (`2565709`). | A single file read/parse is not interruptible or newly bounded; sorting, result mapping and eager view construction remain profiling targets. |
| 11 | Implemented: consumer-aware bounded Mermaid queues/source/SVG/dimensions/cache, 15-second deadlines and engine recovery (`797f9df`, `a3ef7e8`). | Failure/recovery tests pass; repeated edit/export memory and helper-process CPU are unmeasured. |
| 12 | Implemented: cancellable off-main bounded 2 MB source preparation, stale-install gates, no remote preview images; image XPC startup/cancellation serialized (`fc8f1e2`, `27d865e`). | Rapid Finder navigation and provider/helper/WebKit process profiling remain outstanding. |
| 13 | Partial: off-main diagram preparation and HTML writes, bounded preflight/chunk image reads and 50 MB URI embedding budget; owned export jobs, PDF deadlines and staged destination writes (`19d7c0b`, `f95d6bf`). | Native printing has no public cancel API: one hung native job/delegate is retained until callback and can block later PDF exports until restart. Cancellation cannot write the selected destination. |
| 14 | Partial: version-keyed word/Find/outline/link data, off-main root discovery/knowledge validation and coordinated backlink writes from current disk contents (`b64b14d`, `f95d6bf`). | Inspector grouping and scroll-driven view construction still need profiles; single-document parsing is synchronous. |
| 15 | Implemented: header-only link checks, bounded streaming summaries/local reads, shared four-probe budget, pruned async caches and owned cancellation; serialized summary JSON fits the 4 MB reload cap (`348ff33`, `410930b`, `6ddb24e`). | Summary memory updates precede disk success and do not roll back on write failure; errors are reported. Multiwindow throughput and persistence stalls need scenario measurement. |

Web-link following is also fixed (`80802df`): cached Markdown spans cover inline/reference links, angle autolinks and balanced-parenthesis destinations, skip code and route through `Knowledge.follow`/NSWorkspace. Bare URLs are not model link spans. Automated checks cover extraction/follow behavior without launching a browser.

## Baseline ranked gaps

P1 means prioritize before release; P2 means follow up with targeted profiling and a scoped fix. Priority reflects frequency, resource growth and potential impact, not a claim that every document currently hangs.

| ID | Priority | Gap | Resource affected |
| --- | --- | --- | --- |
| 1 | P1 | Whole-document synchronous work on every keystroke | Responsiveness, CPU, temporary memory |
| 2 | P1 | Tables create and update all rows/cells, including offscreen ones | Responsiveness, CPU, memory |
| 3 | P1 | Source-location conversion rescans each line prefix | Responsiveness, CPU on long lines |
| 4 | P1 | Every saved document is read in full on MainActor every second | Idle energy, I/O, responsiveness |
| 5 | P1 | Remote images have no download, pixel, cache or aggregate bounds | Memory, network, CPU |
| 6 | P1 | HTML import and local image access happen synchronously in styling/drawing | Responsiveness, I/O |
| 7 | P2 | Block notification registrations outlive editor instances | Memory, notification CPU |
| 8 | P2 | Cancelled bundle scans continue, and windows duplicate bundle state | CPU, I/O, energy, memory |
| 9 | P2 | Every search refresh reads and parses every note again | CPU, I/O, energy |
| 10 | P2 | Cancelled search-result enrichment continues and shares the indexing actor | Search latency, CPU, I/O |
| 11 | P2 | Mermaid jobs accumulate obsolete work and lack explicit recovery deadlines | CPU, memory, long-running jobs |
| 12 | P2 | Quick Look reads and renders entire documents on MainActor | Finder preview responsiveness |
| 13 | P2 | Export preparation and writes still contain MainActor work | Responsiveness, temporary memory |
| 14 | P2 | Derived UI data and Knowledge validation repeat full scans and filesystem checks | CPU, responsiveness |
| 15 | P2 | Link fetches and summary persistence have incomplete resource bounds | Memory, network, responsiveness |

### 1. Whole-document work per keystroke

Evidence: `Markify/NativeEditor.swift:743` calls `style(..., incremental: true)` directly from the text-change delegate. At line 145, incremental styling copies the entire attributed storage, resets the copy's attributes over the whole source, reads a newly parsed model for the changed text, styles every span, and compares attribute runs across the entire document at line 653. Incremental here preserves unchanged live layout; it does not limit computation to the changed paragraph. Inline formulas are rebuilt at lines 212 and 375, and code highlighting is repeated for code blocks. The source remains authoritative, which a fix must preserve.

Reproduce: type at the end of a large rich document, including with Find open. Measure the synchronous delegate and the subsequent SwiftUI update separately. Proposed fix: first isolate the dominant measured component; reuse unaffected computed styles/formulas and bound attribute work to affected blocks where parser semantics permit it. Keep source offsets, undo and the existing incremental-layout tests intact. Moving AppKit text storage operations wholesale into a detached task is not a valid fix.

Acceptance: small edits must preserve existing styling and viewport behavior while latency stays within a defined interaction budget across document-size tiers; record main-thread p95 and worst cases, not only average parse time.

### 2. Table updates defeat viewport-limited work

Evidence: `NativeEditor.swift:992` calls `settleLayout` through the last table row, then creates/updates overlays for every row. Each row recomputes column widths by scanning table contents (`tableWidths`, line 929), and checks expansion by walking overlay fields (`tableRowExpanded`, line 962). `TableCellPresentation.update` at line 2445 invalidates every cell when the owner's text version changes, even if that cell's text is unchanged. Its render pass styles and lays out each cell's complete text. Table-cell context lookup at line 2568 scans the owner's model spans. These nested scans can make table maintenance superlinear. Hover animation performs document-wide table-height/overlay refreshes roughly every 16 ms for 0.28 s.

Reproduce: type in prose after a 200–500-row table; hover a row repeatedly; resize a window with several tables. Proposed fix: compute widths once per table/context, preserve unaffected cell presentations, and instantiate/update visible rows with a small prefetch margin. Establish accurate geometry without rebuilding every cell. Restrict hover animation to affected rows.

Acceptance: editing outside a table does not restyle every cell; view count and update work scale with the viewport, and scrolling/resizing still preserves correct source geometry and cell navigation.

### 3. Long lines cause repeated prefix conversion

Evidence: `MarkifyMarkdown/Sources/MarkifyMarkdown/SourceMap.swift:16` scans Unicode scalars from the beginning of a line for each cmark location. Each span needs range endpoints and sometimes additional offsets. A line with many inline nodes therefore repeatedly traverses growing prefixes, yielding quadratic conversion work for that workload. `MarkdownModel.swift:193` also tests every candidate extension against an array of occupied ranges; many math/footnote spans can add quadratic overlap checks. Extension documents may require a second cmark parse.

Reproduce: compare one long line containing repeated emphasis/links with the same constructs on short lines; separately scale inline math. Proposed fix: index UTF-8/UTF-16 boundaries or use per-line checkpoints, and exploit ordered occupied ranges for extension overlap checks. Preserve non-ASCII and source-offset tests.

Acceptance: doubling inline-node count on a long line should not quadruple conversion time; verify emoji, combining characters, CRLF and MDX offsets.

### 4. Unconditional main-thread full-file polling

Evidence: `Markify/MarkifyDocument.swift:89–101` establishes a full-data baseline and schedules a repeating one-second timer. `refresh()` reads `Data(contentsOf:)` and compares it to the retained baseline before it can return for an unchanged file. The read runs on MainActor. Each document has its own timer and recursive parent-folder FSEvents watcher; callbacks disregard event paths. There is no timer tolerance or app-visibility/energy policy. `preserveVersions` at line 183 also coordinates file writes and creates two versions synchronously during Reload/Merge.

Reproduce: leave multiple saved documents open without typing, including files on a slow/network/cloud volume. The local cached-file probe cannot represent cloud hydration or filesystem stalls. For N unchanged files of size S, the polling code requests approximately N×S bytes each second, plus comparisons and FSEvents-triggered reads; this does not imply those bytes come from physical disk each time.

Proposed fix: check file identity/metadata and event paths first, perform content reads/comparisons off MainActor, retain a coalesced fallback for missed events, and preserve save/external-change/version semantics. Make any required polling tolerant and adaptive. Profile version preservation separately because file coordination can wait on other presenters.

Acceptance: idle unchanged documents do not reread their entire contents each second; external-change, own-save, merge, Versions and file-URL-following tests still pass, including missed/coalesced events.

### 5. Remote image lifetime and size are unbounded

Evidence: `NativeEditor.swift:2366` uses a process-wide singleton with persistent URL→NSImage states and URL→base64 data URIs. There is no eviction, byte cost, pixel limit or consumer lifetime. `URLSession.shared.data(from:)` buffers the full response; image construction and base64 encoding resume on MainActor. The base64 representation is retained even for ordinary Markdown images that never need HTML embedding. Tasks have no stored handles, so closing a document or turning remote images off cannot cancel existing downloads. Repeated style/draw requests append waiting callbacks until a URL settles.

Reproduce: open/close documents containing unique high-resolution remote images; toggle remote loading during a slow transfer. Proposed fix: enforce transfer and decoded-pixel budgets, decode/downsample for display away from the main thread, bound total cache cost, create data URIs only when needed, deduplicate subscribers and cancel work without consumers. An entry-count limit alone cannot bound memory for large bitmaps.

Acceptance: memory reaches a stable bound across repeated unique-document cycles; disabled/closed-document consumers do not keep transfers alive; large responses stop before full buffering.

### 6. HTML import and local images block styling/drawing

Evidence: `NativeEditor.swift:1543–1585` imports uncached HTML with `NSAttributedString(...documentType: .html)` synchronously during style. The existing reentrancy guard explicitly acknowledges WebKit/run-loop behavior. Before looking up the HTML cache it reads local image bytes and builds base64 strings. `image(for:)` at line 1712 calls `NSImage(contentsOf:)` synchronously. `style()` clears the local image cache at line 647, so later paint/style requests reload unchanged images. File copy, TIFF→PNG paste conversion and image writes at lines 2290–2355 also happen on the UI path. The HTML cache has a 64-entry clear-all policy but no byte budget; display-math images at line 1828 accumulate by formula for the editor's lifetime, with no eviction.

Reproduce: edit an HTML block, type next to large local images, scroll into cold display math, and paste a large screenshot. Proposed fix: asynchronous file/decode preparation with explicit placeholders and version checks, file-identity-based invalidation, bounded media caches, and coalesced render completion. Investigate the supported HTML import path before choosing its executor; do not assume AppKit's HTML importer is safe in an arbitrary detached task.

Acceptance: uncached media/import work does not monopolize MainActor; unchanged images survive unrelated edits; removed formulas/images release cached resources.

### 7. Editor notification registrations are never removed

Evidence: `NativeEditor.swift:838` registers a block observer for all text-storage editing notifications, stores its token, and captures the editor weakly. There is no deinit/removal for `editingObserver`. Clip observers at line 1321 are removed on a later superview move, but have no final cleanup. A weak capture avoids retaining the editor; it does not unregister the block token. Table cells each create another `MarkdownTextView`, magnifying registration churn. [Apple: Block notification observers](https://developer.apple.com/documentation/foundation/notificationcenter/addobserver(forname:object:queue:using:)).

Proposed fix: remove tokens at the owning object's lifetime boundary and consider observing only the actual text storage, with rebinding when TextKit replaces it. Acceptance: repeated document/table creation and destruction does not grow registrations or notification-delivery cost. Measure retained blocks separately from retained editor objects; this finding does not assert that the editor itself leaks.

### 8. Bundle refresh cancellation suppresses results, not work

Evidence: `ContentView.swift:618` cancels the previous knowledge task; `Knowledge.load` at line 29 starts a detached scan and awaits its result without forwarding cancellation. `OKFBundle.load` reads and retains full source text for up to 5,000 documents and has no cancellation checks or byte budget. Validation then checks files/links across the bundle. Each document window owns its own knowledge state and watcher. FSEvents for the same bundle can therefore trigger multiple complete scans, and cancelled scans may overlap replacements. `onDisappear` at `ContentView.swift:450` stops the watcher but does not cancel knowledge, human-stamp or AI task handles.

Proposed fix: coalesce refreshes per root, propagate cancellation into scanning/validation, and share immutable bundle snapshots across windows. Add an aggregate source-size budget if large bundles must remain bounded. Acceptance: repeated bundle events leave at most one current scan per root; window closure cancels its work and does not retain obsolete snapshots.

### 9. Search fingerprints only skip Spotlight submission

Evidence: `LibrarySearch.swift:240` calls `SearchNote.read` for every note on every refresh, before comparing the content fingerprint. That method reads the entire file, parses Markdown/frontmatter, builds headings/searchable text, resolves root memberships and hashes the result. Unchanged notes avoid Spotlight writes but not reads/parses. Any root event requests a complete rescan. Progress snapshots every 50 notes lead to MainActor reconstruction of ID sets and retained-note lists (`progress`, line 449); publishing growing snapshots can add superlinear aggregate work. All subfolders are retained, including unrelated directory trees outside the configured skip list.

Proposed fix: reuse unchanged per-file results using reliable identity/metadata plus an explicit invalidation policy; retain a complete reconciliation path for missed events. Reduce growing-snapshot copies/publication frequency and avoid enumerating known irrelevant trees. Acceptance: changing one note in a large library normally reads/parses that note, with bounded UI progress work and correct deletion/configuration handling.

### 10. Obsolete search enrichment occupies the worker

Evidence: `SearchSession` cancels its task and rejects stale generations, but `SpotlightWorker.matches` at `LibrarySearch.swift:277` performs a synchronous `compactMap` of all selected notes with no cancellation checks. It reads each file, scans matches, and may reparse headings. Because indexing and enrichment use the same actor, an old enrichment batch or a synchronous part of a scan can delay the new search. Spotlight result collection, sorting and note mapping in `LibrarySearchView.swift:40–59` run on MainActor. Results/browse lists use eager `VStack` containers.

Proposed fix: check cancellation between files, bound enrichment to visible/paged results, and prevent old enrichment from monopolizing indexing/search service work. Profile result sorting and view construction before moving them. Acceptance: rapid query changes stop obsolete file work promptly and the latest query is not queued behind a complete old batch.

### 11. Mermaid queue can retain obsolete renders

Evidence: `Mermaid.swift:16–49` retains pending raster/SVG jobs and per-key callbacks. Every diagram edit creates a new key. There is no stale-job cancellation or pending-byte/count budget; the approximate 64-state cache trim only drops settled renders. Multiple requests for a rendering key append callbacks, and completion invokes each directly, causing repeated whole-document restyles. One shared WebView serializes work, SVG jobs take priority, and JavaScript/snapshot operations have no application deadline. Provisional navigation failure and Web content process termination have no handlers that settle continuations and recover the renderer. Rendered bitmap dimensions are not capped before resizing/snapshotting the view.

Proposed fix: coalesce consumers by editor/version, discard obsolete queued work, bound snapshot dimensions/cache cost, and settle/recover pending jobs on failure or deadline. Keep one WebView where feasible. Acceptance: quickly editing a large diagram does not require rendering all intermediate versions; engine failure cannot leave exports waiting indefinitely.

### 12. Quick Look's async task still renders on MainActor

Evidence: `QuickLook/PreviewProvider.swift:75` reads source synchronously in an actor-isolated async method, parses it for Mermaid, then synchronously renders Markdown HTML and math on MainActor. The image helper separately has good limits (2 MB source, 128 image destinations, 50 MB aggregate image data), but those do not bound the provider's source read/render. Preparation jobs have no tracked cancellation/version gate for a superseded preview. Remote HTTPS images in the resulting WebView can also load outside the helper's local-image budget.

Proposed fix: bounded source reads and pure parse/render work off MainActor, then version-checked WebView installation. Acceptance: navigating previews rapidly avoids stale installation and long main-thread rendering; verify both the provider and helper processes.

### 13. Export still has synchronous preparation/write tails

Evidence: `Export.swift:46` creates a full Markdown model on MainActor before offloading page generation; even documents without diagrams pay this cost. `writeHTML` at line 76 resumes on MainActor and atomically writes the complete rendered page. Rendering embeds local images, so output can be much larger than source. `MarkdownPage.imageSource` checks its 25 MB per-image limit only after `Data(contentsOf:)` has read the whole file, and has no aggregate embedding budget or reuse for repeated destinations. `PDFPrinter` waits for load/print continuations without application deadlines/cancellation or a Web content termination handler. Export tasks in `ContentView.swift:1417` have no retained handles.

Proposed fix: scan diagram inputs and write completed output away from MainActor; enforce image limits before/during reads, plus an aggregate export policy; add job ownership and deterministic continuation cleanup. Acceptance: exporting while typing remains responsive, output budgets are explicit, and closing/cancelling/failing a job releases its WebView and pending work.

### 14. View recomputation repeats source and filesystem work

Evidence: `ContentView.swift:140` splits the entire document to count words. Find matches at line 132 are regenerated when read, including for current-match/count/navigation consumers. With the inspector open, body construction re-extracts headings/links on changes including scroll-driven reading state (`lines 228, 429`). `DocumentInspector.body` at `Inspector.swift:84` regroups link entries even on Contents. `Knowledge.issues` (`Knowledge.swift:36`, called from `ContentView.swift:558`) validates and checks link existence on MainActor as the sidebar builds. Bundle-root discovery (`Knowledge.swift:21`, `OKFKit/Bundle.swift:104`) walks ancestors and reads `index.md` synchronously. Rename/move retargeting (`ContentView.swift:1658`) transforms and writes backlink documents on MainActor.

Proposed fix: cache derived values by text/model version and relevant options; separate source-derived inspector data from scroll-derived selection; move filesystem validation/discovery/batch edits to cancellable worker jobs. Acceptance: scrolling/selecting/AI streaming does not repeatedly rescan unchanged text or hit the filesystem, and batch retargeting preserves failure reporting and edit consistency.

### 15. Link-related resource limits are incomplete

Evidence: `LinkHealth.swift:157` uses `session.data` for its fallback GET with a one-byte Range request, but a server can ignore Range and return an entire body. Four probes are limited per `check` invocation, not globally across simultaneous windows; cache entries remain on disk indefinitely despite 24-hour freshness. `LinksPanel.swift:200` rejects web content above 1 MB only after buffering it fully. Local summaries read and process complete files before limiting model input to 20,000 characters. Summaries have no stored cancellation handles, and `LinkSummaryStore.save` at line 123 encodes/writes the whole unbounded JSON store synchronously on MainActor. Initial summary/check cache reads/decodes also run there.

Proposed fix: enforce stream limits as bytes arrive, coordinate a global probe budget, cancel summaries without consumers, and prune/bound persistent caches with serialization/writes off MainActor. Acceptance: oversized/range-ignoring responses stop early, many windows respect one concurrency budget, and growing summary history does not stall interactions.

## Existing safeguards worth preserving

- Markdown models are cached by text version; drawing uses sorted decoration anchors and binary search, with decorations attached to layout fragments.
- Incremental attribute application avoids invalidating unchanged TextKit layout; current source/undo/viewport tests are valuable constraints on optimization.
- Search scan/parsing lives on a worker actor; full page export, merge computation, local link checks and summary text extraction already have background paths.
- Search enumeration checks cancellation between files, Spotlight submissions are batched, remote link checks deduplicate in-flight URLs and cache freshness, and remote image arrivals coalesce restyles for an editor.
- Quick Look's image helper bounds reads before buffering. Public URL opening streams responses with a 10 MB cap, and report inbox reads have a 10 MiB bound. These patterns can inform other resource limits without adding a new framework.
- The table hover animation terminates after 0.28 s and respects Reduce Motion. There is no evidence here of a perpetual animation timer.

## Verification gaps and release follow-up

Current guards allow up to 2 seconds for a full style pass (`EditorFixtureTests.swift:199`) and 1 second for a model parse (`MarkdownModelTests.swift:196`). Those detect pathological regressions; they do not establish interactive typing or scrolling performance. The style guard uses a plain `NSTextView`, so it does not cover actual table overlays, image/HTML imports or the whole editor delegate-to-frame path. The diagnostic introduced here intentionally reports observations without blessing a loose threshold.

Before asserting that the release is efficient, capture the following with Instruments on an optimized, normally launched build. Prefer Time Profiler/Hangs for synchronous stacks, Allocations/Leaks for lifetimes, and available energy/wakeup tooling for idle behavior. Include WebKit/helper processes where applicable.

| Scenario | Evidence needed |
| --- | --- |
| Small/medium/large documents in both lenses, with Find/sidebar/inspector open and closed | Key-to-frame and scroll latency; main-thread p95/worst work; source and viewport correctness |
| Tables with 50/200/500+ rows, near top and end; hover and resize | Number of instantiated cells, width/layout work, animation hitches and peak memory |
| Long single lines, many math/footnote/MDX constructs and long code blocks | Parse/style scaling and worst main-thread interval |
| 1/10/20 saved windows idle for 5 minutes, then backgrounded | CPU, wakeups, bytes requested/read, timer behavior and memory plateau |
| Slow/network/cloud document files, externally edited while local edits/Versions exist | Responsiveness during reads/coordination, prompt correctness, own-save and merge behavior |
| Repeated open/close and edits of large local/remote images, HTML, math and Mermaid | Retained editor/observer/task/cache objects, decoded pixels/bytes, cancellations and renderer recovery |
| Large library and OKF bundle, many windows, event bursts and rapid searches | Duplicate/obsolete scans, actor wait time, bytes read, progress update cost and results latency |
| Large HTML/PDF exports, failed/hung renderer and repeated export cancellation | Main-thread tails, aggregate memory, bounded waits and resource release |
| Rapid Quick Look navigation and oversized previews | Provider/helper/WebKit process time, memory and stale-job cleanup |
| Apple Intelligence stream, stop, retry, window closure and many link summaries | UI recomputation cost, obsolete task lifetime, model/network work and cache persistence stalls |
| Normal release startup/idle with Sentry and Sparkle enabled | Telemetry/update overhead; the test host suppresses both, so these diagnostics do not measure them |
| Supported macOS 26 and Intel hardware, battery/Low Power Mode | Verify responsiveness and energy behavior beyond this single M1 Max/macOS 27 host |

No battery-power, whole-app idle trace, leak graph, Intel run or macOS 26 run has been established by these microbenchmarks. Findings about missing bounds and cancellation are supported by source; exact retained-memory growth, energy savings, slow-volume stalls and renderer failure behavior still need the scenario measurements above. Fixes should follow the ranked list, with before/after evidence and existing correctness tests retained.
