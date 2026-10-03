---
title: Library and find
description: Search note contents with Spotlight, browse folders and knowledge bundles, and find and replace text in a document.
order: 6
keywords: library, sidebar, notes, folder, search, find, replace
---
# Library and find

## The library

Press **⌃⌘S** or click the sidebar button to slide the library over the page. It lists:

- **Open files**: every document open in Markify, wherever it's saved.
- **Library notes**: `.md`, `.markdown` and `.mdx` files in your library folder and its subfolders. Hidden files are skipped. The default folder is `Documents/Markify`.

To use an existing notes folder, choose **File › Open Folder…** and select it. You can also choose the folder under **Markify › Settings… › General › Library location**. Open the Library with **⌃⌘S**. The sidebar shows subfolders, including empty ones; click **+** beside a folder to create a document there. Notes from subfolders show their folder path below the title.

### Search across notes

Press **⇧⌘F** to open the Library and focus **Search notes**. Markify uses Apple Spotlight to search the full text of `.md`, `.markdown` and `.mdx` notes, including subfolders; titles and relative folder paths are searchable too. The default scope is your current Library. The **In** menu narrows the search to a folder, a granted project folder, or an OKF bundle, or expands it to **All Folders**. Use **Add Folder…** to grant another folder without changing your Library.

Spotlight ranks the results. They are grouped by Library, project or knowledge bundle, with relative paths to distinguish notes with the same name. **Type** and **Tag** filter indexed OKF frontmatter in the selected scope. Type means the frontmatter’s `type` value, such as `Concept` or `Reference`, rather than the file extension. Filters are unavailable when that scope has no indexed values; hover for an explanation. Enable **Index OKF frontmatter** in Settings › Search to use them. Selected filters are highlighted and checked in their menus. Literal matches show highlighted context, a line number and, when enabled, the section heading. Click a result to open it and select the first occurrence in the current source. A title or path match opens normally. **Related** means Spotlight returned a result without a literal or metadata match; it opens at the top and has no invented line number. Related matching depends on Spotlight’s capabilities and processing on your Mac.

The footer reports indexing progress and folder access problems. Markify scans and submits notes in the background, so you can keep editing. Submission to Spotlight and Spotlight’s processing are separate: newly submitted notes may take time to appear. An empty result while indexing is labelled **Still indexing**. Use **Refresh** in the Library menu to retry a search after submission. Folder changes made outside Markify trigger refreshes while the app runs; reopening the pane also refreshes. Removed or moved notes are removed from Markify’s donated entries.

If a folder’s access expires, its results are hidden. Choose **Grant Access…** and select that same folder. Manage indexing, excluded folders and search defaults in [Settings › Search](settings.md).

With no query, browse open files and Library notes or reuse a recent search. Drag a note into the page to link to it.

The Library overlays the page, with window controls above search. Choose **New Document** at the bottom, or press **⌘N**, to create a document.

In an Open Knowledge Format bundle, the sidebar also groups concepts by folder, type or tag. See [Knowledge bundles](knowledge.md).

### Changes from other apps

When an open file changes on disk, Markify reloads its contents if the document has no unsaved edits. Unsaved local edits are preserved. Changes also request a search index refresh for notes in configured search folders; Spotlight may take time to show the new content.

## Find and replace

| Shortcut | Action |
| --- | --- |
| ⌘F | Find |
| ⌥⌘F | Find and replace |
| ⌘G | Next match |
| ⇧⌘G | Previous match |
| Escape | Close the find bar |

In the Rendered lens, Find matches the words you see and skips hidden syntax, so searching “important note” finds `**important** note`. Matches are highlighted in place.

## Word count

The capsule at the bottom right of the window shows the word count and the current lens. Turn the count off with **More (…) › Show Word Count**, or hide the capsule in **Settings › Appearance › Show status capsule**.
