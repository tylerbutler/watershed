import { parse } from "@astrojs/compiler";
import { extractJavaScript } from "./javascript.mjs";
import { rangeAt } from "./symbols.mjs";
import { core } from "./core.mjs";

export async function parseAstro({ path, source }) {
  const parsed = await parse(source, { position: true });
  const diagnostics = parsed.diagnostics.filter((d) => d.severity === 1).map((d) => ({
    path, message: d.text, range: null,
  }));
  const symbols = [];
  const skippedRegions = [];
  const regions = [];
  const bytes = Buffer.from(source);
  const offset = (byte) => bytes.subarray(0, byte).toString().length;
  let scriptCount = 0;
  function collect(node) {
    if (node.type === "frontmatter") {
      const start = offset(node.position.start.offset) + 3;
      regions.push({ start, end: start + node.value.length, scope: "frontmatter", kind: "ts" });
    } else if (node.type === "element" && node.name === "script") {
      const scope = `script:${++scriptCount}`;
      const attributes = new Map(node.attributes.map((a) => [a.name, a]));
      const type = attributes.get("type")?.value ?? "";
      const lang = attributes.get("lang")?.value ?? "";
      const external = attributes.has("src");
      const unsupported = [...attributes.values()].some((a) => ["type", "lang"].includes(a.name) && a.kind !== "quoted");
      const javascript = ["", "module", "text/javascript", "application/javascript"].includes(type);
      const kind = external || unsupported || !javascript || !["", "ts", "typescript", "js", "javascript"].includes(lang) ? null
        : ["ts", "typescript"].includes(lang) ? "ts"
        : ["js", "javascript"].includes(lang) || attributes.has("is:inline") || type ? "js" : "ts";
      for (const child of node.children) {
        if (child.type !== "text") continue;
        const start = offset(child.position.start.offset);
        regions.push({ start, end: start + child.value.length, scope, kind,
          reason: external ? "External script" : `Unsupported script type/lang: ${type || lang || "dynamic"}` });
      }
      return;
    }
    if (node.type !== "expression") for (const child of node.children ?? []) collect(child);
  }
  collect(parsed.ast);
  for (const region of regions) {
    if (region.start === region.end) continue;
    if (!region.kind) {
      skippedRegions.push({ reason: region.reason, range: rangeAt(source, region.start, region.end) });
      continue;
    }
    const fragment = source.slice(region.start, region.end);
    const result = extractJavaScript({ path, source: fragment, scriptKind: region.kind });
    const originalRange = (range) => {
      const start = region.start + Buffer.from(fragment).subarray(0, range.start.byte).toString().length;
      const end = region.start + Buffer.from(fragment).subarray(0, range.end.byte).toString().length;
      return rangeAt(source, start, end);
    };
    diagnostics.push(...result.diagnostics.map((d) => ({ ...d, range: d.range ? originalRange(d.range) : null })));
    for (const symbol of result.symbols) {
      const container = [region.scope, ...symbol.container];
      const range = originalRange(symbol.range);
      symbols.push({ ...symbol, container, range });
    }
  }
  return core().normalize_parse(path, { symbols, diagnostics, skippedRegions });
}
