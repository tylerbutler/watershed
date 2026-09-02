// Tests for marker extraction from the real Gleam source files.
// Verifies that every snippet marker in the retro tutorial produces valid,
// non-empty code matching the content that the old section() calls extracted.
// Run: node --strip-types --test src/lib/snippet-markers.test.ts
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { snippetFromMarker, snippetFromDefinition } from "./snippet.ts";

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(__dirname, "../../..");
const appPath = resolve(
  repoRoot,
  "examples/retro_tutorial_lustre/src/retro_tutorial_lustre.gleam",
);
const appSource = readFileSync(appPath, "utf-8");

const sourcePath = "examples/retro_tutorial_lustre/src/retro_tutorial_lustre.gleam";

// ── Marker extraction from the real source ─────────────────────────────

test("guide-connect-dev-constants: extracts dev constants block", () => {
  const s = snippetFromMarker(appSource, sourcePath, "gleam", "guide-connect-dev-constants");
  assert.ok(s.code.includes("/// These dev constants match"));
  assert.ok(s.code.includes("const socket_url"));
  assert.ok(s.code.includes("const tenant_secret"));
  assert.ok(!s.code.includes("pub fn main("));
});

test("update-readiness: extracts GotDocument through Connected branches", () => {
  const s = snippetFromMarker(appSource, sourcePath, "gleam", "update-readiness");
  assert.ok(s.code.includes("GotDocument(document) -> {"));
  assert.ok(s.code.includes("Connected(Ok(_)) -> {"));
  assert.ok(s.code.includes("Connected(Error(reason))"));
  assert.ok(!s.code.includes("EnsuredNotes(Ok(notes))"));
});

test("lifecycle-ensured-arms: extracts EnsuredNotes and EnsuredVotes arms", () => {
  const s = snippetFromMarker(appSource, sourcePath, "gleam", "lifecycle-ensured-arms");
  assert.ok(s.code.includes("EnsuredNotes(Ok(notes))"));
  assert.ok(s.code.includes("EnsuredVotes(Ok(votes))"));
  assert.ok(s.code.includes("EnsuredNotes(Error(reason))"));
  assert.ok(s.code.includes("EnsuredVotes(Error(reason))"));
  assert.ok(!s.code.includes("SharedChanged"));
});

test("guide-notes-add-clicked: extracts AddClicked handler with mutations comment", () => {
  const s = snippetFromMarker(appSource, sourcePath, "gleam", "guide-notes-add-clicked");
  assert.ok(s.code.includes("// These watershed mutations apply synchronously."));
  assert.ok(s.code.includes("AddClicked(column) -> {"));
  assert.ok(s.code.includes("board.add_note("));
  assert.ok(!s.code.includes("UpvoteClicked"));
});

test("guide-votes-vote-clicks: extracts Upvote and Downvote handlers", () => {
  const s = snippetFromMarker(appSource, sourcePath, "gleam", "guide-votes-vote-clicks");
  assert.ok(s.code.includes("UpvoteClicked(id) ->"));
  assert.ok(s.code.includes("DownvoteClicked(id) ->"));
  assert.ok(s.code.includes("board.upvote("));
  assert.ok(s.code.includes("board.downvote("));
  assert.ok(!s.code.includes("FocusClicked"));
});

test("guide-presence-focus-clicked: extracts FocusClicked and FocusCleared", () => {
  const s = snippetFromMarker(appSource, sourcePath, "gleam", "guide-presence-focus-clicked");
  assert.ok(s.code.includes("FocusClicked(id) -> {"));
  assert.ok(s.code.includes("FocusCleared -> {"));
  assert.ok(s.code.includes("announce_focus(model)"));
  assert.ok(!s.code.includes("PresenceStarted"));
});

test("guide-presence-events: extracts PresenceEvent handler", () => {
  const s = snippetFromMarker(appSource, sourcePath, "gleam", "guide-presence-events");
  assert.ok(s.code.includes("PresenceEvent(event) ->"));
  assert.ok(s.code.includes("presence.State(entries)"));
  assert.ok(s.code.includes("presence.Failed("));
  assert.ok(!s.code.includes("ReconnectClicked"));
});

// ── Content parity with old section() output ────────────────────────────
// These tests verify that the marker ranges produce the same logical content
// the section() function extracted. Indentation may differ due to dedent.

test("update-readiness: starts with GotDocument branch, not a marker line", () => {
  const s = snippetFromMarker(appSource, sourcePath, "gleam", "update-readiness");
  const firstLine = s.code.split("\n")[0];
  assert.ok(firstLine.includes("GotDocument(document)"), `First line: ${firstLine}`);
  assert.ok(!firstLine.includes("docs:snippet"));
});

test("all markers produce non-empty code with correct language", () => {
  const markers = [
    "guide-connect-dev-constants",
    "update-readiness",
    "lifecycle-ensured-arms",
    "guide-notes-add-clicked",
    "guide-votes-vote-clicks",
    "guide-presence-focus-clicked",
    "guide-presence-events",
  ];
  for (const name of markers) {
    const s = snippetFromMarker(appSource, sourcePath, "gleam", name);
    assert.ok(s.code.length > 10, `Marker "${name}" produced too-short code: ${s.code.length} chars`);
    assert.equal(s.language, "gleam");
    assert.equal(s.sourcePath, sourcePath);
    assert.deepEqual(s.origin, { kind: "marker", name });
  }
});

// ── Definition extraction still works for these same sources ────────────

test("definition extraction works for fn init( in the app source", () => {
  const s = snippetFromDefinition(appSource, sourcePath, "gleam", "fn init(");
  assert.ok(s.code.includes("fn init(document: String)"));
  assert.ok(s.code.includes("watershed_lustre.connect_dev("));
});

test("definition extraction works for fn bootstrap_effect(", () => {
  const s = snippetFromDefinition(appSource, sourcePath, "gleam", "fn bootstrap_effect(");
  assert.ok(s.code.includes("fn bootstrap_effect("));
  assert.ok(s.code.includes("effect.batch("));
});
