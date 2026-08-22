//// The JavaScript presence driver: one handle over both implementations.
////
//// `start` subscribes to the presence lane and to ripples, then waits. The
//// mode cannot be chosen yet — the server's capability is only known once the
//// handshake settles, and every application starts presence before that. So
//// the first `PresenceSession` frame resolves the mode, and from then on the
//// handle behaves as one implementation or the other:
////
//// - **Server mode** sends `joinPresence` and folds `presence_state` /
////   `presence_diff` into a `presence.Tracker`. It has no heartbeat: the
////   connection is the liveness signal, and the server removes a presence when
////   its socket goes.
//// - **Ripple mode** broadcasts its metadata every `heartbeat_ms` and expires
////   peers it has not heard from within `ttl_ms`, folding both into a
////   `presence.Sessions`.
////
//// Once `Auto` has resolved, the choice sticks. A later reconnect onto a server
//// without the capability reports `UnsupportedPresence` rather than quietly
//// dropping to ripples, because a silent downgrade reads as presence being
//// intermittently broken.
////
//// JavaScript target only; the pure model lives in `watershed/presence`.

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
    /// The runtime handle and a "send one presence ripple" closure stand in
    /// for the document, so the root-schema tag on `Document(root)` stops at
    /// `start` instead of threading through `Driver` into the public
    /// `Handle(a)`.
    runtime: runtime.Runtime,
    broadcast: fn(Json) -> Nil,
    config: Config(a),
    on_event: fn(Event(a)) -> Nil,
    scheduler: Scheduler,
    /// The latest metadata, always. A rejoin after a reconnect sends *this*,
    /// which is what makes "changed while disconnected" arrive on reconnect
    /// without any extra bookkeeping.
    meta: a,
    /// `None` until the first handshake resolves it.
    mode: Option(Mode),
    /// The local session id — the current server-assigned client id.
    session: Option(String),
    /// The ripple-mode presence key: this client's authenticated user id.
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
/// Begin tracking presence on `document` with `initial` as this client's
/// metadata.
///
/// Metadata is required up front rather than announced separately, so there is
/// no window in which the handle is running but has nothing to say.
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
/// `start`, but driven by a supplied clock and timer. Pass
/// `sluice_js.scheduler` to advance a heartbeat or a TTL by stepping a test's
/// logical clock instead of waiting out real time.
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
/// Replace this client's metadata. In server mode the change is pushed
/// immediately; in ripple mode the next heartbeat carries it, and peers see the
/// replacement as a leave followed by a join.
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
/// Stop tracking. Server mode leaves immediately; ripple-mode peers see the
/// departure when the TTL expires, since there is no one to tell.
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
/// Which implementation this handle resolved to, or `None` before the first
/// handshake settles. For diagnostics and tests — the two modes have different
/// failure timing, and hiding which one is running makes that undebuggable.
pub fn mode(handle: Handle(a)) -> Option(Mode) {
  transport_js.get_cell(handle.cell).mode
}

@target(javascript)
/// This client's own session id, for `presence.remote_entries`. `None` before
/// the first handshake.
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
/// A handshake settled: resolve the mode if it is still open, adopt the new
/// session id, and (re)join.
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
/// The connection went away. In server mode the tracker goes back to unsynced,
/// which is what makes a diff arriving before the next snapshot queue rather
/// than apply to a roster that no longer exists.
///
/// No event is emitted: reporting an empty roster on every socket blip would
/// blank the interface for a gap the next snapshot closes in milliseconds.
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
/// An inbound ripple. The session id comes from the ripple's *server-stamped*
/// client id, never from the payload, so a sender cannot name its own session.
/// A ripple without one cannot be attributed and is dropped, as are foreign
/// kinds and malformed metadata — ripples are best-effort input that any peer
/// on the document can emit.
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
/// One heartbeat: refresh our own entry, expire the silent, broadcast, and
/// re-arm.
///
/// The local entry is refreshed rather than special-cased because a client
/// never hears its own ripple, so nothing else would keep it alive — and
/// presence state includes the local session by design.
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
/// Report a change, unless nothing moved — a bare heartbeat must not re-render.
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
