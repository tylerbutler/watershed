//// Behavioural tests for the peer-to-peer bindings in
//// `watershed_lustre/crdt`.
////
//// These run a *solo* replica: a no-op `Rtc` seam and a signaling hub that
//// admits the tab into an empty room (`Roster([])`) the instant it joins. A
//// replica that is alone is ready immediately, opens no `RTCPeerConnection`,
//// and — because a local mutation fans an event back to the same document's
//// own subscribers — can exercise every callback path this module bridges
//// without a second browser or a fake network.
////
//// The one invariant every test turns on: the bindings never dispatch inside
//// the effect that starts them. A watershed callback fires synchronously, but
//// this module defers it to a microtask, so right after an effect is performed
//// the capture sink is still empty; only after the microtask queue drains
//// (`promise.wait(0)`) do the messages land. Each test drives the effect with
//// `effect.perform`, captures every dispatch, flushes, and asserts on the
//// chronological message log.

import gleam/javascript/promise.{type Promise}
import gleam/list
import gleam/result

import lustre/effect.{type Effect}

import watershed/crdt_js.{
  type CrdtConnection, type CrdtDocument, type Status, type Subscription,
}
import watershed/g_set_kernel
import watershed/or_map_kernel
import watershed/or_set_kernel
import watershed/p2p.{type P2pError}
import watershed/p2p_transport_js.{
  type Rtc, type Signaling, Roster, Rtc, Signaling,
}
import watershed/pn_counter_kernel
import watershed/transport_js.{type Cell}
import watershed/two_p_set_kernel

import watershed_lustre/crdt

// ── Message vocabulary ───────────────────────────────────────────────────────
//
// A concrete `Msg` — the generic `CrdtDocument(root)` a `ready` callback
// carries is collapsed to `Nil` with `result.replace` (each test already holds
// the document it built), so the type needs no parameter.

type Msg {
  Held(CrdtConnection)
  Readied(Result(Nil, P2pError))
  Statused(Status)
  Subscribed(Subscription)
  Counter(pn_counter_kernel.PnCounterEvent)
  Grow(g_set_kernel.GSetEvent)
  TwoPhase(two_p_set_kernel.TwoPSetEvent)
  Observed(or_set_kernel.OrSetEvent)
  Outcome(Result(Nil, P2pError))
}

// ── Harness ──────────────────────────────────────────────────────────────────

/// A signaling adapter that admits the caller into an empty room and reports
/// that roster inside `join`, synchronously — the "I am alone" path.
fn solo_signaling() -> Signaling {
  Signaling(
    join: fn(room, peer, on_signal) {
      on_signal(Roster([]))
      Ok(p2p_transport_js.signaling_session(room: room, peer_id: peer))
    },
    send: fn(_session, _to, _payload) { Nil },
    leave: fn(_session) { Nil },
  )
}

/// An `Rtc` seam that does nothing. A solo replica never opens a peer, so none
/// of these are called; they exist only to satisfy the record.
fn noop_rtc() -> Rtc {
  Rtc(
    open: fn(_peer, _config, _hooks) { Nil },
    open_channel: fn(_peer, _label, _options) { Nil },
    offer: fn(_peer) { Nil },
    accept_offer: fn(_peer, _sdp) { Nil },
    accept_answer: fn(_peer, _sdp) { Nil },
    add_candidate: fn(_peer, _candidate) { Nil },
    signaling_state: fn(_peer) { "closed" },
    send: fn(_peer, _payload) { False },
    close: fn(_peer) { Nil },
    diagnostics: fn(_peer) { "{}" },
  )
}

/// Build (but do not attach) a solo document rooted at `kind`.
fn solo_document(
  kind: p2p.CrdtKind(root),
) -> Result(CrdtDocument(root), P2pError) {
  crdt_js.new_document(crdt_js.config(
    room_id: "test-room",
    replica_label: "tab",
    compatibility_tag: "crdt-test/v1",
    root: kind,
    signaling: solo_signaling(),
  ))
}

/// Perform an effect, routing every dispatched `Msg` into `sink` (prepended, so
/// `messages` reverses it back to arrival order). The non-`dispatch` actions are
/// unused by this module's effects.
fn run(eff: Effect(Msg), sink: Cell(List(Msg))) -> Nil {
  effect.perform(
    eff,
    fn(msg) {
      transport_js.set_cell(sink, [msg, ..transport_js.get_cell(sink)])
    },
    fn(_name, _json) { Nil },
    fn(_selector) { Nil },
    fn() { panic as "root action is unused by crdt effects" },
    fn(_name, _json) { Nil },
    fn(_name, _decoder) { Nil },
    fn(_name) { Nil },
  )
}

fn new_sink() -> Cell(List(Msg)) {
  transport_js.new_cell([])
}

fn messages(sink: Cell(List(Msg))) -> List(Msg) {
  list.reverse(transport_js.get_cell(sink))
}

/// Drain the microtask queue. Everything this module dispatches is deferred at
/// most two microtasks deep (`ready` takes the extra hop that orders it after
/// `connection`), so a single `wait(0)` — which resolves after a macrotask,
/// strictly later than any queued microtask — is enough to observe it all.
fn flush() -> Promise(Nil) {
  promise.wait(0)
}

/// A `ready` constructor that discards the document handle the test already
/// holds, keeping `Msg` monomorphic.
fn readied(outcome: Result(CrdtDocument(root), P2pError)) -> Msg {
  Readied(result.replace(outcome, Nil))
}

/// Attach `document` through the bindings with the standard harness wiring —
/// connection into `Held`, readiness into `readied`, status into `Statused`,
/// over the no-op `Rtc` — routing every dispatch into `sink`.
fn attached(document: CrdtDocument(root), sink: Cell(List(Msg))) -> Nil {
  run(
    crdt.attach_with_rtc(
      document,
      connection: Held,
      ready: readied,
      status: Statused,
      rtc: noop_rtc(),
    ),
    sink,
  )
}

fn is_held(msg: Msg) -> Bool {
  case msg {
    Held(_) -> True
    _ -> False
  }
}

fn is_subscribed(msg: Msg) -> Bool {
  case msg {
    Subscribed(_) -> True
    _ -> False
  }
}

fn has_status(msgs: List(Msg), pred: fn(Status) -> Bool) -> Bool {
  list.any(msgs, fn(msg) {
    case msg {
      Statused(status) -> pred(status)
      _ -> False
    }
  })
}

fn find_connection(msgs: List(Msg)) -> CrdtConnection {
  let assert Ok(Held(connection)) = list.find(msgs, is_held)
  connection
}

fn find_subscription(msgs: List(Msg)) -> Subscription {
  let assert Ok(Subscribed(subscription)) = list.find(msgs, is_subscribed)
  subscription
}

fn subscriptions(msgs: List(Msg)) -> List(Subscription) {
  list.filter_map(msgs, fn(msg) {
    case msg {
      Subscribed(subscription) -> Ok(subscription)
      _ -> Error(Nil)
    }
  })
}

fn count_set_events(msgs: List(Msg)) -> Int {
  list.length(
    list.filter(msgs, fn(msg) {
      case msg {
        Grow(_) | TwoPhase(_) | Observed(_) -> True
        _ -> False
      }
    }),
  )
}

// ── Connect / attach lifecycle ───────────────────────────────────────────────

pub fn attach_defers_then_delivers_connection_ready_and_status_test() -> Promise(
  Nil,
) {
  let sink = new_sink()
  let assert Ok(document) = solo_document(p2p.pn_counter_root())

  attached(document, sink)

  // Deferral: watershed drove readiness synchronously inside the effect, yet
  // nothing has been dispatched — every callback is one microtask away.
  let assert [] = messages(sink)

  use _ <- promise.await(flush())
  let msgs = messages(sink)

  // The connection to retain, and a successful readiness, both arrive.
  let assert True = list.any(msgs, is_held)
  let assert True = list.any(msgs, fn(msg) { msg == Readied(Ok(Nil)) })

  // And in that order: even though readiness resolved synchronously (a solo
  // replica), nothing dispatched before the first `Held` is a `Readied` — an
  // app retains the `CrdtConnection` before it is told the room is usable.
  let assert False =
    list.take_while(msgs, fn(msg) { !is_held(msg) })
    |> list.any(fn(msg) {
      case msg {
        Readied(_) -> True
        _ -> False
      }
    })

  // The lifecycle statuses a solo join walks through are all reported.
  let assert True =
    has_status(msgs, fn(status) {
      case status {
        crdt_js.Joined(_, _) -> True
        _ -> False
      }
    })
  let assert True =
    has_status(msgs, fn(status) {
      case status {
        crdt_js.RosterKnown([]) -> True
        _ -> False
      }
    })
  let assert True =
    has_status(msgs, fn(status) {
      case status {
        crdt_js.Ready -> True
        _ -> False
      }
    })

  promise.resolve(Nil)
}

// ── Subscribe + mutate ───────────────────────────────────────────────────────

pub fn subscribe_and_mutation_defer_then_deliver_event_and_outcome_test() -> Promise(
  Nil,
) {
  let sink = new_sink()
  let assert Ok(document) = solo_document(p2p.pn_counter_root())
  attached(document, sink)
  use _ <- promise.await(flush())

  let counter = crdt_js.root(document)
  run(
    crdt.subscribe_pn_counter(counter, subscribed: Subscribed, event: Counter),
    sink,
  )
  let before = messages(sink)
  run(
    crdt.perform(fn() { crdt_js.pn_counter_update(counter, 5) }, Outcome),
    sink,
  )

  // Both the subscription handle and the mutation's event/outcome are deferred:
  // performing them adds nothing to the sink until the queue drains.
  let assert True = messages(sink) == before

  use _ <- promise.await(flush())
  let msgs = messages(sink)

  // The subscription handle came back (so it can be retained for unsubscribe).
  let assert True = list.any(msgs, is_subscribed)
  // The local edit fanned an event carrying the new total, 5.
  let assert True =
    list.any(msgs, fn(msg) {
      case msg {
        Counter(pn_counter_kernel.Updated(_applied, 5)) -> True
        _ -> False
      }
    })
  // The mutation reported a typed success.
  let assert True = list.any(msgs, fn(msg) { msg == Outcome(Ok(Nil)) })
  // And the read-side agrees.
  let assert Ok(5) = crdt_js.pn_counter_value(counter)

  promise.resolve(Nil)
}

// ── Unsubscribe ──────────────────────────────────────────────────────────────

pub fn unsubscribe_stops_events_without_stopping_mutations_test() -> Promise(
  Nil,
) {
  let sink = new_sink()
  let assert Ok(document) = solo_document(p2p.pn_counter_root())
  attached(document, sink)
  use _ <- promise.await(flush())

  let counter = crdt_js.root(document)
  run(
    crdt.subscribe_pn_counter(counter, subscribed: Subscribed, event: Counter),
    sink,
  )
  use _ <- promise.await(flush())
  let subscription = find_subscription(messages(sink))

  // One edit while subscribed: an event lands.
  run(
    crdt.perform(fn() { crdt_js.pn_counter_update(counter, 1) }, Outcome),
    sink,
  )
  use _ <- promise.await(flush())
  let events_while_subscribed =
    list.length(list.filter(messages(sink), is_counter))
  let assert True = events_while_subscribed >= 1

  // Drop the subscription, then edit again.
  run(crdt.unsubscribe(subscription), sink)
  run(
    crdt.perform(fn() { crdt_js.pn_counter_update(counter, 1) }, Outcome),
    sink,
  )
  use _ <- promise.await(flush())

  // No new event fired…
  let assert True =
    list.length(list.filter(messages(sink), is_counter))
    == events_while_subscribed
  // …but the mutation still succeeded and the value still advanced.
  let assert Ok(2) = crdt_js.pn_counter_value(counter)

  promise.resolve(Nil)
}

fn is_counter(msg: Msg) -> Bool {
  case msg {
    Counter(_) -> True
    _ -> False
  }
}

// ── Close cleanup + typed errors ─────────────────────────────────────────────

pub fn close_cleans_up_and_later_edits_are_typed_errors_test() -> Promise(Nil) {
  let sink = new_sink()
  let assert Ok(document) = solo_document(p2p.pn_counter_root())
  attached(document, sink)
  use _ <- promise.await(flush())

  let connection = find_connection(messages(sink))
  let counter = crdt_js.root(document)

  run(crdt.close(connection), sink)
  // Closing the retained connection stops the document.
  let assert True = crdt_js.is_closed(document)

  // A mutation after close is a typed `DocumentClosed`, never a silent success.
  run(
    crdt.perform(fn() { crdt_js.pn_counter_update(counter, 1) }, Outcome),
    sink,
  )
  use _ <- promise.await(flush())
  let assert True =
    list.any(messages(sink), fn(msg) {
      msg == Outcome(Error(p2p.DocumentClosed))
    })

  promise.resolve(Nil)
}

// ── Transport policy is wired through readiness ──────────────────────────────

pub fn sequenced_only_without_a_sequencer_fails_readiness_test() -> Promise(Nil) {
  let sink = new_sink()
  let assert Ok(document) =
    crdt_js.config(
      room_id: "test-room",
      replica_label: "tab",
      compatibility_tag: "crdt-test/v1",
      root: p2p.pn_counter_root(),
      signaling: solo_signaling(),
    )
    |> crdt_js.with_transport_policy(crdt_js.SequencedOnly)
    |> crdt_js.new_document

  // The configured policy reads back verbatim.
  let assert crdt_js.SequencedOnly = crdt_js.policy(document)

  attached(document, sink)
  use _ <- promise.await(flush())

  // No sequencer to be ready on → readiness resolves to a typed error.
  let assert True =
    list.any(messages(sink), fn(msg) {
      case msg {
        Readied(Error(p2p.SequencerUnavailable(_detail))) -> True
        _ -> False
      }
    })

  promise.resolve(Nil)
}

pub fn p2p_only_solo_replica_becomes_ready_on_the_mesh_test() -> Promise(Nil) {
  let sink = new_sink()
  let assert Ok(document) =
    crdt_js.config(
      room_id: "test-room",
      replica_label: "tab",
      compatibility_tag: "crdt-test/v1",
      root: p2p.pn_counter_root(),
      signaling: solo_signaling(),
    )
    |> crdt_js.with_transport_policy(crdt_js.P2pOnly)
    |> crdt_js.new_document

  let assert crdt_js.P2pOnly = crdt_js.policy(document)

  attached(document, sink)
  use _ <- promise.await(flush())

  let assert True =
    list.any(messages(sink), fn(msg) { msg == Readied(Ok(Nil)) })
  // Deltas stay on the mesh.
  let assert crdt_js.PeerToPeer = crdt_js.effective_path(document)

  promise.resolve(Nil)
}

// ── Invalid input stays a typed Error ────────────────────────────────────────

pub fn an_invalid_mutation_surfaces_as_a_typed_error_test() -> Promise(Nil) {
  let sink = new_sink()
  let assert Ok(document) =
    solo_document(p2p.or_map_root(or_map_kernel.RegisterMode))
  attached(document, sink)
  use _ <- promise.await(flush())

  let map = crdt_js.root(document)
  // `increment` is a tally op; on a `RegisterMode` map it must fail rather than
  // silently succeed — the binding passes the `Error` through untouched.
  run(
    crdt.perform(
      fn() { crdt_js.or_map_increment(map, key: "k", amount: 1) },
      Outcome,
    ),
    sink,
  )
  use _ <- promise.await(flush())

  let assert True =
    list.any(messages(sink), fn(msg) {
      case msg {
        Outcome(Error(_error)) -> True
        _ -> False
      }
    })

  promise.resolve(Nil)
}

// ── Multiple channels, independent subscribe / mutate / cleanup ──────────────

pub fn multiple_channels_subscribe_mutate_and_clean_up_independently_test() -> Promise(
  Nil,
) {
  let sink = new_sink()
  let assert Ok(document) = solo_document(p2p.pn_counter_root())
  attached(document, sink)
  use _ <- promise.await(flush())

  // Register three channels of different kinds off the same document.
  let assert Ok(grow) = crdt_js.create_channel(document, p2p.g_set_root())
  let assert Ok(two_phase) =
    crdt_js.create_channel(document, p2p.two_p_set_root())
  let assert Ok(observed) = crdt_js.create_channel(document, p2p.or_set_root())

  // Subscribe to each; each subscription arrives to be retained.
  run(crdt.subscribe_g_set(grow, subscribed: Subscribed, event: Grow), sink)
  run(
    crdt.subscribe_two_p_set(two_phase, subscribed: Subscribed, event: TwoPhase),
    sink,
  )
  run(
    crdt.subscribe_or_set(observed, subscribed: Subscribed, event: Observed),
    sink,
  )
  use _ <- promise.await(flush())
  let retained = subscriptions(messages(sink))
  let assert 3 = list.length(retained)

  // Mutate each; each fires exactly its own event type.
  run(crdt.perform(fn() { crdt_js.g_set_add(grow, "a") }, Outcome), sink)
  run(
    crdt.perform(fn() { crdt_js.two_p_set_add(two_phase, "b") }, Outcome),
    sink,
  )
  run(crdt.perform(fn() { crdt_js.or_set_add(observed, "c") }, Outcome), sink)
  use _ <- promise.await(flush())
  let msgs = messages(sink)
  let assert True =
    list.any(msgs, fn(msg) {
      case msg {
        Grow(g_set_kernel.ElementAdded("a")) -> True
        _ -> False
      }
    })
  let assert True =
    list.any(msgs, fn(msg) {
      case msg {
        TwoPhase(two_p_set_kernel.ElementAdded("b")) -> True
        _ -> False
      }
    })
  let assert True =
    list.any(msgs, fn(msg) {
      case msg {
        Observed(or_set_kernel.ElementAdded("c")) -> True
        _ -> False
      }
    })
  // Read-side agrees for every channel.
  let assert Ok(True) = crdt_js.g_set_contains(grow, "a")
  let assert Ok(True) = crdt_js.two_p_set_contains(two_phase, "b")
  let assert Ok(True) = crdt_js.or_set_contains(observed, "c")

  let events_before_cleanup = count_set_events(messages(sink))

  // Unsubscribe every channel, then mutate every channel again.
  list.each(retained, fn(subscription) {
    run(crdt.unsubscribe(subscription), sink)
  })
  run(crdt.perform(fn() { crdt_js.g_set_add(grow, "d") }, Outcome), sink)
  run(
    crdt.perform(fn() { crdt_js.two_p_set_add(two_phase, "e") }, Outcome),
    sink,
  )
  run(crdt.perform(fn() { crdt_js.or_set_add(observed, "f") }, Outcome), sink)
  use _ <- promise.await(flush())

  // No channel produced a new event after cleanup…
  let assert True = count_set_events(messages(sink)) == events_before_cleanup
  // …though the edits themselves still applied.
  let assert Ok(True) = crdt_js.g_set_contains(grow, "d")
  let assert Ok(True) = crdt_js.two_p_set_contains(two_phase, "e")
  let assert Ok(True) = crdt_js.or_set_contains(observed, "f")

  promise.resolve(Nil)
}
