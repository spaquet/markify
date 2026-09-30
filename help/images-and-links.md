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

### Links panel

Click the right sidebar button in the toolbar to list links in document order. Click a link's title to jump to it, or choose **Open destination** to follow it. The panel shows an empty message when the document has no links.

Expand **Summary** on a link to see a saved summary or request one with Apple Intelligence. For websites, **Fetch and summarize** contacts the site only when you click it. Local `.md`, `.markdown` and `.mdx` files use their readable text; websites must return a text or HTML page. Other destinations remain in the list without a summary. The panel shows progress or an error if a destination cannot be read, and explains when Apple Intelligence is unavailable.

Summaries are saved by Markify outside your Markdown file. Local summaries show when their target changed and can be refreshed. Web summaries show their generation date and stay as saved until you choose **Refresh summary**.
