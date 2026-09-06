@target(javascript)
import gleam/json
@target(javascript)
import gleam/list
@target(javascript)
import gleam/option.{None, Some}
@target(javascript)
import startest/expect
@target(javascript)
import watershed
@target(javascript)
import watershed/runtime
@target(javascript)
import watershed/sluice/frame
@target(javascript)
import watershed/transport_js

@target(javascript)
pub fn inline_join_uses_the_installed_transport_test() -> Nil {
  let pushes = transport_js.new_cell([])
  let document =
    watershed.connect_via(
      tenant: "default",
      document: "inline",
      user_id: "a",
      transport: runtime.Transport(connect: fn(callbacks) {
        callbacks.on_join()
        runtime.TransportHandle(
          push: fn(event, _) {
            transport_js.set_cell(pushes, [
              event,
              ..transport_js.get_cell(pushes)
            ])
          },
          close: fn() { Nil },
          drop: fn() { Nil },
          hold: fn() { Nil },
          resume: fn() { Nil },
        )
      }),
      on_ready: fn(_) { Nil },
    )
  transport_js.get_cell(pushes) |> expect.to_equal(["connect_document"])
  watershed.close(document)
}

@target(javascript)
fn connected(checkpoint: Int) -> String {
  frame.encode_connected(
    client_id: "a",
    tenant_id: "default",
    document_id: "inline",
    scopes: ["doc:read", "doc:write"],
    checkpoint_sequence_number: checkpoint,
    initial_clients: ["a"],
    initial_messages: [],
    timestamp: 0,
    presence_v1: True,
  )
  |> json.to_string
}

@target(javascript)
fn noop(sequence: Int) -> frame.Sequenced {
  frame.Sequenced(
    client_id: None,
    sequence_number: sequence,
    minimum_sequence_number: 0,
    client_sequence_number: -1,
    reference_sequence_number: 0,
    operation_type: "noop",
    contents: json.null(),
    metadata: None,
    timestamp: 0,
    data: None,
  )
}

@target(javascript)
pub fn inline_handshake_and_reconnect_catchup_preserve_responses_test() -> Nil {
  let pushes = transport_js.new_cell([])
  let reference = transport_js.new_cell(None)
  let checkpoint = transport_js.new_cell(0)
  let ready = transport_js.new_cell([])
  let document =
    watershed.connect_via(
      tenant: "default",
      document: "inline",
      user_id: "a",
      transport: runtime.Transport(connect: fn(callbacks) {
        transport_js.set_cell(reference, Some(callbacks))
        callbacks.on_join()
        runtime.TransportHandle(
          push: fn(event, _) {
            transport_js.set_cell(pushes, [
              event,
              ..transport_js.get_cell(pushes)
            ])
            case event {
              "connect_document" ->
                callbacks.on_event(
                  "connect_document_success",
                  connected(transport_js.get_cell(checkpoint)),
                )
              "requestOps" ->
                callbacks.on_event(
                  "op",
                  frame.encode_operation_event([noop(1), noop(2)])
                    |> json.to_string,
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
        transport_js.set_cell(ready, [outcome, ..transport_js.get_cell(ready)])
      },
    )
  transport_js.get_cell(ready) |> expect.to_equal([Ok(Nil)])
  let assert Some(callbacks) = transport_js.get_cell(reference)
  callbacks.on_close()
  transport_js.set_cell(checkpoint, 2)
  callbacks.on_join()
  runtime.diagnostics(watershed.runtime_of(document)).last_seen_sequence_number
  |> expect.to_equal(Some(2))
  runtime.diagnostics(watershed.runtime_of(document)).phase
  |> expect.to_equal("ready")
  transport_js.get_cell(pushes)
  |> list.reverse
  |> expect.to_equal(["connect_document", "connect_document", "requestOps"])
  transport_js.get_cell(ready) |> expect.to_equal([Ok(Nil)])
  watershed.close(document)
}
