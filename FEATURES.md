# Implemented features

This is an inventory of features in the current Markify source tree. See the [user guide](help/index.md) for instructions and the [OKF guide](OKF.md) for knowledge bundle details.

## Documents and editing

- Open and save `.md`, `.markdown` and `.mdx` files as plain UTF-8 text. macOS document autosave, recent files, rename, move and version browsing are available.
- Recover saved Markdown text with native macOS Versions through File › Revert To › Browse All Versions… or the title menu; restore an earlier version or restore a copy with Option. macOS manages history storage and checkpoints; linked assets are not versioned with the text. External-change prompts pause during version browsing.
- Detect external file edits and offer Keep My Changes, Reload or Merge. Reload reads the latest disk contents; Merge preserves independent changes and marks overlapping edits, with undo support.
- Open public HTTPS Markdown files with File › Open URL…, including GitHub and GitLab file-page URLs. Browse and search Markdown files on a public repository’s default branch, then open a file as an unsaved local copy. Downloads reject redirects to HTTP, credentials, HTML responses and files larger than 10 MB; authentication is not supported.
- Keep a web document’s source URL available through More › Source, and resolve relative links, images and exports against its fetched web location for the current document session. Saving writes only the Markdown text; reopening the local copy uses its local folder.
- Create new documents in a chosen library folder or choose a location each time. Reopen previous documents, start a new document or show the library at launch.
- Open Markdown text as an editable, untitled document in the Rendered lens. Untouched reports close without a save prompt; edits receive normal save protection. Create one from the clipboard with File › New from Clipboard (⌃⌥⌘V).
- Edit the same source through two lenses: **Rendered** shows formatting in place; **Markdown** shows source with syntax dimmed. Switch with ⌘/ while keeping the caret, selection, scroll position and undo history.
- Select a default lens or the last used lens, and optionally remember the lens for each document.
- Use a floating format bar for block styles, bold, italic, strikethrough, inline code and links; use keyboard shortcuts for the same actions.
- Type `/` at the start of a line to insert or filter block templates: table, task list, code block, callout, display or inline math, Mermaid diagram, image, headings, bullet or numbered list, quote, divider, footnote, frontmatter, OKF concept or AI-generated text.
- Continue lists with Return, end an empty list with Return, renumber ordered lists after edits and toggle task checkboxes by clicking them.
- Edit rendered table cells with Tab and Shift-Tab; add a row by tabbing from the last cell. Insert and delete rows or columns through the context menu or keyboard shortcuts.
- Show a Contents outline in the right pane: headings (including setext headings) at H1, H2, H3 or all levels, in document order, with collapsible sections, a filter and a reading-position marker. Click a heading to jump to it.
- Insert a table of contents at the caret with **Insert Table of Contents**; it lists the headings at the chosen depth as links between `<!-- toc -->` and `<!-- /toc -->` markers and updates itself a moment after headings change. The button then reads **Update Table of Contents**. Exported HTML and PDF show it as a card.
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
- Open the right Links panel to browse each resolved destination once, with source line numbers that update as you edit. Jump to an occurrence, open its destination, and request an Apple Intelligence summary of a local Markdown file or web page. Summaries and error messages support partial selection and copying. Summaries persist outside the document and show when a local target changes.
- Open a folder into the Library sidebar; browse its subfolders and all `.md`, `.markdown` and `.mdx` notes, create a document in any subfolder, and search full note contents, titles and paths with Apple Spotlight. Scope search to a folder, project, OKF bundle or all granted roots; filter by OKF type/tag, preview highlighted literal matches and jump to their source location. Background indexing follows external file changes; Settings › Search manages roots, file types, exclusions and rebuilding.
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

- Copy the entire Markdown source, including frontmatter, with More (…) or Edit › Copy All as Markdown, regardless of lens or selection. No keyboard shortcut.
- Copy the entire document for Medium with More (…) or Edit › Copy All for Medium. HTML conversion runs off the main thread on a snapshot of the source; the clipboard includes formatted HTML and the original Markdown as a plain-text fallback. Frontmatter is omitted from the HTML. No keyboard shortcut. Medium controls what survives pasting: tables, task checkboxes, footnotes, callouts, math and diagrams may lose formatting. Local images and note links are not uploaded; upload images separately and replace local links with public URLs. Check the pasted story before publishing; live Medium paste compatibility has not yet been manually verified.
- Export a self-contained HTML page with local images embedded, math and Mermaid as SVG, syntax-colored code, working local links, frontmatter metadata and light/dark styling.
- Export a paginated PDF of that page with clickable links and page-break handling for headings, tables, code, callouts, math and images.
- Preview `.md`, `.markdown` and `.mdx` files in Finder with Space using a formatted Quick Look extension. Local images, math and Mermaid render in the preview; MDX code stays readable. Click linked local Markdown files to open them in Markify, with feedback for missing or inaccessible files; web links and in-page anchors remain available.
- Customize fonts, line width, page color, code theme, app appearance, accent, floating control style and status capsule. Optionally fade the toolbar while typing.
- Make Markify the default Markdown app; use the built-in Welcome tour and Help Book; check for signed updates automatically or on demand.

## Command line

- Run the bundled `markify` executable from Terminal; `--help` lists commands and exit status. Validation and export run without opening an editor window.
- Open file or stdin text as an untitled report with `markify view [FILE | -] [--title TITLE] [--base DIRECTORY]`. Relative images, links and exports use the supplied base until the document is saved. The source file is never changed.
- Validate an OKF bundle with `markify check BUNDLE`, showing file paths and severity for each finding. Error findings fail the command; warnings and information do not.
- Export a `.md`, `.markdown` or `.mdx` file to a self-contained HTML page with `markify export FILE --html --output OUTPUT`, embedding local images and adjusting local links for the destination.

## Coding agents

- Send local Markdown reports directly from Claude Code (`/markify:view`), Codex (`markify-view` skill), or OpenCode (`markify_view` tool). Separate packages share the bundled CLI transport and detect missing or outdated Markify, reporting a GitHub Releases download link.
- Install Claude and Codex packages through Markify's own marketplace catalogs; install OpenCode from a local package. Public distribution is pending. The [coding agents guide](help/coding-agents.md) covers installation, invocation, updates, removal, permissions and clipboard fallback for each agent.
- Optionally open each completed Claude response through a Stop hook. Reports transfer through a private local cache; no extra AI service is used. Integrations require the agent and Markify on the same Mac.
