// Tests for practice snippet registry — TDD for Task 4.
// Every practice id must map to a source-backed Snippet descriptor.
// Run: node --strip-types --test src/data/practice-snippets.test.ts
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import {
  combineSnippets,
  isSourceBacked,
  originParts,
  snippetFromDefinition,
  snippetFromMarker,
  type Snippet,
} from "../lib/snippet.ts";

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(__dirname, "../../..");

function readSource(repoRelative: string): string {
  return readFileSync(resolve(repoRoot, repoRelative), "utf-8");
}

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

// ── Source paths ────────────────────────────────────────────────────────────

const sourcePaths: Record<string, string> = {
  clapCounter: "examples/clap_counter_lustre/src/clap_counter_lustre.gleam",
  diceCLI: "examples/dice_cli/src/dice_cli.gleam",
  diceLustre: "examples/dice_lustre/src/dice_lustre.gleam",
  drumMachine: "examples/drum_machine_lustre/src/drum_machine_lustre.gleam",
  audioFFI: "examples/drum_machine_lustre/src/drum_machine_lustre/audio_ffi.mjs",
  retroTutorial: "examples/retro_tutorial_lustre/src/retro_tutorial_lustre.gleam",
  scenarioProtocol: "examples/grocery_triptych_lustre/src/grocery_triptych_lustre/scenario_protocol.gleam",
  refreshGuard: "examples/grocery_triptych_lustre/src/grocery_triptych_lustre/refresh_guard.gleam",
  pixelCanvas: "examples/pixel_canvas_lustre/src/pixel_canvas_lustre.gleam",
  playlistComponent: "examples/playlist_lustre/src/playlist_lustre/component.gleam",
  retroBoard: "examples/retro_board_lustre/src/retro_board_lustre/board.gleam",
  scoreboardCLI: "examples/scoreboard_cli/src/scoreboard_cli.gleam",
  showcase: "examples/showcase_lustre/src/showcase_lustre.gleam",
  sudokuComponent: "examples/sudoku_lustre/src/sudoku_lustre/component.gleam",
  textComponent: "examples/text_lustre/src/text_lustre/component.gleam",
  tournament: "examples/tournament_bracket_lustre/src/tournament_bracket_lustre.gleam",
  queueTest: "examples/work_queue_lustre/test/queue_semantics_test.gleam",
};

// Replicate the registry's extraction logic using readFileSync instead of ?raw.
function buildSnippets(): Record<string, Snippet> {
  const src = Object.fromEntries(
    Object.entries(sourcePaths).map(([k, v]) => [k, readSource(v)])
  ) as Record<string, string>;

  return {
    "relay-decorator": combineSnippets(
      snippetFromMarker(src.clapCounter, sourcePaths.clapCounter, "gleam", "practice-relay-config"),
      snippetFromDefinition(src.clapCounter, sourcePaths.clapCounter, "gleam", "fn with_relay("),
      sourcePaths.clapCounter,
    ),
    "shared-core-two-runtimes": snippetFromDefinition(
      src.diceCLI, sourcePaths.diceCLI, "gleam", "fn event_loop(",
    ),
    "diagnostics-first": snippetFromDefinition(
      src.diceLustre, sourcePaths.diceLustre, "gleam", "fn diagnostic_line(",
    ),
    "quorum-pending-roster": snippetFromMarker(
      src.drumMachine, sourcePaths.drumMachine, "gleam", "practice-quorum-pending",
    ),
    "realtime-out-of-band": snippetFromDefinition(
      src.audioFFI, sourcePaths.audioFFI, "js", "function tick(engine)",
    ),
    "presence-idiom": snippetFromDefinition(
      src.retroTutorial, sourcePaths.retroTutorial, "gleam",
      "fn presence_effect(", "fn remote_peers(",
    ),
    "protocol-on-ripples": snippetFromDefinition(
      src.scenarioProtocol, sourcePaths.scenarioProtocol, "gleam",
      "pub fn matches_run(", "pub fn from_self(", "pub fn should_acknowledge(",
    ),
    "pure-modules": snippetFromDefinition(
      src.refreshGuard, sourcePaths.refreshGuard, "gleam",
      "pub type State {", "pub fn idle(", "pub fn request(", "pub fn flush(",
    ),
    "ffi-surface": snippetFromMarker(
      src.pixelCanvas, sourcePaths.pixelCanvas, "gleam", "practice-ffi-connected",
    ),
    "fallible-edits": combineSnippets(
      snippetFromMarker(src.playlistComponent, sourcePaths.playlistComponent, "gleam", "practice-fallible-move"),
      snippetFromDefinition(src.playlistComponent, sourcePaths.playlistComponent, "gleam", "fn mutate(", "fn record("),
      sourcePaths.playlistComponent,
    ),
    "authoritative-channel": snippetFromDefinition(
      src.retroBoard, sourcePaths.retroBoard, "gleam", "fn render_column(",
    ),
    "stamp-schema": snippetFromMarker(
      src.scoreboardCLI, sourcePaths.scoreboardCLI, "gleam", "practice-stamp-schema",
    ),
    "typedmap-panels": snippetFromDefinition(
      src.showcase, sourcePaths.showcase, "gleam", "fn bootstrap_effect(",
    ),
    "claims-seeding": snippetFromDefinition(
      src.sudokuComponent, sourcePaths.sudokuComponent, "gleam", "fn seed_givens(",
    ),
    "anchors-not-offsets": snippetFromDefinition(
      src.textComponent, sourcePaths.textComponent, "gleam", "fn refresh_anchor(",
    ),
    "unsettled-writes": combineSnippets(
      snippetFromMarker(src.tournament, sourcePaths.tournament, "gleam", "practice-unsettled-report"),
      snippetFromMarker(src.tournament, sourcePaths.tournament, "gleam", "practice-unsettled-atomic"),
      sourcePaths.tournament,
      "\n\n// ... and in the register event handler:\n",
    ),
    "deterministic-death": snippetFromDefinition(
      src.queueTest, sourcePaths.queueTest, "gleam",
      "pub fn held_job_returns_to_queue_when_holder_disconnects_test(",
    ),
  };
}

// ── Tests ──────────────────────────────────────────────────────────────────

const snippets = buildSnippets();

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

test("no descriptor uses literal origin (all must be source-backed)", () => {
  for (const [id, snippet] of Object.entries(snippets)) {
    // originParts flattens a composite, so a joined snippet cannot hide a
    // literal half behind a non-literal `origin.kind`.
    assert.ok(
      isSourceBacked(snippet),
      `Practice "${id}" has a literal origin part — every part must be a definition or a marker`,
    );
  }
});

// ── Composite origins name every part they were built from ─────────────────

test("a joined descriptor reports both of its parts, not just the first", () => {
  for (const id of ["relay-decorator", "fallible-edits", "unsettled-writes"]) {
    const origin = snippets[id].origin;
    assert.equal(
      origin.kind,
      "composite",
      `Practice "${id}" joins two extractions, so its origin must be composite`,
    );
    assert.equal(
      originParts(origin).length,
      2,
      `Practice "${id}" must report both parts it was built from`,
    );
  }
});

test("combineSnippets keeps both origins, and the code of both", () => {
  const first = snippetFromMarker(
    ["// docs:snippet-start a", "let a = 1", "// docs:snippet-end a"].join("\n"),
    "src/x.gleam", "gleam", "a",
  );
  const second = snippetFromDefinition(
    "pub fn b() {\n  2\n}\n", "src/x.gleam", "gleam", "pub fn b(",
  );
  const joined = combineSnippets(first, second, "src/x.gleam");

  assert.deepEqual(originParts(joined.origin), [first.origin, second.origin]);
  assert.ok(joined.code.includes("let a = 1"));
  assert.ok(joined.code.includes("pub fn b()"));
});

test("a composite carrying a literal part is not source-backed", () => {
  const marker = snippetFromMarker(
    ["// docs:snippet-start a", "let a = 1", "// docs:snippet-end a"].join("\n"),
    "src/x.gleam", "gleam", "a",
  );
  const literal = {
    code: "let b = 2",
    language: "gleam",
    sourcePath: "src/x.gleam",
    origin: { kind: "literal" as const },
  };
  const joined = combineSnippets(marker, literal, "src/x.gleam");

  assert.equal(joined.origin.kind, "composite");
  assert.ok(
    !isSourceBacked(joined),
    "a composite must not vouch for a literal part by reporting its first origin",
  );
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
  assert.deepEqual(snippets["shared-core-two-runtimes"].origin.kind, "definition");
});

test("diagnostics-first contains fn diagnostic_line", () => {
  assert.ok(snippets["diagnostics-first"].code.includes("fn diagnostic_line("));
  assert.deepEqual(snippets["diagnostics-first"].origin.kind, "definition");
});

test("realtime-out-of-band contains function tick and is JS", () => {
  const s = snippets["realtime-out-of-band"];
  assert.ok(s.code.includes("function tick(engine)"));
  assert.equal(s.language, "js");
  assert.deepEqual(s.origin.kind, "definition");
});

test("quorum-pending-roster contains BpmCommitted arm", () => {
  const s = snippets["quorum-pending-roster"];
  assert.ok(s.code.includes("BpmCommitted ->"));
  assert.deepEqual(s.origin.kind, "marker");
});

test("ffi-surface contains Connected arms", () => {
  const s = snippets["ffi-surface"];
  assert.ok(s.code.includes("Connected(Ok(_))"));
  assert.ok(s.code.includes("Connected(Error(reason))"));
  assert.deepEqual(s.origin.kind, "marker");
});

test("presence-idiom extracts two definitions", () => {
  const s = snippets["presence-idiom"];
  assert.ok(s.code.includes("fn presence_effect("));
  assert.ok(s.code.includes("fn remote_peers("));
  assert.deepEqual(s.origin.kind, "definition");
});

test("protocol-on-ripples extracts three definitions", () => {
  const s = snippets["protocol-on-ripples"];
  assert.ok(s.code.includes("pub fn matches_run("));
  assert.ok(s.code.includes("pub fn from_self("));
  assert.ok(s.code.includes("pub fn should_acknowledge("));
  assert.deepEqual(s.origin.kind, "definition");
});

test("pure-modules extracts type and three functions", () => {
  const s = snippets["pure-modules"];
  assert.ok(s.code.includes("pub type State {"));
  assert.ok(s.code.includes("pub fn idle("));
  assert.ok(s.code.includes("pub fn request("));
  assert.ok(s.code.includes("pub fn flush("));
  assert.deepEqual(s.origin.kind, "definition");
});

test("deterministic-death extracts test function", () => {
  const s = snippets["deterministic-death"];
  assert.ok(s.code.includes("pub fn held_job_returns_to_queue_when_holder_disconnects_test("));
  assert.deepEqual(s.origin.kind, "definition");
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
  const s = snippets["authoritative-channel"];
  assert.ok(s.code.includes("fn render_column("));
});
