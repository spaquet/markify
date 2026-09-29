---
title: Command line
description: Validate OKF bundles and export Markdown to HTML from Terminal or a script.
order: 10
keywords: cli, terminal, command line, markify, check, validation, export, html, ci
---
# Command line

Markify includes a separate `markify` command for scripts. It runs without opening an editor window. After installing the app, find it at `/Applications/Markify.app/Contents/MacOS/markify`. If you installed Markify elsewhere, use the matching path inside that app.

To call it as `markify` from any folder, link it into a directory on your `PATH`:

```sh
ln -s /Applications/Markify.app/Contents/MacOS/markify /usr/local/bin/markify
markify --help
```

If you build from source, run `swift build -c release --package-path MarkifyCLI`; the executable is in `MarkifyCLI/.build/release/markify`.

## Validate a knowledge bundle

```sh
markify check path/to/bundle
```

The command reads the folder without changing it. Each finding includes its file path, severity and message. It exits with status 0 if there are no errors. Warnings and information are printed but do not fail the command. Errors, unreadable files and invalid paths return a nonzero status.

For a CI job, add a step such as:

```sh
/Applications/Markify.app/Contents/MacOS/markify check knowledge/
```

## Export HTML

```sh
markify export notes/example.md --html --output public/example.html
```

The output folder must exist. The command writes a self-contained HTML page, embeds local images, and rewrites links to other files relative to the output page. It accepts `.md`, `.markdown` and `.mdx` files. It leaves the source file unchanged and reports read or write failures on stderr with a nonzero status.

The CLI renders math as LaTeX code and Mermaid fences as code blocks. Use the app's HTML export when you need their SVG rendering or syntax-colored code.

Run `markify --help` for the full syntax and exit status. To open a file in the editor from Terminal, use `open -a Markify file.md`.
