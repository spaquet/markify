# Search

Press **⇧⌘F** to search saved Markdown notes with Apple Spotlight. In-document find and replace uses **⌘F** and **⌥⌘F** separately.

## Scope and results

The default scope is the Library. The **In** menu selects a folder, granted project, OKF bundle, or All Folders. **Add Folder…** grants access without changing the Library. Opening a document does not add its containing folder to search.

Markify indexes `.md`, `.markdown`, and `.mdx` files recursively. Hidden files, packages, symlinks, and configured excluded folders are skipped. Search includes contents, titles, and relative paths. Type and Tag filters use OKF frontmatter when metadata indexing is enabled.

Spotlight ranks results. Literal matches show highlighted context and source line numbers; clicking selects the occurrence in the current document. Title, path, and related matches open normally. Folder access problems appear in the footer; expired grants hide results until access is renewed.

## Index updates and external changes

`LibrarySearch` watches configured roots with `BundleWatcher` (FSEvents). Changes schedule a background scan through `SpotlightWorker`. SHA-256 fingerprints cover content, searchable metadata, options, and modification time; only changed notes are submitted. Complete scans remove entries for deleted or moved notes. Incomplete scans preserve entries that could not be read.

Open windows watch the document's parent folder, including saves that atomically replace the file. When disk content differs, Markify requests a search refresh and reloads a clean document through `NSDocument.revert`. Unsaved local edits are preserved. Only notes inside configured search roots are indexed.

Submission and Spotlight processing are separate: new content can take time to appear. The Library's Refresh action retries; Settings › Search provides rebuild, pause, exclusions, and search defaults.

## Implementation

- `Markify/LibrarySearch.swift`: folder grants, options, scans, fingerprints, Spotlight donation, and matching.
- `Markify/LibrarySearchView.swift`: search interface and navigation.
- `Markify/Knowledge.swift`: `BundleWatcher` and OKF integration.
- `Markify/MarkifyDocument.swift`: external change refresh.
- `Markify/ContentView.swift`: document window watcher attachment.
- `MarkifyTests/LibrarySearchTests.swift`: search regression coverage.
- `help/library.md` and `help/settings.md`: user guide; regenerate Help with `scripts/build-help.sh` after edits.

Run app tests with `xcodebuild -project Markify.xcodeproj -scheme Markify -only-testing:MarkifyTests test`.
