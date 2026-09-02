// ──────────────────────────────────────────────────────────────────────────
// Tests for the practice snippet registry.
//
// The registry names one generated id per practice. Node can import it
// directly now that no module reads source with Vite's `?raw`, so these
// tests check the snippets the site actually renders rather than a
// replication of them.
//
// Generate the manifest first: `just website-snippets`.
// Run: node --strip-types --test src/data/practice-snippets.test.ts
// ──────────────────────────────────────────────────────────────────────────
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { isSourceBacked } from "../lib/snippet.ts";
import { practiceSnippets } from "./practice-snippets.ts";

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(__dirname, "../../..");

// ── Inventory: all 17 practice ids ─────────────────────────────────────────

const PRACTICE_IDS = [
  "relay-decorator",
  "shared-core-two-runtimes",
  "diagnostics-first",
  "quorum-pending-roster",
  "realtime-out-of-band",
  "presence-idiom",
  "protocol-on-ripples",
  "pure-modules",
  "ffi-surface",
  "fallible-edits",
  "authoritative-channel",
  "stamp-schema",
  "typedmap-panels",
  "claims-seeding",
  "anchors-not-offsets",
  "unsettled-writes",
  "deterministic-death",
] as const;

const snippets = practiceSnippets;

test("registry produces exactly 17 practice snippets", () => {
  assert.equal(
    Object.keys(snippets).length,
    17,
    `Expected 17 entries, got ${Object.keys(snippets).length}`,
  );
});

test("every known practice id has a snippet", () => {
  for (const id of PRACTICE_IDS) {
    assert.ok(snippets[id], `Missing snippet for practice "${id}"`);
  }
});

// ── Descriptor shape ───────────────────────────────────────────────────────

test("every descriptor has non-empty code", () => {
  for (const [id, snippet] of Object.entries(snippets)) {
    assert.ok(
      snippet.code.length > 10,
      `Practice "${id}" has too-short code (${snippet.code.length} chars)`,
    );
  }
});

test("every descriptor has a language", () => {
  for (const [id, snippet] of Object.entries(snippets)) {
    assert.ok(
      snippet.language === "gleam" || snippet.language === "js",
      `Practice "${id}" has unexpected language "${snippet.language}"`,
    );
  }
});

test("every descriptor has a sourcePath starting with examples/", () => {
  for (const [id, snippet] of Object.entries(snippets)) {
    assert.ok(
      snippet.sourcePath.startsWith("examples/"),
      `Practice "${id}" sourcePath "${snippet.sourcePath}" does not start with examples/`,
    );
  }
});

test("every descriptor cites a source file that exists", () => {
  for (const [id, snippet] of Object.entries(snippets)) {
    assert.ok(
      readFileSync(resolve(repoRoot, snippet.sourcePath), "utf-8").length > 0,
      `Practice "${id}" cites an empty file`,
    );
  }
});

test("no descriptor uses literal origin (all must be source-backed)", () => {
  for (const [id, snippet] of Object.entries(snippets)) {
    assert.ok(
      isSourceBacked(snippet),
      `Practice "${id}" is a hand-written literal — every practice quotes real source`,
    );
  }
});

test("every descriptor names the marker ranges it was composed from", () => {
  for (const [id, snippet] of Object.entries(snippets)) {
    assert.equal(
      snippet.origin.kind,
      "source",
      `Practice "${id}" must come from marker ranges, not a whole-file listing`,
    );
    if (snippet.origin.kind === "source") {
      assert.ok(
        snippet.origin.markers.length > 0,
        `Practice "${id}" reports no marker range`,
      );
    }
  }
});

test("a joined descriptor reports every part it was built from", () => {
  const parts: Record<string, number> = {
    "relay-decorator": 2,
    "fallible-edits": 3,
    "unsettled-writes": 2,
    "pure-modules": 4,
  };
  for (const [id, count] of Object.entries(parts)) {
    const origin = snippets[id].origin;
    assert.equal(origin.kind, "source");
    if (origin.kind === "source") {
      assert.equal(
        origin.markers.length,
        count,
        `Practice "${id}" joins ${count} ranges, so its origin must name ${count}`,
      );
    }
  }
});

// ── Language matches the source file extension ─────────────────────────────

test("JS snippets have .mjs or .js source path", () => {
  for (const [id, snippet] of Object.entries(snippets)) {
    if (snippet.language === "js") {
      assert.ok(
        snippet.sourcePath.endsWith(".mjs") || snippet.sourcePath.endsWith(".js"),
        `Practice "${id}" is JS but sourcePath is "${snippet.sourcePath}"`,
      );
    }
  }
});

test("Gleam snippets have .gleam source path", () => {
  for (const [id, snippet] of Object.entries(snippets)) {
    if (snippet.language === "gleam") {
      assert.ok(
        snippet.sourcePath.endsWith(".gleam"),
        `Practice "${id}" is Gleam but sourcePath is "${snippet.sourcePath}"`,
      );
    }
  }
});

// ── No marker lines leak into rendered code ────────────────────────────────

test("no snippet code contains marker directives", () => {
  for (const [id, snippet] of Object.entries(snippets)) {
    assert.ok(
      !snippet.code.includes("docs:snippet-start"),
      `Practice "${id}" code leaks a start marker`,
    );
    assert.ok(
      !snippet.code.includes("docs:snippet-end"),
      `Practice "${id}" code leaks an end marker`,
    );
  }
});

// ── Content spot-checks ────────────────────────────────────────────────────

test("shared-core-two-runtimes contains fn event_loop", () => {
  assert.ok(snippets["shared-core-two-runtimes"].code.includes("fn event_loop("));
});

test("diagnostics-first contains fn diagnostic_line", () => {
  assert.ok(snippets["diagnostics-first"].code.includes("fn diagnostic_line("));
});

test("realtime-out-of-band contains function tick and is JS", () => {
  const s = snippets["realtime-out-of-band"];
  assert.ok(s.code.includes("function tick(engine)"));
  assert.equal(s.language, "js");
});

test("quorum-pending-roster contains BpmCommitted arm", () => {
  assert.ok(snippets["quorum-pending-roster"].code.includes("BpmCommitted ->"));
});

test("ffi-surface contains Connected arms", () => {
  const s = snippets["ffi-surface"];
  assert.ok(s.code.includes("Connected(Ok(_))"));
  assert.ok(s.code.includes("Connected(Error(reason))"));
});

test("presence-idiom extracts two definitions", () => {
  const s = snippets["presence-idiom"];
  assert.ok(s.code.includes("fn presence_effect("));
  assert.ok(s.code.includes("fn remote_peers("));
});

test("protocol-on-ripples extracts three definitions", () => {
  const s = snippets["protocol-on-ripples"];
  assert.ok(s.code.includes("pub fn matches_run("));
  assert.ok(s.code.includes("pub fn from_self("));
  assert.ok(s.code.includes("pub fn should_acknowledge("));
});

test("pure-modules extracts type and three functions", () => {
  const s = snippets["pure-modules"];
  assert.ok(s.code.includes("pub type State {"));
  assert.ok(s.code.includes("pub fn idle("));
  assert.ok(s.code.includes("pub fn request("));
  assert.ok(s.code.includes("pub fn flush("));
});

test("deterministic-death extracts test function", () => {
  assert.ok(
    snippets["deterministic-death"].code.includes(
      "pub fn held_job_returns_to_queue_when_holder_disconnects_test(",
    ),
  );
});

test("relay-decorator contains both config and with_relay", () => {
  const s = snippets["relay-decorator"];
  assert.ok(s.code.includes("let config ="));
  assert.ok(s.code.includes("fn with_relay("));
  assert.ok(s.code.includes("|> with_relay"));
});

test("fallible-edits contains MoveDownClicked, mutate, and record", () => {
  const s = snippets["fallible-edits"];
  assert.ok(s.code.includes("MoveDownClicked(index)"));
  assert.ok(s.code.includes("fn mutate("));
  assert.ok(s.code.includes("fn record("));
});

test("stamp-schema contains write, stamp, and set_child", () => {
  const s = snippets["stamp-schema"];
  assert.ok(s.code.includes("watershed_beam.write("));
  assert.ok(s.code.includes("watershed_beam.stamp("));
  assert.ok(s.code.includes("watershed_beam.set_child("));
});

test("unsettled-writes contains both ReportClicked and AtomicChanged", () => {
  const s = snippets["unsettled-writes"];
  assert.ok(s.code.includes("ReportClicked(match_key, winner)"));
  assert.ok(s.code.includes("AtomicChanged(key, value, _local)"));
  assert.ok(s.code.includes("// ... and in the register event handler:"));
});

test("typedmap-panels contains bootstrap_effect", () => {
  const s = snippets["typedmap-panels"];
  assert.ok(s.code.includes("fn bootstrap_effect("));
  assert.ok(s.code.includes("ensure_child("));
});

test("claims-seeding contains seed_givens", () => {
  const s = snippets["claims-seeding"];
  assert.ok(s.code.includes("fn seed_givens("));
  assert.ok(s.code.includes("claim_once("));
});

test("anchors-not-offsets contains refresh_anchor", () => {
  const s = snippets["anchors-not-offsets"];
  assert.ok(s.code.includes("fn refresh_anchor("));
  assert.ok(s.code.includes("text_resolve_anchor("));
});

test("authoritative-channel contains render_column", () => {
  assert.ok(snippets["authoritative-channel"].code.includes("fn render_column("));
});
