//// Ungated convergence tests driving real `watershed` documents against the
//// in-memory `sluice` (plan HM3). These mirror the core subset of
//// `integration_test.gleam` — but run with no floodgate server and no env gate,
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
import watershed/claims_kernel
@target(erlang)
import watershed/client_id
@target(erlang)
import watershed/json_ot
@target(erlang)
import watershed/ordered_collection_kernel
@target(erlang)
import watershed/presence
@target(erlang)
import watershed/rich_text
@target(erlang)
import watershed/rich_text_kernel
@target(erlang)
import watershed/runtime_beam
@target(erlang)
import watershed/schema
@target(erlang)
import watershed/sequence_kernel
@target(erlang)
import watershed/sluice
@target(erlang)
import watershed/summary_policy
@target(erlang)
import watershed/text_kernel
@target(erlang)
import watershed_beam

@target(erlang)
type SequenceFields

@target(erlang)
type RichTextFields

@target(erlang)
type TextFields

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
fn start(document: String) -> sluice.Sluice {
  let assert Ok(sluice) = sluice.start(tenant: "default", document: document)
  sluice
}

@target(erlang)
fn connect(
  sluice: sluice.Sluice,
  user: String,
) -> watershed_beam.Document(root) {
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

@target(erlang)
fn rich_text_document(raw: String) -> rich_text.Document {
  let assert Ok(document) = rich_text.parse_document(raw)
  document
}

@target(erlang)
fn rich_text_delta(raw: String) -> rich_text.Delta {
  let assert Ok(delta) = rich_text.parse_delta(raw)
  delta
}

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
pub fn map_lww_converges_test() -> Nil {
  let sluice = start("map-lww")
  let doc_a = connect(sluice, "user-a")
  let doc_b = connect(sluice, "user-b")
  // Complete both handshakes before editing.
  sluice.settle(sluice)

  let map_a = watershed_beam.root(doc_a)
  let map_b = watershed_beam.root(doc_b)

  // Concurrent edits, including a same-key race the sequencer resolves.
  watershed_beam.set(map_a, "die", json.int(4))
  watershed_beam.set(map_b, "color", json.string("blue"))
  watershed_beam.set(map_a, "shared", json.string("from-a"))
  watershed_beam.set(map_b, "shared", json.string("from-b"))
  watershed_beam.delete(map_a, "die")
  watershed_beam.set(map_a, "die", json.int(6))
  sluice.settle(sluice)

  // Deterministic once settled — no polling.
  watershed_beam.get(map_a, "die") |> expect.to_equal(Ok(json.int(6)))
  watershed_beam.get(map_b, "die") |> expect.to_equal(Ok(json.int(6)))
  watershed_beam.get(map_b, "color")
  |> expect.to_equal(Ok(json.string("blue")))
  // Both sides pick the same LWW winner for the raced key.
  watershed_beam.get(map_a, "shared")
  |> expect.to_equal(watershed_beam.get(map_b, "shared"))
  same_entries(watershed_beam.entries(map_a), watershed_beam.entries(map_b))
  |> expect.to_be_true()

  // A late joiner replays history and lands on the same map.
  let doc_c = connect(sluice, "user-c")
  sluice.settle(sluice)
  let map_c = watershed_beam.root(doc_c)
  same_entries(watershed_beam.entries(map_c), watershed_beam.entries(map_a))
  |> expect.to_be_true()
}

@target(erlang)
pub fn counter_sum_converges_test() -> Nil {
  let sluice = start("counter-sum")
  let doc_a = connect(sluice, "user-a")
  let doc_b = connect(sluice, "user-b")
  sluice.settle(sluice)

  let map_a = watershed_beam.root(doc_a)
  let map_b = watershed_beam.root(doc_b)

  // Attach a shared counter via the root map.
  let assert Ok(counter_a) = watershed_beam.create_counter(doc_a)
  watershed_beam.increment(counter_a, 2)
  watershed_beam.set(
    map_a,
    "tally",
    watershed_beam.counter_handle_of(counter_a),
  )
  sluice.settle(sluice)

  let counter_b = resolve_counter(doc_b, map_b, "tally")
  watershed_beam.counter_value(counter_b) |> expect.to_equal(Ok(2))

  // Concurrent increments commute to the same sum on both sides.
  watershed_beam.increment(counter_a, 5)
  watershed_beam.increment(counter_b, -1)
  sluice.settle(sluice)
  watershed_beam.counter_value(counter_a) |> expect.to_equal(Ok(6))
  watershed_beam.counter_value(counter_b) |> expect.to_equal(Ok(6))
}

@target(erlang)
fn resolve_counter(
  doc: watershed_beam.Document(root),
  map: watershed_beam.SharedMap,
  key: String,
) -> watershed_beam.SharedCounter {
  let assert Ok(value) = watershed_beam.get(map, key)
  let assert Ok(counter) = watershed_beam.resolve_counter(doc, value)
  counter
}

@target(erlang)
pub fn pause_holds_delivery_until_resume_test() -> Nil {
  // Explicit delivery makes "who has seen what, when" scriptable. Here a peer
  // is held while another edits, then released — deterministically.
  let sluice = start("pause-delivery")
  let doc_a = connect(sluice, "user-a")
  let doc_b = connect(sluice, "user-b")
  sluice.settle(sluice)

  let map_a = watershed_beam.root(doc_a)
  let map_b = watershed_beam.root(doc_b)

  // Hold B, then let A author an edit.
  sluice.pause(sluice, doc_b)
  watershed_beam.set(map_a, "k", json.string("v"))
  sluice.settle(sluice)

  // A sees its own edit (optimistic + echo); B is held and sees nothing.
  watershed_beam.get(map_a, "k") |> expect.to_equal(Ok(json.string("v")))
  watershed_beam.get(map_b, "k") |> expect.to_equal(Error(Nil))

  // Releasing B delivers the held op.
  sluice.resume(sluice, doc_b)
  sluice.settle(sluice)
  watershed_beam.get(map_b, "k") |> expect.to_equal(Ok(json.string("v")))
}

@target(erlang)
pub fn claims_first_writer_wins_test() -> Nil {
  let sluice = start("claims-race")
  let doc_a = connect(sluice, "user-a")
  let doc_b = connect(sluice, "user-b")
  sluice.settle(sluice)

  let map_a = watershed_beam.root(doc_a)
  let map_b = watershed_beam.root(doc_b)

  // Attach a claims register and let B resolve its handle.
  let assert Ok(claims_a) = watershed_beam.create_claims(doc_a)
  watershed_beam.set(map_a, "locks", watershed_beam.claims_handle_of(claims_a))
  sluice.settle(sluice)
  let assert Ok(handle) = watershed_beam.get(map_b, "locks")
  let assert Ok(claims_b) = watershed_beam.resolve_claims(doc_b, handle)
  sluice.settle(sluice)

  // Both submit the same key before any delivery. Each `claim_once`
  // synchronously pushes its op into the core, so A's reaches the sequencer
  // first (it is called first) and wins — deterministically, no timing.
  let reply_a = watershed_beam.claim_once(claims_a, "owner", json.string("A"))
  let reply_b = watershed_beam.claim_once(claims_b, "owner", json.string("B"))
  sluice.settle(sluice)

  let outcome_a = await_claim(reply_a)
  let outcome_b = await_claim(reply_b)
  outcome_a |> expect.to_equal(claims_kernel.Accepted(json.string("A")))
  outcome_b |> expect.to_equal(claims_kernel.Lost(Some(json.string("A"))))

  // Both sides converge on the winner.
  watershed_beam.get_claim(claims_a, "owner")
  |> expect.to_equal(Ok(json.string("A")))
  watershed_beam.get_claim(claims_b, "owner")
  |> expect.to_equal(Ok(json.string("A")))
}

@target(erlang)
fn await_claim(
  reply: runtime_beam.ClaimSubmitReply,
) -> claims_kernel.ClaimOutcome {
  let assert runtime_beam.Pending(outcome) = reply
  let assert Ok(resolved) = process.receive(from: outcome, within: 5000)
  resolved
}

@target(erlang)
pub fn ripple_broadcasts_to_peers_test() -> Nil {
  let sluice = start("ripple-presence")
  let doc_a = connect(sluice, "user-a")
  let doc_b = connect(sluice, "user-b")
  sluice.settle(sluice)

  // Both listen for ripples; A broadcasts one ephemeral signal.
  let ripples_a = watershed_beam.subscribe_ripples(doc_a)
  let ripples_b = watershed_beam.subscribe_ripples(doc_b)
  watershed_beam.submit_ripple(
    doc_a,
    ripple_type: "cursor",
    content: json.object([#("x", json.int(7))]),
  )
  sluice.settle(sluice)

  // B hears A's ripple: the sender is stamped and the content carried through.
  // floodgate strips the `type` tag on broadcast, so it arrives as `None`.
  let assert Ok(ripple) = process.receive(from: ripples_b, within: 100)
  let assert Some(_) = watershed_beam.ripple_client_id(ripple)
  watershed_beam.ripple_type(ripple) |> expect.to_equal(None)
  json.parse(
    json.to_string(watershed_beam.ripple_content(ripple)),
    decode.at(["x"], decode.int),
  )
  |> expect.to_equal(Ok(7))

  // A never hears its own ripple, and ripples are not persisted — a late
  // joiner replays no history for them.
  process.receive(from: ripples_a, within: 10) |> expect.to_equal(Error(Nil))
  let doc_c = connect(sluice, "user-c")
  let ripples_c = watershed_beam.subscribe_ripples(doc_c)
  sluice.settle(sluice)
  process.receive(from: ripples_c, within: 10) |> expect.to_equal(Error(Nil))
}

@target(erlang)
pub fn sequence_subscription_narrows_local_events_test() -> Nil {
  let sluice = start("sequence-subscription")
  let document = connect(sluice, "user-a")
  sluice.settle(sluice)

  let assert Ok(sequence) = watershed_beam.create_sequence(document)
  let events = watershed_beam.subscribe_sequence(sequence)
  let assert Ok(Nil) =
    watershed_beam.sequence_insert(sequence, 0, json.string("first"))

  let assert Ok(event) = process.receive(from: events, within: 100)
  event
  |> expect.to_equal(sequence_kernel.SequenceChanged([json.string("first")]))
}

@target(erlang)
pub fn ensure_sequence_adopts_stored_field_test() -> Nil {
  let sluice = start("ensure-sequence")
  let doc_a = connect(sluice, "user-a")
  let doc_b = connect(sluice, "user-b")
  let field: schema.ChannelField(SequenceFields, schema.SequenceChannel) =
    schema.channel_field("items")
  let root_a: watershed_beam.TypedMap(SequenceFields) =
    watershed_beam.root_typed(doc_a)
  let root_b: watershed_beam.TypedMap(SequenceFields) =
    watershed_beam.root_typed(doc_b)
  sluice.settle(sluice)

  let assert Ok(sequence_a) = watershed_beam.create_sequence(doc_a)
  watershed_beam.set_sequence_field(root_a, field, sequence_a)
  sluice.settle(sluice)

  let assert Ok(sequence_b) =
    watershed_beam.ensure_sequence(doc_b, root_b, field)
  let assert Ok(Some(resolved)) =
    watershed_beam.resolve_sequence_field(doc_b, root_b, field)
  let assert Ok(Nil) =
    watershed_beam.sequence_insert(sequence_a, 0, json.string("ensured"))
  sluice.settle(sluice)
  watershed_beam.sequence_values(sequence_b)
  |> expect.to_equal(watershed_beam.sequence_values(resolved))
}

@target(erlang)
pub fn shared_sequence_converges_test() -> Nil {
  let sluice = start("shared-sequence")
  let doc_a = connect(sluice, "user-a")
  let doc_b = connect(sluice, "user-b")
  sluice.settle(sluice)

  let assert Ok(sequence_a) = watershed_beam.create_sequence(doc_a)
  let assert Ok(Nil) =
    watershed_beam.sequence_insert(sequence_a, 0, json.string("base"))
  watershed_beam.set(
    watershed_beam.root(doc_a),
    "items",
    watershed_beam.sequence_handle_of(sequence_a),
  )
  sluice.settle(sluice)

  let assert Ok(sequence_handle) =
    watershed_beam.get(watershed_beam.root(doc_b), "items")
  let assert Ok(sequence_b) =
    watershed_beam.resolve_sequence(doc_b, sequence_handle)
  case
    watershed_beam.resolve_sequence(
      doc_b,
      watershed_beam.handle_of(watershed_beam.root(doc_b)),
    )
  {
    Error(_) -> Nil
    Ok(_) -> panic as "expected map handle resolution to fail for SharedSequence"
  }

  let assert Ok(Nil) =
    watershed_beam.sequence_insert(sequence_a, 1, json.string("a"))
  let assert Ok(Nil) =
    watershed_beam.sequence_insert(sequence_b, 1, json.string("b"))
  sluice.settle(sluice)

  watershed_beam.sequence_values(sequence_a)
  |> expect.to_equal(watershed_beam.sequence_values(sequence_b))

  let assert Ok(Nil) = watershed_beam.sequence_move(sequence_a, 0, 2)
  let assert Ok(Nil) =
    watershed_beam.sequence_replace(sequence_b, 0, json.string("B"))
  sluice.settle(sluice)
  watershed_beam.sequence_values(sequence_a)
  |> expect.to_equal(watershed_beam.sequence_values(sequence_b))

  watershed_beam.sequence_delete(sequence_a, 99)
  |> expect.to_equal(Error("delete index 99 invalid for length 3"))
}

@target(erlang)
pub fn shared_rich_text_create_resolve_submit_view_subscribe_test() -> Nil {
  let sluice = start("shared-rich-text")
  let doc_a = connect(sluice, "user-a")
  let doc_b = connect(sluice, "user-b")
  sluice.settle(sluice)

  let assert Ok(rich_text_a) = watershed_beam.create_rich_text(doc_a)
  let events = watershed_beam.subscribe_rich_text(rich_text_a)
  let first = rich_text_delta("[{\"insert\":\"A\"}]")
  watershed_beam.submit_rich_text(rich_text_a, first)
  let assert Ok(local_event) = process.receive(from: events, within: 100)
  local_event
  |> expect.to_equal(rich_text_kernel.RichTextChanged(first, True))
  watershed_beam.rich_text_view(rich_text_a)
  |> expect.to_equal(Ok(rich_text_document("[{\"insert\":\"A\"}]")))

  let handle = watershed_beam.rich_text_handle_of(rich_text_a)
  watershed_beam.set(watershed_beam.root(doc_a), "rich", handle)
  sluice.settle(sluice)
  watershed_beam.get(watershed_beam.root(doc_b), "rich")
  |> expect.to_equal(Ok(handle))
  let assert Ok(rich_text_b) = watershed_beam.resolve_rich_text(doc_b, handle)
  watershed_beam.rich_text_view(rich_text_b)
  |> expect.to_equal(Ok(rich_text_document("[{\"insert\":\"A\"}]")))

  watershed_beam.submit_rich_text(
    rich_text_b,
    rich_text_delta("[{\"retain\":1},{\"insert\":\"B\"}]"),
  )
  sluice.settle(sluice)
  watershed_beam.rich_text_view(rich_text_a)
  |> expect.to_equal(Ok(rich_text_document("[{\"insert\":\"AB\"}]")))
  watershed_beam.rich_text_view(rich_text_b)
  |> expect.to_equal(Ok(rich_text_document("[{\"insert\":\"AB\"}]")))
}

@target(erlang)
pub fn typed_rich_text_field_set_resolve_and_ensure_test() -> Nil {
  let sluice = start("typed-rich-text")
  let doc_a = connect(sluice, "user-a")
  let doc_b = connect(sluice, "user-b")
  let field: schema.ChannelField(RichTextFields, schema.RichTextChannel) =
    schema.channel_field("rich")
  let root_a: watershed_beam.TypedMap(RichTextFields) =
    watershed_beam.root_typed(doc_a)
  let root_b: watershed_beam.TypedMap(RichTextFields) =
    watershed_beam.root_typed(doc_b)
  sluice.settle(sluice)

  let assert Ok(rich_text_a) = watershed_beam.create_rich_text(doc_a)
  watershed_beam.set_rich_text_field(root_a, field, rich_text_a)
  sluice.settle(sluice)
  let assert Ok(Some(rich_text_b)) =
    watershed_beam.resolve_rich_text_field(doc_b, root_b, field)

  watershed_beam.submit_rich_text(
    rich_text_a,
    rich_text_delta("[{\"insert\":\"typed\"}]"),
  )
  sluice.settle(sluice)
  watershed_beam.rich_text_view(rich_text_b)
  |> expect.to_equal(Ok(rich_text_document("[{\"insert\":\"typed\"}]")))

  let empty_field: schema.ChannelField(RichTextFields, schema.RichTextChannel) =
    schema.channel_field("ensured")
  let assert Ok(ensured) =
    watershed_beam.ensure_rich_text(doc_b, root_b, empty_field)
  let assert Ok(Some(resolved)) =
    watershed_beam.resolve_rich_text_field(doc_b, root_b, empty_field)
  watershed_beam.rich_text_view(ensured)
  |> expect.to_equal(watershed_beam.rich_text_view(resolved))
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared text
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
pub fn shared_text_converges_test() -> Nil {
  let sluice = start("shared-text")
  let doc_a = connect(sluice, "user-a")
  let doc_b = connect(sluice, "user-b")
  sluice.settle(sluice)

  let assert Ok(text_a) = watershed_beam.create_text(doc_a)
  let assert Ok(Nil) = watershed_beam.text_insert(text_a, 0, "base")
  watershed_beam.set(
    watershed_beam.root(doc_a),
    "doc",
    watershed_beam.text_handle_of(text_a),
  )
  sluice.settle(sluice)

  let assert Ok(text_handle) =
    watershed_beam.get(watershed_beam.root(doc_b), "doc")
  let assert Ok(text_b) = watershed_beam.resolve_text(doc_b, text_handle)
  // A map handle does not resolve as text.
  case
    watershed_beam.resolve_text(
      doc_b,
      watershed_beam.handle_of(watershed_beam.root(doc_b)),
    )
  {
    Error(_) -> Nil
    Ok(_) -> panic as "expected map handle resolution to fail for SharedText"
  }
  watershed_beam.text_value(text_b) |> expect.to_equal("base")

  // Concurrent inserts at the same index (both authors type at the gap
  // before "base" before either has seen the other's edit) still converge:
  // both replicas end up with the same string, containing both insertions.
  let assert Ok(Nil) = watershed_beam.text_insert(text_a, 0, "A-")
  let assert Ok(Nil) = watershed_beam.text_insert(text_b, 0, "B-")
  sluice.settle(sluice)

  watershed_beam.text_value(text_a)
  |> expect.to_equal(watershed_beam.text_value(text_b))
  let converged = watershed_beam.text_value(text_a)
  string.contains(converged, "A-") |> expect.to_be_true()
  string.contains(converged, "B-") |> expect.to_be_true()
  string.contains(converged, "base") |> expect.to_be_true()

  // Overlapping delete-range (A) racing a replace-range (B) over intersecting
  // spans still converges deterministically once both sides have merged.
  let assert Ok(Nil) =
    watershed_beam.text_replace_range(
      text_a,
      0,
      watershed_beam.text_length(text_a),
      "abcdef",
    )
  sluice.settle(sluice)
  let assert Ok(Nil) = watershed_beam.text_delete_range(text_a, 1, 4)
  let assert Ok(Nil) = watershed_beam.text_replace_range(text_b, 2, 5, "XY")
  sluice.settle(sluice)
  watershed_beam.text_value(text_a)
  |> expect.to_equal(watershed_beam.text_value(text_b))

  // An append racing a concurrent insert also converges.
  let assert Ok(Nil) = watershed_beam.text_append(text_a, "!!!")
  let assert Ok(Nil) = watershed_beam.text_insert(text_b, 0, ">>")
  sluice.settle(sluice)
  watershed_beam.text_value(text_a)
  |> expect.to_equal(watershed_beam.text_value(text_b))

  // A late joiner replays history and lands on the same text.
  let doc_c = connect(sluice, "user-c")
  sluice.settle(sluice)
  let assert Ok(handle_for_c) =
    watershed_beam.get(watershed_beam.root(doc_c), "doc")
  let assert Ok(text_c) = watershed_beam.resolve_text(doc_c, handle_for_c)
  watershed_beam.text_value(text_c)
  |> expect.to_equal(watershed_beam.text_value(text_a))
}

@target(erlang)
pub fn shared_text_emoji_and_combining_graphemes_converge_test() -> Nil {
  // "e" + combining acute (U+0301) is one grapheme cluster, and a
  // ZWJ-joined family emoji is a single grapheme despite many codepoints —
  // both must survive concurrent edits and index math intact.
  let sluice = start("shared-text-emoji")
  let doc_a = connect(sluice, "user-a")
  let doc_b = connect(sluice, "user-b")
  sluice.settle(sluice)

  let assert Ok(text_a) = watershed_beam.create_text(doc_a)
  let combining_e = "e\u{0301}"
  let family =
    "👩" <> "\u{200D}" <> "👩" <> "\u{200D}" <> "👧" <> "\u{200D}" <> "👦"
  let assert Ok(Nil) =
    watershed_beam.text_insert(text_a, 0, combining_e <> family)
  watershed_beam.set(
    watershed_beam.root(doc_a),
    "doc",
    watershed_beam.text_handle_of(text_a),
  )
  sluice.settle(sluice)

  let assert Ok(handle) = watershed_beam.get(watershed_beam.root(doc_b), "doc")
  let assert Ok(text_b) = watershed_beam.resolve_text(doc_b, handle)
  watershed_beam.text_length(text_b) |> expect.to_equal(2)
  watershed_beam.text_value(text_b) |> expect.to_equal(combining_e <> family)
  watershed_beam.text_substring(text_b, 0, 1)
  |> expect.to_equal(Ok(combining_e))
  watershed_beam.text_substring(text_b, 1, 2) |> expect.to_equal(Ok(family))

  // Concurrent grapheme-cluster inserts between the two clusters, plus a
  // mixed-script append, converge to the same visible string on both sides.
  let assert Ok(Nil) = watershed_beam.text_insert(text_a, 1, "🎉")
  let assert Ok(Nil) = watershed_beam.text_append(text_b, "日д")
  sluice.settle(sluice)

  watershed_beam.text_value(text_a)
  |> expect.to_equal(watershed_beam.text_value(text_b))
  watershed_beam.text_length(text_a) |> expect.to_equal(5)
  watershed_beam.text_value(text_a)
  |> expect.to_equal(combining_e <> "🎉" <> family <> "日д")
}

@target(erlang)
pub fn shared_text_invalid_bounds_return_errors_test() -> Nil {
  let sluice = start("shared-text-invalid-bounds")
  let document = connect(sluice, "user-a")
  sluice.settle(sluice)

  let assert Ok(text) = watershed_beam.create_text(document)
  let assert Ok(Nil) = watershed_beam.text_insert(text, 0, "hello")

  watershed_beam.text_insert(text, 99, "x")
  |> expect.to_equal(Error("insert index 99 outside 0..5"))
  watershed_beam.text_insert(text, -1, "x")
  |> expect.to_equal(Error("insert index -1 outside 0..5"))
  watershed_beam.text_delete_range(text, 3, 1)
  |> expect.to_equal(Error("delete range 3..1 invalid for length 5"))
  watershed_beam.text_delete_range(text, 0, 99)
  |> expect.to_equal(Error("delete range 0..99 invalid for length 5"))
  watershed_beam.text_replace_range(text, 0, 99, "x")
  |> expect.to_equal(Error("replace range 0..99 invalid for length 5"))
  watershed_beam.text_substring(text, 0, 99)
  |> expect.to_equal(Error("substring range 0..99 invalid for length 5"))

  // None of the rejected edits changed the text or left pending debris.
  watershed_beam.text_value(text) |> expect.to_equal("hello")
}

@target(erlang)
pub fn shared_text_no_op_edits_do_not_submit_test() -> Nil {
  // No-op edits (an empty insert/append, or a zero-length delete/replace)
  // must not submit a channel op: subscribers see no event, and a peer that
  // never delivers anything still converges since nothing was ever sent.
  let sluice = start("shared-text-no-op")
  let doc_a = connect(sluice, "user-a")
  let doc_b = connect(sluice, "user-b")
  sluice.settle(sluice)

  let assert Ok(text_a) = watershed_beam.create_text(doc_a)
  let assert Ok(Nil) = watershed_beam.text_insert(text_a, 0, "hello")
  watershed_beam.set(
    watershed_beam.root(doc_a),
    "doc",
    watershed_beam.text_handle_of(text_a),
  )
  sluice.settle(sluice)

  let assert Ok(handle) = watershed_beam.get(watershed_beam.root(doc_b), "doc")
  let assert Ok(text_b) = watershed_beam.resolve_text(doc_b, handle)
  let events_a = watershed_beam.subscribe_text(text_a)

  // An empty insert at a valid index is a no-op: it returns Ok(Nil), fires
  // no event, and never reaches the wire.
  watershed_beam.text_insert(text_a, 2, "") |> expect.to_equal(Ok(Nil))
  // A zero-length delete-range/replace-range is likewise a no-op.
  watershed_beam.text_delete_range(text_a, 2, 2) |> expect.to_equal(Ok(Nil))
  watershed_beam.text_replace_range(text_a, 2, 2, "")
  |> expect.to_equal(Ok(Nil))
  // Appending "" is a no-op too.
  watershed_beam.text_append(text_a, "") |> expect.to_equal(Ok(Nil))

  process.receive(from: events_a, within: 10) |> expect.to_equal(Error(Nil))
  sluice.settle(sluice)

  // Nothing was ever submitted, so B never saw an update and both sides
  // remain exactly "hello".
  watershed_beam.text_value(text_a) |> expect.to_equal("hello")
  watershed_beam.text_value(text_b) |> expect.to_equal("hello")
}

@target(erlang)
pub fn shared_text_subscription_narrows_local_events_test() -> Nil {
  let sluice = start("shared-text-subscription")
  let document = connect(sluice, "user-a")
  sluice.settle(sluice)

  let assert Ok(text) = watershed_beam.create_text(document)
  let events = watershed_beam.subscribe_text(text)
  let assert Ok(Nil) = watershed_beam.text_insert(text, 0, "first")

  let assert Ok(event) = process.receive(from: events, within: 100)
  event |> expect.to_equal(text_kernel.TextChanged("first"))
}

@target(erlang)
pub fn ensure_text_adopts_stored_field_test() -> Nil {
  let sluice = start("ensure-text")
  let doc_a = connect(sluice, "user-a")
  let doc_b = connect(sluice, "user-b")
  let field: schema.ChannelField(TextFields, schema.TextChannel) =
    schema.channel_field("body")
  let root_a: watershed_beam.TypedMap(TextFields) =
    watershed_beam.root_typed(doc_a)
  let root_b: watershed_beam.TypedMap(TextFields) =
    watershed_beam.root_typed(doc_b)
  sluice.settle(sluice)

  let assert Ok(text_a) = watershed_beam.create_text(doc_a)
  watershed_beam.set_text_field(root_a, field, text_a)
  sluice.settle(sluice)

  let assert Ok(text_b) = watershed_beam.ensure_text(doc_b, root_b, field)
  let assert Ok(Some(resolved)) =
    watershed_beam.resolve_text_field(doc_b, root_b, field)
  let assert Ok(Nil) = watershed_beam.text_insert(text_a, 0, "ensured")
  sluice.settle(sluice)
  watershed_beam.text_value(text_b)
  |> expect.to_equal(watershed_beam.text_value(resolved))
}

@target(erlang)
/// `client_id` exists so a client can find *itself* in a list some kernel
/// reports about the room. That is the only claim worth testing, and it is a
/// claim about agreement between two independent derivations: the id the
/// facade hands out, and the integer a consensus kernel writes into a signoff
/// list. This asserts they name the same client.
///
/// The BEAM mirror of `driver_js_test.client_id_matches_the_id_kernels_report`
/// — the accessor is one of the few genuinely document-level functions on both
/// facades, and a divergence here would not be caught by the per-kind parity
/// test.
pub fn client_id_matches_the_id_kernels_report_test() -> Nil {
  let sluice = start("client-id-beam")
  let doc_a = connect(sluice, "user-a")
  let doc_b = connect(sluice, "user-b")
  let doc_c = connect(sluice, "user-c")

  // Before the handshake there is no server-assigned id to report, and the
  // honest answer is `None` rather than a placeholder that would quietly
  // match nothing.
  watershed_beam.client_id(doc_a) |> expect.to_equal(None)

  sluice.settle(sluice)
  let assert Some(id_a) = watershed_beam.client_id(doc_a)
  let assert Some(id_c) = watershed_beam.client_id(doc_c)
  { id_a != id_c } |> expect.to_be_true()

  let assert Ok(pact_a) = watershed_beam.create_pact_map(doc_a)
  watershed_beam.set(
    watershed_beam.root(doc_a),
    "tempo",
    watershed_beam.pact_map_handle_of(pact_a),
  )
  sluice.settle(sluice)
  let assert Ok(handle) =
    watershed_beam.get(watershed_beam.root(doc_b), "tempo")
  let assert Ok(_pact_c) = watershed_beam.resolve_pact_map(doc_c, handle)

  // Hold C, propose, and the outstanding signoff list names exactly C — which
  // C can now recognise as itself, going through the public derivation an app
  // would use.
  sluice.pause(sluice, doc_c)
  watershed_beam.pact_map_set(pact_a, "bpm", json.int(128))
  sluice.settle(sluice)

  watershed_beam.pact_map_pending_signoffs(pact_a, "bpm")
  |> expect.to_equal(Ok([client_id.to_int(id_c)]))
}

// ─────────────────────────────────────────────────────────────────────────────
// Reconnect
// ─────────────────────────────────────────────────────────────────────────────

@target(erlang)
/// The primitive itself: the socket goes, the client comes back under a new
/// identity, and the document it was editing is still there.
pub fn reconnect_rejoins_under_a_fresh_client_id_test() -> Nil {
  let sluice = start("reconnect-identity")
  let doc_a = connect(sluice, "user-a")
  let doc_b = connect(sluice, "user-b")
  sluice.settle(sluice)

  watershed_beam.set(watershed_beam.root(doc_a), "before", json.int(1))
  sluice.settle(sluice)
  let assert Some(was) = watershed_beam.client_id(doc_a)

  sluice.reconnect(sluice, doc_a)
  sluice.settle(sluice)

  let assert Some(now) = watershed_beam.client_id(doc_a)
  { now != was } |> expect.to_be_true()

  // The core survived the drop, and the link is live in both directions again.
  watershed_beam.get(watershed_beam.root(doc_a), "before")
  |> expect.to_equal(Ok(json.int(1)))
  watershed_beam.set(watershed_beam.root(doc_a), "after", json.int(2))
  sluice.settle(sluice)
  watershed_beam.get(watershed_beam.root(doc_b), "after")
  |> expect.to_equal(Ok(json.int(2)))
}

@target(erlang)
/// The reconnecting client replays the ops it missed rather than losing them,
/// which is what makes the gap a gap and not a reset.
pub fn reconnect_replays_the_ops_missed_while_away_test() -> Nil {
  let sluice = start("reconnect-gap")
  let doc_a = connect(sluice, "user-a")
  let doc_b = connect(sluice, "user-b")
  sluice.settle(sluice)

  sluice.reconnect(sluice, doc_a)
  // B edits while A is between connections. A must not see it yet.
  watershed_beam.set(watershed_beam.root(doc_b), "during", json.int(7))
  sluice.settle(sluice)

  watershed_beam.get(watershed_beam.root(doc_a), "during")
  |> expect.to_equal(Ok(json.int(7)))
}

@target(erlang)
/// A departing client's `leave` is sequenced, so the room the survivors see
/// never contains the identity that went away. Without it a `PactMap` would
/// wait forever on a client that cannot answer.
pub fn reconnect_sequences_a_leave_for_the_old_identity_test() -> Nil {
  let sluice = start("reconnect-roster")
  let doc_a = connect(sluice, "user-a")
  let doc_b = connect(sluice, "user-b")
  let doc_c = connect(sluice, "user-c")
  sluice.settle(sluice)

  let assert Ok(pact_a) = watershed_beam.create_pact_map(doc_a)
  watershed_beam.set(
    watershed_beam.root(doc_a),
    "tempo",
    watershed_beam.pact_map_handle_of(pact_a),
  )
  sluice.settle(sluice)
  let assert Ok(handle) =
    watershed_beam.get(watershed_beam.root(doc_b), "tempo")
  let assert Ok(pact_b) = watershed_beam.resolve_pact_map(doc_b, handle)
  let assert Ok(_) = watershed_beam.resolve_pact_map(doc_c, handle)

  let assert Some(gone) = watershed_beam.client_id(doc_c)
  sluice.reconnect(sluice, doc_c)
  sluice.settle(sluice)

  // A proposal now must not be waiting on the identity that dropped.
  watershed_beam.pact_map_set(pact_a, "bpm", json.int(128))
  sluice.settle(sluice)
  case watershed_beam.pact_map_pending_signoffs(pact_a, "bpm") {
    Error(Nil) -> Nil
    Ok(outstanding) ->
      list.contains(outstanding, client_id.to_int(gone))
      |> expect.to_be_false()
  }
  watershed_beam.pact_map_get(pact_b, "bpm")
  |> expect.to_equal(Ok(json.int(128)))
}

@target(erlang)
/// Regression: an `Accept` a kernel releases while a reconnect is still
/// settling must reach the wire exactly once.
///
/// The shape that matters is one frame doing two things. C comes back far
/// enough behind that its catch-up arrives as a single batch, and that batch
/// both carries the proposal it owes a signoff on *and* brings it level with
/// the handshake checkpoint. So the released `Accept` is sent, and then the
/// reconnect completes and restamps the whole in-flight queue — the same
/// `Accept` among it. Sending it in both places put two copies on the wire; the
/// server sequenced both, and the stale ack failed C's FIFO match with
/// `AckMismatch("expected ack for csn N, got csn M")`, killing its runtime_beam.
pub fn a_released_accept_is_not_sent_twice_across_a_reconnect_test() -> Nil {
  let sluice = start("reconnect-released-accept")
  let doc_a = connect(sluice, "user-a")
  let doc_b = connect(sluice, "user-b")
  let doc_c = connect(sluice, "user-c")
  sluice.settle(sluice)

  let assert Ok(pact_a) = watershed_beam.create_pact_map(doc_a)
  watershed_beam.set(
    watershed_beam.root(doc_a),
    "settings",
    watershed_beam.pact_map_handle_of(pact_a),
  )
  sluice.settle(sluice)
  let assert Ok(handle) =
    watershed_beam.get(watershed_beam.root(doc_b), "settings")
  let assert Ok(pact_b) = watershed_beam.resolve_pact_map(doc_b, handle)
  let assert Ok(pact_c) = watershed_beam.resolve_pact_map(doc_c, handle)

  // Put C far enough behind that its catch-up comes back as one batch.
  sluice.pause(sluice, doc_c)
  watershed_beam.set(watershed_beam.root(doc_a), "filler", json.int(1))
  watershed_beam.pact_map_set(pact_a, "bpm", json.int(128))
  watershed_beam.set(watershed_beam.root(doc_b), "more", json.int(2))
  sluice.settle(sluice)

  // C's held frames die with the socket; everything it missed arrives through
  // the post-reconnect catch-up instead.
  sluice.reconnect(sluice, doc_c)
  sluice.settle(sluice)

  // C survived, and the room agrees. Under the double-send C's runtime was
  // already dead by here.
  watershed_beam.get(watershed_beam.root(doc_c), "filler")
  |> expect.to_equal(Ok(json.int(1)))
  watershed_beam.get(watershed_beam.root(doc_c), "more")
  |> expect.to_equal(Ok(json.int(2)))

  watershed_beam.pact_map_get(pact_a, "bpm")
  |> expect.to_equal(Ok(json.int(128)))
  watershed_beam.pact_map_get(pact_b, "bpm")
  |> expect.to_equal(Ok(json.int(128)))
  watershed_beam.pact_map_get(pact_c, "bpm")
  |> expect.to_equal(Ok(json.int(128)))
  watershed_beam.pact_map_is_pending(pact_a, "bpm") |> expect.to_be_false()
}

@target(erlang)
/// A proposal sequenced while a client is away must not gain a signoff from
/// the identity that client comes back under.
///
/// C is out of the room from its `leave` until its rejoin, so the proposal in
/// between froze a signoff list naming only A and B. When C returns it replays
/// that proposal — and it is *not* in that list, under either identity: the one
/// it had is gone, and the one it has now did not exist yet. Deciding otherwise
/// makes C send an `Accept` for a pact that never expected it, which the room
/// rejects as `AckMismatch("client was not expected to sign off")`.
pub fn a_proposal_made_while_away_does_not_gain_the_returning_client_test() -> Nil {
  let sluice = start("reconnect-window-proposal")
  let doc_a = connect(sluice, "user-a")
  let doc_b = connect(sluice, "user-b")
  let doc_c = connect(sluice, "user-c")
  sluice.settle(sluice)

  let assert Ok(pact_a) = watershed_beam.create_pact_map(doc_a)
  watershed_beam.set(
    watershed_beam.root(doc_a),
    "settings",
    watershed_beam.pact_map_handle_of(pact_a),
  )
  sluice.settle(sluice)
  let assert Ok(handle) =
    watershed_beam.get(watershed_beam.root(doc_b), "settings")
  let assert Ok(pact_b) = watershed_beam.resolve_pact_map(doc_b, handle)
  let assert Ok(_) = watershed_beam.resolve_pact_map(doc_c, handle)

  // Hold B, so the proposal is still outstanding when C comes back. A settled
  // pact ignores a stray `Accept`; a pending one rejects it, and rejecting it
  // is fatal to the connection that sent it.
  sluice.pause(sluice, doc_b)

  // C's socket goes, and the proposal is sequenced in the window before it is
  // let back. A froze a signoff list of A and B — C had already left.
  sluice.drop(sluice, doc_c)
  watershed_beam.pact_map_set(pact_a, "bpm", json.int(128))
  sluice.settle(sluice)
  watershed_beam.pact_map_is_pending(pact_a, "bpm") |> expect.to_be_true()

  // C returns and replays it.
  sluice.rejoin(sluice, doc_c)
  sluice.settle(sluice)
  sluice.resume(sluice, doc_b)
  sluice.settle(sluice)

  let assert Ok(pact_c) = watershed_beam.resolve_pact_map(doc_c, handle)
  watershed_beam.pact_map_get(pact_c, "bpm")
  |> expect.to_equal(Ok(json.int(128)))
  watershed_beam.pact_map_is_pending(pact_c, "bpm") |> expect.to_be_false()

  // And the room is still usable afterwards.
  watershed_beam.pact_map_set(pact_b, "bpm", json.int(96))
  sluice.settle(sluice)
  watershed_beam.pact_map_get(pact_a, "bpm")
  |> expect.to_equal(Ok(json.int(96)))
  watershed_beam.pact_map_get(pact_c, "bpm")
  |> expect.to_equal(Ok(json.int(96)))
}

@target(erlang)
/// The erlang runtime's presence lane, end to end over a real document: the
/// handshake reports the negotiated capability, and a `joinPresence` pushed by
/// hand comes back as a snapshot and a diff.
///
/// There is no erlang presence *driver* yet (every consumer is a browser), so
/// this is what keeps the erlang half of the lane from rotting: the JS runtime
/// and this one are maintained as parallel implementations, and an untested
/// lane on one side drifts.
pub fn presence_lane_delivers_session_state_and_diffs_test() -> Nil {
  let sluice = start("presence-lane")
  let document = connect(sluice, "user-a")
  let runtime = watershed_beam.runtime_subject(document)

  // Collect frames into a mailbox rather than a mutable cell: the subscriber
  // runs on the runtime's process, not this one.
  let inbox = process.new_subject()
  process.send(
    runtime,
    runtime_beam.SubscribePresence(fn(frame) { process.send(inbox, frame) }),
  )
  sluice.settle(sluice)

  let assert Ok(runtime_beam.PresenceSession(client_id, presence_v1)) =
    process.receive(inbox, 1000)
  presence_v1 |> expect.to_be_true
  client_id |> expect.to_not_equal("")

  process.send(
    runtime,
    runtime_beam.SubmitPresence(
      "joinPresence",
      json.object([
        #("meta", json.object([#("panel", json.string("dice"))])),
      ]),
    ),
  )
  sluice.settle(sluice)

  let assert Ok(runtime_beam.PresenceState(state)) =
    process.receive(inbox, 1000)
  let assert Ok(snapshot) =
    json.parse(
      json.to_string(state),
      presence.presence_state_decoder(decode: panel_decoder()),
    )
  let #(tracker, _) = presence.apply_state(presence.tracker(), snapshot)
  // The snapshot precedes this client's own tracking, so it is empty and the
  // join arrives as the diff below.
  presence.tracker_entries(tracker) |> expect.to_equal([])

  let assert Ok(runtime_beam.PresenceDiff(payload)) =
    process.receive(inbox, 1000)
  let assert Ok(diff) =
    json.parse(
      json.to_string(payload),
      presence.presence_diff_decoder(decode: panel_decoder()),
    )
  presence.diff_joins(diff)
  |> expect.to_equal([
    presence.PresenceEntry(
      session_id: client_id,
      key: "user-a",
      meta: PresencePanel("dice"),
    ),
  ])
}

@target(erlang)
type PresencePanel {
  PresencePanel(name: String)
}

@target(erlang)
fn panel_decoder() -> decode.Decoder(PresencePanel) {
  use name <- decode.field("panel", decode.string)
  decode.success(PresencePanel(name))
}

@target(erlang)
/// The full job lifecycle — add, acquire, release, re-acquire, complete — is
/// observable end to end from both sides: the author's subscriber sees each op
/// land on ack with `local: True`, a peer's with `local: False`, and a release
/// surfaces as `Added(newly_added: False)` rather than a distinct event, which
/// is the shape the work-queue demo renders "job returned to queue" from.
pub fn subscribe_ordered_collection_observes_the_full_lifecycle_test() -> Nil {
  let sluice = start("ordered-lifecycle")
  let doc_a = connect(sluice, "user-a")
  let doc_b = connect(sluice, "user-b")
  sluice.settle(sluice)

  let assert Ok(queue_a) = watershed_beam.create_ordered_collection(doc_a)
  watershed_beam.set(
    watershed_beam.root(doc_a),
    "jobs",
    watershed_beam.ordered_collection_handle_of(queue_a),
  )
  sluice.settle(sluice)
  let assert Ok(handle) = watershed_beam.get(watershed_beam.root(doc_b), "jobs")
  let assert Ok(queue_b) =
    watershed_beam.resolve_ordered_collection(doc_b, handle)

  let events_a = watershed_beam.subscribe_ordered_collection(queue_a)
  let events_b = watershed_beam.subscribe_ordered_collection(queue_b)

  let job = json.string("job1")
  let assert Some(id_a) = watershed_beam.client_id(doc_a)
  let owner = Some(client_id.to_int(id_a))

  watershed_beam.ordered_add(queue_a, job)
  sluice.settle(sluice)
  watershed_beam.ordered_size(queue_b) |> expect.to_equal(Ok(1))
  watershed_beam.ordered_queue(queue_b) |> expect.to_equal([job])
  watershed_beam.ordered_jobs(queue_b) |> expect.to_equal([])

  let #(first_acquire, first_outcome) =
    watershed_beam.ordered_acquire_with_outcome(queue_a)
  sluice.settle(sluice)
  watershed_beam.ordered_size(queue_b) |> expect.to_equal(Ok(0))
  watershed_beam.ordered_queue(queue_b) |> expect.to_equal([])
  watershed_beam.ordered_jobs(queue_b)
  |> expect.to_equal([
    #(first_acquire, ordered_collection_kernel.JobEntry(job, owner)),
  ])
  process.receive(from: first_outcome, within: 1000)
  |> expect.to_equal(
    Ok(ordered_collection_kernel.AcquiredItem(first_acquire, job)),
  )

  watershed_beam.ordered_release(queue_a, first_acquire)
  sluice.settle(sluice)
  watershed_beam.ordered_size(queue_b) |> expect.to_equal(Ok(1))
  watershed_beam.ordered_jobs(queue_b) |> expect.to_equal([])

  let second_acquire = watershed_beam.ordered_acquire(queue_a)
  sluice.settle(sluice)
  watershed_beam.ordered_complete(queue_a, second_acquire)
  sluice.settle(sluice)
  watershed_beam.ordered_size(queue_b) |> expect.to_equal(Ok(0))
  watershed_beam.ordered_queue(queue_b) |> expect.to_equal([])
  watershed_beam.ordered_jobs(queue_b) |> expect.to_equal([])

  // An acquire that sequences against a drained queue resolves `QueueEmpty` —
  // and emits no event, which is why the outcome channel exists at all.
  let #(_losing_acquire, losing_outcome) =
    watershed_beam.ordered_acquire_with_outcome(queue_a)
  sluice.settle(sluice)
  process.receive(from: losing_outcome, within: 1000)
  |> expect.to_equal(Ok(ordered_collection_kernel.QueueEmpty))

  let lifecycle = fn(local) {
    [
      ordered_collection_kernel.Added(job, True, local),
      ordered_collection_kernel.Acquired(job, owner, local),
      ordered_collection_kernel.Added(job, False, local),
      ordered_collection_kernel.Acquired(job, owner, local),
      ordered_collection_kernel.Completed(job, local),
    ]
  }
  drain_ordered_events(events_a, [])
  |> expect.to_equal(lifecycle(True))
  drain_ordered_events(events_b, [])
  |> expect.to_equal(lifecycle(False))
}

@target(erlang)
fn drain_ordered_events(
  events: process.Subject(ordered_collection_kernel.OrderedEvent),
  acc: List(ordered_collection_kernel.OrderedEvent),
) -> List(ordered_collection_kernel.OrderedEvent) {
  case process.receive(from: events, within: 100) {
    Ok(event) -> drain_ordered_events(events, [event, ..acc])
    Error(_) -> list.reverse(acc)
  }
}

@target(erlang)
pub fn ops_since_summary_counts_the_unsummarized_log_test() -> Nil {
  // Nothing has summarized this document, so every sequenced message is drift
  // a joining client would have to replay. That number is what the automatic
  // policy thresholds on, and it is the one thing about summaries visible
  // from the facade without a storage server.
  let sluice = start("summary-drift")
  let doc_a = connect(sluice, "user-a")
  sluice.settle(sluice)

  let before = watershed_beam.ops_since_summary(doc_a)
  { before > 0 } |> expect.to_be_true()

  watershed_beam.set(watershed_beam.root(doc_a), "a", json.int(1))
  watershed_beam.set(watershed_beam.root(doc_a), "b", json.int(2))
  sluice.settle(sluice)

  watershed_beam.ops_since_summary(doc_a) |> expect.to_equal(before + 2)
}

@target(erlang)
pub fn a_failing_automatic_summary_leaves_the_document_working_test() -> Nil {
  // The sluice serves no summary storage and its documents carry no token, so
  // every attempt this policy makes fails at the first gate. That is the point:
  // a summarize op has no ack and no rollback, so a failed attempt must be
  // inert — the document keeps converging and the client keeps writing.
  let sluice = start("summary-attempt")
  let doc_a = connect(sluice, "user-a")
  let doc_b = connect(sluice, "user-b")
  sluice.settle(sluice)

  // Threshold 1 with no jitter: an attempt is armed by the next sequenced op.
  let policy =
    summary_policy.policy()
    |> summary_policy.with_threshold(1)
    |> summary_policy.with_jitter_ms(0)
  watershed_beam.auto_summarize(doc_a, policy)

  watershed_beam.set(watershed_beam.root(doc_a), "die", json.int(4))
  watershed_beam.set(watershed_beam.root(doc_b), "color", json.string("blue"))
  sluice.settle(sluice)
  // The wake-up is a timer message rather than a delivered frame, so it lands
  // outside the sluice's own barrier.
  process.sleep(50)
  sluice.settle(sluice)

  watershed_beam.set(watershed_beam.root(doc_a), "after", json.int(1))
  sluice.settle(sluice)

  same_entries(
    watershed_beam.entries(watershed_beam.root(doc_a)),
    watershed_beam.entries(watershed_beam.root(doc_b)),
  )
  |> expect.to_be_true()
  watershed_beam.get(watershed_beam.root(doc_b), "after")
  |> expect.to_equal(Ok(json.int(1)))
  // The attempt failed, so nothing moved the checkpoint.
  { watershed_beam.ops_since_summary(doc_a) > 0 } |> expect.to_be_true()
}

@target(erlang)
/// Two clients replace the same json0 key while both sockets are away, and the
/// room agrees on one value when they return.
///
/// A rejoin gives a client a **new** client id. The json0 transform side came
/// from that id before, so each author rebased its own pending op under the id
/// it held when it wrote the op, while every other client transformed the same
/// op under the id that the rejoin assigned. The two replicas then gave the
/// pair opposite sides, and the document forked: one client read `a` and the
/// other read `b`. The side now comes from the sequence order, so the
/// replacement that sequenced first wins everywhere.
pub fn concurrent_json_ot_replace_across_a_reconnect_converges_test() -> Nil {
  let sluice = start("json-ot-replace-reconnect")
  let doc_a = connect(sluice, "user-a")
  let doc_b = connect(sluice, "user-b")
  sluice.settle(sluice)

  let assert Ok(json_a) = watershed_beam.create_json_ot(doc_a)
  watershed_beam.set(
    watershed_beam.root(doc_a),
    "notes",
    watershed_beam.json_ot_handle_of(json_a),
  )
  watershed_beam.submit_json_ot(json_a, [
    json_ot.obj_insert([json_ot.Key("title")], json_ot.VString("x")),
  ])
  sluice.settle(sluice)

  let assert Ok(handle) =
    watershed_beam.get(watershed_beam.root(doc_b), "notes")
  let assert Ok(json_b) = watershed_beam.resolve_json_ot(doc_b, handle)
  sluice.settle(sluice)

  // Both sockets go, so neither replacement can read the other one.
  sluice.drop(sluice, doc_a)
  sluice.drop(sluice, doc_b)
  watershed_beam.submit_json_ot(json_a, [
    json_ot.obj_replace(
      [json_ot.Key("title")],
      json_ot.VString("x"),
      json_ot.VString("a"),
    ),
  ])
  watershed_beam.submit_json_ot(json_b, [
    json_ot.obj_replace(
      [json_ot.Key("title")],
      json_ot.VString("x"),
      json_ot.VString("b"),
    ),
  ])
  sluice.settle(sluice)

  sluice.rejoin(sluice, doc_a)
  sluice.rejoin(sluice, doc_b)
  sluice.settle(sluice)

  let seen_by_a = watershed_beam.json_ot_view(json_a)
  seen_by_a |> expect.to_equal(watershed_beam.json_ot_view(json_b))
  seen_by_a
  |> expect.to_equal(Ok(json_ot.VObject([#("title", json_ot.VString("a"))])))
}
