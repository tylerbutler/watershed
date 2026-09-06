@target(javascript)
import gleam/dict
@target(javascript)
import gleam/dynamic/decode
@target(javascript)
import gleam/javascript/promise.{type Promise}
@target(javascript)
import gleam/json
@target(javascript)
import gleam/option.{None, Some}
@target(javascript)
import gleam/result
@target(javascript)
import signet/types as token
@target(javascript)
import spillway/message
@target(javascript)
import spillway/types
@target(javascript)
import watershed/channel
@target(javascript)
import watershed/map_kernel
@target(javascript)
import watershed/runtime
@target(javascript)
import watershed/sluice/frame
@target(javascript)
import watershed/transport_js
@target(javascript)
import watershed/wire
@target(javascript)
import watershed/wire/op
@target(javascript)
import watershed/wire/summary_blob

@target(javascript)
pub type Fixture {
  Fixture(
    connect: fn(Bool, Int, Int) -> Nil,
    receive: fn(String) -> Nil,
    disconnect: fn() -> Nil,
    close: fn() -> Nil,
    ready: fn() -> Int,
    failure: fn() -> String,
    failures: fn() -> Int,
    value: fn() -> String,
    sequence: fn() -> Int,
    changes: fn() -> Int,
    requests: fn() -> Int,
  )
}

@target(javascript)
fn operation(sequence: Int, value: String) -> frame.Sequenced {
  frame.Sequenced(
    client_id: Some("other"),
    sequence_number: sequence,
    minimum_sequence_number: 0,
    client_sequence_number: sequence,
    reference_sequence_number: 0,
    operation_type: "op",
    contents: op.encode_map_envelope(
      "root",
      map_kernel.Set("value", json.string(value)),
    ),
    metadata: None,
    timestamp: 0,
    data: None,
  )
}

@target(javascript)
fn make_fixture() -> Fixture {
  let callbacks = transport_js.new_cell(None)
  let ready = transport_js.new_cell(0)
  let failure = transport_js.new_cell("")
  let failures = transport_js.new_cell(0)
  let changes = transport_js.new_cell(0)
  let requests = transport_js.new_cell(0)
  let runtime =
    runtime.start_with_transport(
      http_base_url: "https://bootstrap.invalid",
      connect_message: message.ConnectMessage(
        tenant_id: "test",
        document_id: "bootstrap",
        token: Some("fixture-only"),
        client: types.Client(
          mode: types.WriteMode,
          details: types.ClientDetails(
            capabilities: types.ClientCapabilities(interactive: True),
            client_type: None,
            environment: None,
            device: None,
          ),
          permission: [],
          user: token.User("reader", dict.new()),
          scopes: ["doc:read"],
          timestamp: None,
        ),
        versions: ["^0.1.0"],
        driver_version: None,
        mode: types.WriteMode,
        nonce: None,
        epoch: None,
        supported_features: None,
        relay_user_agent: None,
      ),
      transport: runtime.Transport(connect: fn(handlers) {
        transport_js.set_cell(callbacks, Some(handlers))
        runtime.TransportHandle(
          push: fn(event, _) {
            case event {
              "requestOps" ->
                transport_js.set_cell(
                  requests,
                  transport_js.get_cell(requests) + 1,
                )
              _ -> Nil
            }
          },
          close: fn() { Nil },
          drop: fn() { Nil },
          hold: fn() { Nil },
          resume: fn() { Nil },
        )
      }),
      on_ready: fn(outcome) {
        case outcome {
          Ok(Nil) ->
            transport_js.set_cell(ready, transport_js.get_cell(ready) + 1)
          Error(reason) -> {
            transport_js.set_cell(failure, reason)
            transport_js.set_cell(failures, transport_js.get_cell(failures) + 1)
          }
        }
      },
    )
  let _subscription =
    runtime.subscribe(runtime, "root", fn(_) {
      transport_js.set_cell(changes, transport_js.get_cell(changes) + 1)
    })
  let assert Some(callbacks) = transport_js.get_cell(callbacks)
  Fixture(
    connect: fn(summary, checkpoint, initial_sequence) {
      callbacks.on_join()
      let initial = case initial_sequence {
        0 -> []
        sequence -> [operation(sequence, "initial")]
      }
      let encoded =
        frame.encode_connected(
          client_id: "reader",
          tenant_id: "test",
          document_id: "bootstrap",
          scopes: ["doc:read"],
          checkpoint_sequence_number: checkpoint,
          initial_clients: ["reader", "other"],
          initial_messages: initial,
          timestamp: 0,
          presence_v1: False,
        )
      let assert Ok(fields) =
        json.parse(
          json.to_string(encoded),
          decode.dict(decode.string, wire.json_value_decoder()),
        )
      let fields = case summary {
        True ->
          dict.insert(
            fields,
            "summaryContext",
            json.object([
              #("handle", json.string("tree-1")),
              #("sequenceNumber", json.int(1)),
            ]),
          )
        False -> fields
      }
      callbacks.on_event(
        "connect_document_success",
        fields |> dict.to_list |> json.object |> json.to_string,
      )
    },
    receive: fn(raw) { callbacks.on_event("op", raw) },
    disconnect: callbacks.on_close,
    close: fn() { runtime.close(runtime) },
    ready: fn() { transport_js.get_cell(ready) },
    failure: fn() { transport_js.get_cell(failure) },
    failures: fn() { transport_js.get_cell(failures) },
    value: fn() {
      runtime.get(runtime, "root", "value")
      |> result.try(fn(value) {
        json.parse(json.to_string(value), decode.string)
        |> result.replace_error(Nil)
      })
      |> result.unwrap("")
    },
    sequence: fn() {
      case runtime.diagnostics(runtime).last_seen_sequence_number {
        Some(sequence) -> sequence
        None -> -1
      }
    },
    changes: fn() { transport_js.get_cell(changes) },
    requests: fn() { transport_js.get_cell(requests) },
  )
}

@target(javascript)
@external(javascript, "./runtime_bootstrap_ffi.mjs", "run")
fn run_ffi(
  make_fixture: fn() -> Fixture,
  summary: String,
  operation: fn(Int, String) -> String,
) -> Promise(Nil)

@target(javascript)
pub fn run() -> Promise(Nil) {
  run_ffi(
    make_fixture,
    summary_blob.encode_channels(1, [], [
      #("root", channel.MapSnapshot([#("value", json.string("summary"))])),
    ])
      |> json.to_string,
    fn(sequence, value) {
      operation(sequence, value) |> frame.encode_sequenced |> json.to_string
    },
  )
}
