---
name: view
description: Send a Markdown report to Markify for comfortable reading on this Mac. Use when the user asks to open or read an answer, report, plan, or brainstorm in Markify.
disable-model-invocation: true
argument-hint: "[report request or Markdown file]"
---

Open the requested Markdown in Markify using the bundled launcher:

```sh
bash "${CLAUDE_PLUGIN_ROOT}/scripts/view.sh" - --title 'Claude report' --base "$PWD"
```

Supply the report as UTF-8 stdin. Use a shell-safe data mechanism (a quoted heredoc with a delimiter absent from the text, or an existing file redirected to stdin). Never interpolate report text into shell code, `echo`, or a command substitution. Do not write into the user's project just to deliver a report. For an existing file, pass its quoted path instead of `-`; omit `--base` so its parent directory is used.

With arguments, write the requested report and send it. With no arguments, send the preceding substantive report from conversation context. Do not add an outer code fence or rewrite its links. If the prior response is unavailable, say so instead of inventing it. Sending from conversation context does not guarantee byte-for-byte transcript recovery.

Keep the source intact. Set the base directory to the relevant local project so relative links and images work. Use normal agent permission prompts if launch or cache access requires approval; do not bypass a sandbox.

On success, say the report was sent to Markify. This opens a new, editable, untitled document in the Rendered lens; the user saves it with ⌘S. Do not claim it was saved or that rendering was acknowledged. On failure, show the launcher error and recommend installing/updating Markify or setting MARKIFY_CLI. Do not enable an automatic Stop hook unless explicitly requested.
