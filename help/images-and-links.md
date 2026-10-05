---
title: Images and links
description: Add images by dragging or pasting, link to other notes, and follow links with ⌘-click.
order: 5
keywords: image, picture, paste, drag, assets, remote images, link, note link, command click
---
# Images and links

## Adding images

Drag an image file onto the page or paste an image. Markify copies it into a folder next to your document and inserts a relative link such as `![photo](assets/photo.png)`, so the document and its images move together.

- Choose the folder in **Settings › General › Save pasted images to**: `./assets` (the default), `./images`, or the document's own folder.
- Save a new document before adding images, so Markify knows where to put them.
- An image alone on its line is drawn at full width. An image inside a sentence appears as a small chip; hover over it to preview the image.

Local images and linked Markdown files are read directly from their paths relative to the document. No folder permission step is needed.

Editor images load in the background. Images above 10 MB show an unavailable placeholder; displayed images are reduced to at most 2,048 pixels on their longest side. Your original files stay unchanged.

### Remote images

Images from the web (`https://…`) load only when **Settings › General › Load remote images** is on. Turn it off to keep documents from contacting other servers.

## Links

- Type `[text](address)`, or select text and press ⌘K.
- **⌘-click** a link to open it, in either lens. Links to other Markdown files open in Markify; web links open in your browser.
- Drag a note from the library sidebar or the Finder into the page to insert a link to it. The link uses a path relative to your document, so it keeps working in other editors and on GitHub.

### Documents opened from the web

When you [open a URL](getting-started.md#open-a-url), relative image paths and links resolve against the fetched document’s web location. **⌘-click** opens these resolved web links in your browser; remote images follow **Load remote images**. Local image URLs are not loaded in a web document.

The web location remains in use for the current document session, including after saving locally. Reopening the saved copy resolves relative paths against its local folder. Use **More (…) › Source** to open the original page in your browser or copy its URL while that document session is open.

### Links panel

Click the right sidebar button in the toolbar, then **Links** at the top of the pane. Links are grouped into **In this document** (links to a heading, such as `#method`), **Files** and **Web**, in the order they first appear. Mail, phone and app links (`mailto:`, `tel:`, `slack://`) aren't listed. Repeated links to the same destination share one row, marked ×2, ×3 and so on, even when their labels differ. The chips at the top show all links, one group, or only broken ones.

Each row shows the line of the first occurrence. Point at a row to see its actions:

- **↩ Go to line** moves to the link in the document. With repeated links, each click goes to the next occurrence; clicking the row does the same.
- **↗ Open** opens the file in Markify or the page in your browser.
- **✦ Summarize** shows a summary from Apple Intelligence under the row (see below).
- **✎ Fix link…** appears on broken links (see below).

⌘-click a link to a heading in the document to jump to it. A link such as `notes.md#setup` opens `notes.md` at that heading.

#### Broken links

Markify checks links in the background while the pane is open and marks broken ones in red with the reason: **No such heading**, **File not found**, or for web pages **Not found (404)**, **Server not found**, **Timed out** and similar. Links to headings and files are checked as you type. Web links are checked when the pane opens and after you stop typing; each result is kept for 24 hours, even after you quit, so the same page isn't asked again. Clicking a link, in the pane or ⌘-clicking it in the document, checks it again at once, so a page that came back or went away shows its current state. **Check Links** at the bottom checks every link again now; the line beside it shows how many are broken and when they were checked. Pages that need a login count as working. Markify never marks a link broken when your Mac is offline.

**✎ Fix link…** shows the destination in an editable field with suggestions: the closest headings for a link to a heading, or similar Markdown files in the same folder for a missing file. Choose a suggestion or type a destination, then **Replace**. Every occurrence of that link changes, including a reference definition (`[label]: path`), and one **Undo** puts them all back.

#### Summaries

**✦** opens a card under the link. If no summary is saved, Apple Intelligence writes one on your Mac; for websites, Markify downloads the page only when you choose ✦. Local `.md`, `.markdown` and `.mdx` files use their readable text; websites must return a text or HTML page. ✦ doesn't appear for other destinations or when Apple Intelligence is unavailable. The card shows progress, or an error with **Try Again**.

Summaries are saved by Markify outside your Markdown file. The card shows when a summary was generated, notes **Source changed** when a local file changed since, and offers **Refresh**.

Website summaries accept pages up to 1 MB, and local summaries accept Markdown files up to 2 MB. Older summaries and link checks may be removed as their caches fill; you can generate a summary or check a link again.

Select part or all of a summary or error message to copy it with ⌘C or the standard text context menu. You can paste the copied text into your document or another app.

### Links in Finder previews

Press Space on a Markdown file in Finder to preview it. Click a local `.md`, `.markdown` or `.mdx` link to open the linked file in Markify. Relative paths, including `../` and percent-encoded filenames, resolve beside the previewed file. A missing or inaccessible destination produces a selectable message at the bottom of the preview. Links to other local file types are not opened by this preview.

Previews accept Markdown files up to 2 MB and omit remote images. Local images are included within the preview's image size limits.

HTTPS links open in your browser; in-document anchors stay inside the preview. Links to a section of another Markdown file open that document without jumping to its section. No folder permission step is added.
