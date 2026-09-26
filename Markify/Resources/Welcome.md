---
tags: [essay, editor]
date: 2026-09-25
---
# One Page, Two Lenses

Most Markdown editors split the window in two: code on the left, preview on the right. Markify **keeps a single page** and lets you change the lens instead.[^1]

> [!NOTE]
> Press ⌘/ anywhere to flip between the rendered page and its Markdown. The lens changes; your caret and scroll stay put.

## Getting started

- [x] Write in the rendered lens
- [x] Select text to format it
- [ ] Switch to the Markdown lens once

| Shortcut | Action | Lens |
| --- | --- | --- |
| ⌘/ | Toggle Markdown | Both |
| / | Insert block | Rendered |
| ⌃⌘S | Show library | Both |

```swift
// Flip lenses without losing place
func toggleLens() {
    let anchor = editor.caretOffset
    editor.lens = editor.lens == .rendered ? .source : .rendered
    editor.restore(anchor)
}
```

$$
\int_0^1 x^2\,dx = \frac{1}{3}
$$

## Knowledge bundles

Markify reads and edits [Open Knowledge Format](https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md) bundles: folders of Markdown concepts that AI agents can use as curated context.

- **File › Open Bundle Folder…** (⇧⌘O) opens a bundle and shows it in the sidebar by folder, type or tag.
- A concept's type, status, staleness and trust appear above its title. ⌘-click any link to follow it.
- Type `](/` to link another concept, and use **… › Knowledge** to verify a concept, set its status, log a change or rebuild an index.

![One window, one column.](hero.png)

[^1]: Both lenses edit the same file — nothing is ever exported or synced between panes.
