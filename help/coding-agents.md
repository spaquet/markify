---
title: Coding agents
description: Read coding-agent reports in Markify, with Claude Code and Codex plugin installation.
order: 12
keywords: claude, codex, opencode, agent, report, plugin, marketplace, clipboard
---
# Coding agents

Send a long Markdown answer to Markify to read it on the rendered page. Each report opens as a new, editable, untitled document. Press ⌘/ to inspect the Markdown and ⌘S to keep it. An untouched report closes without a save prompt; after edits, normal save protection applies.

Install [Markify from GitHub Releases](https://github.com/spaquet/markify/releases/latest), using a version whose [command line](command-line.md) help lists `view`. The agent and Markify must run on the same Mac. A plugin does not install the macOS app. Remote, container, and cloud sessions cannot directly open a local window through this integration.

## Claude Code

The Markify plugin adds `/markify:view`. In Claude Code, add Markify's own marketplace and install the plugin:

```text
/plugin marketplace add spaquet/markify
/plugin install markify@markify
```

These repository installation commands become available when the plugin is included in the published repository. For a source checkout containing this feature, use `/plugin marketplace add /absolute/path/to/markify` instead. Install from the plugin details panel if prompted, then start a new session.

Ask for a report, then run:

```text
/markify:view
```

Or request one directly, for example `/markify:view Explain the architecture we just discussed`. Claude sends Markdown through the bundled CLI; you do not need a `markify` symlink. Sending an earlier response from conversation context can differ from its exact original wording.

To update, run `/plugin marketplace update markify`, then `/plugin update markify@markify` and restart the session. To remove, run `/plugin uninstall markify@markify`; optionally remove its catalog with `/plugin marketplace remove markify`. This is Markify's first-party catalog, separate from Anthropic's official marketplace. See [Claude's plugin guide](https://code.claude.com/docs/en/plugins).

### Optional automatic responses

The plugin does not enable automatic viewing. If you want every completed response to open a new document, install `jq` and use Claude's `/hooks` interface to add a **Stop** command pointing to the plugin's `scripts/stop.sh`:

```sh
bash "/absolute/path/to/markify/agents/claude/scripts/stop.sh"
```

Use a stable checkout path for this optional command; marketplace cache paths may change on updates. The script reads `last_assistant_message` from the hook input, skips empty messages and hook continuations, and reports viewer failures without blocking Claude. It does not parse transcripts or reuse windows. Remove the Stop entry in `/hooks` to turn it off. Older Claude versions without that message field need updating for automatic mode. See [Claude's Stop hook reference](https://code.claude.com/docs/en/hooks#stop).

## Codex

The separate Codex plugin adds the `markify-view` skill and uses the same local report transport. Installation was tested with Codex CLI 0.159.2. Use a version that provides these plugin commands:

```sh
codex plugin marketplace add spaquet/markify
codex plugin add markify@markify
```

As with Claude, the GitHub commands require the package to be published. In a source checkout, replace the first command with `codex plugin marketplace add /absolute/path/to/markify`. Start a new Codex thread after installation, then invoke the skill:

```text
$markify-view Send the report we just discussed to Markify.
```

You can also ask Codex to open a report in Markify in ordinary language. The launcher checks for the app and the `view` command; if either is missing, it reports the problem and links to [GitHub Releases](https://github.com/spaquet/markify/releases/latest). You do not need a CLI symlink. Allow the normal sandbox request to launch Markify or write the report cache; if denied, use the clipboard fallback.

For a Git-backed catalog, refresh it with `codex plugin marketplace upgrade markify`, then reinstall the package with `codex plugin remove markify@markify` and `codex plugin add markify@markify`. Start a new thread. To uninstall, run `codex plugin remove markify@markify`; optionally run `codex plugin marketplace remove markify` to remove the catalog. This package does not install an automatic response hook or a cloud connection. See [OpenAI's plugin packaging guide](https://developers.openai.com/plugins/build/plugins).

## OpenCode

The dedicated OpenCode tool is planned in Phase 3. For now, ask the agent to send its Markdown through the `view` command below.

## Clipboard and manual use

Copy the answer, then choose **File › New from Clipboard** (⌃⌥⌘V). Clipboard reports have no project base, so use absolute paths for local links and images.

From Terminal:

```sh
pbpaste | /Applications/Markify.app/Contents/MacOS/markify view - --title 'Agent report' --base "$PWD"
/Applications/Markify.app/Contents/MacOS/markify view report.md --title 'Architecture review'
```

File input resolves relative resources beside the input file; stdin uses the current directory unless `--base` specifies another existing directory. File input is copied into a new document; the original file is never changed.

## Save, privacy, and troubleshooting

Save beside the referenced project assets, or use absolute paths. Saving into another folder changes how relative links resolve; Markify preserves the Markdown and does not copy assets or rewrite paths during the first save.

Reports are transferred locally through a private cache envelope, limited to 10 MiB including JSON metadata. Markify deletes it after creating the document. Failed transfers remain available temporarily; a later `view` command removes envelopes older than 24 hours. macOS may keep document recovery data. Markify's existing remote-image setting still controls image downloads; no extra AI service is used by this handoff.

If the launcher cannot find Markify, install the app, add its CLI to PATH, or set `MARKIFY_CLI` to the absolute path of `Markify.app/Contents/MacOS/markify` in the agent's environment. An “unsupported view” error means that executable needs updating. Missing or outdated app messages include a GitHub Releases download link. For local source testing, point it to `MarkifyCLI/.build/debug/markify`.

Allow the agent's normal permission request to launch the app or write the cache. If denied, use New from Clipboard. A successful command means macOS accepted the launch request; an app-side failure appears in Markify. A missing/already-opened report URL cannot reopen a consumed request: send the report again.
