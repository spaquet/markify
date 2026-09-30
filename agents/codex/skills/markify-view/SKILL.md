---
name: markify-view
description: Send an answer, report, plan, or brainstorm to Markify when the user asks to read Markdown there on this Mac.
---

Send the requested Markdown through this skill's `scripts/view.sh` launcher. Resolve its path relative to this SKILL.md, not the project directory:

```sh
bash "/absolute/path/to/this/skill/scripts/view.sh" - --title 'Codex report' --base "$PWD"
```

Supply UTF-8 text through stdin using a shell-safe data mechanism, such as a quoted heredoc with a delimiter absent from the text, or an existing file redirected to stdin. Never interpolate report contents into shell code. For an existing Markdown file, pass its quoted path instead of `-` and omit `--base` to resolve resources beside that file. Do not create a project file merely to deliver a report.

If the user asks to view a previous answer, use the substantive report available in conversation context. Preserve its Markdown and links without an outer code fence; do not invent a missing response or claim exact transcript recovery. Choose the relevant local project as the base for relative resources.

The launcher checks for Markify and its `view` command. On a missing or outdated app, report the error and link to [Markify downloads](https://github.com/spaquet/markify/releases/latest). `MARKIFY_CLI` can point to a nonstandard installation's bundled executable. On permission denial, stop the delivery attempt and offer File › New from Clipboard; do not bypass the sandbox or change agent settings.

Success means the report was sent to a new, editable, untitled document in the Rendered lens. The user saves it with ⌘S. Do not claim it was saved or that rendering was acknowledged. Automatic response hooks and window replacement are not part of this skill.
