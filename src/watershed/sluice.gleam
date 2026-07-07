//// Erlang test driver for the in-memory sluice (plan HM3).
////
//// Wraps the pure `sluice/core` in an actor and drives real `watershed`
//// documents through the runtime's injectable transport — so an app author
//// writes deterministic multi-client convergence tests with no levee server.
////
//// ## Determinism without a clock
////
//// Ops sequence when submitted but are delivered only on `settle`/`step`, so
//// races are scriptable rather than timing-dependent. Coordination is
//// deadlock-free by construction:
////
//// - **runtime → sluice** pushes are *synchronous* (`process.call`). So once a
////   runtime's mailbox is flushed, its ops have already reached the core.
//// - **sluice → runtime** delivery is an *async send* (the runtime's
////   `on_event` enqueues an `Inbound`). The sluice never calls a runtime, so a
////   runtime blocked mid-push can't deadlock it.
//// - **barriers** are `process.call`s issued from the *test* process. A call
////   returns only after the actor has drained its mailbox, so barriering every
////   runtime flushes all pending edits into the core before delivery.
////
//// `settle` therefore is: barrier all runtimes, then repeatedly deliver one
//// frame and re-barrier (to flush the recipient's reaction) until the core has
//// nothing left to hand out.

@target(erlang)
import gleam/dynamic.{type Dynamic}
@target(erlang)
import gleam/dynamic/decode
@target(erlang)
import gleam/erlang/process.{type Subject}
@target(erlang)
import gleam/json.{type Json}
@target(erlang)
import gleam/list
@target(erlang)
import gleam/option.{type Option, None, Some}
@target(erlang)
import gleam/otp/actor

@target(erlang)
import watershed
@target(erlang)
import watershed/runtime
@target(erlang)
import watershed/sluice/core

@target(erlang)
const call_timeout_ms = 5000

// ─────────────────────────────────────────────────────────────────────────────
// Public API
// ─────────────────────────────────────────────────────────────────────────────

/// A running in-memory server for one document.
@target(erlang)
pub opaque type Sluice {
  Sluice(actor: Subject(Message), tenant: String, document: String)
}

/// Start a sluice for one document. `tenant`/`document` name the logical
/// document the way `watershed.connect` would.
@target(erlang)
pub fn start(
  tenant tenant: String,
  document document: String,
) -> Result(Sluice, actor.StartError) {
  actor.new(State(
    core: core.new(tenant, document),
    conns: [],
    subjects: [],
    last_registered: None,
  ))
  |> actor.on_message(handle)
  |> actor.start
  |> result_map(fn(started) {
    Sluice(actor: started.data, tenant: tenant, document: document)
  })
}

/// Connect a fresh client, returning a real `watershed.Document`. The handshake
/// completes on the next `settle` (delivery is explicit), so callers connect
/// every client, then `settle` once before editing.
@target(erlang)
pub fn connect(
  sluice: Sluice,
  user_id user_id: String,
) -> Result(watershed.Document, String) {
  let transport = sluice_transport(sluice.actor)
  case
    watershed.connect_via(
      tenant: sluice.tenant,
      document: sluice.document,
      user_id: user_id,
      transport: transport,
    )
  {
    Error(reason) -> Error(reason)
    Ok(document) -> {
      // Bind this document's runtime to the connection just registered, so
      // `settle` can barrier it and `pause` can target it.
      let subject = watershed.runtime_subject(document)
      let _ =
        process.call(sluice.actor, waiting: call_timeout_ms, sending: fn(reply) {
          Bind(subject, reply)
        })
      Ok(document)
    }
  }
}

/// Deliver queued frames until the system is quiescent: every pending op has
/// reached every client and no client has produced new ops in response.
@target(erlang)
pub fn settle(sluice: Sluice) -> Nil {
  barrier_all(sluice)
  drain(sluice)
}

/// Deliver exactly one queued frame (to a non-paused client), returning `False`
/// when nothing was deliverable. The building block for scripted races:
/// `pause` one client, then `step` to release another's op first.
@target(erlang)
pub fn step(sluice: Sluice) -> Bool {
  barrier_all(sluice)
  case take_and_deliver(sluice) {
    False -> False
    True -> {
      barrier_all(sluice)
      True
    }
  }
}

/// Hold a client's inbound frames until `resume` — its queued frames stay put
/// while others are delivered.
@target(erlang)
pub fn pause(sluice: Sluice, document: watershed.Document) -> Nil {
  let subject = watershed.runtime_subject(document)
  process.call(sluice.actor, waiting: call_timeout_ms, sending: fn(reply) {
    Pause(subject, reply)
  })
}

/// Release a paused client's held frames back into the deliverable queue.
@target(erlang)
pub fn resume(sluice: Sluice, document: watershed.Document) -> Nil {
  let subject = watershed.runtime_subject(document)
  process.call(sluice.actor, waiting: call_timeout_ms, sending: fn(reply) {
    Resume(subject, reply)
  })
}

/// Advance the sluice's logical clock, so TTL-based logic (presence prune) is
/// testable without real time passing.
@target(erlang)
pub fn advance(sluice: Sluice, ms: Int) -> Nil {
  process.call(sluice.actor, waiting: call_timeout_ms, sending: fn(reply) {
    Advance(ms, reply)
  })
}

// ─────────────────────────────────────────────────────────────────────────────
// Delivery orchestration (runs in the caller's process)
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
fn drain(sluice: Sluice) -> Nil {
  case take_and_deliver(sluice) {
    False -> Nil
    True -> {
      barrier_all(sluice)
      drain(sluice)
    }
  }
}

@target(erlang)
fn take_and_deliver(sluice: Sluice) -> Bool {
  process.call(sluice.actor, waiting: call_timeout_ms, sending: fn(reply) {
    TakeAndDeliver(reply)
  })
}

/// Flush every connected runtime's mailbox. A synchronous call returns only
/// after the actor has processed all prior messages, so any pending edit has
/// synchronously pushed its op into the core by the time this returns.
@target(erlang)
fn barrier_all(sluice: Sluice) -> Nil {
  let subjects =
    process.call(sluice.actor, waiting: call_timeout_ms, sending: Subjects)
  list.each(subjects, fn(subject) {
    let _ = runtime.is_synced(subject)
    Nil
  })
}

// ─────────────────────────────────────────────────────────────────────────────
// Transport: bridges a runtime to the sluice actor
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
fn sluice_transport(actor: Subject(Message)) -> runtime.Transport {
  runtime.Transport(connect: fn(callbacks: runtime.TransportCallbacks) -> Nil {
    let client_id =
      process.call(actor, waiting: call_timeout_ms, sending: fn(reply) {
        Register(callbacks.on_event, reply)
      })
    let handle =
      runtime.TransportHandle(
        push: fn(event, payload) {
          process.call(actor, waiting: call_timeout_ms, sending: fn(reply) {
            Push(client_id, event, payload, reply)
          })
        },
        close: fn() { Nil },
        drop: fn() { Nil },
      )
    callbacks.on_ready(handle)
  })
}

// ─────────────────────────────────────────────────────────────────────────────
// Actor
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
type Message {
  /// A new connection: store its delivery callback, mint a client id.
  Register(on_event: fn(String, Dynamic) -> Nil, reply: Subject(String))
  /// Associate a runtime subject with the just-registered connection.
  Bind(subject: Subject(runtime.Msg), reply: Subject(String))
  /// A client→server push (synchronous; the reply is the flush barrier).
  Push(client_id: String, event: String, payload: Json, reply: Subject(Nil))
  /// Pop one deliverable frame and deliver it; reply whether one was sent.
  TakeAndDeliver(reply: Subject(Bool))
  Pause(subject: Subject(runtime.Msg), reply: Subject(Nil))
  Resume(subject: Subject(runtime.Msg), reply: Subject(Nil))
  Advance(ms: Int, reply: Subject(Nil))
  /// The connected runtime subjects, for the caller's barrier sweep.
  Subjects(reply: Subject(List(Subject(runtime.Msg))))
}

@target(erlang)
type State {
  State(
    core: core.Sluice,
    conns: List(#(String, fn(String, Dynamic) -> Nil)),
    subjects: List(#(Subject(runtime.Msg), String)),
    last_registered: Option(String),
  )
}

@target(erlang)
fn handle(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    Register(on_event, reply) -> {
      let #(core, client_id) = core.register(state.core)
      process.send(reply, client_id)
      actor.continue(
        State(
          ..state,
          core: core,
          conns: [#(client_id, on_event), ..state.conns],
          last_registered: Some(client_id),
        ),
      )
    }

    Bind(subject, reply) ->
      case state.last_registered {
        Some(client_id) -> {
          process.send(reply, client_id)
          actor.continue(
            State(
              ..state,
              subjects: [#(subject, client_id), ..state.subjects],
              last_registered: None,
            ),
          )
        }
        None -> {
          process.send(reply, "")
          actor.continue(state)
        }
      }

    Push(client_id, event, payload, reply) -> {
      let core = core.handle(state.core, client_id, event, to_dynamic(payload))
      process.send(reply, Nil)
      actor.continue(State(..state, core: core))
    }

    TakeAndDeliver(reply) ->
      case core.take(state.core) {
        #(core, None) -> {
          process.send(reply, False)
          actor.continue(State(..state, core: core))
        }
        #(core, Some(frame)) -> {
          case list.key_find(state.conns, frame.client_id) {
            Ok(on_event) -> on_event(frame.event, to_dynamic(frame.payload))
            Error(_) -> Nil
          }
          process.send(reply, True)
          actor.continue(State(..state, core: core))
        }
      }

    Pause(subject, reply) -> {
      let core = case client_id_of(state.subjects, subject) {
        Ok(client_id) -> core.pause(state.core, client_id)
        Error(_) -> state.core
      }
      process.send(reply, Nil)
      actor.continue(State(..state, core: core))
    }

    Resume(subject, reply) -> {
      let core = case client_id_of(state.subjects, subject) {
        Ok(client_id) -> core.resume(state.core, client_id)
        Error(_) -> state.core
      }
      process.send(reply, Nil)
      actor.continue(State(..state, core: core))
    }

    Advance(ms, reply) -> {
      process.send(reply, Nil)
      actor.continue(State(..state, core: core.advance(state.core, ms)))
    }

    Subjects(reply) -> {
      process.send(reply, list.map(state.subjects, fn(pair) { pair.0 }))
      actor.continue(state)
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Internals
// ─────────────────────────────────────────────────────────────────────────────

/// Serialize a queued `Json` frame and re-parse it as `Dynamic` — the exact
/// trip a frame takes over a real socket before the runtime decodes it.
@target(erlang)
fn to_dynamic(payload: Json) -> Dynamic {
  let assert Ok(dynamic) = json.parse(json.to_string(payload), decode.dynamic)
  dynamic
}

@target(erlang)
fn client_id_of(
  subjects: List(#(Subject(runtime.Msg), String)),
  subject: Subject(runtime.Msg),
) -> Result(String, Nil) {
  case list.find(subjects, fn(pair) { pair.0 == subject }) {
    Ok(pair) -> Ok(pair.1)
    Error(_) -> Error(Nil)
  }
}

@target(erlang)
fn result_map(
  result: Result(a, e),
  transform: fn(a) -> b,
) -> Result(b, e) {
  case result {
    Ok(value) -> Ok(transform(value))
    Error(error) -> Error(error)
  }
}
