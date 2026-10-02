# Feature requests

Demand below is a directional estimate from features and roadmaps of comparable Markdown editors, not a survey of Markify users. Rows are ordered by estimated demand; priority reflects Markify's Mac-first, plain-file design. Current support is based on [FEATURES.md](FEATURES.md) and the [user guide](help/index.md).

| Demand rank | Request | Current support | Priority |
| --- | --- | --- | --- |
| 1 | Access notes across devices | Files work in iCloud Drive, Dropbox, or Git folders, but Markify runs only on Mac. | Strategic: pursue a mobile companion only if cross-device editing becomes a product goal; file sync already covers multiple Macs. |
| 2 | Search all library note contents | Library search checks title, folder path, and a short preview; Find searches the current document. | Highest near-term: search full text across library files and show matching context. |
| 3 | Link and navigate a note collection | Markdown links work; OKF bundles have backlinks. Wiki links such as `[[note]]` are plain text in ordinary folders. | High if supporting Obsidian-style folders: resolve existing wiki links and their targets first. |
| 4 | Table of contents for the current document | The right Links pane lists outgoing link destinations and their source lines, but not headings. | High: add a **Table of Contents** view to the existing right sliding pane, alongside **Links**. Automatically list level 1 and 2 headings (`#` and `##`, including their setext equivalents) in document order and jump to their source positions. Omit levels 3–6 to keep the pane readable. |
| 5 | Capture web pages and content from other apps | Open URL reads remote Markdown; New from Clipboard opens copied Markdown. Neither saves a web page as a library note. | Medium: start with a simple save-to-library capture flow. |
| 6 | Share and edit with others | Users can share Markdown files or use an external sync folder; no live coediting or comments. | Low for now: revisit if team use becomes a primary audience. |
| 7 | Exchange documents with Word users | HTML and PDF export work; DOCX import and export do not. | Medium if users regularly hand drafts to Word users. |
| 8 | Focus or typewriter mode | Controls can fade while typing; text outside the current line or paragraph is not dimmed, and the caret is not centered. | Medium-low for long-form writing. |


## Market references

- [Obsidian roadmap](https://obsidian.md/roadmap/): mobile sync, search relevance, and collaborative editing remain active or planned areas.
- [Obsidian Web Clipper](https://obsidian.md/help/web-clipper): browser capture into Markdown notes.
- [iA Writer features](https://ia.net/writer/support/basics/features): cross-device access, focus mode, wiki links, and Word import/export.
