//// The real-browser gate for `watershed/crdt_js`: two browser peers, one
//// reference signaling process, and a PN counter that has to converge.
////
//// Run by `smoke/p2p_clap.mjs`, which starts
//// `tools/signaling/server.mjs`, serves the compiled JavaScript, and
//// evaluates `run` in two separate pages. Each page is a genuine peer —
//// its own `RTCPeerConnection`s, its own `WebSocket` to the signaling
//// service, its own document — so this is the plan's P2P5 gate rather
//// than a simulation of it:
////
//// 1. both pages join the same room through the reference signaling
////    service, with no sequencer and no document server anywhere;
//// 2. each waits until it can see the other, then claps `claps` times
////    without coordinating;
//// 3. both must converge on the same total *and* the same canonical
////    digest;
//// 4. the signaling process must have carried nothing but offers,
////    answers and ICE candidates — which the runner checks from its own
////    instrumentation, on the other side of the wire.
////
//// The document configuration here is the example's, deliberately:
//// `clap-counter/v1` on a PN-counter root. What the pages exercise is
//// what `examples/clap_counter_lustre` ships.
////
//// This is not a `gleam test` case, for the same reason
//// `p2p_browser_smoke` is not: every step waits on the browser, and
//// startest's test body has nowhere to return a promise.

@target(javascript)
import gleam/int
@target(javascript)
import gleam/javascript/promise.{type Promise}
@target(javascript)
import gleam/json
@target(javascript)
import gleam/list
@target(javascript)
import gleam/option.{type Option, None, Some}
@target(javascript)
import gleam/string

@target(javascript)
import watershed/crdt_js.{type CrdtDocument}
@target(javascript)
import watershed/crdt_signaling_js
@target(javascript)
import watershed/p2p
@target(javascript)
import watershed/schema
@target(javascript)
import watershed/transport_js.{type Cell}

@target(javascript)
const compatibility = "clap-counter/v1"

@target(javascript)
/// How long a wait may take before the page gives up. Generous: a
/// headless browser gathering host candidates is not fast, and a hang is
/// far more useful reported than timed out at the first hiccup.
const wait_milliseconds = 20_000

@target(javascript)
@external(javascript, "./p2p_browser_smoke_ffi.mjs", "sleep")
fn sleep(milliseconds: Int) -> Promise(Nil)

@target(javascript)
@external(javascript, "./p2p_browser_smoke_ffi.mjs", "nowMs")
fn now_milliseconds() -> Int

@target(javascript)
type Peer {
  Peer(
    document: Cell(Option(CrdtDocument(schema.PnCounterChannel))),
    statuses: Cell(List(String)),
    problems: Cell(List(String)),
    ready: Cell(Bool),
    /// How many peers the signaling service named in this page's roster.
    /// The page that joined second sees one; the first sees none.
    roster: Cell(Int),
    /// `state` transfers merged so far, and how many of them had
    /// happened when `on_ready` ran. A late joiner's readiness must come
    /// *after* its merge, which is the whole of the late-join contract.
    merges: Cell(Int),
    merges_at_ready: Cell(Int),
    value_at_ready: Cell(Int),
  )
}

@target(javascript)
/// Join `room` through the signaling service at `url`, clap `claps`
/// times once a peer is visible, and resolve to a JSON report.
pub fn run(room: String, url: String, claps: Int) -> Promise(String) {
  let peer =
    Peer(
      document: transport_js.new_cell(None),
      statuses: transport_js.new_cell([]),
      problems: transport_js.new_cell([]),
      ready: transport_js.new_cell(False),
      roster: transport_js.new_cell(-1),
      merges: transport_js.new_cell(0),
      merges_at_ready: transport_js.new_cell(-1),
      value_at_ready: transport_js.new_cell(-1),
    )

  let signaling =
    crdt_signaling_js.websocket_signaling(url: url, on_failure: fn(detail) {
      note(peer, "signaling: " <> detail)
    })

  let config =
    crdt_js.config(
      room_id: room,
      replica_label: "tab",
      compatibility_tag: compatibility,
      root: p2p.pn_counter_root(),
      signaling: signaling,
    )

  let _connection =
    crdt_js.connect(
      config,
      on_ready: fn(outcome) {
        case outcome {
          Ok(document) -> {
            transport_js.set_cell(peer.document, Some(document))
            transport_js.set_cell(peer.ready, True)
            // Read *inside* the callback: what a page is handed at the
            // moment it is told it is ready is exactly what the gate is
            // about.
            transport_js.set_cell(
              peer.merges_at_ready,
              transport_js.get_cell(peer.merges),
            )
            transport_js.set_cell(peer.value_at_ready, value(peer))
          }
          Error(error) -> note(peer, "ready: " <> crdt_js.describe_error(error))
        }
      },
      on_status: fn(status) {
        transport_js.set_cell(peer.statuses, [
          render(status),
          ..transport_js.get_cell(peer.statuses)
        ])
        case status {
          crdt_js.RosterKnown(peers) ->
            transport_js.set_cell(peer.roster, list.length(peers))
          crdt_js.StateMerged(_, _) ->
            transport_js.set_cell(
              peer.merges,
              transport_js.get_cell(peer.merges) + 1,
            )
          crdt_js.PeerRejected(who, error) ->
            note(
              peer,
              "peer " <> who <> " rejected: " <> crdt_js.describe_error(error),
            )
          crdt_js.Failed(error) ->
            note(peer, "failed: " <> crdt_js.describe_error(error))
          crdt_js.SubscriberFailed(address, detail) ->
            note(peer, "subscriber " <> address <> ": " <> detail)
          crdt_js.RejectedByPeer(who, reason, detail) ->
            note(peer, "rejected by " <> who <> ": " <> reason <> " " <> detail)
          crdt_js.Transport(_)
          | crdt_js.TransportError(_)
          | crdt_js.Joined(..)
          | crdt_js.AwaitingState(_)
          | crdt_js.Ready
          | crdt_js.PeerReady(_)
          | crdt_js.PeerGone(_)
          | crdt_js.RelayConnecting(_)
          | crdt_js.RelayUnsupported(_)
          | crdt_js.RelaySyncingStatus
          | crdt_js.RelayRecovering
          | crdt_js.RelayPrimary(_)
          | crdt_js.RelayCheckpointRequested
          | crdt_js.RelayCheckpointed(_)
          | crdt_js.RelayFallback(_)
          | crdt_js.RelayRetry(_)
          | crdt_js.RelayRejected(..)
          | crdt_js.RelayFailed(_) -> Nil
        }
      },
    )

  use seen <- promise.await(wait_until(fn() { peer_count(peer) >= 1 }))
  case seen {
    False ->
      promise.resolve(report(peer, claps, False, "no peer ever appeared"))
    True -> clap_and_converge(peer, claps)
  }
}

@target(javascript)
fn clap_and_converge(peer: Peer, claps: Int) -> Promise(String) {
  // Both pages reach this point independently, so the claps genuinely
  // race: neither waits for the other's total.
  list.each(upto(claps), fn(_) {
    case document_of(peer) {
      Some(document) ->
        case crdt_js.pn_counter_update(crdt_js.root(document), 1) {
          Ok(Nil) -> Nil
          Error(error) -> note(peer, "clap: " <> crdt_js.describe_error(error))
        }
      None -> note(peer, "clap before the document was ready")
    }
  })

  let target = claps * 2
  use converged <- promise.await(wait_until(fn() { value(peer) == target }))
  promise.resolve(
    report(peer, claps, converged, case converged {
      True -> ""
      False ->
        "the totals never converged: this page holds "
        <> int.to_string(value(peer))
        <> " of "
        <> int.to_string(target)
    }),
  )
}

// ─────────────────────────────────────────────────────────────────────────────
// Reporting
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
fn report(peer: Peer, claps: Int, converged: Bool, failure: String) -> String {
  let problems = case failure {
    "" -> problems_of(peer)
    _ -> list.append(problems_of(peer), [failure])
  }
  json.object([
    #("ok", json.bool(converged && problems == [])),
    #("replica", json.string(replica(peer))),
    #("claps", json.int(claps)),
    #("value", json.int(value(peer))),
    #("digest", json.string(digest(peer))),
    #("peers", json.int(peer_count(peer))),
    #("ready", json.bool(transport_js.get_cell(peer.ready))),
    #("rosterPeers", json.int(transport_js.get_cell(peer.roster))),
    #("merges", json.int(transport_js.get_cell(peer.merges))),
    #("mergesAtReady", json.int(transport_js.get_cell(peer.merges_at_ready))),
    #("valueAtReady", json.int(transport_js.get_cell(peer.value_at_ready))),
    #("problems", json.array(problems, json.string)),
    #("statuses", json.array(statuses(peer), json.string)),
  ])
  |> json.to_string
}

@target(javascript)
fn render(status: crdt_js.Status) -> String {
  case status {
    crdt_js.Transport(inner) -> "transport " <> string.inspect(inner)
    crdt_js.TransportError(error) ->
      "transportError " <> crdt_js.describe_error(error)
    crdt_js.Joined(room, _) -> "joined " <> room
    crdt_js.RosterKnown(peers) ->
      "rosterKnown " <> int.to_string(list.length(peers))
    crdt_js.AwaitingState(who) -> "awaitingState " <> who
    crdt_js.Ready -> "ready"
    crdt_js.PeerReady(who) -> "peerReady " <> who
    crdt_js.PeerGone(who) -> "peerGone " <> who
    crdt_js.PeerRejected(who, error) ->
      "peerRejected " <> who <> " " <> crdt_js.describe_error(error)
    crdt_js.StateMerged(who, channels) ->
      "stateMerged " <> who <> " " <> int.to_string(channels)
    crdt_js.RejectedByPeer(who, reason, detail) ->
      "rejectedByPeer " <> who <> " " <> reason <> " " <> detail
    crdt_js.Failed(error) -> "failed " <> crdt_js.describe_error(error)
    crdt_js.SubscriberFailed(address, detail) ->
      "subscriberFailed " <> address <> " " <> detail
    // The gate runs with no sequencer configured, so none of these can
    // fire. Rendered anyway: a smoke page that silently stopped
    // compiling when the facade grew a status would be worse than a
    // line of prose nobody reads.
    crdt_js.RelayConnecting(url) -> "relayConnecting " <> url
    crdt_js.RelayUnsupported(detail) -> "relayUnsupported " <> detail
    crdt_js.RelaySyncingStatus -> "relaySyncing"
    crdt_js.RelayRecovering -> "relayRecovering"
    crdt_js.RelayPrimary(digest) -> "relayPrimary " <> digest
    crdt_js.RelayCheckpointRequested -> "relayCheckpointRequested"
    crdt_js.RelayCheckpointed(digest) -> "relayCheckpointed " <> digest
    crdt_js.RelayFallback(detail) -> "relayFallback " <> detail
    crdt_js.RelayRetry(delay) -> "relayRetry " <> int.to_string(delay)
    crdt_js.RelayRejected(who, error) ->
      "relayRejected " <> who <> " " <> crdt_js.describe_error(error)
    crdt_js.RelayFailed(error) ->
      "relayFailed " <> crdt_js.describe_error(error)
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
fn document_of(peer: Peer) -> Option(CrdtDocument(schema.PnCounterChannel)) {
  transport_js.get_cell(peer.document)
}

@target(javascript)
fn value(peer: Peer) -> Int {
  case document_of(peer) {
    Some(document) ->
      case crdt_js.pn_counter_value(crdt_js.root(document)) {
        Ok(total) -> total
        Error(_) -> -1
      }
    None -> -1
  }
}

@target(javascript)
fn digest(peer: Peer) -> String {
  case document_of(peer) {
    Some(document) -> crdt_js.digest(document)
    None -> ""
  }
}

@target(javascript)
fn replica(peer: Peer) -> String {
  case document_of(peer) {
    Some(document) -> crdt_js.replica_id(document)
    None -> ""
  }
}

@target(javascript)
fn peer_count(peer: Peer) -> Int {
  case document_of(peer) {
    Some(document) -> crdt_js.peer_count(document)
    None -> 0
  }
}

@target(javascript)
fn note(peer: Peer, problem: String) -> Nil {
  transport_js.set_cell(peer.problems, [
    problem,
    ..transport_js.get_cell(peer.problems)
  ])
}

@target(javascript)
fn problems_of(peer: Peer) -> List(String) {
  list.reverse(transport_js.get_cell(peer.problems))
}

@target(javascript)
fn statuses(peer: Peer) -> List(String) {
  list.reverse(transport_js.get_cell(peer.statuses))
}

@target(javascript)
fn wait_until(condition: fn() -> Bool) -> Promise(Bool) {
  wait_from(now_milliseconds(), condition)
}

@target(javascript)
fn wait_from(started: Int, condition: fn() -> Bool) -> Promise(Bool) {
  case condition() {
    True -> promise.resolve(True)
    False ->
      case now_milliseconds() - started > wait_milliseconds {
        True -> promise.resolve(False)
        False -> {
          use _ <- promise.await(sleep(50))
          wait_from(started, condition)
        }
      }
  }
}

@target(javascript)
/// `1..count`, since this stdlib has no `list.range`.
fn upto(count: Int) -> List(Int) {
  build_upto(count, [])
}

@target(javascript)
fn build_upto(remaining: Int, acc: List(Int)) -> List(Int) {
  case remaining <= 0 {
    True -> acc
    False -> build_upto(remaining - 1, [remaining, ..acc])
  }
}
