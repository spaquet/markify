# AGENTS.md

This file provides guidance to AI coding agents working in this repository.

## Project Overview

Markify is a macOS 26 Markdown editor built with SwiftUI and TextKit 2. There is no split preview: one column shows the document through two lenses over the same text storage — a Rendered lens and a Markdown lens (⌘/). Formatting happens through a floating format bar and a `/` slash menu; a library sidebar lists open files and library notes. The binding design is in [design/README.md](design/README.md) and `design/Markdown Editor.dc.html`; decisions that fill its gaps are in [DECISIONS.md](DECISIONS.md).

The app uses the document-based pattern (`DocumentGroup` with a `FileDocument`). It opens `.md` and `.markdown`, and `.mdx` as Markdown with MDX blocks kept as written.

## Build & Development Commands

### Building and Running

```bash
# Build the app for Release
xcodebuild -project Markify.xcodeproj -scheme Markify -configuration Release build

# Build for Debug
xcodebuild -project Markify.xcodeproj -scheme Markify -configuration Debug build

# Run the app from Xcode
open Markify.xcodeproj
```

### Testing

```bash
# Markdown model tests (fast, no Xcode app needed)
swift test --package-path MarkifyMarkdown

# OKF library tests (fast, no Xcode app needed)
swift test --package-path OKFKit

# Run all tests
xcodebuild -project Markify.xcodeproj -scheme Markify test

# Run specific test target
xcodebuild -project Markify.xcodeproj -scheme Markify -only-testing MarkifyTests test

# Run UI tests
xcodebuild -project Markify.xcodeproj -scheme Markify -only-testing MarkifyUITests test
```

## Architecture & Key Components

### Packages

- **MarkifyMarkdown** (local): `MarkdownModel` parses the source once with swift-markdown (cmark-gfm) and exposes typed spans — content and marker ranges in UTF-16 source offsets — plus tables and lists. Markify's extensions that cmark does not know (frontmatter, `$$`/`$…$` math, footnotes, GitHub callouts, MDX blocks) are found first and masked with same-length whitespace, so cmark never misreads them and every offset still points into the original text. `MarkdownSourceMap` converts cmark locations to offsets. UI-free.
- **OKFKit** (local): Open Knowledge Format model, bundle scan, validator and text-splice editing. See `OKF.md`.
- **swift-markdown**, **SwaTex** (math rendering, no WebView), **Sparkle** (updates).

### App files (`Markify/`)

- **MarkifyApp.swift**: `@main`, `DocumentGroup`, launch behavior (reopen documents, Welcome, library).
- **MarkifyDocument.swift**: `FileDocument` reading and writing UTF-8 text; the source string is never converted.
- **ContentView.swift**: the window — floating controls, format bar, block menu, slash menu (`SlashEntry`), find, library sidebar, Apple Intelligence flows, export.
- **NativeEditor.swift**: `NativeEditor` (`NSViewRepresentable`) and `MarkdownTextView` (TextKit 2 `NSTextView`).
  - `NativeEditor.style(_:)` styles both lenses from the cached `MarkdownModel`: fonts first, then inline traits, then markers (dimmed in the Markdown lens, hidden in the Rendered lens), then paragraph layout.
  - `MarkdownTextView` handles clicks, ⌘-click links and footnotes, drops, paste, list continuation and table editing, supplies images, math and diagram renders to its fragments, and keeps table cell fields as subviews.
  - `MarkdownList` and `MarkdownTable` keep list renumbering and table navigation, built from the model.
- **MarkdownLayoutFragment.swift**: `MarkdownLayoutFragment`, the `NSTextLayoutFragment` every paragraph lays out as, and the rendering attribute keys. It draws what text attributes cannot — bullets, list numbers, checkboxes, rounded code and callout boxes, and (through `MarkdownTextView.drawDecorations(anchoredIn:)`) images, math, diagrams, callout titles, code labels, the footnotes rule and chips — so decorations move with the text through layout, scrolling and resizing.
- **Mermaid.swift**: `MermaidRenderer`, one offscreen `WKWebView` running the bundled Mermaid (`Resources/Mermaid`) with no network access.
- **Knowledge.swift**: the OKF app layer — link following, log/index writes, the knowledge sidebar section.
- **Updates.swift**: Sparkle's `SPUStandardUpdaterController` (not started under tests) and the Check for Updates… button. Feed and key are in Info.plist; see RELEASE.md.
- **Theme.swift**: `EditorTheme` fonts and colors. New York is a system design (`withDesign(.serif)`), not a font name.
- **Shortcuts.swift**, **Settings/Views/SettingsView.swift**, **Help/**, **Resources/**.

### Key Design Patterns

1. **Source is the authority.** Both lenses style one text storage; nothing converts the Markdown. Selection offsets and undo stay in source coordinates, and every style pass must leave `editor.string` unchanged.
2. **One parse per text version.** `MarkdownTextView.model` caches `MarkdownModel` by string; styling, drawing, clicks and list/table editing read it instead of scanning with regular expressions. Follow CommonMark/GFM as cmark reads it.
3. **Decorations belong to layout fragments.** `style()` marks what to draw with Markify rendering attributes (`.markifyBullet`, `.markifyTaskBox`, `.markifyBlockFill`, …) or the decoration's anchor character; the fragment that lays out that text draws it. Drawing and hit-testing share geometry functions (e.g. `MarkdownLayoutFragment.checkboxRect`). Never position drawing from `firstRect(forCharacterRange:)`: it answers only inside the viewport; use `MarkdownTextView.textRect` for views such as table cells.
4. **Hidden markers take no room.** A hidden marker uses a 1pt clear font and kerns each character by its own advance; TextKit caps a negative kern near its glyph's advance, and a kern on the last character of a run is only partly applied.
5. **Relative paths.** Images and note links use paths relative to the document (bundle-absolute `/…` inside an OKF bundle), falling back to absolute paths for unsaved documents.

## Key Implementation Details

- **Images**: drops and pastes copy into the Settings folder beside the document (default `./assets`) and insert a percent-encoded relative path; `MarkdownTextView.imageURL` decodes it. Remote images load through `RemoteImages` when Settings › Load remote images is on. Images alone on a line draw full width; inline images draw as a chip that previews on hover.
- **Links**: ⌘-click follows links in both lenses (`Knowledge.follow`). Dropping a note from the sidebar or Finder inserts `[title](path)` (`MarkdownTextView.noteLink`).
- **Footnotes**: references show their text in a tooltip; ⌘-click jumps between a reference and its definition.
- **Mermaid**: fenced `mermaid` blocks render as diagrams in the Rendered lens; failures show the source with Mermaid's message.

## Testing Notes

Tests use Swift Testing, not XCTest.

- `MarkifyMarkdown/Tests`: model spans over the shared fixture and edge cases.
- `MarkifyTests/LayoutFragmentTests.swift`: fragments are installed, `style()` sets rendering attributes, and pixel tests render fragments into a bitmap to check what they draw.
- `MarkifyTests/EditorFixtureTests.swift`: golden styling probes for both lenses over `MarkifyTests/Fixtures/editor-fixture.md`, layout checks that hidden markers take no room, and a performance guard. When styling changes on purpose, update the golden entry and say why in the commit.
- `MarkifyTests/MarkifyTests.swift`, `MermaidTests.swift`: editing behavior, lists, tables, slash menu, links, footnotes, OKF and Mermaid rendering.

## Common Workflows

**Supporting new Markdown syntax**: add a `MarkdownModel.Kind` (from a cmark node in the walker, or as a masked extension), cover it in `MarkdownModelTests`, then style it in `NativeEditor.style(_:)`. If it needs drawing, mark it with a rendering attribute and draw it in `MarkdownLayoutFragment` (or anchor it in `MarkdownTextView.decorationAnchors` and draw it in `drawDecorations(anchoredIn:)`), with a pixel test in `LayoutFragmentTests`. Add a fixture probe for both lenses.

**Adding slash menu entries**: add to `SlashEntry.all` in ContentView.swift and, if the caret should land inside the insertion, to the caret table in `SlashEntry.apply`.

**Modifying Document I/O**: changes to reading and writing belong in `MarkifyDocument`.
