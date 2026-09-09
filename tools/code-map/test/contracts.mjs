import { refreshIndex, queryIndex } from "../lib/index.mjs";
import { renderText } from "../lib/queries.mjs";
import { makeRepo, write } from "./helpers.mjs";

export async function captureContracts(t) {
  const root = await makeRepo(t, {
    "src/a.ts": "export function connect(x: number = 1) { return x; }\nfunction connector() {}\nfunction disconnect() {}",
    "src/b.gleam": "@target(javascript)\npub fn connect() { Nil }\nfn private() { Nil }",
    "src/c.astro": "---\nfunction wave(n: number) { return n; }\n---\n<script>function boot() {}</script>",
    "src/\u00e9.ts": '// \u{1f600}\r\nfunction unicode() {}\r\n',
    "readme.md": "# Notes",
    "vendor/a.ts": "function hidden() {}",
    "code-map.json": '{"version":1,"excludePaths":["vendor"]}',
  });
  const index = await refreshIndex(root);
  const requests = [
    {}, { command: "refresh" }, { command: "files" },
    { command: "files", path: "src", limit: 2, offset: 1 },
    { command: "file", path: "src/a.ts" }, { command: "file", path: "readme.md" },
    { command: "find", query: "CONNECT", path: "src", limit: 2 },
    { command: "find", query: "connect", offset: 2 },
    { command: "find", query: "missing" },
  ];
  const views = requests.map((request) => {
    const view = queryIndex(index, request);
    return { request, view, text: renderText(view) };
  });
  await write(root, "src/a.ts", "function bad(");
  const incomplete = queryIndex(await refreshIndex(root), { command: "find", query: "connect" });
  return { index: { ...index, toolHash: "0".repeat(64) }, views,
    incomplete, incompleteText: renderText(incomplete) };
}
