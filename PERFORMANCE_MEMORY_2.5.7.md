# Markify 2.5.7 memory investigation

Measured October 26, 2026 on `fix/memory-2.5.7`, based on `380e0fc`, with marketing version 2.5.7 and build 370. Product behavior was not changed. Raw benchmark samples and environment metadata are in [performance-memory-results-2.5.7.json](performance-memory-results-2.5.7.json).

## Establishing the baseline

`HANDOFF_MEMORY_2.5.7.md` describes another branch at `a774421`, build 369. This checkout started at 2.5.6 build 367. The referenced reports were recovered read-only with `git show a774421:PERFORMANCE_MEMORY_2.5.7.md` and `git show a774421:PERFORMANCE_AUDIT_2.5.6.md`; they were not present in this checkout. The handoff's font caches, source-map bridging changes, boxed model changes and startup-pass suppression are absent here. Its before/after footprint figures cannot be used as this branch's measurements.

The saved `defaultLens` preference is Markdown, although the application's fallback is Rendered. Both stress documents had `com.markify.lens=rendered` extended attributes when inspected. Synthetic loads explicitly passed `-defaultLens Rendered`; no persistent preference was intentionally changed. Both lenses are editable; there is no separate read-only viewer.

Opening this report in Markdown does not identify the lens used for the measurements: this report was not a profiling input. The controlled baseline and final candidate scripts opened the synthetic prose files or the two stress documents in fresh processes with **both `-defaultLens Rendered` and `-rememberLens NO`**, bypassing saved defaults and per-document lens attributes. A separate debugger inspection confirmed a Rendered body font (`.NewYork-Regular`, 18 pt) during the investigation. The scripts did not independently record the active UI lens for every launch; the earliest stress snapshot did not force a lens and should be distinguished from the later controlled comparison.

## Method and tools

MacBookPro18,2, 32 GiB RAM; macOS 27.2 (26B118), Xcode 27.2 (27B48), arm64. Release app built in the default DerivedData with signing disabled. Benchmarks additionally enabled testability and disabled coverage. The 5 MB app run uses that rebuilt Release executable. These are local unsigned builds, not the distributed application.

Launch with `open -n -a <Release/Markify.app> <documents> --args -startup Blank -ApplePersistenceIgnoreState YES`. Synthetic loads also set the Rendered lens explicitly. Only profiling instances created during this investigation were terminated. Record idle CPU before interpreting footprint; the original 5 MB load remains busy for minutes.

Used `footprint`, `vmmap -summary`, `heap -s`, `sample`, `leaks`, Xcode tests, `xcresulttool`, Instruments Time Profiler and Allocations, LLDB and full malloc-stack high-water attribution. Allocations initially failed to attach; temporary debugger signing of the generated profiling executable subsequently enabled capture. Its executable and signature were restored, verified by hash; project entitlements were unchanged. A content-free malloc memgraph was captured. No MetricKit field collection was performed.

A `-telemetryEnabled NO` command-line override was attempted on the first run, but the sample still contains Sentry crash-handler threads. Therefore these results do not establish a telemetry-disabled baseline. Test hosts use the existing test guard, which disables reporting. Do not infer SDK savings from these measurements.

## Initial baseline measurements

### Two stress documents

Opened the repository-root `render-stress-test.md` (75,402 bytes) and `render-stress-test-2.md` (3,461 bytes) together. The process was idle when sampled, about 27 seconds after launch. The heap contained two `MarkdownTextView` instances.

- Physical footprint: **88.4 MiB**, peak **90.7 MiB**.
- Live malloc allocations: **41,949,099 bytes**, 245,832 nodes.
- Attribute-run array storage: **114,400 bytes**, 326 allocations.
- Parsed span arrays: **76,928 bytes**, six allocations.
- `leaks`: **0 leaks / 0 leaked bytes** in this snapshot.

This is one initial-viewport/session snapshot. It does not exercise scrolling through every asset, establish a long-session plateau, or disprove retention. The supplied Activity Monitor screenshot's 120.8 MB is not a controlled A/B: session history, settings, renderer state and memory accounting need matching. WebKit content/GPU/networking and open/save-panel services run outside the main process. Their memory is absent from the main-process figure; summing process rows also cannot account accurately for shared pages.

### Synthetic 1 MB prose

Source: `# Title\n\n` followed by 13,700 repetitions of `Paragraph with **bold**, *emphasis*, and [a link](https://example.com).\n\n`, totaling **1,000,109 bytes**. Sampled about 28 seconds after launch; the main thread was idle.

- Physical footprint: **102.9 MiB**, peak **120.7 MiB**.
- Live malloc allocations: **49,632,952 bytes**, 224,726 nodes.
- Attribute-run array storage: **14,904,272 bytes**.
- Parsed span array: **4,947,968 bytes**.
- Mutable dictionary storage: **541,600 bytes**, 1,515 allocations.
- CFString storage: **8,528 bytes**, 186 allocations.

`footprint` charges about **31 MiB** to Malloc Large. `vmmap` divides it into **17.3 MiB dirty Malloc Large** and **14.2 MiB dirty Malloc Large (empty)**. Empty allocator pages explain a substantial part of the difference between live heap allocations and footprint. This is region attribution, not allocation-stack attribution; the owner of each large allocation remains unproven.

The handoff's tens of thousands of retained font/dictionary objects did not reproduce in this 1 MB snapshot. That does not invalidate its earlier instrumented runs: configuration, lifetime, autorelease timing and source revision differ. A controlled same-font, same-lens A/B is required before importing its font-cache change as a measured fix here.

### Synthetic 5 MB prose

Same paragraph repeated 68,500 times, totaling **5,000,509 bytes**. First observed idle CPU at **4 minutes 17 seconds** after launch, with **4 minutes 13 seconds CPU time**. The monitoring interval was three seconds; the memory snapshot was taken after a further eight-second wait. This is one launch, not a three-run distribution.

- Physical footprint: **346.5 MiB**, peak **407.0 MiB**.
- Live malloc allocations: **174,241,600 bytes**, 469,783 nodes.
- Attribute-run array storage: **83,586,720 bytes** (about 48% of live allocated bytes).
- Parsed span array: **24,674,304 bytes**.
- Mutable dictionary storage: **553,488 bytes**, 1,573 allocations.
- CFString storage: **8,528 bytes**, 186 allocations.

A later idle footprint sample at about 5 minutes 31 seconds still rounded to **347 MiB**, so the initial post-load footprint did not promptly drain.

The VM malloc-zone table reports **166.2 MiB allocated** and **162.0 MiB dirty fragmentation**. These are allocator accounting categories, not two additional costs to add to footprint. In particular, fragmentation includes unused bytes within dirty allocator pages; it is not proof of leaked objects or of immediately reclaimable memory.

This reproduces the handoff's minutes-long load on the pre-startup-fix architecture, but not its retained-object breakdown: attribute-run storage is much larger here, while dictionaries and bridged strings are small. The absolute footprint also exceeds the handoff's figures. The code revisions differ and this is not a controlled A/B; no regression is attributed to a particular commit. These observations favor addressing attribute-run construction before speculative SDK or image changes for this prose workload.

### Original optimized benchmarks

Both opt-in benchmark tests passed. Medians of three samples, in milliseconds:

| 365,009-byte prose workload | Recovered 2.5.6 baseline | This branch |
| --- | ---: | ---: |
| Parse | 164.85 | 164.52 |
| Full style | 1027.94 | 1028.59 |
| Append and incremental style | 201.23 | 201.11 |

Additional current medians: unchanged incremental restyle **1924.51 ms**, lens roundtrip **1426.90 ms**, Find full style **1155.17 ms**, asset full restyle **1889.03 ms**, asset block restyle **39.54 ms**. These measure direct editor calls, not complete UI latency. The benchmark host reached 553 MiB during a mixed-workload sample; that is not a single-document steady-state footprint and must not be compared with the app measurements above.

## Mechanism and priority

The active 5 MB stack independently confirms the handoff's primary CPU finding. In a sample with 1,311 main-thread observations, two disjoint marker-writing paths alone account for 991 observations in `_platform_memmove`, called by `NSMutableRLEArray insertObject:range:`. They originate in `NativeEditor.style`, through `marker` and per-character `collapse` kern writes. An optimized benchmark-host sample independently shows the same path.

The responsible layer is attributed-text construction in `NativeEditor.style`. It resets attributes, applies content styling, then inserts hidden-marker attributes and individual character kerns into an already fragmented run array. Repeated inserts shift existing entries; this explains the observed scaling bottleneck. A change should batch construction while preserving attribute precedence, source offsets and exact hidden-marker geometry. Simply deleting kerns violates the zero-width-marker invariant and is not justified by a footprint snapshot.

Other handoff proposals checked against this checkout:

- **Image downsampling already exists:** `ImagePreparation.decode` uses `CGImageSourceCreateThumbnailAtIndex`, with a 2048-pixel cap. It is not viewport-specific, but adding thumbnail decoding again would duplicate existing behavior.
- **Editor image data URIs are eager in some paths:** `imageSize` and HTML image handling request `embed: true`; the cache retains PNG/base64 alongside decoded pixels. Moving encoding exclusively to copy/export is a candidate, but needs a measured image-heavy workload and copy/export regression proof.
- **Mermaid WebKit lifetime:** the shared renderer keeps its web view after successful work; `recover` tears it down. Idle shutdown could reduce helper-process memory, but cold render/reload latency and async ownership need measurement. No savings are established here.
- **Paragraph interning and source copies:** plausible candidates, not demonstrated dominant causes in this investigation.
- **The +33 MB after `a774421`:** unresolved. Neither that startup change nor its parent is the current code. A controlled two-revision comparison is required; attributing it to a leak or declaring the startup fix responsible would exceed the evidence.

## Optimization phase: shared marker runs and compact spans

The patch retains the 1 pt invisible marker size and per-composed-character advance calculation, using one shared monospaced system font. Native measurements give the same 0.6181640625 pt advance for the tested ASCII letters, punctuation and spaces; emoji still measures separately. Equal advances can share one kern run. A new regression verifies that a long mixed-width ASCII URL retains **one** kern run.

`collapse` also groups consecutive equal advances before calling `addAttribute`, rather than submitting a redundant write for every character. Unicode clusters remain whole at both boundaries. The full-document marker pass coalesces ranges, builds their attributes in source order, then merges with an immutable snapshot of content attributes into cleared storage from left to right. Partial asset restyles keep their existing regional path, and later overrides for chips, math, lists and tables retain their order. Source characters are never replaced.

`MarkdownModel` copies its sorted spans into compact owned array storage once before retaining them. Heap comparison found a 41.8 MB span buffer where the baseline used 24.7 MB for the same input; this avoids retaining the builder's geometric spare capacity. The sorted span values and order are unchanged.

The invisible-font choice intentionally updates **14 Rendered-lens golden probes** from `1 hidden` to `1 m hidden`. Visible probes and the entire Markdown-lens golden are unchanged. Geometry checks cover ASCII and Unicode URLs and compare thirty repeated Unicode links against the previous proportional-font implementation, within the existing 1 pt tolerance. Rectangles must have nonzero widths, preventing offscreen/empty results from passing. Copy-button rendering passes in both appearances.

The new opt-in 2 MB marker-dense regression reproduced the old Debug slowdown at **24.624 seconds**. Before the final bounded pools and per-pass font reuse, the grouped shared-kern implementation completed the isolated test in **5.541 seconds**, below its 12-second guard. The final Release regression also passes that guard; Xcode reports overlapping host wall durations for the concurrently scheduled tests, so those durations are not treated as isolated styling timings. It uses the existing `MARKIFY_PERFORMANCE_AUDIT` opt-in so a synchronous multi-MB test cannot block concurrently scheduled renderer deadlines in normal runs.

The normal Debug suite passed **225 tests** with four opt-in diagnostics skipped. The Markdown package passed **47 tests** after the compact-buffer change. Existing source, editing, incremental/full equivalence, stress scrolling, cache, export and rendering checks passed. The existing OverlayLayoutTests priority-inversion runtime warning remains. A separate full-suite Release attempt passed 223 tests but failed a Quick Look test that loads a hard-coded `MarkifyQuickLook.debug.dylib`; normal tests are validated in Debug and optimized diagnostics separately in Release.

## Transient allocation attribution and follow-up

An initial shared-run candidate reduced live malloc allocations to about 113 MB and attribute arrays to 26.5 MB, but **regressed physical footprint to 421.6–427.1 MiB**. It was not accepted as a memory improvement. Calling `malloc_zone_pressure_relief(0, 0)` after settling returned zero bytes and did not reduce footprint; no allocator-relief call remains in the patch.

Full malloc-stack high-water analysis attributed about 99 MiB to marker construction, of which roughly 83 MiB was autorelease-pool page storage, and another 50 MiB to the merge closure. Bridged enumeration arguments are created before the callback, so a pool inside each callback misses them. Pools now wrap batches of 1,024 marker ranges and entire enumerations over 16,384 UTF-16 units. A regression checks a composed emoji crossing that boundary. This reduced the 5 MB footprint to 354.8–355.2 MiB across three fresh launches, essentially unchanged from the controlled baseline, while retaining the latency improvement.

The same instrumented trace attributed another 46.15 MiB at high water to repeated `EditorTheme.adding` font descriptor construction. The styling helper now reuses bold/italic conversions within a single pass, keyed by the full `NSFont`, with separate maps for each trait. It calls the existing conversion unchanged on a cache miss. Maps expire at the end of the pass; there is no cross-document cache or new eviction policy. Existing goldens cover nested bold/italic traits and font sizes.

The instrumented high-water capture recorded 428.5 MiB allocated heap plus VM, 4.51 GiB cumulative allocations and 36.6 million allocations. These diagnostic values include instrumentation overhead and are **not** directly comparable with the uninstrumented physical-footprint measurements. Font construction and source-map bridging remain independently identifiable costs; no source-map change was made in this patch.

## Controlled comparison and final verification

The control was rebuilt from original `NativeEditor.swift` and `MarkdownModel.swift` at `380e0fc`, retaining version/build 2.5.7/370 and identical Release build flags. Candidate sources were restored automatically afterward. Each row is a fresh launch; CPU was polled every three seconds until below 5%, followed by an eight-second wait and recheck. Only profiling instances were terminated. Load times are polling observations, not precise UI-ready timings.

Final optimized diagnostics all pass (three tests). Medians of three direct-call samples at 365,009 bytes:

| Operation | Original | Final |
| --- | ---: | ---: |
| Parse | 164.52 ms | 163.89 ms |
| Full style | 1028.59 ms | 330.33 ms |
| Append and incremental style | 201.11 ms | 202.09 ms |
| Unchanged incremental restyle | 1924.51 ms | 684.03 ms |
| Lens roundtrip | 1426.90 ms | 681.91 ms |
| Find full style | 1155.17 ms | 395.62 ms |
| Asset full restyle | 1889.03 ms | 678.98 ms |
| Asset block restyle | 39.54 ms | 30.42 ms |

Final uninstrumented measurements:

| Workload | Control footprint / peak (MiB) | Final footprint / peak (MiB) | First observed idle: control → final |
| --- | ---: | ---: | --- |
| 1 MB | 102.5 / 121.4 | 112.4 / 116.1 | 15.21 → 6.18 s |
| 5 MB #1 | 349.0 / 408.3 | 341.5 / 387.6 | 250.71 → 18.23 s |
| 5 MB #2 | 362.5 / 409.7 | 340.2 / 388.8 | 253.81 → 21.25 s |
| 5 MB #3 | 344.5 / 404.3 | 340.8 / 387.8 | 250.82 → 18.23 s |
| Stress pair | 85.8 / 89.6 | 113.5 / 120.4 | 15.25 → 15.27 s |

Median 5 MB settled footprint decreased **349.0 → 340.8 MiB (2.3%)**, median peak **408.3 → 387.8 MiB (5.0%)**. Median first observed idle decreased **250.82 → 18.23 seconds (13.8× faster)**. Attribute-run storage decreased from about **83.6 MB to 26.5 MB (68%)**. Live malloc allocations were 113.2–165.2 MB versus the control's 172.6–224.4 MB; the spread includes launches retaining an additional parsed model and must not be hidden by quoting only the minimum.

Small-workload repeats were necessary because the first final stress result regressed. A second 1 MB launch measured **123.4 MiB**, peak **124.5 MiB**, despite only 35.9 MB live malloc allocations. Two further stress launches measured **88.8 / 92.5 MiB** and **114.5 / 116.1 MiB** (settled / peak). The control has only one fresh launch for each small workload, so these are not matched distributions. The patch does **not** establish uniform footprint savings: the 1 MB settled samples are higher and stress-pair variability is unresolved. Reduced live heap alone remains insufficient acceptance evidence. No additional allocator policy was introduced to force these figures down.

The implementation is a tested, uncommitted candidate with repeatable large-document gains. Further work should explain the smaller-workload variation with matched repeated controls before claiming a general memory improvement. The JSON retains the original baseline, completed comparison and diagnostics.

All 225 normal app tests pass (274 expanded executions), with four opt-in diagnostics skipped. The Markdown package's 47 tests pass after the compact-span change. The existing priority-inversion warning in OverlayLayoutTests remains. No source, undo or document format changes are intended; no help regeneration is needed. The pre-existing localization changes are preserved. No commit or push was made.

Large loads still exceed two seconds, so this investigation does not establish that the reported Sentry hangs are resolved. The separate branch's unexplained +33 MB after `a774421` remains unresolved: neither its startup suppression nor its other optimizations were present in this checkout. No causal attribution is made without a matched two-revision comparison.

Raw diagnostics remain under `/private/tmp/markify-*`; these temporary files may disappear. This report and the JSON retain the principal findings and samples.
