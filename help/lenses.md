---
title: Two lenses
description: Switch between the Rendered lens and the Markdown lens with ⌘/, without losing your place.
order: 2
keywords: lens, rendered, markdown, source, toggle, preview, command slash
---
# Two lenses

Markify has no split preview. It shows one document through two **lenses**:

| Lens | What you see |
| --- | --- |
| Rendered | Headings, lists, tables, math and images drawn in place, with the Markdown syntax hidden. |
| Markdown | The plain text of the file, with syntax characters dimmed so your words stand out. |

Press **⌘/** or click **MD** at the top right to switch. Your caret, selection and scroll position stay where they were, and undo keeps working across the switch.

Both lenses edit the same text. Switching only changes how the text is styled; Markify never rewrites your Markdown.

The insertion cursor follows the size of the visible text, including headings, body text and code.

## Choosing the lens a document opens in

In **Settings › Editor › Lenses**, choose whether documents open in the Rendered lens, the Markdown lens or the one you used last. Turn on *Remember lens per document* to reopen each file the way you left it.
