import test from "node:test";
import assert from "node:assert/strict";
import { parseGleam } from "../lib/gleam.mjs";
import { parseJavaScript } from "../lib/javascript.mjs";
import { parseAstro } from "../lib/astro.mjs";
import { positionAtByte, positionAtUtf16 } from "../lib/symbols.mjs";

test("positions preserve Unicode scalar columns, UTF-8 bytes, and CRLF lines", () => {
  const source = "é😀x\r\nnext";
  assert.deepEqual(positionAtUtf16(source, 3), { line: 1, column: 3, byte: 6 });
  assert.deepEqual(positionAtByte(source, 9), { line: 2, column: 1, byte: 9 });
  assert.throws(() => positionAtByte(source, 2 + 1), /boundary/);
});

test("Gleam declarations preserve private functions, targets, and named bindings", async () => {
  const source = '// 😀 fn fake() {}\r\npub opaque type Box { Box(Int) }\r\n'
    + 'const label = "é😀"\r\n@target(javascript)\r\n'
    + '@external(javascript, "node:process", "exit")\r\npub fn halt(code: Int) -> Nil\r\n'
    + "fn outer() { let inner = fn(x) { x } let captured = inner(_) captured(1) }\r\n";
  const result = await parseGleam({ path: "a.gleam", source });
  assert.deepEqual(result.diagnostics, []);
  assert.deepEqual(result.symbols.map((s) => s.name), ["Box", "label", "halt", "outer", "inner", "captured"]);
  const halt = result.symbols[2];
  assert.equal(halt.target, "javascript");
  assert.equal(halt.exported, true);
  assert.equal(halt.range.start.line, 6);
  assert.equal(halt.range.start.byte, Buffer.byteLength(source.slice(0, source.indexOf("pub fn"))));
  assert.equal(halt.signature, "pub fn halt(code: Int) -> Nil");
  assert.equal(result.symbols[1].signature, "const label");
  assert.equal(slice(source, result.symbols[1]), 'const label = "é😀"');
  assert.deepEqual(result.symbols[4].container, ["outer"]);
  assert.equal(result.symbols[5].signature, "let captured");
});

test("Gleam rejects malformed source without a partial successful outline", async () => {
  const result = await parseGleam({ path: "a.gleam", source: "fn good() { Nil }\nfn bad(" });
  assert.equal(result.symbols.length, 0);
  assert.equal(result.diagnostics.length, 1);
});

test("JS/TS captures nested bindings without copying function bodies", () => {
  const source = "export function open() {\n  const close = () => 1;\n  return close;\n}\n";
  const result = parseJavaScript({ path: "a.ts", source });
  assert.deepEqual(result.diagnostics, []);
  assert.deepEqual(result.symbols.map((s) => [s.name, s.container]), [
    ["open", []], ["close", ["open"]],
  ]);
  assert.equal(result.symbols[1].signature, "const close = () =>");
  assert.equal(result.symbols[0].signature, "export function open()");
});

test("JS/TS declarations include static methods, expressions, types, exports and overloads", () => {
  const source = `
const text = "function fake() {}";
interface Options { value: number }
type Choice = "a" | "b";
enum Mode { One, Two }
function choose(value: string): string;
function choose(value: number): number;
function choose(value: unknown) { return value; }
export { choose };
export default class Client {
  constructor() {}
  private stop() {}
  get value() { return 1; }
  set value(v: number) {}
  action = async (v: number) => v;
}
const obj = { go() {}, end: function named() {}, [text]() {} };
const fn = function inner() {};
[1].map(() => { function nested() {} return nested(); });
`;
  const result = parseJavaScript({ path: "a.ts", source });
  assert.deepEqual(result.diagnostics, []);
  const names = result.symbols.map((s) => s.name);
  for (const name of ["text", "Options", "Choice", "Mode", "Client", "constructor", "stop", "value", "action", "go", "end", "fn", "nested"]) {
    assert.ok(names.includes(name), name);
  }
  assert.equal(names.includes("fake"), false);
  assert.equal(names.includes("named"), false);
  assert.equal(names.includes("inner"), false);
  assert.equal(names.filter((name) => name === "choose").length, 3);
  assert.equal(new Set(result.symbols.map((s) => s.id)).size, result.symbols.length);
  assert.ok(result.symbols.filter((s) => s.name === "choose").every((s) => s.exported));
  assert.equal(result.symbols.find((s) => s.name === "stop").visibility, "private");
  assert.deepEqual(result.symbols.find((s) => s.name === "go").container, ["obj"]);
  assert.equal(result.symbols.find((s) => s.name === "text").signature, "const text");
});

test("JS/TS signatures keep structural types, defaults and multiline parameters", () => {
  const source = "export function shape(\n  arg = { nested: 1 },\n): { value: number } { return { value: 2 }; }";
  const result = parseJavaScript({ path: "a.ts", source });
  assert.deepEqual(result.diagnostics, []);
  assert.equal(result.symbols[0].signature, "export function shape(\n  arg = { nested: 1 },\n): { value: number }");
  assert.equal(slice(source, result.symbols[0]), source);
});

test("wrapped callable bindings and object-bound classes retain their binding names", () => {
  const source = "const run = (() => 1) satisfies Function;\n"
    + "const types = { Client: class Internal { open() {} } };\n"
    + "const factory = (class Named {});";
  const result = parseJavaScript({ path: "a.ts", source });
  assert.deepEqual(result.diagnostics, []);
  assert.deepEqual(result.symbols.map((s) => [s.name, s.kind, s.container]), [
    ["run", "function", []], ["types", "constant", []],
    ["Client", "class", ["types"]], ["open", "method", ["types", "Client"]],
    ["factory", "class", []],
  ]);
});

test("Gleam target variants keep distinct identity and byte ranges", async () => {
  const source = '@target(erlang)\npub fn name() { Nil }\n@target(javascript)\npub fn name() { Nil }';
  const result = await parseGleam({ path: "a.gleam", source });
  assert.deepEqual(result.symbols.map((s) => s.target), ["erlang", "javascript"]);
  assert.notEqual(result.symbols[0].id, result.symbols[1].id);
});

for (const [path, source] of [
  ["a.js", "export async function* values() { yield 1; }"],
  ["a.cjs", "function main() {} module.exports = main;"],
  ["a.jsx", "const App = () => <div />;"],
  ["a.tsx", "const App = (): JSX.Element => <div />;"],
]) {
  test(`selects the correct syntax for ${path}`, () => {
    const result = parseJavaScript({ path, source });
    assert.deepEqual(result.diagnostics, []);
    assert.equal(result.symbols.length, 1);
  });
}

test("JS syntax errors return diagnostics, not salvaged declarations", () => {
  const result = parseJavaScript({ path: "a.ts", source: "function good() {}\nfunction bad(" });
  assert.equal(result.symbols.length, 0);
  assert.ok(result.diagnostics.length > 0);
});

test("Astro indexes original frontmatter and executable scripts, not generated wrappers", async () => {
  const source = "---\n// 😀\nfunction wave(seed: number) { return seed; }\n---\n"
    + '<p>é</p>\n<script>function boot() {}</script>\n'
    + '<script type="application/ld+json">{"fn":"ignored"}</script>\n'
    + '<script is:inline>function raw() {}</script>\n'
    + '<script src="./external.js"></script>\n'
    + '{(() => { function templateOnly() {} return ""; })()}';
  const result = await parseAstro({ path: "example.astro", source });
  assert.deepEqual(result.diagnostics, []);
  assert.deepEqual(result.symbols.map((s) => [s.name, s.range.start.line]), [
    ["wave", 3], ["boot", 6], ["raw", 8],
  ]);
  assert.equal(slice(source, result.symbols[0]), "function wave(seed: number) { return seed; }");
  assert.equal(slice(source, result.symbols[1]), "function boot() {}");
  assert.ok(result.skippedRegions.some((s) => /json/i.test(s.reason)));
  assert.deepEqual(result.symbols[0].container, ["frontmatter"]);
});

test("Astro syntax errors in an executable region invalidate the file", async () => {
  const result = await parseAstro({ path: "a.astro", source: "---\nfunction okay() {}\n---\n<script>function bad(</script>" });
  assert.equal(result.symbols.length, 0);
  assert.ok(result.diagnostics.length > 0);
});

function slice(source, symbol) {
  return Buffer.from(source).subarray(symbol.range.start.byte, symbol.range.end.byte).toString();
}
