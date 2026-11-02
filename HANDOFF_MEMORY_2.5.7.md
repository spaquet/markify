# Handoff: Markify 2.5.7 memory and launch-time investigation

Repo: /Users/spaquet/Sites/Markify. Branch: `feature/memory-footprint-2.5.7`. HEAD: `a774421` (build 369). Read `AGENTS.md`, `PERFORMANCE_MEMORY_2.5.7.md` (full history) and `PERFORMANCE_AUDIT_2.5.6.md` (benchmark) first.

Rules: investigate first and prove causes with measurements before changing product code. Commit only when the user asks; the user pushes. Never pass `-derivedDataPath`. Tests use Swift Testing. Bump `CURRENT_PROJECT_VERSION` (app and extension targets, not the `= 1` test targets) in each phase commit.

## Measurement method (required)

- Build: `xcodebuild -project Markify.xcodeproj -scheme Markify -configuration Release -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO build`
- App: `/Users/spaquet/Library/Developer/Xcode/DerivedData/Markify-fgujxgddrpvorxeunwaujojtnrqa/Build/Products/Release/Markify.app`
- Launch: `open -n -a <app> <doc> --args -startup Blank -ApplePersistenceIgnoreState YES`. **Always pass `-ApplePersistenceIgnoreState YES`**: `pkill` leaves saved window state, so the next launch otherwise restores the previous document (this invalidated a "1 MB" run). Run `pkill -x Markify` in its own command, not chained with `malloc_history`.
- Footprint: `footprint -p <pid>` (physical footprint, not RSS). Classes: `heap -s <pid>`. Regions: `vmmap -summary <pid>`. CPU: `ps -o %cpu=,time= -p <pid>`.
- **Steady state only.** The footprint changes while the main thread is busy styling. Wait until CPU is under 5% (poll every 3 s), then wait 8 s more, then measure. Never compare mid-load samples.
- Traces: `sample <pid> 5 -file out.txt`; for allocations launch with `MallocStackLogging=full MallocStackLoggingNoCompact=1` and use `malloc_history <pid> -callTree <Class> -fullStacks -consolidateSystemFramesBySymbol`. Attribution helper: `python3 /private/tmp/claude-501/-Users-spaquet-Sites-Markify/527368cf-1bea-4bae-a66b-6db62e403cd4/scratchpad/attrib_tree.py <file> "(in Markify)" 20`.
- Test documents: `/private/tmp/claude-501/-Users-spaquet-Sites-Markify/527368cf-1bea-4bae-a66b-6db62e403cd4/scratchpad/mem/` (`prose-100k.md` … `prose-5m.md`). Debug builds are fine for counts, not for footprint.
- Tests after any change: `xcodebuild -project Markify.xcodeproj -scheme Markify -destination 'platform=macOS,arch=arm64' -only-testing:MarkifyTests CODE_SIGNING_ALLOWED=NO test` (all must pass) and `swift test --package-path MarkifyMarkdown` (51). Swift Testing selectors need the suite name; env vars for test hosts need the `TEST_RUNNER_` prefix. Layout golden tests are sensitive to hidden-marker font changes.

## What is proven (5 MB document, Release, clean launch)

1. **The footprint is not steady after launch because the main thread is still styling.** The first `NativeEditor.style` pass takes minutes. `sample` shows about 85% of samples in `NSMutableRLEArray insertObject:range:` → `_platform_memmove`: each attribute-run insert moves the whole tail of a run array with hundreds of thousands of entries, so the cost is quadratic (1 MB settles in about 12 s; 5 MB took about 253 s).
2. **Two sources of those inserts**, both in `NativeEditor.style`:
   - `collapse` (NativeEditor.swift ~258-265) adds one `.kern` attribute per character of every hidden marker. Disabling it cut the load from about 253 s to about 93 s and did not change the footprint.
   - `marker` (~266-270) calls `storage.addAttributes([.foregroundColor, .font], range:)` for every hidden marker range; the `memmove` remains there after `collapse` is disabled.
3. **The document was styled twice at launch.** With the blank startup window showing, an opened file gets its own window (pass 1 in `makeNSView`), then `MarkifyAppDelegate.replaceStartupDocument` reverts the startup document to the file (pass 2 in `updateNSView`) and closes the first window. Fixed in `a774421`: the first pass is skipped (`startupDocumentWillReplace`, `styleSkipped`, restyle fallback in `watchDocument`). Load went from about 253 s to 127–133 s.
4. **Steady footprint at 5 MB: 239 MB before `a774421`, 271–281 MB after (3 runs, reproducible).** Unexplained. Skipping a pass should not add memory.
5. Clean 1 MB launch: 105 MB, steady from 12 s (Malloc Small 52 MB dirty, Malloc Large 31 MB dirty, about 22 MB other; blank baseline is about 42 MB). The Malloc Large part is not attributed.
6. Earlier work on this branch: bold/italic font variant cache (retained `NSMutableDictionary` 275k → about 1.4k), `MarkdownSourceMap` line splitting without Objective-C bridging (CFString 137k → about 250), font cache for prose and mono, boxed `Kind.listItem` and `MarkerList`. A previous attempt to remove per-character kerns cut attribute runs by 60% but failed the layout test `copiedButtonShowsAGreenCheck` and did not change retained memory; do not repeat it without a layout fix.

## Sentry App Hangs

All are from this memory testing (one user ID, one machine, 267-281 MB `app_memory`, release 2.5.7 build 368). They are the same load stall caught in different phases: 36 (`collapse` `.kern` writes, `updateNSView`), 3D (cmark `Literals.collect`), 3F (cmark `Walker.visit`), 3V and 40 (`MarkdownSourceMap.init`). 3A, 3B, 3E, 3G, 3K, 35, 3P, 3W, 3X, 3Z were not read in full. Documented in the umbrella issue https://github.com/spaquet/markify/issues/77 (comment 6401185712; keep adding rows there, do not open a new issue). Resolve them only after a clean 5 MB load shows no 2 s hang.

## Tasks

**1. Explain the +33 MB steady footprint after `a774421`.** Measure `heap -s` and `vmmap -summary` after settling, for `a774421^` (build from `git stash`/worktree is not needed; use `git checkout a774421^ -- Markify/ContentView.swift Markify/MarkifyApp.swift Markify/NativeEditor.swift`, build, measure, then restore) and for `a774421`. Diff by class and region. Report the cause with numbers. Do not change product code in this step.

**2. Remove the quadratic attribute-run inserts in `NativeEditor.style`.** Batch the hidden-marker styling (fonts, colors, kerns) so the attribute runs are written once, not per range and per character, without changing what `editor.string` or the layout produce. A fix must pass `copiedButtonShowsAGreenCheck` and the golden probes in `EditorFixtureTests`; if a golden entry changes on purpose, say why in the commit. Add a test that styles a large synthetic document and bounds the time, and re-measure load time and steady footprint at 5 MB (three runs). Do not commit; report the numbers.

**Other open items (not started; verify each against the code before changing it):** `NSMutableRLEArray` memory (about 10 MB at 5 MB); Malloc Large attribution at 1 MB; decode images to display size with `CGImageSourceCreateThumbnailAtIndex` (NativeEditor.swift ~1096); `imageDataURIs` (~2549) should be built on demand at export; Mermaid `WKWebView` (Mermaid.swift ~202) never shuts down; paragraph style interning (~19 `NSMutableParagraphStyle` sites); duplicate text copies (`document.text`, `view.string`, `MarkdownModel.source`, undo); launch-time SDKs (Sentry, Sparkle, WebKit).

## Tools available in Xcode (use where they help)

Instruments via `xctrace` (Allocations, Leaks, VM Tracker, Time Profiler, hangs template), the Memory Graph debugger, MetricKit payloads (`MXMetricManager`, hang and CPU diagnostics) for field data, and the Sentry MCP (org `markify-ax`, project `markify`).
