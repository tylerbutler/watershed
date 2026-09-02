// ──────────────────────────────────────────────────────────────────────────
// Standalone snippet registry — source-backed code excerpts for the
// homepage, runtime pages, and the SharedTree comparison. Each Gleam
// snippet is extracted from a compiled source (example or fixture);
// TypeScript snippets are explicit literals with syntax checking.
// ──────────────────────────────────────────────────────────────────────────
import {
  snippetFromDefinition,
  snippetFromLiteral,
  snippetFromMarker,
  type Snippet,
} from "../lib/snippet.ts";

// ── Raw source imports (Gleam — compiled examples) ─────────────────────────
import diceCLISource from "../../../examples/dice_cli/src/dice_cli.gleam?raw";
import sudokuSchemaSource from "../../../examples/sudoku_lustre/src/sudoku_lustre/document_schema.gleam?raw";
import sudokuComponentSource from "../../../examples/sudoku_lustre/src/sudoku_lustre/component.gleam?raw";

// ── Raw source imports (Gleam — website fixture) ───────────────────────────
import boardSchemaSource from "../../../tools/website-samples/src/website_samples/board_schema.gleam?raw";
import boardAppSource from "../../../tools/website-samples/src/website_samples/board_app.gleam?raw";
import optimisticSource from "../../../tools/website-samples/src/website_samples/optimistic_sample.gleam?raw";
import p2pSource from "../../../tools/website-samples/src/website_samples/p2p_sample.gleam?raw";

// ── Source paths (repo-relative, for citation and links) ───────────────────
const paths = {
  diceCLI: "examples/dice_cli/src/dice_cli.gleam",
  sudokuSchema: "examples/sudoku_lustre/src/sudoku_lustre/document_schema.gleam",
  sudokuComponent: "examples/sudoku_lustre/src/sudoku_lustre/component.gleam",
  boardSchema: "tools/website-samples/src/website_samples/board_schema.gleam",
  boardApp: "tools/website-samples/src/website_samples/board_app.gleam",
  optimistic: "tools/website-samples/src/website_samples/optimistic_sample.gleam",
  p2p: "tools/website-samples/src/website_samples/p2p_sample.gleam",
} as const;

// ── Gleam snippets ─────────────────────────────────────────────────────────

/** Every standalone Gleam snippet, keyed by extraction id. */
export const standaloneSnippets: Record<string, Snippet> = {
  // Homepage BEAM sample — the full connect → root → subscribe → set → loop
  // flow from the dice CLI example.
  "homepage-beam": snippetFromMarker(
    diceCLISource, paths.diceCLI, "gleam", "homepage-beam",
  ),

  // Runtime / optimistic — local set + immediate get
  "optimistic-local": snippetFromMarker(
    optimisticSource, paths.optimistic, "gleam", "optimistic-local",
  ),

  // Runtime / p2p — CRDT document configuration
  "p2p-config": snippetFromMarker(
    p2pSource, paths.p2p, "gleam", "p2p-config",
  ),

  // SharedTree comparison — schema declaration
  "sharedtree-declare": snippetFromMarker(
    boardSchemaSource, paths.boardSchema, "gleam", "sharedtree-declare",
  ),

  // SharedTree comparison — bootstrap with ensure_*
  "sharedtree-bootstrap": snippetFromMarker(
    boardAppSource, paths.boardApp, "gleam", "sharedtree-bootstrap",
  ),

  // SharedTree comparison — typed read / write
  "sharedtree-read-write": snippetFromMarker(
    boardAppSource, paths.boardApp, "gleam", "sharedtree-read-write",
  ),

  // SharedTree comparison — record schema + write
  "sharedtree-record": snippetFromMarker(
    boardAppSource, paths.boardApp, "gleam", "sharedtree-record",
  ),

  // SharedTree comparison — field subscription events
  "sharedtree-events": snippetFromMarker(
    boardAppSource, paths.boardApp, "gleam", "sharedtree-events",
  ),

  // SharedTree comparison — one root, four channel merge policies
  "sharedtree-nest": snippetFromMarker(
    sudokuSchemaSource, paths.sudokuSchema, "gleam", "sharedtree-nest",
  ),

  // SharedTree comparison — narrowed per-kind subscriptions
  "sharedtree-per-kind": snippetFromMarker(
    sudokuComponentSource, paths.sudokuComponent, "gleam", "sharedtree-per-kind",
  ),
};

// ── SharedTree TypeScript literals ─────────────────────────────────────────
// Fluid Framework TypeScript stays illustrative. Each snippet is an explicit
// literal checked for valid syntax at test time; fluid-framework is external.

export const sharedtreeTypeScriptSnippets: Record<string, Snippet> = {
  "ts-declare": snippetFromLiteral(
    `import { SchemaFactory } from "fluid-framework";

// This id is written into the document. It becomes the *stored* schema,
// and from here on every client's SharedTree enforces it.
const sf = new SchemaFactory("com.example.sprintboard");

class Card extends sf.object("Card", {
  title: sf.string,
  column: sf.string,
  owner: sf.optional(sf.string),
}) {}

class Cards extends sf.array("Cards", Card) {}

class Board extends sf.object("Board", {
  title: sf.string,
  cards: Cards,
  wipBreaches: sf.number,
}) {}`,
    "typescript",
    "(illustrative — Fluid SharedTree schema)",
  ),

  "ts-root": snippetFromLiteral(
    `import { TreeViewConfiguration } from "fluid-framework";

const config = new TreeViewConfiguration({ schema: Board });
const view = tree.viewWith(config);

// Once, against an empty document. After this the stored schema is
// authoritative and every later client just reads it.
view.initialize(
  new Board({ title: "Sprint board", cards: [], wipBreaches: 0 }),
);

const board = view.root; // typed Board, guaranteed to exist`,
    "typescript",
    "(illustrative — Fluid SharedTree root)",
  ),

  "ts-read-write": snippetFromLiteral(
    `// Writing is checked by the compiler and again by SharedTree.
board.title = "Q3 sprint board";

// Reading is total. \`title\` is a string, and no client running this
// schema can make it anything else.
renderHeader(board.title);`,
    "typescript",
    "(illustrative — Fluid SharedTree read/write)",
  ),

  "ts-record": snippetFromLiteral(
    `// The shape was declared once, on the class. There is no second
// encoder to keep in sync, because the tree stores the node itself.
card.title = "Ship the gauge rebuild";
card.column = "doing";
card.owner = undefined; // clears the optional property`,
    "typescript",
    "(illustrative — Fluid SharedTree record)",
  ),

  "ts-nest": snippetFromLiteral(
    `// Everything is in one tree under one changeset algebra, so inserts,
// removals, and reorders are all edits to the same document — and all
// merge by the same rules.
board.cards.insertAtEnd(new Card({ title: "Ship it", column: "todo" }));
board.cards.moveRangeToIndex(4, 0, 3);
board.cards.removeAt(2);`,
    "typescript",
    "(illustrative — Fluid SharedTree nesting)",
  ),

  "ts-events": snippetFromLiteral(
    `// Per node, plus a subtree rollup for free: \`treeChanged\` fires for a
// change anywhere below the node, because there is a tree to roll up.
const stopCards = Tree.on(board.cards, "nodeChanged", renderCards);
const stopAll = Tree.on(board, "treeChanged", renderEverything);

// Editing the tree from inside a change callback throws a UsageError.`,
    "typescript",
    "(illustrative — Fluid SharedTree events)",
  ),

  "ts-gaps": snippetFromLiteral(
    `// Atomicity — every edit in the callback lands, or none of them does.
Tree.runTransaction(board, () => {
  card.column = "doing";
  card.owner = "ada";
  if (overWipLimit(board)) return Tree.runTransaction.rollback;
});

// Undo — each local commit offers a revertible.
view.events.on("commitApplied", (data, getRevertible) => {
  if (getRevertible !== undefined) undoStack.push(getRevertible());
});

// Schema upgrade — an old document can be moved onto the new stored schema.
if (!view.compatibility.canView && view.compatibility.canUpgrade) {
  view.upgradeSchema();
}`,
    "typescript",
    "(illustrative — Fluid SharedTree gaps)",
  ),
};
