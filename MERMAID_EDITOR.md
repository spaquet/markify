# Mermaid editor

Status: requirements draft for discussion. This document proposes behavior and scope; it does not record approved design decisions or an implemented feature.

## The gap

Markify is a Markdown editor without markup. For Mermaid, that promise currently stops at reading: the Rendered lens displays a diagram, but creating or changing one requires writing Mermaid syntax.

We need a way to create and edit diagrams through their visible parts, while keeping ordinary Mermaid in the Markdown file. Someone should be able to draw a simple process, change a label and connect a decision to two outcomes without learning node IDs, arrows or fence syntax.

## What exists today

- `/Mermaid` inserts a fenced starter diagram (`graph TD` with `A --> B`) through `SlashEntry` in [ContentView.swift](Markify/ContentView.swift).
- The Rendered lens displays fenced Mermaid blocks as diagrams; the Markdown lens exposes their source. Invalid diagrams show source with Mermaid's error message.
- [MermaidRenderer](Markify/Mermaid.swift) renders with the bundled Mermaid in an offscreen WebView, without network access, and supplies SVG for export.
- [NativeEditor.swift](Markify/NativeEditor.swift) handles diagram styling and drawing. Diagram placement follows the document's text layout.
- Mermaid also appears inside table cells; see [Formatting](help/formatting.md).

These are foundations to reuse. Rendering a diagram does not yet provide the editable objects or source mappings a visual editor needs.

## Product requirements

### Enable explicitly

- Visual Mermaid editing is **off by default**, including for existing installations.
- Add a **Mermaid editor** toggle in Settings › Editor. Use the app's existing preferences pattern to remember this app-wide choice across launches and apply it to all document windows.
- With the toggle off, `/Mermaid` keeps inserting the current fenced starter diagram, and visual editing actions are hidden. Diagram rendering, source editing and export remain available.
- With the toggle on, `/Mermaid` opens the visual creation flow and existing diagrams expose the visual editing action described below.
- Changing the toggle never rewrites a document. Turning it off while a draft is open must let the user apply or cancel that draft before closing the editor; it must not silently discard work.

### Create without syntax

With the Mermaid editor enabled, the proposed first release focuses on flowcharts: steps, decisions and connections. Other diagram families remain readable and editable through source until we define their visual interactions.

1. Choose Mermaid from the slash menu and enter a visual editor at the insertion point.
2. Start with a small valid flowchart and immediately edit its labels.
3. Add a step or decision, connect two nodes, label a connection and choose the diagram's direction through visible controls.
4. Apply the diagram to the document without typing Mermaid or Markdown fences.
5. Cancel creation without leaving a starter block behind.

### Edit what is visible

- With the Mermaid editor enabled, an existing diagram exposes an **Edit diagram** action in the Rendered lens, available by keyboard as well as pointer.
- Selecting a node exposes its label and supported shape. Selecting a connection exposes its endpoints, label and supported line/arrow style.
- Users can add and delete nodes and connections. Deleting a connected node makes the affected connections clear before committing the deletion.
- Mermaid performs automatic layout. Direction controls affect the saved diagram; first-release editing does not require dragging nodes into fixed positions.
- Every pointer operation has a keyboard-accessible control. VoiceOver identifies nodes, connections, selection and available actions.
- Source editing remains available for people who want it and for constructs outside visual editing coverage.

### Stay part of the document

Proposed interaction: a temporary editor sheet with the diagram and contextual controls. It opens from the page, then returns focus to that diagram when dismissed. Exact layout needs a design pass consistent with Markify's existing surfaces.

- Keep the document's single-column reading experience and avoid permanent diagram chrome.
- Work on a temporary draft. **Apply** commits the change as one document undo step; **Cancel** or Escape leaves the document untouched.
- Support undo/redo within the draft. After Apply, document undo restores the previous block and redo restores the edited block.
- Opening, selecting, zooming or closing an unchanged diagram never rewrites its source or marks the document modified.
- Switching between visual and source editing within the draft retains edits and makes validation failures clear.

## Source and compatibility requirements

The Markdown source remains authoritative. The editor must write a standard fenced Mermaid block, with no required sidecar file, proprietary metadata or rendered image replacing the source.

| Situation | Required behavior |
| --- | --- |
| New supported flowchart | Generate valid Mermaid using stable node identifiers; labels are not identifiers. |
| Existing supported flowchart | Preserve identifiers, comments, directives, styling and unrelated text; change only what the action requires. |
| Valid syntax the visual editor cannot safely edit | Keep rendering and source editing available. Explain the visual editing limit without converting or simplifying the diagram. |
| Invalid source | Retain the draft, show the error and allow source repair or cancellation. Do not overwrite the document with invalid generated output. |
| No changes | Keep the original source exactly, including whitespace and fence style. |
| Document changes while the editor is open | Verify the target block still matches before applying. If it changed or disappeared, retain the draft and require conflict resolution rather than overwrite newer text. |
| Diagram inside a table cell or nested block | Preserve the enclosing Markdown structure and escaping. Until that context is supported safely, offer source editing with a clear explanation. |

Visual editing coverage must be explicit. A diagram being a flowchart is not enough to assume it can be safely rewritten. Subgraphs, advanced shapes, custom styling, directives and other constructs need preservation tests before enabling edits that touch them.

User labels require correct Mermaid quoting and escaping, including punctuation, quotes, Unicode and line breaks. User content must never become executable JavaScript through the WebView bridge. Editing and preview must retain the existing offline rendering and security restrictions.

## Proposed first-release boundary

| Include | Defer |
| --- | --- |
| Create and edit a documented subset of flowcharts | Visual editors for sequence, class, state, ER, Gantt and other diagram families |
| Step and decision nodes; labels; connections; direction | Arbitrary shape libraries, free positioning and manual edge routing |
| Existing diagrams that can be edited without losing source | Automatic conversion of every valid Mermaid diagram into an editable model |
| Draft preview, validation, Apply/Cancel and undo/redo | AI generation, collaboration and cloud services |
| Existing HTML/PDF export of the committed Mermaid | Separate diagram files or new export formats |

This first release closes the no-markup gap for basic flowcharts. It does not yet fulfill that promise for every Mermaid diagram type; the UI and documentation must state the supported coverage honestly.

## Technical questions to resolve before implementation

1. **Editable representation:** inspect the bundled Mermaid's parsing capabilities and establish how nodes and edges map back to source. Choose the smallest approach that supports safe edits; do not assume rendered SVG IDs are a stable editing API.
2. **Source preservation:** prove label changes, node insertion/deletion and connection changes can preserve untouched syntax. If a construct cannot be preserved, disable the affected visual edit rather than regenerate a simplified diagram.
3. **Interaction surface:** design the sheet, object selection, contextual controls and keyboard navigation. Decide whether the canvas is native or WebKit only after a small interaction prototype; reuse the bundled renderer either way.
4. **Coverage:** write the exact supported flowchart grammar and a capability check before advertising existing-diagram editing. Decide whether table-cell and nested-block editing belong in the first release.
5. **Draft lifecycle:** define how document closure, external reload and a changed target block retain or discard a draft through explicit user actions. Never apply to a stale source range.
6. **Preview scheduling:** keep rapid edits responsive and prevent an older render result from replacing a newer preview. Reuse the renderer's queue and cache where suitable without delaying document rendering or export unnecessarily.

## Implementation reach

- **Settings:** add the default-off toggle to `Settings/Views/SettingsView.swift` using existing preference storage; gate slash-menu behavior and visual editing actions on the same preference.
- **Document UI:** `ContentView.swift` slash insertion and presentation; diagram actions and focus handling in `NativeEditor.swift`; layout-fragment geometry for actions anchored to a diagram.
- **Editing model:** source-aware flowchart operations and capability detection, separate from UI. Keep Markdown block boundaries in the existing `MarkdownModel`; do not reparse the document with another Markdown scanner.
- **Rendering:** `Mermaid.swift` and bundled resources as needed for preview and interaction. Keep document rendering and export consistent with the committed source.
- **Document edits:** use the existing text-editing and undo path, validate the original block before replacement, and preserve its surrounding Markdown. No new document file format.
- **Accessibility and localization:** localizable app controls, errors and accessibility descriptions; never translate user labels, Mermaid keywords or identifiers.
- **Verification:** model operation tests, renderer tests, editor/undo integration tests, keyboard and VoiceOver review, and export regression checks. Extend existing fixtures only where behavior changes.
- **Documentation when shipped:** update `help/settings.md`, `help/formatting.md` and relevant lens/shortcut guidance, rebuild the Help Book, and record approved decisions in `DECISIONS.md`.

## Acceptance criteria

- On a fresh or upgraded installation, visual editing is off. Existing Mermaid insertion, rendering, source editing and export work as before.
- Enabling the toggle makes visual creation and editing available in all document windows and persists across launches. Disabling it hides those entry points without changing documents or losing an open draft.
- After enabling the Mermaid editor, a person unfamiliar with Mermaid can create a Start → decision → two outcomes flowchart, label the branches and apply it without seeing syntax.
- They can reopen it, rename a node, reconnect an edge and delete a step using visible controls or keyboard navigation.
- The saved file contains valid Mermaid that the bundled renderer can render after closing and reopening the document.
- Apply is one document undo step; undo/redo restores exact before/after source. Cancel and unchanged sessions preserve the original document exactly.
- Unicode, quotes, punctuation, duplicate labels and multiline labels survive editing and reopening.
- Unsupported and invalid diagrams remain intact, with an understandable path to source editing. Existing comments, styling and directives are never silently discarded.
- An external edit, block deletion or source shift cannot make Apply overwrite the wrong text.
- Preview errors and slow renders retain the draft and keep the editor usable. Editing works offline in light and dark appearances.
- HTML and PDF export render the applied diagram through the existing export pipeline.

## Next decisions

- Agree on the initial flowchart subset and the treatment of advanced constructs.
- Review a visual editor mockup against the creation and editing acceptance criteria.
- Prove source-preserving edits on representative existing diagrams before committing to the implementation approach.
