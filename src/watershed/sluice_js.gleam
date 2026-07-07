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
import watershed_js

// ─────────────────────────────────────────────────────────────────────────────
// Public API
// ─────────────────────────────────────────────────────────────────────────────

/// A running in-memory server for one document.
@target(javascript)
pub opaque type Sluice {
  Sluice(cell: Cell(State), tenant: String, document: String)
}

/// Start a sluice for one document.
@target(javascript)
pub fn start(tenant tenant: String, document document: String) -> Sluice {
  Sluice(
    cell: transport_js.new_cell(State(
      core: core.new(tenant, document),
      conns: [],
      last_registered: None,
    )),
    tenant: tenant,
    document: document,
  )
}

/// Connect a fresh client, returning a real `watershed_js.Document`. The
/// handshake completes on the next `settle` (delivery is explicit).
@target(javascript)
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
  // `transport.connect` would run before the handle is stored.)
  let state = transport_js.get_cell(sluice.cell)
  case state.last_registered {
    Some(client_id) -> {
      transport_js.set_cell(
        sluice.cell,
        State(..state, last_registered: None),
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

/// Deliver queued frames until the system is quiescent. Synchronous: each
/// delivery's reaction is pushed back into the core before the next iteration.
@target(javascript)
pub fn settle(sluice: Sluice) -> Nil {
  drain(sluice.cell)
}

/// Deliver exactly one queued frame (to a non-paused client), returning `False`
/// when nothing was deliverable.
@target(javascript)
pub fn step(sluice: Sluice) -> Bool {
  let state = transport_js.get_cell(sluice.cell)
  case core.take(state.core) {
    #(core, None) -> {
      transport_js.set_cell(sluice.cell, State(..state, core: core))
      False
    }
    #(core, Some(frame)) -> {
      transport_js.set_cell(sluice.cell, State(..state, core: core))
      deliver(sluice.cell, frame)
      True
    }
  }
}

/// Advance the sluice's logical clock, so TTL-based logic (presence prune) is
/// testable without real time passing.
@target(javascript)
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
  let state = transport_js.get_cell(cell)
  case core.take(state.core) {
    #(core, None) -> transport_js.set_cell(cell, State(..state, core: core))
    #(core, Some(frame)) -> {
      // Commit the take before delivering: the recipient's reaction pushes
      // back into the same cell, and we must not clobber it.
      transport_js.set_cell(cell, State(..state, core: core))
      deliver(cell, frame)
      drain(cell)
    }
  }
}

@target(javascript)
fn deliver(cell: Cell(State), frame: core.Outbound) -> Nil {
  let state = transport_js.get_cell(cell)
  case find_conn(state.conns, frame.client_id) {
    Ok(conn) -> conn.on_event(frame.event, to_dynamic(frame.payload))
    Error(_) -> Nil
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
      core: core,
      conns: [#(client_id, Conn(on_event, on_join)), ..state.conns],
      last_registered: Some(client_id),
    ),
  )
  client_id
}

@target(javascript)
fn push(cell: Cell(State), client_id: String, event: String, payload: Json) -> Nil {
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
    last_registered: Option(String),
  )
}

@target(javascript)
fn find_conn(conns: List(#(String, Conn)), client_id: String) -> Result(Conn, Nil) {
  case list.key_find(conns, client_id) {
    Ok(conn) -> Ok(conn)
    Error(_) -> Error(Nil)
  }
}

/// Serialize a queued `Json` frame and re-parse it as `Dynamic` — the exact
/// trip a frame takes over a real socket before the runtime decodes it.
@target(javascript)
fn to_dynamic(payload: Json) -> Dynamic {
  let assert Ok(dynamic) = json.parse(json.to_string(payload), decode.dynamic)
  dynamic
}
