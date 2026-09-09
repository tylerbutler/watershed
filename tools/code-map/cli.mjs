#!/usr/bin/env node
import { parseArgs } from "node:util";
import { realpath } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { resolve } from "node:path";
import { refreshIndex } from "./lib/index.mjs";
import { validateRequest, queryIndex, renderText } from "./lib/queries.mjs";

const help = `Usage: code-map [--root <directory>] <command> [options]
Commands:
  overview                          Repository summary (default)
  files [--path <directory>]         File inventory
  file <path>                       Declarations in an exact file
  find <query> [--path <directory>] [--kind <kind>]
  refresh [--rebuild]                Refresh the persistent index
Options:
  --json                            One JSON object on stdout
  --limit <n> --offset <n>           Pagination for files, file, find (50, 0)
  --help                            Show this help
Exit: 0 complete, 1 usage/operational error, 2 incomplete source coverage
`;

export async function main(argv, { cwd = process.cwd(), stdout = process.stdout, stderr = process.stderr } = {}) {
  // The CLI is the terminal error boundary; failures are surfaced, never converted to successful results.
  try {
    const { values, positionals } = parseArgs({
      args: argv, strict: true, allowPositionals: true,
      options: {
        root: { type: "string" }, json: { type: "boolean" }, rebuild: { type: "boolean" },
        path: { type: "string" }, kind: { type: "string" }, limit: { type: "string" },
        offset: { type: "string" }, help: { type: "boolean" },
      },
    });
    if (values.help) { stdout.write(help); return 0; }
    const [command = "overview", argument, ...extra] = positionals;
    const request = { command };
    if (extra.length || (argument !== undefined && !["file", "find"].includes(command))) throw new Error("Unexpected positional argument");
    if (command === "file") request.path = argument;
    if (command === "find") request.query = argument;
    for (const key of ["path", "kind", "limit", "offset"]) {
      if (values[key] === undefined) continue;
      if (key === "path" && command === "file") throw new Error("file takes its path as a positional argument");
      if (["limit", "offset"].includes(key) && !/^\d+$/.test(values[key])) throw new Error(`${key} must be an integer`);
      request[key] = ["limit", "offset"].includes(key) ? Number(values[key]) : values[key];
    }
    if (values.rebuild && command !== "refresh") throw new Error("--rebuild is only valid for refresh");
    validateRequest(request);
    const root = values.root === undefined ? cwd : resolve(cwd, values.root);
    const index = await refreshIndex(root, { rebuild: values.rebuild ?? false });
    const view = queryIndex(index, request);
    stdout.write(values.json ? `${JSON.stringify(view)}\n` : renderText(view));
    return index.complete ? 0 : 2;
  } catch (error) {
    stderr.write(`error: ${JSON.stringify(error instanceof Error ? error.message : String(error))}\n`);
    return 1;
  }
}

if (process.argv[1] && await realpath(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = await main(process.argv.slice(2));
}
