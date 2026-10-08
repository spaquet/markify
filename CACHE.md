# Mermaid render cache

How Markify keeps rendered Mermaid diagrams in memory and on disk, and the steps to get there from the current cache in `Markify/Mermaid.swift`.

## Problem

With several documents open, diagrams in a newly opened window show "Diagram cache exceeds its memory limit." even though the same document opened alone renders every diagram (e.g. the Mermaid project's README).

Causes in the current `MermaidRenderer`:

1. **One budget, first come first served.** Every window's rendered bitmaps count against a single 64 MB budget (`finish`, `Mermaid.swift:239`). A window holds its share for as long as its document contains the diagram, whether the window is in the background or the diagram is scrolled away. `release(owner:)` runs only when a block leaves the document or the view closes.
2. **Admission instead of eviction.** When the budget is full, the new diagram is refused rather than evicting one nobody is looking at.
3. **The refusal is sticky.** The limit failure is stored in `states[key]` and returned by `state(of:)` from then on. Closing the other windows does not bring the diagram back; only reopening the document does.
4. **Bitmaps are large.** A snapshot covers up to 524,288 points (`snapshotArea`), about 8.4 MB of pixels at 2x, and large diagrams are downscaled to 2048 pt, which also blurs them.

Sharing one store between windows is right (a diagram open twice renders once); the budget has to follow what is visible, not which window rendered first.

## Design

### Tiers

| Tier | Holds | Where | Size | Eviction |
|---|---|---|---|---|
| **T0 metadata** | key → intrinsic size, or Mermaid's parse error | RAM (`State.evicted`, `.failed`); on disk, the PDF's page size and `<sha256>.error` files | ~100 B per entry | with its diagram |
| **T1 disk** | one PDF per key | `~/Library/Caches/<bundle id>/Mermaid/<sha256>.pdf` | 20–200 KB each, 50 MB cap | least recently used (file modification date), pruned at launch and when idle |
| **T2 memory** | PDF data / `NSPDFImageRep` | `MermaidRenderer.shared` | 32 MB budget | least recently drawn, leased entries pinned |
| **T3 raster** (only if profiling asks for it) | bitmap at column width × backing scale | per `MarkdownTextView`, visible diagrams only | small | dropped when scrolled off screen |

The web view renders only on a T1 miss: a new diagram, an edited one, a theme the diagram has not been shown in, or a new Mermaid version.

### Rendering to PDF

- Replace `takeSnapshot` with `WKWebView.createPDF(configuration:)` over the diagram's bounds.
- The result is vector: sharp at any zoom and column width, typically tens of KB instead of megabytes. `snapshotArea` and the 2048 pt downscale go away.
- Draw with `NSPDFImageRep` (or `NSImage(data:)`), so Core Graphics rasterizes only the fragment being drawn, at the screen's scale.
- Do not use `NSImage`'s SVG loading: Mermaid draws labels in `<foreignObject>`, which the native SVG renderer drops. WebKit's PDF keeps them.
- Keep the sanity limits: 64 KB of source, 4096 pt bounds, 32 pending renders.
- Export is unchanged: `svg(for:)` still renders SVG on demand.

### Keys

- **In memory (T0, T2):** the current string key, `"\(dark):\(source)"`. `state(of:)` runs on every style pass for every diagram, and a dictionary hashes the string anyway, so no digest is computed there.
- **On disk (T1, persisted T0):** SHA-256 (CryptoKit) of
  `source + "\0" + theme + "\0" + mermaidVersion + "\0" + renderVersion`, as lowercase hex.
  - Swift's `Hasher` is seeded per launch, so it cannot name files.
  - `mermaidVersion` is read from the bundled script, so a Mermaid update invalidates the cache by itself.
  - `renderVersion` is a constant bumped when the render code or page changes output.
  - The digest is computed only on a T2 miss and stored on the entry, once per source.
- CryptoKit SHA-256 with the hex idiom already appears in `LinksPanel.swift`, `LibrarySearch.swift` and `MarkifyApp.swift`; factor it into one helper and use it in all four places.

### Failures

- **Stored** (T0, persisted): Mermaid's parse errors only. They are deterministic, so a reopened document shows the error without rendering.
- **Never stored**: memory limits, timeouts, snapshot or PDF errors. They are shown for that request and retried on the next one.
- "Diagram cache exceeds its memory limit." is removed: a full budget evicts, it never refuses.

### Sharing and priority

- One store shared by every window.
- Each text view **leases** the diagram keys near its viewport: the visible range plus about one screen above and below. The existing `waiting` owners become leases; diagrams in a document but far from its viewport hold none.
- When T2 is over budget, unleased entries go first, least recently drawn first. A newly requested diagram is never refused; if only leased entries remain, the budget is exceeded rather than failing a visible diagram.
- When a window becomes key (`didBecomeKey`), it renews its leases; anything evicted reloads from T1, decoded off the main thread.
- On memory pressure (`DispatchSource.makeMemoryPressureSource`), T2 keeps only leased entries and T3 is cleared.

### Layout stability

Block heights come from T0's intrinsic size, never from the loaded image. Eviction, a reload from disk or a re-render does not change a paragraph's height, so background windows do not jump when they come back.

### Why files and not a database

The disk tier stores immutable blobs looked up by content hash, with no queries, relations or updates. The file system does that directly; SQLite or SwiftData would add a schema, a write-ahead log and blob overhead for nothing. `~/Library/Caches` is the right place: the system may purge it, and every entry can be rebuilt.

## Implementation steps

Each step ships on its own and keeps the tests green.

### 1. Stop refusing (fix for the multi-window bug) — done, build 324

- In `finish`, never turn a render into `.failed` for the budget. Instead evict unleased settled entries, least recently drawn first, until the new one fits; if none can go, keep it over budget.
- Track a last-drawn time per key (set in `state(of:)` and `cached(_:dark:)`).
- Remove the `states.count >= 64` sweep in `state(of:)` in favor of the same eviction.
- Tests: a full budget evicts an unleased entry; a leased entry survives; no `.failed` state is ever stored for the budget; after another owner releases, a previously over-budget diagram renders.

### 2. PDF payload and the T0 split — done, build 325

Results: a 360 × 3340 pt flowchart is 18 KB of PDF in the light theme and 62 KB in the dark one (the bitmap was capped at ~8 MB); it draws into a 1216 px square in 10–16 ms. Flowchart labels from `<foreignObject>` are in the PDF as text, and the background stays transparent in both themes, so `mermaid.html` is unchanged. In memory, T0 is `State.evicted(size)`: an evicted entry keeps only its size, and step 3 persists it. The memory budget is now 32 MB.

- Render with `createPDF`; `State.rendered` carries the PDF image and its intrinsic size.
- Keep T0 (size or parse error) apart from T2 (the PDF), so dropping T2 keeps heights.
- `diagramHeight` reads the size from T0; `drawDiagrams` draws from T2 and, on a miss, requests a reload and draws the placeholder at the T0 size.
- Cost per entry becomes the PDF's byte count.
- Verify first, against the README diagrams and the editor fixture:
  - `<foreignObject>` labels appear in the PDF.
  - The PDF background is transparent in the dark theme (clear the page background in `mermaid.html` if not).
  - PDF size with embedded fonts.
  - Scrolling performance on a large flowchart (decides step 5).
- Remove `snapshotArea` and the downscale.
- Tests: pixel test that a rendered diagram draws (dark and light), height unchanged after T2 eviction.

### 3. T1 disk tier — done, build 326

As built (`Markify/DiagramCache.swift`, `DiagramDiskCache`): no JSON sidecar. A cached PDF's page size is the diagram's size, and a parse error is a `<sha256>.error` file holding Mermaid's message, so T0 needs nothing beside T1. The renderer version is the SHA-256 of the bundled `mermaid.min.js` and `mermaid.html`, hashed once on the cache's queue, rather than a version string. Pruning runs when the cache is first used and whenever a write takes it over 50 MB, and stops at three quarters of the limit. Under tests the cache is a throwaway folder. The Quick Look extension compiles the same file and keeps its own cache in its container.

The plan as written:


- Add the shared SHA-256 hex helper; switch the three existing call sites to it.
- Read `mermaidVersion` from the bundled script once; add `renderVersion`.
- On a T2 miss: compute the digest, look in T1, decode off the main thread; render only when T1 misses, then write the PDF atomically.
- Persist T0 (sizes and parse errors) in a JSON sidecar keyed by digest; load it lazily.
- Touch the file's modification date on read; prune to 50 MB at launch and when idle.
- Tests: a T1 hit does not use the web view (render-count probe); the key changes with source, theme, Mermaid version and render version; pruning keeps the cap; a corrupt file is deleted and re-rendered.

### 4. Viewport leases — done, build 327

As built: leases sit beside ownership instead of replacing the `keeping:` set. A document still owns all its diagrams, so a style pass never re-requests one scrolled out of view, and only the lease decides what eviction may drop. `MarkdownTextView.leaseDiagrams()` leases the Mermaid blocks within the TextKit viewport's character range, widened on each side by the viewport's own length (at least 2,000 characters) to stand in for a screen above and below, so no text outside the viewport is laid out. It runs after each style pass, scroll and resize, and when the window becomes key; leasing an evicted diagram loads it again at once. Leased diagrams of every window are equal: none is evicted for another diagram, and the cache goes over its budget before refusing one. On memory pressure, `relieveMemoryPressure()` evicts every unleased image.

The plan as written:


- `MarkdownTextView` reports the diagram keys in its visible range plus one screen on scroll, resize and restyle; this replaces the document-wide `keeping:` set passed to `release(owner:keeping:)`.
- Renew leases on `didBecomeKey`.
- Install the memory-pressure source.
- Tests: two owners, the one that scrolled away loses its pin and is evicted first; the key window's diagrams stay.

### 5. T3 raster (only if step 2's profiling shows slow scrolling)

- Per text view, rasterize visible diagrams at column width × backing scale; drop them when they leave the viewport or the width changes.

## Open choices

- Budgets: 32 MB memory, 50 MB disk.
- Settings › Clear diagram cache: if added, update `help/settings.md` and rebuild the Help Book (`scripts/build-help.sh`).
- Record the decision in `DECISIONS.md` once agreed.
