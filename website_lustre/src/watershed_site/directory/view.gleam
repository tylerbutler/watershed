import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import lustre/attribute as a
import lustre/element.{type Element}
import lustre/element/html as h
import lustre/element/keyed
import lustre/event
import watershed_site/directory/runtime as directory

pub type Options {
  Options(include_noscript: Bool)
}

pub fn static() -> Element(Nil) {
  view(directory.static_model(), Options(True))
  |> element.map(fn(_) { Nil })
}

pub fn view(
  model: directory.Model,
  options: Options,
) -> Element(directory.Msg) {
  let unavailable =
    model.phase == directory.Static
    || model.phase == directory.Starting
    || model.phase == directory.Failed
  h.section(
    [
      a.id("dir-demo"),
      a.class("demo"),
      a.attribute("aria-labelledby", "dir-demo-title"),
      test_id("directory-demo"),
    ],
    [
      h.div([a.class("demo-head"), a.attribute("data-reveal", "rise")], [
        h.h2([a.id("dir-demo-title")], [h.text("A shared folder tree, live")]),
        h.p([], [
          h.text("Three "),
          h.code([], [h.text("watershed")]),
          h.text(" documents share one "),
          h.code([], [h.text("SharedDirectory")]),
          h.text(", a recursive "),
          h.code([], [h.text("SharedMap")]),
          h.text(
            " where every folder holds its own key/value readings and a set of named child folders. One client creates it and shares the handle; the others resolve it. They talk to one ",
          ),
          h.code([], [h.text("sluice")]),
          h.text(
            ", the in-memory server that ships in the library. It runs the production client runtime without a network backend. Local edits are drawn in ",
          ),
          h.strong([a.class("k-pending")], [h.text("magenta")]),
          h.text(" until the sluice stamps them; server-sequenced state is "),
          h.strong([a.class("k-seq")], [h.text("ink")]),
          h.text("."),
        ]),
        h.p([a.class("demo-hint")], [
          h.text(
            "Add folders and readings on any client, delete a folder, or press ",
          ),
          h.strong([], [h.text("Race the same folder")]),
          h.text(": all three clients create "),
          h.code([], [h.text("/kettle-run")]),
          h.text(
            " at the same instant. The three ops merge into a single folder (whose creator set records every author), rather than duplicating. That hierarchical-identity merge is exactly what a flat map can't do, and it survives delete-then-recreate races too.",
          ),
        ]),
      ]),
      h.div([a.class("rig"), test_id("directory-rig")], [
        client(model, directory.ClientA, "a"),
        client(model, directory.ClientB, "b"),
        client(model, directory.ClientC, "c"),
        channel(model),
        flows(model),
      ]),
      controls(model, unavailable),
      h.p([a.class("controls-hint")], [
        h.text(
          "Jitter can change simulated arrival order; animation speed changes playback only. Each moving request shows its sampled hop latency.",
        ),
      ]),
      case options.include_noscript {
        False -> element.none()
        True ->
          element.element("noscript", [], [
            h.p([a.class("demo-noscript"), test_id("noscript")], [
              h.text(
                "The live demo needs JavaScript: it runs the watershed runtime and in-memory ",
              ),
              h.code([], [h.text("sluice")]),
              h.text(
                " compiled for the browser. The rest of the page works without it.",
              ),
            ]),
          ])
      },
      case model.phase {
        directory.Static ->
          h.p(
            [
              a.class("demo-noscript directory-fallback"),
              test_id("directory-fallback"),
            ],
            [
              h.text(
                "The live demo couldn't start: it runs the production client runtime against the in-memory ",
              ),
              h.code([], [h.text("sluice")]),
              h.text(
                " as compiled JavaScript, and this browser didn't load it. The rest of the page works fine without it.",
              ),
            ],
          )
        _ -> element.none()
      },
      h.p(
        [
          a.class("demo-noscript"),
          a.attribute("aria-live", "polite"),
          test_id("error"),
        ],
        case model.error {
          None -> []
          Some(reason) -> [h.text(reason)]
        },
      ),
    ],
  )
}

fn client(model: directory.Model, replica: directory.Replica, area: String) {
  let id = directory.replica_id(replica)
  let label = directory.replica_label(replica)
  let pending =
    model.pending
    |> list.filter(fn(item) { item.replica == replica })
    |> list.length
  h.article(
    [
      a.class("client"),
      a.attribute("data-client", id),
      a.attribute("data-flow-node", id),
      a.attribute("aria-label", label <> " replica"),
      a.style("grid-area", area),
      test_id("client-" <> id),
    ],
    [
      h.header([a.class("client-head")], [
        h.h3([], [h.text(label)]),
        h.span(
          [
            a.class(case pending > 0 {
              True -> "pending-count annot is-pending"
              False -> "pending-count annot"
            }),
            test_id("pending-" <> id),
          ],
          [h.text(int.to_string(pending) <> " pending")],
        ),
      ]),
      h.div(
        [
          a.class("tree"),
          a.role("tree"),
          a.attribute("aria-label", label <> " directory tree"),
          test_id("tree-" <> id),
        ],
        case directory.node(model, replica, "/") {
          None -> []
          Some(root) -> [node(model, replica, root, True, unavailable(model))]
        },
      ),
    ],
  )
}

fn node(
  model: directory.Model,
  replica: directory.Replica,
  item: directory.Node,
  root: Bool,
  disabled: Bool,
) -> Element(directory.Msg) {
  let id = directory.replica_id(replica)
  let pending_folder =
    list.any(model.pending, fn(marker) {
      marker.replica == replica && marker.marker == "sub:" <> item.path
    })
  h.div([a.class("dir-node"), a.role("treeitem")], [
    h.div(
      [
        a.class(case pending_folder {
          True -> "dir-head pending"
          False -> "dir-head"
        }),
      ],
      [
        h.span([a.class("dir-name")], [
          h.text(case root {
            True -> "/"
            False -> item.name <> "/"
          }),
        ]),
        h.span([a.class("dir-actions")], [
          action(
            "+/",
            "Add a folder under "
              <> item.path
              <> " on "
              <> directory.replica_label(replica),
            "add-folder-" <> id <> "-" <> path_id(item.path),
            directory.AddFolder(replica, item.path),
            "",
            disabled,
          ),
          action(
            "+=",
            "Add a reading in "
              <> item.path
              <> " on "
              <> directory.replica_label(replica),
            "add-reading-" <> id <> "-" <> path_id(item.path),
            directory.AddReading(replica, item.path),
            "",
            disabled,
          ),
          case root {
            True -> element.none()
            False ->
              action(
                "×",
                "Delete "
                  <> item.path
                  <> " on "
                  <> directory.replica_label(replica),
                "delete-" <> id <> "-" <> path_id(item.path),
                directory.DeleteFolder(replica, parent(item.path), item.name),
                "dir-del",
                disabled,
              )
          },
        ]),
      ],
    ),
    case item.entries {
      [] -> element.none()
      entries ->
        h.ul(
          [a.class("dir-keys")],
          list.map(entries, fn(entry) {
            let marker = "key:" <> item.path <> "::" <> entry.key
            let pending =
              list.any(model.pending, fn(pending) {
                pending.replica == replica && pending.marker == marker
              })
            h.li(
              [
                a.class(case pending {
                  True -> "dir-key pending"
                  False -> "dir-key"
                }),
              ],
              [
                h.span([a.class("dk-key")], [h.text(entry.key)]),
                h.span([a.class("dk-val")], [h.text(entry.value)]),
              ],
            )
          }),
        )
    },
    case item.children {
      [] -> element.none()
      children ->
        h.div(
          [a.class("dir-children"), a.role("group")],
          list.map(children, node(model, replica, _, False, disabled)),
        )
    },
  ])
}

fn action(label, aria, id, message, extra, disabled) {
  h.button(
    [
      a.type_("button"),
      a.class(
        "node-action"
        <> case extra {
          "" -> ""
          _ -> " " <> extra
        },
      ),
      a.attribute("aria-label", aria),
      a.title(aria),
      a.disabled(disabled),
      test_id(id),
      event.on_click(message),
    ],
    [h.text(label)],
  )
}

fn unavailable(model: directory.Model) -> Bool {
  model.phase == directory.Static
  || model.phase == directory.Starting
  || model.phase == directory.Failed
}

fn channel(model: directory.Model) {
  h.div([a.class("channel"), a.style("grid-area", "seq")], [
    h.div([a.class("seq-node"), a.attribute("data-flow-node", "seq")], [
      h.span([a.class("annot")], [h.text("Sequencer")]),
      h.output(
        [
          a.class(case list.any(model.flows, fn(flow) { flow.from == "seq" }) {
            True -> "seq-counter stamped"
            False -> "seq-counter"
          }),
          a.attribute("aria-label", "Latest sequence number"),
          test_id("sequence"),
        ],
        [h.text("SN " <> int.to_string(model.latest_sequence))],
      ),
    ]),
    h.ol(
      [
        a.class("op-log"),
        a.attribute("aria-live", "polite"),
        a.attribute("aria-label", "Sequenced operations, newest first"),
        test_id("operation-log"),
      ],
      model.log
        |> list.take(24)
        |> list.map(fn(entry) {
          h.li([], [
            h.span([a.class("op-meta")], [
              h.text(
                "SN "
                <> int.to_string(entry.sequence_number)
                <> " · "
                <> string.drop_start(directory.replica_label(entry.author), 7),
              ),
            ]),
            h.span([a.class("op-path")], [h.text(entry.label)]),
            h.span([a.class("op-kind")], [h.text("op")]),
          ])
        }),
    ),
  ])
}

fn flows(model: directory.Model) {
  keyed.div(
    [
      a.class("flow-layer"),
      a.attribute("aria-hidden", "true"),
      test_id("flow-layer"),
    ],
    list.map(model.flows, fn(flow) {
      #(
        int.to_string(flow.id),
        h.span(
          [
            a.class(case flow.from {
              "seq" -> "flow-dot sequenced"
              _ -> "flow-dot"
            }),
            a.attribute("data-flow-id", int.to_string(flow.id)),
            a.attribute("data-from", flow.from),
            a.attribute("data-to", flow.to),
          ],
          [h.span([a.class("flow-dot-label")], [h.text(flow.label)])],
        ),
      )
    }),
  )
}

fn controls(model: directory.Model, unavailable: Bool) {
  h.div([a.class("demo-controls"), a.attribute("data-reveal", "rise")], [
    h.label([a.class("pace")], [
      h.span([a.class("annot")], [h.text("Animation speed")]),
      h.input([
        a.type_("range"),
        a.min("0.25"),
        a.max("2"),
        a.step("0.25"),
        a.value(pace(model.pace_quarters)),
        a.title("Playback only; does not affect simulated ordering."),
        a.disabled(unavailable),
        test_id("pace"),
        event.on_input(directory.SetPace),
      ]),
      h.output([], [h.text(pace(model.pace_quarters) <> "×")]),
    ]),
    h.label([a.class("field-notes-toggle")], [
      h.input([
        a.type_("checkbox"),
        a.checked(model.jitter),
        a.title("Add random ±100 ms per hop; arrival order may change."),
        a.disabled(unavailable),
        test_id("jitter"),
        event.on_check(directory.SetJitter),
      ]),
      h.span([a.class("annot")], [h.text("Jitter ±100 ms")]),
    ]),
    control_button(
      "race-btn",
      "race",
      "Race the same folder",
      unavailable,
      directory.Race,
    ),
    control_button(
      "reset-btn",
      "seed",
      "Build sample tree",
      unavailable,
      directory.Seed,
    ),
    h.button(
      [
        a.type_("button"),
        a.class("reset-btn"),
        a.attribute("aria-label", "Reset all replicas to an empty root"),
        a.disabled(unavailable),
        test_id("reset"),
        event.on_click(directory.Reset),
      ],
      [h.text("Reset")],
    ),
    h.p([a.class("status"), a.role("status"), test_id("status")], [
      h.span(
        [
          a.class(case model.converged {
            True -> "stamp converged"
            False -> "stamp revising"
          }),
        ],
        [
          h.text(case model.converged {
            True -> "Converged"
            False -> "Revising"
          }),
        ],
      ),
      h.text(case model.converged {
        True -> " all replicas identical · nothing pending"
        False -> " ops in flight"
      }),
    ]),
  ])
}

fn control_button(class, id, label, disabled, message) {
  h.button(
    [
      a.type_("button"),
      a.class(class),
      a.disabled(disabled),
      test_id(id),
      event.on_click(message),
    ],
    [h.text(label)],
  )
}

fn parent(path: String) -> String {
  let parent =
    path
    |> string.split("/")
    |> list.reverse
    |> list.drop(1)
    |> list.reverse
    |> string.join("/")
  case parent {
    "" -> "/"
    parent -> parent
  }
}

fn path_id(path: String) -> String {
  case path {
    "/" -> "root"
    _ -> string.replace(string.drop_start(path, 1), "/", "-")
  }
}

fn pace(quarters: Int) -> String {
  case quarters {
    1 -> "0.25"
    2 -> "0.5"
    3 -> "0.75"
    4 -> "1"
    5 -> "1.25"
    6 -> "1.5"
    7 -> "1.75"
    _ -> "2"
  }
}

fn test_id(id: String) -> a.Attribute(msg) {
  a.attribute("data-testid", id)
}
