//// Behavioural tests for `watershed_lustre.claim_once` and
//// `compare_and_set_claim`: the bindings that turn a `runtime.ClaimSubmitReply`
//// into a `claims_kernel.ClaimOutcome` message.
////
//// The in-memory `watershed/sluice_js` stands in for a live floodgate server —
//// `settle` delivers every queued frame synchronously, including the ack that
//// resolves a claim's underlying `Promise`. The one invariant under test: the
//// bindings never dispatch inside the effect that starts them, whether the
//// reply resolves synchronously (`AlreadyClaimed`) or asynchronously
//// (`Pending`). Each test drives the effect with `effect.perform`, settles the
//// sluice, then flushes the microtask queue (`promise.wait(0)`) before reading
//// the captured dispatch — the same two-step `run` / `flush` shape
//// `crdt_test.gleam` uses for the peer-to-peer bindings.

import gleam/dynamic/decode
import gleam/javascript/promise.{type Promise}
import gleam/json
import gleam/list
import gleam/option.{Some}

import lustre/effect.{type Effect}

import watershed.{type Claims}
import watershed/claims_kernel
import watershed/sluice_js
import watershed/transport_js.{type Cell}
import watershed_lustre

const captain_key = "captain"

type Msg {
  Outcome(claims_kernel.ClaimOutcome)
}

/// Perform an effect, routing every dispatched `Msg` into `sink` (prepended, so
/// `messages` reverses it back to arrival order). The non-`dispatch` actions
/// are unused by the claims effects.
fn run(effect_to_run: Effect(Msg), sink: Cell(List(Msg))) -> Nil {
  effect.perform(
    effect_to_run,
    fn(msg) {
      transport_js.set_cell(sink, [msg, ..transport_js.get_cell(sink)])
    },
    fn(_name, _json) { Nil },
    fn(_selector) { Nil },
    fn() { panic as "root action is unused by claims effects" },
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

/// Drain the microtask queue. `deliver_claim_outcome` is at most two
/// microtasks deep (the promise's own resolution, then the module's
/// `queue_microtask` redispatch) — one `wait(0)`, which resolves after a
/// macrotask, is strictly later than either.
fn flush() -> Promise(Nil) {
  promise.wait(0)
}

/// Two clients sharing one `captain` `Claims` channel, seeded the way the
/// release checklist app reaches it through `ensure_claims`: the first client
/// creates it and writes its handle to the root map, the second resolves that
/// handle. The sluice is synchronous, so both are usable straight after
/// `settle`.
fn room() -> #(sluice_js.Sluice, Claims, Claims) {
  let sluice = sluice_js.start(tenant: "default", document: "claims-binding")
  let document_a = sluice_js.connect(sluice, "alice")
  let document_b = sluice_js.connect(sluice, "bob")
  sluice_js.settle(sluice)

  let assert Ok(claims_a) = watershed.create_claims(document_a)
  watershed.set(
    watershed.root(document_a),
    captain_key,
    watershed.claims_handle_of(claims_a),
  )
  sluice_js.settle(sluice)

  let assert Ok(handle) = watershed.get(watershed.root(document_b), captain_key)
  let assert Ok(claims_b) = watershed.resolve_claims(document_b, handle)
  #(sluice, claims_a, claims_b)
}

// ── claim_once ────────────────────────────────────────────────────────────

pub fn claim_once_defers_then_delivers_accepted_test() -> Promise(Nil) {
  let #(sluice, claims_a, _claims_b) = room()
  let sink = new_sink()

  run(
    watershed_lustre.claim_once(
      claims_a,
      captain_key,
      json.string("alice"),
      to_msg: Outcome,
    ),
    sink,
  )

  // Deferral: the reply is `Pending` (nobody holds the seat yet), but nothing
  // dispatches until the ack is sequenced and its promise resolves.
  let assert [] = messages(sink)

  sluice_js.settle(sluice)
  let assert [] = messages(sink)

  use _ <- promise.await(flush())
  let assert [Outcome(claims_kernel.Accepted(value))] = messages(sink)
  let assert Ok("alice") = json.parse(json.to_string(value), decode.string)
  promise.resolve(Nil)
}

pub fn claim_once_on_a_held_seat_defers_then_delivers_lost_test() -> Promise(
  Nil,
) {
  let #(sluice, claims_a, claims_b) = room()

  // Alice claims first and settles — the seat is committed before Bob tries.
  let seed_sink = new_sink()
  run(
    watershed_lustre.claim_once(
      claims_a,
      captain_key,
      json.string("alice"),
      to_msg: Outcome,
    ),
    seed_sink,
  )
  sluice_js.settle(sluice)

  let sink = new_sink()
  run(
    watershed_lustre.claim_once(
      claims_b,
      captain_key,
      json.string("bob"),
      to_msg: Outcome,
    ),
    sink,
  )

  // `AlreadyClaimed` resolves synchronously inside `watershed.claim_once`
  // — the seat is already committed, so there is no wire round trip — but the
  // binding still defers the message to a microtask rather than dispatching
  // inside the effect.
  let assert [] = messages(sink)

  use _ <- promise.await(flush())
  let assert [Outcome(claims_kernel.Lost(Some(current)))] = messages(sink)
  let assert Ok("alice") = json.parse(json.to_string(current), decode.string)
  promise.resolve(Nil)
}

// ── compare_and_set_claim ────────────────────────────────────────────────────

pub fn compare_and_set_claim_takes_over_and_defers_test() -> Promise(Nil) {
  let #(sluice, claims_a, claims_b) = room()

  let seed_sink = new_sink()
  run(
    watershed_lustre.claim_once(
      claims_a,
      captain_key,
      json.string("alice"),
      to_msg: Outcome,
    ),
    seed_sink,
  )
  sluice_js.settle(sluice)

  let sink = new_sink()
  run(
    watershed_lustre.compare_and_set_claim(
      claims_b,
      captain_key,
      json.string("bob"),
      to_msg: Outcome,
    ),
    sink,
  )

  // Take-over goes over the wire like any other claim — the reply is
  // `Pending`, not synchronous — so nothing dispatches before `settle`.
  let assert [] = messages(sink)

  sluice_js.settle(sluice)
  let assert [] = messages(sink)

  use _ <- promise.await(flush())
  let assert [Outcome(claims_kernel.Accepted(value))] = messages(sink)
  let assert Ok("bob") = json.parse(json.to_string(value), decode.string)
  promise.resolve(Nil)
}
