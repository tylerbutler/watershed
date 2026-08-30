//// Erlang test driver for the in-memory sluice (plan HM3).
////
//// This module puts the pure `sluice/core` in an actor, and it drives real
//// `watershed` documents through the injectable transport of the runtime. An
//// application author can thus write deterministic multi-client convergence
//// tests with no floodgate server.
////
//// ## Determinism without a clock
////
//// An op sequences when a client submits it, but the sluice delivers it only
//// on a `settle` or a `step`. A test can thus script a race, and the result
//// does not depend on timing. The coordination cannot deadlock, by
//// construction:
////
//// - A push from a runtime to the sluice is *synchronous*, through
////   `process.call`. After a runtime empties its mailbox, its ops have thus
////   already reached the core.
//// - A delivery from the sluice to a runtime is an *asynchronous* send. The
////   `on_event` function of the runtime puts an `Inbound` message in the
////   mailbox. The sluice never calls a runtime, so a runtime that blocks in
////   the middle of a push cannot deadlock the sluice.
//// - A barrier is a `process.call` from the *test* process. A call returns
////   only after the actor processes every earlier message. A barrier on every
////   runtime thus moves every pending edit into the core before the delivery.
////
//// `settle` is thus this procedure: apply a barrier to every runtime, then
//// deliver one frame and apply the barriers again, which flushes the reaction
//// of the recipient. Repeat until the core has no frame left to deliver.

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
import gleam/result

@target(erlang)
import watershed/runtime_beam
@target(erlang)
import watershed/sluice/core
@target(erlang)
import watershed_beam

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
/// Start a sluice for one document. `tenant` and `document` name the logical
/// document in the same way as `watershed_beam.connect`.
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
  |> result.map(fn(started) {
    Sluice(actor: started.data, tenant: tenant, document: document)
  })
}

@target(erlang)
/// Connect a new client and return a real `watershed_beam.Document` value. The
/// handshake completes on the next `settle`, because every delivery is
/// explicit. A caller thus connects every client, and then calls `settle` one
/// time before it edits.
pub fn connect(
  sluice: Sluice,
  user_id user_id: String,
) -> Result(watershed_beam.Document(root), String) {
  let transport = sluice_transport(sluice.actor)
  case
    watershed_beam.connect_via(
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
      let subject = watershed_beam.runtime_subject(document)
      let _ =
        process.call(sluice.actor, waiting: call_timeout_ms, sending: fn(reply) {
          Bind(subject, reply)
        })
      Ok(document)
    }
  }
}

@target(erlang)
/// Close the socket of a client and then let that client return. This is the
/// reconnect that a real client survives. It is not a departure.
///
/// The difference from `disconnect` is the purpose of this function.
/// `disconnect` removes a client from the room permanently. This function
/// closes the connection below a runtime that keeps its core, which is the
/// kernel state, the pending consensus, and the in-flight queue. The runtime
/// then does the handshake again. The server assigns it a **new client id**,
/// exactly as floodgate does, so the client that returns is a different member
/// of the room than the client that left.
///
/// Many protocol faults are in that window. An op that sequenced while the
/// client was absent replays against the room as it was at that time. An edit
/// from the interval gets a new stamp and a resubmission. A consensus kernel
/// can owe signoffs under an identity that no longer exists. A test can reach
/// none of those conditions unless it can script this sequence.
///
/// The handshake completes on the next `settle`, the same as for `connect`.
///
/// The lock order of the driver sets the steps below. See the module docs. The
/// sluice never calls into a runtime, so `DropConn` returns the `on_close`
/// function and *this* process calls it. The barrier that follows lets the
/// runtime complete its whole reconnect: `ChannelClosed`, then a new
/// `connect`, then `ChannelReady`, then a `connect_document` that carries
/// `last_seen`. Only then does `Bind` point the binding at the connection that
/// the runtime opened.
pub fn reconnect(
  sluice: Sluice,
  document: watershed_beam.Document(root),
) -> Nil {
  drop(sluice, document)
  rejoin(sluice, document)
}

@target(erlang)
/// The first half of `reconnect`: close the socket and keep it closed.
///
/// The two halves are separate because the interesting window is *between*
/// them. A client is outside the room from its `leave` until its rejoin. Every
/// op that sequences in that interval sequenced for a room that did not
/// contain the client. The client must then replay those ops, under an
/// identity that did not exist when other clients made them. To script that
/// sequence, a test must sequence ops while the client is absent, and one
/// atomic reconnect cannot express that.
///
/// The runtime keeps its core and stays in its reconnecting phase until
/// `rejoin`.
pub fn drop(sluice: Sluice, document: watershed_beam.Document(root)) -> Nil {
  let subject = watershed_beam.runtime_subject(document)
  let _ =
    process.call(sluice.actor, waiting: call_timeout_ms, sending: fn(reply) {
      DropConn(subject, reply)
    })
  Nil
}

@target(erlang)
/// The second half of `reconnect`: let a dropped client return, under a new
/// client id that the server assigns.
///
/// The function does nothing for a client that `drop` did not remove.
pub fn rejoin(sluice: Sluice, document: watershed_beam.Document(root)) -> Nil {
  let subject = watershed_beam.runtime_subject(document)
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
      let _ = runtime_beam.is_synced(subject)
      let _ =
        process.call(sluice.actor, waiting: call_timeout_ms, sending: fn(reply) {
          Bind(subject, reply)
        })
      Nil
    }
  }
}

@target(erlang)
/// Deliver the queued frames until the system is quiet. At that point every
/// pending op has reached every client, and no client has produced a new op in
/// response.
pub fn settle(sluice: Sluice) -> Nil {
  barrier_all(sluice)
  drain(sluice)
}

@target(erlang)
/// Deliver exactly one queued frame, to a client that is not paused. The
/// function returns `False` when it can deliver no frame. This is the basic
/// operation for a scripted race: call `pause` on one client, then call `step`
/// to release the op of another client first.
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
/// Hold the inbound frames of a client until a `resume` call. The queued
/// frames of that client stay in the queue while the sluice delivers the
/// frames of the other clients.
pub fn pause(sluice: Sluice, document: watershed_beam.Document(root)) -> Nil {
  let subject = watershed_beam.runtime_subject(document)
  process.call(sluice.actor, waiting: call_timeout_ms, sending: fn(reply) {
    Pause(subject, reply)
  })
}

@target(erlang)
/// Return the held frames of a paused client to the deliverable queue.
pub fn resume(sluice: Sluice, document: watershed_beam.Document(root)) -> Nil {
  let subject = watershed_beam.runtime_subject(document)
  process.call(sluice.actor, waiting: call_timeout_ms, sending: fn(reply) {
    Resume(subject, reply)
  })
}

@target(erlang)
/// Advance the logical clock of the sluice. A test can thus check the logic
/// that depends on a time-to-live (TTL), for example the presence prune,
/// without a wait for the real time.
pub fn advance(sluice: Sluice, ms: Int) -> Nil {
  process.call(sluice.actor, waiting: call_timeout_ms, sending: fn(reply) {
    Advance(ms, reply)
  })
}

@target(erlang)
/// Remove `presence_v1` from the handshake. A client in `Auto` mode thus
/// selects the ripple fallback, and a client that forces `Server` mode fails.
/// Call this function before `connect`.
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
/// Empty the mailbox of every connected runtime. A synchronous call returns
/// only after the actor processes every earlier message. Every pending edit has
/// thus pushed its op into the core before this function returns.
fn barrier_all(sluice: Sluice) -> Nil {
  let subjects =
    process.call(sluice.actor, waiting: call_timeout_ms, sending: Subjects)
  list.each(subjects, fn(subject) {
    let _ = runtime_beam.is_synced(subject)
    Nil
  })
}

// ─────────────────────────────────────────────────────────────────────────────
// Transport: bridges a runtime to the sluice actor
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
fn sluice_transport(actor: Subject(Message)) -> runtime_beam.Transport {
  runtime_beam.Transport(
    connect: fn(callbacks: runtime_beam.TransportCallbacks) -> Nil {
      let client_id =
        process.call(actor, waiting: call_timeout_ms, sending: fn(reply) {
          Register(callbacks.on_event, callbacks.on_close, reply)
        })
      let handle =
        runtime_beam.TransportHandle(
          push: fn(event, payload) {
            process.call(actor, waiting: call_timeout_ms, sending: fn(reply) {
              Push(client_id, event, payload, reply)
            })
          },
          close: fn() { Nil },
          drop: fn() { Nil },
        )
      callbacks.on_ready(handle)
    },
  )
}

// ─────────────────────────────────────────────────────────────────────────────
// Actor
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
type Message {
  /// A new connection. Store its delivery callbacks and create a client id.
  Register(
    on_event: fn(String, Json) -> Nil,
    on_close: fn(String) -> Nil,
    reply: Subject(String),
  )
  /// Close the connection of a bound runtime, in the same way as a dropped
  /// socket. Sequence its `leave`, remove the connection, and return its
  /// `on_close` function, so that the *caller* can call it. A call into a
  /// runtime from inside this actor would reverse the lock order that this
  /// driver depends on.
  DropConn(subject: Subject(runtime_beam.Msg), reply: Subject(Result(Nil, Nil)))
  /// Return the `on_close` function of a dropped runtime, so that the caller
  /// can call it. That call starts the rejoin. This message is separate from
  /// `DropConn`, so a test can sequence ops while the client is absent.
  TakeDropped(
    subject: Subject(runtime_beam.Msg),
    reply: Subject(Result(fn(String) -> Nil, Nil)),
  )
  /// Associate a runtime subject with the just-registered connection.
  Bind(subject: Subject(runtime_beam.Msg), reply: Subject(String))
  /// A push from a client to the server. It is synchronous, and the reply is
  /// the flush barrier.
  Push(client_id: String, event: String, payload: Json, reply: Subject(Nil))
  /// Take one deliverable frame and deliver it. The reply says whether the
  /// actor sent a frame.
  TakeAndDeliver(reply: Subject(Bool))
  Pause(subject: Subject(runtime_beam.Msg), reply: Subject(Nil))
  Resume(subject: Subject(runtime_beam.Msg), reply: Subject(Nil))
  Advance(ms: Int, reply: Subject(Nil))
  SetPresenceSupported(supported: Bool, reply: Subject(Nil))
  /// The subjects of the connected runtimes, for the barrier sweep of the
  /// caller.
  Subjects(reply: Subject(List(Subject(runtime_beam.Msg))))
}

@target(erlang)
type State {
  State(
    core: core.Sluice,
    conns: List(#(String, Conn)),
    subjects: List(#(Subject(runtime_beam.Msg), String)),
    /// The runtimes whose socket the driver closed and did not open again.
    /// Each entry holds the `on_close` function that starts the rejoin of that
    /// runtime.
    dropped: List(#(Subject(runtime_beam.Msg), fn(String) -> Nil)),
    last_registered: Option(String),
  )
}

@target(erlang)
/// The callbacks of one open connection into the runtime that owns it.
///
/// The record keeps `on_close`, and does not discard it, because that function
/// is the only way to tell a runtime that its socket closed. `reconnect` needs
/// that message, and no other part of the driver can produce it.
type Conn {
  Conn(on_event: fn(String, Json) -> Nil, on_close: fn(String) -> Nil)
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
      let core =
        core.handle(state.core, client_id, event, json_to_dynamic(payload))
      process.send(reply, Nil)
      actor.continue(State(..state, core: core))
    }

    TakeAndDeliver(reply) ->
      case core.take(state.core) {
        #(core, Error(Nil)) -> {
          process.send(reply, False)
          actor.continue(State(..state, core: core))
        }
        #(core, Ok(frame)) -> {
          case list.key_find(state.conns, frame.client_id) {
            Ok(conn) -> conn.on_event(frame.event, frame.payload)
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
/// Serialize a queued `Json` push and parse it again as `Dynamic`. This mirrors
/// the server side of a real socket, which decodes the client's push with the
/// server's own `Dynamic`-based frame decoders (`sluice/core`, `frame`).
fn json_to_dynamic(payload: Json) -> Dynamic {
  // `json.to_string` always writes valid JSON, so the parse always succeeds.
  // The error arm reports a null value, because this module must not panic.
  case json.parse(json.to_string(payload), decode.dynamic) {
    Ok(value) -> value
    Error(_) -> dynamic.nil()
  }
}

@target(erlang)
fn client_id_of(
  subjects: List(#(Subject(runtime_beam.Msg), String)),
  subject: Subject(runtime_beam.Msg),
) -> Result(String, Nil) {
  case list.find(subjects, fn(pair) { pair.0 == subject }) {
    Ok(pair) -> Ok(pair.1)
    Error(_) -> Error(Nil)
  }
}
