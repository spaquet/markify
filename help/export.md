---
title: Export to HTML and PDF
description: Export a Markdown document as a self-contained HTML page or a paginated PDF.
order: 8
keywords: export, html, pdf, print, share, web page
---
# Export to HTML and PDF

Choose **More (…) › Export › HTML** or **PDF**, then pick where to save.

## HTML

The HTML file is a complete, self-contained web page:

- Headings, lists, task lists, tables, callouts, footnotes and code with syntax colors look as they do in the Rendered lens.
- Math is typeset as vector graphics, and Mermaid diagrams are drawn as SVG, so the page needs no scripts or network.
- Images from your Mac are embedded in the file, so you can email or move it on its own. Web images stay linked.
- Links to other notes are adjusted to work from where you saved the page.
- The page follows the reader's light or dark appearance and prints cleanly.
- The page's title comes from the frontmatter `title`, else the first heading. Frontmatter `tags` and `date` appear as chips; other frontmatter is left out.

Image embedding accepts local images below 25 MB, with a 50 MB total budget for embedded image data. Remote PDF images have a 10 MB download limit. Images that exceed these limits stay linked, so keep those files with the exported page. A failed Mermaid render falls back to its source.

## PDF

The PDF is the same page laid out on your Mac's default paper size, such as A4 or US Letter. Headings stay with the text that follows them, and code blocks, table rows, callouts, equations and images aren't split across pages. Links stay clickable.

Remote images are included in the PDF only when **Settings › General › Load remote images** is on.

Closing the document or starting another export cancels the previous export. A canceled PDF export leaves an existing destination file intact. If PDF printing times out and later PDF exports fail, quit and reopen Markify before retrying.

## Sharing the Markdown itself

Your document is already a plain `.md` file. **More (…) › Share** sends the file itself with AirDrop, Mail, Messages and other services.

For scripted HTML export, see [Command line](command-line.md).

## Copying the whole document

Choose **More (…) › Copy All as Markdown** or **Edit › Copy All as Markdown** to copy the entire source, including frontmatter, regardless of the current lens or selection.

Choose **Copy All for Medium** from either menu, then paste into Medium's story editor. The clipboard includes formatted HTML for headings, emphasis, links, lists and code, with Markdown as a plain-text fallback. Frontmatter is omitted from the formatted version. Neither action has a keyboard shortcut.

After either copy, a brief notice at the bottom of the window confirms it — "Copied as Markdown" or "Copied for Medium" — and VoiceOver reads it aloud. Copy for Medium shows the notice once the formatted version is on the clipboard, which can take a moment on long documents. If the clipboard can't be written, the notice says so instead. You can keep typing while it shows.

Medium controls which formatting survives a paste. Tables, task checkboxes, footnotes, callouts, math and diagrams may lose formatting; check the pasted story before publishing. Local images and links to local notes are not uploaded by copying: upload images to Medium and replace local links with public URLs.
