// ──────────────────────────────────────────────────────────────────────────
// Standalone snippet registry — the source-backed code the homepage, the
// runtime sheets, and the SharedTree comparison quote, plus the Fluid
// TypeScript the comparison sets beside it.
//
// The Gleam side is generated: `website/snippets.json` declares each range,
// `tools/source-snippets` extracts it, and the loader fails the build on an
// id nothing generates. The TypeScript side stays illustrative — Fluid
// Framework is external, so there is no checked-in source to quote — and
// each literal is parsed at test time instead.
// ──────────────────────────────────────────────────────────────────────────
import { snippetFromLiteral, sourceSnippet, type Snippet } from "../lib/snippet.ts";

// ── Gleam snippets ─────────────────────────────────────────────────────────

/** Every standalone Gleam snippet, keyed by generated id. */
export const standaloneSnippets: Record<string, Snippet> = {
  // Homepage BEAM sample — the full connect → root → subscribe → set → loop
  // flow from the dice CLI example.
  "homepage-beam": sourceSnippet("homepage-beam"),

  // Runtime / optimistic — local set + immediate get
  "optimistic-local": sourceSnippet("optimistic-local"),

  // Runtime / p2p — CRDT document configuration
  "p2p-config": sourceSnippet("p2p-config"),

  // SharedTree comparison — schema declaration
  "sharedtree-declare": sourceSnippet("sharedtree-declare"),

  // SharedTree comparison — bootstrap with ensure_*
  "sharedtree-bootstrap": sourceSnippet("sharedtree-bootstrap"),

  // SharedTree comparison — typed read / write
  "sharedtree-read-write": sourceSnippet("sharedtree-read-write"),

  // SharedTree comparison — record schema + write
  "sharedtree-record": sourceSnippet("sharedtree-record"),

  // SharedTree comparison — field subscription events
  "sharedtree-events": sourceSnippet("sharedtree-events"),

  // SharedTree comparison — one root, four channel merge policies. The four
  // channel fields carry their own markers so the schema sheet can quote them
  // without the tag and the two plain fields above them; this sheet wants the
  // whole block, so the configuration composes the five ranges back together.
  "sharedtree-nest": sourceSnippet("sharedtree-nest"),

  // SharedTree comparison — narrowed per-kind subscriptions
  "sharedtree-per-kind": sourceSnippet("sharedtree-per-kind"),
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
