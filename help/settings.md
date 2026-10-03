---
title: Settings
description: Change where documents are saved, the default lens, fonts, appearance, Spotlight search, Apple Intelligence options and keyboard shortcuts.
order: 10
keywords: settings, preferences, font, theme, dark mode, line width, accent, shortcuts, library location
---
# Settings

Choose **Markify › Settings…** (⌘,).

## General

- **New documents are saved to** your library or a place you choose each time.
- **Library location** chooses the folder whose `.md`, `.markdown` and `.mdx` files and subfolders appear in the sidebar.
- **Save pasted images to** `./assets`, `./images` or the document's folder.
- **Load remote images** from the web. Changes apply to open documents and image previews immediately.
- **On launch**, reopen your last documents, start a new one, or show the library.
- **Default Markdown app**: make Markify open `.md` files from the Finder.
- **Knowledge**: your verifier name and whether your edits are recorded in OKF concepts.
- **Updates**: check for updates automatically, and download and install them automatically.

## Editor

- **Open documents in** the Rendered lens, the Markdown lens or the last one used, and optionally remember the lens per document.
- **Prose font** (New York or SF Pro) and **Markdown font** (SF Mono or Menlo).
- **Limit line width**: text normally fills the window, with margins that grow as the window widens. Turn this on to keep lines no wider than **Line width** (560–1200 pt) however wide the window is.
- **Fade toolbar while typing** and **Show word count**.

## Appearance

Theme (light, dark or system), page color, code colors, the glass style of the floating controls, the accent color, and the status capsule.

## Search

- **Rebuild Index** deletes and recreates Markify’s donated Spotlight entries in the background. **Cancel** stops the current indexing job; rebuild again to finish it.
- **Indexed folders** lists the Library, granted projects and OKF bundles with their status. Select a row and click **−** to remove that root from search, or **+** to grant a folder. Files shared with another indexed root stay searchable there. **Grant Access…** renews an expired folder grant by asking you to select the same folder.
- **File types** enables `.md`, `.markdown` and `.mdx`, all on by default.
- **Index OKF frontmatter** adds title, description, type and tags to search and enables type/tag filtering.
- **Index headings as context** adds section context to literal results. Heading text remains searchable as part of the note when this is off.
- **Skip folders named** accepts comma-separated folder names, applied recursively inside every indexed root. The defaults are `.git`, `node_modules`, and `_build`; hidden files, packages and symlinks are skipped too.
- **Default scope** chooses Current Library, Current OKF bundle or All Folders. Outside a bundle, Current OKF bundle falls back to the Library.
- **Include related results** allows Spotlight’s semantic matching when available. Results with no exact or metadata match open at the top of the note.
- **System Spotlight** explains that donated notes may also appear outside Markify for this Mac account. **Spotlight Settings…** opens macOS’s controls; Markify has no separate app-only visibility toggle.
- **Delete Search Index…** removes Markify’s entries and pauses indexing until you choose Rebuild Index. It does not delete notes or remove macOS’s independent filesystem entries.

The named index stays on this Mac. Markify reports submission progress; Spotlight may continue processing notes after submission finishes.

## Intelligence

Turn Writing Tools in the format bar, generating at the caret, and title and tag suggestions on or off, and choose the default tone. See [Apple Intelligence](intelligence.md).

## Shortcuts

Double-click a shortcut to record a new one. See [Keyboard shortcuts](shortcuts.md).
