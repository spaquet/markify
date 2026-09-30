# Agent reports in Markify

Status: implementation on `feature/agent-reports`. Phase 1 implements the shared
transport, Claude package, and help. Phase 2 adds a separate Codex package using
the same launcher. Phase 3 adds a separate OpenCode tool package.
Reviewed against the repository and official agent documentation on 2026-09-30.

## Goal and phases

Send a coding agent's Markdown report directly to a new, editable, untitled Markify document. Start in the Rendered lens; preserve the exact source. The user can read it, switch lenses, edit, export, or explicitly save it.

| Phase | Deliverable |
| --- | --- |
| 1 — Claude Code | Shared app and CLI transport, clipboard entry point, Claude plugin, installation help, tests. |
| 2 — Codex | Separate Codex plugin and installation help using the same CLI and app behavior. |
| 3 — OpenCode | OpenCode tool/plugin package and installation help using the same transport. |

Each phase must work independently. The plugin installs agent instructions and a small launcher; Markify remains a separately installed macOS app. Local agent sessions on the same Mac are the initial target. Remote, container, and cloud sessions need a separate handoff and are outside these phases.

## Review of the original draft

Keep the three entry points—CLI, URL, clipboard—feeding one app operation. Keep Markdown out of URLs and use the existing `markify://` handler and single-instance handoff. A local CLI is sufficient; no HTTP service or MCP server is needed initially.

Corrections and implementation gates:

- **Document construction needs a spike.** The draft's `pendingText` mechanism is a candidate, not a proven document-opening API. Confirm when SwiftUI evaluates the `DocumentGroup` factory, how creation completes, and how to identify the resulting document. Serialize requests on the main actor; never allow two URL requests or a concurrent ⌘N to overwrite or consume each other's payload. Clear failed requests. Use a small FIFO only if creation is deferred.
- **Clean-close behavior needs proof.** Set the imported source as the initial document value, rather than injecting it through an editor binding after opening. Confirm that the untouched document is unedited, closes without a save prompt, and that edits restore normal save/close protection. Do not clear change counts after user edits. Account for macOS autosave/recovery: “no document file is explicitly saved until Save” does not promise that no temporary or recovery data exists.
- **Title is metadata.** Do not assume `currentDocument` immediately identifies the new window or that `displayName` is assignable. Use the imported title in Markify's existing title capsule and save-name suggestion; verify native window naming separately. Never prepend a heading to change the source.
- **Relative paths are Phase 1 scope.** Links and images are part of reading a report. Include export and save behavior, not just the editor's image loader.
- **CLI bundled does not mean CLI on PATH.** `help/command-line.md` already documents the app executable and an optional symlink. Agent launchers should resolve the installed app without requiring that symlink.
- **Cold launch still needs testing.** `handedOff` handles a second instance's URLs; it does not establish readiness of SwiftUI document creation on a first launch. Wait for readiness and coordinate with startup restoration to avoid an extra empty/Welcome window caused by a race.
- **Defer `--reuse`.** Opening a fresh document is the first release. Replacement introduces session routing and data-loss risks that the initial reading workflow does not need.

If the document spike fails, revisit document creation before shipping. Opening the cache file as a normal document is not equivalent: Save would target the cache and the document would have the wrong identity.

## Shared app operation

Provide one main-actor operation with the conceptual signature:

```swift
openUntitled(text: String, title: String?, baseDirectory: URL?)
```

Put document construction in `MarkifyDocument.swift` and opening/lifecycle coordination in `MarkifyApp.swift`. Keep transient import metadata with the document instance, excluded from `fileWrapper` and ordinary file reads. Pass it to `ContentView` and `NativeEditor` as needed. A regular ⌘N still creates an empty document with the configured default lens.

Imported documents start Rendered without changing the user's global lens preference. Once opened, they use the existing editor, source offsets, undo, renderer, and Save command. The transport does not execute code or follow links; existing remote-image settings continue to apply.

## CLI and inbox protocol

```text
markify view [FILE | -] [--title TITLE] [--base DIRECTORY]
```

No input path, or `-`, reads stdin. A file supplies its UTF-8 contents without modifying the file. Reject malformed UTF-8, invalid options, and missing option values. Preserve Unicode, line endings, and final-newline presence.

Default base: the input file's parent for file input, current working directory for stdin. `--base` overrides either; resolve it to an absolute existing directory. Titles and paths travel as data, never interpolated into shell commands.

Use one atomic UTF-8 JSON envelope per request:

```json
{
  "version": 1,
  "text": "# Report\n\nMarkdown source…\n",
  "title": "Claude report",
  "baseDirectory": "/Users/me/project"
}
```

Store it at `~/Library/Caches/com.stephanepaquet.Markify/Inbox/<uuid>.json`. One envelope avoids coordinating a Markdown file and a metadata sidecar, and keeps title/base out of the URL. Write privately (directory mode 0700, file mode 0600), atomically, before dispatching:

```text
/usr/bin/open -b com.stephanepaquet.Markify markify://view?id=<uuid>
```

Launch with Foundation `Process` and an argument array. Construct the URL with `URLComponents`. The app accepts exactly one valid UUID, derives the path inside its inbox, rejects symlinks/nonregular files and unsupported envelopes, and reports read/decode errors. Never accept an arbitrary payload file path from a URL. Enforce a documented payload limit in both processes (proposed: 10 MiB per envelope).

Delete only the inbox envelope after successful document creation. Never delete the original CLI input file. Retain a failed request for retry; remove stale inbox requests older than 24 hours on later CLI invocations. Explain that these are temporary local report contents. Duplicate delivery of a consumed ID must not open an empty document.

Keep exit codes consistent with the existing CLI: 0 for successful dispatch, 1 for input/write/launch errors, 2 for invalid arguments. Exit 0 means Launch Services accepted the request, not that the app has rendered it. App-side failures need a visible error. An acknowledgment protocol can follow if reliable synchronous confirmation becomes necessary.

## Relative resources, export, and Save

Keep actual `fileURL` nil until Save. Add a distinct base directory for imported documents; do not assign a fictitious file URL throughout the app. Reuse existing resolution helpers with an optional base where possible.

Audit these consumers:

- `NativeEditor` / `MarkdownTextView.imageURL`, link clicks, note drops, and inserted image/link paths.
- `Knowledge.follow`, `OKFLinks.resolve`, and the Links panel.
- `DocumentExport.Context` and `MarkdownPage.Context` for embedded images and destination-relative links in HTML/PDF.

The supplied base establishes local relative paths. It does not automatically enroll an untitled report in an OKF bundle or make library/log/index operations available. Without a known bundle root, `/…` is an ordinary absolute filesystem path.

After Save, the saved document's directory becomes the normal base. Phase 1 preserves Markdown source unchanged, so Save into a different directory may change relative-link meaning. Document that limitation and recommend saving beside the referenced project assets or using absolute links. Automatic path rewriting or asset copying is a separate feature.

## Clipboard

Add File › New from Clipboard in `CommandGroup(after: .newItem)`, using plain text from `NSPasteboard.general`. Disable it when there is no text. Use the same opening operation; no base directory is inferred from clipboard contents.

Choose a shortcut after checking the native Paste and Match Style command and `Shortcuts.actions`. Do not reserve ⇧⌘V in the proposal without checking conflicts. Document the final shortcut in `help/shortcuts.md` and the configurable shortcut list if applicable.

## Phase 1 — Claude Code

Package a `markify` plugin with `.claude-plugin/plugin.json`, `skills/view/SKILL.md`, and a small launcher under `scripts/`. Expose `/markify:view` to send a requested report or the preceding report to Markify. The skill passes Markdown as data through stdin; it does not interpolate generated content into shell code. If it recreates an earlier response from conversation context, do not claim byte-for-byte transcript extraction.

Resolve `markify` on PATH first, then the installed app's `Contents/MacOS/markify` through Launch Services; support an explicit executable path for nonstandard installations. Fail clearly when the app or `view` command is missing. Use the same discovery convention in later agent packages.

Publish a first-party marketplace catalog at `.claude-plugin/marketplace.json` in a repository containing the plugin. Proposed marketplace name: `markify`. If hosted in this repository, the planned installation is:

```text
/plugin marketplace add spaquet/markify
/plugin install markify@markify
/markify:view
```

These commands are verified against an isolated local marketplace installation with Claude Code 2.1.285; GitHub installation requires publishing the branch contents. Verify them from a clean Claude installation before publishing. Adding Markify's own marketplace is distinct from acceptance into Anthropic's official marketplace. See [Claude plugins](https://code.claude.com/docs/en/plugins) and [marketplace setup](https://code.claude.com/docs/en/plugin-marketplaces).

Provide an optional automatic mode after the on-demand command works. Current [Stop hook documentation](https://code.claude.com/docs/en/hooks#stop) exposes `last_assistant_message`, `cwd`, and `session_id`: use the message directly instead of parsing `transcript_path`. Skip empty messages and `stop_hook_active` continuations; do not block or restart the conversation on viewer failure. Explicitly opt in to opening each completed response. A JSON parser dependency such as `jq`, if used, must be checked and documented. No automatic hook is enabled merely by installing the basic plugin.

Without reuse, automatic mode opens a new document per response. Keep it optional and describe that behavior. Manual fallback:

```sh
pbpaste | /Applications/Markify.app/Contents/MacOS/markify view - --title 'Claude report'
```

## Phase 2 — Codex

Create a separate Codex package containing a report-viewing skill and launcher. Use the manifest/catalog supported by the target Codex release; share the CLI contract, not Claude's manifest or transcript assumptions. No app transport change should be required.

Current [official OpenAI packaging documentation](https://developers.openai.com/plugins/build/plugins) describes a portable root `plugin.json`, `skills/`, and a `.agents/plugins/marketplace.json` catalog. It documents adding a marketplace with `codex plugin marketplace add`; the published installation surface must be verified for the supported Codex CLI/app versions. Do not invent a `codex plugin install` command or promise Claude-style slash commands. Acceptance in an official directory is a separate publication step.

Before release, test a clean marketplace install and explicit skill invocation that sends a report locally. Include the precise verified commands/UI steps, minimum compatible versions, update/uninstall steps, and normal sandbox approval requirements in the help. Do not bypass agent sandbox permissions to write the inbox or launch Markify. Support an on-demand skill first; defer automatic response hooks until the supported Codex lifecycle API is established.

## Phase 3 — OpenCode

Implement a small tool accepting Markdown, optional title, and base directory, then call the same CLI through stdin and an argument array. Distribute using OpenCode's supported plugin mechanism. Current [OpenCode plugin documentation](https://opencode.ai/docs/plugins/) supports npm packages in its configuration and local plugin directories; do not promise a Claude/Codex-style marketplace. Recheck the schema and APIs at implementation time, including supported OpenCode versions.

Release with installation, invocation, update, uninstall, and troubleshooting instructions. Defer automatic session-event delivery until explicit tool invocation is verified.

## Help and release deliverables

In Phase 1 add `help/coding-agents.md` with prerequisites, Claude marketplace installation, first report, clipboard/CLI fallback, optional automation, privacy, Save/base limitations, troubleshooting, and uninstall. Mark Codex and OpenCode as planned until their phases ship. Extend the same page per phase with tested installation steps for that agent.

Update `help/command-line.md` for `view`, stdin, file input, title/base defaults, payload limit, and dispatch-only success. Its current statement that the CLI never opens a window must become specific to `check` and `export`. Update `help/shortcuts.md` for the clipboard command and link the new guide from appropriate existing help pages. Run `scripts/build-help.sh` and include generated Help Book and website outputs with each user-visible phase. Do not publish installation instructions as working before the plugin artifacts exist.

## Acceptance checks

Phase 1 is complete when all of these pass:

1. App integration test/manual lifecycle check: exact imported source; actual `fileURL == nil`; Rendered override; clean initial close; edit/save protection; Save panel/title; regular ⌘N unaffected.
2. Lifecycle check: already-running app, cold launch, first launch, restored documents, duplicate instance handoff, and multiple rapid requests preserve the correct text/title/base pair.
3. Inbox tests: valid consumption and deletion after creation; invalid UUID/envelope/UTF-8, symlink, oversized/missing input, duplicate URL, and failed creation do not delete unrelated files or consume another request.
4. Extend `scripts/test-cli.sh` for stdin/file/default input, option errors, Unicode/newlines, base defaults/overrides, envelope permissions, and launch failure. Exercise launch argument construction without opening UI for every parser case; keep one real CLI-to-app smoke check.
5. Resource checks: relative image and note link in editor and Links panel; HTML/PDF export from an untitled report; Save beside assets and Save elsewhere match documented behavior.
6. Clean Claude marketplace install, `/markify:view`, optional Stop hook, missing/outdated Markify, paths with spaces, and uninstall. Help generation is current.

Phases 2 and 3 add clean-install and report-delivery checks for their agent, including executable discovery and permission-denial behavior, while rerunning the shared transport smoke check.

## Deferred window reuse

If frequent automatic delivery makes it necessary, introduce a session-keyed option rather than replacing “the last viewer.” Only replace a still-untitled, unedited imported document associated with that agent session. A saved or edited document must be preserved and a new one opened. Serialize per-session arrivals, avoid stale responses overwriting newer ones, and test undo/dirty-state behavior before enabling reuse. Never replace the frontmost arbitrary document.

## Phase 1 validation

Verified with Claude Code 2.1.285: isolated local marketplace add/install, skill
inventory, uninstall, and catalog removal. Launcher tests cover exact stdin, paths
with spaces, missing/outdated CLI errors with GitHub download links, and optional
Stop-hook failure/continuation handling.

App tests cover clean initial documents, independent Rendered windows despite a
Markdown default, real editor changes becoming dirty after the normal Cocoa undo
event closes, source preservation, inbox consumption, and resource resolution.
All app tests, 42 Markdown package tests, 36 OKF package tests, and CLI tests pass.
The local smoke check exercises cold URL launch and two rapid real CLI dispatches.
The CLI targets an already-running copy by its bundle path to avoid Launch Services
selecting an older installed Xcode build. Public marketplace publication is pending.

## Phase 2 validation

Codex CLI 0.159.2 successfully adds the local `.agents/plugins/marketplace.json`
catalog and installs the portable `agents/codex/plugin.json` package in an isolated
configuration. `codex plugin list` reports it installed and enabled. The skill
has its own copy of the tested launcher, kept identical by the integration check,
so marketplace installation does not depend on files outside its package.
Missing/outdated Markify errors include the GitHub Releases link. The help documents
the verified `codex plugin add` / `remove` commands and `$markify-view` invocation.
Uninstall/catalog removal and the skill-creator validator also pass. Help ordering
uses the page slug to break equal-order ties, keeping generated navigation stable.

## Phase 3 validation

The self-contained npm package uses OpenCode’s 1.18.33 plugin API. An isolated
configuration-directory install is detected by `opencode debug config`. Package
install and direct tool execution preserve Unicode, CRLF, literal shell
characters, title argument boundaries, and the session base directory. Permission
denial prevents any CLI execution. Missing-app errors survive early stdin closure
and retain the GitHub Releases link. All three launchers are byte-identical and
pass the shared missing/outdated-app and dispatch-failure checks. Installation,
updates, uninstall, and permission settings are documented in the help. Publication
to npm or agent catalogs is a separate release action.
The real URL and rapid CLI-to-app smoke checks pass again after all three phases.
