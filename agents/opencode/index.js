import { tool } from "@opencode-ai/plugin";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";

export const MarkifyPlugin = async () => ({
  tool: {
    markify_view: tool({
      description: "Open Markdown as an editable, unsaved report in Markify on this Mac. Use when the user asks to read a report in Markify; report missing-app errors and their download link to the user.",
      args: {
        text: tool.schema.string().describe("The complete Markdown report, preserved verbatim"),
        title: tool.schema.string().optional(),
        base: tool.schema.string().optional().describe("Existing absolute directory for relative links; defaults to the session directory"),
      },
      async execute({ text, title, base }, context) {
        await context.ask({ permission: "markify_view", patterns: ["open"], always: ["open"], metadata: { title: title ?? "Markify report" } });
        const args = [fileURLToPath(new URL("./scripts/view.sh", import.meta.url)), "-", "--base", base ?? context.directory];
        if (title !== undefined) args.push("--title", title);
        await new Promise((resolve, reject) => {
          const child = spawn("/bin/bash", args, { stdio: ["pipe", "ignore", "pipe"], signal: context.abort });
          let error = "";
          child.stderr.setEncoding("utf8").on("data", chunk => { error += chunk; });
          child.on("error", reject);
          child.on("close", code => code === 0 ? resolve() : reject(new Error(error.trim() || `Markify launch failed (${code})`)));
          // A missing/outdated CLI can exit before it reads stdin; preserve its useful stderr.
          child.stdin.on("error", failure => { if (failure.code !== "EPIPE") reject(failure); });
          child.stdin.end(text, "utf8");
        });
        return "macOS accepted the Markify report launch. The report opens unsaved; use Save to keep it.";
      },
    }),
  },
});
