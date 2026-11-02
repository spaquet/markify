# Markify 2.5.7: lazy paragraph presentation

## Baseline and implementation

This comparison starts from the existing uncommitted 2.5.7 **build 371**, including the earlier marker-run optimization and the existing localization/startup changes. It does not use the different branch described by `HANDOFF_MEMORY_2.5.7.md` as its control. App and extension build numbers were incremented to **372**; test-target versions remain unchanged.

Build 372 keeps the full source and semantic model, but supplies self-contained prose and ATX heading paragraphs through `NSTextContentStorageDelegate`. Detailed attributes for those paragraphs are constructed when TextKit requests them, using the existing styler. Source storage retains baseline attributes and contextual block styling. The provider retains a semantic paragraph index and one reusable scratch view, with no cache of previously styled paragraphs. Its copy of styling settings has constant bindings and empty callbacks to avoid retaining the document/editor through SwiftUI bindings.

Lists, tables, multiline syntax, code, images, math, HTML, footnotes and other contextual regions retain their existing full-context path. This is the first bounded migration, not complete block virtualization or incremental parsing. The paragraph index refers into the shared span buffer and uses binary lookup; it does not parse paragraph substrings or scan the entire span list on a paragraph request. Reference-link destinations therefore remain resolved from the full model.

Caret fonts and Find/Replace visibility consult transient paragraph presentation as needed. Styling preserves source characters, UTF-16 coordinates and hidden-marker geometry. No golden changes were needed for this phase. Export remains independent of the currently displayed paragraphs.

## Method

Release builds in default Xcode DerivedData, arm64, signing disabled, without instrumentation or a custom DerivedData path. Same machine and settings for both builds: MacBookPro18,2, 32 GiB RAM, macOS 27.2 (26B118). Each workload runs in a fresh process three times. The profiling script refuses to start alongside another Markify process and terminates only the instances it launches.

Workloads: blank startup, `render-stress-test-2.md`, `render-stress-test.md`, and the existing `/private/tmp/markify-memory-prose-1m.md` and `prose-5m.md` synthetic files (1,000,109 and 5,000,509 bytes). The two stress files are measured individually. Source hashes, executable hashes, build numbers, CPU polling observations and all individual samples are retained in `performance-paragraph-memory-2.5.7.json`.

Launch arguments force Rendered with remembered lenses disabled and saved-window restoration ignored. CPU must be below 5%, followed by an eight-second wait and recheck, before each snapshot. Initial sampling waits at least fifteen seconds after launch; the resulting idle observations are not precise presentation latency. `vmmap`, `footprint` and `heap` snapshots are captured initially. The initial control runner also sent thirty Page Down events, a jump to the end, and a return to the beginning without verifying editor focus. A real-keyboard check exposed that a newly opened window can lack editor focus. Its post-keyboard samples are retained for transparency but excluded from scrolling comparisons. The candidate runner requires accessibility-confirmed focus before navigating; none of these profiling windows exposed a text area to that external harness. Each failure is recorded, and only the valid initial samples are compared. Screenshots confirmed that the stress document was visibly rendered; the cause of the missing external accessibility controls was not established. Separate in-process navigation is described below.

Figures are main-process physical footprint in MiB, not RSS. WebKit and image-preview helper processes are excluded; these results cannot establish total system cost for asset-heavy documents or a memory ranking against Electron applications. The same launch and initial-snapshot sequence is used for control and candidate. Existing disk caches are not cleared; repeated samples help expose variation but are not a cold-cache study. No telemetry-disabled baseline is claimed.

The repeatable runner is `scripts/profile-paragraph-memory.py`. Raw text snapshots are under `/private/tmp/markify-lazy-371` and `/private/tmp/markify-lazy-372`; these temporary files can disappear. The repository JSON retains the principal measurements. It records whether navigation focus was verified; initial control measurements remain valid independently of later keyboard focus.

## Verification

The Markdown package passed **50 tests**. The final full Debug app suite passed **235 tests**, with four opt-in diagnostics skipped (**287 expanded passing executions**). The existing `OverlayLayoutTests` priority-inversion runtime warning remains. Existing editing, export, asset rendering, scroll, marker geometry and golden checks passed. New tests compare native paragraph elements with materialized styles in both lenses, exercise both stress documents, enumerate distant paragraphs without populating source attributes, and verify caret fonts, hidden Find matches, editing, undo/redo, lens changes and explicit teardown. A final incremental-Find regression ensures contextual blocks are checked against newly styled scratch attributes before those attributes reach source storage.

An exploratory unit test that called `setMarkedText` directly after undo/redo in a synthetic window crashed the test host. The same sequence also crashed with paragraph presentation removed. That synthetic composition sequence was removed from the new unit test; undo/redo coverage remains. Existing dead-key tests using actual SwiftUI document windows pass in both lenses, including composition, cancellation, unrelated settings updates and source serialization. Fresh dynamic code-color providers are resolved before comparing test attributes; provider identity is not a visual difference.

A separate Release check sent physical Option-e then e through System Events to the focused editor in a temporary document. It saved the composed `é` correctly and preserved the exact source after a lens roundtrip and undo/redo. Neither stress document was edited.

## Measurements

The control's median initial settled footprints were: blank **41.6 MiB**, stress-2 **71.2 MiB**, stress-1 **87.1 MiB**, 1 MB prose **118.4 MiB**, and 5 MB prose **340.7 MiB**. After the original unverified navigation-key sequence, the respective nonblank medians were **73.0**, **194.8**, **122.8** and **339.7 MiB**. The 5 MB median peak was **388.0 MiB**; the larger stress document's median peak after the key sequence was **726.0 MiB**. These latter samples do not establish verified scroll behavior or its cause.

Initial settled footprint and peak, medians of three fresh processes, in MiB:

| Workload | Build 371 settled | Build 372 settled | Settled change | Build 371 peak | Build 372 peak |
| --- | ---: | ---: | ---: | ---: | ---: |
| Blank | 41.6 | 42.0 | +1.0% | 42.8 | 43.3 |
| `render-stress-test-2.md` | 71.2 | 59.8 | −16.0% | 72.4 | 65.1 |
| `render-stress-test.md` | 87.1 | 98.0 | **+12.5%** | 95.0 | 102.6 |
| 1 MB prose | 118.4 | 103.5 | −12.6% | 122.0 | 114.7 |
| 5 MB prose | 340.7 | 258.0 | −24.3% | 388.0 | 388.0 |

Individual settled samples matter:

| Workload | Build 371 samples (MiB) | Build 372 samples (MiB) |
| --- | --- | --- |
| Blank | 39.3, 41.8, 41.6 | 42.0, 42.0, 42.2 |
| Stress-2 | 71.2, 59.8, 71.4 | 59.7, 59.8, 59.8 |
| Stress-1 | 87.9, 87.1, 86.6 | 98.0, 98.0, 88.8 |
| 1 MB | 128.0, 118.4, 116.7 | 116.5, 103.5, 103.5 |
| 5 MB | 340.3, 340.7, 341.5 | 274.3, 258.0, 212.7 |

The 5 MB document's median attribute-run storage fell **26,466,256 → 67,056 bytes (99.75%)**, and median live malloc bytes fell **113,325,922 → 88,594,048 (21.8%)**. The 1 MB attribute-run median fell **3,161,008 → 38,144 bytes**. This establishes that document-wide prose attributes were removed from retained source styling, with a substantial large-document settled-footprint improvement. It does not remove the full semantic model or all TextKit presentation state.

The large-document **peak is unchanged**, and candidate settled footprint varies substantially despite similar live malloc bytes. No allocation-stack attribution of the remaining peak or allocator/VM gap was performed in this phase. Do not infer that all remaining memory belongs to rendered paragraphs, or promise that a different drawing engine would remove it.

The larger stress document **regressed by 10.9 MiB at the median**. Its median live malloc bytes were approximately unchanged (**41,013,074 → 41,175,634**), which does not explain the physical-footprint increase. Further allocation/VM attribution is needed before calling this a general memory improvement. The smaller stress document's control range overlaps the candidate range, so its median reduction should also be read with the individual samples. These results support the prose migration while leaving a mixed-document regression open; this remains an uncommitted candidate, not a release recommendation.

## Verified navigation audit

An additional opt-in `PerformanceAuditTests.measureParagraphNavigation` audit opens the existing 1 MB and 5 MB prose files in native TextKit 2 windows in an isolated **Debug test host**. It moves to the middle, end and start three times. Every sample asserts that the requested source position is actually within TextKit's viewport and that source text is unchanged. This avoids relying on inaccessible external controls. It samples `TASK_VM_INFO.phys_footprint` in process; these test-host figures must not be compared directly with the standalone Release table.

- 1 MB: **84.84 MiB** initially; navigation samples ranged **85.56–99.70 MiB**, ending at **98.30 MiB**. This short run does not establish a settled plateau.
- 5 MB: **245.53 MiB** initially; subsequent samples stayed within **251.25–254.28 MiB**, ending at **253.75 MiB** after the third return to the beginning.
- Both documents retained **one source attribute run** at all twenty samples. The middle/end/start viewport-offset assertions passed. Detailed paragraph styling was not accumulated into source storage by visiting distant regions.

The audit passed separately after the full normal suite. It is disabled by default through the existing `MARKIFY_PERFORMANCE_AUDIT` opt-in, adding one more skipped diagnostic to future normal runs. Its raw samples and viewport offsets are embedded in the repository JSON. This is evidence for the visited regions, not proof of a global memory bound after visiting every paragraph or of long-session behavior.

Reproduce with the existing synthetic files present:

```sh
env TEST_RUNNER_MARKIFY_PERFORMANCE_AUDIT=1 xcodebuild -project Markify.xcodeproj -scheme Markify \
  -destination 'platform=macOS,arch=arm64' \
  '-only-testing:MarkifyTests/PerformanceAuditTests/measureParagraphNavigation()' \
  CODE_SIGNING_ALLOWED=NO test
```

No commit, push, allocator-pressure call, telemetry change or dependency addition was made. Existing unrelated working-tree changes were preserved.
