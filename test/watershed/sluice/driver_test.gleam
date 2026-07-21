//// Ungated convergence tests driving real `watershed` documents against the
//// in-memory `sluice` (plan HM3). These mirror the core subset of
//// `integration_test.gleam` — but run with no levee server and no env gate,
//// and assert *deterministically* after an explicit `settle` rather than
//// polling with `wait_until`.

@target(erlang)
import gleam/dynamic/decode
@target(erlang)
import gleam/erlang/process
@target(erlang)
import gleam/json
@target(erlang)
import gleam/list
@target(erlang)
import gleam/option.{None, Some}
@target(erlang)
import gleam/string
@target(erlang)
import startest/expect

@target(erlang)
import watershed
@target(erlang)
import watershed/claims_kernel
@target(erlang)
import watershed/runtime
@target(erlang)
import watershed/schema
@target(erlang)
import watershed/sequence_kernel
@target(erlang)
import watershed/sluice

@target(erlang)
type SequenceFields

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
fn start(document: String) -> sluice.Sluice {
  let assert Ok(sluice) = sluice.start(tenant: "default", document: document)
  sluice
}

@target(erlang)
fn connect(sluice: sluice.Sluice, user: String) -> watershed.Document {
  let assert Ok(document) = sluice.connect(sluice, user)
  document
}

@target(erlang)
fn same_entries(
  a: List(#(String, json.Json)),
  b: List(#(String, json.Json)),
) -> Bool {
  normalize(a) == normalize(b)
}

@target(erlang)
fn normalize(entries: List(#(String, json.Json))) -> List(#(String, String)) {
  entries
  |> list.map(fn(entry) { #(entry.0, json.to_string(entry.1)) })
  |> list.sort(fn(x, y) { string.compare(x.0, y.0) })
}

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
pub fn map_lww_converges_test() {
  let sluice = start("map-lww")
  let doc_a = connect(sluice, "user-a")
  let doc_b = connect(sluice, "user-b")
  // Complete both handshakes before editing.
  sluice.settle(sluice)

  let map_a = watershed.root(doc_a)
  let map_b = watershed.root(doc_b)

  // Concurrent edits, including a same-key race the sequencer resolves.
  watershed.set(map_a, "die", json.int(4))
  watershed.set(map_b, "color", json.string("blue"))
  watershed.set(map_a, "shared", json.string("from-a"))
  watershed.set(map_b, "shared", json.string("from-b"))
  watershed.delete(map_a, "die")
  watershed.set(map_a, "die", json.int(6))
  sluice.settle(sluice)

  // Deterministic once settled — no polling.
  watershed.get(map_a, "die") |> expect.to_equal(Some(json.int(6)))
  watershed.get(map_b, "die") |> expect.to_equal(Some(json.int(6)))
  watershed.get(map_b, "color") |> expect.to_equal(Some(json.string("blue")))
  // Both sides pick the same LWW winner for the raced key.
  watershed.get(map_a, "shared")
  |> expect.to_equal(watershed.get(map_b, "shared"))
  same_entries(watershed.entries(map_a), watershed.entries(map_b))
  |> expect.to_be_true()

  // A late joiner replays history and lands on the same map.
  let doc_c = connect(sluice, "user-c")
  sluice.settle(sluice)
  let map_c = watershed.root(doc_c)
  same_entries(watershed.entries(map_c), watershed.entries(map_a))
  |> expect.to_be_true()
}

@target(erlang)
pub fn counter_sum_converges_test() {
  let sluice = start("counter-sum")
  let doc_a = connect(sluice, "user-a")
  let doc_b = connect(sluice, "user-b")
  sluice.settle(sluice)

  let map_a = watershed.root(doc_a)
  let map_b = watershed.root(doc_b)

  // Attach a shared counter via the root map.
  let assert Ok(counter_a) = watershed.create_counter(doc_a)
  watershed.increment(counter_a, 2)
  watershed.set(map_a, "tally", watershed.counter_handle_of(counter_a))
  sluice.settle(sluice)

  let counter_b = resolve_counter(doc_b, map_b, "tally")
  watershed.counter_value(counter_b) |> expect.to_equal(Some(2))

  // Concurrent increments commute to the same sum on both sides.
  watershed.increment(counter_a, 5)
  watershed.increment(counter_b, -1)
  sluice.settle(sluice)
  watershed.counter_value(counter_a) |> expect.to_equal(Some(6))
  watershed.counter_value(counter_b) |> expect.to_equal(Some(6))
}

@target(erlang)
fn resolve_counter(
  doc: watershed.Document,
  map: watershed.SharedMap,
  key: String,
) -> watershed.SharedCounter {
  let assert Some(value) = watershed.get(map, key)
  let assert Ok(counter) = watershed.resolve_counter(doc, value)
  counter
}

@target(erlang)
pub fn pause_holds_delivery_until_resume_test() {
  // Explicit delivery makes "who has seen what, when" scriptable. Here a peer
  // is held while another edits, then released — deterministically.
  let sluice = start("pause-delivery")
  let doc_a = connect(sluice, "user-a")
  let doc_b = connect(sluice, "user-b")
  sluice.settle(sluice)

  let map_a = watershed.root(doc_a)
  let map_b = watershed.root(doc_b)

  // Hold B, then let A author an edit.
  sluice.pause(sluice, doc_b)
  watershed.set(map_a, "k", json.string("v"))
  sluice.settle(sluice)

  // A sees its own edit (optimistic + echo); B is held and sees nothing.
  watershed.get(map_a, "k") |> expect.to_equal(Some(json.string("v")))
  watershed.get(map_b, "k") |> expect.to_equal(None)

  // Releasing B delivers the held op.
  sluice.resume(sluice, doc_b)
  sluice.settle(sluice)
  watershed.get(map_b, "k") |> expect.to_equal(Some(json.string("v")))
}

@target(erlang)
pub fn claims_first_writer_wins_test() {
  let sluice = start("claims-race")
  let doc_a = connect(sluice, "user-a")
  let doc_b = connect(sluice, "user-b")
  sluice.settle(sluice)

  let map_a = watershed.root(doc_a)
  let map_b = watershed.root(doc_b)

  // Attach a claims register and let B resolve its handle.
  let assert Ok(claims_a) = watershed.create_claims(doc_a)
  watershed.set(map_a, "locks", watershed.claims_handle_of(claims_a))
  sluice.settle(sluice)
  let assert Some(handle) = watershed.get(map_b, "locks")
  let assert Ok(claims_b) = watershed.resolve_claims(doc_b, handle)
  sluice.settle(sluice)

  // Both submit the same key before any delivery. Each `try_set_claim`
  // synchronously pushes its op into the core, so A's reaches the sequencer
  // first (it is called first) and wins — deterministically, no timing.
  let reply_a = watershed.try_set_claim(claims_a, "owner", json.string("A"))
  let reply_b = watershed.try_set_claim(claims_b, "owner", json.string("B"))
  sluice.settle(sluice)

  let outcome_a = await_claim(reply_a)
  let outcome_b = await_claim(reply_b)
  outcome_a |> expect.to_equal(claims_kernel.Accepted(json.string("A")))
  outcome_b |> expect.to_equal(claims_kernel.Lost(Some(json.string("A"))))

  // Both sides converge on the winner.
  watershed.get_claim(claims_a, "owner")
  |> expect.to_equal(Some(json.string("A")))
  watershed.get_claim(claims_b, "owner")
  |> expect.to_equal(Some(json.string("A")))
}

@target(erlang)
fn await_claim(reply: runtime.ClaimSubmitReply) -> claims_kernel.ClaimOutcome {
  let assert runtime.Pending(outcome) = reply
  let assert Ok(resolved) = process.receive(from: outcome, within: 5000)
  resolved
}

@target(erlang)
pub fn ripple_broadcasts_to_peers_test() {
  let sluice = start("ripple-presence")
  let doc_a = connect(sluice, "user-a")
  let doc_b = connect(sluice, "user-b")
  sluice.settle(sluice)

  // Both listen for ripples; A broadcasts one ephemeral signal.
  let ripples_a = watershed.subscribe_ripples(doc_a)
  let ripples_b = watershed.subscribe_ripples(doc_b)
  watershed.submit_ripple(
    doc_a,
    ripple_type: "cursor",
    content: json.object([#("x", json.int(7))]),
  )
  sluice.settle(sluice)

  // B hears A's ripple: the sender is stamped and the content carried through.
  // levee strips the `type` tag on broadcast, so it arrives as `None`.
  let assert Ok(ripple) = process.receive(from: ripples_b, within: 100)
  let assert Some(_) = watershed.ripple_client_id(ripple)
  watershed.ripple_type(ripple) |> expect.to_equal(None)
  decode.run(watershed.ripple_content(ripple), decode.at(["x"], decode.int))
  |> expect.to_equal(Ok(7))

  // A never hears its own ripple, and ripples are not persisted — a late
  // joiner replays no history for them.
  process.receive(from: ripples_a, within: 10) |> expect.to_equal(Error(Nil))
  let doc_c = connect(sluice, "user-c")
  let ripples_c = watershed.subscribe_ripples(doc_c)
  sluice.settle(sluice)
  process.receive(from: ripples_c, within: 10) |> expect.to_equal(Error(Nil))
}

@target(erlang)
pub fn sequence_subscription_narrows_local_events_test() {
  let sluice = start("sequence-subscription")
  let document = connect(sluice, "user-a")
  sluice.settle(sluice)

  let assert Ok(sequence) = watershed.create_sequence(document)
  let events = watershed.subscribe_sequence(sequence)
  let assert Ok(Nil) =
    watershed.sequence_insert(sequence, 0, json.string("first"))

  let assert Ok(event) = process.receive(from: events, within: 100)
  event
  |> expect.to_equal(sequence_kernel.SequenceChanged([json.string("first")]))
}

@target(erlang)
pub fn ensure_sequence_adopts_stored_field_test() {
  let sluice = start("ensure-sequence")
  let doc_a = connect(sluice, "user-a")
  let doc_b = connect(sluice, "user-b")
  let field: schema.ChannelField(SequenceFields, schema.SequenceChannel) =
    schema.channel_field("items")
  let root_a: watershed.TypedMap(SequenceFields) = watershed.root_typed(doc_a)
  let root_b: watershed.TypedMap(SequenceFields) = watershed.root_typed(doc_b)
  sluice.settle(sluice)

  let assert Ok(sequence_a) = watershed.create_sequence(doc_a)
  watershed.set_sequence_field(root_a, field, sequence_a)
  sluice.settle(sluice)

  let assert Ok(sequence_b) = watershed.ensure_sequence(doc_b, root_b, field)
  let assert Ok(Some(resolved)) =
    watershed.resolve_sequence_field(doc_b, root_b, field)
  let assert Ok(Nil) =
    watershed.sequence_insert(sequence_a, 0, json.string("ensured"))
  sluice.settle(sluice)
  watershed.sequence_values(sequence_b)
  |> expect.to_equal(watershed.sequence_values(resolved))
}

@target(erlang)
pub fn shared_sequence_converges_test() {
  let sluice = start("shared-sequence")
  let doc_a = connect(sluice, "user-a")
  let doc_b = connect(sluice, "user-b")
  sluice.settle(sluice)

  let assert Ok(sequence_a) = watershed.create_sequence(doc_a)
  let assert Ok(Nil) =
    watershed.sequence_insert(sequence_a, 0, json.string("base"))
  watershed.set(
    watershed.root(doc_a),
    "items",
    watershed.sequence_handle_of(sequence_a),
  )
  sluice.settle(sluice)

  let assert Some(sequence_handle) =
    watershed.get(watershed.root(doc_b), "items")
  let assert Ok(sequence_b) = watershed.resolve_sequence(doc_b, sequence_handle)
  case
    watershed.resolve_sequence(
      doc_b,
      watershed.handle_of(watershed.root(doc_b)),
    )
  {
    Error(_) -> Nil
    Ok(_) ->
      panic as "expected map handle resolution to fail for SharedSequence"
  }

  let assert Ok(Nil) =
    watershed.sequence_insert(sequence_a, 1, json.string("a"))
  let assert Ok(Nil) =
    watershed.sequence_insert(sequence_b, 1, json.string("b"))
  sluice.settle(sluice)

  watershed.sequence_values(sequence_a)
  |> expect.to_equal(watershed.sequence_values(sequence_b))

  let assert Ok(Nil) = watershed.sequence_move(sequence_a, 0, 2)
  let assert Ok(Nil) =
    watershed.sequence_replace(sequence_b, 0, json.string("B"))
  sluice.settle(sluice)
  watershed.sequence_values(sequence_a)
  |> expect.to_equal(watershed.sequence_values(sequence_b))

  watershed.sequence_delete(sequence_a, 99)
  |> expect.to_equal(Error("delete index 99 invalid for length 3"))
}
