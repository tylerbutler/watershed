@target(javascript)
import gleam/dynamic/decode
@target(javascript)
import gleam/json
@target(javascript)
import gleam/list
@target(javascript)
import gleam/option.{type Option, None, Some}
@target(javascript)
import gleam/string
@target(javascript)
import startest/expect
@target(javascript)
import watershed
@target(javascript)
import watershed/component
@target(javascript)
import watershed/component_runtime_js
@target(javascript)
import watershed/port
@target(javascript)
import watershed/port_graph
@target(javascript)
import watershed/schema.{type ChildField}
@target(javascript)
import watershed/sluice_js
@target(javascript)
import watershed/transport_js.{type Cell}
@target(javascript)
import watershed/workspace
@target(javascript)
import watershed/workspace_js

@target(javascript)
pub type Root

@target(javascript)
type Running {
  Tasks(stops: Cell(List(String)), output: component.OutputEmitter)
  Notes(focus: Option(String), stops: Cell(List(String)))
  Activity(entries: List(String), stops: Cell(List(String)))
  Delayed(stops: Cell(List(String)))
}

@target(javascript)
type Context {
  Context(
    instance_id: String,
    starts: Cell(List(String)),
    stops: Cell(List(String)),
    output: component.OutputEmitter,
  )
}

@target(javascript)
fn workspace_field() -> ChildField(Root, workspace.WorkspaceSchema) {
  schema.child_field("workspace")
}

@target(javascript)
fn selected_output() -> port.Output(String) {
  port.output("selected", "task-id@1", json.string)
}

@target(javascript)
fn completed_output() -> port.Output(String) {
  port.output("completed", "task-id@1", json.string)
}

@target(javascript)
fn undeclared_output() -> port.Output(String) {
  port.output("undeclared", "task-id@1", json.string)
}

@target(javascript)
fn focus_input() -> port.Input(String) {
  port.local_input("focus", "task-id@1", decode.string)
}

@target(javascript)
fn append_input() -> port.Input(String) {
  port.collaborative_input("append", "task-id@1", decode.string, [
    "sequence:insert",
  ])
}

@target(javascript)
fn catalog() -> component.Catalog(Context, Running) {
  let assert Ok(with_tasks) =
    component.register(component.new_catalog(), tasks_descriptor())
  let assert Ok(with_notes) = component.register(with_tasks, notes_descriptor())
  let assert Ok(full) = component.register(with_notes, activity_descriptor())
  full
}

@target(javascript)
fn tasks_descriptor() -> component.Descriptor(Context, Running) {
  component.executable_descriptor(
    kind: "tasks",
    version: 1,
    config_decoder: decode.string,
    start: fn(context: Context, _, done) {
      record(context.starts, context.instance_id)
      done(Ok(Tasks(context.stops, context.output)))
    },
    inputs: [],
    stop: stop_running,
    ports: [
      port.output_descriptor(selected_output()),
      port.output_descriptor(completed_output()),
    ],
  )
}

@target(javascript)
fn notes_descriptor() -> component.Descriptor(Context, Running) {
  notes_descriptor_with_hooks(fn() { Nil }, fn() { Nil })
}

@target(javascript)
fn notes_descriptor_with_hooks(
  on_input: fn() -> Nil,
  on_stop: fn() -> Nil,
) -> component.Descriptor(Context, Running) {
  component.executable_descriptor(
    kind: "notes",
    version: 1,
    config_decoder: decode.string,
    start: fn(context: Context, _, done) {
      record(context.starts, context.instance_id)
      done(Ok(Notes(None, context.stops)))
    },
    inputs: [
      component.input_handler(focus_input(), fn(running, task_id) {
        on_input()
        case running {
          Notes(_, stops) -> Ok(#(Notes(Some(task_id), stops), []))
          _ -> Error("focus reached the wrong component")
        }
      }),
    ],
    stop: fn(running) {
      on_stop()
      stop_running(running)
    },
    ports: [port.input_descriptor(focus_input())],
  )
}

@target(javascript)
fn activity_descriptor() -> component.Descriptor(Context, Running) {
  component.executable_descriptor(
    kind: "activity",
    version: 1,
    config_decoder: decode.string,
    start: fn(context: Context, _, done) {
      record(context.starts, context.instance_id)
      done(Ok(Activity([], context.stops)))
    },
    inputs: [
      component.input_handler(append_input(), fn(running, task_id) {
        case running {
          Activity(entries, stops) ->
            Ok(#(Activity(list.append(entries, [task_id]), stops), []))
          _ -> Error("append reached the wrong component")
        }
      }),
    ],
    stop: stop_running,
    ports: [port.input_descriptor(append_input())],
  )
}

@target(javascript)
fn stop_running(running: Running) -> Result(Nil, String) {
  let #(name, stops) = case running {
    Tasks(stops, _) -> #("tasks", stops)
    Notes(_, stops) -> #("notes", stops)
    Activity(_, stops) -> #("activity", stops)
    Delayed(stops) -> #("delayed", stops)
  }
  record(stops, name)
  Ok(Nil)
}

@target(javascript)
fn record(cell: Cell(List(value)), value: value) -> Nil {
  transport_js.set_cell(cell, [value, ..transport_js.get_cell(cell)])
}

@target(javascript)
fn started_runtime(
  name: String,
) -> #(
  sluice_js.Sluice,
  workspace_js.Workspace(Root),
  component_runtime_js.Runtime(Root, Context, Running),
  Cell(List(String)),
  Cell(List(String)),
  Cell(List(component_runtime_js.DispatchReport)),
) {
  started_runtime_with_hooks(name, fn() { Nil }, fn() { Nil }, fn(_) { Nil })
}

@target(javascript)
fn started_runtime_with_hooks(
  name: String,
  on_input: fn() -> Nil,
  on_stop: fn() -> Nil,
  on_report: fn(component_runtime_js.DispatchReport) -> Nil,
) -> #(
  sluice_js.Sluice,
  workspace_js.Workspace(Root),
  component_runtime_js.Runtime(Root, Context, Running),
  Cell(List(String)),
  Cell(List(String)),
  Cell(List(component_runtime_js.DispatchReport)),
) {
  let sluice = sluice_js.start(tenant: "default", document: name)
  let document = sluice_js.connect(sluice, "user-a")
  sluice_js.settle(sluice)
  let store = ensure_workspace(document)
  let assert Ok(catalog) =
    component.new_catalog()
    |> component.register(tasks_descriptor())
  let assert Ok(catalog) =
    component.register(catalog, notes_descriptor_with_hooks(on_input, on_stop))
  let assert Ok(catalog) = component.register(catalog, activity_descriptor())
  let assert Ok(_) =
    workspace_js.add_instance(
      store,
      catalog,
      "tasks",
      "tasks",
      1,
      json.string("tasks"),
    )
  let assert Ok(_) =
    workspace_js.add_instance(
      store,
      catalog,
      "notes",
      "notes",
      1,
      json.string("notes"),
    )
  let assert Ok(_) =
    workspace_js.add_instance(
      store,
      catalog,
      "activity",
      "activity",
      1,
      json.string("activity"),
    )
  let assert Ok(_) =
    workspace_js.add_connection(
      store,
      catalog,
      port_graph.connection(
        "selected-focus",
        port_graph.PortRef("tasks", "selected"),
        port_graph.PortRef("notes", "focus"),
      ),
    )
  let assert Ok(_) =
    workspace_js.add_connection(
      store,
      catalog,
      port_graph.connection(
        "completed-append",
        port_graph.PortRef("tasks", "completed"),
        port_graph.PortRef("activity", "append"),
      ),
    )
  let starts = transport_js.new_cell([])
  let stops = transport_js.new_cell([])
  let reports = transport_js.new_cell([])
  let runtime =
    component_runtime_js.start(
      document: document,
      root: watershed.root_typed(document),
      field: workspace_field(),
      store: store,
      catalog: catalog,
      context_for: fn(entry, _, _, output) {
        Context(entry.instance_id, starts, stops, output)
      },
      scheduler: sluice_js.scheduler(sluice),
      on_change: fn() { Nil },
      on_report: fn(report) {
        record(reports, report)
        on_report(report)
      },
    )
  sluice_js.advance(sluice, 0)
  #(sluice, store, runtime, starts, stops, reports)
}

@target(javascript)
fn ensure_workspace(
  document: watershed.Document(Root),
) -> workspace_js.Workspace(Root) {
  let opened = transport_js.new_cell(None)
  workspace_js.ensure(
    document,
    watershed.root_typed(document),
    workspace_field(),
    fn(result) { transport_js.set_cell(opened, Some(result)) },
  )
  let assert Some(Ok(store)) = transport_js.get_cell(opened)
  store
}

@target(javascript)
pub fn local_and_collaborative_deliveries_update_the_targets_test() -> Nil {
  let #(_sluice, _store, runtime, starts, _stops, reports) =
    started_runtime("component-runtime-delivery")

  component_runtime_js.command(runtime, "tasks", fn(running) {
    case running {
      Tasks(_, _) ->
        Ok(#(running, [component.emit(selected_output(), "task-1")]))
      _ -> Error("wrong source")
    }
  })
  |> expect.to_equal(Ok(Nil))

  let assert Ok(Notes(focus, _)) =
    component_runtime_js.running(runtime, "notes")
  focus |> expect.to_equal(Some("task-1"))

  component_runtime_js.command(runtime, "tasks", fn(running) {
    case running {
      Tasks(_, _) ->
        Ok(#(running, [component.emit(completed_output(), "task-1")]))
      _ -> Error("wrong source")
    }
  })
  |> expect.to_equal(Ok(Nil))

  let assert Ok(Activity(entries, _)) =
    component_runtime_js.running(runtime, "activity")
  entries |> expect.to_equal(["task-1"])
  transport_js.get_cell(starts)
  |> list.sort(string.compare)
  |> expect.to_equal(["activity", "notes", "tasks"])
  transport_js.get_cell(reports)
  |> list.any(fn(report) {
    case report {
      component_runtime_js.LocalDelivered(_, "selected-focus", _) -> True
      _ -> False
    }
  })
  |> expect.to_equal(True)
  transport_js.get_cell(reports)
  |> list.any(fn(report) {
    case report {
      component_runtime_js.MutationSubmitted(_, "completed-append", _) -> True
      _ -> False
    }
  })
  |> expect.to_equal(True)
}

@target(javascript)
pub fn separate_source_events_on_one_port_are_not_collapsed_test() -> Nil {
  let #(_sluice, _store, runtime, _starts, _stops, reports) =
    started_runtime("component-runtime-repeated-output")

  component_runtime_js.command(runtime, "tasks", fn(running) {
    case running {
      Tasks(_, _) ->
        Ok(
          #(running, [
            component.emit(selected_output(), "task-1"),
            component.emit(selected_output(), "task-2"),
          ]),
        )
      _ -> Error("wrong source")
    }
  })
  |> expect.to_equal(Ok(Nil))

  let assert Ok(Notes(focus, _)) =
    component_runtime_js.running(runtime, "notes")
  focus |> expect.to_equal(Some("task-2"))
  transport_js.get_cell(reports)
  |> list.filter(fn(report) {
    case report {
      component_runtime_js.LocalDelivered(_, "selected-focus", _) -> True
      _ -> False
    }
  })
  |> list.length
  |> expect.to_equal(2)
}

@target(javascript)
pub fn asynchronous_outputs_use_the_graph_and_distinct_traces_test() -> Nil {
  let #(sluice, _store, runtime, _starts, _stops, reports) =
    started_runtime("component-runtime-async-output")

  component_runtime_js.command(runtime, "tasks", fn(running) {
    case running {
      Tasks(_, _) ->
        Ok(#(running, [component.emit(selected_output(), "command")]))
      _ -> Error("wrong source")
    }
  })
  |> expect.to_equal(Ok(Nil))

  let assert Ok(Tasks(_, output)) =
    component_runtime_js.running(runtime, "tasks")
  component.publish(output, [component.emit(selected_output(), "async")])

  let assert Ok(Notes(Some("command"), _)) =
    component_runtime_js.running(runtime, "notes")

  sluice_js.advance(sluice, 0)

  let assert Ok(Notes(Some("async"), _)) =
    component_runtime_js.running(runtime, "notes")
  transport_js.get_cell(reports)
  |> list.filter_map(fn(report) {
    case report {
      component_runtime_js.Triggered(trace_id, _) -> Ok(trace_id)
      _ -> Error(Nil)
    }
  })
  |> list.reverse
  |> expect.to_equal(["trace-1", "trace-2"])
}

@target(javascript)
pub fn asynchronous_output_batches_are_validated_before_dispatch_test() -> Nil {
  let #(sluice, _store, runtime, _starts, _stops, reports) =
    started_runtime("component-runtime-async-validation")
  let assert Ok(Tasks(_, output)) =
    component_runtime_js.running(runtime, "tasks")

  component.publish(output, [
    component.emit(selected_output(), "must-not-deliver"),
    component.emit(undeclared_output(), "invalid"),
  ])
  sluice_js.advance(sluice, 0)

  let assert Ok(Notes(None, _)) = component_runtime_js.running(runtime, "notes")
  transport_js.get_cell(reports)
  |> list.any(fn(report) {
    case report {
      component_runtime_js.DispatchFailed(
        _,
        None,
        component_runtime_js.SourceOutputRejected("tasks", _),
      ) -> True
      _ -> False
    }
  })
  |> expect.to_equal(True)
}

@target(javascript)
pub fn a_replaced_generation_disables_its_old_output_emitter_test() -> Nil {
  let #(sluice, store, runtime, _starts, _stops, reports) =
    started_runtime("component-runtime-stale-output")
  let assert Ok(Tasks(_, old_output)) =
    component_runtime_js.running(runtime, "tasks")
  let room_catalog = catalog()

  let assert Ok(Nil) =
    workspace_js.delete_instance(store, room_catalog, "tasks")
  sluice_js.advance(sluice, 0)
  component_runtime_js.running(runtime, "tasks") |> expect.to_be_error()

  let assert Ok(_) =
    workspace_js.add_instance(
      store,
      room_catalog,
      "tasks",
      "tasks",
      1,
      json.string("replacement"),
    )
  let assert Ok(_) =
    workspace_js.add_connection(
      store,
      room_catalog,
      port_graph.connection(
        "selected-focus",
        port_graph.PortRef("tasks", "selected"),
        port_graph.PortRef("notes", "focus"),
      ),
    )
  sluice_js.advance(sluice, 0)

  let assert Ok(Tasks(_, new_output)) =
    component_runtime_js.running(runtime, "tasks")
  let report_count = list.length(transport_js.get_cell(reports))
  component.publish(old_output, [
    component.emit(selected_output(), "stale-late"),
  ])
  sluice_js.advance(sluice, 0)
  list.length(transport_js.get_cell(reports))
  |> expect.to_equal(report_count)

  component.publish(new_output, [
    component.emit(selected_output(), "replacement"),
  ])
  sluice_js.advance(sluice, 0)
  let assert Ok(Notes(Some("replacement"), _)) =
    component_runtime_js.running(runtime, "notes")
  Nil
}

@target(javascript)
pub fn a_queued_output_from_a_stopped_runtime_is_rejected_test() -> Nil {
  let #(sluice, _store, runtime, _starts, _stops, reports) =
    started_runtime("component-runtime-stopped-output")
  let assert Ok(Tasks(_, output)) =
    component_runtime_js.running(runtime, "tasks")

  component.publish(output, [component.emit(selected_output(), "stale")])
  let _errors = component_runtime_js.stop(runtime)
  sluice_js.advance(sluice, 0)

  transport_js.get_cell(reports)
  |> list.any(fn(report) {
    case report {
      component_runtime_js.DispatchFailed(
        _,
        None,
        component_runtime_js.SourceNotReady("tasks"),
      ) -> True
      _ -> False
    }
  })
  |> expect.to_equal(True)

  let report_count = list.length(transport_js.get_cell(reports))
  component.publish(output, [component.emit(selected_output(), "late")])
  sluice_js.advance(sluice, 0)
  list.length(transport_js.get_cell(reports))
  |> expect.to_equal(report_count)
}

@target(javascript)
pub fn layout_and_graph_edits_do_not_restart_components_test() -> Nil {
  let #(sluice, store, runtime, starts, stops, _reports) =
    started_runtime("component-runtime-topology")

  let assert Ok(Nil) =
    workspace_js.move_instance(store, catalog(), "activity", 0)
  let assert Ok(Nil) =
    workspace_js.remove_connection(store, catalog(), "selected-focus")
  sluice_js.advance(sluice, 0)

  transport_js.get_cell(starts)
  |> list.sort(string.compare)
  |> expect.to_equal(["activity", "notes", "tasks"])
  transport_js.get_cell(stops) |> expect.to_equal([])

  let assert Ok(Nil) = workspace_js.delete_instance(store, catalog(), "notes")
  sluice_js.advance(sluice, 0)

  component_runtime_js.running(runtime, "notes") |> expect.to_be_error()
  transport_js.get_cell(stops) |> expect.to_equal(["notes"])
}

@target(javascript)
pub fn a_late_start_is_stopped_after_its_instance_is_deleted_test() -> Nil {
  let sluice =
    sluice_js.start(tenant: "default", document: "component-runtime-late-start")
  let document = sluice_js.connect(sluice, "user-a")
  sluice_js.settle(sluice)
  let store = ensure_workspace(document)
  let starts = transport_js.new_cell([])
  let stops = transport_js.new_cell([])
  let deferred: Cell(Option(fn(Result(Running, String)) -> Nil)) =
    transport_js.new_cell(None)
  let descriptor =
    component.executable_descriptor(
      kind: "delayed",
      version: 1,
      config_decoder: decode.string,
      start: fn(context: Context, _, done) {
        record(context.starts, context.instance_id)
        transport_js.set_cell(deferred, Some(done))
      },
      inputs: [],
      stop: stop_running,
      ports: [],
    )
  let assert Ok(catalog) =
    component.register(component.new_catalog(), descriptor)
  let assert Ok(_) =
    workspace_js.add_instance(
      store,
      catalog,
      "delayed",
      "delayed",
      1,
      json.string("delayed"),
    )
  let runtime =
    component_runtime_js.start(
      document: document,
      root: watershed.root_typed(document),
      field: workspace_field(),
      store: store,
      catalog: catalog,
      context_for: fn(entry, _, _, output) {
        Context(entry.instance_id, starts, stops, output)
      },
      scheduler: sluice_js.scheduler(sluice),
      on_change: fn() { Nil },
      on_report: fn(_) { Nil },
    )
  sluice_js.advance(sluice, 0)
  let assert [#("delayed", component_runtime_js.Starting(_))] =
    component_runtime_js.lifecycle(runtime)

  let assert Ok(Nil) = workspace_js.delete_instance(store, catalog, "delayed")
  sluice_js.advance(sluice, 0)
  let assert Some(done) = transport_js.get_cell(deferred)
  done(Ok(Delayed(stops)))

  component_runtime_js.running(runtime, "delayed") |> expect.to_be_error()
  transport_js.get_cell(stops) |> expect.to_equal(["delayed"])
}

@target(javascript)
pub fn a_failed_identity_is_not_retried_by_unrelated_topology_changes_test() -> Nil {
  let sluice =
    sluice_js.start(tenant: "default", document: "component-runtime-failed")
  let document = sluice_js.connect(sluice, "user-a")
  sluice_js.settle(sluice)
  let store = ensure_workspace(document)
  let starts = transport_js.new_cell([])
  let stops = transport_js.new_cell([])
  let broken =
    component.executable_descriptor(
      kind: "broken",
      version: 1,
      config_decoder: decode.string,
      start: fn(context: Context, _, done) {
        record(context.starts, context.instance_id)
        done(Error("bootstrap failed"))
      },
      inputs: [],
      stop: stop_running,
      ports: [],
    )
  let assert Ok(with_broken) =
    component.register(component.new_catalog(), broken)
  let assert Ok(catalog) = component.register(with_broken, tasks_descriptor())
  let assert Ok(_) =
    workspace_js.add_instance(
      store,
      catalog,
      "broken",
      "broken",
      1,
      json.string("broken"),
    )
  let runtime =
    component_runtime_js.start(
      document: document,
      root: watershed.root_typed(document),
      field: workspace_field(),
      store: store,
      catalog: catalog,
      context_for: fn(entry, _, _, output) {
        Context(entry.instance_id, starts, stops, output)
      },
      scheduler: sluice_js.scheduler(sluice),
      on_change: fn() { Nil },
      on_report: fn(_) { Nil },
    )
  sluice_js.advance(sluice, 0)

  let assert Ok(_) =
    workspace_js.add_instance(
      store,
      catalog,
      "tasks",
      "tasks",
      1,
      json.string("tasks"),
    )
  sluice_js.advance(sluice, 0)

  transport_js.get_cell(starts)
  |> list.filter(fn(instance_id) { instance_id == "broken" })
  |> list.length
  |> expect.to_equal(1)
  let assert [
    #("broken", component_runtime_js.Failed(_, _)),
    #("tasks", component_runtime_js.Ready(_)),
  ] = component_runtime_js.lifecycle(runtime)
  Nil
}

@target(javascript)
pub fn cold_workspace_runtimes_reopen_the_same_winner_test() -> Nil {
  let sluice =
    sluice_js.start(tenant: "default", document: "component-runtime-cold-race")
  let document_a = sluice_js.connect(sluice, "user-a")
  let document_b = sluice_js.connect(sluice, "user-b")
  sluice_js.settle(sluice)

  let store_a = ensure_workspace(document_a)
  let store_b = ensure_workspace(document_b)
  let catalog = catalog()
  let assert Ok(_) =
    workspace_js.add_instance(
      store_a,
      catalog,
      "tasks",
      "tasks",
      1,
      json.string("tasks"),
    )
  let assert Ok(_) =
    workspace_js.add_instance(
      store_b,
      catalog,
      "activity",
      "activity",
      1,
      json.string("activity"),
    )
  let starts_a = transport_js.new_cell([])
  let stops_a = transport_js.new_cell([])
  let starts_b = transport_js.new_cell([])
  let stops_b = transport_js.new_cell([])
  let runtime_a =
    runtime_for(sluice, document_a, store_a, catalog, starts_a, stops_a)
  let runtime_b =
    runtime_for(sluice, document_b, store_b, catalog, starts_b, stops_b)
  sluice_js.advance(sluice, 0)

  sluice_js.settle(sluice)
  sluice_js.advance(sluice, 0)
  sluice_js.settle(sluice)
  sluice_js.advance(sluice, 0)

  let winner = component_runtime_js.layout(runtime_a)
  winner |> expect.to_equal(component_runtime_js.layout(runtime_b))
  case winner {
    ["tasks"] -> {
      component_runtime_js.running(runtime_a, "tasks")
      |> expect.to_be_ok()
      component_runtime_js.running(runtime_b, "tasks")
      |> expect.to_be_ok()
    }
    ["activity"] -> {
      component_runtime_js.running(runtime_a, "activity")
      |> expect.to_be_ok()
      component_runtime_js.running(runtime_b, "activity")
      |> expect.to_be_ok()
    }
    other -> panic as { "unexpected winning layout: " <> string.inspect(other) }
  }
  list.length(transport_js.get_cell(stops_a))
  + list.length(transport_js.get_cell(stops_b))
  |> expect.to_equal(1)
}

@target(javascript)
pub fn startup_opens_a_winner_replaced_before_subscription_test() -> Nil {
  let sluice =
    sluice_js.start(
      tenant: "default",
      document: "component-runtime-stale-start",
    )
  let document_a = sluice_js.connect(sluice, "user-a")
  let document_b = sluice_js.connect(sluice, "user-b")
  sluice_js.settle(sluice)

  let stale_store = ensure_workspace(document_b)
  let room_catalog = catalog()
  let assert Ok(_) =
    workspace_js.add_instance(
      stale_store,
      room_catalog,
      "tasks",
      "tasks",
      1,
      json.string("tasks"),
    )
  sluice_js.settle(sluice)

  watershed.delete(watershed.root(document_a), "workspace")
  let winning_store = ensure_workspace(document_a)
  let assert Ok(_) =
    workspace_js.add_instance(
      winning_store,
      room_catalog,
      "activity",
      "activity",
      1,
      json.string("activity"),
    )
  sluice_js.settle(sluice)

  let starts = transport_js.new_cell([])
  let stops = transport_js.new_cell([])
  let runtime =
    runtime_for(sluice, document_b, stale_store, room_catalog, starts, stops)
  sluice_js.advance(sluice, 0)

  component_runtime_js.layout(runtime) |> expect.to_equal(["activity"])
  component_runtime_js.running(runtime, "activity") |> expect.to_be_ok()
  component_runtime_js.running(runtime, "tasks") |> expect.to_be_error()
}

@target(javascript)
fn runtime_for(
  sluice: sluice_js.Sluice,
  document: watershed.Document(Root),
  store: workspace_js.Workspace(Root),
  catalog: component.Catalog(Context, Running),
  starts: Cell(List(String)),
  stops: Cell(List(String)),
) -> component_runtime_js.Runtime(Root, Context, Running) {
  component_runtime_js.start(
    document: document,
    root: watershed.root_typed(document),
    field: workspace_field(),
    store: store,
    catalog: catalog,
    context_for: fn(entry, _, _, output) {
      Context(entry.instance_id, starts, stops, output)
    },
    scheduler: sluice_js.scheduler(sluice),
    on_change: fn() { Nil },
    on_report: fn(_) { Nil },
  )
}

@target(javascript)
pub fn nested_commands_are_rejected_before_the_action_runs_test() -> Nil {
  let #(_, _, runtime, _, _, _) = started_runtime("nested-command")
  let nested_results = transport_js.new_cell([])
  let nested_calls = transport_js.new_cell([])
  list.each(["tasks", "notes"], fn(target) {
    component_runtime_js.command(runtime, "tasks", fn(running) {
      record(
        nested_results,
        component_runtime_js.command(runtime, target, fn(inner) {
          record(nested_calls, "called")
          Ok(#(inner, []))
        }),
      )
      component_runtime_js.running(runtime, "tasks") |> expect.to_be_ok()
      component_runtime_js.layout(runtime)
      |> expect.to_equal(["tasks", "notes", "activity"])
      component_runtime_js.lifecycle(runtime)
      |> list.length
      |> expect.to_equal(3)
      let assert Some(_) = component_runtime_js.graph(runtime)
      Ok(#(running, []))
    })
    |> expect.to_equal(Ok(Nil))
  })
  transport_js.get_cell(nested_results)
  |> list.all(fn(outcome) { outcome == Error(component_runtime_js.RuntimeBusy) })
  |> expect.to_equal(True)
  transport_js.get_cell(nested_calls) |> expect.to_equal([])
  component_runtime_js.command(runtime, "notes", fn(running) {
    Ok(#(running, []))
  })
  |> expect.to_equal(Ok(Nil))
}

@target(javascript)
pub fn nested_input_and_report_commands_are_rejected_test() -> Nil {
  let reference = transport_js.new_cell(None)
  let results = transport_js.new_cell([])
  let calls = transport_js.new_cell([])
  let nested = fn() {
    let assert Some(runtime) = transport_js.get_cell(reference)
    record(
      results,
      component_runtime_js.command(runtime, "notes", fn(running) {
        record(calls, "called")
        Ok(#(running, []))
      }),
    )
  }
  let #(sluice, _, runtime, _, _, _) =
    started_runtime_with_hooks("nested-delivery", nested, fn() { Nil }, fn(_) {
      nested()
    })
  transport_js.set_cell(reference, Some(runtime))
  component_runtime_js.command(runtime, "tasks", fn(running) {
    Ok(#(running, [component.emit(selected_output(), "outer")]))
  })
  |> expect.to_equal(Ok(Nil))
  let assert Ok(Notes(Some("outer"), _)) =
    component_runtime_js.running(runtime, "notes")
  let assert Ok(Tasks(_, output)) =
    component_runtime_js.running(runtime, "tasks")
  component.publish(output, [component.emit(selected_output(), "async")])
  sluice_js.advance(sluice, 0)
  let assert Ok(Notes(Some("async"), _)) =
    component_runtime_js.running(runtime, "notes")
  transport_js.get_cell(results) |> list.length |> expect.to_equal(6)
  transport_js.get_cell(results)
  |> list.all(fn(outcome) { outcome == Error(component_runtime_js.RuntimeBusy) })
  |> expect.to_equal(True)
  transport_js.get_cell(calls) |> expect.to_equal([])
  component_runtime_js.command(runtime, "notes", fn(running) {
    Ok(#(running, []))
  })
  |> expect.to_equal(Ok(Nil))
}

@target(javascript)
pub fn stop_is_terminal_before_cleanup_and_reentrant_stop_test() -> Nil {
  let reference = transport_js.new_cell(None)
  let cleanup_calls = transport_js.new_cell([])
  let results = transport_js.new_cell([])
  let #(sluice, _, runtime, _, stops, reports) =
    started_runtime_with_hooks(
      "nested-stop",
      fn() { Nil },
      fn() {
        let assert Some(runtime) = transport_js.get_cell(reference)
        record(cleanup_calls, "cleanup")
        record(
          results,
          component_runtime_js.command(runtime, "tasks", fn(running) {
            Ok(#(running, []))
          }),
        )
        // Limit recursion so the regression fails without exhausting the stack.
        case transport_js.get_cell(cleanup_calls) {
          [_] -> component_runtime_js.stop(runtime) |> expect.to_equal([])
          _ -> Nil
        }
      },
      fn(_) { Nil },
    )
  transport_js.set_cell(reference, Some(runtime))
  let assert Ok(Tasks(_, output)) =
    component_runtime_js.running(runtime, "tasks")
  component_runtime_js.stop(runtime) |> expect.to_equal([])
  transport_js.get_cell(cleanup_calls) |> expect.to_equal(["cleanup"])
  transport_js.get_cell(results)
  |> list.all(fn(outcome) {
    outcome == Error(component_runtime_js.RuntimeStopped)
  })
  |> expect.to_equal(True)
  transport_js.get_cell(stops)
  |> list.sort(string.compare)
  |> expect.to_equal(["activity", "notes", "tasks"])
  component.publish(output, [component.emit(selected_output(), "stopped")])
  sluice_js.advance(sluice, 0)
  transport_js.get_cell(reports) |> expect.to_equal([])
}

@target(javascript)
pub fn stop_during_action_cannot_restore_instances_test() -> Nil {
  let #(sluice, _, runtime, _, stops, reports) = started_runtime("stop-action")
  component_runtime_js.command(runtime, "tasks", fn(running) {
    component_runtime_js.stop(runtime) |> expect.to_equal([])
    Ok(#(running, [component.emit(selected_output(), "stopped")]))
  })
  |> expect.to_equal(Error(component_runtime_js.RuntimeStopped))
  component_runtime_js.running(runtime, "tasks") |> expect.to_be_error()
  component_runtime_js.lifecycle(runtime) |> expect.to_equal([])
  sluice_js.advance(sluice, 0)
  transport_js.get_cell(reports) |> expect.to_equal([])
  transport_js.get_cell(stops) |> list.length |> expect.to_equal(3)
  component_runtime_js.command(runtime, "tasks", fn(running) {
    Ok(#(running, []))
  })
  |> expect.to_equal(Error(component_runtime_js.RuntimeStopped))
  Nil
}

@target(javascript)
pub fn stop_during_input_or_report_prevents_later_deliveries_test() -> Nil {
  list.each([True, False], fn(stop_in_input) {
    let reference = transport_js.new_cell(None)
    let stop = fn() {
      let assert Some(runtime) = transport_js.get_cell(reference)
      let _ = component_runtime_js.stop(runtime)
      Nil
    }
    let #(_, _, runtime, _, stops, reports) =
      started_runtime_with_hooks(
        "stop-delivery",
        fn() {
          case stop_in_input {
            True -> stop()
            False -> Nil
          }
        },
        fn() { Nil },
        fn(_) {
          case stop_in_input {
            False -> stop()
            True -> Nil
          }
        },
      )
    transport_js.set_cell(reference, Some(runtime))
    component_runtime_js.command(runtime, "tasks", fn(running) {
      Ok(
        #(running, [
          component.emit(selected_output(), "stopped"),
          component.emit(completed_output(), "not-delivered"),
        ]),
      )
    })
    |> expect.to_equal(Error(component_runtime_js.RuntimeStopped))
    component_runtime_js.running(runtime, "notes") |> expect.to_be_error()
    component_runtime_js.running(runtime, "activity") |> expect.to_be_error()
    transport_js.get_cell(stops) |> list.length |> expect.to_equal(3)
    transport_js.get_cell(reports) |> list.length |> expect.to_equal(1)
  })
}

@target(javascript)
pub fn rejected_commands_release_execution_ownership_test() -> Nil {
  let #(_, _, runtime, _, _, _) = started_runtime("command-errors")
  component_runtime_js.command(runtime, "missing", fn(running) {
    Ok(#(running, []))
  })
  |> expect.to_be_error()
  component_runtime_js.command(runtime, "tasks", fn(_) { Error("rejected") })
  |> expect.to_be_error()
  component_runtime_js.command(runtime, "tasks", fn(running) {
    Ok(#(running, [component.emit(undeclared_output(), "invalid")]))
  })
  |> expect.to_be_error()
  component_runtime_js.command(runtime, "tasks", fn(running) {
    Ok(#(running, []))
  })
  |> expect.to_equal(Ok(Nil))
}

@target(javascript)
type DeferredRuntime {
  DeferredRuntime(
    sluice: sluice_js.Sluice,
    store: workspace_js.Workspace(Root),
    catalog: component.Catalog(Context, Running),
    runtime: component_runtime_js.Runtime(Root, Context, Running),
    done: fn(Result(Running, String)) -> Nil,
    output: component.OutputEmitter,
    stops: Cell(List(String)),
    reports: Cell(List(component_runtime_js.DispatchReport)),
  )
}

@target(javascript)
fn deferred_runtime(name: String) -> DeferredRuntime {
  let sluice = sluice_js.start(tenant: "default", document: name)
  let document = sluice_js.connect(sluice, "user-a")
  sluice_js.settle(sluice)
  let store = ensure_workspace(document)
  let starts = transport_js.new_cell([])
  let stops = transport_js.new_cell([])
  let reports = transport_js.new_cell([])
  let deferred = transport_js.new_cell(None)
  let emitter = transport_js.new_cell(None)
  let descriptor =
    component.executable_descriptor(
      kind: "delayed",
      version: 1,
      config_decoder: decode.string,
      start: fn(context: Context, _, done) {
        transport_js.set_cell(deferred, Some(done))
        transport_js.set_cell(emitter, Some(context.output))
      },
      inputs: [],
      stop: stop_running,
      ports: [port.output_descriptor(selected_output())],
    )
  let assert Ok(catalog) = component.register(catalog(), descriptor)
  list.each(["tasks", "notes", "delayed"], fn(id) {
    let assert Ok(_) =
      workspace_js.add_instance(store, catalog, id, id, 1, json.string(id))
    Nil
  })
  let assert Ok(_) =
    workspace_js.add_connection(
      store,
      catalog,
      port_graph.connection(
        "delayed-focus",
        port_graph.PortRef("delayed", "selected"),
        port_graph.PortRef("notes", "focus"),
      ),
    )
  let runtime =
    component_runtime_js.start(
      document: document,
      root: watershed.root_typed(document),
      field: workspace_field(),
      store: store,
      catalog: catalog,
      context_for: fn(entry, _, _, output) {
        Context(entry.instance_id, starts, stops, output)
      },
      scheduler: sluice_js.scheduler(sluice),
      on_change: fn() { Nil },
      on_report: fn(report) { record(reports, report) },
    )
  sluice_js.advance(sluice, 0)
  let assert Some(done) = transport_js.get_cell(deferred)
  let assert Some(output) = transport_js.get_cell(emitter)
  DeferredRuntime(sluice, store, catalog, runtime, done, output, stops, reports)
}

@target(javascript)
pub fn external_start_completion_waits_for_the_current_command_test() -> Nil {
  let fixture = deferred_runtime("deferred-ownership")
  component_runtime_js.command(fixture.runtime, "tasks", fn(running) {
    fixture.done(Ok(Delayed(fixture.stops)))
    component_runtime_js.running(fixture.runtime, "delayed")
    |> expect.to_be_error()
    Ok(#(running, []))
  })
  |> expect.to_equal(Ok(Nil))
  sluice_js.advance(fixture.sluice, 0)
  component_runtime_js.running(fixture.runtime, "delayed") |> expect.to_be_ok()
  Nil
}

@target(javascript)
pub fn deferred_completion_rechecks_shutdown_before_installing_test() -> Nil {
  let fixture = deferred_runtime("deferred-stop")
  component_runtime_js.command(fixture.runtime, "tasks", fn(running) {
    fixture.done(Ok(Delayed(fixture.stops)))
    component_runtime_js.stop(fixture.runtime) |> expect.to_equal([])
    Ok(#(running, []))
  })
  |> expect.to_equal(Error(component_runtime_js.RuntimeStopped))
  sluice_js.advance(fixture.sluice, 0)
  component_runtime_js.running(fixture.runtime, "delayed")
  |> expect.to_be_error()
  transport_js.get_cell(fixture.stops)
  |> list.sort(string.compare)
  |> expect.to_equal(["delayed", "notes", "tasks"])
}

@target(javascript)
pub fn stop_during_reconcile_cleanup_cannot_restart_instances_test() -> Nil {
  let reference = transport_js.new_cell(None)
  let #(sluice, store, runtime, starts, stops, _) =
    started_runtime_with_hooks(
      "stop-reconcile",
      fn() { Nil },
      fn() {
        let assert Some(runtime) = transport_js.get_cell(reference)
        component_runtime_js.stop(runtime) |> expect.to_equal([])
      },
      fn(_) { Nil },
    )
  transport_js.set_cell(reference, Some(runtime))
  let assert Ok(Nil) = workspace_js.delete_instance(store, catalog(), "notes")
  let assert Ok(_) =
    workspace_js.add_instance(
      store,
      catalog(),
      "replacement",
      "notes",
      1,
      json.string("new"),
    )
  sluice_js.advance(sluice, 0)
  component_runtime_js.running(runtime, "replacement") |> expect.to_be_error()
  component_runtime_js.lifecycle(runtime) |> expect.to_equal([])
  transport_js.get_cell(starts) |> list.length |> expect.to_equal(3)
  transport_js.get_cell(stops)
  |> list.sort(string.compare)
  |> expect.to_equal(["activity", "notes", "tasks"])
}
