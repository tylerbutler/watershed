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
import watershed/channel
import watershed/counter_kernel
import watershed/runtime_core
import watershed/wire

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

pub fn counter_core(
  client_id: String,
  address: String,
  initial_value: Int,
) -> Result(CounterCore, String) {
  let summary =
    runtime_core.Summary(
      sequence_number: 0,
      channels: [#(address, channel.CounterSnapshot(initial_value))],
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
  case runtime_core.increment(core, address, amount) {
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
  let #(count, delta) =
    list.fold(core.in_flight, #(0, 0), fn(pending, entry) {
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
  runtime_core.counter_value(core, address)
  |> result.map_error(string.inspect)
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
