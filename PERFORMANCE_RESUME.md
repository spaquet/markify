# Resume prompt

Continue the Markify performance work in `/Users/spaquet/Sites/Markify`.

Original instruction: fix the performance gaps in `PERFORMANCE_AUDIT.md`, plus the regression where web links do not open. Commit each coherent, verified step. Keep all work on the current branch, **`optimize`**. Do not push or deploy. Read `AGENTS.md` and the audit before proceeding. Ponytail full is active: prefer minimal fixes in shared code, native APIs, and meaningful regression checks. Do not spawn agents without authorization.

The previous session stopped for a context handoff, not because the task was finished. Latest implementation HEAD before this handoff is **`17c6d7c`**. Many improvements are committed, but the full audit has not been closed or measured after the changes. Do not claim it is complete. This file was updated after the second implementation session; the pending work below supersedes the original handoff.

## Start here

1. Inspect `git status`, current diff and recent commits. Preserve pending and pre-existing edits.
2. Review and rerun the pending knowledge/export/document/Quick Look changes described below. Summary/link-check work is now tested and committed.
3. Verify and commit this step, then address remaining audit work, regenerate help, run the complete relevant tests and repeat the Release audit. Record actual results and remaining limitations.

```sh
xcodebuild -quiet -project Markify.xcodeproj -scheme Markify \
  -only-testing:MarkifyTests/MarkifyTests \
  -only-testing:MarkifyTests/ExportTests \
  -only-testing:MarkifyTests/InspectorTests \
  -parallel-testing-enabled NO test CODE_SIGNING_ALLOWED=NO \
  > /private/tmp/markify-resume-next.log 2>&1
```

Use default Xcode DerivedData for Markify; **never add `-derivedDataPath`**. Sandbox restrictions on Xcode/Swift cache directories have required escalated execution. Request tool escalation when necessary, rather than changing build locations. Git add/commit is authorized. Check for leftover test processes before starting another run.

## Pending changes and ownership

Uncommitted implementation (preserve it):

- `Markify/Knowledge.swift`: `Knowledge.root` is now async, captures the granted folder on MainActor and runs ancestry/index/concept work in a cancellation-forwarded detached task. New nonisolated `retargetFiles` reads current disk contents under `NSFileCoordinator` before changing links; bounded 20 MB reads and cancellation checks prevent writing stale bundle snapshots.
- `Markify/ContentView.swift`: awaits root discovery within the owned knowledge task; owns/cancels backlink and export jobs on disappearance; applies own-link changes only if editor source still equals the pre-alert snapshot; reports backlink failures after worker completion. Export task cancels the previous export and suppresses cancellation alerts.
- `Markify/Export.swift`: forwards cancellation into detached scan/render/HTML-write tasks. PDFPrinter bounds load wait at 30 s and native print wait at 60 s, handles WebKit termination/failure, settles continuations once, and prints to a temporary file before off-main atomic destination writing. See the native-print limitation below.
- `Markify/MarkifyDocument.swift`: establishes native document bytes without a synchronous disk read, confirms initial baseline in a worker, uses an initial identity stamp to distinguish existing unsaved differences from an external change during attachment. Automatic reads now use FileRead with a 50 MB limit. Latest initial-stamp refinement was made while the last build was in progress; rerun it explicitly.
- `QuickLook/PreviewImageClient.swift`: cancellation forwards to the XPC image request and invalidates its connection; Request can be canceled before its continuation attaches and remembers its completion to prevent double resumes.
- `MarkifyTests/MarkifyTests.swift`: async knowledge-root tests and a coordinated backlink regression verifying newer disk text survives.
- `MarkifyTests/ExportTests.swift`: canceled PDF job preserves the existing destination; repeated failure cannot resume twice.

Review before committing:

- **PDF native ceiling:** NSPrintOperation exposes no public cancel method; its SDK explicitly says not to call `cleanUpOperation` yourself. `PDFPrinter.activePrint` retains at most one native job/delegate until its callback, including after our timeout/cancel. This prevents repeated abandoned jobs and dangling delegates, but a permanently hung native print may retain one job and reject subsequent PDFs until restart. Record this limitation honestly. Callback cleanup removes canceled temporary output. Verify successful output is not removed before the outer copy (the successful `completed` flag protects it).
- PDF cancellation test and actual pagination passed before the final cancellation-forwarding edits; rerun current source. Check cancellation before/after continuations and output staging, and avoid overwriting existing files on cancellation.
- **XPC race:** request attach and connection startup are separate; cancellation can invalidate a connection between them. Review startup serialization or confirm safe API behavior. Cancellation currently applies to `images`, not the user-initiated `openMarkdown` request. Request's generic optional result handles an optional nil value via `.some(value)`.
- **Document baseline:** native fallback comes from `document.fileWrapper`, not the potentially stale SwiftUI binding. Initial metadata lookup still runs on MainActor. Explicit `refresh()` and prompt rereads/version preservation/merge validation remain synchronous. Preserve Reload/Merge/Versions/own-save behavior; do not silently replace a merge baseline when the file changes during attachment.
- **Knowledge writes:** current disk text is coordinated, but review interaction with open documents/unsaved changes and failure/cancellation reporting. A new batch cancels the prior batch between files. No stale source snapshot is written.
- **Summary cache follow-up:** the committed async save updates memory before disk success; write errors are reported, but no rollback is implemented. Entries are bounded by count/text and reads by total JSON bytes; unusually long keys/fingerprints could still make the written file exceed its reload cap. Consider a serialized byte budget if warranted.

Stage and commit coherent tested steps. `ContentView.swift` contains both knowledge and export changes, so use partial staging to keep separate commits if useful. No partial staging is pending at this handoff: the math test hunk was staged and committed, while the knowledge hunk remains unstaged.

Pre-existing user edits that must be preserved:

- `Markify.xcodeproj/project.pbxproj`
- `MarkifyTests/ReportTests.swift`
- `help/getting-started.md`
- Generated `Markify.help` getting-started page and help index
- `docs/help/{export,formatting,getting-started}.html`, `docs/llms-full.txt`, `docs/sitemap.xml`

There were also pre-existing `MarkifyDocument.swift` and `MarkifyTests.swift` refresh changes, incorporated into the committed refresh step. Do not restore those files to an older version. Original audit files and diagnostics were committed as baseline.

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

## Remaining work / review targets

Use the fifteen findings in the audit as the source of truth. Known incomplete areas:

- **Styling:** measure paragraph fast path in Release. Full parse remains synchronous; formula/code caches are now implemented. Review reference/neighbor dependencies and preserve full-style equivalence.
- **Tables:** hover only modifies affected heights, but row enumeration/overlay refresh still runs each frame. Profile remaining cost. Unchanged cell invalidation includes reference definitions but needs review for footnote/other owner context changes.
- **Document refresh:** review/finish pending async initial baseline. Explicit manual refresh, prompt rereads, version preservation and merge validation still have synchronous I/O. Preserve conflict/data-loss semantics and existing tests when moving these tails.
- **Media:** paste file copying and TIFF conversion remain synchronous; uncached inline math remains synchronous. Review async HTML stale keys/failure-cache byte accounting and lifetime across closed editors. Inline-cache input bound is present, but output dimensions/vector cost deserve review.
- **Bundle scans:** bounded growing-file and root-index reads are now committed (root index max 2 MB). Review cancellation within individual document validation and truncated reporting if a file exceeds the budget after preflight.
- **Search:** unchanged notes are reused and enrichment no longer blocks the indexing actor; main-thread result sorting/mapping and eager enrichment may remain. Do not add complexity without evidence.
- **Mermaid:** review cache/consumer cleanup and failure retry behavior. Recovery and obsolete-queue regression tests passed.
- **Quick Look:** pending XPC cancellation needs startup-race review and final verification.
- **Export:** pending deadlines/cancellation/task ownership are implemented; verify and commit them, with the native-print ceiling documented.
- **Derived UI / Knowledge:** pending off-main root discovery and coordinated backlink writes passed focused tests; finish review/commit. Inspector grouping still rebuilds in body.
- **Links:** globally bounded queue/persistence/summary cancellation are now tested and committed; review final persistent byte limits if necessary.

## Validation so far

Latest session test results (serial Xcode suites, successful exit):

- `/private/tmp/markify-summary-fixes.log`: MarkifyTests, OpenURLTests, InspectorTests; concurrent callers peak at exactly four probes and unchanged URLs do not fetch again; concurrent summary saves survive reload. Initial actor-isolation compile failures were corrected (`nonisolated lifetime`, `@MainActor` local queue helper).
- `/private/tmp/markify-hover-fixes.log`: OverlayLayoutTests, IncrementalStyleTests, PerformanceFixTests passed.
- `/private/tmp/markify-math-fixes.log`: MarkifyTests, InlineMathTests, EditorFixtureTests passed.
- `/private/tmp/markify-knowledge-fixes.log`: MarkifyTests and InspectorTests passed, including current-disk backlink preservation.
- `/private/tmp/markify-export-lifetime.log`: ExportTests, MarkifyTests, InlineMathTests, EditorFixtureTests passed; includes native pagination and canceled-destination preservation. Later forwarding changes need rerun.
- `/private/tmp/markify-lifetimes-resume.log`: ExportTests and MarkifyTests passed (6.474 s test session); Quick Look request changes compiled. The final initial-stamp baseline refinement occurred during this build, so rerun explicitly rather than assuming which source revision it compiled.
- `/private/tmp/markify-package-resume.log`: all 46 Markdown package tests passed with hardened FileRead.
- `/private/tmp/markify-okf-resume.log`: all 37 OKF tests passed with bounded reads.

Last Xcode process returned exit 0; no test command remains intentionally running. Tool session 6918 is already closed. No interactive git staging session remains open.

The previous handoff's `/private/tmp/markify-paragraph-fixes.log` also passed IncrementalStyleTests, PerformanceFixTests, MermaidTests, and MarkifyTests, including paragraph/full-style equivalence.

Earlier successful focused logs: `/private/tmp/markify-{table,refresh,viewport,io,search,media,renderer}-fixes.log`. They cover observer teardown, overlay layout, refresh conflicts/versions, bounded URL responses, export, search, remote/local media and renderer recovery.

Async media tests retain source/pixel checks; layout bitmap helpers ensure layout before capturing, and table thumbnails use their cell reading's prepared images.

No full final app-test run, post-change Release audit, Instruments run, Intel validation, idle/battery measurements or memory-plateau certification has happened. Baseline timing JSON remains unchanged.

## Finish and measure

- Update appropriate `help/*.md` for user-visible limits/fallbacks/Quick Look remote-image behavior. Preserve existing getting-started edits. Run `scripts/build-help.sh`; commit sources and generated Help Book/docs together.
- Run `swift test --package-path MarkifyMarkdown`, `swift test --package-path OKFKit`, all `MarkifyTests`, and `git diff --check`. Include golden styling, pixel/layout, refresh, search, export/PDF and renderer checks. Broaden testing only for changes or unresolved failures.
- Repeat the opt-in Release audit:

```sh
TEST_RUNNER_MARKIFY_PERFORMANCE_AUDIT=1 xcodebuild -quiet \
  -project Markify.xcodeproj -scheme Markify -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:MarkifyTests/PerformanceAuditTests \
  -parallel-testing-enabled NO test CODE_SIGNING_ALLOWED=NO ENABLE_TESTABILITY=YES
```

It writes `/private/tmp/markify-performance-audit.json`. Preserve `performance-audit-results.json` as baseline; save after results separately and update the audit with actual before/after timings and limitations. Baseline rich-prose edit was ~2370 ms; 500-row table edit ~7418 ms / unchanged update ~5145 ms; long-line parse ~1293 ms.

Audit diagnostics need interpretation: the old cold HTML measurement now times asynchronous submission rather than completion. Update it or label the comparison clearly. Word-count diagnostic still uses the original split implementation; measure the new cached implementation honestly, distinguishing cold and warm work. Three medians alone do not establish p95, memory plateau or battery behavior.

Keep committing each verified step on `optimize`. Finish with a concise report of actual fixes, tests, measured improvement and remaining limitations.
