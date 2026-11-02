# Memory architecture investigation

Investigated October 26, 2026. Source review only; no product changes or new runtime measurements. Existing working-tree changes were left intact. External repositories were inspected from shallow clones under `/private/tmp`; the source revisions below identify the findings, not necessarily the versions users have installed.

## Conclusion

Keep Markify a native Markdown editor. The strongest architectural experiment is to retain source and semantic information globally, but construct detailed presentation attributes as TextKit requests paragraphs for layout. Do not replace the editor with CodeMirror, Electron, a document-wide HTML preview, or a bitmap renderer.

This is a plausible direction with native API support, not a demonstrated memory reduction. A bounded prototype must establish TextKit's retention behavior and compatibility with Markify's layout before committing to migration.

## What the measurements actually establish

`PERFORMANCE_MEMORY_2.5.7.md` describes the current candidate; `HANDOFF_MEMORY_2.5.7.md` describes a different branch. Their absolute footprints are not interchangeable. `PERFORMANCE_TELEMETRY.md` is a proposal, not collected field evidence.

The controlled 5 MB comparison reports median settled footprint of 349.0 → 340.8 MiB, peak of 408.3 → 387.8 MiB, and first observed idle of 250.82 → 18.23 seconds. Attribute-run storage fell from approximately 83.6 MB to 26.5 MB. That is strong evidence of a construction-time improvement, but only a small settled-footprint improvement. Smaller-workload variability remains unexplained.

The prose workload contains no diagrams or images. Its results directly implicate text/model/styling and allocator behavior; reducing diagram caches cannot explain or solve that workload. Existing allocation attribution demonstrates large transient construction costs and dirty allocator pages. It does not establish that every remaining byte belongs to retained rendered content, or that removing the final 26.5 MB attribute array would recover the entire footprint difference.

## Current ownership and work boundaries

- `Markify/NativeEditor.swift:91` creates `MarkdownTextView(usingTextLayoutManager: true)`: TextKit 2 is already in use.
- `MarkdownTextView.model` rebuilds the full `MarkdownModel` on a text-version change. The retained model contains source, spans, tables and lists; the temporary cmark document is not a retained field of `MarkdownModel`.
- `NativeEditor.style` writes presentation attributes across the document on a full pass. Ordinary eligible edits have a paragraph styling path, but that path consults the full model after edits. It is not an incremental parser.
- The incremental fallback creates `NSTextStorage(attributedString: live)`, styles it, then applies differences. This adds full-document transient representation work even when live layout invalidation is narrow. Physical buffer duplication depends on Foundation behavior and must be measured.
- TextKit lays out around the viewport; layout fragments draw decorations. Markify does not eagerly rasterize every prose paragraph into retained images.
- Mermaid leasing already targets approximately the viewport plus a margin. Reimplementing viewport leasing would duplicate existing behavior.
- `OndineFFI/src/lib.rs` and `OndineMermaid` compile **Mermaid source to SVG**. Ondine is not the Markdown text editor or prose layout engine. SVG display/snapshot work still uses WebKit.

The mismatch is between lazy layout and eager full-document styling, rather than the absence of viewport rendering.

## Other projects: useful evidence and limits

### MarkEdit

Inspected revision `7295b03a8f88b0d0294d0bd853913feed812bec2`.

MarkEdit has native macOS UI around a WebKit-hosted CodeMirror 6 editor. Its [README](https://github.com/MarkEdit-app/MarkEdit/blob/7295b03a8f88b0d0294d0bd853913feed812bec2/README.md) identifies that engine. In [styling/matchers/lezer.ts](https://github.com/MarkEdit-app/MarkEdit/blob/7295b03a8f88b0d0294d0bd853913feed812bec2/CoreEditor/src/styling/matchers/lezer.ts), `createNodeRanges` traverses syntax within `editor.visibleRanges` to build decorations.

The relevant lesson is limiting presentation work to visible ranges while retaining source semantics. CodeMirror is not proposed as a Markify dependency or replacement. MarkEdit's default editing experience and optional extensions also differ from Markify's Rendered lens.

### Zettlr

Inspected revision `97d2d26e3cff9a1d0a8e97dc138fb56fcf288246`.

Zettlr uses CodeMirror in its Electron application. Its [base-renderer.ts](https://github.com/Zettlr/Zettlr/blob/97d2d26e3cff9a1d0a8e97dc138fb56fcf288246/source/common/modules/markdown-editor/renderers/base-renderer.ts) builds inline widget decorations from `view.visibleRanges`, updating on document, viewport and selection changes. However, `renderBlockWidgets` supplies an empty range list, which explicitly requests traversal of the full document. Emphasis and other plugins also have viewport-aware paths.

It is evidence for separating source state from presentation work, not proof that all presentation state is viewport-bounded or that Zettlr uses less total memory.

### MarkText

Inspected revision `a6596d3d3428bc4f40374398b79ba4f198505c6d`.

Current Muya code uses structured JSON document state and block objects/DOM. [state/index.ts](https://github.com/marktext/marktext/blob/a6596d3d3428bc4f40374398b79ba4f198505c6d/packages/muya/src/state/index.ts) parses Markdown into state and serializes state back into Markdown. [scrollPage/index.ts](https://github.com/marktext/marktext/blob/a6596d3d3428bc4f40374398b79ba4f198505c6d/packages/muya/src/block/scrollPage/index.ts) creates blocks for every top-level state entry; `Parent.append` attaches their DOM nodes. Targeted transactions can preserve adjacent block instances. Inline rendering uses Snabbdom.

The inspected creation path is not viewport virtualization. Incremental updates and virtualization are distinct. Its structured-state/serialization architecture would also conflict with Markify's requirement to preserve the user's exact Markdown source unless redesigned around source edits. Similar appearance alone does not make it the right foundation.

No comparative app memory benchmark was performed. None of these source findings establishes a memory ranking.

## Recommended native experiment

Keep the source text as authority, retain the existing full semantic model initially, and move presentation construction out of document-wide text-storage mutations into paragraphs supplied on demand to TextKit. Query model spans intersecting a requested paragraph, including enclosing block context. Styling a paragraph must not scan all spans; use an appropriate range index if measurement warrants it.

Apple's installed SDK exposes `NSTextContentStorageDelegate.textContentStorage(_:textParagraphWith:)`, which can supply a custom `NSTextParagraph` with the same UTF-16 length as the requested source range. `NSTextLayoutManager` also exposes rendering attributes and `renderingAttributesValidator`, documented as filling attributes for a layout fragment before layout. These are candidate integration points, not guarantees of bounded caching. Test custom paragraph provision first for geometry-affecting styles; validate which existing attributes belong in paragraph content versus layout-manager rendering attributes.

Preserve source characters, UTF-16 positions, undo, selection, IME composition and accessibility. Hidden markers must still occupy zero width. Block context must remain correct for lists, fences, tables, callouts and multiline constructs. Font, kern and paragraph layout changes affect geometry, so simply applying styles after viewport layout is unsafe: it can create height-estimation feedback, scroll jumps and incorrect hit testing.

Do not add an independent unbounded paragraph cache. Establish what TextKit retains after scrolling and invalidation. If its element retention remains proportional to the full document, this API alone has not met the objective; assess a custom content manager only with that evidence.

Expected direction: presentation memory should track active layout and bounded reuse, while source and semantic indexes remain proportional to document size. Total editor memory cannot be independent of document size. Large single paragraphs and large individual tables need separate scrutiny because paragraph-level laziness does not bound their internal cost.

## Alternatives and priority

1. **Lazy native paragraph presentation:** first experiment. Directly targets eager attributes and full scratch-storage construction while preserving native editing services.
2. **Incremental semantic parsing:** separate follow-up if full parsing remains a measured typing or allocation bottleneck. Reference definitions, fences, lists and extension masking can propagate changes beyond the edited paragraph; arbitrary line-chunk parsing is incorrect. Moving the same full parser into Rust does not by itself make it incremental or reduce retained presentation state.
3. **Custom virtualized native block editor:** fallback if TextKit cannot bound retained presentation. Requires height indexing, cross-block selections, navigation, IME, undo, accessibility and source-coordinate mapping. Substantial maintenance cost; do not start here.
4. **Custom Core Text/GPU/Rust text editor:** greatest control, but assumes ownership of editing behavior currently provided by AppKit. Not justified by current evidence.

Moving full parsing off the main thread can improve responsiveness, but overlapping source versions can increase peak memory. Treat scheduling and retention as separate problems, with stale-result rejection and bounded in-flight work.

## Proof required before adoption

Use a disposable experimental branch and existing performance fixtures. Compare identical Release builds/settings against the current candidate, with at least three fresh launches per workload: blank, stress pair, 1 MB and 5 MB prose. Record settled physical footprint, peak, live attributed-run/model allocations, open-to-initial-display and typing latency. Include WebKit helper processes for asset-heavy comparisons and report accounting limits.

Measure initial viewport, scrolling to the end, revisiting the beginning and repeated lens switches. A low initial footprint that grows permanently during scrolling does not establish bounded presentation. Compare scaling from 1 MB to 5 MB and separate source/model growth from presentation growth. No numerical memory promise is justified before this comparison.

Verify source unchanged by styling, existing goldens and marker geometry, incremental/full appearance equivalence, scrolling/resizing, undo/redo, IME, selection across distant blocks, accessibility, tables, math, diagrams and export. Export must read full source/model independently of what has been displayed.

For a competitor comparison, use released app versions and identical documents, equivalent presentation modes, clean sessions and the same scroll/edit sequence. Account for Electron/WebKit helper processes; comparing Markify's whole process with an Electron main-process row is invalid. Report actual results before claiming any editor is lighter.

No tests were run for this source-only investigation. Existing test results quoted above belong to the memory report, not a new verification run.
