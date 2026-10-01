# Prompt for the coding agent

You are implementing **Markify**, a native macOS 26+ WYSIWYG Markdown editor.

## Inputs (in this folder)
- `README.md`: the full spec. It is the source of truth for behavior, measurements, tokens and copy.
- `Markdown Editor.dc.html` + `support.js`: an HTML design reference. Open it in a browser to see every screen; the ids 1a–1o and 2a–2e match the README. Screen 1a is interactive (⌘/, ⌃⌘S, typing fades the chrome). The Settings tabs in 1n are clickable.
  - **Do not port the HTML.** Recreate it natively.

## Stack
- Swift 6, SwiftUI app lifecycle, deployment target **macOS 26**. Use the system Liquid Glass APIs (`.glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glass)`) instead of imitating glass. Apply glass only to the floating control layer, never to the page.
- `DocumentGroup` + `FileDocument` for `.md` files, so autosave, versions, Recents and "— Edited" come from the system.
- Editor: TextKit 2 `NSTextView` wrapped in `NSViewRepresentable`.
- Parsing: swift-markdown (cmark-gfm), extended for callouts (`> [!NOTE]`), math (`$…$`, `$$…$$`), footnotes and YAML frontmatter.
- **The Markdown source string is the single source of truth.** The Rendered and Markdown lenses are two stylings of the same text storage. Keep selection and scroll anchors in source coordinates so the lens crossfade (240ms) preserves caret and scroll.
- Apple Intelligence runs **on-device only**:
  - System Writing Tools (`writingToolsBehavior = .complete`, `showWritingTools(_:)`) handle proofread, rewrite, tones and transforms.
  - The Foundation Models framework (`LanguageModelSession`, streaming, `@Generable`) handles generate, continue, summarize and title/tag suggestions.
  - No network calls and no cloud extensions.
  - Handle every `SystemLanguageModel.availability` state as the README describes.
- No third-party UI libraries. SF Symbols only (names are listed in the README).

## Milestones (build, run and verify each before moving on)
1. **Shell**:
   - Document app, window with a transparent titlebar, centered 640px column
   - Floating glass controls: sidebar button, title capsule, ✦ button, MD toggle, ⋯ menu, status capsule
   - Light and dark tokens from the README
2. **Lenses**:
   - Markdown lens styling (dimmed syntax)
   - Rendered lens: headings, emphasis, lists, task checkboxes, quotes, callouts, links, footnotes, frontmatter chips
   - ⌘/ crossfade with caret and scroll preserved
3. **Rich blocks**: tables (Tab navigation), fenced code with syntax colors, display and inline math, images (drag-in saved to `./assets`)
4. **Floating format bar** (1c): ✦ Writing Tools, then the block style menu (1o), then the bold/italic/strike/code/link buttons
5. **Slash menu** (1d) and Markdown autoformat shortcuts
6. **Chrome fade while typing** (1g), **Find & Replace** (1e), **empty document** (1h)
7. **Library sidebar** (1f): glass overlay that slides over the page, Open Files + Library sections, search
8. **Apple Intelligence**:
   - 2a Writing Tools popover
   - 2b inline proofread with the suggestion capsule
   - 2c rewrite review with the AI edge
   - 2d inline generate composer with streaming
   - 2e whole-document panel
   - Unavailable/preparing states
   - Each AI change is a single undo step
9. **Settings** (1n): all five tabs (General, Editor, Appearance, Intelligence, Shortcuts), wired to `@AppStorage`
10. **Accessibility pass**: VoiceOver labels on every floating control, Reduce Motion (instant lens swap), Reduce Transparency, Increase Contrast, keyboard-only operation

## Rules
- Match the README's measurements, colors, typography, radii and timings. Where the README names a system component (toggle, popup, slider, segmented control, traffic lights), use the real one.
- Follow the Apple HIG. Keep the chrome minimal. Add no UI that isn't in the design; propose additions separately.
- When the README and the HTML disagree, the README wins. When something is unspecified, choose the most native macOS behavior and note it in `DECISIONS.md`.
- Write unit tests for Markdown round-tripping (rendered edits → identical source) and for the lens-toggle caret/scroll mapping.
- At the end of each milestone, summarize what was built, what deviates from the spec, and what's next.
