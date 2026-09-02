// ──────────────────────────────────────────────────────────────────────────
// Tests for the generated manifest against the configuration that produced
// it, and against the code each id is supposed to show.
//
// `website/snippets.json` is the checked-in declaration; the manifest under
// `src/generated/` is built from it by `tools/source-snippets`. These tests
// prove the two agree, and that the ranges the sheets quote still hold the
// code the prose talks about.
//
// Generate the manifest first: `just snippets`.
// Run: node --strip-types --test src/lib/snippet-manifest.test.ts
// ──────────────────────────────────────────────────────────────────────────
import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { sourceSnippet, sourceSnippetIds } from "./snippet.ts";

const __dirname = dirname(fileURLToPath(import.meta.url));
const websiteRoot = resolve(__dirname, "..", "..");
const repoRoot = resolve(websiteRoot, "..");

interface ConfiguredSnippet {
  id: string;
  sourcePath: string;
  language: string;
  markers?: string[];
  wholeFile?: boolean;
  separator?: string;
}

const configured: ConfiguredSnippet[] = (
  JSON.parse(readFileSync(resolve(websiteRoot, "snippets.json"), "utf-8")) as {
    snippets: ConfiguredSnippet[];
  }
).snippets;

// ── 1. The manifest holds exactly what the configuration declares ─────────

describe("the manifest and the configuration declare the same snippets", () => {
  it("the configuration declares snippets", () => {
    assert.ok(configured.length > 0, "snippets.json declares no snippets");
  });

  it("the generated ids are the configured ids, with nothing extra", () => {
    assert.deepEqual(
      sourceSnippetIds(),
      configured.map((entry) => entry.id).sort(),
    );
  });

  for (const entry of configured) {
    it(`${entry.id}: keeps its configured path and language`, () => {
      const snippet = sourceSnippet(entry.id);
      assert.equal(snippet.sourcePath, entry.sourcePath);
      assert.equal(snippet.language, entry.language);
    });

    it(`${entry.id}: reports the selection the configuration made`, () => {
      const snippet = sourceSnippet(entry.id);
      if (entry.wholeFile === true) {
        assert.deepEqual(snippet.origin, { kind: "file" });
      } else {
        assert.deepEqual(snippet.origin, {
          kind: "source",
          markers: entry.markers,
        });
      }
    });
  }
});

// ── 2. The whole-file listing on guide/connect ────────────────────────────

describe("guide-connect-schema is the whole schema module", () => {
  const sourcePath =
    "examples/retro_tutorial_lustre/src/retro_tutorial_lustre/document_schema.gleam";
  const snippet = sourceSnippet("guide-connect-schema");

  it("declares the schema module as its source", () => {
    assert.equal(snippet.sourcePath, sourcePath);
    assert.equal(snippet.language, "gleam");
    assert.deepEqual(snippet.origin, { kind: "file" });
  });

  it("keeps the module documentation header the guide sheet shows", () => {
    assert.ok(
      snippet.code.startsWith("//// Typed schema for the tutorial retro board."),
      "the listing must open with the module documentation",
    );
    assert.match(snippet.code, /pub fn title\(\)/);
    assert.match(snippet.code, /pub fn notes\(\)/);
    assert.match(snippet.code, /pub fn votes\(\)/);
  });

  it("keeps every other line of the module, in order", () => {
    const source = readFileSync(resolve(repoRoot, sourcePath), "utf-8");
    const kept = source
      .split("\n")
      .filter((line) => !/docs:snippet-(start|end)\s/.test(line));
    const rendered = snippet.code.split("\n");

    for (const line of kept) {
      assert.ok(
        rendered.includes(line),
        `the listing dropped a line of the module: ${JSON.stringify(line)}`,
      );
    }
    // Two directive lines go, and one blank line goes with the seam the
    // formatter leaves around the end directive.
    assert.equal(rendered.length, source.split("\n").length - 3);
  });
});

// ── 3. The ranges still hold the code the sheets discuss ──────────────────

describe("marker ranges hold the code their sheet talks about", () => {
  it("guide-connect-dev-constants: the dev constants block", () => {
    const { code } = sourceSnippet("guide-connect-dev-constants");
    assert.ok(code.includes("/// These dev constants match"));
    assert.ok(code.includes("const socket_url"));
    assert.ok(code.includes("const tenant_secret"));
    assert.ok(!code.includes("pub fn main("));
  });

  it("guide-connect-readiness: GotDocument through Connected", () => {
    const { code } = sourceSnippet("guide-connect-readiness");
    assert.ok(code.includes("GotDocument(document) -> {"));
    assert.ok(code.includes("Connected(Ok(_)) -> {"));
    assert.ok(code.includes("Connected(Error(reason))"));
    assert.ok(!code.includes("EnsuredNotes(Ok(notes))"));
  });

  it("foundations-lifecycle-readiness: the same range, quoted twice", () => {
    assert.equal(
      sourceSnippet("foundations-lifecycle-readiness").code,
      sourceSnippet("guide-connect-readiness").code,
    );
  });

  it("foundations-lifecycle-ensured-arms: EnsuredNotes and EnsuredVotes", () => {
    const { code } = sourceSnippet("foundations-lifecycle-ensured-arms");
    assert.ok(code.includes("EnsuredNotes(Ok(notes))"));
    assert.ok(code.includes("EnsuredVotes(Ok(votes))"));
    assert.ok(code.includes("EnsuredNotes(Error(reason))"));
    assert.ok(code.includes("EnsuredVotes(Error(reason))"));
    assert.ok(!code.includes("SharedChanged"));
  });

  it("guide-notes-add-clicked: the AddClicked handler and its comment", () => {
    const { code } = sourceSnippet("guide-notes-add-clicked");
    assert.ok(code.includes("// These watershed mutations apply synchronously."));
    assert.ok(code.includes("AddClicked(column) -> {"));
    assert.ok(code.includes("board.add_note("));
    assert.ok(!code.includes("UpvoteClicked"));
  });

  it("guide-votes-vote-clicks: the upvote and downvote handlers", () => {
    const { code } = sourceSnippet("guide-votes-vote-clicks");
    assert.ok(code.includes("UpvoteClicked(id) ->"));
    assert.ok(code.includes("DownvoteClicked(id) ->"));
    assert.ok(code.includes("board.upvote("));
    assert.ok(code.includes("board.downvote("));
    assert.ok(!code.includes("FocusClicked"));
  });

  it("guide-presence-focus-clicked: FocusClicked and FocusCleared", () => {
    const { code } = sourceSnippet("guide-presence-focus-clicked");
    assert.ok(code.includes("FocusClicked(id) -> {"));
    assert.ok(code.includes("FocusCleared -> {"));
    assert.ok(code.includes("announce_focus(model)"));
    assert.ok(!code.includes("PresenceStarted"));
  });

  it("guide-presence-events: the PresenceEvent handler", () => {
    const { code } = sourceSnippet("guide-presence-events");
    assert.ok(code.includes("PresenceEvent(event) ->"));
    assert.ok(code.includes("presence.State(entries)"));
    assert.ok(code.includes("presence.Failed("));
    assert.ok(!code.includes("ReconnectClicked"));
  });
});

// ── 4. Composed ranges land in configuration order ────────────────────────

describe("a composed snippet joins its ranges in the configured order", () => {
  it("guide-notes-note-record puts the type before the id function", () => {
    const { code } = sourceSnippet("guide-notes-note-record");
    assert.ok(code.indexOf("pub type Note {") < code.indexOf("pub fn id("));
  });

  it("practice-unsettled-writes keeps its editorial separator", () => {
    const { code } = sourceSnippet("practice-unsettled-writes");
    assert.ok(code.includes("ReportClicked(match_key, winner)"));
    assert.ok(code.includes("// ... and in the register event handler:"));
    assert.ok(code.includes("AtomicChanged(key, value, _local)"));
  });

  it("sharedtree-nest rejoins the five schema ranges", () => {
    const { code } = sourceSnippet("sharedtree-nest");
    assert.match(code, /SudokuDocument/);
    for (const field of ["cells()", "notes()", "givens()", "mistakes()"]) {
      assert.ok(code.includes(field), `sharedtree-nest lost ${field}`);
    }
  });
});
