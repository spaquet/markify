// Run against an installed package: node scripts/test-opencode.mjs /path/to/markify-opencode/index.js
import assert from "node:assert/strict";
import { mkdtemp, writeFile, readFile, access, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const { MarkifyPlugin } = await import(pathToFileURL(process.argv[2]));
const { tool: { markify_view: view } } = await MarkifyPlugin();
const folder = await mkdtemp(join(tmpdir(), "markify opencode "));
const previous = process.env.MARKIFY_CLI;
try {
  const cli = join(folder, "fake markify");
  const capture = join(folder, "capture.json");
  await writeFile(cli, `#!/usr/bin/env node
if (process.argv[2] === '--help') { console.log('markify view'); process.exit(0); }
(async () => {
let text = ''; for await (const chunk of process.stdin) text += chunk;
require('node:fs').writeFileSync(${JSON.stringify(capture)}, JSON.stringify({args: process.argv.slice(2), text}));
})();
`, { mode: 0o700 });
  process.env.MARKIFY_CLI = cli;
  let permissions = 0;
  const context = { directory: folder, abort: new AbortController().signal, ask: async request => { assert.equal(request.permission, "markify_view"); permissions++; } };
  const text = "# café 🌻\r\n\r\n$(touch never) `literal`\nNo final newline";
  await view.execute({ text, title: "A & B" }, context);
  assert.equal(permissions, 1);
  assert.deepEqual(JSON.parse(await readFile(capture, "utf8")), { args: ["view", "-", "--base", folder, "--title", "A & B"], text });
  await rm(capture);
  await assert.rejects(view.execute({ text }, { ...context, ask: async () => { throw new Error("Permission denied"); } }), /Permission denied/);
  await assert.rejects(access(capture));
  process.env.MARKIFY_CLI = join(folder, "missing");
  await assert.rejects(view.execute({ text: text.repeat(10000) }, context), /https:\/\/github.com\/spaquet\/markify\/releases\/latest/);
  process.env.MARKIFY_CLI = cli;
  await writeFile(cli, "#!/bin/bash\necho 'old CLI'\n", { mode: 0o700 });
  await assert.rejects(view.execute({ text: text.repeat(10000) }, context), /This Markify CLI does not support view.*https:\/\/github.com\/spaquet\/markify\/releases\/latest/);
  await writeFile(cli, "#!/bin/bash\nif [ \"$1\" = '--help' ]; then echo 'markify view'; exit 0; fi\necho 'Could not open report' >&2\nexit 1\n", { mode: 0o700 });
  await assert.rejects(view.execute({ text: text.repeat(10000) }, context), /Could not open report/);
  await writeFile(cli, "#!/bin/bash\nif [ \"$1\" = '--help' ]; then echo 'markify view'; fi\nexit 0\n", { mode: 0o700 });
  await assert.rejects(view.execute({ text: text.repeat(10000) }, context));
  console.log("OpenCode tool checks passed.");
} finally {
  if (previous === undefined) delete process.env.MARKIFY_CLI; else process.env.MARKIFY_CLI = previous;
  await rm(folder, { recursive: true });
}
