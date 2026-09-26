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

## PDF

The PDF is the same page laid out on your Mac's default paper size, such as A4 or US Letter. Headings stay with the text that follows them, and code blocks, table rows, callouts, equations and images aren't split across pages. Links stay clickable.

Remote images are included in the PDF only when **Settings › General › Load remote images** is on.

## Sharing the Markdown itself

Your document is already a plain `.md` file. **More (…) › Share** sends the file itself with AirDrop, Mail, Messages and other services.
