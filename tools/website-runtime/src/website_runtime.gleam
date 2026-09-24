//// Internal runtime boundary for the watershed website.

import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some, map}
import gleam/result
import gleam/string
import signet/types as token
import spillway/message
import spillway/types
import watershed
import watershed/channel
import watershed/counter_kernel
import watershed/json_ot
import watershed/or_map_kernel
import watershed/runtime_core
import watershed/wire
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
