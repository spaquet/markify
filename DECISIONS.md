# Design decisions

- Markify opens an empty document on launch. The document picker remains available through File > Open, matching the empty-document design state.
- Saved image drops copy into `assets` beside the Markdown file. Name collisions get a numeric suffix; unsaved documents use the original absolute path until saved.
- A library defaults to `~/Documents/Markify` when that folder exists. Settings can choose another folder with a persistent security-scoped bookmark.
- The source remains plain Markdown. Both lenses style the same TextKit 2 text storage, so selection offsets and undo history stay in source coordinates.
