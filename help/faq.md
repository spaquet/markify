---
title: Frequently asked questions
description: Answers to common questions about Markify — price, privacy, file formats, Apple Intelligence, installing, exporting and more.
order: 13
keywords: faq, questions, answers, free, price, privacy, open source, windows, ios, sync, icloud, obsidian
web: faq.html
schema: faq
---
# Frequently asked questions

## About Markify

### Is Markify free?

Yes. Markify is free to download and use, including for work. Its source code is on [GitHub](https://github.com/spaquet/markify). The [license](legal.md) restricts selling Markify itself, or a product or service whose value derives substantially from it. You can support its development with a [GitHub sponsorship](https://github.com/sponsors/spaquet).

### Which Macs does Markify run on?

Any Mac with macOS 26 Tahoe or later, with Apple silicon or an Intel processor. Download the build that matches your Mac.

### Is there a version for iPhone, iPad, Windows or Linux?

No. Markify is a native Mac app built with SwiftUI and TextKit 2.

### How is Markify different from other Markdown editors?

Most Markdown editors split the window into source and preview. Markify shows one page and lets you switch its lens with ⌘/: the rendered page and the plain Markdown are the same text, so nothing is converted or rewritten. See [Two lenses](lenses.md).

## Files and formats

### Where are my documents stored?

Wherever you save them. Every document is an ordinary `.md` file. By default new documents go to your library folder, `Documents/Markify`, which you can change in Settings.

### Can I use Markify with iCloud Drive, Dropbox or Git?

Yes. Because documents are plain files, anything that syncs or versions files works with them. Markify reloads a document when another app changes it.

### Does Markify change my Markdown?

No. Markify only styles the text it shows. The file is saved exactly as you typed it, in UTF-8.

### Which Markdown features are supported?

CommonMark and GitHub Flavored Markdown (tables, task lists, strikethrough, autolinks), plus callouts, math, footnotes, Mermaid diagrams, YAML frontmatter and MDX files. See [Markdown support](markdown.md).

### Can I open Obsidian or other notes folders?

Yes. Choose **File › Open Folder…** or set your notes folder under **Settings › General › Library location**. The Library sidebar lists `.md`, `.markdown` and `.mdx` files in that folder and its subfolders. Links written as `[text](file.md)` work; wiki links such as `[[note]]` show as plain text.

### Can I open Markdown from GitHub or the web?

Yes. Choose **File › Open URL…** and paste an HTTPS link to a `.md` file, or a GitHub or GitLab repository to browse its Markdown files. Private repositories work with a personal access token. The file opens as an unsaved local copy; your edits are never sent back. See [Open a URL](getting-started.md#open-a-url).

### Is there a command-line tool?

Yes. The `markify` command inside the app opens Markdown in a new window (`markify view`), validates knowledge bundles (`markify check`) and exports HTML (`markify export`). See [Command line](command-line.md).

### Can coding agents send their answers to Markify?

Yes. Plugins for Claude Code, Codex and OpenCode open a long answer as a new document on the rendered page. See [Coding agents](coding-agents.md).

### How do I export to PDF or HTML?

Choose **More (…) › Export › HTML** or **PDF**. The HTML page is self-contained, with images embedded, and the PDF is paginated. See [Export to HTML and PDF](export.md).

## Privacy and Apple Intelligence

### Does Markify collect any data?

No. Markify has no accounts, analytics or tracking. See the privacy section on the [Legal](legal.md) page for the few times it connects to the internet.

### Is my text sent to an AI service?

No. Apple Intelligence features run on your Mac with Apple's on-device model and system Writing Tools. Markify doesn't use cloud AI services.

### Why don't I see the Apple Intelligence features?

They need a Mac with Apple silicon and Apple Intelligence turned on in System Settings › Apple Intelligence & Siri. Check that Writing Tools and the other options are on in Markify's **Settings › Intelligence**. See [Apple Intelligence](intelligence.md).

## Installing and updating

### macOS says it can't verify Markify. What do I do?

Markify isn't notarized yet. Open it once, click **Done**, then go to **System Settings › Privacy & Security** and click **Open Anyway** next to the message about Markify. See [Install and update](updates.md).

### How do I update Markify?

Markify checks for updates automatically. Choose **Markify › Check for Updates…** to check now.

### I found a bug or have an idea. Where do I report it?

Open an issue on [GitHub](https://github.com/spaquet/markify/issues). Include your macOS version, Markify version (Markify › About Markify) and the steps to reproduce the problem.

## Accessibility

### Does Markify work with VoiceOver?

Yes. Markify uses the standard Mac text view, so VoiceOver reads and edits the document, and its buttons have spoken labels. The Markdown lens shows every character, which some VoiceOver users prefer. If something isn't accessible, please [report it](https://github.com/spaquet/markify/issues).

### Can I make the text bigger?

Yes. Press ⌘= and ⌘- to zoom, ⌘0 to return to actual size, and change the fonts and line width in **Settings › Editor**.
