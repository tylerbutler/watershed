import gleam/list
import gleam/option.{type Option, None, Some}
import lustre/attribute as a
import lustre/element.{type Element}
import lustre/element/html as h
import watershed_site/code
import watershed_site/view/ecosystem
import watershed_site/view/sheet

type Row {
  Row(axis: String, tree: String, watershed: String)
}

pub fn view(body: List(Element(msg))) -> Element(msg) {
  sheet.view("/sharedtree/", [
    hero(),
    h.main([a.class("doc-body")], body),
    table(),
    guide(),
    ecosystem.view("/sharedtree/"),
  ])
}

fn hero() -> Element(msg) {
  h.header([a.class("st-hero")], [
    h.div([a.class("st-hero-inner")], [
      h.p([a.class("eyebrow annot")], [
        h.a([a.href("/")], [h.text("← watershed")]),
        h.text(" · "),
        h.a([a.href("/models")], [h.text("Models")]),
        h.text(" / SharedTree"),
      ]),
      h.h1([], [
        h.text("Two places to put"),
        h.br([]),
        h.em([], [h.text("the guarantee.")]),
      ]),
      h.p([a.class("lede")], [
        h.text("Fluid Framework's "),
        h.code([], [h.text("SharedTree")]),
        h.text(
          " and watershed's typed layer want the same thing: declare a document's shape once, get static types, get roots that are guaranteed to be there, get told when something changes. They disagree about where to put the guarantee, and almost everything else follows from that choice.",
        ),
      ]),
    ]),
  ])
}

fn table() -> Element(msg) {
  h.section(
    [
      a.class("st-table-section"),
      a.attribute("aria-labelledby", "st-table-title"),
    ],
    [
      h.div([a.class("st-table-inner")], [
        h.h2([a.id("st-table-title")], [h.text("Side by side")]),
        h.p([a.class("st-table-intro")], [
          h.text(
            "The same axes, two answers. Read the bottom four rows together with the top one: they are the same decision, seen from either end.",
          ),
        ]),
        h.div(
          [
            a.class("st-table-scroll"),
            a.attribute("role", "region"),
            a.attribute("aria-labelledby", "st-table-title"),
            a.tabindex(0),
          ],
          [
            h.table([a.class("st-table")], [
              h.thead([], [
                h.tr([], [
                  h.th([a.attribute("scope", "col")], [
                    h.span([a.class("visually-hidden")], [h.text("Property")]),
                  ]),
                  heading("SharedTree", None),
                  heading("watershed", Some("ws")),
                ]),
              ]),
              h.tbody([], rows() |> list.map(row)),
            ]),
          ],
        ),
      ]),
    ],
  )
}

fn heading(label: String, side: Option(String)) -> Element(msg) {
  let attributes = case side {
    None -> [a.class("th-kind")]
    Some(side) -> [a.class("th-kind"), a.attribute("data-side", side)]
  }
  h.th([a.attribute("scope", "col")], [
    h.span(attributes, [h.text(label)]),
  ])
}

fn row(item: Row) -> Element(msg) {
  h.tr([], [
    h.th([a.attribute("scope", "row")], [h.text(item.axis)]),
    h.td([], [h.text(item.tree)]),
    h.td([], [h.text(item.watershed)]),
  ])
}

fn guide() -> Element(msg) {
  h.section(
    [a.class("st-guide"), a.attribute("aria-labelledby", "st-guide-title")],
    [
      h.div([a.class("st-guide-inner")], [
        h.h2([a.id("st-guide-title")], [h.text("Further reading")]),
        h.div([a.class("st-cta")], [
          link("cta-primary", "/guide/notes", "The decode boundary →"),
          link("cta-quiet", "/models", "DDS · CRDT · OT →"),
          link("cta-quiet", "/structures", "The field atlas →"),
          link(
            "cta-quiet",
            "https://fluidframework.com/docs/data-structures/tree/",
            "SharedTree documentation ↗",
          ),
        ]),
      ]),
    ],
  )
}

pub fn gaps() -> Element(msg) {
  element.fragment([
    h.div([a.class("st-solo")], [
      code.literal_block(
        "// Atomicity — every edit in the callback lands, or none of them does.\nTree.runTransaction(board, () => {\n  card.column = \"doing\";\n  card.owner = \"ada\";\n  if (overWipLimit(board)) return Tree.runTransaction.rollback;\n});\n\n// Undo — each local commit offers a revertible.\nview.events.on(\"commitApplied\", (data, getRevertible) => {\n  if (getRevertible !== undefined) undoStack.push(getRevertible());\n});\n\n// Schema upgrade — an old document can be moved onto the new stored schema.\nif (!view.compatibility.canView && view.compatibility.canUpgrade) {\n  view.upgradeSchema();\n}",
        "typescript",
        Some("(illustrative — Fluid SharedTree gaps)"),
        Some("Fluid SharedTree · TypeScript"),
      ),
    ]),
    h.ul([], [
      gap_item("Transactions.", [
        h.text(
          " watershed writes per-key ops, so peers can observe a partial record. Fixing it means a batched multi-set map op: a wire-format change, deliberately deferred until a real consumer hurts.",
        ),
      ]),
      gap_item("Undo and redo.", [
        h.text(" Not offered. The kernels do have a "),
        h.code([], [h.text("rollback")]),
        h.text(
          ", but that is nack-and-resubmit machinery for unacknowledged local ops, not a user-facing stack.",
        ),
      ]),
      gap_item("Schema upgrade.", [
        h.text(" "),
        h.code([], [h.text("schema.versioned(n)")]),
        h.text(
          " stamps a version and fails closed on mismatch, which is a dead end rather than a path. Entries-level migrations are designed and unshipped.",
        ),
      ]),
      gap_item("Enforcement, node identity, cross-parent moves, branching.", [
        h.text(
          " Absent by design. Typing stays a client decode boundary; the server stays content-agnostic.",
        ),
      ]),
    ]),
    h.p([], [
      h.text(
        "The reason is worth stating as a number rather than an adjective. Fluid Framework's tree package (stored-versus-view schema system, forest, compositional changeset rebasing, undo/redo, ID compression) is ",
      ),
      h.strong([], [h.text("77,804 lines")]),
      h.text(
        " — a multi-year project to reproduce in any language, and one watershed would take on only for a compelling product need. watershed's entire schema vocabulary is one ",
      ),
      h.strong([], [h.text("roughly 700-line")]),
      h.text(" module: "),
      h.code([], [h.text("src/watershed/schema.gleam")]),
      h.text(". That is the trade."),
    ]),
  ])
}

fn gap_item(label: String, children: List(Element(msg))) -> Element(msg) {
  h.li([], [h.strong([], [h.text(label)]), ..children])
}

fn link(class: String, href: String, label: String) -> Element(msg) {
  h.a([a.class(class), a.href(href)], [h.text(label)])
}

fn rows() -> List(Row) {
  [
    Row(
      "Schema location",
      "in the document, as a stored schema written on first initialize",
      "in your build only, as a phantom tag and a set of field descriptors erased at runtime",
    ),
    Row(
      "A peer writes the wrong type",
      "cannot happen under the stored schema; SharedTree rejects the write on that client",
      "reaches the document, and surfaces as Error(Invalid(_)) on your read",
    ),
    Row(
      "Shape of the data",
      "one tree, one changeset algebra over the whole document",
      "a graph of independently addressed channels, joined by handles stored as map values",
    ),
    Row(
      "Merge policy",
      "one, applied to everything in the tree",
      "one per slot: LWW map, add-wins OR-set, first-writer-wins claims, commutative counter, OT rich text",
    ),
    Row(
      "Declare once",
      "SchemaFactory classes; static types derived",
      "Field / ChannelField / recordN; encoder and decoder derived from one prop list",
    ),
    Row(
      "Guaranteed roots",
      "viewWith + initialize, once, against an empty document",
      "ensure_* per slot, idempotent, run by every client on every boot",
    ),
    Row(
      "Invalidation",
      "nodeChanged plus a treeChanged subtree rollup",
      "subscribe_field (decoded previous and new) and narrowed per-kind channel events; no rollup above a channel",
    ),
    Row(
      "Atomic multi-field write",
      "Tree.runTransaction, with rollback and preconditions",
      "none: per-key ops, so peers can observe a partial record",
    ),
    Row("Undo / redo", "commitApplied → Revertible.revert()", "none offered"),
    Row(
      "Schema upgrade",
      "canView / canUpgrade / upgradeSchema, plus staged rollout",
      "versioned(n) fails closed with SchemaMismatch; no migration path",
    ),
    Row(
      "Moves",
      "moveRangeToIndex, including between arrays in the same tree",
      "convergent move inside one SharedSequence; no cross-parent move",
    ),
    Row(
      "Runs on",
      "TypeScript and JavaScript",
      "one Gleam core, on the BEAM and in the browser",
    ),
    Row(
      "Implementation size",
      "77,804 lines in the Fluid tree package",
      "about 700 lines in watershed/schema.gleam",
    ),
  ]
}
