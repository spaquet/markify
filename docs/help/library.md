<!-- Library and find — Markify Help. Web page: https://spaquet.github.io/markify/help/library.html -->

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

If a folder’s access expires, its results are hidden. Choose **Grant Access…** and select that same folder. Manage indexing, excluded folders and search defaults in [Settings › Search](https://spaquet.github.io/markify/help/settings.md).

With no query, browse open files and Library notes or reuse a recent search. Drag a note into the page to link to it.

The Library overlays the page, with window controls above search. Choose **New Document** at the bottom, or press **⌘N**, to create a document.

In an Open Knowledge Format bundle, the sidebar also groups concepts by folder, type or tag. See [Knowledge bundles](https://spaquet.github.io/markify/help/knowledge.md).

### Changes from other apps

When an open file changes on disk, Markify reloads its contents if the document has no unsaved edits. Unsaved local edits are preserved. Changes also request a search index refresh for notes in configured search folders; Spotlight may take time to show the new content.

## Sync and share with iCloud Drive

Markify saves ordinary Markdown files, so iCloud Drive can keep your documents in sync between your Macs or share them with other people, with no extra service to install.

> [!WARNING]
> Simultaneous editing hasn't been fully tested yet. If the same document is edited on two Macs at once, or by two people at once, the other Mac may not show the new text right away. Edit a shared document in one place at a time, and wait for iCloud Drive to finish syncing before you continue elsewhere. When Markify notices that a file changed on disk, it offers **Keep My Changes**, **Reload** or **Merge**. See [Changes from another app](https://spaquet.github.io/markify/help/getting-started.md#changes-from-another-app).

### Between your own Macs

1. Create a folder in iCloud Drive, such as `iCloud Drive/Markify`.
2. Move your documents into it, along with their images and linked files, so relative paths keep working.
3. On each Mac, choose that folder in **Markify › Settings… › General › Library location**.
4. Sign in to the same Apple Account on each Mac and turn on iCloud Drive.

Wait for syncing to finish before you switch Macs, especially after working offline.

### With other people

In the Finder, select the folder in iCloud Drive and use its sharing controls to invite people through their own Apple Accounts. Let them view only or make changes, depending on what they need. They can then open the shared Markdown files in Markify.

Share a folder that holds only the documents and images you mean to share. Don't use “anyone with the link” access for private material. Removing someone's access later doesn't delete copies they've already downloaded.

### Protecting your documents

For stronger privacy, turn on **Advanced Data Protection** in your Apple Account's iCloud settings, where it's available. It adds end-to-end encryption to the contents of your iCloud Drive files. A shared folder keeps this protection only when every participant has turned it on, and sharing with “anyone with the link” doesn't keep it. Set up a recovery contact or recovery key first: Apple can't recover end-to-end encrypted data if you lose access to your account. See [Apple's iCloud data security overview](https://support.apple.com/en-us/102651).

Use a strong password on each Mac, turn on FileVault, and keep two-factor authentication on for your Apple Account.

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
