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

Click the right sidebar button in the toolbar to list destinations in the order they first appear. Repeated links to the same resolved destination share one entry, even when their labels differ. Each entry lists its source line numbers, which update as you edit. Click a line number to jump to that occurrence, click the title to jump to the first occurrence, or choose **Open destination** to follow the link. Multiple mentions on one line list that line once. The panel shows an empty message when the document has no links.

Expand **Summary** on a link to see a saved summary or request one with Apple Intelligence. For websites, **Fetch and summarize** contacts the site only when you click it. Local `.md`, `.markdown` and `.mdx` files use their readable text; websites must return a text or HTML page. Other destinations remain in the list without a summary. The panel shows progress or an error if a destination cannot be read, and explains when Apple Intelligence is unavailable.

Summaries are saved by Markify outside your Markdown file. Local summaries show when their target changed and can be refreshed. Web summaries show their generation date and stay as saved until you choose **Refresh summary**.

Select part or all of a summary or error message to copy it with ⌘C or the standard text context menu. You can paste the copied text into your document or another app.

### Links in Finder previews

Press Space on a Markdown file in Finder to preview it. Click a local `.md`, `.markdown` or `.mdx` link to open the linked file in Markify. Relative paths, including `../` and percent-encoded filenames, resolve beside the previewed file. A missing or inaccessible destination produces a selectable message at the bottom of the preview. Links to other local file types are not opened by this preview.

HTTPS links open in your browser; in-document anchors stay inside the preview. Links to a section of another Markdown file open that document without jumping to its section. No folder permission step is added.
