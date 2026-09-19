import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre/attribute as a
import lustre/element.{type Element}
import lustre/element/html as h
import lustre/event
import watershed_site/structure_demo/model.{
  type Model, type Replica, type Structure, ClientA, ClientB, ClientC, Failed,
  Map, MvRegister, Ready, Static,
}
import watershed_site/structure_demo/runtime

pub type Options {
  Options(include_noscript: Bool, views: List(String), heading: Option(String))
}

pub fn static(selected: Structure, options: Options) -> Element(Nil) {
  view(runtime.static_model(selected), options)
  |> element.map(fn(_) { Nil })
}

pub fn view(model: Model, options: Options) -> Element(runtime.Msg) {
  case options.heading {
    Some(heading) -> family_view(model, options.views, heading)
    None -> static_variant(model, options.include_noscript)
  }
}

fn family_view(
  model: Model,
  requested_views: List(String),
  heading: String,
) -> Element(runtime.Msg) {
  let views = expand_views(requested_views)
  let initial = runtime.structure_id(model.selected)
  h.section(
    list.append(
      [
        a.id("demo"),
        a.class("demo demo-embedded"),
        a.attribute("aria-labelledby", "demo-title"),
      ],
      mounted_attribute(model),
    ),
    [
      h.a([a.class("demo-skip"), a.href("#after-demo")], [
        h.text("Skip past the interactive demo"),
      ]),
      h.div([a.class("demo-head")], [
        h.h2([a.id("demo-title"), a.class("visually-hidden")], [
          h.text(heading),
        ]),
        h.div([a.class("demo-intro")], [
          h.p([], [
            h.text(
              "Try an edit on any client, race concurrent writes, or switch on jitter. Pending edits print in ",
            ),
            h.strong([a.class("k-pending")], [h.text("magenta")]),
            h.text(
              "; once the sequencer stamps an SN, every replica lands the same ",
            ),
            h.strong([a.class("k-seq")], [h.text("ink")]),
            h.text(" state."),
          ]),
        ]),
      ]),
      h.div([a.class("dds-switch")], [
        picker(views, initial),
        ..merge_rules(views, initial)
      ]),
      family_rig(model, views),
      controls(model),
      h.p([a.class("controls-hint")], [
        h.span([], [
          h.text(
            "Jitter can change simulated arrival order; animation speed changes playback only. Each moving request shows its sampled hop latency. “Ops in flight” counts every hop still travelling: one client → sequencer leg, then one sequencer → replica leg per client.",
          ),
        ]),
      ]),
      h.noscript([], [
        h.p([a.class("demo-noscript")], [
          h.text(
            "The live demo needs JavaScript: it runs watershed's actual kernels in your browser. The rest of the page works fine without it.",
          ),
        ]),
      ]),
      h.p(
        [
          a.class("demo-noscript"),
          a.attribute("data-demo-fallback", ""),
          a.hidden(True),
        ],
        [
          h.text(
            "The live demo couldn't start: this browser didn't load watershed's compiled kernels. The rest of the page works fine without it. ",
          ),
          h.a([a.href("")], [h.text("Reload the page to retry.")]),
        ],
      ),
    ],
  )
}

fn expand_views(views: List(String)) -> List(String) {
  list.flat_map(views, fn(view) {
    case view {
      "ormap" -> ["ormap", "or-map-mv-register"]
      _ -> [view]
    }
  })
}

fn picker(views: List(String), initial: String) -> Element(runtime.Msg) {
  let cells = [
    #("map", "Shared map", "DDS"),
    #("lww-map", "LWWMap", "CRDT"),
    #("counter", "Shared counter", "DDS"),
    #("gcounter", "G-counter", "CRDT"),
    #("pn", "PN counter", "CRDT"),
    #("ormap", "OR-map", "CRDT"),
    #("or-map-mv-register", "OR-map / MV registers", "CRDT"),
    #("lww-register", "LWW register", "CRDT"),
    #("mv-register", "MV register", "CRDT"),
    #("orset", "OR-set", "CRDT"),
    #("gset", "G-set", "CRDT"),
    #("twopset", "2P-set", "CRDT"),
    #("claims", "Claims", "DDS"),
    #("registers", "Registers", "DDS"),
    #("ordered", "OrderedCollection", "DDS"),
    #("tasks", "TaskManager", "DDS"),
    #("pact", "PactMap", "DDS"),
  ]
  h.fieldset(
    [
      a.class("dds-picker"),
      a.attribute("data-dds-picker", ""),
      a.hidden(True),
    ],
    [
      h.legend([a.class("visually-hidden")], [
        h.text("Data structure shown in all clients"),
      ]),
      ..list.filter_map(cells, fn(cell) {
        case list.contains(views, cell.0) {
          False -> Error(Nil)
          True ->
            Ok(
              h.label([], [
                h.input([
                  a.type_("radio"),
                  a.name("dds"),
                  a.value(cell.0),
                  a.checked(cell.0 == initial),
                  a.attribute("data-dds-pick", ""),
                  event.on_click(runtime.SelectId(cell.0)),
                ]),
                h.span([], [
                  h.text(cell.1 <> " "),
                  h.b([], [h.text(cell.2)]),
                ]),
              ]),
            )
        }
      })
    ],
  )
}

fn merge_rules(
  views: List(String),
  initial: String,
) -> List(Element(runtime.Msg)) {
  let rules = [
    #(
      "map",
      "Merge rule: last write wins. Server sequence decides which write survives.",
    ),
    #(
      "lww-map",
      "Merge rule: timestamp wins per key. Author identity breaks an equal-time tie.",
    ),
    #(
      "counter",
      "Merge rule: increments commute. Concurrent changes add instead of overwriting one another.",
    ),
    #(
      "gcounter",
      "Merge rule: grow-only max per replica. Duplicate delivery cannot count an increment twice.",
    ),
    #(
      "pn",
      "Merge rule: positive and negative grow-only tallies merge independently.",
    ),
    #(
      "lww-register",
      "Merge rule: timestamp wins; author identity breaks a tie.",
    ),
    #(
      "mv-register",
      "Merge rule: keep concurrent alternatives until a later write resolves what it has seen.",
    ),
    #(
      "or-map-mv-register",
      "Keep the key. Read the disagreement. The OR-map preserves unseen writes while each MV register preserves concurrent alternatives.",
    ),
    #(
      "orset",
      "Merge rule: add-wins, observed-remove. An unseen concurrent add survives removal.",
    ),
    #("gset", "Merge rule: grow-only union. Facts can be added, never removed."),
    #(
      "twopset",
      "Merge rule: tombstone wins. A removed value cannot be added again.",
    ),
    #(
      "claims",
      "Merge rule: first writer wins. A claim appears only after the sequencer accepts it.",
    ),
    #(
      "registers",
      "Merge rule: atomic sequence plus retained versions. Concurrent losers remain available to versioned reads.",
    ),
    #(
      "ordered",
      "Merge rule: FIFO by sequence. The first sequenced acquire takes the front item.",
    ),
    #(
      "tasks",
      "Merge rule: one assignee, FIFO waiters. Abandon promotes the next volunteer.",
    ),
    #(
      "pact",
      "Merge rule: quorum acceptance. A value takes effect only after every required client signs off.",
    ),
  ]
  let standard =
    list.filter_map(rules, fn(rule) {
      case list.contains(views, rule.0) {
        False -> Error(Nil)
        True ->
          Ok(
            h.p(
              [
                a.class("merge-rule"),
                a.attribute("data-merge-rule", rule.0),
                a.hidden(rule.0 != initial),
              ],
              [h.strong([], [h.text(rule.1)])],
            ),
          )
      }
    })
  let ormap = case list.contains(views, "ormap") {
    False -> [
      h.p([a.attribute("data-ormap-tally-note", ""), a.hidden(True)], []),
      h.p([a.attribute("data-ormap-set-note", ""), a.hidden(True)], []),
    ]
    True -> [
      ormap_view_controls(initial),
      h.div(
        [
          a.class("merge-rule"),
          a.attribute("data-merge-rule", "ormap"),
          a.hidden(initial != "ormap"),
        ],
        [
          h.p([a.attribute("data-ormap-tally-note", "")], [
            h.strong([], [
              h.text("Merge rule: add-wins, observed-remove."),
            ]),
            h.text(
              " A strike removes only the history this client has seen; an unseen concurrent delivery keeps the key alive.",
            ),
          ]),
          h.p([a.attribute("data-ormap-set-note", ""), a.hidden(True)], [
            h.strong([], [h.text("Merge the members, not an array.")]),
            h.text(
              " Independent additions survive together, while removals clear only observed tags.",
            ),
          ]),
        ],
      ),
      ormap_controls(initial),
    ]
  }
  list.append(standard, ormap)
}

fn ormap_view_controls(initial: String) -> Element(runtime.Msg) {
  h.div(
    [
      a.class("ormap-controls"),
      a.attribute("data-ormap-view-controls", ""),
      a.hidden(initial != "ormap" && initial != "or-map-mv-register"),
    ],
    [
      h.label([], [
        h.span([a.class("annot")], [h.text("OR-map instance")]),
        h.select(
          [
            a.attribute("data-ormap-view", ""),
            event.on_input(runtime.SelectId),
          ],
          [
            h.option([a.value("ormap")], "Ledger / string sets"),
            h.option(
              [a.value("or-map-mv-register")],
              "MV registers · gate revisions",
            ),
          ],
        ),
      ]),
      h.p([a.class("mv-hint")], [
        h.text(
          "These are separate OR-map instances. Switching views keeps their edits.",
        ),
      ]),
    ],
  )
}

fn ormap_controls(initial: String) -> Element(runtime.Msg) {
  h.div(
    [
      a.class("ormap-controls"),
      a.attribute("data-ormap-controls", ""),
      a.hidden(initial != "ormap"),
    ],
    [
      h.label([], [
        h.span([a.class("annot")], [h.text("Value mode for all three clients")]),
        h.select(
          [
            a.attribute("data-ormap-mode", ""),
            event.on_input(runtime.SetOrMapMode),
          ],
          [
            h.option([a.value("tally")], "Tallies · stockpile ledger"),
            h.option([a.value("set")], "String sets · document checklist"),
          ],
        ),
      ]),
      h.div([a.attribute("data-ormap-scenarios", ""), a.hidden(True)], [
        h.label([], [
          h.span([a.class("annot")], [h.text("Controlled set scenario")]),
          h.select([a.attribute("data-ormap-set-race", ""), a.disabled(True)], [
            h.option([a.value("union")], "Independent additions to one key"),
            h.option([a.value("member")], "Member removal vs fresh re-add"),
            h.option([a.value("key")], "Key removal vs unseen member"),
            h.option([a.value("readd")], "Remove key, re-add, replay old add"),
            h.option(
              [a.value("empty")],
              "Last member and absent-member removals",
            ),
          ]),
        ]),
        h.p(
          [
            a.class("annot"),
            a.attribute("data-ormap-race-status", ""),
            a.role("status"),
          ],
          [h.text("Ready to run.")],
        ),
      ]),
    ],
  )
}

fn family_rig(model: Model, views: List(String)) -> Element(runtime.Msg) {
  h.div(
    [
      a.class("rig"),
      a.attribute("data-demo-rig", ""),
      a.attribute("data-dds", runtime.structure_id(model.selected)),
      a.attribute("data-views", string.join(views, ",")),
    ],
    [
      client(model, ClientA, "a", "Client A", "raise crest", True),
      client(model, ClientB, "b", "Client B", "arm pump", True),
      client(model, ClientC, "c", "Client C", "check datum", True),
      h.div([a.class("channel"), a.style("grid-area", "seq")], [
        h.div([a.class("seq-node"), a.attribute("data-seq-node", "")], [
          h.span([a.class("annot")], [h.text("Sequencer")]),
          h.output(
            [
              a.class("seq-counter"),
              a.attribute("data-seq-counter", ""),
              a.attribute("aria-label", "Latest sequence number"),
            ],
            [h.text("SN " <> int.to_string(model.sequence_number))],
          ),
        ]),
        h.ol(
          [
            a.class("op-log"),
            a.attribute("data-op-log", ""),
            a.attribute("aria-live", "polite"),
            a.attribute("aria-label", "Sequenced operations, newest first"),
          ],
          list.map(model.log, fn(entry) {
            h.li([], [
              h.text(
                "#"
                <> int.to_string(entry.sequence_number)
                <> " "
                <> entry.label,
              ),
            ])
          }),
        ),
      ]),
      h.div(
        [
          a.class("flow-layer"),
          a.attribute("data-flow-layer", ""),
          a.attribute("aria-hidden", "true"),
        ],
        [],
      ),
    ],
  )
}

fn static_variant(
  model: Model,
  include_noscript: Bool,
) -> Element(runtime.Msg) {
  let map = model.selected == Map
  h.section(
    list.append(
      [
        a.id("demo"),
        a.class("demo"),
        a.attribute("aria-labelledby", "demo-title"),
      ],
      mounted_attribute(model),
    ),
    [
      h.a([a.class("demo-skip"), a.href("#after-demo")], [
        h.text("Skip past the interactive demo"),
      ]),
      h.div([a.class("demo-head")], [
        h.h2([a.id("demo-title")], [
          h.text(case map {
            True -> "Watch three clients converge"
            False -> "One slate, three field crews"
          }),
        ]),
        h.div([a.class("demo-head-grid")], [
          h.div([a.class("demo-intro")], [
            h.p([], [
              h.text(case map {
                True ->
                  "On a photorevised survey sheet, magenta marks updates not yet field-checked. This demo borrows that color code: edits that aren't confirmed yet are drawn in magenta, confirmed state in ink. All three clients run watershed's compiled map_kernel Gleam code and share one ordered list of changes. That is a shared map, the structure most collaborative apps start with."
                False ->
                  "Confirmed alternatives stay in ink; your pending revision appears in magenta. Cut Client B's link, write on both sides, then restore it. Agreement means every crew sees the same alternatives, not necessarily a single answer."
              }),
            ]),
            h.p([], [
              h.text(case map {
                True ->
                  "Nudge a gauge, have two clients write at once, stretch the network delay. The copies agree once queued writes arrive; the most recent write to a key wins. Try cutting Client B's link mid-edit: its writes park locally, the others keep converging, and restoring the link catches B up."
                False ->
                  "Re-deliver keeps an earlier delta even after resolution. The old revision stays retired. Reset tears off a fresh slate and discards delayed work from the previous one."
              }),
            ]),
          ]),
          h.ol(
            [
              a.class("demo-legend annot"),
              a.attribute("aria-label", "How an edit converges"),
            ],
            [
              h.li([], [
                h.span([a.class("k-pending")], [
                  h.text("1 · local edit"),
                ]),
                h.text(" prints in magenta"),
              ]),
              h.li([], [
                h.span([a.class("k-flow")], [
                  h.text("2 · the sequencer"),
                ]),
                h.text(" stamps it with an SN"),
              ]),
              h.li([], [
                h.span([a.class("k-seq")], [
                  h.text("3 · every client"),
                ]),
                h.text(" lands the same ink state"),
              ]),
            ],
          ),
        ]),
      ]),
      h.p(
        [
          a.class("merge-rule"),
          a.attribute("data-merge-rule", case map {
            True -> "map"
            False -> "mv-register"
          }),
        ],
        [
          case map {
            True ->
              h.strong([], [
                h.text(
                  "Merge rule: the latest sequenced write to each key wins.",
                ),
              ])
            False ->
              h.strong([], [h.text("Merge rule: keep concurrent alternatives.")])
          },
          h.text(case map {
            True ->
              " Different keys merge independently. Concurrent writes to one key follow the server's final sequence."
            False ->
              " Two revisions can converge without agreeing on one answer. After both arrive, write a combined revision to replace the alternatives you've seen."
          }),
        ],
      ),
      h.p([a.attribute("data-ormap-tally-note", ""), a.hidden(True)], []),
      h.p([a.attribute("data-ormap-set-note", ""), a.hidden(True)], []),
      h.div([a.class("field-notes-row")], [
        h.label([a.class("field-notes-toggle")], [
          h.input([
            a.type_("checkbox"),
            a.attribute("data-field-notes", ""),
            a.attribute("aria-describedby", "field-notes-help"),
            a.disabled(True),
          ]),
          h.span([a.class("field-note-tip")], [
            h.span([a.class("annot")], [h.text("Field notes")]),
            h.span(
              [
                a.class("field-note-mark"),
                a.attribute("aria-hidden", "true"),
              ],
              [h.text("?")],
            ),
            h.span(
              [
                a.class("field-note-tooltip"),
                a.id("field-notes-help"),
                a.attribute("role", "tooltip"),
              ],
              [
                h.text(
                  "Show hand-drawn annotations as edits move from pending to sequenced.",
                ),
              ],
            ),
          ]),
        ]),
      ]),
      h.div(
        [
          a.class("rig"),
          a.attribute("data-demo-rig", ""),
          a.attribute("data-dds", case map {
            True -> "map"
            False -> "mv-register"
          }),
          a.attribute("data-views", case map {
            True -> "map"
            False -> "mv-register"
          }),
        ],
        [
          client(model, ClientA, "a", "Client A", "raise crest", False),
          client(model, ClientB, "b", "Client B", "arm pump", False),
          client(model, ClientC, "c", "Client C", "check datum", False),
          h.div([a.class("channel"), a.style("grid-area", "seq")], [
            h.div([a.class("seq-node"), a.attribute("data-seq-node", "")], [
              h.span([a.class("annot")], [h.text("Sequencer")]),
              h.output(
                [
                  a.class("seq-counter"),
                  a.attribute("data-seq-counter", ""),
                  a.attribute("aria-label", "Latest sequence number"),
                ],
                [h.text("SN " <> int.to_string(model.sequence_number))],
              ),
            ]),
            h.ol(
              [
                a.class("op-log"),
                a.attribute("data-op-log", ""),
                a.attribute("aria-live", "polite"),
                a.attribute("aria-label", "Sequenced operations, newest first"),
              ],
              list.map(model.log, fn(entry) { h.li([], [h.text(entry.label)]) }),
            ),
          ]),
          h.div(
            [
              a.class("flow-layer"),
              a.attribute("data-flow-layer", ""),
              a.attribute("aria-hidden", "true"),
            ],
            [],
          ),
        ],
      ),
      controls(model),
      h.p([a.class("controls-hint")], [
        h.span([], [
          h.text(
            "Jitter can change simulated arrival order; animation speed changes playback only. Each moving request shows its sampled hop latency. “Ops in flight” counts every hop still travelling: one client → sequencer leg, then one sequencer → replica leg per client.",
          ),
        ]),
      ]),
      case include_noscript {
        True ->
          h.noscript([], [
            h.p(
              [
                a.class("demo-noscript"),
                a.attribute("data-testid", "noscript"),
              ],
              [
                h.text(
                  "The live demo needs JavaScript: it runs watershed's actual ",
                ),
                h.code([], [h.text("mv_register_kernel")]),
                h.text(
                  " in your browser. The rest of the page works fine without it.",
                ),
              ],
            ),
          ])
        False -> h.text("")
      },
      h.p(
        [
          a.class("demo-noscript"),
          a.attribute("data-demo-fallback", ""),
          a.attribute("data-testid", case map {
            True -> "home-fallback"
            False -> "mv-register-fallback"
          }),
          a.hidden(True),
        ],
        [
          h.text(
            "The live demo couldn't start: it runs watershed's kernels as compiled JavaScript modules, and this browser didn't load them. The rest of the page works fine without it. ",
          ),
          h.a([a.href("")], [h.text("Reload the page to retry.")]),
        ],
      ),
    ],
  )
}

fn mounted_attribute(model: Model) -> List(a.Attribute(msg)) {
  case model.phase {
    Static -> []
    _ -> [a.attribute("data-mounted", "")]
  }
}

fn client(
  model: Model,
  replica: Replica,
  id: String,
  label: String,
  revision: String,
  family: Bool,
) -> Element(runtime.Msg) {
  h.article(
    [
      a.class("client"),
      a.attribute("data-client", id),
      a.attribute("aria-label", label <> " replica"),
      a.style("grid-area", id),
    ],
    [
      h.header([a.class("client-head")], [
        h.h3([], [h.text(label)]),
        case id {
          "b" ->
            h.button(
              [
                a.type_("button"),
                a.class("link-btn"),
                a.attribute("data-cut-link", ""),
                a.attribute("aria-pressed", "false"),
                a.title(
                  "Sever this replica's link to the sequencer; its edits park locally until the link is restored",
                ),
                event.on_click(runtime.ToggleLink),
              ],
              [h.text("Cut link")],
            )
          _ -> h.text("")
        },
        h.span(
          [
            a.class("pending-count annot"),
            a.attribute("data-pending-count", ""),
            a.attribute("data-live", id),
          ],
          [
            h.text(
              int.to_string(runtime.pending_count(model, replica)) <> " pending",
            ),
          ],
        ),
      ]),
      case id {
        "b" ->
          h.p(
            [
              a.class("annot link-note"),
              a.attribute("data-link-note", ""),
              a.hidden(model.link_up),
            ],
            [
              h.text("link cut — ops park locally until the link is restored"),
            ],
          )
        _ -> h.text("")
      },
      h.table(
        [
          a.class("gauge-table dds-map"),
          a.hidden(model.selected != Map),
        ],
        [
          h.caption([a.class("visually-hidden")], [
            h.text("Shared map replica on " <> label),
          ]),
          h.tbody([], [
            gauge(model, replica, "mill-race", "24", label),
            gauge(model, replica, "kettle-run", "61", label),
            gauge(model, replica, "low-ford", "42", label),
          ]),
        ],
      ),
      h.div(
        [
          a.class("mv-register-panel dds-mv-register"),
          a.hidden(model.selected != MvRegister),
        ],
        [
          h.h3([a.class("annot")], [h.text("Revision slate")]),
          h.p([a.class("annot")], [h.text("Confirmed alternatives")]),
          h.output(
            [
              a.class("mv-alternatives k-seq"),
              a.attribute("data-mv-register-confirmed", ""),
              a.attribute("aria-live", "polite"),
              a.attribute(
                "aria-label",
                "Confirmed MV register alternatives on " <> label,
              ),
            ],
            [h.text(mv_text(model, replica, True))],
          ),
          h.p([a.class("annot")], [h.text("Local view")]),
          h.output(
            [
              a.class("mv-alternatives"),
              a.attribute("data-mv-register-values", ""),
              a.attribute("aria-live", "polite"),
              a.attribute(
                "aria-label",
                "Local MV register alternatives on " <> label,
              ),
            ],
            [h.text(mv_text(model, replica, False))],
          ),
          h.label([a.class("annot"), a.attribute("for", "mv-revision-" <> id)], [
            h.text("Next revision"),
          ]),
          h.input([
            a.id("mv-revision-" <> id),
            a.attribute("data-mv-register-input", ""),
            a.value(revision),
          ]),
          h.div([a.class("mv-actions")], [
            h.button(
              [
                a.type_("button"),
                a.attribute("data-mv-register-write", ""),
                event.on_click(runtime.WriteMv(replica, revision)),
              ],
              [h.text("Write revision")],
            ),
            h.button(
              [
                a.type_("button"),
                a.attribute("data-mv-register-resolve", ""),
                event.on_click(runtime.ResolveMv(replica)),
              ],
              [h.text("Resolve with both")],
            ),
          ]),
          h.p([a.class("mv-hint")], [
            h.text(
              "Resolve writes \"raise crest + arm pump\". Any new revision replaces only the history this client has seen.",
            ),
          ]),
        ],
      ),
      ..case family {
        False -> [
          h.div([a.hidden(True)], [
            h.input([a.attribute("data-ormap-set-input", "")]),
            h.input([a.attribute("data-ormap-key", "")]),
            h.input([a.attribute("data-or-map-mv-register-key", "")]),
            h.input([a.attribute("data-or-map-mv-register-input", "")]),
            h.input([a.attribute("data-lww-map-key", "")]),
            h.input([a.attribute("data-lww-map-input", "")]),
            h.input([a.attribute("data-lww-register-input", "")]),
          ]),
        ]
        True -> family_panel(model, id, label, revision)
      }
    ],
  )
}

fn family_panel(
  model: Model,
  id: String,
  label: String,
  revision: String,
) -> List(Element(runtime.Msg)) {
  case runtime.structure_id(model.selected) {
    "counter" -> [counter_panel(label)]
    "pn" -> [pn_panel(label)]
    "gcounter" -> [gcounter_panel(label)]
    "lww-map" -> [lww_map_panel(id, label)]
    "lww-register" -> [lww_register_panel(id, label, revision)]
    "or-map-mv-register" -> [ormap_mv_register_panel(id, label, revision)]
    "claims" -> [claims_table(label)]
    "ormap" ->
      case model.or_map_set_mode {
        True -> [ormap_set_panel(id, label)]
        False -> [ormap_table(label)]
      }
    "orset" -> [set_table("orset", label)]
    "gset" -> [set_table("gset", label)]
    "twopset" -> [set_table("twopset", label)]
    "registers" -> [registers_table(label)]
    "ordered" -> [ordered_table(label)]
    "pact" -> [pact_table(label)]
    "tasks" -> [tasks_table(label)]
    _ -> []
  }
}

fn counter_panel(label: String) -> Element(msg) {
  h.div(
    [
      a.class("counter-panel dds-counter"),
      a.role("group"),
      a.attribute("aria-label", "Shared counter replica on " <> label),
    ],
    [
      h.code([a.class("counter-key")], [h.text("sandbags-placed")]),
      h.output(
        [a.class("counter-value"), a.attribute("data-counter-value", "")],
        [h.text("120")],
      ),
      h.span(
        [
          a.class("counter-delta annot"),
          a.attribute("data-counter-delta", ""),
          a.attribute("aria-label", "Pending unsequenced delta"),
        ],
        [],
      ),
      h.div(
        [a.class("counter-actions")],
        list.map([-5, -1, 1, 5], fn(step) {
          let amount = int_text(step)
          let absolute = case step {
            -5 -> "5"
            -1 -> "1"
            1 -> "1"
            _ -> "5"
          }
          h.button(
            [
              a.type_("button"),
              a.attribute("data-inc", amount),
              a.attribute("aria-label", case step > 0 {
                True -> "Add " <> amount <> " sandbags on " <> label
                False -> "Remove " <> absolute <> " sandbags on " <> label
              }),
              a.disabled(True),
            ],
            [
              h.text(case step > 0 {
                True -> "+" <> amount
                False -> "−" <> absolute
              }),
            ],
          )
        }),
      ),
    ],
  )
}

fn pn_panel(label: String) -> Element(msg) {
  h.div(
    [
      a.class("counter-panel dds-pn"),
      a.role("group"),
      a.attribute("aria-label", "PN counter replica on " <> label),
    ],
    [
      h.code([a.class("counter-key")], [h.text("earthwork-balance · yd³")]),
      h.output([a.class("counter-value"), a.attribute("data-pn-value", "")], [
        h.text("+44"),
      ]),
      h.span(
        [
          a.class("counter-delta annot"),
          a.attribute("data-pn-delta", ""),
          a.attribute("aria-label", "Pending unsequenced delta"),
        ],
        [],
      ),
      h.dl([a.class("pn-ledger")], [
        ledger_value("fill Σ", "data-pn-fill", "74"),
        ledger_value("cut Σ", "data-pn-cut", "30"),
      ]),
      h.div([a.class("counter-actions pn-actions")], [
        h.span([a.class("annot"), a.attribute("aria-hidden", "true")], [
          h.text("cut"),
        ]),
        increment_button("data-pn-inc", "-6", "−6", "Cut 6 cubic yards", label),
        increment_button("data-pn-inc", "-2", "−2", "Cut 2 cubic yards", label),
        increment_button("data-pn-inc", "2", "+2", "Fill 2 cubic yards", label),
        increment_button("data-pn-inc", "6", "+6", "Fill 6 cubic yards", label),
        h.span([a.class("annot"), a.attribute("aria-hidden", "true")], [
          h.text("fill"),
        ]),
      ]),
    ],
  )
}

fn gcounter_panel(label: String) -> Element(msg) {
  h.div(
    [
      a.class("counter-panel dds-gcounter"),
      a.role("group"),
      a.attribute("aria-label", "G-counter replica on " <> label),
    ],
    [
      h.code([a.class("counter-key")], [h.text("inspection-count")]),
      h.output(
        [a.class("counter-value"), a.attribute("data-gcounter-value", "")],
        [h.text("18")],
      ),
      h.span(
        [
          a.class("counter-delta annot"),
          a.attribute("data-gcounter-delta", ""),
          a.attribute("aria-label", "Pending unsequenced increment"),
        ],
        [],
      ),
      h.dl([a.class("pn-ledger gcounter-ledger")], [
        author_value("a"),
        author_value("b"),
        author_value("c"),
      ]),
      h.div([a.class("counter-actions")], [
        increment_button(
          "data-gcounter-inc",
          "1",
          "+1",
          "Add 1 inspection",
          label,
        ),
        increment_button(
          "data-gcounter-inc",
          "3",
          "+3",
          "Add 3 inspections",
          label,
        ),
        increment_button(
          "data-gcounter-inc",
          "7",
          "+7",
          "Add 7 inspections",
          label,
        ),
      ]),
    ],
  )
}

fn lww_map_panel(id: String, label: String) -> Element(msg) {
  h.div(
    [
      a.class("mv-register-panel dds-lww-map"),
      a.role("group"),
      a.attribute("aria-label", "LWW map replica on " <> label),
    ],
    [
      h.h3([a.class("annot")], [h.text("Gate settings")]),
      h.p([a.class("annot")], [h.text("Confirmed entries, sorted by key")]),
      h.output(
        [
          a.class("mv-alternatives k-seq"),
          a.attribute("data-lww-map-confirmed", ""),
          a.attribute("aria-live", "polite"),
        ],
        [h.text("[[\"gate-mode\",\"surveyed\"]]")],
      ),
      h.p([a.class("annot")], [h.text("Local view")]),
      h.output(
        [
          a.class("mv-alternatives"),
          a.attribute("data-lww-map-entries", ""),
          a.attribute("aria-live", "polite"),
        ],
        [h.text("[[\"gate-mode\",\"surveyed\"]]")],
      ),
      h.output(
        [
          a.class("mv-alternatives k-seq"),
          a.attribute("data-lww-map-metadata", ""),
          a.attribute("aria-live", "polite"),
        ],
        [
          h.text(
            "[{\"key\":\"gate-mode\",\"value\":\"surveyed\",\"timestamp\":100}]",
          ),
        ],
      ),
      h.label([a.class("annot"), a.attribute("for", "lww-map-key-" <> id)], [
        h.text("Key (string)"),
      ]),
      h.input([
        a.id("lww-map-key-" <> id),
        a.attribute("data-lww-map-key", ""),
        a.value("gate-mode"),
        a.disabled(True),
      ]),
      h.label([a.class("annot"), a.attribute("for", "lww-map-value-" <> id)], [
        h.text("Value (string)"),
      ]),
      h.input([
        a.id("lww-map-value-" <> id),
        a.attribute("data-lww-map-input", ""),
        a.value(case id {
          "b" -> "closed"
          _ -> "open"
        }),
        a.disabled(True),
      ]),
      h.div([a.class("mv-actions")], [
        action_button("data-lww-map-write", "Set string"),
        action_button("data-lww-map-remove", "Remove key"),
      ]),
    ],
  )
}

fn lww_register_panel(
  id: String,
  label: String,
  revision: String,
) -> Element(msg) {
  h.div(
    [
      a.class("mv-register-panel dds-lww-register"),
      a.role("group"),
      a.attribute("aria-label", "LWW register replica on " <> label),
    ],
    [
      h.h3([a.class("annot")], [h.text("Field note")]),
      h.p([a.class("annot")], [h.text("Confirmed value")]),
      h.output(
        [
          a.class("mv-alternatives k-seq"),
          a.attribute("data-lww-register-confirmed", ""),
          a.attribute("aria-live", "polite"),
        ],
        [h.text("Survey datum")],
      ),
      h.p([a.class("annot")], [h.text("Local view")]),
      h.output(
        [
          a.class("mv-alternatives"),
          a.attribute("data-lww-register-value", ""),
          a.attribute("aria-live", "polite"),
        ],
        [h.text("Survey datum")],
      ),
      h.output(
        [
          a.class("mv-hint"),
          a.attribute("data-lww-register-winner", ""),
          a.attribute("aria-live", "polite"),
        ],
        [h.text("timestamp 100 · survey-lww")],
      ),
      h.label([a.class("annot"), a.attribute("for", "lww-revision-" <> id)], [
        h.text("Next field note"),
      ]),
      h.input([
        a.id("lww-revision-" <> id),
        a.attribute("data-lww-register-input", ""),
        a.value(revision),
        a.disabled(True),
      ]),
      h.div([a.class("mv-actions")], [
        action_button("data-lww-register-write", "Write note"),
      ]),
    ],
  )
}

fn ormap_mv_register_panel(
  id: String,
  label: String,
  revision: String,
) -> Element(msg) {
  h.div(
    [
      a.class("mv-register-panel dds-or-map-mv-register"),
      a.role("group"),
      a.attribute("aria-label", "OR-map with MV registers on " <> label),
      a.attribute("data-or-map-mv-register-canonical-summary", ""),
    ],
    [
      h.h3([a.class("annot")], [h.text("Gate revisions")]),
      h.output(
        [
          a.class("mv-alternatives k-seq"),
          a.attribute("data-or-map-mv-register-confirmed", ""),
          a.attribute("aria-live", "polite"),
        ],
        [h.text("[[\"gate-mode\",[\"surveyed\"]]]")],
      ),
      h.output(
        [
          a.class("mv-alternatives"),
          a.attribute("data-or-map-mv-register-entries", ""),
          a.attribute("aria-live", "polite"),
        ],
        [h.text("[[\"gate-mode\",[\"surveyed\"]]]")],
      ),
      h.label([a.class("annot"), a.attribute("for", "or-map-mv-key-" <> id)], [
        h.text("Key (string)"),
      ]),
      h.input([
        a.id("or-map-mv-key-" <> id),
        a.attribute("data-or-map-mv-register-key", ""),
        a.value("gate-mode"),
        a.disabled(True),
      ]),
      h.label(
        [a.class("annot"), a.attribute("for", "or-map-mv-revision-" <> id)],
        [h.text("Next revision (string)")],
      ),
      h.input([
        a.id("or-map-mv-revision-" <> id),
        a.attribute("data-or-map-mv-register-input", ""),
        a.value(revision),
        a.disabled(True),
      ]),
      h.div([a.class("mv-actions")], [
        action_button("data-or-map-mv-register-write", "Write revision"),
        action_button("data-or-map-mv-register-resolve", "Resolve observed"),
        action_button("data-or-map-mv-register-remove", "Remove key"),
      ]),
    ],
  )
}

fn claims_table(label: String) -> Element(msg) {
  keyed_table(
    "claims-table dds-claims",
    "Claims replica on " <> label,
    ["north-levee", "spillway-gate", "pump-house"],
    fn(key) {
      h.tr([a.attribute("data-key", key)], [
        key_heading(key, "data-claim-note"),
        h.td([a.class("claim-holder")], [
          h.output([a.attribute("data-holder", "")], [
            h.text(case key {
              "pump-house" -> "Survey"
              _ -> "—"
            }),
          ]),
        ]),
        h.td([a.class("gauge-actions claim-actions")], [
          action_button("data-claim", "Claim"),
        ]),
      ])
    },
  )
}

fn ormap_table(label: String) -> Element(msg) {
  keyed_table(
    "ormap-table dds-ormap",
    "OR-map stockpile ledger replica on " <> label,
    ["spoil-north", "borrow-pit-7", "wash-fill"],
    fn(key) {
      h.tr([a.attribute("data-key", key)], [
        h.th([a.attribute("scope", "row")], [
          h.code([], [h.text(key)]),
        ]),
        h.td([a.class("gauge-value ormap-value")], [
          h.output([a.attribute("data-ormap-value", "")], [
            h.text(case key {
              "spoil-north" -> "18"
              "borrow-pit-7" -> "-6"
              _ -> "12"
            }),
          ]),
          h.span(
            [a.class("annot ormap-note"), a.attribute("data-ormap-note", "")],
            [],
          ),
        ]),
        h.td([a.class("gauge-actions ormap-actions")], [
          valued_button("data-ormap-log", "2", "+2"),
          valued_button("data-ormap-log", "6", "+6"),
          action_button("data-ormap-strike", "×"),
          action_button("data-ormap-reopen", "Re-open"),
        ]),
      ])
    },
  )
}

fn ormap_set_panel(id: String, label: String) -> Element(msg) {
  let documents = ["inspection-brief", "spillway-plan", "pump-watch"]
  h.div(
    [
      a.class("mv-register-panel ormap-set-panel dds-ormap"),
      a.role("group"),
      a.attribute("aria-label", "OR-map string set replica on " <> label),
    ],
    [
      h.h3([a.class("annot")], [h.text("Document checklist")]),
      h.dl(
        [a.class("ormap-members")],
        list.map(documents, fn(key) {
          h.div([a.attribute("data-ormap-set-row", key)], [
            h.dt([], [h.code([], [h.text(key)])]),
            h.dd([], [
              h.output(
                [
                  a.class("mv-alternatives k-seq"),
                  a.attribute("data-ormap-confirmed", ""),
                ],
                [h.text("missing")],
              ),
              h.output(
                [
                  a.class("mv-alternatives"),
                  a.attribute("data-ormap-members", ""),
                ],
                [h.text("missing")],
              ),
            ]),
          ])
        }),
      ),
      h.select(
        [
          a.id("ormap-key-" <> id),
          a.attribute("data-ormap-key", ""),
          a.disabled(True),
        ],
        list.map(documents, fn(key) { h.option([a.value(key)], key) }),
      ),
      h.input([
        a.id("ormap-member-" <> id),
        a.attribute("data-ormap-set-input", ""),
        a.value(case id {
          "a" -> "draft"
          "b" -> "reviewed"
          _ -> "handoff"
        }),
        a.disabled(True),
      ]),
      h.div([a.class("mv-actions")], [
        action_button("data-ormap-set-add", "Add member"),
        action_button("data-ormap-set-remove", "Remove member"),
        action_button("data-ormap-remove-key", "Remove key"),
      ]),
    ],
  )
}

fn set_table(kind: String, label: String) -> Element(msg) {
  let #(name, keys, values) = case kind {
    "orset" -> #(
      "OR-set field marker roster",
      ["north-stake", "sluice-tag", "borrow-flag"],
      ["marked", "marked", "clear"],
    )
    "gset" -> #(
      "G-set permanent benchmark registry",
      ["BM-17", "BM-22", "BM-31"],
      ["recorded", "unrecorded", "unrecorded"],
    )
    _ -> #(
      "2P-set retired marker ledger",
      ["stake-3", "gate-pin", "silt-flag"],
      ["active", "unplaced", "retired"],
    )
  }
  keyed_table(
    kind <> "-table dds-" <> kind,
    name <> " replica on " <> label,
    list.zip(keys, values),
    fn(item) {
      h.tr([a.attribute("data-key", item.0)], [
        key_heading(item.0, "data-" <> kind <> "-note"),
        h.td([a.class("gauge-value " <> kind <> "-value")], [
          h.output([a.attribute("data-" <> kind <> "-value", "")], [
            h.text(item.1),
          ]),
        ]),
        h.td([a.class("gauge-actions " <> kind <> "-actions")], case kind {
          "gset" -> [action_button("data-gset-add", "Record")]
          "orset" -> [
            action_button("data-orset-add", "Mark"),
            action_button("data-orset-remove", "Clear"),
          ]
          _ -> [
            action_button("data-twopset-add", "Place"),
            action_button("data-twopset-remove", "Retire"),
          ]
        }),
      ])
    },
  )
}

fn registers_table(label: String) -> Element(msg) {
  keyed_table(
    "register-table dds-registers",
    "RegisterCollection replica on " <> label,
    ["north-bench", "gate-setpoint", "pump-mode"],
    fn(key) {
      h.tr([a.attribute("data-key", key)], [
        key_heading(key, "data-register-note"),
        h.td([a.class("register-value")], [
          h.output([a.attribute("data-register-atomic", "")], [
            h.text(case key {
              "north-bench" -> "Survey"
              _ -> "—"
            }),
          ]),
        ]),
        h.td([a.class("register-value")], [
          h.output([a.attribute("data-register-lww", "")], [
            h.text(case key {
              "north-bench" -> "Survey"
              _ -> "—"
            }),
          ]),
          h.span(
            [
              a.class("annot register-versions"),
              a.attribute("data-register-versions", ""),
            ],
            [],
          ),
        ]),
        h.td([a.class("gauge-actions register-actions")], [
          action_button("data-register-write", "Revise"),
        ]),
      ])
    },
  )
}

fn ordered_table(label: String) -> Element(msg) {
  h.table(
    [
      a.class("gauge-table ordered-table dds-ordered"),
      a.attribute("aria-label", "OrderedCollection replica on " <> label),
    ],
    [
      h.tbody([], [
        h.tr([], [
          key_heading("queue", "data-ordered-note"),
          h.td([a.class("ordered-value")], [
            h.output([a.attribute("data-ordered-queue", "")], [
              h.text("grade-stakes, pump-check"),
            ]),
          ]),
          h.td([a.class("gauge-actions ordered-actions")], [
            action_button("data-ordered-add", "Add task"),
            action_button("data-ordered-acquire", "Acquire"),
          ]),
        ]),
        h.tr([], [
          h.th([a.attribute("scope", "row")], [
            h.code([], [h.text("held jobs")]),
          ]),
          h.td([a.class("ordered-value")], [
            h.output([a.attribute("data-ordered-jobs", "")], [h.text("none")]),
          ]),
          h.td([a.class("gauge-actions ordered-actions")], [
            action_button("data-ordered-complete", "Complete"),
            action_button("data-ordered-release", "Release"),
          ]),
        ]),
      ]),
    ],
  )
}

fn pact_table(label: String) -> Element(msg) {
  keyed_table(
    "pact-table dds-pact",
    "PactMap replica on " <> label,
    ["datum-grid", "gate-policy", "inspection-window"],
    fn(key) {
      h.tr([a.attribute("data-key", key)], [
        key_heading(key, "data-pact-note"),
        h.td([a.class("pact-value")], [
          h.output([a.attribute("data-pact-accepted", "")], [
            h.text(case key {
              "datum-grid" -> "Survey datum"
              _ -> "—"
            }),
          ]),
        ]),
        h.td([a.class("pact-value")], [
          h.output([a.attribute("data-pact-pending", "")], [h.text("—")]),
          h.span(
            [
              a.class("annot pact-signoffs"),
              a.attribute("data-pact-signoffs", ""),
            ],
            [],
          ),
        ]),
        h.td([a.class("gauge-actions pact-actions")], [
          action_button("data-pact-set", "Propose"),
          action_button("data-pact-delete", "Delete"),
        ]),
      ])
    },
  )
}

fn tasks_table(label: String) -> Element(msg) {
  keyed_table(
    "task-table dds-tasks",
    "TaskManager replica on " <> label,
    ["sluice-inspection", "pump-watch", "crest-walk"],
    fn(key) {
      h.tr([a.attribute("data-key", key)], [
        key_heading(key, "data-task-note"),
        h.td([a.class("task-value")], [
          h.output([a.attribute("data-task-assignee", "")], [h.text("—")]),
        ]),
        h.td([a.class("task-value")], [
          h.output([a.attribute("data-task-waiters", "")], [h.text("empty")]),
        ]),
        h.td([a.class("gauge-actions task-actions")], [
          action_button("data-task-volunteer", "Volunteer"),
          action_button("data-task-abandon", "Abandon"),
          action_button("data-task-complete", "Complete"),
        ]),
      ])
    },
  )
}

fn keyed_table(
  class: String,
  caption: String,
  items: List(item),
  row: fn(item) -> Element(msg),
) -> Element(msg) {
  h.table([a.class("gauge-table " <> class)], [
    h.caption([a.class("visually-hidden")], [h.text(caption)]),
    h.tbody([], list.map(items, row)),
  ])
}

fn key_heading(key: String, note_attribute: String) -> Element(msg) {
  h.th([a.attribute("scope", "row")], [
    h.code([], [h.text(key)]),
    h.span([a.class("annot"), a.attribute(note_attribute, "")], []),
  ])
}

fn ledger_value(
  label: String,
  attribute: String,
  value: String,
) -> Element(msg) {
  h.div([], [
    h.dt([a.class("annot")], [h.text(label)]),
    h.dd([a.attribute(attribute, "")], [h.text(value)]),
  ])
}

fn author_value(id: String) -> Element(msg) {
  h.div([], [
    h.dt([a.class("annot")], [h.text(string.uppercase(id) <> " Σ")]),
    h.dd([a.attribute("data-gcounter-author", id)], [h.text("0")]),
  ])
}

fn increment_button(
  attribute: String,
  value: String,
  text: String,
  label: String,
  client: String,
) -> Element(msg) {
  h.button(
    [
      a.type_("button"),
      a.attribute(attribute, value),
      a.attribute("aria-label", label <> " on " <> client),
      a.disabled(True),
    ],
    [h.text(text)],
  )
}

fn valued_button(
  attribute: String,
  value: String,
  text: String,
) -> Element(msg) {
  h.button(
    [
      a.type_("button"),
      a.attribute(attribute, value),
      a.disabled(True),
    ],
    [h.text(text)],
  )
}

fn action_button(attribute: String, text: String) -> Element(msg) {
  h.button([a.type_("button"), a.attribute(attribute, ""), a.disabled(True)], [
    h.text(text),
  ])
}

fn int_text(value: Int) -> String {
  case value {
    -5 -> "-5"
    -1 -> "-1"
    1 -> "1"
    _ -> "5"
  }
}

fn gauge(
  model: Model,
  replica: Replica,
  key: String,
  fallback: String,
  label: String,
) -> Element(runtime.Msg) {
  let value = case model.selected {
    Map -> int.to_string(runtime.map_value_for(model, replica, key))
    _ -> fallback
  }
  h.tr([a.attribute("data-key", key)], [
    h.th([a.attribute("scope", "row")], [h.code([], [h.text(key)])]),
    h.td([a.class("gauge-value"), a.attribute("data-value", "")], [
      h.text(value),
    ]),
    h.td([a.class("gauge-actions")], [
      h.button(
        [
          a.type_("button"),
          a.attribute("data-step", "-1"),
          a.attribute("aria-label", "Lower " <> key <> " on " <> label),
          event.on_click(runtime.StepMap(replica, key, -1)),
        ],
        [h.text("−")],
      ),
      h.button(
        [
          a.type_("button"),
          a.attribute("data-step", "1"),
          a.attribute("aria-label", "Raise " <> key <> " on " <> label),
          event.on_click(runtime.StepMap(replica, key, 1)),
        ],
        [h.text("+")],
      ),
    ]),
  ])
}

fn controls(model: Model) -> Element(runtime.Msg) {
  h.div([a.class("demo-controls")], [
    h.label([a.class("pace")], [
      h.span([a.class("annot")], [h.text("Animation speed")]),
      h.input([
        a.type_("range"),
        a.min("0.25"),
        a.max("2"),
        a.step("0.25"),
        a.value("1"),
        a.attribute("data-pace", ""),
        a.title("Playback only; does not affect simulated ordering."),
        event.on_input(runtime.SetLatency),
      ]),
      h.output([a.attribute("data-pace-out", "")], [h.text("1×")]),
    ]),
    h.label([a.class("field-notes-toggle")], [
      h.input([
        a.type_("checkbox"),
        a.attribute("data-latency-variance", ""),
        a.title("Add random ±100 ms per hop; arrival order may change."),
        event.on_check(runtime.SetJitter),
      ]),
      h.span([a.class("annot")], [h.text("Jitter ±100 ms")]),
    ]),
    h.button(
      [
        a.type_("button"),
        a.class("race-btn"),
        a.attribute("data-race", ""),
        event.on_click(runtime.RunRace),
      ],
      [
        h.text(case model.selected {
          MvRegister -> "Race two revisions"
          _ -> "Race a concurrent write"
        }),
      ],
    ),
    h.button(
      [
        a.type_("button"),
        a.class("race-btn"),
        a.attribute("data-replay", ""),
        a.attribute(
          "aria-label",
          "Deliver the most recently sequenced delta a second time to every replica",
        ),
        a.hidden(model.selected != MvRegister),
        event.on_click(runtime.Replay),
      ],
      [h.text("Re-deliver last delta")],
    ),
    h.button(
      [
        a.type_("button"),
        a.class("reset-btn"),
        a.attribute("data-reset", ""),
        a.attribute(
          "aria-label",
          "Reset all revisions to their surveyed baseline values",
        ),
        event.on_click(runtime.Reset),
      ],
      [h.text("Reset survey")],
    ),
    h.p(
      [
        a.class("status"),
        a.attribute("data-status", ""),
        a.attribute("role", "status"),
      ],
      [
        h.span([a.class(status_class(model))], [h.text(status_label(model))]),
        h.text(status_detail(model)),
      ],
    ),
  ])
}

fn mv_text(model: Model, replica: Replica, sequenced: Bool) -> String {
  case model.selected {
    MvRegister ->
      case sequenced {
        True -> string.inspect(runtime.mv_sequenced_values(model, replica))
        False -> string.inspect(runtime.mv_values(model, replica))
      }
    _ -> "[\"Survey datum\"]"
  }
}

fn status_class(model: Model) -> String {
  case model.link_up, model.phase {
    False, _ -> "stamp revising"
    _, Ready -> "stamp converged"
    _, Failed -> "stamp revising"
    _, _ -> "stamp revising"
  }
}

fn status_label(model: Model) -> String {
  case model.link_up, model.phase {
    False, _ -> "Link cut"
    _, Ready -> "Converged"
    _, Failed -> "Offline"
    _, _ -> "Revising"
  }
}

fn status_detail(model: Model) -> String {
  case model.link_up, model.phase {
    False, _ ->
      " Client B off the wire · "
      <> int.to_string(model.queued_for_b)
      <> " queued"
    _, Ready -> " replicas identical · nothing pending"
    _, Failed -> " kernels did not load, see below"
    _, _ -> " " <> int.to_string(list.length(model.pending)) <> " ops in flight"
  }
}
