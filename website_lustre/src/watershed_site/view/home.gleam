import gleam/int
import gleam/list
import gleam/option
import lustre/attribute as a
import lustre/element.{type Element, element, fragment, map}
import lustre/element/html as h
import lustre/event
import watershed/map_kernel
import watershed_site/structure_demo/model
import watershed_site/structure_demo/runtime
import watershed_site/structure_demo/view as demo
import watershed_site/view/ecosystem
import watershed_site/view/sheet

pub type GaugeValue {
  GaugeValue(key: String, value: String, pending: Bool)
}

pub type GaugeClient {
  GaugeClient(id: String, values: List(GaugeValue))
}

pub type GaugeStrip {
  GaugeStrip(clients: List(GaugeClient))
}

pub fn view(body: List(Element(Nil))) -> Element(Nil) {
  sheet.view("/", [
    hero(),
    h.main([], [
      home_demo(),
      dds_sections(),
      atlas(),
      architecture(),
      code_sample(body),
      rigor(),
    ]),
    ecosystem.view("/"),
  ])
}

pub fn gauge_strip_model(demo: model.Model) -> GaugeStrip {
  GaugeStrip([
    gauge_client(demo, model.ClientA, "a"),
    gauge_client(demo, model.ClientB, "b"),
    gauge_client(demo, model.ClientC, "c"),
  ])
}

fn gauge_client(
  demo: model.Model,
  replica: model.Replica,
  id: String,
) -> GaugeClient {
  GaugeClient(id:, values: [
    gauge_value(demo, replica, "mill-race"),
    gauge_value(demo, replica, "kettle-run"),
    gauge_value(demo, replica, "low-ford"),
  ])
}

fn gauge_value(
  demo: model.Model,
  replica: model.Replica,
  key: String,
) -> GaugeValue {
  GaugeValue(
    key:,
    value: runtime.map_value_for(demo, replica, key) |> int.to_string,
    pending: map_key_pending(demo, replica, key),
  )
}

fn map_key_pending(
  demo: model.Model,
  replica: model.Replica,
  key: String,
) -> Bool {
  let state = case replica {
    model.ClientA -> demo.alpha
    model.ClientB -> demo.beta
    model.ClientC -> demo.gamma
  }
  case state {
    model.MapReplica(state) ->
      list.any(state.pending, fn(entry) {
        case entry {
          map_kernel.PendingLifetime(pending_key, _)
          | map_kernel.PendingDelete(pending_key) -> pending_key == key
          map_kernel.PendingClear -> True
        }
      })
    _ -> False
  }
}

fn hero() -> Element(Nil) {
  h.header([a.class("hero"), a.attribute("data-hero", "")], [
    contours(),
    h.div([a.class("hero-inner")], [
      h.h1([], [
        h.text("Edit upstream."),
        h.br([]),
        h.text("Converge "),
        h.em([], [h.text("downstream.")]),
      ]),
      h.p([a.class("lede")], [
        h.text(
          "watershed lets people edit shared data without losing concurrent changes. Clients apply edits at once; the server sequences them; each data structure resolves conflicts under its stated policy. The same Gleam core runs on the BEAM and in the browser, on a distributed-data-structure (DDS) runtime and sequencer drawn from Fluid Framework's design.",
        ),
      ]),
      h.div([a.class("cta-row")], [
        h.a(
          [
            a.class("cta-primary"),
            a.href("https://github.com/tylerbutler/watershed"),
          ],
          [h.text("View on GitHub")],
        ),
        h.a([a.class("cta-quiet"), a.href("#demo")], [
          h.text("Watch three clients converge ↓"),
        ]),
      ]),
    ]),
  ])
}

fn contours() -> Element(Nil) {
  element(
    "svg",
    [
      a.class("contours"),
      a.attribute("data-contour-field", ""),
      a.attribute("viewBox", "0 0 1300 860"),
      a.attribute("preserveAspectRatio", "xMaxYMid slice"),
      a.attribute("aria-hidden", "true"),
    ],
    [
      contour("0", "contour"),
      contour("1", "contour index"),
      contour("2", "contour"),
      contour("3", "contour"),
      contour("4", "contour"),
      contour("5", "contour index"),
      contour("6", "contour"),
      contour("7", "contour"),
      contour("8", "contour"),
      contour("9", "contour index"),
      contour("10", "contour"),
      contour("11", "contour"),
      contour("12", "contour"),
      label("contour-1", "SN 1220"),
      label("contour-5", "SN 1140"),
      label("contour-9", "SN 1060"),
    ],
  )
}

fn contour(index: String, class: String) -> Element(Nil) {
  let path = case index {
    "0" -> "M -40 60 C 300 25, 900 95, 1340 55"
    "1" -> "M -40 115 C 300 75, 900 150, 1340 120"
    "2" -> "M -40 170 C 300 130, 900 205, 1340 180"
    "3" -> "M -40 225 C 300 190, 900 265, 1340 245"
    "4" -> "M -40 285 C 300 240, 900 330, 1340 310"
    "5" -> "M -40 345 C 300 300, 900 395, 1340 375"
    "6" -> "M -40 405 C 300 365, 900 455, 1340 440"
    "7" -> "M -40 465 C 300 425, 900 520, 1340 505"
    "8" -> "M -40 525 C 300 485, 900 580, 1340 570"
    "9" -> "M -40 590 C 300 545, 900 645, 1340 635"
    "10" -> "M -40 655 C 300 610, 900 710, 1340 700"
    "11" -> "M -40 720 C 300 675, 900 775, 1340 765"
    _ -> "M -40 785 C 300 740, 900 835, 1340 830"
  }
  element(
    "path",
    [
      a.id("contour-" <> index),
      a.class(class),
      a.attribute("d", path),
      a.style("--i", index),
    ],
    [],
  )
}

fn label(path: String, text: String) -> Element(Nil) {
  element("text", [a.class("contour-label")], [
    element(
      "textPath",
      [a.attribute("href", "#" <> path), a.attribute("startOffset", "70%")],
      [h.text(text)],
    ),
  ])
}

fn home_demo() -> Element(Nil) {
  let model = runtime.static_model(model.Map)
  h.div([a.id("home-demo-mount")], [
    demo(model, gauge_strip_model(model)),
  ])
  |> map(fn(_) { Nil })
}

pub fn demo(
  model: model.Model,
  gauge_strip: GaugeStrip,
) -> Element(runtime.Msg) {
  fragment([
    demo.view(model, demo.Options(True, ["map"], option.None)),
    h.p([a.class("map-comparison")], [
      h.a([a.href("/structures/maps#map")], [
        h.text("SharedMap's server order"),
      ]),
    ]),
    h.aside([a.class("demo-bug-teaser")], [
      h.p([], [
        h.strong([], [
          h.text(
            "Seen enough of “most recent write wins”? It has a famous failure mode.",
          ),
        ]),
        gauge_strip_view(gauge_strip),
        h.text(
          " Store a counter in this map and have two people add to it at once: their increments silently overwrite each other instead of adding up.",
        ),
      ]),
      h.a([a.href("/counter-bug")], [h.text("Watch a boat vanish, live →")]),
    ]),
    h.p([a.class("demo-outro-hint")], [
      h.text(
        "Every other structure runs the same way on its own page. Start with the ",
      ),
      h.a([a.href("/structures")], [h.text("field atlas")]),
      h.text(", the full catalog →"),
    ]),
  ])
}

fn gauge_strip_view(gauge_strip: GaugeStrip) -> Element(runtime.Msg) {
  let GaugeStrip(clients) = gauge_strip
  h.div([a.class("gauge-strip"), a.attribute("data-gauge-strip", "")], [
    h.div(
      [
        a.class("strip-values"),
        a.attribute("aria-hidden", "true"),
      ],
      list.map(clients, strip_client),
    ),
    h.button(
      [
        a.type_("button"),
        a.class("race-btn strip-race"),
        a.attribute("data-strip-race", ""),
        event.on_click(runtime.Defer(runtime.RunRace)),
      ],
      [h.text("Race a concurrent write")],
    ),
  ])
}

fn strip_client(client: GaugeClient) -> Element(runtime.Msg) {
  let GaugeClient(id, values) = client
  h.div([a.class("strip-client"), a.attribute("data-strip-client", id)], [
    h.span([a.class("strip-id annot")], [h.text(id)]),
    ..list.map(values, strip_value)
  ])
}

fn strip_value(value: GaugeValue) -> Element(runtime.Msg) {
  let GaugeValue(key, text, pending) = value
  h.span(
    [
      a.class(case pending {
        True -> "strip-val pending"
        False -> "strip-val"
      }),
      a.attribute("data-strip-key", key),
    ],
    [
      h.text(text),
    ],
  )
}

fn dds_sections() -> Element(Nil) {
  fragment([
    h.section([a.class("dds-field"), a.id("after-demo")], [
      h.div([a.class("dds-inner")], [
        h.div([a.class("dds-copy")], [
          h.h2([a.id("dds-field-title")], [
            h.text("One ordered stream, one clear rule per structure"),
          ]),
          h.p([], [
            h.text(
              "watershed doesn't paper over conflicts with one catch-all merge. Each structure states a small, clear rule: what can show up instantly, what has to wait for the server to confirm it, and what gets saved so a client can reload later.",
            ),
          ]),
          h.p([a.class("dds-atlas-note")], [
            h.text(
              "Only a few of watershed's structures are shown here. Find the rest, grouped by family, in ",
            ),
            h.a([a.href("/structures")], [h.text("the field atlas")]),
            h.text(
              ". The full catalog includes a live demo for each structure.",
            ),
          ]),
          h.nav(
            [
              a.class("family-nav"),
              a.attribute("aria-label", "Convergence models compared"),
            ],
            [
              h.a([a.href("/models")], [h.text("DDS vs CRDT vs OT →")]),
            ],
          ),
        ]),
        featured_structures(),
      ]),
    ]),
    h.section([a.class("dds-flow")], [
      h.div([a.class("flow-inner")], [
        h.h2([], [h.text("Every structure uses the same channel")]),
        h.p([], [
          h.text(
            "Every structure above rides the same ordered stream of changes, the very one the live SharedMap demo runs on. Open any family to switch which structure is on screen; they all stay hosted together as channels sharing one sequenced document.",
          ),
        ]),
        h.ol([a.class("flow-steps")], [
          flow(
            "01",
            "Submit",
            "A client makes a change and updates just its own local copy for now.",
          ),
          flow(
            "02",
            "Sequence",
            "A server like floodgate puts everyone's changes in one order and sends that order to every client.",
          ),
          flow(
            "03",
            "Confirm / apply",
            "The client that made the change locks it in; everyone else applies it through the exact same code.",
          ),
          flow(
            "04",
            "Summarize",
            "A saved snapshot lets any client reload the current state, the same path used after a reconnect.",
          ),
        ]),
      ]),
    ]),
  ])
}

fn flow(number: String, title: String, copy: String) -> Element(Nil) {
  h.li([], [
    h.span([a.class("flow-step annot")], [h.text(number)]),
    h.div([a.class("flow-step-body")], [
      h.h3([], [h.text(title)]),
      h.p([], [h.text(copy)]),
    ]),
  ])
}

fn featured_structures() -> Element(Nil) {
  h.div([a.class("sheet-stack")], [
    featured(
      "SharedMap",
      "map_kernel",
      "for each key, the most recent write wins, decided by server order",
      "your writes show instantly, then lock in once the server confirms them",
      "confirmed entries reload with their keys and insertion order intact",
      "/structures/maps#map",
    ),
    featured(
      "SharedCounter",
      "counter_kernel",
      "everyone sends +/− changes instead of overwriting, so simultaneous edits just add up",
      "your change shows next to the confirmed total right away",
      "only one number needs saving, since every change is an add",
      "/structures/counters#counter",
    ),
    featured(
      "OrSet",
      "or_set_kernel",
      "add, remove, and add again all work; if an add and a remove race, the add wins",
      "your change overlays the list in magenta until it's confirmed",
      "current members and their removal history reload intact",
      "/structures/sets#or-set",
    ),
    featured(
      "Claims",
      "claims_kernel",
      "the first client to claim a slot owns it; every later claim is refused",
      "a claim only shows as yours once it has actually won, never before",
      "who owns what reloads intact",
      "/structures/coordination#claims",
    ),
  ])
}

fn featured(
  name: String,
  module: String,
  rule: String,
  optimistic: String,
  summary: String,
  href: String,
) -> Element(Nil) {
  h.article([a.class("field-sheet")], [
    h.header([], [
      h.h3([], [h.text(name)]),
      h.code([], [h.text(module)]),
    ]),
    h.dl([], [
      detail("Merge rule", rule),
      detail("Before it's confirmed", optimistic),
      detail("What gets saved", summary),
    ]),
    h.a([a.class("field-detail annot"), a.href(href)], [
      h.text("Read in depth →"),
    ]),
  ])
}

fn detail(term: String, definition: String) -> Element(Nil) {
  h.div([], [
    h.dt([], [h.text(term)]),
    h.dd([], [h.text(definition)]),
  ])
}

fn atlas() -> Element(Nil) {
  h.section([a.class("atlas-cta")], [
    h.div([a.class("atlas-inner")], [
      h.div([a.class("atlas-head")], [
        h.h2([], [
          h.text("Every structure, "),
          h.br([]),
          h.em([], [h.text("mapped by family.")]),
        ]),
        h.p([a.class("atlas-lede")], [
          h.text(
            "The demo above runs one kernel. The atlas is the whole field guide: every structure watershed ships, grouped by how it converges, each with its own live demo and merge rule.",
          ),
        ]),
        h.a([a.class("cta-primary"), a.href("/structures")], [
          h.text("Open the field atlas →"),
        ]),
      ]),
      family_links(),
    ]),
  ])
}

fn architecture() -> Element(Nil) {
  h.section([a.class("arch")], [
    h.div([a.class("arch-inner")], [
      h.h2([], [h.text("One pure core, two runtimes")]),
      h.p([a.class("arch-intro")], [
        h.text(
          "watershed is written once and runs in two places. runtime_core, channel, wire, and the kernels compile for both targets. Erlang and JavaScript keep separate facades, runtimes, and socket bindings only where the platform forces them to differ.",
        ),
      ]),
      h.div(
        [
          a.class("strata"),
          a.attribute("role", "img"),
          a.attribute(
            "aria-label",
            "Cross-section of the watershed architecture: target-specific public APIs, runtimes, and transports over a shared pure core.",
          ),
        ],
        [
          stratum(
            "Facade: watershed_beam",
            "Erlang-only API: blocking connect, OTP subject calls, handles, summaries, and subscriptions.",
            "Facade: watershed",
            "JavaScript-only API: immediate document handle, on_ready callback, promises, and the same DDS verbs.",
          ),
          stratum(
            "Runtime: runtime_beam",
            "OTP actor, receiver process, process calls, heartbeat timer, and reconnect orchestration.",
            "Runtime: runtime",
            "Callback-driven shell over a mutable cell; same bootstrap, ordering, catch-up, and resubmit discipline.",
          ),
          h.div([a.class("stratum span bedrock")], [
            h.h3([], [h.text("Shared pure core")]),
            h.p([], [
              h.text(
                "runtime_core owns CSN/RSN, ack matching, gap detection, detached attach, and resubmit. channel dispatches the kernels hosted by the document runtime. wire encodes the same operation and sequencing payloads on both targets.",
              ),
            ]),
          ]),
          stratum(
            "Transport: aquamarine",
            "Phoenix channel client over Gun, gated to Erlang.",
            "Transport: transport_js",
            "Phoenix.js FFI, socket callbacks, mutable cell helpers, and browser Web Crypto dev-token signing.",
          ),
        ],
      ),
    ]),
  ])
}

fn stratum(
  left_title: String,
  left_copy: String,
  right_title: String,
  right_copy: String,
) -> Element(Nil) {
  h.div([a.class("stratum split")], [
    h.div([], [
      h.h3([], [h.text(left_title)]),
      h.p([], [h.text(left_copy)]),
    ]),
    h.div([], [
      h.h3([], [h.text(right_title)]),
      h.p([], [h.text(right_copy)]),
    ]),
  ])
}

fn code_sample(body: List(Element(Nil))) -> Element(Nil) {
  h.section([a.class("code-sample")], [
    h.div([a.class("code-inner")], [
      h.div([a.class("code-prose")], [
        h.h2([], [h.text("A map over one sequenced stream")]),
        h.p([], [
          h.text(
            "connect hands back a document, root hands back its SharedMap, and subscribe hands back a stream of changes to select on. No merge callback appears because the server sequences every write and the highest-sequenced write wins per key.",
          ),
        ]),
        h.p([], [
          h.text(
            "The same core runs on the Erlang target and JavaScript target. See ",
          ),
          h.a(
            [
              a.href(
                "https://github.com/tylerbutler/watershed/tree/main/examples",
              ),
            ],
            [h.text("the examples")],
          ),
          h.text(" for both."),
        ]),
        h.a([a.href("/guide")], [
          h.text("Build an app, step by step: the field guide →"),
        ]),
      ]),
      h.div([a.class("code-figure")], body),
    ]),
  ])
}

fn rigor() -> Element(Nil) {
  h.section([a.class("rigor")], [
    h.div([a.class("rigor-inner")], [
      h.div([a.class("guarantees")], [
        h.h2([], [h.text("What is implemented and tested")]),
        h.p([], [
          h.text(
            "The runtime is tested three ways: against reference models, against a live floodgate server, and against deliberately nasty orderings of operations — over a thousand test functions across more than a hundred test files.",
          ),
        ]),
        h.dl([a.class("claims")], [
          claim(
            "Property-tested convergence",
            "Eleven reference models replay randomized multi-client command traces.",
            "test/watershed/fuzz",
            "Read the harness →",
          ),
          claim(
            "Reference-checked map ops",
            "SharedMap set, delete, and clear payloads are checked against reference scenarios.",
            "test/fixtures/corpus",
            "Read the corpus →",
          ),
          claim(
            "Reconnect safety",
            "Buffered delivery, catch-up, client-id remapping, and pending resubmit are tested.",
            "test/watershed/fuzz/disconnect_test.gleam",
            "Read the disconnect suite →",
          ),
        ]),
      ]),
      h.table([a.class("ledger")], [
        h.tbody([], [
          ledger("01", "Maps"),
          ledger("02", "Counters and sets"),
          ledger("03", "Sequences and text"),
          ledger("04", "Transforms"),
          ledger("05", "Coordination"),
          ledger("06", "Runtime"),
          ledger("07", "App layer"),
        ]),
      ]),
    ]),
  ])
}

fn claim(
  title: String,
  copy: String,
  path: String,
  label: String,
) -> Element(Nil) {
  h.div([], [
    h.dt([], [h.text(title)]),
    h.dd([], [
      h.text(copy <> " "),
      source_link(path, label),
    ]),
  ])
}

fn ledger(number: String, name: String) -> Element(Nil) {
  h.tr([], [
    h.th([], [h.text(number)]),
    h.td([], [
      h.span([a.class("ledger-name")], [h.text(name)]),
    ]),
  ])
}

fn family_links() -> Element(Nil) {
  h.div([a.class("atlas-grid")], [
    family(
      "/structures/counters",
      "Counters",
      "Numbers that many hands move at once.",
      "SharedCounter DDS GCounter CRDT PnCounter CRDT",
    ),
    family(
      "/structures/sets",
      "Sets",
      "Lists of things, as people add and remove at the same time.",
      "GSet CRDT TwoPSet CRDT OrSet CRDT",
    ),
    family(
      "/structures/registers",
      "Registers",
      "One shared value, and three different answers to a race.",
      "LWWRegister CRDT MvRegister CRDT RegisterCollection DDS",
    ),
    family(
      "/structures/maps",
      "Maps",
      "Keyed state that picks a winner, keeps an edit, or grows into a tree.",
      "SharedMap DDS LWWMap CRDT OrMap CRDT SharedDirectory DDS",
    ),
    family(
      "/structures/sequences",
      "Sequences",
      "Ordered lists that stay ordered while everyone rearranges them.",
      "SharedSequence CRDT SharedText CRDT",
    ),
    family(
      "/structures/coordination",
      "Coordination",
      "Deciding who owns what, and agreeing before acting.",
      "Claims DDS OrderedCollection DDS TaskManager DDS PactMap DDS",
    ),
    family(
      "/structures/transforms",
      "Transforms",
      "One shared document, kept in agreement as everyone edits.",
      "JsonOt OT SharedRichText OT",
    ),
  ])
}

fn family(href: String, name: String, tagline: String, structures: String) {
  h.a([a.class("atlas-family"), a.href(href)], [
    h.h3([], [h.text(name)]),
    h.p([], [h.text(tagline)]),
    h.p([], [h.text(structures)]),
    h.span([a.class("atlas-family-go annot")], [h.text("Open family →")]),
  ])
}

fn source_link(path: String, label: String) -> Element(Nil) {
  h.a(
    [
      a.class("claim-source annot"),
      a.href("https://github.com/tylerbutler/watershed/tree/main/" <> path),
    ],
    [h.text(label)],
  )
}
