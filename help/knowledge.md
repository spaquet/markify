---
title: Knowledge bundles
description: Open, browse and maintain Open Knowledge Format (OKF) bundles of Markdown concepts in Markify.
order: 9
keywords: okf, open knowledge format, bundle, concept, knowledge, verify, index, log
---
# Knowledge bundles

The [Open Knowledge Format](https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md) (OKF), an open specification published by Google Cloud, packages what a team knows as a folder of Markdown files that AI agents can read. Each file is a **concept** with YAML frontmatter such as `type`, `title`, `description`, `tags` and `status`.

## Opening a bundle

Choose **File › Open Bundle Folder…** (⇧⌘O) and pick the bundle's folder. The library sidebar shows its concepts by folder, type or tag, and flags problems the format defines, such as a missing title or a broken link.

## Reading concepts

A concept's type, status, staleness and trust appear as chips above its title. **⌘-click** any link to follow it; bundle links that start with `/` are resolved from the bundle's root.

## Editing concepts

- Type `](/` to pick another concept to link to.
- Type `/concept` to insert a concept header.
- **More (…) › Knowledge** marks a concept verified, makes the current document a concept, adds a log entry, or rebuilds the bundle's index.

Markify changes only the lines you edit. Settings › General › Knowledge sets the name recorded when you verify a concept and whether your edits are recorded in the concept's `generated` field. Learn more on the [Open Knowledge Format page](https://spaquet.github.io/markify/okf.html).

To validate a whole bundle in Terminal or CI, see [Command line](command-line.md).
