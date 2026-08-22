//// The JavaScript presence driver: one handle over the two implementations.
////
//// `start` subscribes to the presence lane and to the ripples, then it waits.
//// It cannot select the mode yet. The capability of the server is known only
//// after the handshake settles, and every application starts presence before
//// that point. The first `PresenceSession` frame thus resolves the mode. After
//// that, the handle behaves as one implementation or as the other:
////
//// - **Server mode** sends `joinPresence` and folds `presence_state` and
////   `presence_diff` into a `presence.Tracker`. It has no heartbeat. The
////   connection is the liveness signal, and the server removes a presence when
////   its socket closes.
//// - **Ripple mode** broadcasts its metadata every `heartbeat_ms`, and it
////   removes a peer that has sent nothing for `ttl_ms`. It folds both events
////   into a `presence.Sessions` value.
////
//// After `Auto` resolves, the choice does not change. A later reconnect to a
//// server without the capability reports `UnsupportedPresence`. It does not
//// change to ripple mode, because a silent downgrade makes presence look
//// intermittently broken.
////
//// JavaScript target only. The pure model is in `watershed/presence`.

@target(javascript)
import gleam/dynamic/decode
@target(javascript)
import gleam/json.{type Json}
@target(javascript)
import gleam/list
@target(javascript)
import gleam/option.{type Option, None, Some}

@target(javascript)
import watershed/presence.{type Config, type Event, type Mode}
@target(javascript)
import watershed/runtime.{type PresenceFrame}
@target(javascript)
import watershed/transport_js.{type Cell, type Scheduler}
@target(javascript)
import watershed.{type Document, type Ripple}

@target(javascript)
/// A running presence session. Stop it with `stop`.
pub opaque type Handle(a) {
  Handle(cell: Cell(Driver(a)))
}

@target(javascript)
type Driver(a) {
  Driver(
    /// The runtime handle and a closure that sends one presence ripple replace
    /// the document here. The root-schema tag on `Document(root)` thus stops at
    /// `start`. It does not go through `Driver` into the public `Handle(a)`
    /// type.
    runtime: runtime.Runtime,
    broadcast: fn(Json) -> Nil,
    config: Config(a),
    on_event: fn(Event(a)) -> Nil,
    scheduler: Scheduler,
    /// The most recent metadata, always. A rejoin after a reconnect sends this
    /// value. A change that the client made while it was disconnected thus
    /// arrives on the reconnect, and the driver needs no other record of it.
    meta: a,
    /// `None` until the first handshake resolves it.
    mode: Option(Mode),
    /// The local session id, which is the current client id that the server
    /// assigned.
    session: Option(String),
    /// The presence key in ripple mode, which is the authenticated user id of
    /// this client.
    key: String,
    implementation: Implementation(a),
    stopped: Bool,
  )
}

@target(javascript)
type Implementation(a) {
  Unresolved
  ServerPresence(tracker: presence.Tracker(a))
  RipplePresence(sessions: presence.Sessions(a), cancel: Option(fn() -> Nil))
}

@target(javascript)
/// Start to track presence on `document`, with `initial` as the metadata of
/// this client.
///
/// The metadata is a required argument, and not a separate announcement. There
/// is thus no interval in which the handle runs but has no metadata to send.
pub fn start(
  document document: Document(root),
  config config: Config(a),
  initial initial: a,
  on_event on_event: fn(Event(a)) -> Nil,
) -> Handle(a) {
  start_with_scheduler(
    document: document,
    config: config,
    initial: initial,
    on_event: on_event,
    scheduler: transport_js.real_scheduler(),
  )
}

@target(javascript)
/// `start`, but with a supplied clock and timer. Give `sluice_js.scheduler` to
/// advance a heartbeat or a TTL with the logical clock of a test, instead of a
/// wait for the real time.
pub fn start_with_scheduler(
  document document: Document(root),
  config config: Config(a),
  initial initial: a,
  on_event on_event: fn(Event(a)) -> Nil,
  scheduler scheduler: Scheduler,
) -> Handle(a) {
  let runtime = watershed.runtime_of(document)
  let cell =
    transport_js.new_cell(Driver(
      runtime: runtime,
      broadcast: fn(content) {
        watershed.submit_ripple(
          document,
          ripple_type: presence.ripple_type,
          content: content,
        )
      },
      config: config,
      on_event: on_event,
      scheduler: scheduler,
      meta: initial,
      mode: None,
      session: None,
      key: runtime.user_id(runtime),
      implementation: Unresolved,
      stopped: False,
    ))

  // Both subscriptions are registered up front and unconditionally. Neither can
  // be detached, so registering lazily would buy nothing; each is inert until
  // the matching implementation is chosen.
  runtime.subscribe_presence(runtime, fn(frame) { on_frame(cell, frame) })
  watershed.subscribe_ripples(document, fn(ripple) {
    on_ripple(cell, ripple)
  })
  Handle(cell)
}

@target(javascript)
/// Replace the metadata of this client. In server mode the driver pushes the
/// change immediately. In ripple mode the next heartbeat carries it, and the
/// peers see the change as a leave and then a join.
pub fn update(handle: Handle(a), meta: a) -> Nil {
  let driver = transport_js.get_cell(handle.cell)
  case driver.stopped {
    True -> Nil
    False -> {
      transport_js.set_cell(handle.cell, Driver(..driver, meta: meta))
      case driver.implementation, driver.session {
        // No session means nothing to update on the server, and the rejoin
        // after the next handshake will carry the new value anyway. This is
        // also what stops an update racing a disconnect from resurrecting a
        // presence the server has already cleaned up.
        ServerPresence(_), Some(_) ->
          push(handle.cell, presence.event_update, meta)
        ServerPresence(_), None -> Nil
        RipplePresence(_, _), _ -> broadcast_ripple(handle.cell, meta)
        Unresolved, _ -> Nil
      }
    }
  }
}

@target(javascript)
/// Stop the tracking. In server mode the client leaves immediately. In ripple
/// mode the peers see the departure when the TTL expires, because there is no
/// message to send.
pub fn stop(handle: Handle(a)) -> Nil {
  let driver = transport_js.get_cell(handle.cell)
  case driver.stopped {
    True -> Nil
    False -> {
      case driver.implementation {
        ServerPresence(_) ->
          runtime.send_presence(
            runtime_of(driver),
            presence.event_leave,
            presence.encode_leave(),
          )
        RipplePresence(_, cancel) ->
          case cancel {
            Some(cancel) -> cancel()
            None -> Nil
          }
        Unresolved -> Nil
      }
      // The ripple subscription cannot be detached (ripples are
      // fire-and-forget), so a `stopped` guard is what drops later traffic.
      transport_js.set_cell(handle.cell, Driver(..driver, stopped: True))
    }
  }
}

@target(javascript)
/// The implementation that this handle resolved to. The result is `None`
/// before the first handshake settles. Use this function for diagnostics and
/// tests. The two modes fail at different times, and you cannot debug that
/// difference if the mode is hidden.
pub fn mode(handle: Handle(a)) -> Option(Mode) {
  transport_js.get_cell(handle.cell).mode
}

@target(javascript)
/// The session id of this client, for `presence.remote_entries`. The result is
/// `None` before the first handshake.
pub fn local_session(handle: Handle(a)) -> Option(String) {
  transport_js.get_cell(handle.cell).session
}

// ── Lane handling ────────────────────────────────────────────────────────────

@target(javascript)
fn on_frame(cell: Cell(Driver(a)), frame: PresenceFrame) -> Nil {
  let driver = transport_js.get_cell(cell)
  case driver.stopped {
    True -> Nil
    False ->
      case frame {
        runtime.PresenceSession(client_id, presence_v1) ->
          on_session(cell, client_id, presence_v1)
        runtime.PresenceSessionLost -> on_session_lost(cell)
        runtime.PresenceState(payload) ->
          case driver.implementation {
            ServerPresence(tracker) ->
              case
                decode.run(
                  payload,
                  presence.presence_state_decoder(
                    decode: presence.config_decoder(driver.config),
                  ),
                )
              {
                Error(_) -> Nil
                Ok(snapshot) -> {
                  let #(next, events) = presence.apply_state(tracker, snapshot)
                  commit_server(cell, next, events)
                }
              }
            _ -> Nil
          }
        runtime.PresenceDiff(payload) ->
          case driver.implementation {
            ServerPresence(tracker) ->
              case
                decode.run(
                  payload,
                  presence.presence_diff_decoder(
                    decode: presence.config_decoder(driver.config),
                  ),
                )
              {
                Error(_) -> Nil
                Ok(diff) -> {
                  let #(next, events) = presence.apply_diff(tracker, diff)
                  commit_server(cell, next, events)
                }
              }
            _ -> Nil
          }
        runtime.PresenceError(payload) ->
          case decode.run(payload, presence.presence_error_decoder()) {
            Error(_) -> Nil
            Ok(error) -> driver.on_event(presence.Failed(error))
          }
      }
  }
}

@target(javascript)
/// A handshake settled. Resolve the mode if it is not resolved yet, take the
/// new session id, and join again.
fn on_session(
  cell: Cell(Driver(a)),
  client_id: String,
  presence_v1: Bool,
) -> Nil {
  let driver = transport_js.get_cell(cell)
  let resolved = case driver.mode {
    Some(mode) -> mode
    None ->
      case presence.config_mode(driver.config) {
        presence.Ripple -> presence.Ripple
        presence.Server -> presence.Server
        presence.Auto ->
          case presence_v1 {
            True -> presence.Server
            False -> presence.Ripple
          }
      }
  }

  case resolved, presence_v1 {
    presence.Server, False -> {
      // Forced server mode against a server without the lane. Report and stop
      // rather than degrade: the caller asked for connection-backed presence
      // and would otherwise get heartbeat presence without being told.
      transport_js.set_cell(
        cell,
        Driver(..driver, mode: Some(resolved), stopped: True),
      )
      driver.on_event(presence.Failed(presence.UnsupportedPresence))
    }
    presence.Server, True -> {
      transport_js.set_cell(
        cell,
        Driver(
          ..driver,
          mode: Some(resolved),
          session: Some(client_id),
          // A fresh session gets a fresh tracker: diffs from the previous one
          // describe a roster that no longer exists.
          implementation: ServerPresence(presence.tracker()),
        ),
      )
      push(cell, presence.event_join, driver.meta)
    }
    _, _ -> {
      // Carry the roster across a reconnect — remote peers are still there —
      // but cancel the old heartbeat before `tick` arms a new one, or the two
      // would both keep firing.
      let sessions = case driver.implementation {
        RipplePresence(sessions, cancel) -> {
          case cancel {
            Some(cancel) -> cancel()
            None -> Nil
          }
          sessions
        }
        _ -> presence.sessions()
      }
      transport_js.set_cell(
        cell,
        Driver(
          ..driver,
          mode: Some(resolved),
          session: Some(client_id),
          implementation: RipplePresence(sessions, None),
        ),
      )
      // Re-key the local entry under the new session id and start beating.
      // Peers keyed under the old id simply expire.
      tick(cell)
    }
  }
}

@target(javascript)
/// The connection closed. In server mode the tracker returns to the unsynced
/// state. A diff that arrives before the next snapshot thus queues. It does not
/// apply to a roster that no longer exists.
///
/// The driver emits no event. A report of an empty roster on every short socket
/// failure would clear the interface for an interval that the next snapshot
/// closes in milliseconds.
fn on_session_lost(cell: Cell(Driver(a))) -> Nil {
  let driver = transport_js.get_cell(cell)
  case driver.implementation {
    ServerPresence(tracker) ->
      transport_js.set_cell(
        cell,
        Driver(
          ..driver,
          session: None,
          implementation: ServerPresence(presence.reset(tracker)),
        ),
      )
    RipplePresence(sessions, cancel) -> {
      // Drop only our own entry; remote peers keep their TTL, which is exactly
      // the soft-presence behavior ripple mode promises.
      let #(sessions, _) = case driver.session {
        Some(session) -> presence.forget_session(sessions, session)
        None -> #(sessions, presence.no_change())
      }
      transport_js.set_cell(
        cell,
        Driver(
          ..driver,
          session: None,
          implementation: RipplePresence(sessions, cancel),
        ),
      )
    }
    Unresolved -> Nil
  }
}

// ── Server mode ──────────────────────────────────────────────────────────────

@target(javascript)
fn commit_server(
  cell: Cell(Driver(a)),
  tracker: presence.Tracker(a),
  events: List(Event(a)),
) -> Nil {
  let driver = transport_js.get_cell(cell)
  transport_js.set_cell(
    cell,
    Driver(..driver, implementation: ServerPresence(tracker)),
  )
  list.each(events, driver.on_event)
}

@target(javascript)
fn push(cell: Cell(Driver(a)), event: String, meta: a) -> Nil {
  let driver = transport_js.get_cell(cell)
  runtime.send_presence(
    runtime_of(driver),
    event,
    presence.encode_command(presence.config_encode(driver.config), meta),
  )
}

@target(javascript)
fn runtime_of(driver: Driver(a)) -> runtime.Runtime {
  driver.runtime
}

// ── Ripple mode ──────────────────────────────────────────────────────────────

@target(javascript)
/// An inbound ripple. The session id comes from the *server-stamped* client id
/// of the ripple, and never from the payload, so a sender cannot select its own
/// session. The driver drops a ripple without that id, because it cannot
/// attribute the ripple. It also drops a foreign kind and malformed metadata. A
/// ripple is best-effort input, and any peer on the document can emit one.
fn on_ripple(cell: Cell(Driver(a)), ripple: Ripple) -> Nil {
  let driver = transport_js.get_cell(cell)
  case driver.stopped, driver.implementation {
    False, RipplePresence(sessions, cancel) ->
      case
        watershed.ripple_client_id(ripple),
        decode.run(
          watershed.ripple_content(ripple),
          presence.ripple_decoder(decode: presence.config_decoder(driver.config)),
        )
      {
        Some(session_id), Ok(#(key, meta)) -> {
          let clock = driver.scheduler.now_ms
          let #(sessions, diff) =
            presence.observe_session(sessions, session_id, key, meta, clock())
          commit_ripple(cell, sessions, cancel)
          report(cell, sessions, diff)
        }
        _, _ -> Nil
      }
    _, _ -> Nil
  }
}

@target(javascript)
/// One heartbeat. Refresh the local entry, remove the silent peers, broadcast,
/// and arm the timer again.
///
/// The function refreshes the local entry, and it does not treat that entry as
/// a special case. A client never receives its own ripple, so nothing else
/// would keep the entry alive. The presence state includes the local session by
/// design.
fn tick(cell: Cell(Driver(a))) -> Nil {
  let driver = transport_js.get_cell(cell)
  case driver.stopped, driver.implementation {
    False, RipplePresence(sessions, cancel) -> {
      let clock = driver.scheduler.now_ms
      let now = clock()
      let #(sessions, joined) = case driver.session {
        Some(session) ->
          presence.observe_session(
            sessions,
            session,
            driver.key,
            driver.meta,
            now,
          )
        None -> #(sessions, presence.no_change())
      }
      let #(sessions, expired) =
        presence.expire_sessions(
          sessions,
          presence.config_ttl_ms(driver.config),
          now,
        )
      // Store once, then report both changes against the settled roster — an
      // observer that saw the join against a pre-expiry roster would render a
      // peer this same tick just removed.
      commit_ripple(cell, sessions, cancel)
      report(cell, sessions, joined)
      report(cell, sessions, expired)

      broadcast_ripple(cell, driver.meta)
      schedule(cell)
    }
    _, _ -> Nil
  }
}

@target(javascript)
fn schedule(cell: Cell(Driver(a))) -> Nil {
  let driver = transport_js.get_cell(cell)
  case driver.implementation {
    RipplePresence(sessions, previous) -> {
      case previous {
        Some(cancel) -> cancel()
        None -> Nil
      }
      let arm = driver.scheduler.schedule
      let cancel =
        arm(fn() { tick(cell) }, presence.config_heartbeat_ms(driver.config))
      transport_js.set_cell(
        cell,
        Driver(..driver, implementation: RipplePresence(sessions, Some(cancel))),
      )
    }
    _ -> Nil
  }
}

@target(javascript)
fn broadcast_ripple(cell: Cell(Driver(a)), meta: a) -> Nil {
  let driver = transport_js.get_cell(cell)
  driver.broadcast(presence.encode_ripple(
    driver.key,
    presence.config_encode(driver.config),
    meta,
  ))
}

@target(javascript)
fn commit_ripple(
  cell: Cell(Driver(a)),
  sessions: presence.Sessions(a),
  cancel: Option(fn() -> Nil),
) -> Nil {
  let driver = transport_js.get_cell(cell)
  transport_js.set_cell(
    cell,
    Driver(..driver, implementation: RipplePresence(sessions, cancel)),
  )
}

@target(javascript)
/// Report a change. If nothing changed, report nothing, because a heartbeat
/// alone must not cause a re-render.
fn report(
  cell: Cell(Driver(a)),
  sessions: presence.Sessions(a),
  diff: presence.Diff(a),
) -> Nil {
  case presence.diff_is_empty(diff) {
    True -> Nil
    False ->
      transport_js.get_cell(cell).on_event(presence.Changed(
        diff,
        presence.session_entries(sessions),
      ))
  }
}
