# Performance handoff — 5 October 2026

This historical handoff was resumed and completed on 5 October. See the completion record below and PERFORMANCE_AUDIT.md; the pending steps described in the original handoff are no longer outstanding.

Original task: finish the performance audit and web-link fixes, preserve pending edits, stay on **optimize**, commit each coherent verified step, regenerate help, run the full relevant tests, and record measured Release audit results. Do not push or deploy. Read AGENTS.md and PERFORMANCE_AUDIT.md. Ponytail full remains active; no subagents are authorized. Use default Xcode DerivedData for Markify, never `-derivedDataPath`. Xcode/Swift caches have needed tool escalation. Git add/commit is authorized.

## Current state

Branch: `optimize`. Latest HEAD: **f20421e**. No test/build command remains running: the final tool session 82736 exited 0, but selected **zero tests** (details below). Do not infer test success from that exit.

Four verified implementation/documentation steps were committed this session:

- **f95d6bf** — Own knowledge and export jobs and confirm document baselines off main. Reviewed the pending Knowledge, ContentView, Export and MarkifyDocument changes, then tested MarkifyTests, ExportTests and InspectorTests. Includes coordinated current-disk backlink updates, async root discovery/baseline, cancellation forwarding, PDF deadlines/staged destination writing and owned tasks.
- **27d865e** — Cancel Quick Look image requests and serialize connection startup. Cancellation previously could invalidate the XPC connection between continuation attachment and `resume()`. Interface setup and resume now occur inside Request.attach's lock, before cancellation can settle/invalidate. QuickLookTests passed after this change.
- **6ddb24e** — Bound serialized summary and HTML caches and refresh table footnote context. Summary JSON byte accounting happens in its writer actor, including escaped keys/fingerprints; persisted data fits the 4 MB reload cap. HTML budget now includes pending/failed keys and rejects stale width/accent completions. Table cells invalidate footnote tooltips when referenced definitions change and compare bundle root. Shared binary-search contextSpans avoids adding a full-span scan per ordinary table cell. Regression tests cover changed footnote tooltips and very large escaped summary keys.
- **f20421e** — Document preview and media limits and regenerate help. Preserved the user's getting-started version-history edits. Help now describes Quick Look's 2 MB source cap/no remote images, editor 10 MB/2048-pixel image limits, summary limits, export embedding budgets, cancellation and hung native PDF recovery.

## Pending files — preserve

`git status --short` at handoff:

- `Markify.xcodeproj/project.pbxproj` — pre-existing user version bump to 2.2.0; leave unstaged/uncommitted unless separately requested.
- `MarkifyTests/ReportTests.swift` — pre-existing user prompt-test timing/diagnostic edits; leave unstaged/uncommitted.
- `MarkifyTests/PerformanceAuditTests.swift` — our pending diagnostic corrections, described below. Compile succeeded, but the final split diagnostics have not been run because the individual method filter selected zero tests.
- `Markify/Resources/Markify.help/Contents/Resources/en.lproj/Markify.helpindex` — binary changes on every generation; harmless regeneration output.
- `docs/help/{export,getting-started,images-and-links}.html`, `docs/sitemap.xml` — generated date metadata changed when `scripts/build-help.sh --check` ran after committing the help sources. Preserve and include with the final documentation commit if appropriate.

All prior pending knowledge/export/document/Quick Look implementation is now committed. No partial staging remains.

## Verified tests and help

- `/private/tmp/markify-resume-next.log`: MarkifyTests, ExportTests, InspectorTests passed, exit 0 (pending baseline refinement was included).
- `/private/tmp/markify-quicklook-final.log`: QuickLookTests passed, exit 0.
- `/private/tmp/markify-final-cache-verified.log`: PerformanceFixTests, MarkifyTests, OverlayLayoutTests passed, exit 0. Result bundle `Test-Markify-2026.10.05_00-13-51--0700.xcresult`: **83 passed, zero failures**; one runtime QoS warning in the layout test.
- `/private/tmp/markify-final-app-tests.log`: complete **MarkifyTests** target passed, exit 0. Result bundle `Test-Markify-2026.10.05_00-14-51--0700.xcresult`: **172 tests passed, one opt-in audit skipped**, zero failures, no runtime warnings. Parameterized executions yield 175 passes in the per-device summary; 172 is the top-level passedTests count.
- `/private/tmp/markify-final-markdown.log`: **46 Markdown tests passed**.
- `/private/tmp/markify-final-okf.log`: **37 OKF tests passed**.
- `/private/tmp/markify-final-help.log`: regenerated all 17 pages and index successfully.
- `/private/tmp/markify-final-help-check.log`: Help Book freshness check passed after the documentation commit. It changed generated website dates and the binary help index as noted above.
- `git diff --check` passed before the help commit; rerun at the end.

Default result directory:
`/Users/spaquet/Library/Developer/Xcode/DerivedData/Markify-fgujxgddrpvorxeunwaujojtnrqa/Logs/Test/`

`xcrun xcresulttool get test-results summary --path <bundle>` may need escalation because it indexes the result bundle on first read.

## Release audit: failed attempt, useful partial observations

The first final Release invocation used the entire PerformanceAuditTests suite with an updated async HTML-completion wait. It **crashed**, exit **65**, while yielding for the HTML import after all prose/table/parser measurements had been recorded. Do not claim the Release audit passed.

- Log: `/private/tmp/markify-final-release-audit.log`.
- Result bundle: `Test-Markify-2026.10.05_00-17-37--0700.xcresult`, **one failed test**, failure `Crash: Markify at static MarkifyApp.$main()`.
- Crash: `/Users/spaquet/Library/Logs/DiagnosticReports/Markify-2026-10-05-002012.ips`.
- Observed stack: **EXC_BAD_ACCESS/SIGSEGV** on `com.apple.main-thread`, `swift_getObjectType` → Swift executor checks → **WebKit RemoteLayerTreePropertyApplier/RemoteLayerTreeHost/RemoteLayerTreeDrawingAreaProxy**, then the normal NSApplication loop. This is not an established root cause and does not prove an app or OS bug. No importer completion frame appears in the crashed stack.
- The crash only appeared after the long workload sequence began asynchronously yielding. Existing Debug HTML regression tests passed. Isolate the Release HTML workload before deciding what to fix or document.
- Partial raw JSON: `/private/tmp/markify-performance-audit.json`. Copied for preservation to **`/private/tmp/markify-performance-audit-partial-2026-10-05.json`**. This contains completed synchronous workloads and HTML submission only, not completion/polling. Baseline `performance-audit-results.json` remains unchanged. No final after-results file has been saved in the repo yet.

Partial medians (diagnostic observations from the failed run; **not final certified results**):

| Workload | Baseline | Partial after |
| --- | ---: | ---: |
| 5,000 rich paragraphs, edit + incremental style | 2,370.0 ms | 215.46 ms |
| 500-row table, edit + style + overlays | 7,418.8 ms | 36.74 ms |
| 500-row table, unchanged overlays | 5,145.6 ms | 2.92 ms |
| 500-row table, initial overlays (one sample) | 9,509.3 ms | 70.87 ms |
| 1,500 inline groups on one line, parse | 1,293.6 ms | 26.94 ms |
| 500 inline groups on one line, parse | 149.8 ms | 9.16 ms |

Three medians do not establish p95, memory plateau, battery/idle performance or complete key-to-frame latency. Full-model parsing remains synchronous; 5,000-paragraph parse alone was about 166.69 ms, so even the improved large-document edit is above a 100 ms interaction reference.

## Pending diagnostic changes and next commands

`MarkifyTests/PerformanceAuditTests.swift` now separates:

1. `measureEditorWork()` — synchronous prose/parser/table/polling benchmark, no HTML import. Retains original `word-count` comparison and adds cached cold/warm measurements.
2. `measureHTMLImport()` — isolated async cold HTML submission and actual completion measurement, writing `/private/tmp/markify-performance-html-audit.json`. It waits up to ten seconds and calls stopObserving afterward.

Both use the original `MARKIFY_PERFORMANCE_AUDIT=1` flag. Run them in **separate Xcode invocations/test hosts** so WebKit completion is not mixed with accumulated table/prose work. The original entire-suite command now would launch both tests and defeats the intended isolation.

Important diagnostic correction: the first failed run's cached word-count probes called `view.string` inside every measurement. The NSTextView getter contaminated warm timing (about 21 ms at 365 KB). ContentView uses its String binding. Current pending code captures `let currentSource = view.string` outside the cached probes, so they measure actual cache access instead of repeated editor-string extraction. Verify rather than reporting the previous warm timing as cache performance.

The attempted isolated HTML command used:
`-only-testing:MarkifyTests/PerformanceAuditTests/measureHTMLImport`
It exited 0 but **selected zero tests**, confirmed by xcresult summary (totalTestCount 0, result unknown). No `/private/tmp/markify-performance-html-audit.json` exists. Do not count it as verified.

**Use Swift Testing method identifiers with parentheses** (or inspect `xcodebuild -enumerate-tests` first):

```sh
TEST_RUNNER_MARKIFY_PERFORMANCE_AUDIT=1 xcodebuild -quiet \
  -project Markify.xcodeproj -scheme Markify -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:'MarkifyTests/PerformanceAuditTests/measureHTMLImport()' \
  -parallel-testing-enabled NO test CODE_SIGNING_ALLOWED=NO ENABLE_TESTABILITY=YES \
  > /private/tmp/markify-final-release-html-selected.log 2>&1
```

Then run the same command selecting `measureEditorWork()` and logging to `/private/tmp/markify-final-release-editor-selected.log`. **Confirm nonzero selected test counts and pass status.** If parentheses still do not select, enumerate tests and use exact identifiers; do not blindly retry the entire suite.

The zero-selection run compiled the latest test source but did not execute it. Its result bundle is `Test-Markify-2026.10.05_00-23-26--0700.xcresult`. Tool session 82736 is finished. No running commands to resume.

## Finish after diagnostics

- Resolve or honestly record the isolated Release HTML crash if it reproduces. Preserve meaningful Debug HTML tests and supported asynchronous importer behavior.
- Save successful measured samples separately, e.g. `performance-audit-results-after.json` (baseline untouched). Combine isolated HTML results only if actually produced and passed.
- Update PERFORMANCE_AUDIT.md with actual before/after medians, all fifteen findings' implementation status, and remaining ceilings. The report currently still describes the original baseline; it has not been updated this session.
- Commit the verified diagnostic/report step on optimize, including generated date changes if appropriate.
- Because the diagnostic source changed after the full Debug suite, run the relevant diagnostic selection/skip checks; broaden app tests if production fixes are required. Full app and packages already passed current production source.
- Final `git diff --check`, status and commits. Leave project version bump and ReportTests user edits untouched. Do not push or deploy.

## Remaining honest limitations / review targets

- **PDF native ceiling:** no public NSPrintOperation cancel method; do not call cleanUpOperation. One native job/delegate remains retained until callback after timeout/cancellation. Permanently hung native printing can reject later PDF exports until restart. Successful completion preserves temporary output until the outer atomic copy; cancellation cannot write the chosen destination.
- Full Markdown parse remains synchronous; safe paragraph styling reduces attribute work, while block/container/Find/multi-edit/context changes fall back to full styling. Large rich prose still has measurable latency.
- Table overlays are viewport bounded and unchanged cells/widths reused. Hover changes only affected heights, but row enumeration/overlay refresh still happens each animation frame. Profile actual bottom-of-table scrolling/resize/hover before further changes.
- Explicit refresh() is now used by tests/audit, while production watchers/timers call scheduleRefresh(). Manual prompt rereads, merge validation, preserveVersions and native revert retain synchronous I/O. Initial attachment metadata lookup remains on MainActor. Preserve data-loss/conflict semantics in any follow-up.
- Image file paste/copy and TIFF conversion remain synchronous; uncached inline math remains synchronous and its vector output dimensions were not newly bounded this session. Display math has source/pixel/cache/job bounds from prior work.
- HTML imports have weak completions, bounded counts/bytes and stale gates; current Release crash needs diagnosis, not attribution by guess.
- Bundle scans cancel between documents and bound chunk reads. A file growing beyond its budget after metadata preflight can be skipped without setting truncated. Cancellation inside a single parse/validation remains coarse.
- Search sorting/view mapping and inspector grouping remain potential profile targets; no measured evidence warrants new abstractions.
- Summary JSON now fits its reload cap, but save updates memory before disk success and does not roll back on I/O failure; errors are reported.
- No Instruments trace, memory-plateau/battery/whole-app idle study, normally launched telemetry/update profiling, Intel validation or macOS 26 run is established. Host is M1 Max/macOS 27.2/Xcode 27.1. Do not certify these.
- Web-link fix is already committed: cached Markdown spans cover inline/reference/angle autolinks/balanced-parenthesis URLs, skip code and route through Knowledge.follow/NSWorkspace. Bare URLs are not model link spans. Full tests include extraction/follow behavior but do not launch a real browser as a test.

## Committed work

Read the commits for implementation details; this is a map, not a certification that every gap is closed:

| Commit | Change |
| --- | --- |
| `02ee07c` | Audit baseline and opt-in diagnostics |
| `80802df` | Follow rendered/reference/autolinks through cached Markdown spans |
| `a34f52f` | Index Unicode boundaries for source-offset conversion |
| `afd433a` | Remove editor observers; cache table widths and row lookups |
| `5ee257d` | Index occupied ranges during extension recognition |
| `73346c8` | Preserve unchanged cell rendering; tear down observers |
| `5de2453` | Bounded file reads and inode/size/nanosecond identity stamps |
| `56ab78b` | Coalesced off-main document polling, identity gate |
| `483779c` | Large-table overlays limited to visible rows and neighbors |
| `348ff33` | Stop web checks at headers; stream bounded response bodies |
| `19d7c0b` | Off-main export preparation/writes; image embedding budgets |
| `2565709` | Reuse unchanged search notes; enrichment outside indexing actor |
| `cb78c0b` | Shared bundle scans and consumer cancellation |
| `4f9048a` | Bounded remote images with editor subscriptions and cleanup |
| `797f9df` | Async local media/HTML; bounded diagram renderer |
| `fc8f1e2` | Bounded, cancellable off-main Quick Look preparation |
| `a3ef7e8` | Safe paragraph-only styling and renderer recovery tests |
| `b64b14d` | Cached source-derived UI values; off-main knowledge validation |
| `dbaeec9` | Reject nonregular files after opening bounded read handles |
| `410930b` | Shared four-probe budget, async/pruned persistence, owned summary cancellation |
| `86fd9c0` | Table hover updates restricted to affected row heights; stale overlay indices filtered |
| `4913d7e` | Bounded chunk reads for OKF bundle files and root indexes |
| `17c6d7c` | Cached inline formulas/code tokens; asynchronous bounded display-math preparation |

Links use `MarkdownTextView.link(at:)` over the model rather than an OKF regex. Reference links, angle autolinks and URLs with balanced parentheses are covered; links in code are skipped. Bare URLs currently are not link spans in the model.

Safe prose styling still parses the new complete model once, then styles a translated paragraph slice using a scratch text view. Block/container edits, Find, multiple edits or context changes fall back to full styling. Source text and UTF-16 selection coordinates remain authoritative.

Media budgets: remote/local image reads 10 MB, thumbnails max dimension 2048, caches max 64 entries / 64 MB; four image jobs concurrently. HTML uses native asynchronous `NSAttributedString.loadFromHTML`, timeout five seconds, two imports per editor, bounded source/cache, stale completion gates. Mermaid has bounded queues/source/SVG/dimensions/cache, 15-second load/render deadlines and recovery. Quick Look source is bounded at 2 MB and disables remote preview images. Export embeds bounded images with a 50 MB aggregate URI budget and falls back to paths.

Latest math work: display drawing only requests/reads worker results, four jobs per editor. Source limit 8,192 UTF-8 bytes; raster metrics max 2,048 points per dimension / one million square points before allocating at 2x scale; settled image cache max 64 entries / estimated 64 MB. Deleted formulas, theme changes and teardown cancel/prune cache entries. Inline formulas reuse up to 256 cached values; code tokens up to 32 blocks / roughly 2 MB source. Inline formulas still prepare synchronously when uncached; only display raster preparation moved off-main. Async math reuse/oversized-source test is committed and passed. There are no final memory-plateau measurements yet.

## Completion record — 5 October 2026

- `e09a13b` commits the isolated diagnostics, concrete NSDocument fixture and successful `performance-audit-results-after.json`; the baseline is unchanged.
- Isolated Release HTML and editor diagnostics each passed exactly one test, with zero failures/skips/runtime warnings. The prior mixed-host WebKit crash did not reproduce; no root cause or production crash fix is claimed. The editor fixture stall was resolved.
- Final Debug app target: 172 passed, two diagnostic skips, zero failures/runtime warnings. Markdown: 46 passed. OKF: 37 passed. Help freshness and diff whitespace checks passed.
- PERFORMANCE_AUDIT.md now records measured comparisons, all fifteen implementation statuses, precise checks and remaining performance/measurement ceilings.
- The pending project 2.2.0 version changes and ReportTests edits remain uncommitted. Concurrent user website/legal work was preserved. No push, deployment or agents.
