<!-- Getting started — Markify Help. Web page: https://spaquet.github.io/markify/help/getting-started.html -->

# Getting started

## Create or open a document

- **File › New** (⌘N) creates an untitled document. Settings › General › *New documents are saved to* decides whether it saves into your library folder or asks each time.
- **File › Open…** (⌘O) opens any `.md`, `.markdown` or `.mdx` file on your Mac. You can also drag a file onto the Markify icon.
- **File › Open URL…** opens a file from the web or browses a GitHub or GitLab repository. See [Open a URL](#open-a-url).
- **File › Open Folder…** chooses a folder for the Library sidebar. Use this for a folder of notes; the standard **Open…** command accepts individual files.
- **File › Open Recent** lists the files you used lately.

Opening a file replaces an untouched, empty startup document in the same window, keeping its size. Once you edit that document, files open in separate windows.

Markify saves automatically, like other Mac apps. Once an edit has autosaved, reloading the file does not undo it. Use **⌘Z** for recent edits or macOS version history for earlier saved text.

### Recover an earlier version

Save a document to a file before using version history. Choose **File › Revert To › Browse All Versions…**, or click the document's title and choose **Browse All Versions…**. Select an earlier version and click **Restore** to make it current. Hold **Option** to choose **Restore a Copy**, keeping the current document intact. Choose **Done** to leave without restoring.

macOS manages version checkpoints and their storage; history does not capture every keystroke. Markify does not create a separate backup folder. Versions recover the Markdown text, including image paths, but do not restore changes to linked images or other files. Available history depends on the file's storage location; keep backups for long-term recovery.

External-change prompts pause while the version browser is open. Restoring an earlier version deliberately replaces the current file; use Restore a Copy if you want to preserve the current content, including edits from another app.

### Changes from another app

If another app changes an open file, Markify notifies you, including when text is added, updated or removed. Repeated external edits share one prompt; your choice uses the latest contents on disk. Before **Reload** or **Merge**, Markify saves both your current text (including unsaved edits) and the latest external text in **Browse All Versions…**. If either version cannot be saved, Markify reports the error and leaves your current text intact. Choose **Keep My Changes** to leave your text alone, **Reload** to replace it with the version on disk, or **Merge** to combine both versions. Merge marks overlapping edits with `<<<<<<< My Changes`, `||||||| Original`, `=======` and `>>>>>>> External Changes`; edit those sections to keep the text you want and remove the markers before saving. Keeping your changes leaves the external file alone until Markify saves your version. Merging can be undone with **⌘Z**.

To preview a Markdown file without opening it, select a `.md`, `.markdown` or `.mdx` file in Finder and press Space. Markify's Quick Look extension shows formatted Markdown, HTML, math and Mermaid diagrams for files up to 2 MB. It loads local images referenced by the document, without a folder permission step; remote images are omitted. Click linked local Markdown files to open them in Markify; web links open in your browser and anchor links stay in the preview. See [Images and links](https://spaquet.github.io/markify/help/images-and-links.md#links-in-finder-previews).

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

- **Library** (sidebar button, ⌃⌘S) shows your open files and library notes. See [Library and find](https://spaquet.github.io/markify/help/library.md).
- **Title**: click the document's name to rename it, move it or browse its versions.
- **Contents and Links** (right sidebar button) slides in a pane with two tabs; see [Contents](#contents) and [Links panel](https://spaquet.github.io/markify/help/images-and-links.md#links-panel). The pane slides over the page; click the page, the same button or press Esc to close it. It updates as you edit and remembers the last tab.
- **Apple Intelligence** (the multicolor symbol) opens writing actions for the whole document. See [Apple Intelligence](https://spaquet.github.io/markify/help/intelligence.md).
- **MD** switches to the Markdown lens (⌘/). See [Two lenses](https://spaquet.github.io/markify/help/lenses.md).
- **More** (…) holds Share, Export, Source (for documents opened from URLs), Knowledge, Find, the word count and Settings.

## Contents

The **Contents** tab outlines the document's headings at every level, with guide lines showing which section each sits in. Click a heading to move the caret to it; it scrolls to the top of the page. Click the triangle beside a heading to fold or unfold its section.

- **H1, H2, H3, All** choose how deep the outline goes. Markify remembers the depth.
- **Filter headings** shows the headings whose title contains what you type, inside their sections.
- The heading you're reading is highlighted, and its guide line turns blue. The bar at the bottom shows how far through the document you've scrolled.
- **Insert Table of Contents** adds a Contents card at the caret, listing the headings shown at the current depth. Click an entry to go to its heading. The card keeps itself up to date as you add, rename or remove headings, a moment after you stop typing; **⌘Z** undoes an update. When the document has one, the button reads **Update Table of Contents** and rebuilds it at the current depth.

In the file, the table of contents is an ordinary list of links between two comments, `<!-- toc -->` and `<!-- /toc -->`, so other apps and GitHub show it as a list. The Markdown lens shows that source; exported HTML and PDF show the card.

## Start writing

Type as you would in any text editor. Markdown formats as you type: `# ` starts a heading, `- ` a list, `**bold**` turns bold. To see everything you can insert, type `/` at the start of a line. See [Formatting](https://spaquet.github.io/markify/help/formatting.md).

## Take the tour

The first time you open Markify, it opens **Welcome to Markify**, a document that tours the main features by letting you try them: the two lenses, the format bar and slash menu, tasks, tables, callouts, code, math, diagrams, images, the library, Apple Intelligence and export. It's saved in your library folder, so you can edit it freely.

[Open the Welcome tour](markify://welcome) anytime, or choose **Help › Welcome to Markify**. If you've deleted it, Markify puts a fresh copy back.
