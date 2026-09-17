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
import watershed/map_kernel
@target(javascript)
import watershed/ordered_collection_kernel
@target(javascript)
import watershed/runtime
@target(javascript)
import watershed/sluice/frame
@target(javascript)
import watershed/sluice_js
@target(javascript)
import watershed/transport_js
@target(javascript)
import watershed/wire/op

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

@target(javascript)
@external(javascript, "./callback_test_ffi.mjs", "withReporter")
fn with_reporter(
  fallback: Bool,
  work: fn(fn() -> Int, fn() -> String) -> Nil,
) -> Nil

@target(javascript)
fn manual_runtime(
  on_ready: fn(Result(Nil, String)) -> Nil,
) -> #(
  runtime.Runtime,
  runtime.TransportCallbacks,
  transport_js.Cell(List(String)),
) {
  let reference = transport_js.new_cell(None)
  let pushes = transport_js.new_cell([])
  let document =
    watershed.connect_via(
      tenant: "default",
      document: "inline",
      user_id: "a",
      transport: runtime.Transport(connect: fn(callbacks) {
        transport_js.set_cell(reference, Some(callbacks))
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
      on_ready: on_ready,
    )
  let assert Some(callbacks) = transport_js.get_cell(reference)
  #(watershed.runtime_of(document), callbacks, pushes)
}

@target(javascript)
pub fn a_throwing_subscriber_cannot_skip_other_observers_or_gap_requests_test() -> Nil {
  use count, _ <- with_reporter(False)
  let #(owner, callbacks, pushes) = manual_runtime(fn(_) { Nil })
  callbacks.on_event("connect_document_success", connected(0))
  let seen = transport_js.new_cell([])
  let _good =
    runtime.subscribe(owner, "root", fn(_) {
      transport_js.set_cell(seen, [
        runtime.get(owner, "root", "value"),
        ..transport_js.get_cell(seen)
      ])
    })
  let _bad =
    runtime.subscribe(owner, "root", fn(_) { panic as "subscriber fault" })
  let first =
    frame.Sequenced(
      ..noop(1),
      client_id: Some("other"),
      operation_type: "op",
      contents: op.encode_map_envelope(
        "root",
        map_kernel.Set("value", json.int(1)),
      ),
    )
  callbacks.on_event(
    "op",
    frame.encode_operation_event([first, noop(3)]) |> json.to_string,
  )
  transport_js.get_cell(seen) |> expect.to_equal([Ok(json.int(1))])
  transport_js.get_cell(pushes) |> expect.to_equal(["requestOps"])
  count() |> expect.to_equal(1)
  callbacks.on_event(
    "op",
    frame.encode_operation_event([noop(2)]) |> json.to_string,
  )
  runtime.diagnostics(owner).last_seen_sequence_number
  |> expect.to_equal(Some(3))
  runtime.close(owner)
}

@target(javascript)
pub fn throwing_ready_presence_and_ripple_observers_do_not_stop_the_session_test() -> Nil {
  use count, _ <- with_reporter(False)
  let #(owner, callbacks, _) = manual_runtime(fn(_) { panic as "ready fault" })
  let presence = transport_js.new_cell([])
  let ripples = transport_js.new_cell([])
  runtime.subscribe_presence(owner, fn(frame) {
    transport_js.set_cell(presence, [frame, ..transport_js.get_cell(presence)])
  })
  runtime.subscribe_presence(owner, fn(_) { panic as "presence fault" })
  runtime.subscribe_ripples(owner, fn(_) {
    transport_js.set_cell(ripples, ["received"])
  })
  runtime.subscribe_ripples(owner, fn(_) { panic as "ripple fault" })
  callbacks.on_event("connect_document_success", connected(0))
  transport_js.get_cell(presence)
  |> expect.to_equal([runtime.PresenceSession("a", True)])
  callbacks.on_event(
    "signal",
    frame.encode_signal("other", json.string("hello")) |> json.to_string,
  )
  transport_js.get_cell(ripples) |> expect.to_equal(["received"])
  callbacks.on_event("connect_document_success", connected(0))
  count() |> expect.to_equal(3)
  runtime.diagnostics(owner).phase |> expect.to_equal("ready")
  runtime.close(owner)
}

@target(javascript)
pub fn throwing_pact_observer_cannot_skip_outbound_signoffs_test() -> Nil {
  use count, _ <- with_reporter(False)
  let sluice = sluice_js.start(tenant: "default", document: "throw-pact")
  let a = sluice_js.connect(sluice, "a")
  let b = sluice_js.connect(sluice, "b")
  sluice_js.settle(sluice)
  let assert Ok(pact_a) = watershed.create_pact_map(a)
  watershed.set(watershed.root(a), "pact", watershed.pact_map_handle_of(pact_a))
  sluice_js.settle(sluice)
  let assert Ok(handle) = watershed.get(watershed.root(b), "pact")
  let assert Ok(pact_b) = watershed.resolve_pact_map(b, handle)
  watershed.subscribe_pact_map(pact_b, fn(_) { panic as "pact observer fault" })
  watershed.pact_map_set(pact_a, "agreement", json.string("accepted"))
  sluice_js.settle(sluice)
  watershed.pact_map_get(pact_a, "agreement")
  |> expect.to_equal(Ok(json.string("accepted")))
  watershed.pact_map_get(pact_b, "agreement")
  |> expect.to_equal(Ok(json.string("accepted")))
  count() |> expect.to_equal(2)
  watershed.close(a)
  watershed.close(b)
}

@target(javascript)
pub fn immediate_acquire_callback_cannot_resurrect_a_closed_runtime_test() -> Nil {
  let #(owner, callbacks, _) = manual_runtime(fn(_) { Nil })
  callbacks.on_event("connect_document_success", connected(0))
  let assert Ok(address) = runtime.create_ordered_collection(owner)
  let _id =
    runtime.ordered_acquire_with_outcome(owner, address, fn(_) {
      runtime.close(owner)
    })
  runtime.diagnostics(owner).phase |> expect.to_equal("failed: runtime closed")
}

@target(javascript)
pub fn aborting_waiters_commits_terminal_state_before_callbacks_test() -> Nil {
  use count, _ <- with_reporter(False)
  let sluice = sluice_js.start(tenant: "default", document: "abort-waiters")
  let document = sluice_js.connect(sluice, "a")
  sluice_js.settle(sluice)
  let assert Ok(queue) = watershed.create_ordered_collection(document)
  watershed.set(
    watershed.root(document),
    "queue",
    watershed.ordered_collection_handle_of(queue),
  )
  sluice_js.settle(sluice)
  let calls = transport_js.new_cell([])
  let _first =
    watershed.ordered_acquire_with_outcome(queue, fn(outcome) {
      transport_js.set_cell(calls, [outcome, ..transport_js.get_cell(calls)])
      case transport_js.get_cell(calls) {
        [_] -> watershed.close(document)
        _ -> Nil
      }
    })
  let _second =
    watershed.ordered_acquire_with_outcome(queue, fn(_) {
      panic as "outcome fault"
    })
  watershed.close(document)
  transport_js.get_cell(calls)
  |> expect.to_equal([ordered_collection_kernel.Aborted])
  count() |> expect.to_equal(1)
  runtime.diagnostics(watershed.runtime_of(document)).phase
  |> expect.to_equal("failed: runtime closed")
}

@target(javascript)
pub fn resolved_waiters_are_removed_before_a_callback_closes_the_document_test() -> Nil {
  let sluice = sluice_js.start(tenant: "default", document: "resolved-waiter")
  let document = sluice_js.connect(sluice, "a")
  sluice_js.settle(sluice)
  let assert Ok(queue) = watershed.create_ordered_collection(document)
  watershed.set(
    watershed.root(document),
    "queue",
    watershed.ordered_collection_handle_of(queue),
  )
  watershed.ordered_add(queue, json.string("job"))
  sluice_js.settle(sluice)
  let calls = transport_js.new_cell([])
  let _id =
    watershed.ordered_acquire_with_outcome(queue, fn(outcome) {
      transport_js.set_cell(calls, [outcome, ..transport_js.get_cell(calls)])
      case transport_js.get_cell(calls) {
        [_] -> watershed.close(document)
        _ -> Nil
      }
    })
  sluice_js.settle(sluice)
  let assert [ordered_collection_kernel.AcquiredItem(_, _)] =
    transport_js.get_cell(calls)
  runtime.diagnostics(watershed.runtime_of(document)).phase
  |> expect.to_equal("failed: runtime closed")
}

@target(javascript)
pub fn failure_state_is_visible_inside_on_ready_test() -> Nil {
  let reference = transport_js.new_cell(None)
  let observed = transport_js.new_cell("")
  let #(owner, callbacks, _) =
    manual_runtime(fn(_) {
      let assert Some(owner) = transport_js.get_cell(reference)
      transport_js.set_cell(observed, runtime.diagnostics(owner).phase)
      runtime.close(owner)
    })
  transport_js.set_cell(reference, Some(owner))
  callbacks.on_event(
    "connect_document_error",
    "{\"code\":403,\"message\":\"refused\"}",
  )
  transport_js.get_cell(observed) |> expect.to_equal("failed: refused")
  runtime.diagnostics(owner).phase |> expect.to_equal("failed: runtime closed")
}
