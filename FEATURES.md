# Implemented features

This is an inventory of features in the current Markify source tree. See the [user guide](help/index.md) for instructions and the [OKF guide](OKF.md) for knowledge bundle details.

## Documents and editing

- Open and save `.md`, `.markdown` and `.mdx` files as plain UTF-8 text. macOS document autosave, recent files, rename, move and version browsing are available.
- Create new documents in a chosen library folder or choose a location each time. Reopen previous documents, start a new document or show the library at launch.
- Edit the same source through two lenses: **Rendered** shows formatting in place; **Markdown** shows source with syntax dimmed. Switch with ⌘/ while keeping the caret, selection, scroll position and undo history.
- Select a default lens or the last used lens, and optionally remember the lens for each document.
- Use a floating format bar for block styles, bold, italic, strikethrough, inline code and links; use keyboard shortcuts for the same actions.
- Type `/` at the start of a line to insert or filter block templates: table, task list, code block, callout, display or inline math, Mermaid diagram, image, headings, bullet or numbered list, quote, divider, footnote, frontmatter, OKF concept or AI-generated text.
- Continue lists with Return, end an empty list with Return, renumber ordered lists after edits and toggle task checkboxes by clicking them.
- Edit rendered table cells with Tab and Shift-Tab; add a row by tabbing from the last cell. Insert and delete rows or columns through the context menu or keyboard shortcuts.
- Find and replace text, move between matches and match case. In the Rendered lens, Find searches visible words across hidden Markdown markers.
- Zoom text, show or hide the word count, and customize most keyboard shortcuts.

## Markdown rendering

- CommonMark and GitHub Flavored Markdown: headings, emphasis, strikethrough, links, images, blockquotes, nested lists, task lists, fenced and indented code, pipe tables, dividers, escapes and HTML kept as source.
- Syntax coloring for fenced code blocks with a language name.
- GitHub-style `NOTE`, `TIP`, `IMPORTANT` and `WARNING` callouts.
- Inline `$…$` and display `$$…$$` LaTeX math, typeset locally and editable at the formula.
- Footnote references and definitions, with hover text and ⌘-click navigation in both directions.
- Offline Mermaid diagram rendering from fenced `mermaid` blocks, with source and error text shown when rendering fails.
- YAML frontmatter, with `title`, `tags` and `date` reflected in the document UI.
- MDX `import`/`export` lines and JSX blocks preserved as written and dimmed in `.mdx` files.

## Files, images and links

- Paste or drop images into a configurable folder beside the document and insert relative Markdown image paths. Full-line images render at page width; inline images appear as chips with hover previews.
- Optionally load remote images. Open web links in the browser and Markdown file links in Markify with ⌘-click.
- Drag notes from Finder or the library into a document to insert relative links.
- Open a folder into the Library sidebar; browse its subfolders and all `.md`, `.markdown` and `.mdx` notes, create a document in any subfolder, and filter by title, folder path or text preview.
- Share the original Markdown file through the macOS share sheet.

## Open Knowledge Format (OKF)

- Open an OKF bundle folder, remember access across launches and browse concepts by folder, type or tag. Bundle changes on disk refresh the sidebar.
- Read concept frontmatter, provenance, status, staleness and trust signals. Show backlinks and validation issues without blocking access to a bundle.
- Follow bundle-relative and bundle-root links; complete concept paths while typing Markdown links.
- Insert a concept template; make a note a concept; mark it verified; change its status; add log entries; and rebuild an index.
- Offer to update links across the bundle when a concept is renamed or moved. Preserve unrelated YAML fields and formatting when editing concept metadata.
- Record human or Apple Intelligence edits in a concept's `generated` metadata when the corresponding setting is enabled.
- Read OKF v0.1 conventions and newer bundle versions on a best-effort basis; display Attested Computation fields without executing them.

## Apple Intelligence

- Use system Writing Tools on a selection to proofread, rewrite, change tone, summarize or reorganize it.
- Describe a custom change to a selection or whole document; summarize a document, add key points, suggest frontmatter metadata or continue writing.
- Generate text at the caret, preview streamed output and keep or discard it. Compare, retry, revert or accept rewrites; accepted changes can be undone.
- Choose a default tone and section context, and turn individual Intelligence entry points on or off. These features require an eligible Mac with Apple Intelligence enabled.

## Export, appearance and app

- Export a self-contained HTML page with local images embedded, math and Mermaid as SVG, syntax-colored code, working local links, frontmatter metadata and light/dark styling.
- Export a paginated PDF of that page with clickable links and page-break handling for headings, tables, code, callouts, math and images.
- Preview `.md`, `.markdown` and `.mdx` files in Finder with Space using a formatted Quick Look extension. Local images, math and Mermaid render in the preview; MDX code stays readable.
- Customize fonts, line width, page color, code theme, app appearance, accent, floating control style and status capsule. Optionally fade the toolbar while typing.
- Make Markify the default Markdown app; use the built-in Welcome tour and Help Book; check for signed updates automatically or on demand.

## Command line

- Run the bundled `markify` executable from Terminal without opening an editor window; `--help` lists commands and exit status.
- Validate an OKF bundle with `markify check BUNDLE`, showing file paths and severity for each finding. Error findings fail the command; warnings and information do not.
- Export a `.md`, `.markdown` or `.mdx` file to a self-contained HTML page with `markify export FILE --html --output OUTPUT`, embedding local images and adjusting local links for the destination.
