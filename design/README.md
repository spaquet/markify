# Handoff: Markify — WYSIWYG Markdown Editor for macOS 26+

## Overview
Markify is a minimal, single‑surface Markdown editor for macOS 26 (Tahoe) and later. There is **no split preview pane**. A document is shown in one column through one of two **lenses**:

- **Rendered lens** (default) — WYSIWYG: headings, bold, lists, tables, code, math and images render in place and are edited directly.
- **Markdown lens** — the raw `.md` source in the same column, with syntax characters dimmed (not hidden).

A single toolbar toggle button (**MD**, ⌘/) crossfades between the lenses and keeps caret and scroll position. Formatting happens through a floating format bar that appears on text selection, plus a `/` slash insert menu (Notion/Medium style). Chrome is near-zero and **fades while typing**. Liquid Glass is used **only** on the floating control layer, never on the document page.

**Apple Intelligence** (on-device only) proofreads, rewrites and generates text, either for a selection or for the whole document. See the Apple Intelligence section.

The files are plain `.md` on disk. Markify supports both **single files** (open any `.md`, TextEdit-style) and a **library** of notes, shown together in one glass sidebar.

## About the design files
The files in this bundle are **design references built in HTML**: prototypes that show the intended look and behavior. They are not production code. Recreate them natively, preferably in **SwiftUI** targeting macOS 26 with the system Liquid Glass APIs, falling back to AppKit (`NSTextView` / TextKit 2) where the editor needs it. Open `Markdown Editor.dc.html` in a browser to see every state. Screen `1a` is interactive (⌘/, ⌃⌘S, typing fades the chrome).

## Fidelity
**High-fidelity.** Colors, type, spacing, radii, shadows and timings are final intent. Where the HTML imitates a system component (glass, toggles, popups, sliders, traffic lights), **use the real system component** instead of copying the CSS. The HTML values show how the result should read.

---

## Recommended architecture (non-binding)
- `DocumentGroup` + `FileDocument` (or `ReferenceFileDocument`) for `.md` files, so versions, autosave, iCloud, Recents and "— Edited" in the title come from the system.
- Editor core: **TextKit 2** (`NSTextView` wrapped in `NSViewRepresentable`) with a Markdown parser that keeps an AST with **source ranges**, e.g. swift-markdown (cmark-gfm) plus extensions for callouts, math and footnotes.
- **The Markdown source string is the single source of truth.** Both lenses are views over it:
  - The Markdown lens is the source string styled with attributes: syntax tokens dimmed, headings bold.
  - The Rendered lens is the same storage, but syntax tokens are hidden or collapsed and blocks (tables, code, math, images, task checkboxes, callouts) are drawn with custom `NSTextLayoutFragment`s / text attachments. Edits map back to source ranges.
  - This makes the lens toggle a re-style of the same text rather than a conversion, and it is what keeps the caret stable.
- Library: a folder, by default `~/Documents/Markify` or a user-chosen location, indexed for search. Open files and library notes share one sidebar list.

---

## Global window anatomy
- Window: standard titled window, full-size content view, transparent titlebar, no visible toolbar background. Corner radius follows the system (≈26px in the mock). Default size in the mock is 980×660. Minimum suggested size is 520×400.
- Page background: flat `page` token. No glass on the page.
- The **document column** is centered, **640px** wide (rendered) / **660px** (Markdown), top padding **96px**, bottom **90px**. Line width is user-adjustable in Settings.
- Floating control layer (all Liquid Glass, `.glassEffect()` capsules; group them in a `GlassEffectContainer` so they blend and morph):
  1. **Traffic lights**: system, at the top-left (22,22). They never fade.
  2. **Sidebar button**: 36×36 circle glass at left 88, top 10. Icon: `sidebar.left`. Selected (tinted) while the sidebar is open.
  3. **Title capsule**: 36px tall, padding 0 15px, at left 134, top 10. Content: document name in 13/600, then "— Edited" in secondary. It slides to left 282 when the sidebar opens (320ms, same curve as the sidebar). Clicking it opens the standard rename/move/versions title menu.
  4. **Right capsule** at right 12, top 10, 36px tall, 3px inner padding, containing:
     - **Apple Intelligence (✦)**: 30×30, SF Symbol `apple.intelligence` drawn in the system multicolor. Opens the whole-document panel (2e). Selected state uses an `accentSoft` background.
     - **MD toggle**: 30px tall, padding 0 13px, SF Mono 11.5/700, tracking .02em. **Off** = transparent background, primary ink. **On** (Markdown lens active) = filled accent with white text. Tooltip: "Show Markdown ⌘/". This is a toggle button (`Toggle` with `.toggleStyle(.button)`), not a segmented control.
     - **More (⋯)**: 30×30, `ellipsis`. Menu items: Share, Export (HTML/PDF), Find, Show Word Count, Settings.
  5. **Status capsule**: bottom-right (right 16, bottom 14), 28px tall, 11.5px secondary text: "1,284 words · Rendered" or "· Markdown". It can be hidden in Settings.
- All controls in 2–5 (not the traffic lights) sit in a layer that fades during typing (see Interactions).

---

## Screens / states (ids match the HTML)

### 1a — Rendered lens (live prototype)
The default writing state. Document content, in order:
1. **Frontmatter** renders as a quiet chip row, not as YAML. Chips are 11.5/500 SF Pro, padding 3×9, radius 999, `field` background, secondary ink (e.g. "essay", "editor"), followed by the date as plain text ("Sep 25, 2026"). 20px below. Clicking a chip edits the frontmatter inline in a small glass popover.
2. **H1**: prose font 36/700, line-height 1.15, tracking −0.01em, margin-bottom 18.
3. **Paragraph**: prose 18, line-height 1.65, `text-wrap: pretty` equivalent (avoid orphans), margin-bottom 16.
4. **Footnote reference**: superscript, SF Pro 11/600, accent color. Hover shows the footnote text in a glass popover.
5. **Callout** (`> [!NOTE]`): radius 14, padding 14×18, `callout` fill, SF Pro 15/1.55. Title "Note" is 13/600 in accent, 3px above the body. **No colored left border.** Types: NOTE (accent), TIP (green), WARNING (orange), IMPORTANT (purple); all use the same alpha recipe.
6. **H2**: prose 22/700, margin-bottom 12.
7. **Task list**: 17px, row gap 9. Checkbox 18×18 radius 6. Checked = accent fill with a white ✓ (SF Symbol `checkmark`, 11pt bold), and the label turns secondary with a strikethrough. Unchecked = 16×16 with a 1.5px `ink3` border. Clicking toggles `[ ]`/`[x]` in the source.
8. **Table**: SF Pro 14/1.4, radius 12, 1px `rule` outline, header row on the `field` fill with 12.5/600 secondary text, cells padded 9×14, 1px `rule` row separators. Columns come from the Markdown. Tab moves between cells, and Tab in the last cell adds a row.
9. **Code block**: radius 12, padding 16×18, `code` fill, SF Mono 13.5/1.75, whitespace preserved. Language label at the top-right (11/500 SF Pro, `ink3`). Syntax colors: keyword `kw`, type/property `typ`, literal `str`, comment `com`.
10. **Display math** (`$$…$$`): centered, italic serif 22px. Render with a native math renderer (e.g. SwiftMath / iosMath port) or MathJax-to-SVG. Inline `$…$` is also supported.
11. **Image**: full column width, radius 14, with the caption (alt text) below, centered in 13px secondary. Images can be dragged in and are copied to `./assets/` beside the file.
12. **Footnotes section**: 1px `rule` top border, 12px padding, SF Pro 13/1.5 secondary, with the number in accent 600.

### 1b — Markdown lens
- Same window, same controls, and the MD button is **on**.
- SF Mono 14, line-height 1.85, column 660, soft-wrapped.
- Syntax tokens (`#`, `**`, `>`, `- [x]`, `|`, backtick fences, `$$`, `![`, `](`, `---`) use `ink3`. Content stays `ink`, and bold/heading content is still drawn bold.
- Frontmatter keys use `typ`. Link/image URLs and `[^1]` use accent. Fenced code keeps syntax colors.
- **The caret stays on the same source offset, and the same logical block stays at the same y-position** (see Interactions).

### 1c — Selection → floating format bar
- Appears ~150ms after a non-empty selection settles, centered horizontally above the selection's first line with a 6–10px gap. If there is no room above, it flips below.
- Glass capsule, 38px tall, 3px padding, `glassStrong` background plus `popShadow`.
- Items, left to right:
  - **Writing Tools** (✦ + "Writing Tools", 13/600): opens the Writing Tools popover (2a). Hidden when Apple Intelligence is unavailable.
  - Divider
  - **Block style** menu ("Body ▾", see 1o)
  - Divider (1×18, `rule`)
  - **Bold** (active state: `accentSoft` background with accent glyph)
  - **Italic**
  - **Strikethrough**
  - **Inline code**
  - Divider
  - **Link**
  - **Comment** (optional; hide if comments are not in v1)
- Each icon button is 32×32 with circular hit targets.
- The bar dismisses on any keystroke that changes text, on collapsing the selection, or on Esc. Keyboard shortcuts work without the bar: ⌘B, ⌘I, ⌘⇧X, ⌘E, ⌘K.
- The same bar appears in the Markdown lens and wraps the selection with the matching syntax.

### 1o — Format bar → block style menu
- Clicking "Body ▾" opens a glass menu anchored 30px below the format bar, left-aligned with the chip.
  - Width 250, radius 18, padding 6, `glassStrong` + `popShadow`.
  - It must be a **sibling** of the format bar, not a child. A backdrop blur nested inside another backdrop-blur layer doesn't blur the page, so the text behind would show through.
- While the menu is open, the chip gets a `field` background.
- Section "Text" (11/600 secondary). Each row renders **in its own style** and shows its Markdown prefix right-aligned in SF Mono 12 secondary:
  - **Title**: serif 20/700, 38px row, `#`
  - **Heading**: serif 16/700, `##`
  - **Subheading**: serif 14/600, `###`
  - **Body**: serif 14, shortcut ⌥⌘0
  - **Quote**: serif italic 14, secondary, `>`
  - **Code block**: SF Mono 12.5, ````````
  - **Callout**: `> [!NOTE]`
- Divider, then section "Lists":
  - Bulleted `-`
  - Numbered `1.`
  - Task `- [ ]`
- Rows are 32px (unless noted) with radius 11. The current style is filled with accent, has white text and a leading ✓ in a 14px column; the other rows keep that column empty so labels align.
- Applies to every block touched by the selection. ↑↓/↩/Esc work, and typing filters.

### 1d — Slash insert menu
- Typing `/` at the start of an empty line (or after whitespace) opens a glass popover anchored under the caret, 310px wide, radius 18, padding 6.
- Header "Insert" (11/600 secondary). Rows are 36px tall with radius 11, each holding a 24×24 icon tile (radius 7, `field`), a label (13px), and the Markdown shortcut right-aligned in SF Mono 12 secondary. The shortcut teaches the syntax.
  - Table `| — |`
  - Task list `- [ ]`
  - Code block ```` ``` ````
  - Callout `> [!NOTE]`
  - Math `$$`
  - Image `![]()`
  - Also include: Heading 1–3, Bullet, Numbered, Quote, Divider, Footnote, Frontmatter.
- The query after `/` filters rows with fuzzy matching. The selected row is filled with accent and has white text.
- Footer: "↑↓ navigate" on the left, "↩ insert · esc dismiss" on the right (11px secondary), above a 1px divider.
- Esc or a space with no match closes the menu and leaves the typed text.

### 1e — Find & Replace (⌘F / ⌥⌘F), shown in dark
- Glass panel docked under the right toolbar capsule (top 56, right 12), 380px wide, radius 18, padding 8, with two rows (gap 6):
  1. Find field (30px tall, radius 9, `field` fill, 2px `accentSoft` focus ring) with the query and "1 of 4" (11.5 secondary). Then ‹ › buttons and an **Aa** button for match case.
  2. Replace field, then a **Replace** button (`field` fill) and an **All** button (accent fill, white).
- Matches are highlighted in the text with `hl`. The current match uses `hlCur`. Both highlights have radius 3.
- Works in both lenses. In the Rendered lens, find matches visible text and never syntax characters.

### 1f — Library sidebar (⌃⌘S), shown in dark
- **The sidebar overlays the page and does not push it.** It is a glass panel inset 8px from the window edges, 260px wide, radius 20, with top padding 54 so the traffic lights sit inside it.
- It slides in from x −290 to 0 over 320ms with `cubic-bezier(.2,.8,.2,1)`. The title capsule slides with it.
- Contents:
  - Search field (30px, radius 10)
  - **Open Files** section: files opened from anywhere, with the file name (13/600 when selected) and a path subtitle (11.5 secondary)
  - **Library** section: notes with the title plus a first-line preview (11.5 secondary)
  - A spacer, then "New Document ⌘N" at the bottom
- The selected row uses `rowSel`, radius 10, padding 7×10. Section headers are 11/600 secondary.
- Clicking outside the sidebar or pressing Esc closes it. A pinned mode (⌥-click the sidebar button) is optional for v2.

### 1g — Typing (chrome faded), shown in dark
- After the first character key press, every floating control except the traffic lights fades to opacity 0 over **400ms ease**. This includes the sidebar button, title, MD/⋯ capsule and status capsule.
- Moving the pointer, pressing ⌘ shortcuts, or hovering the top 60px brings them back (400ms).
- Faded controls ignore hit-testing, apart from the hover zone.
- The fade can be turned off in Settings ("Fade toolbar while typing").

### 1h — New document (empty)
- The caret sits before a placeholder H1 "Untitled" (36/700, `ink3`), with "Start writing, or type / to insert a block." below it (18px, `ink3`).
- A hint row is centered 26px from the bottom (12px, `ink3`, gap 18): "⌘/ Markdown", "⌃⌘S Library", "⌘O Open file". It disappears after the first keystroke and never returns for that document.
- The placeholders are not part of the text storage. The first typed line becomes the H1 and suggests the file name.

### 1i — Scrolled document
Shows the lower blocks: code, math, image placeholder, caption and footnotes. The styles are specified in 1a.

### 1j–1l — Lens toggle transition
- Three frames, at 0ms, 120ms (both lenses at 50% opacity) and 240ms.
- It is a **crossfade in place**: `opacity` 1↔0 over **240ms ease**, with no movement, scaling or sliding.
- Before the fade, the app records the caret's source offset and the source range of the top visible block with its y-offset. After the swap, it restores both, so the anchor block sits at the same y.
- Honor Reduce Motion by using an instant swap.

### 1n — Settings (⌘,)
Standard SwiftUI `Settings` scene, 780px wide.
- **Tabs**: General, Editor, Appearance, Intelligence, Shortcuts. Each tab button is 80px wide with radius 14; the selected tab uses an `accentSoft` fill and accent text. The window title shows the tab name.
- SF Symbols per tab: `gearshape`, `character.cursor.ibeam`, `circle.lefthalf.filled`, `apple.intelligence`, `keyboard`.
- Layout: `Form` + `.formStyle(.grouped)`, 28px side padding, 18px between groups. Rows have 11×14 padding and 1px `rgba(0,0,0,.07)` separators; subtitles are 11.5 secondary.

**General**
- *Documents*
  - New documents are saved to [Library ▾ / Ask each time]
  - Library location, subtitle "~/Documents/Markify · 128 notes", with a [Choose…] button
  - Save pasted images to [./assets ▾]
  - Reload when changed on disk (on), subtitle "Picks up edits made in other apps or by Git."
- *Startup*
  - On launch [Reopen last documents ▾ / New document / Library]
  - Default Markdown app, with a [Make Default] button

**Editor**
- *Lenses*
  - Open documents in [Rendered / Markdown / Last used]
  - Remember lens per document (on)
  - Reveal syntax on the current line (off; v2)
- *Typography*
  - Prose font [New York ▾]
  - Markdown font [SF Mono ▾]
  - Line width slider, Narrow (560) to Wide (860), default 640
- *Window*
  - Fade toolbar while typing (on)
  - Show word count (on)

**Appearance**
- *Appearance*
  - Theme: three 78×50 thumbnails for Light, Dark and Auto. The selected one gets a 3px accent ring and a 600-weight label.
  - Page color [Paper ▾ / White / System]
  - Code theme [Match appearance ▾]
- *Controls*
  - Glass style: segmented [System | Clear | Tinted]. Default is System, which follows the macOS 26 system setting.
  - Accent color: 16px swatches (Multicolor = follow system, plus Blue, Purple, Pink, Orange, Green, Graphite). The selected swatch gets a 2px white + 1.5px accent ring.
  - Show status capsule (on)

**Intelligence**
- *Status card*:
  - 36px multicolor tile with ✦
  - "Apple Intelligence is on" (600)
  - Subtitle "On-device model ready. Markify never sends your text off this Mac."
  - [System Settings…] button
  - The card changes for unavailable states (see the Apple Intelligence section).
- *Features*
  - Writing Tools in the format bar (on)
  - Generate at caret with ⌘↩ (on), subtitle "Also available as /write in the insert menu."
  - Suggest title & tags for new documents (off), subtitle "Written to frontmatter only after you accept."
- *Generation*
  - Default tone [Match document ▾ / Friendly / Professional / Concise]
  - Use surrounding section as context (on)

**Shortcuts**
- Header hint: "Double-click a shortcut to change it". Keycaps are padded 2×8, radius 6, on the `field` fill with an inset 1px bottom shadow, 12.5px.
- *Editor*: ⌘/, ⌃⌘S, /, ⌘F, ⌥⌘F
- *Formatting*: ⌘B, ⌘I, ⇧⌘X, ⌘E, ⌘K, ⌥⌘1–3
- *Apple Intelligence*: ⇧⌘W (Writing Tools), ⌘↩ (generate/continue)
- [Restore Defaults] button, right-aligned

---

## Apple Intelligence (section 2 in the HTML)
**Constraint: local models only.** Nothing is sent to a server.
- **Proofread, Rewrite, tones and transforms** use the system **Writing Tools**: `NSTextView.writingToolsBehavior = .complete` with `allowedWritingToolsResultOptions = [.plainText, .richText, .table, .list]`. Present them from our own button with `showWritingTools(_:)`.
- **Generation** (compose, continue, summarize-and-insert, title/tag suggestions) uses the on-device **Foundation Models** framework (`LanguageModelSession`, `SystemLanguageModel.default`), streaming with `streamResponse`. Use guided generation (`@Generable`) for structured output such as frontmatter tags.
- Never offer cloud/ChatGPT extensions from Markify UI.
- Check `SystemLanguageModel.default.availability` and handle these cases:
  - `.available`: normal UI
  - `.unavailable(.appleIntelligenceNotEnabled)`: the ✦ entries stay visible and open a card with "Turn on Apple Intelligence in System Settings"
  - `.modelNotReady`: the card shows "Preparing on-device model…" with a progress indicator; actions are disabled
  - `.deviceNotEligible`: all ✦ entry points are hidden
- **Visual language**: the ✦ glyph and the "AI edge" (a 1.5px border in the multicolor gradient `#FF9F0A → #FF375F → #BF5AF2 → #0A84FF` with a soft `aiGlow` shadow) appear **only** on AI entry points and on text AI is changing or just changed. In production, use the `apple.intelligence` SF Symbol and the system glow if available.
- Every AI change is a single undo step and is never saved until it is accepted or the user keeps typing.

### 2a — Selection → Writing Tools popover
- The format bar has "✦ Writing Tools" as its first item. Its popover opens 30px below the selection, 340px wide, radius 20, padding 8, gap 6.
- Contents, top to bottom:
  1. "Describe your change" field: 36px, radius 12, `field` fill, ✦ on the left, ↩ on the right
  2. Two tiles, **Proofread** and **Rewrite** (padding 10×12, radius 12, accent glyph above a 600 label)
  3. Three tone buttons, **Friendly**, **Professional** and **Concise** (32px, radius 10)
  4. Divider
  5. A 2×2 grid of **Summary**, **Key Points**, **List** and **Table** (30px rows)
  6. Footer (11px secondary): "On this Mac" on the left, "Selection · N words" on the right

### 2b — Proofread
- Suggestions are underlined in place: a 2px accent underline with a 5px offset. The current suggestion also gets an `accentSoft` background.
- Suggestion card: 250px wide, radius 16, anchored below the word. It shows the category (Spelling / Grammar / Style), then "old → **new**" in the prose font with the old word struck through, then [Accept] (accent) and [Ignore].
- Bottom-center glass capsule (40px): "✦ Proofread · 3 suggestions | ‹ 1 of 3 › | Accept All | [Done]". Tab/⇧Tab step through suggestions and ↩ accepts.
- Scope: the selection, or the whole document when started from 2e.

### 2c — Rewrite result
- The rewritten text replaces the original in place, wrapped in the AI edge (radius 14, padding 8×14, outset −14px horizontally).
- A review capsule sits below it (38px): "✦ Rewrite · Concise | Try Again | Compare | Revert | [Accept ⌘↩]".
- **Compare** toggles the original on and off. Esc reverts. Typing outside the block accepts.

### 2d — Generate at caret
- ⌘↩ on an empty line, or `/write`, opens an inline composer in the column. It has the AI edge, radius 16 and padding 12×14.
  - Prompt line: ✦, the prompt text and an "esc" hint
  - Option chips (24px): Length, Tone, Format
  - Status "Writing on this Mac…" and a [Stop] button
- Output streams directly below in secondary ink, ending in a 9×19 gradient caret block. When it finishes, the capsule becomes [Keep ⌘↩] [Try Again] [Discard]. Kept text turns primary.

### 2e — Whole-document panel
- The toolbar ✦ opens a glass panel under the right capsule (top 56, right 12), 320px wide, radius 20.
- Contents:
  - Header "✦ Apple Intelligence" plus a "Whole document" chip
  - "Describe a change to the document…" field
  - **Proofread** and **Rewrite…** tiles
  - Rows (32px, detail right-aligned in 11.5 secondary):
    - Summarize, "Insert at top"
    - Key points, "New section"
    - Suggest title & tags, "Frontmatter"
    - Continue writing, "At caret · ⌘↩"
  - Footer: "Runs on this Mac with Apple Intelligence. Your text never leaves it."
- In the Markdown lens, AI results apply to the source as Markdown. Rewrite and Proofread edit only the text, never the syntax tokens.

## Interactions & behavior

| Action | Shortcut | Behavior |
|---|---|---|
| Toggle lens | ⌘/ or MD button | 240ms crossfade. Caret and scroll anchor preserved. Chrome re-shown. |
| Toggle library | ⌃⌘S or sidebar button | Overlay slide, 320ms `cubic-bezier(.2,.8,.2,1)` |
| Find / Replace | ⌘F / ⌥⌘F, ⌘G / ⇧⌘G | Glass find panel |
| Insert block | `/` | Slash menu |
| Format | ⌘B ⌘I ⌘⇧X ⌘E ⌘K | Also through the floating bar |
| New / Open | ⌘N / ⌘O | System document behavior |
| Settings | ⌘, | Settings scene |
| Writing Tools | ⇧⌘W or ✦ in the format bar | Popover for the selection (2a) |
| Generate / continue | ⌘↩ or `/write` | Inline composer (2d) |
| Document AI | ✦ in the toolbar | Panel (2e) |
| Block style | ⌥⌘0–3 or "Body ▾" | 1o menu |
| Chrome fade | any text key | 400ms fade out. Pointer move brings it back. |

**Markdown shortcuts in the Rendered lens** (autoformat as you type): `# ` through `###### `, `- `, `* `, `1. `, `- [ ] `, `> `, ```` ``` ```` + language + ↩, `---` + ↩, `$$` + ↩, `**x**`, `_x_`, `` `x` ``, `~~x~~`, and `[text](url)`. ⌘Z undoes the autoformat first and keeps the typed characters.

**Transitions summary**
- Lens crossfade: opacity, 240ms, ease
- Chrome fade: opacity, 400ms, ease
- Sidebar and title slide: transform / x, 320ms, `cubic-bezier(.2,.8,.2,1)`
- MD button state: background and color, 200ms
- Popovers (format bar, slash, find): use the system glass appear animation, or a 150ms fade plus a 0.98→1 scale

**Accessibility**
- Every floating control has an accessibility label, e.g. "Show Markdown, toggle, off".
- Respect Reduce Transparency: glass becomes an opaque `windowBackgroundColor`-like fill.
- Respect Reduce Motion (instant swaps) and Increase Contrast (stronger `rule` and `ink3`).
- Dynamic Type isn't a macOS thing, but the prose size should follow the ⌘+ / ⌘− zoom (range 14–26px).
- Hit targets are at least 28pt; the mock uses 30–36.

---

## State

```swift
enum Lens { case rendered, markdown }
struct EditorState {
  var lens: Lens = .rendered          // persisted per document when "Remember lens" is on
  var isSidebarOpen = false
  var isChromeVisible = true          // false after a text key; true on pointer move, shortcut or lens toggle
  var selection: NSRange              // in SOURCE coordinates, in both lenses
  var scrollAnchor: (blockSourceRange: NSRange, yOffset: CGFloat)
  var formatBar: FormatBarState?      // non-nil while a selection is settled
  var slashMenu: SlashMenuState?      // query, filtered items, highlighted index
  var find: FindState?                // query, replacement, matchCase, matches, currentIndex
  var blockMenuOpen = false
  var ai: AIState?                    // .writingTools(range) | .proofread(suggestions, index) | .rewrite(original, result, tone) | .generating(prompt, partial) | .docPanel
  var aiAvailability: SystemLanguageModel.Availability
}
```
- The per-document lens is stored in an extended attribute (`com.markify.lens`) so the `.md` file stays clean.
- The library index holds the file URL, title (first H1 or file name), first-line preview, modified date and frontmatter tags.

---

## Design tokens

### Color: light
| Token | Value | Use |
|---|---|---|
| page | `#FCFBF9` | document background |
| ink | `#1D1D1F` | primary text |
| ink2 | `#6E6E73` | secondary text, labels |
| ink3 | `#B3B3B8` | syntax tokens, placeholders |
| rule | `rgba(0,0,0,.09)` | dividers, table lines |
| field | `rgba(0,0,0,.05)` | chips, fields, table header, icon tiles |
| rowSel | `rgba(0,0,0,.07)` | sidebar selection |
| accent | `#0A64D6` | system accent (use `Color.accentColor`) |
| accentSoft | `rgba(10,100,214,.13)` | active tool, focus ring |
| sel | `rgba(10,100,214,.20)` | text selection (use system) |
| callout | `rgba(10,100,214,.07)` | NOTE callout fill |
| code | `#F3F1ED` | code block fill |
| hl / hlCur | `rgba(255,214,10,.40)` / `rgba(255,159,10,.70)` | find matches |
| kw / typ / str / com | `#AD3DA4` / `#3F6E74` / `#C41A16` / `#8A8F96` | syntax |
| ai | `linear-gradient(90deg,#FF9F0A,#FF375F,#BF5AF2,#0A84FF)` | AI edge, ✦ glyph |
| aiGlow | `rgba(191,90,242,.13)` | AI edge shadow |

### Color: dark
| Token | Value |
|---|---|
| page | `#1E1E20` |
| ink / ink2 / ink3 | `#F2F2F7` / `#A1A1A6` / `#5C5C61` |
| rule | `rgba(255,255,255,.12)` |
| field / rowSel | `rgba(255,255,255,.08)` / `rgba(255,255,255,.14)` |
| accent / accentSoft | `#3D8BFF` / `rgba(61,139,255,.22)` |
| sel / callout | `rgba(61,139,255,.38)` / `rgba(61,139,255,.14)` |
| code | `#2A2A2D` |
| hl / hlCur | `rgba(255,214,10,.30)` / `rgba(255,159,10,.65)` |
| kw / typ / str / com | `#FF7AB2` / `#78C2B3` / `#D9C97C` / `#7F8C98` |
| ai / aiGlow | same gradient / `rgba(191,90,242,.22)` |

### Glass (reference only; use `.glassEffect(.regular)` / `.regular.interactive()`)
- Light capsule: `rgba(255,255,255,.62)` + blur 20 + saturate 180%. Edge: `0 0 0 .5px rgba(0,0,0,.09), 0 6px 20px rgba(0,0,0,.08), inset 0 1px 0 rgba(255,255,255,.95)`
- Light popover (glassStrong): `rgba(255,255,255,.78)` + blur 28. Shadow: `0 0 0 .5px rgba(0,0,0,.1), 0 18px 50px rgba(0,0,0,.16), inset 0 1px 0 #fff`
- Dark capsule: `rgba(62,62,70,.55)`. Dark popover: `rgba(50,50,56,.78)`. Edge: `0 0 0 .5px rgba(255,255,255,.14), 0 6px 20px rgba(0,0,0,.3), inset 0 1px 0 rgba(255,255,255,.1)`

### Typography
- Prose: **New York** (`Font.system(.body, design: .serif)`), with SF Pro as an option
- UI: **SF Pro** (system)
- Markdown and code: **SF Mono** (`design: .monospaced`)

| Role | Size / weight / line-height |
|---|---|
| H1 | 36 / 700 / 1.15, tracking −0.01em |
| H2 | 22 / 700 |
| H3 | 19 / 700 (not shown) |
| Body | 18 / 400 / 1.65 |
| Task item | 17 |
| Callout body | SF Pro 15 / 1.55 |
| Table | SF Pro 14 / 1.4, header 12.5 / 600 |
| Code block | SF Mono 13.5 / 1.75 |
| Markdown lens | SF Mono 14 / 1.85, H1 line 16 / 700 |
| UI | 13 regular, 13 / 600 titles, 11–11.5 captions and section headers |

### Spacing, radii, sizes
- Spacing scale: 2 · 4 · 6 · 8 · 10 · 12 · 14 · 16 · 18 · 22 · 26 · 28 · 36
- Radii:
  - Window: system (≈26)
  - Capsules: 999
  - Sidebar: 20
  - Popovers: 18
  - Callout and image: 14
  - Table and code: 12
  - Menu rows: 11
  - Sidebar rows and search: 10
  - Find fields: 9
  - Icon tiles: 7
  - Checkbox: 6
- Control heights:
  - Toolbar capsules: 36 (inner buttons 30)
  - Format bar: 38 (buttons 32)
  - Menu rows: 36
  - Fields: 30
  - Status capsule: 28

## Assets
- No bitmap assets. Every icon is an **SF Symbol**, and the HTML glyphs are stand-ins:
  - `sidebar.left`, `ellipsis`, `bold`, `italic`, `strikethrough`, `chevron.left.forwardslash.chevron.right`, `link`, `text.bubble`
  - `tablecells`, `checklist`, `curlybraces`, `info.circle`, `sum`, `photo`, `magnifyingglass`, `chevron.left`/`right`, `textformat`, `square.and.pencil`
- The hero image in the sample document is a placeholder.
- Sample copy (the "One Page, Two Lenses" document) is in the HTML. Use it as the bundled Welcome document.

## Files
- `Markdown Editor.dc.html`: all screens. Open it in a browser alongside `support.js`.
  - Section 2 (top): 2a Writing Tools, 2b proofread, 2c rewrite (dark), 2d generate, 2e document AI (dark).
  - Section 1 screen ids: 1a live, 1b Markdown lens, 1c format bar, 1o block style menu, 1d slash menu, 1e find (dark), 1f library (dark), 1g typing (dark), 1h empty, 1i scrolled, 1j–1l transition, 1n settings (all 5 tabs clickable).
  - Theme tokens are in `theme()` in the script block. Screen configurations are in `cfgs` (section 1) and `cfgs2` (section 2).

## Out of scope for v1 (suggestions)
- Hybrid "reveal syntax on current line" mode
- Comments
- Pinned sidebar
- Export themes
- iCloud library sync UI beyond the system defaults
