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

@target(erlang)
/// A running in-memory server for one document.
pub opaque type Sluice {
  Sluice(actor: Subject(Message), tenant: String, document: String)
}

@target(erlang)
/// Start a sluice for one document. `tenant`/`document` name the logical
/// document the way `watershed.connect` would.
pub fn start(
  tenant tenant: String,
  document document: String,
) -> Result(Sluice, actor.StartError) {
  actor.new(State(
    core: core.new(tenant, document),
    conns: [],
    subjects: [],
    dropped: [],
    last_registered: None,
  ))
  |> actor.on_message(handle)
  |> actor.start
  |> result_map(fn(started) {
    Sluice(actor: started.data, tenant: tenant, document: document)
  })
}

@target(erlang)
/// Connect a fresh client, returning a real `watershed.Document`. The handshake
/// completes on the next `settle` (delivery is explicit), so callers connect
/// every client, then `settle` once before editing.
pub fn connect(
  sluice: Sluice,
  user_id user_id: String,
) -> Result(watershed.Document(root), String) {
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

@target(erlang)
/// Drop a client's socket and let it come back — the reconnect a real client
/// survives, rather than a departure it does not.
///
/// The distinction from `disconnect` is the whole point. `disconnect` removes a
/// client from the room for good; this severs the connection underneath a
/// runtime that keeps its core — kernel state, pending consensus, and the
/// in-flight queue all survive — and then lets it re-handshake. The server
/// assigns it a **fresh client id**, exactly as floodgate does, so the returning
/// client is a different member of the room than the one that left.
///
/// That is the window a lot of protocol bugs live in: ops sequenced while the
/// client was away replay against the room as it was *then*, edits made during
/// the gap are restamped and resubmitted, and a consensus kernel may owe
/// signoffs under an identity that no longer exists. None of it is reachable
/// without being able to script this.
///
/// The handshake completes on the next `settle`, like `connect`.
///
/// The dance below is dictated by the driver's lock order (see the module
/// docs): the sluice never calls into a runtime, so `DropConn` hands the
/// `on_close` back and *this* process fires it. The barrier that follows lets
/// the runtime run its whole reconnect — `ChannelClosed` → re-`connect` →
/// `ChannelReady` → `connect_document` carrying `last_seen` — before `Bind`
/// re-points the binding at the connection it just opened.
pub fn reconnect(sluice: Sluice, document: watershed.Document(root)) -> Nil {
  drop(sluice, document)
  rejoin(sluice, document)
}

@target(erlang)
/// The first half of `reconnect`: take the socket away and leave it away.
///
/// Splitting the two matters because the interesting window is *between* them.
/// A client is out of the room from its `leave` until its rejoin, and anything
/// sequenced in that gap was sequenced for a room it was not in — which it then
/// has to replay, under an identity that did not exist when those ops were
/// made. Scripting that means being able to sequence ops while the client is
/// away, which an atomic reconnect cannot express.
///
/// The runtime keeps its core and sits in its reconnecting phase until
/// `rejoin`.
pub fn drop(sluice: Sluice, document: watershed.Document(root)) -> Nil {
  let subject = watershed.runtime_subject(document)
  let _ =
    process.call(sluice.actor, waiting: call_timeout_ms, sending: fn(reply) {
      DropConn(subject, reply)
    })
  Nil
}

@target(erlang)
/// The second half of `reconnect`: let a dropped client come back, under a
/// fresh server-assigned client id.
///
/// A no-op for a client that was not `drop`ped.
pub fn rejoin(sluice: Sluice, document: watershed.Document(root)) -> Nil {
  let subject = watershed.runtime_subject(document)
  case
    process.call(sluice.actor, waiting: call_timeout_ms, sending: fn(reply) {
      TakeDropped(subject, reply)
    })
  {
    Error(_) -> Nil
    Ok(on_close) -> {
      on_close("sluice reconnect")
      // Flush the runtime: it must reach `connect_document` before `Bind` can
      // find the new connection as `last_registered`.
      let _ = runtime.is_synced(subject)
      let _ =
        process.call(sluice.actor, waiting: call_timeout_ms, sending: fn(reply) {
          Bind(subject, reply)
        })
      Nil
    }
  }
}

@target(erlang)
/// Deliver queued frames until the system is quiescent: every pending op has
/// reached every client and no client has produced new ops in response.
pub fn settle(sluice: Sluice) -> Nil {
  barrier_all(sluice)
  drain(sluice)
}

@target(erlang)
/// Deliver exactly one queued frame (to a non-paused client), returning `False`
/// when nothing was deliverable. The building block for scripted races:
/// `pause` one client, then `step` to release another's op first.
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

@target(erlang)
/// Hold a client's inbound frames until `resume` — its queued frames stay put
/// while others are delivered.
pub fn pause(sluice: Sluice, document: watershed.Document(root)) -> Nil {
  let subject = watershed.runtime_subject(document)
  process.call(sluice.actor, waiting: call_timeout_ms, sending: fn(reply) {
    Pause(subject, reply)
  })
}

@target(erlang)
/// Release a paused client's held frames back into the deliverable queue.
pub fn resume(sluice: Sluice, document: watershed.Document(root)) -> Nil {
  let subject = watershed.runtime_subject(document)
  process.call(sluice.actor, waiting: call_timeout_ms, sending: fn(reply) {
    Resume(subject, reply)
  })
}

@target(erlang)
/// Advance the sluice's logical clock, so TTL-based logic (presence prune) is
/// testable without real time passing.
pub fn advance(sluice: Sluice, ms: Int) -> Nil {
  process.call(sluice.actor, waiting: call_timeout_ms, sending: fn(reply) {
    Advance(ms, reply)
  })
}

@target(erlang)
/// Withhold `presence_v1` from the handshake, so a client under `Auto` picks the
/// ripple fallback and a client forcing `Server` fails. Call before `connect`.
pub fn disable_presence(sluice: Sluice) -> Nil {
  process.call(sluice.actor, waiting: call_timeout_ms, sending: fn(reply) {
    SetPresenceSupported(False, reply)
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

@target(erlang)
/// Flush every connected runtime's mailbox. A synchronous call returns only
/// after the actor has processed all prior messages, so any pending edit has
/// synchronously pushed its op into the core by the time this returns.
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
        Register(callbacks.on_event, callbacks.on_close, reply)
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
  /// A new connection: store its delivery callbacks, mint a client id.
  Register(
    on_event: fn(String, Dynamic) -> Nil,
    on_close: fn(String) -> Nil,
    reply: Subject(String),
  )
  /// Sever a bound runtime's connection the way a dropped socket would:
  /// sequence its `leave`, forget the connection, and hand its `on_close` back
  /// so the *caller* can fire it (calling into a runtime from inside this actor
  /// would invert the lock order this driver is built on).
  DropConn(subject: Subject(runtime.Msg), reply: Subject(Result(Nil, Nil)))
  /// Hand back a dropped runtime's `on_close` so the caller can fire it, which
  /// is what starts the rejoin. Kept out of `DropConn` so a test can sequence
  /// ops while the client is away.
  TakeDropped(
    subject: Subject(runtime.Msg),
    reply: Subject(Result(fn(String) -> Nil, Nil)),
  )
  /// Associate a runtime subject with the just-registered connection.
  Bind(subject: Subject(runtime.Msg), reply: Subject(String))
  /// A client→server push (synchronous; the reply is the flush barrier).
  Push(client_id: String, event: String, payload: Json, reply: Subject(Nil))
  /// Pop one deliverable frame and deliver it; reply whether one was sent.
  TakeAndDeliver(reply: Subject(Bool))
  Pause(subject: Subject(runtime.Msg), reply: Subject(Nil))
  Resume(subject: Subject(runtime.Msg), reply: Subject(Nil))
  Advance(ms: Int, reply: Subject(Nil))
  SetPresenceSupported(supported: Bool, reply: Subject(Nil))
  /// The connected runtime subjects, for the caller's barrier sweep.
  Subjects(reply: Subject(List(Subject(runtime.Msg))))
}

@target(erlang)
type State {
  State(
    core: core.Sluice,
    conns: List(#(String, Conn)),
    subjects: List(#(Subject(runtime.Msg), String)),
    /// Runtimes whose socket has been taken away but which have not been let
    /// back yet, holding the `on_close` that starts their rejoin.
    dropped: List(#(Subject(runtime.Msg), fn(String) -> Nil)),
    last_registered: Option(String),
  )
}

@target(erlang)
/// One open connection's callbacks into the runtime that owns it.
///
/// `on_close` is held rather than dropped because it is the only way to tell a
/// runtime its socket went away — which `reconnect` needs, and which nothing
/// else in the driver can synthesise.
type Conn {
  Conn(on_event: fn(String, Dynamic) -> Nil, on_close: fn(String) -> Nil)
}

@target(erlang)
fn handle(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    Register(on_event, on_close, reply) -> {
      let #(core, client_id) = core.register(state.core)
      process.send(reply, client_id)
      actor.continue(
        State(
          ..state,
          core: core,
          conns: [
            #(client_id, Conn(on_event: on_event, on_close: on_close)),
            ..state.conns
          ],
          last_registered: Some(client_id),
        ),
      )
    }

    TakeDropped(subject, reply) -> {
      let taken = case
        list.find(state.dropped, fn(pair) { pair.0 == subject })
      {
        Ok(pair) -> Ok(pair.1)
        Error(_) -> Error(Nil)
      }
      process.send(reply, taken)
      actor.continue(
        State(
          ..state,
          dropped: list.filter(state.dropped, fn(pair) { pair.0 != subject }),
        ),
      )
    }

    DropConn(subject, reply) ->
      case client_id_of(state.subjects, subject) {
        Error(_) -> {
          process.send(reply, Error(Nil))
          actor.continue(state)
        }
        Ok(client_id) -> {
          let dropped = case list.key_find(state.conns, client_id) {
            Ok(conn) -> [#(subject, conn.on_close), ..state.dropped]
            Error(_) -> state.dropped
          }
          process.send(reply, Ok(Nil))
          actor.continue(
            State(
              ..state,
              dropped: dropped,
              // The leave the server sequences when a socket goes away. Without
              // it the room keeps a member that is never coming back under that
              // id, which is the ghost the durable-log repair exists to prevent.
              core: core.disconnect(state.core, client_id),
              conns: list.filter(state.conns, fn(pair) { pair.0 != client_id }),
              subjects: list.filter(state.subjects, fn(pair) {
                pair.0 != subject
              }),
            ),
          )
        }
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
            Ok(conn) -> conn.on_event(frame.event, to_dynamic(frame.payload))
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

    SetPresenceSupported(supported, reply) -> {
      process.send(reply, Nil)
      actor.continue(
        State(..state, core: core.set_presence_supported(state.core, supported)),
      )
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

@target(erlang)
/// Serialize a queued `Json` frame and re-parse it as `Dynamic` — the exact
/// trip a frame takes over a real socket before the runtime decodes it.
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
fn result_map(result: Result(a, e), transform: fn(a) -> b) -> Result(b, e) {
  case result {
    Ok(value) -> Ok(transform(value))
    Error(error) -> Error(error)
  }
}
