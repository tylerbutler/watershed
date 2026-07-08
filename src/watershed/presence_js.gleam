//// JavaScript presence driver — the heartbeat/prune lifecycle that the sudoku
//// prototype spread across its `init`/`update`, promoted behind a small handle.
////
//// `start` subscribes to inbound ripples, decodes the presence envelope, folds
//// live peers into a `presence.Peers`, and calls `on_change` only when the
//// visible roster actually changes. A heartbeat timer (suppressed until the
//// first `announce`) rebroadcasts the last payload and prunes expired peers.
////
//// JavaScript target only — the erlang ripple surface is deferred (see the
//// typed-presence plan). The pure state machine lives in `watershed/presence`.

@target(javascript)
import gleam/dynamic/decode.{type Decoder}
@target(javascript)
import gleam/json.{type Json}
@target(javascript)
import gleam/list
@target(javascript)
import gleam/option.{type Option, None, Some}

@target(javascript)
import watershed/presence.{type Config, type Peer}
@target(javascript)
import watershed/transport_js.{type Cell, type TimerId}
@target(javascript)
import watershed_js.{type Document, type Ripple}

@target(javascript)
/// A running presence session. Cancel it with `stop`.
pub opaque type Handle(a) {
  Handle(cell: Cell(Driver(a)))
}

@target(javascript)
type Driver(a) {
  Driver(
    document: Document,
    user_id: String,
    config: Config,
    encode: fn(a) -> Json,
    on_change: fn(List(Peer(a))) -> Nil,
    peers: presence.Peers(a),
    /// The last payload we announced, rebroadcast on each heartbeat. `None`
    /// until the first `announce`, which is what suppresses idle heartbeats.
    last: Option(a),
    timer: Option(TimerId),
    stopped: Bool,
  )
}

@target(javascript)
/// Begin tracking presence on `document`. `on_change` fires with the sorted
/// roster whenever the visible set of peers changes (peers that only bumped
/// their heartbeat are silent), so callers may re-render unconditionally.
pub fn start(
  document document: Document,
  user_id user_id: String,
  config config: Config,
  encode encode: fn(a) -> Json,
  decode decoder: Decoder(a),
  on_change on_change: fn(List(Peer(a))) -> Nil,
) -> Handle(a) {
  let cell =
    transport_js.new_cell(Driver(
      document: document,
      user_id: user_id,
      config: config,
      encode: encode,
      on_change: on_change,
      peers: presence.new(),
      last: None,
      timer: None,
      stopped: False,
    ))
  watershed_js.subscribe_ripples(document, fn(ripple) {
    on_ripple(cell, decoder, ripple)
  })
  Handle(cell)
}

@target(javascript)
/// Update this client's payload and broadcast it immediately, starting the
/// heartbeat if it wasn't already running.
pub fn announce(handle: Handle(a), payload: a) -> Nil {
  let driver = transport_js.get_cell(handle.cell)
  case driver.stopped {
    True -> Nil
    False -> {
      transport_js.set_cell(handle.cell, Driver(..driver, last: Some(payload)))
      broadcast(handle.cell, payload)
      ensure_heartbeat(handle.cell)
    }
  }
}

@target(javascript)
/// Cancel the heartbeat and stop reacting to inbound ripples. The underlying
/// ripple subscription can't be detached (fire-and-forget), so a `stopped`
/// guard drops any further ripples.
pub fn stop(handle: Handle(a)) -> Nil {
  let driver = transport_js.get_cell(handle.cell)
  case driver.timer {
    Some(id) -> transport_js.clear_timer(id)
    None -> Nil
  }
  transport_js.set_cell(
    handle.cell,
    Driver(..driver, timer: None, stopped: True),
  )
}

// ── Internals ────────────────────────────────────────────────────────────────

@target(javascript)
fn on_ripple(
  cell: Cell(Driver(a)),
  decoder: Decoder(a),
  ripple: Ripple,
) -> Nil {
  let driver = transport_js.get_cell(cell)
  case driver.stopped {
    True -> Nil
    False ->
      case
        decode.run(
          watershed_js.ripple_content(ripple),
          presence.decode_envelope(decode: decoder),
        )
      {
        // Skip our own echo; drop foreign kinds / malformed payloads silently.
        Ok(#(user, payload)) if user != driver.user_id -> {
          let before = visible(driver.peers)
          let peers =
            presence.observe(driver.peers, user, payload, transport_js.now_ms())
          transport_js.set_cell(cell, Driver(..driver, peers: peers))
          fire_if_changed(cell, before)
        }
        _ -> Nil
      }
  }
}

@target(javascript)
fn broadcast(cell: Cell(Driver(a)), payload: a) -> Nil {
  let driver = transport_js.get_cell(cell)
  watershed_js.submit_ripple(
    driver.document,
    ripple_type: presence.ripple_type,
    content: presence.encode_envelope(driver.user_id, driver.encode, payload),
  )
}

@target(javascript)
fn ensure_heartbeat(cell: Cell(Driver(a))) -> Nil {
  case transport_js.get_cell(cell).timer {
    Some(_) -> Nil
    None -> schedule(cell)
  }
}

@target(javascript)
fn schedule(cell: Cell(Driver(a))) -> Nil {
  let driver = transport_js.get_cell(cell)
  let timer =
    transport_js.set_timer(fn() { tick(cell) }, driver.config.heartbeat_ms)
  transport_js.set_cell(cell, Driver(..driver, timer: Some(timer)))
}

@target(javascript)
fn tick(cell: Cell(Driver(a))) -> Nil {
  let driver = transport_js.get_cell(cell)
  case driver.stopped {
    True -> Nil
    False -> {
      let before = visible(driver.peers)
      let peers =
        presence.prune(driver.peers, driver.config, transport_js.now_ms())
      transport_js.set_cell(cell, Driver(..driver, peers: peers, timer: None))
      fire_if_changed(cell, before)
      case transport_js.get_cell(cell).last {
        Some(payload) -> broadcast(cell, payload)
        None -> Nil
      }
      schedule(cell)
    }
  }
}

@target(javascript)
/// The user-visible projection: user id + payload, dropping `last_seen` so a
/// bare heartbeat (same payload, newer timestamp) reads as no change.
fn visible(peers: presence.Peers(a)) -> List(#(String, a)) {
  presence.roster(peers)
  |> list.map(fn(p) { #(p.user, p.payload) })
}

@target(javascript)
fn fire_if_changed(cell: Cell(Driver(a)), before: List(#(String, a))) -> Nil {
  let driver = transport_js.get_cell(cell)
  case visible(driver.peers) == before {
    True -> Nil
    False -> driver.on_change(presence.roster(driver.peers))
  }
}
