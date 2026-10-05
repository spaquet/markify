# Resume prompt

Continue the Markify performance work in `/Users/spaquet/Sites/Markify`.

Original instruction: fix the performance gaps in `PERFORMANCE_AUDIT.md`, plus the regression where web links do not open. Commit each coherent, verified step. Keep all work on the current branch, **`optimize`**. Do not push or deploy. Read `AGENTS.md` and the audit before proceeding. Ponytail full is active: prefer minimal fixes in shared code, native APIs, and meaningful regression checks. Do not spawn agents without authorization.

The previous session stopped for a context handoff, not because the task was finished. Implementation HEAD before this handoff was **`b64b14d`**. Many improvements are committed, but the full audit has not been closed or measured after the changes. Do not claim it is complete.

## Start here

1. Inspect `git status`, current diff and recent commits. Preserve pending and pre-existing edits.
2. Review and compile the pending summary/link-check work described below. The intended test command did **not** start before interruption; `/private/tmp/markify-summary-fixes.log` did not exist at handoff.
3. Verify and commit this step, then address remaining audit work, regenerate help, run the complete relevant tests and repeat the Release audit. Record actual results and remaining limitations.

```sh
xcodebuild -quiet -project Markify.xcodeproj -scheme Markify \
  -only-testing:MarkifyTests/MarkifyTests \
  -only-testing:MarkifyTests/OpenURLTests \
  -parallel-testing-enabled NO test CODE_SIGNING_ALLOWED=NO \
  > /private/tmp/markify-summary-fixes.log 2>&1
```

Use default Xcode DerivedData for Markify; **never add `-derivedDataPath`**. Sandbox restrictions on Xcode/Swift cache directories have required escalated execution. Request tool escalation when necessary, rather than changing build locations. Git add/commit is authorized. Check for leftover test processes before starting another run.

## Pending changes and ownership

Uncommitted implementation:

- `Markify/LinksPanel.swift`: asynchronous, bounded summary-cache loading and actor-based persistence; summary/staleness job ownership and cancellation.
- `Markify/LinkHealth.swift`: asynchronous bounded disk-cache loading; one shared queue of web probes with four global slots; bounded pending keys and cache; serialized off-main persistence.
- `Markify/Inspector.swift`: cancel summary jobs when panels/cards disappear.
- `MarkifyMarkdown/Sources/MarkifyMarkdown/FileRead.swift`: harden bounded reads with `Darwin.open(O_RDONLY | O_NONBLOCK)` and `fstat` regular-file/size checks, preventing a changed path from blocking on a nonregular file.
- `MarkifyTests/MarkifyTests.swift`: async summary-cache test changes, plus two async media test adjustments that already passed the latest focused suite.

These need review and validation. In particular:

- Confirm Swift actor isolation/Sendability and operator precedence in the web queue's `force || entries[key].map(...) ?? true` condition.
- Check shared queue scheduling, cache limits, and cancellation semantics across windows.
- Summary `save` updates memory before disk success; consider consistency on write failure. The load task currently remains stored after completion.
- Summary cancellation guards must prevent an old canceled job from clearing a newer job for the same key.
- Test persistence/reload and concurrent updates; add a focused global probe-budget test if practical using the existing URLProtocol test pattern.
- Rerun package tests for the FileRead hardening and paragraph-model changes. Commit hardening separately from summary/link behavior where practical.

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

Links use `MarkdownTextView.link(at:)` over the model rather than an OKF regex. Reference links, angle autolinks and URLs with balanced parentheses are covered; links in code are skipped. Bare URLs currently are not link spans in the model.

Safe prose styling still parses the new complete model once, then styles a translated paragraph slice using a scratch text view. Block/container edits, Find, multiple edits or context changes fall back to full styling. Source text and UTF-16 selection coordinates remain authoritative.

Media budgets: remote/local image reads 10 MB, thumbnails max dimension 2048, caches max 64 entries / 64 MB; four image jobs concurrently. HTML uses native asynchronous `NSAttributedString.loadFromHTML`, timeout five seconds, two imports per editor, bounded source/cache, stale completion gates. Mermaid has bounded queues/source/SVG/dimensions/cache, 15-second load/render deadlines and recovery. Quick Look source is bounded at 2 MB and disables remote preview images. Export embeds bounded images with a 50 MB aggregate URI budget and falls back to paths.

## Remaining work / review targets

Use the fifteen findings in the audit as the source of truth. Known incomplete areas:

- **Styling:** measure paragraph fast path in Release. Full parse remains synchronous; full fallback rebuilds inline formulas/code highlighting. Review reference/neighbor dependencies and preserve full-style equivalence.
- **Tables:** hover animation still scans all rows and refreshes heights every frame. Restrict work to affected rows. Filter preserved active overlay indices against current rows after deletion. Unchanged cell invalidation includes reference definitions but needs review for footnote/other owner context changes.
- **Document refresh:** initial baseline, explicit manual refresh, prompt rereads, version preservation and merge validation still have synchronous I/O. Preserve conflict/data-loss semantics and existing tests when moving these tails.
- **Media:** math cache is not yet bounded/pruned; display math still renders during drawing. Inline formulas rebuild. Paste file copying and TIFF conversion remain synchronous. Review async HTML stale keys/failure-cache byte accounting and lifetime across closed editors.
- **Bundle scans:** aggregate 50 MB/file-count limits are present, but some `String(contentsOf:)` reads still rely on preflight size checks and could overbuffer a growing file; root-index reads and per-document validation cancellation need review.
- **Search:** unchanged notes are reused and enrichment no longer blocks the indexing actor; main-thread result sorting/mapping and eager enrichment may remain. Do not add complexity without evidence.
- **Mermaid:** review cache/consumer cleanup and failure retry behavior. Recovery and obsolete-queue regression tests passed.
- **Quick Look:** XPC image helper has a five-second bound, but request cancellation is not yet forwarded into its connection.
- **Export:** PDFPrinter still needs explicit deadline/cancellation/process-termination handling and single continuation settlement. ContentView export tasks need owned handles, window teardown cancellation, and no alert on cancellation. SDK NSPrintOperation has no public cancelOperation; do not call unsafe cleanup as cancellation. Avoid stale writes or data loss.
- **Derived UI / Knowledge:** root discovery and backlink retarget writes remain main-thread filesystem work; Inspector grouping still rebuilds in body. Move filesystem work safely with source/version/cancellation gates. Coordinate retarget writes using current disk contents, not a stale snapshot.
- **Links:** finish the pending globally bounded queue, cache persistence and summary cancellation; validate them before committing.

## Validation so far

Latest successful Xcode suite: `/private/tmp/markify-paragraph-fixes.log`, covering `IncrementalStyleTests`, `PerformanceFixTests`, `MermaidTests`, and `MarkifyTests`, serial execution. It passed, including async HTML/local-image assertions and paragraph/full-style equivalence. The pending summary/web-cache changes were made afterward and are **untested**.

Earlier successful focused logs: `/private/tmp/markify-{table,refresh,viewport,io,search,media,renderer}-fixes.log`. They cover observer teardown, overlay layout, refresh conflicts/versions, bounded URL responses, export, search, remote/local media and renderer recovery.

MarkifyMarkdown previously passed 46 tests and OKFKit 37 tests, but rerun after current changes. Async media tests retain source/pixel checks; layout bitmap helpers now ensure layout before capturing, and table thumbnails use their cell reading's prepared images.

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
