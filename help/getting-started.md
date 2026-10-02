---
title: Getting started
description: Create, open and save Markdown documents in Markify, and find your way around the window.
order: 1
keywords: new document, open, save, library, window, welcome, URL, HTTPS, GitHub, GitLab, repository
---
# Getting started

## Create or open a document

- **File › New** (⌘N) creates an untitled document. Settings › General › *New documents are saved to* decides whether it saves into your library folder or asks each time.
- **File › Open…** (⌘O) opens any `.md`, `.markdown` or `.mdx` file on your Mac. You can also drag a file onto the Markify icon.
- **File › Open URL…** opens a file from the web or browses a GitHub or GitLab repository. See [Open a URL](#open-a-url).
- **File › Open Folder…** chooses a folder for the Library sidebar. Use this for a folder of notes; the standard **Open…** command accepts individual files.
- **File › Open Recent** lists the files you used lately.

Opening a file replaces an untouched, empty startup document in the same window, keeping its size. Once you edit that document, files open in separate windows.

Markify saves automatically, like other Mac apps. Use **File › Revert To** or the title menu's **Browse All Versions…** to go back to an earlier version.

To preview a Markdown file without opening it, select a `.md`, `.markdown` or `.mdx` file in Finder and press Space. Markify's Quick Look extension shows formatted Markdown, HTML, math and Mermaid diagrams. It loads HTTPS images and local images referenced by the document, without a folder permission step. Click linked local Markdown files to open them in Markify; web links open in your browser and anchor links stay in the preview. See [Images and links](images-and-links.md#links-in-finder-previews).

## Open a URL

Choose **File › Open URL…**, then select one of the two options:

The URL shows its host, repository, branch and path as you type. **Access** offers public access, a personal access token for GitHub or GitLab, or username/password and bearer tokens for other HTTPS servers. GitHub tokens need **Contents: read**; GitLab repository browsing needs **read_api**. Browser account sign-in is not configured in this build.

Credentials are used only for the selected HTTPS service; redirects to another origin are refused. Use Password AutoFill where available in the username and password fields. **Remember in Keychain** is off by default and saves credentials only after a successful request. Choose a saved credential to reuse it, or **Remove** to delete it. Replace rejected or expired credentials and retry. Login pages are never opened as Markdown.

- **File**: paste a direct HTTPS URL ending in `.md`, `.markdown` or `.mdx`, or a GitHub or GitLab file-page URL, and choose **Open**. File-page links fetch the Markdown source rather than the website’s HTML.
- **Repository**: paste a GitHub or GitLab repository URL and choose **Browse**. Markify lists Markdown files from the default branch, or the branch and folder in a repository tree URL. Search by folder or filename, select a file, then choose **Open**.

Loading and errors appear in the dialog. The entered URL stays there so you can correct it or retry; **Cancel** stops the request. Protected resources support personal access tokens, HTTP Basic authentication and bearer tokens. Servers that require browser-only or unsupported authentication show an error. HTTP URLs, redirects to HTTP, HTML pages and downloads over 10 MB are rejected. For repositories too large to browse, use a file URL instead.

Documents opened from URLs are unsaved local copies. Use **⌘S** to choose a local name and location; edits are never sent to the server. Relative links and images use the fetched document’s web location, including during the current session after saving locally. Remote images still follow Settings › General › Load remote images. **More (…) › Source** offers **Open Original in Browser** and **Copy Source URL**. This source information lasts for the current document session; reopening a saved copy uses its local folder.

## The window

The page takes the whole window. A few controls float on glass above it and fade while you type:

- **Library** (sidebar button, ⌃⌘S) shows your open files and library notes. See [Library and find](library.md).
- **Title**: click the document's name to rename it, move it or browse its versions.
- **Contents and Links** (right sidebar button) slides in a pane with two tabs. **Contents** lists the document's level 1 and 2 headings, with level 2 headings indented under their section; click one to move to that heading. **Links** lists the document's links; see [Links panel](images-and-links.md#links-panel). The text moves beside the pane so none of it is hidden, and the pane stays open while you read and edit; close it with the same button or Esc. It updates as you edit and remembers the last tab.
- **Apple Intelligence** (the multicolor symbol) opens writing actions for the whole document. See [Apple Intelligence](intelligence.md).
- **MD** switches to the Markdown lens (⌘/). See [Two lenses](lenses.md).
- **More** (…) holds Share, Export, Source (for documents opened from URLs), Knowledge, Find, the word count and Settings.

## Start writing

Type as you would in any text editor. Markdown formats as you type: `# ` starts a heading, `- ` a list, `**bold**` turns bold. To see everything you can insert, type `/` at the start of a line. See [Formatting](formatting.md).

## Take the tour

The first time you open Markify, it opens **Welcome to Markify**, a document that tours the main features by letting you try them: the two lenses, the format bar and slash menu, tasks, tables, callouts, code, math, diagrams, images, the library, Apple Intelligence and export. It's saved in your library folder, so you can edit it freely.

[Open the Welcome tour](markify://welcome) anytime, or choose **Help › Welcome to Markify**. If you've deleted it, Markify puts a fresh copy back.
