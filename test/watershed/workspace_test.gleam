import gleam/dynamic/decode
import gleam/json
import gleam/list
import startest/expect
import watershed/component
import watershed/handle
import watershed/port
import watershed/port_graph
import watershed/workspace

fn task_config_decoder() -> decode.Decoder(String) {
  use title <- decode.field("title", decode.string)
  decode.success(title)
}

fn task_descriptor() -> component.Descriptor(Nil, Nil) {
  component.descriptor(
    kind: "watershed/tasks",
    version: 1,
    config_decoder: task_config_decoder(),
    start: fn(_, _) { Ok(Nil) },
    ports: [
      port.output_descriptor(port.output("selected", "task-id@1", json.string)),
      port.input_descriptor(port.local_input(
        "focus",
        "task-id@1",
        decode.string,
      )),
    ],
  )
}

fn notes_descriptor() -> component.Descriptor(Nil, Nil) {
  component.descriptor(
    kind: "watershed/notes",
    version: 1,
    config_decoder: decode.success(Nil),
    start: fn(_, _) { Ok(Nil) },
    ports: [
      port.output_descriptor(port.output("selected", "task-id@1", json.string)),
      port.input_descriptor(port.local_input(
        "focus",
        "task-id@1",
        decode.string,
      )),
    ],
  )
}

fn catalog() -> component.Catalog(Nil, Nil) {
  let assert Ok(with_tasks) =
    component.register(component.new_catalog(), task_descriptor())
  let assert Ok(catalog) = component.register(with_tasks, notes_descriptor())
  catalog
}

fn entry(
  id: String,
  kind: String,
  version: Int,
  config: json.Json,
  child: String,
) -> workspace.ManifestEntry {
  workspace.ManifestEntry(
    id,
    kind,
    version,
    config,
    handle.encode_handle(child),
  )
}

fn stored(
  entries: List(workspace.ManifestEntry),
) -> List(#(String, json.Json)) {
  list.map(entries, fn(entry) {
    #(entry.instance_id, workspace.encode_manifest(entry))
  })
}

fn connection(
  id: String,
  source_instance: String,
  source_port: String,
  target_instance: String,
  target_port: String,
) -> port_graph.Connection {
  port_graph.connection(
    id,
    port_graph.PortRef(source_instance, source_port),
    port_graph.PortRef(target_instance, target_port),
  )
}

pub fn manifest_round_trip_preserves_nested_config_test() -> Nil {
  let manifest =
    entry(
      "tasks-1",
      "watershed/tasks",
      1,
      json.object([
        #("title", json.string("Plan")),
        #("filters", json.array([json.string("open")], fn(value) { value })),
      ]),
      "child-1",
    )

  let assert Ok(decoded) =
    manifest
    |> workspace.encode_manifest
    |> workspace.decode_manifest

  decoded.instance_id |> expect.to_equal("tasks-1")
  decoded.kind |> expect.to_equal("watershed/tasks")
  decoded.version |> expect.to_equal(1)
  decoded.child_handle |> expect.to_equal(handle.encode_handle("child-1"))
}

pub fn invalid_child_handle_is_rejected_test() -> Nil {
  let value =
    json.object([
      #("instanceId", json.string("tasks-1")),
      #("kind", json.string("watershed/tasks")),
      #("version", json.int(1)),
      #("config", json.object([#("title", json.string("Plan"))])),
      #("child", json.string("not-a-handle")),
    ])

  case workspace.decode_manifest(value) {
    Error(_) -> Nil
    Ok(_) -> panic as "expected an invalid child handle"
  }
}

pub fn connection_round_trip_test() -> Nil {
  let original = connection("edge-1", "tasks-1", "selected", "notes-1", "focus")

  original
  |> workspace.encode_connection
  |> workspace.decode_connection
  |> expect.to_equal(Ok(original))
}

pub fn effective_layout_keeps_first_known_occurrence_test() -> Nil {
  let entries = [
    entry(
      "tasks-1",
      "watershed/tasks",
      1,
      json.object([#("title", json.string("Plan"))]),
      "child-1",
    ),
    entry("notes-1", "watershed/notes", 1, json.null(), "child-2"),
  ]
  let snapshot =
    workspace.snapshot(
      stored(entries),
      [
        json.string("tasks-1"),
        json.string("missing"),
        json.string("tasks-1"),
        json.string("notes-1"),
      ],
      [],
      catalog(),
    )

  workspace.layout(snapshot)
  |> expect.to_equal(["tasks-1", "notes-1"])
  workspace.diagnostics(snapshot)
  |> expect.to_equal([
    workspace.UnknownLayout("missing"),
    workspace.DuplicateLayout("tasks-1"),
  ])
}

pub fn invalid_manifest_and_graph_values_remain_stored_test() -> Nil {
  let invalid_manifest = json.object([#("kind", json.string("broken"))])
  let invalid_connection = json.object([#("id", json.string("broken"))])
  let snapshot =
    workspace.snapshot(
      [#("broken", invalid_manifest)],
      [],
      [invalid_connection],
      catalog(),
    )

  let assert [
    workspace.StoredManifestEntry(
      key: "broken",
      raw: stored_manifest,
      decoded: Error(_),
    ),
  ] = workspace.stored_manifest(snapshot)
  stored_manifest |> expect.to_equal(invalid_manifest)

  case workspace.diagnostics(snapshot) {
    [workspace.InvalidManifest("broken", _), workspace.InvalidConnection(0, _)] ->
      Nil
    _ -> panic as "expected retained invalid values"
  }
}

pub fn preparation_distinguishes_all_states_test() -> Nil {
  let valid =
    entry(
      "tasks-1",
      "watershed/tasks",
      1,
      json.object([#("title", json.string("Plan"))]),
      "ready",
    )
  let loading =
    entry(
      "tasks-2",
      "watershed/tasks",
      1,
      json.object([#("title", json.string("Wait"))]),
      "loading",
    )
  let unavailable = entry("other-1", "example/other", 1, json.null(), "other")
  let invalid =
    entry("tasks-3", "watershed/tasks", 1, json.object([]), "invalid")
  let snapshot =
    workspace.snapshot(
      stored([valid, loading, unavailable, invalid]),
      [],
      [],
      catalog(),
    )
  let states =
    workspace.prepare(snapshot, catalog(), fn(child_handle) {
      case handle.parse_handle(child_handle) {
        Ok("loading") -> Error("not attached")
        Ok(address) -> Ok(address)
        Error(Nil) -> Error("invalid")
      }
    })

  case states {
    [
      workspace.Prepared(entry: _, subtree: "ready"),
      workspace.Loading(entry: _, reason: "not attached"),
      workspace.Unavailable(entry: _, reason: component.NotRegistered(_)),
      workspace.Failed(
        instance_id: "tasks-3",
        reason: workspace.InvalidComponentConfig(_),
      ),
    ] -> Nil
    _ -> panic as "expected prepared, loading, unavailable, and failed states"
  }
}

pub fn connection_validation_rejects_cycle_without_displacing_edge_test() -> Nil {
  let entries = [
    entry(
      "tasks-1",
      "watershed/tasks",
      1,
      json.object([#("title", json.string("Plan"))]),
      "child-1",
    ),
    entry("notes-1", "watershed/notes", 1, json.null(), "child-2"),
  ]
  let accepted =
    connection("z-existing", "tasks-1", "selected", "notes-1", "focus")
  let snapshot =
    workspace.snapshot(
      stored(entries),
      [json.string("tasks-1"), json.string("notes-1")],
      [workspace.encode_connection(accepted)],
      catalog(),
    )
  let candidate = connection("a-new", "notes-1", "selected", "tasks-1", "focus")

  workspace.validate_connection(snapshot, candidate, catalog())
  |> expect.to_equal(Error(workspace.DisplacesConnection("z-existing")))
}

fn valid_entry() -> workspace.ManifestEntry {
  entry(
    "tasks-1",
    "watershed/tasks",
    1,
    json.object([#("title", json.string("Plan"))]),
    "child-1",
  )
}

pub fn deletion_indexes_are_descending_test() -> Nil {
  let edge = connection("edge", "tasks-1", "selected", "notes-1", "focus")
  let snapshot =
    workspace.snapshot(
      stored([valid_entry()]),
      [
        json.string("tasks-1"),
        json.string("other"),
        json.string("tasks-1"),
      ],
      [
        workspace.encode_connection(edge),
        json.object([]),
        workspace.encode_connection(edge),
      ],
      catalog(),
    )

  workspace.layout_removal_indices(snapshot, "tasks-1")
  |> expect.to_equal([2, 0])
  workspace.connection_id_removal_indices(snapshot, "edge")
  |> expect.to_equal([2, 0])
  workspace.instance_connection_indices(snapshot, "tasks-1")
  |> expect.to_equal([2, 0])
}

pub fn move_plan_removes_stale_copies_before_moving_test() -> Nil {
  let entries = [
    valid_entry(),
    entry("notes-1", "watershed/notes", 1, json.null(), "child-2"),
    entry(
      "tasks-2",
      "watershed/tasks",
      1,
      json.object([#("title", json.string("Other"))]),
      "child-3",
    ),
  ]
  let snapshot =
    workspace.snapshot(
      stored(entries),
      [
        json.string("tasks-1"),
        json.string("notes-1"),
        json.string("tasks-1"),
        json.string("tasks-2"),
      ],
      [],
      catalog(),
    )

  workspace.plan_move(snapshot, "tasks-1", 2)
  |> expect.to_equal(Ok(workspace.Move([2], 0, 2)))
}
