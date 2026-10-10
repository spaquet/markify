# Markify 2.5.0 performance and stability audit

Measured October 10, 2026 at commit `6210d2f` (2.5.0, build 335). No application behavior was changed. The changes accompanying this report extend the opt-in diagnostics, make shortcut UI tests bypass reporting/onboarding, and correct the telemetry proposal's description of the current code.

## Findings

The original performance fixes remain effective in the optimized build. A 5,000-paragraph prose edit measured **205 ms**, versus **209 ms** in the saved post-fix results and **2,370 ms** before that work. The largest remaining delays are in workloads the original audit did not exercise: whole-document restyles after asset completion, structural edits, Find highlighting and lens changes.

The initial Debug runs appeared to show a roughly 2.5× parsing regression. Release timings closely match the saved baseline instead. Disabling coverage did not materially change Debug results. **Do not treat the Debug-to-historical difference as a confirmed 2.5.0 regression.** The historical files lack build/toolchain/hardware metadata, and parser source/dependencies are almost unchanged since `af3ac97`; the model change adds table column alignments. A controlled rebuild of both versions would be needed to attribute a smaller difference to the release.

Raw samples, configuration and machine details: [performance-audit-results-2.5.0.json](performance-audit-results-2.5.0.json). Existing historical files are preserved.

## Stability verification

**283 regular tests passed, zero failed:** 196 app tests, 47 Markdown-package tests, 37 OKF-package tests and three Xcode UI tests. The app run skipped the three opt-in diagnostics as intended; those diagnostics passed in separate benchmark invocations. The selected UI tests exercised inline formatting plus undo, Find/Replace navigation and keyboard focus, and lens/library toggling. They used small documents and do not validate large-document interaction latency.

The app suite covers literal Unicode echo comparison, external-file conflict handling, observer rebinding/teardown, table virtualization/reuse/footnote updates, incremental/full styling equivalence, export and renderer/cache behavior. No crash or source-corruption failure was observed in these runs; this does not establish long-session stability.

Xcode reported **two runtime priority-inversion warnings** in the UI run: interactive work waiting on Default QoS during `testFind`, and on Utility QoS during `testLensAndLibrary`. The result bundle and exported runner logs contain the warning messages but no identifying application stack. Their `[Internal]` classification and placement alongside accessibility queries leave app versus automation/framework ownership unresolved. Treat these as a profiling follow-up, not a confirmed Markify defect; reproduce with Thread Performance Checker and capture the blocking stack before changing queue priorities.

Result bundles remain at `/private/tmp/markify-250-regressions-retry.xcresult`, `/private/tmp/markify-250-ui.xcresult`, `/private/tmp/markify-250-release-audit.xcresult`, `/private/tmp/markify-250-no-coverage.xcresult` and `/private/tmp/markify-250-html-isolated.xcresult`. Package logs are `/private/tmp/markify-250-markdown-tests.log` and `/private/tmp/markify-250-okf-tests.log`. These temporary artifacts can disappear; the committed JSON preserves the measurements, counts and warning messages.

## Measurements

Apple M1 Max, 32 GB RAM, macOS 27.2 (`26B5101f`), Xcode 27.1 (`27A9269`), arm64. Benchmarks ran sequentially, without package tests or UI automation running beside them. Release used `ENABLE_TESTABILITY=YES`, signing disabled and coverage disabled, in default DerivedData. These are optimized local test-host measurements, not measurements of the signed distribution app.

Times below are medians in milliseconds, normally over three samples. Initial table overlays and cold HTML have one sample; unchanged-file polling has ten. Full-style samples mix initial and subsequent calls; unchanged-overlays includes an expensive first repeat. Keep the raw samples when interpreting either. Three samples cannot establish p95, statistical significance or field failure rates.

`prose-N` means N repeated paragraphs, not N lines: prose-5000 is 365,009 UTF-8 bytes and 10,002 source lines (no phantom line after the final terminator). The additional Unicode workload is 390,009 bytes and the same line count. Tables are measured by body rows. Styling timings stop when the styling function returns; they exclude complete viewport drawing and asynchronous asset settlement.

| Original workload / operation | Historical before fixes | Historical after fixes | 2.5.0 Release |
| --- | ---: | ---: | ---: |
| Prose 1,000 / parse | 35.61 | 33.89 | 33.82 |
| Prose 5,000 / parse | 179.73 | 172.32 | 169.37 |
| Prose 5,000 / full style | 1,057.78 | 1,075.88 | 1,048.19 |
| Prose 5,000 / append + incremental style | 2,370.01 | 209.27 | 204.68 |
| Prose 5,000 / cached word count, cold | — | 22.61 | 22.46 |
| Inline math 1,500 / warm style | 59.26 | 53.02 | 46.75 |
| Table 50 / unchanged overlays | 57.20 | 2.80 | 2.95 |
| Table 500 / initial overlays | 9,509.33 | 74.25 | 88.99 |
| Table 500 / unchanged overlays | 5,145.64 | 3.01 | 5.62 |
| Table 500 / tail edit + style + overlays | 7,418.85 | 38.19 | 40.25 |
| Unchanged local file / refresh | 0.0867 | 0.0029 | 0.0034 |

Small historical differences are descriptive, not proven improvements/regressions. Large-table initial/unchanged refresh warrants attention, but the measurements alone cannot separate newer table behavior from environment changes.

Additional optimized workloads:

| Operation | Prose 1,000 | Prose 5,000 | Unicode 5,000 |
| --- | ---: | ---: | ---: |
| Unchanged incremental restyle | 301.64 | 1,920.48 | 2,307.30 |
| Markdown → Rendered style roundtrip | 177.12 | 1,454.17 | 1,515.64 |
| Heading-character replacement + incremental style | 327.72 | 2,148.71 | 2,657.03 |
| Full style with Find highlights | 116.68 | 1,182.90 | 1,266.98 |
| Literal comparison against independent equal copy | 0.003 | 0.011 | 0.012 |

These are direct editor calls, not end-to-end UI latencies. The lens result includes two style passes, without SwiftUI update, selection/scroll anchoring or drawing. Heading replacement writes the same character to keep source and sample sizes identical; NSTextStorage still invalidates the model and exercises the structural-edit fallback. Find measures styling with an active query, not search-only scanning. Literal comparison includes a Swift Testing assertion and is near the measurement floor; it does not measure the full SwiftUI update/32-snapshot echo path.

Isolated cold HTML in Debug submitted in **79.60 ms** and finished importing in **234.77 ms**, versus saved **92.55 / 253.28 ms**. This single cold observation is not evidence of a reliable improvement. The historical pre-fix `full-style` HTML metric is a different boundary and is not directly comparable.

## Recommended implementation order

### 1. Reduce whole-document attribute work for asset completion and Find

**Measured:** an unchanged incremental restyle costs 1.92 seconds in prose-5000 despite a cached parse; Unicode costs 2.31 seconds. Full Find styling costs another 1.18–1.27 seconds.

**Cause visible in code:** `NativeEditor.makeNSView` installs `restyle` with `incremental: true`. Without an eligible character edit, `style` copies the entire attributed storage, rebuilds all attributes and traverses every run in `applyChangedAttributes`. Coalescing completions limits the number of passes but does not reduce the cost of each pass. `updateNSView` also treats query/current-match changes as a reason to run complete styling, and any nonempty query disables paragraph styling for typing.

**Small first change:** separate Find highlight updates from syntax styling, updating previous/new match ranges while preserving syntax attributes. Then pass the affected asset anchor/range through the existing restyle scheduler and update only that block's attributes/layout. Keep full fallback for theme, lens and structural changes. Do not simply skip an unchanged-source restyle: asset height/appearance may have changed.

**Acceptance checks:** source, selection and undo remain unchanged; changing/clearing Find removes old highlights; typing with Find open matches full styling; asset-height changes preserve table/scroll alignment; existing golden and pixel tests pass. Compare the new workloads before/after in Release. This is the highest-value target because caching parsing alone does not remove these stalls.

### 2. Reduce structural-edit fallback cost, then address full parsing per keystroke

**Measured:** even an eligible prose append takes 205 ms at 5,000 paragraphs, with parsing alone taking 169 ms. A heading-character replacement takes 2.15 seconds, or 2.66 seconds in the Unicode workload. At 1,000 paragraphs the heading path still takes 328–373 ms.

**Cause visible in code:** `changedStyledParagraph` asks for the full new `model` before returning a paragraph. Headings/lists/tables/other structural spans are rejected by `styledParagraph`, forcing scratch styling and attribute comparison across the entire document. Both old/new paragraph extraction also scan the span collection.

**First step:** extend safe range styling to contained headings and index span intersections using the already sorted spans. Preserve full fallback where edits affect surrounding structure or reference definitions. Measure afterward; parsing will still set a floor. If that floor remains unacceptable, investigate versioned background parsing or incremental parsing with stale-result rejection and a clearly defined synchronous editing model. Avoid introducing a second independent parser or making selection/undo depend on obsolete offsets.

**Acceptance checks:** incremental/full attribute equivalence for headings and edits that introduce/remove block syntax, list/table boundaries, references, Unicode and multiline paste; immediate typing/undo must preserve exact source. The new heading diagnostic is a workload, not sufficient correctness coverage for an implementation.

### 3. Make visible-table refresh reuse table/cell context

**Measured:** unchanged overlays grow from 2.95 ms at 50 rows to 5.62 ms at 500 rows; the latter is above the saved 3.01 ms. Initial 500-row overlay refresh takes 89 ms, and a tail edit plus refresh takes 40 ms. The old multi-second table behavior has not returned.

**Cause visible in code:** `refreshTableOverlays` rebuilds the complete row/index collections on each call. Each `tablePresentation` searches tables and rows again to identify the cell's column/header even though the caller already knows its table and row. `tableWidths` invalidates for every source version, including unrelated tail edits. `settleLayout(through:)` explicitly lays out the document prefix through the last wanted row, so bounded overlay counts alone do not guarantee bounded layout time near the bottom.

**Small first change:** pass existing table/row/column context into cell presentation and reuse row metadata until textVersion changes. Consider retaining table widths after an edit outside that table. Preserve focused editors and geometry; do not remove prefix settlement without reproducing the scrolling misalignment it prevents.

**Acceptance checks:** measure top/middle/bottom scrolling in large tables and tables after long prose, focus/Tab across the viewport boundary, hover expansion, alignment, reference/footnote updates, and overlay/presentation counts over repeated scroll cycles. Existing tests verify nearby-cell virtualization and reuse, but this audit does not measure bottom-of-document scrolling or a sustained memory plateau.

### 4. Preserve the stability fixes and make measurements reproducible

Literal text comparison is fast in the added Unicode workload, and the existing regression test covers the actual snapshot echo pattern and canonical-inequivalent source. Keep that guard. Observer rebinding, table reuse, renderer ownership/cancellation and bounded caches already have regression coverage; optimize their callers without removing those protections.

Keep the new workloads opt-in and store release/build/toolchain/configuration alongside future measurements. Add a repeated UI workflow for large-document typing, Find navigation, lens toggling and table scrolling before replacing the styling paths. A local Instruments/signpost investigation of initial viewport and renderer completion is a useful follow-up; the existing telemetry document remains a proposal, not evidence that editor-specific spans already exist in Sentry.

## Reproduction

From the repository root, run original and additional editor workloads together, without HTML, package tests or UI automation running concurrently:

```bash
TEST_RUNNER_MARKIFY_PERFORMANCE_AUDIT=1 xcodebuild -quiet \
  -project Markify.xcodeproj -scheme Markify -configuration Release \
  -destination 'platform=macOS,arch=arm64' -enableCodeCoverage NO \
  '-only-testing:MarkifyTests/PerformanceAuditTests/measureEditorWork()' \
  '-only-testing:MarkifyTests/PerformanceAuditTests/measureEditingFallbacks()' \
  -parallel-testing-enabled NO test CODE_SIGNING_ALLOWED=NO ENABLE_TESTABILITY=YES
```

The outputs are `/private/tmp/markify-performance-audit.json` and `/private/tmp/markify-performance-fallbacks.json`; copy them before another run overwrites them. For Debug use `-configuration Debug` and omit `ENABLE_TESTABILITY=YES`. For isolated cold HTML, select only `'MarkifyTests/PerformanceAuditTests/measureHTMLImport()'` in a separate invocation; its output is `/private/tmp/markify-performance-html-audit.json`. Swift Testing method selectors need the trailing `()` here: the selector without it selected zero tests in this environment. Verify the result bundle's actual test count.

The full app suite runs without `TEST_RUNNER_MARKIFY_PERFORMANCE_AUDIT`, using `-only-testing:MarkifyTests`. Package suites use `swift test --package-path MarkifyMarkdown` and `swift test --package-path OKFKit`. Selected real UI checks use `-only-testing:MarkifyUITests/ShortcutUITests/testInlineFormatting`, `/testFind`, and `/testLensAndLibrary` (each with the full target/class prefix).

## Limits

No production optimization, telemetry collection or dependency change was implemented. No signed-distribution benchmark, Instruments allocation/leak session, long-duration soak, remote-resource/network stress, multi-window load, complete UI suite or real-device display latency was measured. Warm math repeats one formula and does not characterize thousands of distinct formulas. No initial-viewport/assets-settled or end-to-end file-open measurement is implied by these style timings. Historical comparison needs a controlled A/B before attributing small differences to 2.5.0.
