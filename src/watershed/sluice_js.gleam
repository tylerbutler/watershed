//// JavaScript test driver for the in-memory sluice (plan HM4).
////
//// The mirror of `watershed/sluice` for the JS target, and much simpler: JS is
//// single-threaded, so the runtime processes every inbound frame synchronously
//// and pushes its own ops back synchronously. There are no actors and no
//// barriers — `settle` just drains the core's outbox in a loop, and each
//// delivery's reaction lands in the same cell before the next iteration reads
//// it.
////
//// This is what lets app authors — whose apps are JS/Lustre — write gleeunit
//// convergence tests on `--target javascript`, and lets presence's TTL logic be
//// tested by `advance`-ing the logical clock past expiry with no real waiting.

@target(javascript)
import gleam/dynamic.{type Dynamic}
@target(javascript)
import gleam/dynamic/decode
@target(javascript)
import gleam/json.{type Json}
@target(javascript)
import gleam/list
@target(javascript)
import gleam/option.{type Option, None, Some}

@target(javascript)
import watershed/runtime_js
@target(javascript)
import watershed/sluice/core
@target(javascript)
import watershed/transport_js.{type Cell}
@target(javascript)
import watershed/wire/socket
@target(javascript)
import watershed_js

// ─────────────────────────────────────────────────────────────────────────────
// Public API
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// A running in-memory server for one document.
pub opaque type Sluice {
  Sluice(cell: Cell(State), tenant: String, document: String)
}

@target(javascript)
/// One delivered frame's metadata, returned by `step_info` so a caller (e.g. a
/// live demo) can animate and log each hop. For `op` events `sequence_number`
/// and `author` are the sequenced op's SN and authoring client; other events
/// (handshake, signal) report `0` / `""`.
pub type Delivery {
  Delivery(to: String, event: String, sequence_number: Int, author: String)
}

@target(javascript)
/// Start a sluice for one document.
pub fn start(tenant tenant: String, document document: String) -> Sluice {
  Sluice(
    cell: transport_js.new_cell(State(
      core: core.new(tenant, document),
      conns: [],
      bindings: [],
      last_registered: None,
    )),
    tenant: tenant,
    document: document,
  )
}

@target(javascript)
/// Connect a fresh client, returning a real `watershed_js.Document`. The
/// handshake completes on the next `settle` (delivery is explicit).
pub fn connect(
  sluice: Sluice,
  user_id user_id: String,
) -> watershed_js.Document {
  let transport = make_transport(sluice.cell)
  let document =
    watershed_js.connect_via(
      tenant: sluice.tenant,
      document: sluice.document,
      user_id: user_id,
      transport: transport,
      on_ready: fn(_result) { Nil },
    )
  // The runtime has now stored its transport handle, so it is safe to fire the
  // `on_join` that makes it push `connect_document`. (Firing during
  // `transport.connect` would run before the handle is stored.) We also bind the
  // document's runtime to the just-registered client id so `pause`/`resume` can
  // target it by identity.
  let state = transport_js.get_cell(sluice.cell)
  case state.last_registered {
    Some(client_id) -> {
      transport_js.set_cell(
        sluice.cell,
        State(
          ..state,
          bindings: [
            #(watershed_js.runtime_of(document), client_id),
            ..state.bindings
          ],
          last_registered: None,
        ),
      )
      case find_conn(state.conns, client_id) {
        Ok(conn) -> conn.on_join()
        Error(_) -> Nil
      }
    }
    None -> Nil
  }
  document
}

@target(javascript)
/// Hold a client's inbound frames until `resume` — its queued frames stay put
/// while others are delivered, so a race can be scripted.
pub fn pause(sluice: Sluice, document: watershed_js.Document) -> Nil {
  update_paused(sluice, document, core.pause)
}

@target(javascript)
/// Release a paused client's held frames back into the deliverable queue.
pub fn resume(sluice: Sluice, document: watershed_js.Document) -> Nil {
  update_paused(sluice, document, core.resume)
}

@target(javascript)
fn update_paused(
  sluice: Sluice,
  document: watershed_js.Document,
  change: fn(core.Sluice, String) -> core.Sluice,
) -> Nil {
  let state = transport_js.get_cell(sluice.cell)
  case client_id_of(state.bindings, watershed_js.runtime_of(document)) {
    Ok(client_id) ->
      transport_js.set_cell(
        sluice.cell,
        State(..state, core: change(state.core, client_id)),
      )
    Error(_) -> Nil
  }
}

@target(javascript)
/// Deliver queued frames until the system is quiescent. Synchronous: each
/// delivery's reaction is pushed back into the core before the next iteration.
pub fn settle(sluice: Sluice) -> Nil {
  drain(sluice.cell)
}

@target(javascript)
/// Deliver exactly one queued frame (to a non-paused client), returning `False`
/// when nothing was deliverable.
pub fn step(sluice: Sluice) -> Bool {
  case take_deliver(sluice.cell) {
    Some(_) -> True
    None -> False
  }
}

@target(javascript)
/// Like `step`, but reports what was delivered (target client, event, and — for
/// `op` events — the sequence number and author). `None` when nothing was
/// deliverable. For driving live visualisations that animate each hop.
pub fn step_info(sluice: Sluice) -> Option(Delivery) {
  case take_deliver(sluice.cell) {
    None -> None
    Some(frame) -> {
      let #(sequence_number, author) = op_meta(frame)
      Some(Delivery(
        to: frame.client_id,
        event: frame.event,
        sequence_number: sequence_number,
        author: author,
      ))
    }
  }
}

@target(javascript)
/// Report the next frame `step`/`step_info` would deliver, without delivering
/// it. Lets a caller group a whole broadcast wave (every frame sharing an op's
/// sequence number) into one animation tick, so all replicas receive an op
/// together instead of one serial hop at a time.
pub fn peek_info(sluice: Sluice) -> Option(Delivery) {
  case core.peek(transport_js.get_cell(sluice.cell).core) {
    None -> None
    Some(frame) -> {
      let #(sequence_number, author) = op_meta(frame)
      Some(Delivery(
        to: frame.client_id,
        event: frame.event,
        sequence_number: sequence_number,
        author: author,
      ))
    }
  }
}

@target(javascript)
/// Whether any frame is still awaiting delivery to a non-paused client.
pub fn pending(sluice: Sluice) -> Bool {
  core.has_pending(transport_js.get_cell(sluice.cell).core)
}

@target(javascript)
/// The sluice-assigned client id for a document (matches the `to`/`author`
/// fields of `step_info`), or `Error` if it isn't connected here.
pub fn client_id(
  sluice: Sluice,
  document: watershed_js.Document,
) -> Result(String, Nil) {
  client_id_of(
    transport_js.get_cell(sluice.cell).bindings,
    watershed_js.runtime_of(document),
  )
}

@target(javascript)
/// The current server sequence number. Ops sequence synchronously on submit,
/// so reading this right after an edit yields that op's SN.
pub fn sequence_number(sluice: Sluice) -> Int {
  core.sequence_number(transport_js.get_cell(sluice.cell).core)
}

@target(javascript)
/// Advance the sluice's logical clock, so TTL-based logic (presence prune) is
/// testable without real time passing.
pub fn advance(sluice: Sluice, ms: Int) -> Nil {
  let state = transport_js.get_cell(sluice.cell)
  transport_js.set_cell(
    sluice.cell,
    State(..state, core: core.advance(state.core, ms)),
  )
}

// ─────────────────────────────────────────────────────────────────────────────
// Delivery
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
fn drain(cell: Cell(State)) -> Nil {
  case take_deliver(cell) {
    None -> Nil
    Some(_) -> drain(cell)
  }
}

@target(javascript)
/// Take the next deliverable frame, deliver it, and return it (or `None`).
/// Commits the take before delivering: the recipient's reaction pushes back
/// into the same cell, and we must not clobber it.
fn take_deliver(cell: Cell(State)) -> Option(core.Outbound) {
  let state = transport_js.get_cell(cell)
  case core.take(state.core) {
    #(core, None) -> {
      transport_js.set_cell(cell, State(..state, core: core))
      None
    }
    #(core, Some(frame)) -> {
      transport_js.set_cell(cell, State(..state, core: core))
      case find_conn(state.conns, frame.client_id) {
        Ok(conn) -> conn.on_event(frame.event, to_dynamic(frame.payload))
        Error(_) -> Nil
      }
      Some(frame)
    }
  }
}

@target(javascript)
/// Pull the sequence number and author from an `op` frame's payload (`0`/`""`
/// for other event kinds), for `step_info`.
fn op_meta(frame: core.Outbound) -> #(Int, String) {
  case frame.event {
    "op" ->
      case
        json.parse(json.to_string(frame.payload), socket.op_message_decoder())
      {
        Ok(message) ->
          case message.ops {
            [op, ..] -> #(op.sequence_number, option.unwrap(op.client_id, ""))
            [] -> #(0, "")
          }
        Error(_) -> #(0, "")
      }
    _ -> #(0, "")
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Transport: bridges a runtime to the sluice cell
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
fn make_transport(cell: Cell(State)) -> runtime_js.Transport {
  runtime_js.Transport(
    connect: fn(callbacks: runtime_js.TransportCallbacks) -> runtime_js.TransportHandle {
      let client_id = register(cell, callbacks.on_event, callbacks.on_join)
      runtime_js.TransportHandle(
        push: fn(event, payload) { push(cell, client_id, event, payload) },
        close: fn() { Nil },
        drop: fn() { Nil },
      )
    },
  )
}

@target(javascript)
fn register(
  cell: Cell(State),
  on_event: fn(String, Dynamic) -> Nil,
  on_join: fn() -> Nil,
) -> String {
  let state = transport_js.get_cell(cell)
  let #(core, client_id) = core.register(state.core)
  transport_js.set_cell(
    cell,
    State(
      ..state,
      core: core,
      conns: [#(client_id, Conn(on_event, on_join)), ..state.conns],
      last_registered: Some(client_id),
    ),
  )
  client_id
}

@target(javascript)
fn push(
  cell: Cell(State),
  client_id: String,
  event: String,
  payload: Json,
) -> Nil {
  let state = transport_js.get_cell(cell)
  transport_js.set_cell(
    cell,
    State(
      ..state,
      core: core.handle(state.core, client_id, event, to_dynamic(payload)),
    ),
  )
}

// ─────────────────────────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
type Conn {
  Conn(on_event: fn(String, Dynamic) -> Nil, on_join: fn() -> Nil)
}

@target(javascript)
type State {
  State(
    core: core.Sluice,
    conns: List(#(String, Conn)),
    /// Runtime → client-id, so `pause`/`resume` can target a document by
    /// identity (structural equality would deep-compare state cells).
    bindings: List(#(runtime_js.Runtime, String)),
    last_registered: Option(String),
  )
}

@target(javascript)
fn client_id_of(
  bindings: List(#(runtime_js.Runtime, String)),
  runtime: runtime_js.Runtime,
) -> Result(String, Nil) {
  case list.find(bindings, fn(pair) { reference_equals(pair.0, runtime) }) {
    Ok(pair) -> Ok(pair.1)
    Error(_) -> Error(Nil)
  }
}

@target(javascript)
@external(javascript, "./sluice_ffi.mjs", "referenceEquals")
fn reference_equals(a: runtime_js.Runtime, b: runtime_js.Runtime) -> Bool

@target(javascript)
fn find_conn(
  conns: List(#(String, Conn)),
  client_id: String,
) -> Result(Conn, Nil) {
  case list.key_find(conns, client_id) {
    Ok(conn) -> Ok(conn)
    Error(_) -> Error(Nil)
  }
}

@target(javascript)
/// Serialize a queued `Json` frame and re-parse it as `Dynamic` — the exact
/// trip a frame takes over a real socket before the runtime decodes it.
fn to_dynamic(payload: Json) -> Dynamic {
  let assert Ok(dynamic) = json.parse(json.to_string(payload), decode.dynamic)
  dynamic
}
