# Design decisions

- Markify opens an empty document on launch. The document picker remains available through File > Open, matching the empty-document design state.
- Saved image drops copy into `assets` beside the Markdown file. Name collisions get a numeric suffix; unsaved documents use the original absolute path until saved.
- A library defaults to `~/Documents/Markify` when that folder exists. Settings can choose another folder with a persistent security-scoped bookmark.
- The source remains plain Markdown. Both lenses style the same TextKit 2 text storage, so selection offsets and undo history stay in source coordinates.
- Display math uses SwaTex's native CoreText renderer; formulas render locally without a WebView.
- Ordered lists display counted numbers in the rendered lens; the file keeps its written numbers until an edit touches that list, which then renumbers only that list.
- Settings › On launch drives startup instead of system window restoration: "Reopen last documents" reopens the files open at quit (security-scoped bookmarks), "New document" opens an empty document, and "Library" opens an empty document with the library sidebar showing.
- "New documents are saved to Library" starts an untitled document's save panel in the library folder; the panel still asks for a name.
- "Reload when changed on disk" was dropped from Settings. The system document architecture already reloads unedited documents, and SwiftUI's `DocumentGroup` offers no clean way to turn that off.
- The per-document lens is stored in the `com.markify.lens` extended attribute and rewritten when the window closes, since saves can replace the file.
- "Use surrounding section as context" sends the heading-bounded section around a selection or the caret with the request; when off, selection edits see only the selection and caret generation sees the whole document.
