import { relativePath } from "./config.mjs";
import { beneath } from "./inventory.mjs";
import { compare, extensions, kinds, limits, statuses } from "./symbols.mjs";

export function validateRequest(request) {
  if (!request || typeof request !== "object" || Array.isArray(request)) throw new Error("Invalid query request");
  const command = request.command ?? "overview";
  const allowed = {
    overview: [], refresh: [], files: ["path", "limit", "offset"],
    file: ["path", "limit", "offset"], find: ["query", "path", "kind", "limit", "offset"],
  };
  if (!Object.hasOwn(allowed, command)) throw new Error(`Unknown command: ${command}`);
  for (const key of Object.keys(request)) {
    if (key !== "command" && !allowed[command].includes(key)) throw new Error(`Option ${key} is not valid for ${command}`);
  }
  const result = { ...request, command };
  if (["find", "file", "files"].includes(command)) {
    result.limit ??= 50;
    result.offset ??= 0;
    if (!Number.isSafeInteger(result.limit) || result.limit <= 0) throw new Error("limit must be a positive integer");
    if (!Number.isSafeInteger(result.offset) || result.offset < 0) throw new Error("offset must be a nonnegative integer");
  }
  if ((command === "file" || result.path !== undefined) && !relativePath(result.path)) {
    throw new Error("path must be a normalized repository-relative path without traversal");
  }
  if (command === "find" && (typeof result.query !== "string" || !result.query.length)) throw new Error("find requires a nonempty query");
  if (result.kind !== undefined && !kinds.includes(result.kind)) throw new Error(`Unknown symbol kind: ${result.kind}`);
  return result;
}

function metadata(file) {
  return { path: file.path, language: file.language, status: file.status, reason: file.reason,
    symbolCount: file.symbols.length, diagnosticCount: file.diagnostics.length,
    skippedRegionCount: file.skippedRegions.length };
}

export function queryIndex(index, request) {
  const query = validateRequest(request);
  const counts = Object.fromEntries(statuses.map((status) => [status, 0]));
  const diagnostics = [];
  let skippedRegionCount = 0;
  for (const file of index.files) {
    counts[file.status]++;
    diagnostics.push(...file.diagnostics);
    skippedRegionCount += file.skippedRegions.length;
  }
  const result = {
    version: 1, command: query.command, complete: index.complete,
    coverage: { statuses: counts, extensions, limits, intrinsicExclusions: [".code-map"],
      diagnosticCount: diagnostics.length, skippedRegionCount },
    diagnostics: diagnostics.slice(0, 50),
    diagnosticsHasMore: diagnostics.length > 50,
  };
  if (["overview", "refresh"].includes(query.command)) {
    const groups = new Map();
    for (const file of index.files) {
      const directory = file.path.includes("/") ? file.path.split("/")[0] : ".";
      const group = groups.get(directory) ?? { path: directory, files: 0, symbols: 0 };
      group.files++;
      group.symbols += file.symbols.length;
      groups.set(directory, group);
    }
    const entries = [...groups.values()].sort((a, b) => compare(a.path, b.path));
    return { ...result, totals: { files: index.files.length, symbols: index.files.reduce((n, f) => n + f.symbols.length, 0) },
      groups: entries.slice(0, 50), groupsTotal: entries.length, groupsHasMore: entries.length > 50 };
  }
  let items;
  if (query.command === "file") {
    const file = index.files.find((f) => f.path === query.path);
    if (!file) throw new Error(`File not in current inventory: ${query.path}`);
    result.file = { ...metadata(file), diagnostics: file.diagnostics, skippedRegions: file.skippedRegions };
    items = file.symbols.map((s) => ({ path: file.path, ...s }));
  } else {
    const files = index.files.filter((f) => query.path === undefined || beneath(f.path, query.path));
    if (query.command === "files") items = files.map(metadata);
    else {
      const needle = query.query.toLowerCase();
      const rank = (symbol) => symbol.name.toLowerCase() === needle ? 0 : symbol.name.toLowerCase().startsWith(needle) ? 1 : 2;
      items = files.flatMap((f) => f.symbols.map((s) => ({ path: f.path, ...s })))
        .filter((s) => (!query.kind || s.kind === query.kind) && s.qualifiedName.toLowerCase().includes(needle))
        .sort((a, b) => rank(a) - rank(b) || compare(a.path, b.path) || a.range.start.byte - b.range.start.byte || compare(a.id, b.id));
    }
  }
  return { ...result, items: items.slice(query.offset, query.offset + query.limit),
    total: items.length, limit: query.limit, offset: query.offset, hasMore: query.offset + query.limit < items.length };
}

const escaped = (text) => JSON.stringify(text);
export function renderText(view) {
  const lines = [];
  if (view.totals) {
    lines.push(`${view.totals.files} files, ${view.totals.symbols} symbols`);
    for (const group of view.groups) lines.push(`${escaped(group.path)}: ${group.files} files, ${group.symbols} symbols`);
    if (view.groupsHasMore) lines.push(`${view.groupsTotal} groups; use files --path <directory> to browse.`);
  } else {
    if (view.file) lines.push(`${escaped(view.file.path)}: ${view.file.status}${view.file.reason ? ` (${escaped(view.file.reason)})` : ""}`);
    lines.push(`${view.items.length} of ${view.total} results (offset ${view.offset})`);
    for (const item of view.items) {
      lines.push(item.range
        ? `${escaped(item.path)}:${item.range.start.line}:${item.range.start.column} ${item.kind} ${item.visibility} ${escaped(item.signature)}`
        : `${escaped(item.path)}: ${item.status}, ${item.symbolCount} symbols${item.reason ? ` (${escaped(item.reason)})` : ""}`);
    }
    if (view.hasMore) lines.push(`More results: repeat with --offset ${view.offset + view.limit}`);
  }
  lines.push(`Coverage: ${Object.entries(view.coverage.statuses).map(([key, count]) => `${key}=${count}`).join(", ")}`);
  if (view.coverage.skippedRegionCount) lines.push(`${view.coverage.skippedRegionCount} script regions excluded; see file --json for details.`);
  if (!view.complete) lines.push("INCOMPLETE: source errors; failed files have no current declarations.");
  for (const d of view.diagnostics) lines.push(`${escaped(d.path)}: ${escaped(d.message)}`);
  if (view.diagnosticsHasMore) lines.push(`${view.coverage.diagnosticCount} diagnostics; use files and file to inspect affected paths.`);
  return `${lines.join("\n")}\n`;
}
