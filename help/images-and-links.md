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

### Remote images

Images from the web (`https://…`) load only when **Settings › General › Load remote images** is on. Turn it off to keep documents from contacting other servers.

## Links

- Type `[text](address)`, or select text and press ⌘K.
- **⌘-click** a link to open it, in either lens. Links to other Markdown files open in Markify; web links open in your browser.
- Drag a note from the library sidebar or the Finder into the page to insert a link to it. The link uses a path relative to your document, so it keeps working in other editors and on GitHub.
