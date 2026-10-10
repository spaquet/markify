# Feature requests

Demand below is a directional estimate from features and roadmaps of comparable Markdown editors, not a survey of Markify users. Rows are ordered by estimated demand; priority reflects Markify's Mac-first, plain-file design. Current support is based on [FEATURES.md](FEATURES.md) and the [user guide](help/index.md).

| Demand rank | Request | Current support | Priority |
| --- | --- | --- | --- |
| 1 | Access notes across devices | Files work in iCloud Drive, Dropbox, or Git folders, but Markify runs only on Mac. | Strategic: pursue a mobile companion only if cross-device editing becomes a product goal; file sync already covers multiple Macs. |
| 2 | Search all library note contents | Supported: Library search (⇧⌘F) uses Apple Spotlight to search the full text of notes, titles and folder paths, across Library, project and OKF scopes, with highlighted context and line numbers. Find searches the current document. | Done. |
| 3 | Link and navigate a note collection | Markdown links work; OKF bundles have backlinks. Wiki links such as `[[note]]` are plain text in ordinary folders. | High if supporting Obsidian-style folders: resolve existing wiki links and their targets first. |
| 4 | Table of contents for the current document | Supported: the right pane's **Contents** tab lists headings with an H1/H2/H3/All depth control and jumps to each heading. **Insert Table of Contents** writes a list between `<!-- toc -->` markers that updates as headings change; exports include it. | Done. |
| 5 | Capture web pages and content from other apps | Open URL reads remote Markdown; New from Clipboard opens copied Markdown. Neither saves a web page as a library note. | Medium: start with a simple save-to-library capture flow. |
| 6 | Share and edit with others | Users can share Markdown files or use an external sync folder; no live coediting or comments. | Low for now: revisit if team use becomes a primary audience. |
| 7 | Exchange documents with Word users | HTML and PDF export work; DOCX import and export do not. | Medium if users regularly hand drafts to Word users. |
| 8 | Focus or typewriter mode | Controls can fade while typing; text outside the current line or paragraph is not dimmed, and the caret is not centered. | Medium-low for long-form writing. |


## Market references

- [Obsidian roadmap](https://obsidian.md/roadmap/): mobile sync, search relevance, and collaborative editing remain active or planned areas.
- [Obsidian Web Clipper](https://obsidian.md/help/web-clipper): browser capture into Markdown notes.
- [iA Writer features](https://ia.net/writer/support/basics/features): cross-device access, focus mode, wiki links, and Word import/export.
