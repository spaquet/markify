<!-- Command line — Markify Help. Web page: https://spaquet.github.io/markify/help/command-line.html -->

# Command line

Markify includes a separate `markify` command for scripts. `check` and `export` run without opening an editor window; `view` opens Markdown in the app. After installing the app, find it at `/Applications/Markify.app/Contents/Helpers/markify`. If you installed Markify elsewhere, use the matching path inside that app.

To call it as `markify` from any folder, link it into a directory on your `PATH`:

```sh
ln -s /Applications/Markify.app/Contents/Helpers/markify /usr/local/bin/markify
markify --help
```

If you build from source, run `swift build -c release --package-path MarkifyCLI`; the executable is in `MarkifyCLI/.build/release/markify`.

## Read a report

```sh
markify view report.md --title 'Architecture review'
pbpaste | markify view - --title 'Agent report' --base "$PWD"
```

`markify view [FILE | -] [--title TITLE] [--base DIRECTORY]` opens UTF-8 Markdown as a new, untitled document in the Rendered lens. Omit FILE or use `-` to read stdin. The source file is never changed. Press ⌘S to save the new document.

Relative images and links use the input file's parent directory, or the current directory for stdin. `--base` overrides that with an existing directory. Without `--title`, the document uses its frontmatter title or first heading. The private cache envelope, including metadata, must fit within 10 MiB; invalid UTF-8 is rejected.

Exit status 0 means macOS accepted the app launch request, rather than confirming rendering. Input, cache, and launch errors return 1; invalid arguments return 2. See [Coding agents](https://spaquet.github.io/markify/help/coding-agents.md) for plugin installation and clipboard use.

## Validate a knowledge bundle

```sh
markify check path/to/bundle
```

The command reads the folder without changing it. Each finding includes its file path, severity and message. It exits with status 0 if there are no errors. Warnings and information are printed but do not fail the command. Errors, unreadable files and invalid paths return a nonzero status.

For a CI job, add a step such as:

```sh
/Applications/Markify.app/Contents/Helpers/markify check knowledge/
```

## Export HTML

```sh
markify export notes/example.md --html --output public/example.html
```

The output folder must exist. The command writes a self-contained HTML page, embeds local images, and rewrites links to other files relative to the output page. It accepts `.md`, `.markdown` and `.mdx` files. It leaves the source file unchanged and reports read or write failures on stderr with a nonzero status.

The CLI renders math as LaTeX code and Mermaid fences as code blocks. Use the app's HTML export when you need their SVG rendering or syntax-colored code.

Run `markify --help` for the full syntax and exit status. To open a file in the editor from Terminal, use `open -a Markify file.md`.
