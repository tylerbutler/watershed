import gleam/list
import gleam/option.{Some}
import lustre/attribute as a
import lustre/element.{type Element}
import lustre/element/html as h
import watershed_site/structures
import watershed_site/view/ecosystem
import watershed_site/view/sheet

type Model {
  Model(
    kind: structures.Kind,
    name: String,
    gloss: String,
    body: List(String),
    tradeoff: String,
  )
}

type Row {
  Row(axis: String, dds: String, crdt: String, ot: String)
}

pub fn view() -> Element(msg) {
  sheet.view("/models/", [
    hero(),
    h.main([], [
      h.section(
        [a.class("mod-cards"), a.attribute("aria-label", "Convergence models")],
        list.map(models(), card),
      ),
      comparison(),
      guide(),
    ]),
    ecosystem.view("/models/"),
  ])
}

fn hero() -> Element(msg) {
  h.header([a.class("mod-hero")], [
    h.div([a.class("mod-hero-inner")], [
      h.p([a.class("eyebrow annot")], [
        h.a([a.href("/")], [h.text("← watershed")]),
        h.text(" · "),
        h.a([a.href("/structures")], [h.text("Data structures")]),
        h.text(" / Convergence models"),
      ]),
      h.h1([], [
        h.text("Three ways to"),
        h.br([]),
        h.em([], [h.text("agree on state.")]),
      ]),
      h.p([a.class("lede")], [
        h.text(
          "Every structure watershed ships has to answer one question: when two clients change the same thing at once, how does everyone end up in the same state? watershed has three answers: order it, merge it, or transform it. Each is the right one somewhere.",
        ),
      ]),
    ]),
  ])
}

fn models() -> List(Model) {
  [
    Model(
      structures.Dds,
      "Distributed Data Structure",
      "Converges by one server's total order.",
      [
        "A DDS here follows Fluid Framework's collaborative-object model. Every client applies its own ops optimistically, sends them to a central sequencer, and receives one authoritative order back. Because every replica replays the same ordered stream, they all land in the same state.",
        "The conflict policy applies on top of that order: last-write-wins for a map, first-writer-wins for a claim, FIFO for a queue, quorum for a pact. The order is the source of truth; the policy just decides what the order means.",
      ],
      "Simple and cheap, but it needs a sequencer, and offline correctness is only as good as the policy you layer on.",
    ),
    Model(
      structures.Crdt,
      "Conflict-free Replicated Data Type",
      "Converges by a merge function, no order required.",
      [
        "A CRDT is designed so its merge is commutative, associative, and idempotent. Feed two replicas the same set of updates in any order, any number of times, and they converge. No central authority is needed to referee.",
        "watershed still delivers CRDT ops over the same sequenced stream, but their correctness does not depend on it. That is why the demo can feed a duplicate delta straight to the kernel and watch the merge absorb it with no double-count. Commutativity, associativity, and idempotence provide that safety; an order-based DDS relies on the runtime deduping by sequence number.",
      ],
      "Its merge can tolerate duplicate and reordered state or deltas, but offline editing still needs durable local storage and a reconnect protocol. Metadata costs depend on the type: some keep per-replica counters, while removable collections retain tags or tombstones.",
    ),
    Model(
      structures.Ot,
      "Operational Transform",
      "Converges by transforming ops past one another.",
      [
        "OT takes the opposite tack from CRDTs. Instead of designing merges that commute, it transforms each op against the concurrent ops it did not see, rewriting indices and positions until any apply order lands in the same place.",
        "watershed ships two OT kernels on the same single-op-in-flight client protocol. json_ot is a faithful port of the ottypes json0 algebra for structured JSON documents. SharedRichText runs that protocol over quill-delta's rich-text algebra (retain/insert/delete spans, attribute patches, embeds) for collaborative Quill editors. In both, concurrent ops have their positions transformed so every replica converges identically.",
      ],
      "Minimal per-op metadata and a natural fit for ordered sequences and rich text (SharedSequence now covers similar ground by merge). The cost: transform functions must be correct for every pair of op types.",
    ),
  ]
}

fn card(model: Model) -> Element(msg) {
  let kind = structures.kind_name(model.kind)
  h.article([a.class("mod-card"), a.attribute("data-reveal", "rise")], [
    h.header([a.class("mod-card-head")], [
      h.span([a.class("stamp"), a.attribute("data-kind", kind)], [h.text(kind)]),
      h.h2([], [h.text(model.name)]),
      h.p([a.class("mod-gloss")], [h.text(model.gloss)]),
    ]),
    h.div(
      [a.class("mod-card-body")],
      list.append(
        list.map(model.body, fn(paragraph) { h.p([], [h.text(paragraph)]) }),
        [h.p([a.class("mod-tradeoff")], [h.text(model.tradeoff)])],
      ),
    ),
    h.footer([a.class("mod-members")], [
      h.span([a.class("annot")], [h.text("In watershed")]),
      h.ul(
        [],
        list.map(members(model.kind), fn(member) {
          h.li([], [
            h.a([a.href(member.1)], [h.code([], [h.text(member.0)])]),
          ])
        }),
      ),
    ]),
  ])
}

fn members(kind: structures.Kind) -> List(#(String, String)) {
  structures.all()
  |> list.flat_map(fn(family) {
    family.entries
    |> list.filter(fn(entry) { entry.kind == kind })
    |> list.map(fn(entry) {
      let href = case kind, entry.demo_href {
        structures.Ot, Some(href) -> href
        _, _ -> "/structures/" <> family.slug <> "#" <> entry.id
      }
      #(entry.name, href)
    })
  })
}

fn comparison() -> Element(msg) {
  h.section(
    [
      a.class("mod-table-section"),
      a.attribute("aria-labelledby", "mod-table-title"),
    ],
    [
      h.h2([a.id("mod-table-title")], [h.text("Side by side")]),
      h.p([a.class("mod-table-intro")], [
        h.text(
          "The same axes, three answers. None of these is strictly better; they trade a sequencer, metadata, and offline behavior against one another.",
        ),
      ]),
      h.div(
        [
          a.class("mod-table-scroll"),
          a.attribute("role", "region"),
          a.attribute("aria-labelledby", "mod-table-title"),
          a.tabindex(0),
        ],
        [
          h.table([a.class("mod-table")], [
            h.thead([], [
              h.tr([], [
                h.th([a.attribute("scope", "col")], [
                  h.span([a.class("visually-hidden")], [h.text("Property")]),
                ]),
                heading("DDS"),
                heading("CRDT"),
                heading("OT"),
              ]),
            ]),
            h.tbody([], list.map(rows(), row)),
          ]),
        ],
      ),
    ],
  )
}

fn heading(kind: String) -> Element(msg) {
  h.th([a.attribute("scope", "col")], [
    h.span([a.class("th-kind"), a.attribute("data-kind", kind)], [h.text(kind)]),
  ])
}

fn row(item: Row) -> Element(msg) {
  h.tr([], [
    h.th([a.attribute("scope", "row")], [h.text(item.axis)]),
    h.td([], [h.text(item.dds)]),
    h.td([], [h.text(item.crdt)]),
    h.td([], [h.text(item.ot)]),
  ])
}

fn rows() -> List(Row) {
  [
    Row(
      "Converges via",
      "one server's total order",
      "a commutative merge function",
      "pairwise op transforms",
    ),
    Row(
      "Needs a sequencer",
      "Yes: the order is the truth",
      "No (watershed uses one anyway)",
      "Yes: to assign the order to transform against",
    ),
    Row(
      "Duplicate / reordered delivery",
      "runtime orders and deduplicates by sequence number",
      "merge is designed to absorb repeats and reordering",
      "client protocol buffers and transforms the ordered stream",
    ),
    Row(
      "Per-item metadata",
      "structure-dependent; often a value plus sequence data",
      "type-dependent; may include replica slots, tags, or tombstones",
      "document state plus in-flight and buffered ops",
    ),
    Row(
      "Offline / unreliable links",
      "policy and client persistence determine safety",
      "merge supports it; storage and transport still required",
      "requires buffered ops and ordered reconnect",
    ),
    Row(
      "Best fit",
      "clear authority, coordination",
      "offline-first, at-least-once delivery",
      "text and ordered sequences",
    ),
  ]
}

fn guide() -> Element(msg) {
  h.section(
    [a.class("mod-guide"), a.attribute("aria-labelledby", "mod-guide-title")],
    [
      h.div([a.class("mod-guide-inner")], [
        h.h2([a.id("mod-guide-title")], [h.text("Which model fits?")]),
        h.ol([a.class("mod-guide-list")], [
          guide_item("Start with a DDS.", [
            h.text(
              " If a central server is already in the loop and last-write-wins or explicit coordination is acceptable, an order-based DDS is the least machinery for the job. Use ",
            ),
            link("/structures/maps#map", "SharedMap"),
            h.text(", "),
            link("/structures/coordination#claims", "Claims"),
            h.text(", or "),
            link("/structures/coordination#pact", "PactMap"),
            h.text("."),
          ]),
          guide_item("Use a CRDT when delivery is unreliable.", [
            h.text(
              " Offline edits backed by durable local storage, at-least-once delivery, or a counter that must survive a re-sent delta all call for a merge that does not care about order: ",
            ),
            link("/structures/counters#pn", "PN counter"),
            h.text(", "),
            link("/structures/sets#orset", "OR-set"),
            h.text(", or "),
            link("/structures/maps#ormap", "OR-map"),
            h.text("."),
          ]),
          guide_item("Use OT for ordered sequences and rich text.", [
            h.text(
              " Collaborative text and lists, where positions shift as others edit, are what transform functions were built for. See the ",
            ),
            link("/json-ot", "json_ot demo"),
            h.text(" for structured JSON or the "),
            link("/rich-text", "SharedRichText demo"),
            h.text(" for a three-editor Quill session."),
          ]),
        ]),
        h.div([a.class("mod-cta")], [
          h.a([a.class("cta-primary"), a.href("/structures")], [
            h.text("Back to the field guide"),
          ]),
          h.a([a.class("cta-quiet"), a.href("/runtime")], [
            h.text("How the runtime behaves →"),
          ]),
          h.a([a.class("cta-quiet"), a.href("/sharedtree")], [
            h.text("Fluid's SharedTree, compared →"),
          ]),
          h.a([a.class("cta-quiet"), a.href("/#demo")], [
            h.text("Compare live merge policies ↓"),
          ]),
        ]),
      ]),
    ],
  )
}

fn guide_item(title: String, children: List(Element(msg))) -> Element(msg) {
  h.li([], [h.strong([], [h.text(title)]), ..children])
}

fn link(href: String, text: String) -> Element(msg) {
  h.a([a.href(href)], [h.text(text)])
}
