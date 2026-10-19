//// Internal runtime boundary for the watershed website.

import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some, map}
import gleam/result
import gleam/string
import shared_tree_checklist_lustre/checklist
import shared_tree_checklist_lustre/schema as checklist_schema
import signet/types as token
import spillway/message
import spillway/types
import watershed
import watershed/channel
import watershed/counter_kernel
import watershed/fluid_ids
import watershed/id
import watershed/json_ot
import watershed/or_map_kernel
import watershed/runtime_core
import watershed/tree as shared_tree
import watershed/tree/error as tree_error
import watershed/tree/schema_builder as builder
import watershed/wire
import watershed/wire/fluid_document
import watershed/wire/fluid_summary

pub opaque type CounterCore {
  CounterCore(core: runtime_core.Core)
}

pub opaque type CounterWrite {
  CounterWrite(outbound: wire.OutboundOperation, contents: Dynamic)
}

pub type CounterChange {
  CounterChange(core: CounterCore, write: CounterWrite)
}

pub type CounterPending {
  CounterPending(count: Int, delta: Int)
}

pub type RegisterEntry {
  RegisterEntry(key: String, value: String)
}

pub type TallyEntry {
  TallyEntry(key: String, value: Int)
}

pub opaque type SharedTreeChecklist {
  SharedTreeChecklist(tree: shared_tree.Tree(checklist.Checklist))
}

pub type SharedTreeChecklistItem {
  SharedTreeChecklistItem(id: String, text: String, completed: Bool)
}

pub fn shared_tree_checklist_seed() -> Result(
  runtime_core.BootstrapSeed,
  String,
) {
  use compiled <- result.try(
    builder.compile(checklist_schema.configuration())
    |> result.map_error(string.inspect),
  )
  use session <- result.try(
    fluid_ids.session_id(id.uuid_v4()) |> result.map_error(string.inspect),
  )
  use view <- result.try(
    fluid_ids.stable_id(id.uuid_v4()) |> result.map_error(string.inspect),
  )
  use initial <- result.try(
    builder.encode_new(
      compiled,
      checklist.Checklist("SharedTree checklist", [
        checklist.Item("inspect-spillway", "inspect spillway", False),
        checklist.Item("review-field-notes", "review field notes", False),
        checklist.Item("publish-survey", "publish survey", False),
      ]),
    )
    |> result.map_error(string.inspect),
  )
  use summary <- result.try(
    fluid_document.initial_tree(
      builder.stored(compiled),
      initial,
      session,
      view,
    )
    |> result.map_error(string.inspect),
  )
  runtime_core.document_seed(summary)
  |> result.map_error(string.inspect)
}

pub fn open_shared_tree_checklist(
  document: watershed.Document(root),
) -> Result(SharedTreeChecklist, String) {
  watershed.open_tree(document, checklist_schema.configuration())
  |> result.map(SharedTreeChecklist)
  |> result.map_error(tree_error.to_string)
}

pub fn shared_tree_checklist_items(
  checklist: SharedTreeChecklist,
) -> Result(List(SharedTreeChecklistItem), String) {
  let SharedTreeChecklist(tree) = checklist
  use decoded <- result.try(
    shared_tree.read_root(tree)
    |> result.map_error(tree_error.to_string),
  )
  let checklist.Checklist(items: items, ..) = decoded
  Ok(
    list.map(items, fn(item) {
      SharedTreeChecklistItem(item.id, item.text, item.completed)
    }),
  )
}

pub fn shared_tree_checklist_add(
  checklist: SharedTreeChecklist,
  id: String,
  text: String,
) -> Result(Nil, String) {
  let SharedTreeChecklist(tree) = checklist
  use item <- result.try(checklist.new_item(id, text, False))
  use #(_, items, nodes) <- result.try(checklist_state(tree))
  shared_tree.array_insert(items, list.length(nodes), [item])
  |> result.map_error(tree_error.to_string)
}

pub fn shared_tree_checklist_edit(
  checklist: SharedTreeChecklist,
  id: String,
  text: String,
) -> Result(Nil, String) {
  let SharedTreeChecklist(tree) = checklist
  use #(node, _, _, _) <- result.try(checklist_target(tree, id))
  use text <- result.try(checklist.normalize_text(text))
  shared_tree.set(node, checklist_schema.text(), text)
  |> result.map_error(tree_error.to_string)
}

pub fn shared_tree_checklist_toggle(
  checklist: SharedTreeChecklist,
  id: String,
) -> Result(Nil, String) {
  let SharedTreeChecklist(tree) = checklist
  use #(node, item, _, _) <- result.try(checklist_target(tree, id))
  shared_tree.set(node, checklist_schema.completed(), !item.completed)
  |> result.map_error(tree_error.to_string)
}

pub fn shared_tree_checklist_move_up(
  checklist: SharedTreeChecklist,
  id: String,
) -> Result(Nil, String) {
  let SharedTreeChecklist(tree) = checklist
  use #(node, _, previous, _) <- result.try(checklist_target(tree, id))
  case previous {
    None -> Ok(Nil)
    Some(previous) -> {
      use #(_, items, _) <- result.try(checklist_state(tree))
      shared_tree.array_move_before(items, node, items, Some(previous))
      |> result.map_error(tree_error.to_string)
    }
  }
}

pub fn shared_tree_checklist_move_down(
  checklist: SharedTreeChecklist,
  id: String,
) -> Result(Nil, String) {
  let SharedTreeChecklist(tree) = checklist
  use #(node, _, _, following) <- result.try(checklist_target(tree, id))
  case following {
    [] -> Ok(Nil)
    [_next, ..after] -> {
      use #(_, items, _) <- result.try(checklist_state(tree))
      let before = case list.first(after) {
        Ok(node) -> Some(node)
        Error(Nil) -> None
      }
      shared_tree.array_move_before(items, node, items, before)
      |> result.map_error(tree_error.to_string)
    }
  }
}

fn checklist_state(
  tree: shared_tree.Tree(checklist.Checklist),
) -> Result(
  #(
    checklist.Checklist,
    shared_tree.Ref(List(checklist.Item)),
    List(shared_tree.Ref(checklist.Item)),
  ),
  String,
) {
  use decoded <- result.try(
    shared_tree.read_root(tree)
    |> result.map_error(tree_error.to_string),
  )
  use root <- result.try(
    shared_tree.required_root(tree)
    |> result.map_error(tree_error.to_string),
  )
  use items <- result.try(
    shared_tree.child(root, checklist_schema.items())
    |> result.map_error(tree_error.to_string),
  )
  use nodes <- result.try(
    checklist.nodes(items)
    |> result.map_error(tree_error.to_string),
  )
  let checklist.Checklist(items: snapshots, ..) = decoded
  use nodes <- result.try(reconcile_checklist_nodes(snapshots, nodes))
  Ok(#(decoded, items, nodes))
}

fn reconcile_checklist_nodes(
  snapshots: List(checklist.Item),
  nodes: List(shared_tree.Ref(checklist.Item)),
) -> Result(List(shared_tree.Ref(checklist.Item)), String) {
  case snapshots {
    [] ->
      case nodes {
        [] -> Ok([])
        _ -> Error("SharedTree checklist changed while it was read")
      }
    [snapshot, ..rest] -> {
      use node <- result.try(find_checklist_node(snapshot, nodes))
      use reconciled <- result.try(reconcile_checklist_nodes(
        rest,
        list.filter(nodes, fn(candidate) { candidate != node }),
      ))
      Ok([node, ..reconciled])
    }
  }
}

fn find_checklist_node(
  snapshot: checklist.Item,
  nodes: List(shared_tree.Ref(checklist.Item)),
) -> Result(shared_tree.Ref(checklist.Item), String) {
  case nodes {
    [] -> Error("SharedTree checklist changed while it was read")
    [node, ..rest] -> {
      use value <- result.try(
        shared_tree.read(node)
        |> result.map_error(tree_error.to_string),
      )
      case value.id == snapshot.id {
        True ->
          case value == snapshot {
            True -> Ok(node)
            False -> Error("SharedTree checklist changed while it was read")
          }
        False -> find_checklist_node(snapshot, rest)
      }
    }
  }
}

fn checklist_target(
  tree: shared_tree.Tree(checklist.Checklist),
  id: String,
) -> Result(
  #(
    shared_tree.Ref(checklist.Item),
    checklist.Item,
    Option(shared_tree.Ref(checklist.Item)),
    List(shared_tree.Ref(checklist.Item)),
  ),
  String,
) {
  use #(decoded, _, nodes) <- result.try(checklist_state(tree))
  let checklist.Checklist(items: snapshots, ..) = decoded
  find_checklist_target(snapshots, nodes, id, None)
}

fn find_checklist_target(
  snapshots: List(checklist.Item),
  nodes: List(shared_tree.Ref(checklist.Item)),
  id: String,
  previous: Option(shared_tree.Ref(checklist.Item)),
) -> Result(
  #(
    shared_tree.Ref(checklist.Item),
    checklist.Item,
    Option(shared_tree.Ref(checklist.Item)),
    List(shared_tree.Ref(checklist.Item)),
  ),
  String,
) {
  case snapshots, nodes {
    [snapshot, ..snapshot_rest], [node, ..node_rest] ->
      case snapshot.id == id {
        True -> Ok(#(node, snapshot, previous, node_rest))
        False -> find_checklist_target(snapshot_rest, node_rest, id, Some(node))
      }
    _, _ -> Error("checklist item " <> id <> " is no longer present")
  }
}

pub fn json_ot_parse(raw: String) -> Result(json_ot.JsonValue, String) {
  json_ot.parse_json(raw)
  |> result.map_error(fn(_) { "invalid JSON" })
}

pub fn json_ot_stringify(value: json_ot.JsonValue) -> String {
  value
  |> json_ot.to_json
  |> json.to_string
}

pub fn json_ot_key(key: String) -> json_ot.PathKey {
  json_ot.Key(key)
}

pub fn json_ot_index(index: Int) -> json_ot.PathKey {
  json_ot.Index(index)
}

pub fn json_ot_integer(value: Int) -> json_ot.Number {
  json_ot.NInt(value)
}

pub fn json_ot_key_value(path_key: json_ot.PathKey) -> Result(String, String) {
  case path_key {
    json_ot.Key(value) -> Ok(value)
    json_ot.Index(_) -> Error("JSON-OT path is not an object key")
  }
}

pub fn json_ot_index_value(path_key: json_ot.PathKey) -> Result(Int, String) {
  case path_key {
    json_ot.Index(value) -> Ok(value)
    json_ot.Key(_) -> Error("JSON-OT path is not an array index")
  }
}

pub fn json_ot_integer_value(number: json_ot.Number) -> Result(Int, String) {
  case number {
    json_ot.NInt(value) -> Ok(value)
    json_ot.NFloat(_) -> Error("JSON-OT number is not an integer")
  }
}

pub fn create_register_or_map(
  document: watershed.Document(root),
) -> Result(watershed.OrMap, String) {
  watershed.create_or_map(document, or_map_kernel.RegisterMode)
}

pub fn create_tally_or_map(
  document: watershed.Document(root),
) -> Result(watershed.OrMap, String) {
  watershed.create_or_map(document, or_map_kernel.TallyMode)
}

pub fn register_entries(
  or_map: watershed.OrMap,
) -> Result(List(#(String, String)), String) {
  decode_register_entries(watershed.or_map_entries(or_map))
}

pub fn tally_entries(
  or_map: watershed.OrMap,
) -> Result(List(#(String, Int)), String) {
  decode_tally_entries(watershed.or_map_entries(or_map))
}

pub fn read_register_entry(entry: #(String, String)) -> RegisterEntry {
  RegisterEntry(key: entry.0, value: entry.1)
}

pub fn read_tally_entry(entry: #(String, Int)) -> TallyEntry {
  TallyEntry(key: entry.0, value: entry.1)
}

pub fn counter_core(
  client_id: String,
  address: String,
  initial_value: Int,
) -> Result(CounterCore, String) {
  let summary =
    runtime_core.Summary(
      sequence_number: 0,
      channels: [
        #("watershed/root", channel.MapSnapshot([])),
        #(counter_address(address), channel.CounterSnapshot(initial_value)),
      ],
      members: [],
    )
  let connected =
    message.ConnectedMessage(
      claims: token.TokenClaims(
        document_id: "demo",
        scopes: [token.DocRead, token.DocWrite],
        tenant_id: "demo",
        user: token.User(id: "demo-user", properties: dict.new()),
        issued_at: 0,
        expiration: 0,
        version: "1.0",
        jti: None,
      ),
      client_id: client_id,
      existing: True,
      max_message_size: 16_000,
      mode: types.WriteMode,
      service_configuration: types.ServiceConfiguration(
        block_size: 65_536,
        max_message_size: 16_000,
        noop_time_frequency: None,
        noop_count_frequency: None,
      ),
      initial_clients: [],
      initial_messages: [],
      initial_signals: [],
      supported_versions: ["^0.1.0"],
      supported_features: dict.new(),
      version: "^0.1.0",
      timestamp: None,
      checkpoint_sequence_number: Some(0),
      epoch: None,
      relay_service_agent: None,
      summary_context: None,
    )

  case runtime_core.bootstrap(connected, Some(summary)) {
    Ok(runtime_core.Complete(core)) -> Ok(CounterCore(core))
    Ok(runtime_core.MissingPrefix(..)) ->
      Error("counter runtime bootstrap requested catch-up")
    Error(error) -> Error(string.inspect(error))
  }
}

pub fn counter_increment(
  core: CounterCore,
  address: String,
  amount: Int,
) -> Result(CounterChange, String) {
  let CounterCore(core) = core
  case runtime_core.increment(core, counter_address(address), amount) {
    Ok(#(core, _events, [outbound])) ->
      Ok(CounterChange(
        CounterCore(core),
        CounterWrite(outbound, json_to_dynamic(outbound.contents)),
      ))
    Ok(#(_, _, _)) -> Error("counter increment produced no outbound operation")
    Error(error) -> Error(string.inspect(error))
  }
}

pub fn counter_pending(core: CounterCore, address: String) -> CounterPending {
  let CounterCore(core) = core
  let address = counter_address(address)
  let pending_items =
    list.flat_map(core.in_flight, fn(entry) {
      case entry {
        runtime_core.InFlightBatch(pending: items, ..) -> items
        entry -> [entry]
      }
    })
  let #(count, delta) =
    list.fold(pending_items, #(0, 0), fn(pending, entry) {
      case entry {
        runtime_core.InFlightOperation(
          address: entry_address,
          operation: channel.CounterOperation(counter_kernel.Increment(amount)),
          ..,
        )
          if entry_address == address
        -> #(pending.0 + 1, pending.1 + amount)
        _ -> pending
      }
    })
  CounterPending(count, delta)
}

pub fn counter_value(
  core: CounterCore,
  address: String,
) -> Result(Int, String) {
  let CounterCore(core) = core
  runtime_core.counter_value(core, counter_address(address))
  |> result.map_error(string.inspect)
}

fn counter_address(id: String) -> String {
  "watershed/" <> fluid_summary.encode_component(id)
}

pub fn deliver_counter(
  core: CounterCore,
  client_id: String,
  sequence_number: Int,
  write: CounterWrite,
) -> Result(CounterCore, String) {
  let CounterCore(core) = core
  let CounterWrite(outbound, contents) = write
  let sequenced =
    types.SequencedDocumentMessage(
      client_id: Some(client_id),
      sequence_number: sequence_number,
      minimum_sequence_number: 0,
      client_sequence_number: outbound.client_sequence_number,
      reference_sequence_number: outbound.reference_sequence_number,
      message_type: outbound.operation_type,
      contents: contents,
      metadata: map(outbound.metadata, json_to_dynamic),
      server_metadata: None,
      origin: None,
      traces: None,
      timestamp: 0,
      data: None,
    )
  case runtime_core.handle_sequenced(core, sequenced) {
    Ok(#(core, _ingested)) -> Ok(CounterCore(core))
    Error(error) -> Error(string.inspect(error))
  }
}

fn json_to_dynamic(value: json.Json) -> Dynamic {
  let assert Ok(dynamic) = json.parse(json.to_string(value), decode.dynamic)
  dynamic
}

fn decode_register_entries(
  entries: List(#(String, or_map_kernel.OrMapValue)),
) -> Result(List(#(String, String)), String) {
  case entries {
    [] -> Ok([])
    [#(key, value), ..rest] ->
      case value {
        or_map_kernel.Register(value) -> {
          use rest <- result.try(decode_register_entries(rest))
          Ok([#(key, value), ..rest])
        }
        or_map_kernel.Tally(_) ->
          Error("register OR-map contains tally value at key: " <> key)
        or_map_kernel.SetMembers(_) ->
          Error("register OR-map contains set value at key: " <> key)
        or_map_kernel.MvRegister(_) ->
          Error("register OR-map contains MV-register value at key: " <> key)
      }
  }
}

fn decode_tally_entries(
  entries: List(#(String, or_map_kernel.OrMapValue)),
) -> Result(List(#(String, Int)), String) {
  case entries {
    [] -> Ok([])
    [#(key, value), ..rest] ->
      case value {
        or_map_kernel.Tally(value) -> {
          use rest <- result.try(decode_tally_entries(rest))
          Ok([#(key, value), ..rest])
        }
        or_map_kernel.Register(_) ->
          Error("tally OR-map contains register value at key: " <> key)
        or_map_kernel.SetMembers(_) ->
          Error("tally OR-map contains set value at key: " <> key)
        or_map_kernel.MvRegister(_) ->
          Error("tally OR-map contains MV-register value at key: " <> key)
      }
  }
}
