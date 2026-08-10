//// Ungated convergence tests driving real `watershed_js` documents against the
//// in-memory `sluice_js` on the JavaScript target (plan HM4). Proof that a
//// browser-shaped app converges deterministically with no server — and that
//// watershed's own suite can exercise the JS runtime without the optional
//// `phoenix` peer dep, since the sluice injects its own transport.

@target(javascript)
import gleam/json
@target(javascript)
import gleam/list
@target(javascript)
import gleam/option.{None, Some}
@target(javascript)
import gleam/string
@target(javascript)
import startest/expect

@target(javascript)
import watershed/client_id
@target(javascript)
import watershed/pact_map_kernel
@target(javascript)
import watershed/rich_text
@target(javascript)
import watershed/runtime_js
@target(javascript)
import watershed/schema
@target(javascript)
import watershed/sequence_kernel
@target(javascript)
import watershed/sluice_js
@target(javascript)
import watershed/text_kernel
@target(javascript)
import watershed/transport_js
@target(javascript)
import watershed_js

@target(javascript)
type SequenceFields

@target(javascript)
type TextFields

@target(javascript)
fn same_entries(
  a: List(#(String, json.Json)),
  b: List(#(String, json.Json)),
) -> Bool {
  normalize(a) == normalize(b)
}

@target(javascript)
fn normalize(entries: List(#(String, json.Json))) -> List(#(String, String)) {
  entries
  |> list.map(fn(entry) { #(entry.0, json.to_string(entry.1)) })
  |> list.sort(fn(x, y) { string.compare(x.0, y.0) })
}

@target(javascript)
fn rich_text_document(raw: String) -> rich_text.Document {
  let assert Ok(document) = rich_text.document_from_json_string(raw)
  document
}

@target(javascript)
fn rich_text_delta(raw: String) -> rich_text.Delta {
  let assert Ok(delta) = rich_text.delta_from_json_string(raw)
  delta
}

@target(javascript)
pub fn map_lww_converges_test() {
  let sluice = sluice_js.start(tenant: "default", document: "map-lww-js")
  let doc_a = sluice_js.connect(sluice, "user-a")
  let doc_b = sluice_js.connect(sluice, "user-b")
  sluice_js.settle(sluice)

  let map_a = watershed_js.root(doc_a)
  let map_b = watershed_js.root(doc_b)

  watershed_js.set(map_a, "die", json.int(4))
  watershed_js.set(map_b, "color", json.string("blue"))
  watershed_js.set(map_a, "shared", json.string("from-a"))
  watershed_js.set(map_b, "shared", json.string("from-b"))
  watershed_js.delete(map_a, "die")
  watershed_js.set(map_a, "die", json.int(6))
  sluice_js.settle(sluice)

  watershed_js.get(map_a, "die") |> expect.to_equal(Some(json.int(6)))
  watershed_js.get(map_b, "die") |> expect.to_equal(Some(json.int(6)))
  watershed_js.get(map_b, "color")
  |> expect.to_equal(Some(json.string("blue")))
  watershed_js.get(map_a, "shared")
  |> expect.to_equal(watershed_js.get(map_b, "shared"))
  same_entries(watershed_js.entries(map_a), watershed_js.entries(map_b))
  |> expect.to_be_true()

  // Late joiner replays history and lands on the same map.
  let doc_c = sluice_js.connect(sluice, "user-c")
  sluice_js.settle(sluice)
  let map_c = watershed_js.root(doc_c)
  same_entries(watershed_js.entries(map_c), watershed_js.entries(map_a))
  |> expect.to_be_true()
}

@target(javascript)
pub fn diagnostics_track_pending_and_sequenced_ops_test() {
  let sluice = sluice_js.start(tenant: "default", document: "diagnostics-js")
  let doc = sluice_js.connect(sluice, "user-a")

  let connecting = watershed_js.diagnostics(doc)
  connecting.phase |> expect.to_equal("connecting")
  connecting.synced |> expect.to_be_false()

  sluice_js.settle(sluice)
  let ready = watershed_js.diagnostics(doc)
  ready.phase |> expect.to_equal("ready")
  // SN 1 is the client's own sequenced join.
  ready.last_seen_sequence_number |> expect.to_equal(Some(1))
  ready.next_client_sequence_number |> expect.to_equal(Some(1))
  ready.in_flight_count |> expect.to_equal(0)
  ready.buffered_out_of_order_count |> expect.to_equal(0)
  ready.synced |> expect.to_be_true()

  watershed_js.set(watershed_js.root(doc), "k", json.int(1))
  let pending = watershed_js.diagnostics(doc)
  pending.last_seen_sequence_number |> expect.to_equal(Some(1))
  pending.next_client_sequence_number |> expect.to_equal(Some(2))
  pending.in_flight_count |> expect.to_equal(1)
  pending.synced |> expect.to_be_false()

  sluice_js.settle(sluice)
  let sequenced = watershed_js.diagnostics(doc)
  sequenced.last_seen_sequence_number |> expect.to_equal(Some(2))
  sequenced.in_flight_count |> expect.to_equal(0)
  sequenced.synced |> expect.to_be_true()
}

@target(javascript)
pub fn pause_holds_delivery_until_resume_test() {
  let sluice = sluice_js.start(tenant: "default", document: "pause-js")
  let doc_a = sluice_js.connect(sluice, "user-a")
  let doc_b = sluice_js.connect(sluice, "user-b")
  sluice_js.settle(sluice)

  // Hold B, then let A author an edit.
  sluice_js.pause(sluice, doc_b)
  watershed_js.set(watershed_js.root(doc_a), "k", json.string("v"))
  sluice_js.settle(sluice)

  // A sees its own edit; B is held and sees nothing yet.
  watershed_js.get(watershed_js.root(doc_a), "k")
  |> expect.to_equal(Some(json.string("v")))
  watershed_js.get(watershed_js.root(doc_b), "k") |> expect.to_equal(None)

  // Releasing B delivers the held op.
  sluice_js.resume(sluice, doc_b)
  sluice_js.settle(sluice)
  watershed_js.get(watershed_js.root(doc_b), "k")
  |> expect.to_equal(Some(json.string("v")))
}

@target(javascript)
pub fn step_info_reports_op_sequence_and_author_test() {
  let sluice = sluice_js.start(tenant: "default", document: "stepinfo-js")
  let doc_a = sluice_js.connect(sluice, "user-a")
  let _doc_b = sluice_js.connect(sluice, "user-b")
  sluice_js.settle(sluice)

  watershed_js.set(watershed_js.root(doc_a), "k", json.int(1))

  // Drain, collecting only the op deliveries' (sn, author).
  let ops = drain_op_meta(sluice, [])
  // The two handshakes sequenced a join apiece (SN 1 and 2), already drained by
  // `settle`. The one op is broadcast to both clients: two op frames, SN 3.
  ops |> list.length |> expect.to_equal(2)
  list.all(ops, fn(meta) { meta.0 == 3 }) |> expect.to_be_true()
}

@target(javascript)
fn drain_op_meta(
  sluice: sluice_js.Sluice,
  acc: List(#(Int, String)),
) -> List(#(Int, String)) {
  case sluice_js.step_info(sluice) {
    None -> list.reverse(acc)
    Some(delivery) ->
      case delivery.event {
        "op" ->
          drain_op_meta(sluice, [
            #(delivery.sequence_number, delivery.author),
            ..acc
          ])
        _ -> drain_op_meta(sluice, acc)
      }
  }
}

@target(javascript)
pub fn sequence_subscription_narrows_local_events_test() {
  let sluice =
    sluice_js.start(tenant: "default", document: "sequence-subscription-js")
  let document = sluice_js.connect(sluice, "user-a")
  sluice_js.settle(sluice)

  let assert Ok(sequence) = watershed_js.create_sequence(document)
  let events = transport_js.new_cell([])
  watershed_js.subscribe_sequence(sequence, fn(event) {
    transport_js.set_cell(events, [event])
  })
  let assert Ok(Nil) =
    watershed_js.sequence_insert(sequence, 0, json.string("first"))

  transport_js.get_cell(events)
  |> expect.to_equal([
    sequence_kernel.SequenceChanged([json.string("first")]),
  ])
}

@target(javascript)
pub fn ensure_sequence_adopts_stored_field_test() {
  let sluice =
    sluice_js.start(tenant: "default", document: "ensure-sequence-js")
  let doc_a = sluice_js.connect(sluice, "user-a")
  let doc_b = sluice_js.connect(sluice, "user-b")
  let field: schema.ChannelField(SequenceFields, schema.SequenceChannel) =
    schema.channel_field("items")
  let root_a: watershed_js.TypedMap(SequenceFields) =
    watershed_js.root_typed(doc_a)
  let root_b: watershed_js.TypedMap(SequenceFields) =
    watershed_js.root_typed(doc_b)
  sluice_js.settle(sluice)

  let assert Ok(sequence_a) = watershed_js.create_sequence(doc_a)
  watershed_js.set_sequence_field(root_a, field, sequence_a)
  sluice_js.settle(sluice)

  let result = transport_js.new_cell(None)
  watershed_js.ensure_sequence(doc_b, root_b, field, fn(value) {
    transport_js.set_cell(result, Some(value))
  })
  let assert Some(Ok(sequence_b)) = transport_js.get_cell(result)
  let assert Ok(Some(resolved)) =
    watershed_js.resolve_sequence_field(doc_b, root_b, field)
  let assert Ok(Nil) =
    watershed_js.sequence_insert(sequence_a, 0, json.string("ensured"))
  sluice_js.settle(sluice)
  watershed_js.sequence_values(sequence_b)
  |> expect.to_equal(watershed_js.sequence_values(resolved))
}

@target(javascript)
pub fn shared_sequence_converges_test() {
  let sluice =
    sluice_js.start(tenant: "default", document: "shared-sequence-js")
  let doc_a = sluice_js.connect(sluice, "user-a")
  let doc_b = sluice_js.connect(sluice, "user-b")
  sluice_js.settle(sluice)

  let assert Ok(sequence_a) = watershed_js.create_sequence(doc_a)
  let assert Ok(Nil) =
    watershed_js.sequence_insert(sequence_a, 0, json.string("base"))
  watershed_js.set(
    watershed_js.root(doc_a),
    "items",
    watershed_js.sequence_handle_of(sequence_a),
  )
  sluice_js.settle(sluice)

  let assert Some(sequence_handle) =
    watershed_js.get(watershed_js.root(doc_b), "items")
  let assert Ok(sequence_b) =
    watershed_js.resolve_sequence(doc_b, sequence_handle)
  case
    watershed_js.resolve_sequence(
      doc_b,
      watershed_js.handle_of(watershed_js.root(doc_b)),
    )
  {
    Error(_) -> Nil
    Ok(_) -> panic as "expected map handle resolution to fail for SharedSequence"
  }

  let assert Ok(Nil) =
    watershed_js.sequence_insert(sequence_a, 1, json.string("a"))
  let assert Ok(Nil) =
    watershed_js.sequence_insert(sequence_b, 1, json.string("b"))
  sluice_js.settle(sluice)

  watershed_js.sequence_values(sequence_a)
  |> expect.to_equal(watershed_js.sequence_values(sequence_b))

  let assert Ok(Nil) = watershed_js.sequence_move(sequence_a, 0, 2)
  let assert Ok(Nil) =
    watershed_js.sequence_replace(sequence_b, 0, json.string("B"))
  sluice_js.settle(sluice)
  watershed_js.sequence_values(sequence_a)
  |> expect.to_equal(watershed_js.sequence_values(sequence_b))

  watershed_js.sequence_delete(sequence_a, 99)
  |> expect.to_equal(Error("delete index 99 invalid for length 3"))
}

@target(javascript)
/// Convergence-to-equal is a weak oracle on its own: a sequence that dropped
/// every element under a concurrent move would satisfy it. The reorderable
/// playlist example (`examples/playlist_lustre`) promises that concurrent
/// reorders neither duplicate nor lose tracks, so pin that directly —
/// length preserved, no duplicates, and the racing replace still present.
pub fn concurrent_sequence_move_preserves_every_element_test() {
  let sluice = sluice_js.start(tenant: "default", document: "sequence-move-js")
  let doc_a = sluice_js.connect(sluice, "user-a")
  let doc_b = sluice_js.connect(sluice, "user-b")
  sluice_js.settle(sluice)

  let assert Ok(sequence_a) = watershed_js.create_sequence(doc_a)
  let assert Ok(Nil) =
    watershed_js.sequence_insert(sequence_a, 0, json.string("one"))
  let assert Ok(Nil) =
    watershed_js.sequence_insert(sequence_a, 1, json.string("two"))
  let assert Ok(Nil) =
    watershed_js.sequence_insert(sequence_a, 2, json.string("three"))
  watershed_js.set(
    watershed_js.root(doc_a),
    "tracks",
    watershed_js.sequence_handle_of(sequence_a),
  )
  sluice_js.settle(sluice)

  let assert Some(handle) = watershed_js.get(watershed_js.root(doc_b), "tracks")
  let assert Ok(sequence_b) = watershed_js.resolve_sequence(doc_b, handle)
  watershed_js.sequence_values(sequence_b)
  |> expect.to_equal([
    json.string("one"),
    json.string("two"),
    json.string("three"),
  ])

  // A lifts the head to the tail while B rewrites a different element. Move
  // destinations are interpreted after removal, so 2 is the tail of the
  // two-element list left behind — the same arithmetic the example's ↓ button
  // uses.
  let assert Ok(Nil) = watershed_js.sequence_move(sequence_a, 0, 2)
  let assert Ok(Nil) =
    watershed_js.sequence_replace(sequence_b, 1, json.string("TWO"))
  sluice_js.settle(sluice)

  let values_a = watershed_js.sequence_values(sequence_a)
  let values_b = watershed_js.sequence_values(sequence_b)

  values_a |> expect.to_equal(values_b)
  list.length(values_a) |> expect.to_equal(3)
  list.unique(values_a) |> expect.to_equal(values_a)
  list.contains(values_a, json.string("TWO")) |> expect.to_be_true()
  list.contains(values_a, json.string("one")) |> expect.to_be_true()
  list.contains(values_a, json.string("three")) |> expect.to_be_true()
}

@target(javascript)
pub fn runtime_rich_text_create_submit_and_view_test() {
  let sluice =
    sluice_js.start(tenant: "default", document: "runtime-rich-text-js")
  let document = sluice_js.connect(sluice, "user-a")
  sluice_js.settle(sluice)
  let runtime = watershed_js.runtime_of(document)
  let assert Ok(address) = runtime_js.create_rich_text(runtime)
  let first = rich_text_delta("[{\"insert\":\"A\"}]")

  runtime_js.submit_rich_text(runtime, address, first)
  runtime_js.rich_text_view(runtime, address)
  |> expect.to_equal(Some(rich_text_document("[{\"insert\":\"A\"}]")))

  runtime_js.submit_rich_text(
    runtime,
    address,
    rich_text_delta("[{\"retain\":1},{\"insert\":\"B\"}]"),
  )
  runtime_js.rich_text_view(runtime, address)
  |> expect.to_equal(Some(rich_text_document("[{\"insert\":\"AB\"}]")))
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared text
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
pub fn shared_text_converges_test() {
  let sluice = sluice_js.start(tenant: "default", document: "shared-text-js")
  let doc_a = sluice_js.connect(sluice, "user-a")
  let doc_b = sluice_js.connect(sluice, "user-b")
  sluice_js.settle(sluice)

  let assert Ok(text_a) = watershed_js.create_text(doc_a)
  let assert Ok(Nil) = watershed_js.text_insert(text_a, 0, "base")
  watershed_js.set(
    watershed_js.root(doc_a),
    "doc",
    watershed_js.text_handle_of(text_a),
  )
  sluice_js.settle(sluice)

  let assert Some(text_handle) =
    watershed_js.get(watershed_js.root(doc_b), "doc")
  let assert Ok(text_b) = watershed_js.resolve_text(doc_b, text_handle)
  // A map handle does not resolve as text.
  case
    watershed_js.resolve_text(
      doc_b,
      watershed_js.handle_of(watershed_js.root(doc_b)),
    )
  {
    Error(_) -> Nil
    Ok(_) -> panic as "expected map handle resolution to fail for SharedText"
  }
  watershed_js.text_value(text_b) |> expect.to_equal("base")

  // Concurrent inserts at the same index (both authors type at the gap
  // before "base" before either has seen the other's edit) still converge:
  // both replicas end up with the same string, containing both insertions.
  let assert Ok(Nil) = watershed_js.text_insert(text_a, 0, "A-")
  let assert Ok(Nil) = watershed_js.text_insert(text_b, 0, "B-")
  sluice_js.settle(sluice)

  watershed_js.text_value(text_a)
  |> expect.to_equal(watershed_js.text_value(text_b))
  let converged = watershed_js.text_value(text_a)
  string.contains(converged, "A-") |> expect.to_be_true()
  string.contains(converged, "B-") |> expect.to_be_true()
  string.contains(converged, "base") |> expect.to_be_true()

  // Overlapping delete-range (A) racing a replace-range (B) over intersecting
  // spans still converges deterministically once both sides have merged.
  let assert Ok(Nil) =
    watershed_js.text_replace_range(
      text_a,
      0,
      watershed_js.text_length(text_a),
      "abcdef",
    )
  sluice_js.settle(sluice)
  let assert Ok(Nil) = watershed_js.text_delete_range(text_a, 1, 4)
  let assert Ok(Nil) = watershed_js.text_replace_range(text_b, 2, 5, "XY")
  sluice_js.settle(sluice)
  watershed_js.text_value(text_a)
  |> expect.to_equal(watershed_js.text_value(text_b))

  // An append racing a concurrent insert also converges.
  let assert Ok(Nil) = watershed_js.text_append(text_a, "!!!")
  let assert Ok(Nil) = watershed_js.text_insert(text_b, 0, ">>")
  sluice_js.settle(sluice)
  watershed_js.text_value(text_a)
  |> expect.to_equal(watershed_js.text_value(text_b))

  // A late joiner replays history and lands on the same text.
  let doc_c = sluice_js.connect(sluice, "user-c")
  sluice_js.settle(sluice)
  let assert Some(handle_for_c) =
    watershed_js.get(watershed_js.root(doc_c), "doc")
  let assert Ok(text_c) = watershed_js.resolve_text(doc_c, handle_for_c)
  watershed_js.text_value(text_c)
  |> expect.to_equal(watershed_js.text_value(text_a))
}

@target(javascript)
pub fn shared_text_emoji_and_combining_graphemes_converge_test() {
  // "e" + combining acute (U+0301) is one grapheme cluster, and a
  // ZWJ-joined family emoji is a single grapheme despite many codepoints —
  // both must survive concurrent edits and index math intact.
  let sluice =
    sluice_js.start(tenant: "default", document: "shared-text-emoji-js")
  let doc_a = sluice_js.connect(sluice, "user-a")
  let doc_b = sluice_js.connect(sluice, "user-b")
  sluice_js.settle(sluice)

  let assert Ok(text_a) = watershed_js.create_text(doc_a)
  let combining_e = "e\u{0301}"
  let family =
    "👩" <> "\u{200D}" <> "👩" <> "\u{200D}" <> "👧" <> "\u{200D}" <> "👦"
  let assert Ok(Nil) =
    watershed_js.text_insert(text_a, 0, combining_e <> family)
  watershed_js.set(
    watershed_js.root(doc_a),
    "doc",
    watershed_js.text_handle_of(text_a),
  )
  sluice_js.settle(sluice)

  let assert Some(handle) = watershed_js.get(watershed_js.root(doc_b), "doc")
  let assert Ok(text_b) = watershed_js.resolve_text(doc_b, handle)
  watershed_js.text_length(text_b) |> expect.to_equal(2)
  watershed_js.text_value(text_b) |> expect.to_equal(combining_e <> family)
  watershed_js.text_substring(text_b, 0, 1) |> expect.to_equal(Ok(combining_e))
  watershed_js.text_substring(text_b, 1, 2) |> expect.to_equal(Ok(family))

  // Concurrent grapheme-cluster inserts between the two clusters, plus a
  // mixed-script append, converge to the same visible string on both sides.
  let assert Ok(Nil) = watershed_js.text_insert(text_a, 1, "🎉")
  let assert Ok(Nil) = watershed_js.text_append(text_b, "日д")
  sluice_js.settle(sluice)

  watershed_js.text_value(text_a)
  |> expect.to_equal(watershed_js.text_value(text_b))
  watershed_js.text_length(text_a) |> expect.to_equal(5)
  watershed_js.text_value(text_a)
  |> expect.to_equal(combining_e <> "🎉" <> family <> "日д")
}

@target(javascript)
pub fn shared_text_invalid_bounds_return_errors_test() {
  let sluice =
    sluice_js.start(tenant: "default", document: "shared-text-invalid-js")
  let document = sluice_js.connect(sluice, "user-a")
  sluice_js.settle(sluice)

  let assert Ok(text) = watershed_js.create_text(document)
  let assert Ok(Nil) = watershed_js.text_insert(text, 0, "hello")

  watershed_js.text_insert(text, 99, "x")
  |> expect.to_equal(Error("insert index 99 outside 0..5"))
  watershed_js.text_insert(text, -1, "x")
  |> expect.to_equal(Error("insert index -1 outside 0..5"))
  watershed_js.text_delete_range(text, 3, 1)
  |> expect.to_equal(Error("delete range 3..1 invalid for length 5"))
  watershed_js.text_delete_range(text, 0, 99)
  |> expect.to_equal(Error("delete range 0..99 invalid for length 5"))
  watershed_js.text_replace_range(text, 0, 99, "x")
  |> expect.to_equal(Error("replace range 0..99 invalid for length 5"))
  watershed_js.text_substring(text, 0, 99)
  |> expect.to_equal(Error("substring range 0..99 invalid for length 5"))

  // None of the rejected edits changed the text or left pending debris.
  watershed_js.text_value(text) |> expect.to_equal("hello")
}

@target(javascript)
pub fn shared_text_no_op_edits_do_not_submit_test() {
  // No-op edits (an empty insert/append, or a zero-length delete/replace)
  // must not submit a channel op: subscribers see no event, and a peer that
  // never delivers anything still converges since nothing was ever sent.
  let sluice =
    sluice_js.start(tenant: "default", document: "shared-text-no-op-js")
  let doc_a = sluice_js.connect(sluice, "user-a")
  let doc_b = sluice_js.connect(sluice, "user-b")
  sluice_js.settle(sluice)

  let assert Ok(text_a) = watershed_js.create_text(doc_a)
  let assert Ok(Nil) = watershed_js.text_insert(text_a, 0, "hello")
  watershed_js.set(
    watershed_js.root(doc_a),
    "doc",
    watershed_js.text_handle_of(text_a),
  )
  sluice_js.settle(sluice)

  let assert Some(handle) = watershed_js.get(watershed_js.root(doc_b), "doc")
  let assert Ok(text_b) = watershed_js.resolve_text(doc_b, handle)

  let events = transport_js.new_cell([])
  watershed_js.subscribe_text(text_a, fn(event) {
    transport_js.set_cell(events, [event, ..transport_js.get_cell(events)])
  })

  // An empty insert at a valid index is a no-op: it returns Ok(Nil), fires
  // no event, and never reaches the wire.
  watershed_js.text_insert(text_a, 2, "") |> expect.to_equal(Ok(Nil))
  // A zero-length delete-range/replace-range is likewise a no-op.
  watershed_js.text_delete_range(text_a, 2, 2) |> expect.to_equal(Ok(Nil))
  watershed_js.text_replace_range(text_a, 2, 2, "") |> expect.to_equal(Ok(Nil))
  // Appending "" is a no-op too.
  watershed_js.text_append(text_a, "") |> expect.to_equal(Ok(Nil))

  transport_js.get_cell(events) |> expect.to_equal([])
  sluice_js.settle(sluice)

  // Nothing was ever submitted, so B never saw an update and both sides
  // remain exactly "hello".
  watershed_js.text_value(text_a) |> expect.to_equal("hello")
  watershed_js.text_value(text_b) |> expect.to_equal("hello")
}

@target(javascript)
pub fn shared_text_subscription_narrows_local_events_test() {
  let sluice =
    sluice_js.start(tenant: "default", document: "shared-text-subscription-js")
  let document = sluice_js.connect(sluice, "user-a")
  sluice_js.settle(sluice)

  let assert Ok(text) = watershed_js.create_text(document)
  let events = transport_js.new_cell([])
  watershed_js.subscribe_text(text, fn(event) {
    transport_js.set_cell(events, [event])
  })
  let assert Ok(Nil) = watershed_js.text_insert(text, 0, "first")

  transport_js.get_cell(events)
  |> expect.to_equal([text_kernel.TextChanged("first")])
}

@target(javascript)
pub fn ensure_text_adopts_stored_field_test() {
  let sluice = sluice_js.start(tenant: "default", document: "ensure-text-js")
  let doc_a = sluice_js.connect(sluice, "user-a")
  let doc_b = sluice_js.connect(sluice, "user-b")
  let field: schema.ChannelField(TextFields, schema.TextChannel) =
    schema.channel_field("body")
  let root_a: watershed_js.TypedMap(TextFields) = watershed_js.root_typed(doc_a)
  let root_b: watershed_js.TypedMap(TextFields) = watershed_js.root_typed(doc_b)
  sluice_js.settle(sluice)

  let assert Ok(text_a) = watershed_js.create_text(doc_a)
  watershed_js.set_text_field(root_a, field, text_a)
  sluice_js.settle(sluice)

  let result = transport_js.new_cell(None)
  watershed_js.ensure_text(doc_b, root_b, field, fn(value) {
    transport_js.set_cell(result, Some(value))
  })
  let assert Some(Ok(text_b)) = transport_js.get_cell(result)
  let assert Ok(Some(resolved)) =
    watershed_js.resolve_text_field(doc_b, root_b, field)
  let assert Ok(Nil) = watershed_js.text_insert(text_a, 0, "ensured")
  sluice_js.settle(sluice)
  watershed_js.text_value(text_b)
  |> expect.to_equal(watershed_js.text_value(resolved))
}

// ─────────────────────────────────────────────────────────────────────────────
// Consensus quorum
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// A `PactMap` set stays pending until *every* connected client has signed off.
///
/// This needs three clients: with two, a quorum that ignores the roster
/// entirely and names only `[self, author]` is indistinguishable from a correct
/// one, because self and author *are* the whole room. The third client is the
/// one a fabricated quorum forgets, and the assertion that matters is that C's
/// agreement is required — not merely that the value eventually lands.
pub fn pact_map_pends_until_the_whole_room_signs_off_test() {
  let sluice = sluice_js.start(tenant: "default", document: "pact-quorum-js")
  let doc_a = sluice_js.connect(sluice, "user-a")
  let doc_b = sluice_js.connect(sluice, "user-b")
  let doc_c = sluice_js.connect(sluice, "user-c")
  sluice_js.settle(sluice)

  let assert Ok(pact_a) = watershed_js.create_pact_map(doc_a)
  watershed_js.set(
    watershed_js.root(doc_a),
    "tempo",
    watershed_js.pact_map_handle_of(pact_a),
  )
  sluice_js.settle(sluice)

  let assert Some(handle) = watershed_js.get(watershed_js.root(doc_b), "tempo")
  let assert Ok(pact_b) = watershed_js.resolve_pact_map(doc_b, handle)
  let assert Ok(pact_c) = watershed_js.resolve_pact_map(doc_c, handle)

  // A proposes. Hold C so it cannot sign off, then drain everything else: the
  // pact must still be pending, because C is in the quorum and has not agreed.
  sluice_js.pause(sluice, doc_c)
  watershed_js.pact_map_set(pact_a, "bpm", json.int(120))
  sluice_js.settle(sluice)

  watershed_js.pact_map_is_pending(pact_a, "bpm") |> expect.to_be_true()
  watershed_js.pact_map_is_pending(pact_b, "bpm") |> expect.to_be_true()
  watershed_js.pact_map_get(pact_a, "bpm") |> expect.to_equal(None)

  // The signoff list is the *outstanding* one — A and B have already signed
  // off, so what remains names exactly the client being waited on: C. That is
  // the assertion a two-client test cannot make. It also pins the quorum's
  // membership precisely, where a length check would not: under the old
  // `[self, author]` quorum A signs off alone and nothing is ever pending here.
  let assert Ok(id_c) = sluice_js.client_id(sluice, doc_c)
  let outstanding = [client_id.to_int(id_c)]
  watershed_js.pact_map_pending_signoffs(pact_a, "bpm")
  |> expect.to_equal(Some(outstanding))
  watershed_js.pact_map_pending_signoffs(pact_b, "bpm")
  |> expect.to_equal(Some(outstanding))
  // Nothing is accepted yet, so there are no accepted details to read.
  watershed_js.pact_map_get_with_details(pact_a, "bpm")
  |> expect.to_equal(None)

  // Release C; its signoff drains the list and the value is accepted by all.
  sluice_js.resume(sluice, doc_c)
  sluice_js.settle(sluice)

  watershed_js.pact_map_is_pending(pact_a, "bpm") |> expect.to_be_false()
  watershed_js.pact_map_is_pending(pact_b, "bpm") |> expect.to_be_false()
  watershed_js.pact_map_is_pending(pact_c, "bpm") |> expect.to_be_false()
  watershed_js.pact_map_get(pact_a, "bpm")
  |> option.map(json.to_string)
  |> expect.to_equal(Some("120"))
  watershed_js.pact_map_get(pact_c, "bpm")
  |> option.map(json.to_string)
  |> expect.to_equal(Some("120"))

  // Once accepted there is nothing left to sign off, and the accepted entry
  // carries the sequence number the pact settled at.
  watershed_js.pact_map_pending_signoffs(pact_a, "bpm") |> expect.to_equal(None)
  let assert Some(accepted) =
    watershed_js.pact_map_get_with_details(pact_a, "bpm")
  { accepted.sequence_number > 0 } |> expect.to_be_true()
}

@target(javascript)
/// `client_id` exists so a client can find *itself* in a list some kernel
/// reports about the room. That is the only claim worth testing, and it is a
/// claim about agreement between two independent derivations: the id the
/// facade hands out, and the integer a consensus kernel writes into a signoff
/// list. This asserts they name the same client.
///
/// The stale-cache failure is the reason it matters. An app that reads its id
/// once and keeps it will silently stop matching after a reconnect assigns a
/// new one, and the symptom — a pending list that never says "you" — looks
/// like a rendering bug rather than an identity one.
pub fn client_id_matches_the_id_kernels_report_test() {
  let sluice = sluice_js.start(tenant: "default", document: "client-id-js")
  let doc_a = sluice_js.connect(sluice, "user-a")
  let doc_b = sluice_js.connect(sluice, "user-b")
  let doc_c = sluice_js.connect(sluice, "user-c")

  // Before the handshake there is no server-assigned id to report, and the
  // honest answer is `None` rather than a placeholder that would quietly
  // match nothing.
  watershed_js.client_id(doc_a) |> expect.to_equal(None)

  sluice_js.settle(sluice)
  let assert Some(id_a) = watershed_js.client_id(doc_a)
  let assert Some(id_c) = watershed_js.client_id(doc_c)
  { id_a != id_c } |> expect.to_be_true()
  // The facade agrees with the sluice about who this client is.
  sluice_js.client_id(sluice, doc_a) |> expect.to_equal(Ok(id_a))

  let assert Ok(pact_a) = watershed_js.create_pact_map(doc_a)
  watershed_js.set(
    watershed_js.root(doc_a),
    "tempo",
    watershed_js.pact_map_handle_of(pact_a),
  )
  sluice_js.settle(sluice)
  let assert Some(handle) = watershed_js.get(watershed_js.root(doc_b), "tempo")
  let assert Ok(pact_c) = watershed_js.resolve_pact_map(doc_c, handle)

  // Hold C, propose, and the outstanding signoff list names exactly C — which
  // C can now recognise as itself, going through the public derivation an app
  // would use.
  sluice_js.pause(sluice, doc_c)
  watershed_js.pact_map_set(pact_a, "bpm", json.int(128))
  sluice_js.settle(sluice)

  watershed_js.pact_map_pending_signoffs(pact_a, "bpm")
  |> expect.to_equal(Some([client_id.to_int(id_c)]))

  // And from C's own side: "is the room waiting on me?" is answerable.
  sluice_js.resume(sluice, doc_c)
  sluice_js.settle(sluice)
  let assert Some(id_c_now) = watershed_js.client_id(doc_c)
  let waiting_on_me = case
    watershed_js.pact_map_pending_signoffs(pact_c, "bpm")
  {
    Some(ids) -> list.contains(ids, client_id.to_int(id_c_now))
    None -> False
  }
  waiting_on_me |> expect.to_be_false()
}

// ─────────────────────────────────────────────────────────────────────────────
// Subscriptions on the kinds that had none (FP3)
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// A PN-counter subscriber learns about a *peer's* update. Before this existed
/// the kind was write-and-poll: an app could increment and read but had no way
/// to hear that anyone else had.
pub fn subscribe_pn_counter_observes_a_peer_update_test() {
  let sluice = sluice_js.start(tenant: "default", document: "pn-subscribe-js")
  let doc_a = sluice_js.connect(sluice, "user-a")
  let doc_b = sluice_js.connect(sluice, "user-b")
  sluice_js.settle(sluice)

  let assert Ok(counter_a) = watershed_js.create_pn_counter(doc_a)
  watershed_js.set(
    watershed_js.root(doc_a),
    "votes",
    watershed_js.pn_counter_handle_of(counter_a),
  )
  sluice_js.settle(sluice)
  let assert Some(handle) = watershed_js.get(watershed_js.root(doc_b), "votes")
  let assert Ok(counter_b) = watershed_js.resolve_pn_counter(doc_b, handle)

  // B watches; A moves the counter.
  let seen = transport_js.new_cell([])
  watershed_js.subscribe_pn_counter(counter_b, fn(event) {
    transport_js.set_cell(seen, [event, ..transport_js.get_cell(seen)])
  })
  watershed_js.pn_counter_update(counter_a, -3)
  sluice_js.settle(sluice)

  { list.length(transport_js.get_cell(seen)) > 0 } |> expect.to_be_true()
  watershed_js.pn_counter_value(counter_b) |> expect.to_equal(Some(-3))
}

@target(javascript)
/// A PactMap subscriber sees both consensus transitions in order:
/// `WentPending` when the proposal is sequenced, `WentAccepted` once the
/// signoff list drains. Those two events *are* the protocol — without them the
/// one interesting thing about the kind is unobservable.
pub fn subscribe_pact_map_observes_both_transitions_test() {
  let sluice = sluice_js.start(tenant: "default", document: "pact-subscribe-js")
  let doc_a = sluice_js.connect(sluice, "user-a")
  let doc_b = sluice_js.connect(sluice, "user-b")
  let doc_c = sluice_js.connect(sluice, "user-c")
  sluice_js.settle(sluice)

  let assert Ok(pact_a) = watershed_js.create_pact_map(doc_a)
  watershed_js.set(
    watershed_js.root(doc_a),
    "tempo",
    watershed_js.pact_map_handle_of(pact_a),
  )
  sluice_js.settle(sluice)
  let assert Some(handle) = watershed_js.get(watershed_js.root(doc_b), "tempo")
  let assert Ok(pact_b) = watershed_js.resolve_pact_map(doc_b, handle)
  let assert Ok(_pact_c) = watershed_js.resolve_pact_map(doc_c, handle)

  let seen = transport_js.new_cell([])
  watershed_js.subscribe_pact_map(pact_b, fn(event) {
    transport_js.set_cell(seen, [event, ..transport_js.get_cell(seen)])
  })

  // Hold C so the pending window is a state, not a race.
  sluice_js.pause(sluice, doc_c)
  watershed_js.pact_map_set(pact_a, "bpm", json.int(120))
  sluice_js.settle(sluice)
  transport_js.get_cell(seen)
  |> expect.to_equal([pact_map_kernel.WentPending("bpm")])

  sluice_js.resume(sluice, doc_c)
  sluice_js.settle(sluice)
  transport_js.get_cell(seen)
  |> expect.to_equal([
    pact_map_kernel.WentAccepted("bpm"),
    pact_map_kernel.WentPending("bpm"),
  ])
}

@target(javascript)
/// An ordered-collection subscriber sees a peer's append land on the queue.
pub fn subscribe_ordered_collection_observes_a_peer_add_test() {
  let sluice =
    sluice_js.start(tenant: "default", document: "ordered-subscribe-js")
  let doc_a = sluice_js.connect(sluice, "user-a")
  let doc_b = sluice_js.connect(sluice, "user-b")
  sluice_js.settle(sluice)

  let assert Ok(queue_a) = watershed_js.create_ordered_collection(doc_a)
  watershed_js.set(
    watershed_js.root(doc_a),
    "jobs",
    watershed_js.ordered_collection_handle_of(queue_a),
  )
  sluice_js.settle(sluice)
  let assert Some(handle) = watershed_js.get(watershed_js.root(doc_b), "jobs")
  let assert Ok(queue_b) =
    watershed_js.resolve_ordered_collection(doc_b, handle)

  let seen = transport_js.new_cell([])
  watershed_js.subscribe_ordered_collection(queue_b, fn(event) {
    transport_js.set_cell(seen, [event, ..transport_js.get_cell(seen)])
  })
  watershed_js.ordered_add(queue_a, json.string("job1"))
  sluice_js.settle(sluice)

  { list.length(transport_js.get_cell(seen)) > 0 } |> expect.to_be_true()
  watershed_js.ordered_size(queue_b) |> expect.to_equal(Some(1))
}

@target(javascript)
/// A late joiner must reconstruct the same lock queue everyone else holds —
/// including for a client that volunteered and has since disconnected.
///
/// This passes today, but not for a good reason, and that is why it is pinned
/// here. `task_manager_kernel.apply_volunteer_core` guards on
/// `list.contains(quorum, author)`, and `runtime_core.quorum_of` unions the
/// op's author into the quorum unconditionally — so the guard has never once
/// been able to fail. It is dead code holding a live invariant.
///
/// Making the replay roster time-correct means that union can stop hiding the
/// guard, and this is the test that says whether activating it broke anything.
/// It should not: a client's `join` is always sequenced before any op it
/// authors, so a correctly reconstructed roster contains the author at the
/// point their `Volunteer` is replayed.
pub fn task_manager_replays_the_same_queue_for_a_late_joiner_test() {
  let sluice = sluice_js.start(tenant: "default", document: "tm-replay-js")
  let doc_a = sluice_js.connect(sluice, "user-a")
  let doc_b = sluice_js.connect(sluice, "user-b")
  let doc_c = sluice_js.connect(sluice, "user-c")
  sluice_js.settle(sluice)

  let assert Ok(tm_a) = watershed_js.create_task_manager(doc_a)
  watershed_js.set(
    watershed_js.root(doc_a),
    "roles",
    watershed_js.task_manager_handle_of(tm_a),
  )
  sluice_js.settle(sluice)
  let assert Some(handle) = watershed_js.get(watershed_js.root(doc_b), "roles")
  let assert Ok(tm_c) = watershed_js.resolve_task_manager(doc_c, handle)

  // C takes the role, A queues behind it.
  watershed_js.volunteer_for_task(tm_c, "leader")
  sluice_js.settle(sluice)
  watershed_js.volunteer_for_task(tm_a, "leader")
  sluice_js.settle(sluice)
  let assert Some(id_c) = watershed_js.client_id(doc_c)
  let assert Some(id_a) = watershed_js.client_id(doc_a)
  watershed_js.task_queues(tm_a)
  |> expect.to_equal([
    #("leader", [client_id.to_int(id_c), client_id.to_int(id_a)]),
  ])

  // C vanishes; the role passes to A.
  sluice_js.disconnect(sluice, doc_c)
  sluice_js.settle(sluice)
  watershed_js.task_assigned(tm_a, "leader") |> expect.to_be_true()

  // A client arriving now replays `volunteer(C)`, `volunteer(A)`, `leave(C)`
  // — a history in which the first volunteer comes from a client that is no
  // longer in the room — and must land on the same queue A holds.
  let doc_d = sluice_js.connect(sluice, "user-late")
  sluice_js.settle(sluice)
  let assert Some(handle_d) =
    watershed_js.get(watershed_js.root(doc_d), "roles")
  let assert Ok(tm_d) = watershed_js.resolve_task_manager(doc_d, handle_d)

  watershed_js.task_queues(tm_d)
  |> expect.to_equal([#("leader", [client_id.to_int(id_a)])])
  watershed_js.task_queues(tm_d)
  |> expect.to_equal(watershed_js.task_queues(tm_a))
}

@target(javascript)
/// Replaying a settled pact must reproduce its *outcome*, not re-run its
/// protocol against today's room.
///
/// The joiner was not in the room when the proposal was sequenced, so it is
/// not in that proposal's quorum, owes no `Accept`, and must simply observe
/// the value the room already agreed. Getting this wrong made a document with
/// an agreed `PactMap` key unjoinable: the joiner wrote itself into a quorum
/// it was never part of, reconstructed the settled pact as pending on itself,
/// and — against a real server — sent peers an `Accept` for a pact they had
/// long since settled, which they rejected as `UnexpectedAccept`.
///
/// The second half covers the case a roster-only fix would still break: one of
/// the clients that *did* sign off has since left, so the joiner replays an
/// `Accept` from a client that is not in the room now and never will be.
pub fn a_settled_pact_replays_intact_for_a_late_joiner_test() {
  let sluice = sluice_js.start(tenant: "default", document: "pact-replay-js")
  let doc_a = sluice_js.connect(sluice, "user-a")
  let doc_b = sluice_js.connect(sluice, "user-b")
  let doc_c = sluice_js.connect(sluice, "user-c")
  sluice_js.settle(sluice)

  let assert Ok(pact_a) = watershed_js.create_pact_map(doc_a)
  watershed_js.set(
    watershed_js.root(doc_a),
    "tempo",
    watershed_js.pact_map_handle_of(pact_a),
  )
  sluice_js.settle(sluice)
  let assert Some(handle) = watershed_js.get(watershed_js.root(doc_b), "tempo")

  watershed_js.pact_map_set(pact_a, "bpm", json.int(128))
  sluice_js.settle(sluice)
  watershed_js.pact_map_is_pending(pact_a, "bpm") |> expect.to_be_false()

  // A fourth client joins and replays `Set` + three `Accept`s.
  let doc_d = sluice_js.connect(sluice, "user-d")
  sluice_js.settle(sluice)
  let assert Ok(pact_d) = watershed_js.resolve_pact_map(doc_d, handle)
  watershed_js.pact_map_get(pact_d, "bpm")
  |> option.map(json.to_string)
  |> expect.to_equal(Some("128"))
  watershed_js.pact_map_is_pending(pact_d, "bpm") |> expect.to_be_false()
  watershed_js.pact_map_pending_signoffs(pact_d, "bpm") |> expect.to_equal(None)

  // C — one of the three that signed off — leaves. A fifth client then joins
  // and replays an `Accept` authored by a client no longer in the room.
  sluice_js.disconnect(sluice, doc_c)
  sluice_js.settle(sluice)
  let doc_e = sluice_js.connect(sluice, "user-e")
  sluice_js.settle(sluice)
  let assert Ok(pact_e) = watershed_js.resolve_pact_map(doc_e, handle)
  watershed_js.pact_map_get(pact_e, "bpm")
  |> option.map(json.to_string)
  |> expect.to_equal(Some("128"))
  watershed_js.pact_map_is_pending(pact_e, "bpm") |> expect.to_be_false()

  // Both newcomers are full members now: a fresh proposal waits on them and
  // reaches them.
  watershed_js.pact_map_set(pact_d, "bpm", json.int(96))
  sluice_js.settle(sluice)
  watershed_js.pact_map_get(pact_e, "bpm")
  |> option.map(json.to_string)
  |> expect.to_equal(Some("96"))
  watershed_js.pact_map_get(pact_a, "bpm")
  |> option.map(json.to_string)
  |> expect.to_equal(Some("96"))
}

// ─────────────────────────────────────────────────────────────────────────────
// Reconnect
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// The primitive itself: the socket goes, the client comes back under a new
/// identity, and the document it was editing is still there.
pub fn reconnect_rejoins_under_a_fresh_client_id_test() {
  let sluice = sluice_js.start(tenant: "default", document: "reconnect-id-js")
  let doc_a = sluice_js.connect(sluice, "user-a")
  let doc_b = sluice_js.connect(sluice, "user-b")
  sluice_js.settle(sluice)

  watershed_js.set(watershed_js.root(doc_a), "before", json.int(1))
  sluice_js.settle(sluice)
  let assert Ok(was) = sluice_js.client_id(sluice, doc_a)

  sluice_js.reconnect(sluice, doc_a)
  sluice_js.settle(sluice)

  let assert Ok(now) = sluice_js.client_id(sluice, doc_a)
  { now != was } |> expect.to_be_true()

  // The core survived the drop, and the link is live in both directions again.
  watershed_js.get(watershed_js.root(doc_a), "before")
  |> option.map(json.to_string)
  |> expect.to_equal(Some("1"))
  watershed_js.set(watershed_js.root(doc_a), "after", json.int(2))
  sluice_js.settle(sluice)
  watershed_js.get(watershed_js.root(doc_b), "after")
  |> option.map(json.to_string)
  |> expect.to_equal(Some("2"))
}

@target(javascript)
/// A client that reconnects into a live proposal converges: it owes a signoff
/// under the identity it came back with, discovers that while still catching
/// up, and the room settles.
///
/// The companion in the erlang driver
/// (`a_released_accept_is_not_sent_twice_across_a_reconnect_test`) is the one
/// that *pins* the double-send this exercises the shape of — it fails with that
/// fix reverted, and this does not. The JS runtime carries the same defect and
/// the same fix, but reports core errors by failing the connection rather than
/// crashing, and no scripting of this window has yet made the duplicate
/// observable here. Treat the erlang test as the regression guard.
pub fn a_reconnect_with_a_live_proposal_converges_test() {
  let sluice =
    sluice_js.start(tenant: "default", document: "reconnect-accept-js")
  let doc_a = sluice_js.connect(sluice, "user-a")
  let doc_b = sluice_js.connect(sluice, "user-b")
  let doc_c = sluice_js.connect(sluice, "user-c")
  sluice_js.settle(sluice)

  let assert Ok(pact_a) = watershed_js.create_pact_map(doc_a)
  watershed_js.set(
    watershed_js.root(doc_a),
    "settings",
    watershed_js.pact_map_handle_of(pact_a),
  )
  sluice_js.settle(sluice)
  let assert Some(handle) =
    watershed_js.get(watershed_js.root(doc_b), "settings")
  let assert Ok(pact_b) = watershed_js.resolve_pact_map(doc_b, handle)
  let assert Ok(pact_c) = watershed_js.resolve_pact_map(doc_c, handle)

  // Put C far enough behind that its catch-up comes back as one batch.
  sluice_js.pause(sluice, doc_c)
  watershed_js.set(watershed_js.root(doc_a), "filler", json.int(1))
  sluice_js.settle(sluice)

  // Rejoin C, then propose *before* delivering anything. The proposal is
  // sequenced after C's new join, so the signoff list names the identity C now
  // has and C genuinely owes an `Accept` — which it discovers while still
  // catching up, in the same batch that completes its reconnect.
  sluice_js.reconnect(sluice, doc_c)
  watershed_js.pact_map_set(pact_a, "bpm", json.int(128))
  sluice_js.settle(sluice)

  watershed_js.get(watershed_js.root(doc_c), "filler")
  |> option.map(json.to_string)
  |> expect.to_equal(Some("1"))
  watershed_js.pact_map_get(pact_a, "bpm")
  |> option.map(json.to_string)
  |> expect.to_equal(Some("128"))
  watershed_js.pact_map_get(pact_c, "bpm")
  |> option.map(json.to_string)
  |> expect.to_equal(Some("128"))
  watershed_js.pact_map_is_pending(pact_b, "bpm") |> expect.to_be_false()

  // C is still a working client. This is the assertion that discriminates: the
  // JS runtime reports a core error by failing the connection rather than
  // crashing, so a duplicate ack leaves a quietly dead client whose state still
  // reads correctly. Only writing through it notices.
  watershed_js.set(watershed_js.root(doc_c), "after", json.int(3))
  sluice_js.settle(sluice)
  watershed_js.get(watershed_js.root(doc_a), "after")
  |> option.map(json.to_string)
  |> expect.to_equal(Some("3"))
}

@target(javascript)
/// A proposal sequenced while a client is away must not gain a signoff from
/// the identity that client comes back under. The erlang driver's companion
/// carries the full explanation; this is the parity check, since the fix lives
/// in the shared `runtime_core`.
pub fn a_proposal_made_while_away_does_not_gain_the_returning_client_test() {
  let sluice =
    sluice_js.start(tenant: "default", document: "reconnect-window-js")
  let doc_a = sluice_js.connect(sluice, "user-a")
  let doc_b = sluice_js.connect(sluice, "user-b")
  let doc_c = sluice_js.connect(sluice, "user-c")
  sluice_js.settle(sluice)

  let assert Ok(pact_a) = watershed_js.create_pact_map(doc_a)
  watershed_js.set(
    watershed_js.root(doc_a),
    "settings",
    watershed_js.pact_map_handle_of(pact_a),
  )
  sluice_js.settle(sluice)
  let assert Some(handle) =
    watershed_js.get(watershed_js.root(doc_b), "settings")
  let assert Ok(pact_b) = watershed_js.resolve_pact_map(doc_b, handle)
  let assert Ok(_) = watershed_js.resolve_pact_map(doc_c, handle)

  // Hold B so the proposal is still outstanding when C returns: a settled pact
  // ignores a stray `Accept`, a pending one rejects it.
  sluice_js.pause(sluice, doc_b)
  sluice_js.drop(sluice, doc_c)
  watershed_js.pact_map_set(pact_a, "bpm", json.int(128))
  sluice_js.settle(sluice)
  watershed_js.pact_map_is_pending(pact_a, "bpm") |> expect.to_be_true()

  sluice_js.rejoin(sluice, doc_c)
  sluice_js.settle(sluice)
  sluice_js.resume(sluice, doc_b)
  sluice_js.settle(sluice)

  let assert Ok(pact_c) = watershed_js.resolve_pact_map(doc_c, handle)
  watershed_js.pact_map_get(pact_c, "bpm")
  |> option.map(json.to_string)
  |> expect.to_equal(Some("128"))
  watershed_js.pact_map_is_pending(pact_c, "bpm") |> expect.to_be_false()

  // The room is still usable afterwards — C's connection survived.
  watershed_js.pact_map_set(pact_b, "bpm", json.int(96))
  sluice_js.settle(sluice)
  watershed_js.pact_map_get(pact_c, "bpm")
  |> option.map(json.to_string)
  |> expect.to_equal(Some("96"))
}

// ─────────────────────────────────────────────────────────────────────────────
// The offline toggle
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// A client goes offline, keeps editing, and its edits land when it returns.
///
/// Neither existing hook expresses this. `force_reconnect` reconnects on the
/// next statement, so there is no window to edit in; `close` parks the runtime
/// in `Failed` with no way out, so coming back means a fresh `connect` — a new
/// core, and the pending queue this asserts the survival of is gone with it.
pub fn go_offline_holds_edits_until_go_online_test() {
  let sluice = sluice_js.start(tenant: "default", document: "offline-toggle-js")
  let doc_a = sluice_js.connect(sluice, "user-a")
  let doc_b = sluice_js.connect(sluice, "user-b")
  sluice_js.settle(sluice)

  watershed_js.go_offline(doc_a)
  sluice_js.settle(sluice)
  watershed_js.diagnostics(doc_a).phase |> expect.to_equal("reconnecting")

  // A keeps painting with the socket away: the edit is optimistically visible
  // to A and to nobody else.
  watershed_js.set(watershed_js.root(doc_a), "offline", json.int(7))
  sluice_js.settle(sluice)
  watershed_js.get(watershed_js.root(doc_a), "offline")
  |> option.map(json.to_string)
  |> expect.to_equal(Some("7"))
  watershed_js.get(watershed_js.root(doc_b), "offline") |> expect.to_equal(None)

  watershed_js.go_online(doc_a)
  sluice_js.settle(sluice)

  watershed_js.diagnostics(doc_a).phase |> expect.to_equal("ready")
  watershed_js.get(watershed_js.root(doc_b), "offline")
  |> option.map(json.to_string)
  |> expect.to_equal(Some("7"))
}

@target(javascript)
/// Both halves of the room edit while one of them is away, and the reunion is
/// the union of the two. This is the claim the pixel canvas makes out loud.
pub fn edits_made_on_both_sides_of_an_offline_window_merge_test() {
  let sluice = sluice_js.start(tenant: "default", document: "offline-merge-js")
  let doc_a = sluice_js.connect(sluice, "user-a")
  let doc_b = sluice_js.connect(sluice, "user-b")
  sluice_js.settle(sluice)

  watershed_js.go_offline(doc_a)
  sluice_js.settle(sluice)

  // Disjoint regions, painted concurrently by a client that cannot hear and a
  // client that cannot be heard.
  watershed_js.set(watershed_js.root(doc_a), "from-a", json.int(1))
  watershed_js.set(watershed_js.root(doc_b), "from-b", json.int(2))
  sluice_js.settle(sluice)

  watershed_js.go_online(doc_a)
  sluice_js.settle(sluice)

  list.each([doc_a, doc_b], fn(doc) {
    let root = watershed_js.root(doc)
    watershed_js.get(root, "from-a")
    |> option.map(json.to_string)
    |> expect.to_equal(Some("1"))
    watershed_js.get(root, "from-b")
    |> option.map(json.to_string)
    |> expect.to_equal(Some("2"))
  })
}

@target(javascript)
/// The same key written on both sides of the window settles the same way for
/// everyone. Which writer wins is the kernel's business and deliberately not
/// asserted — only that the room agrees on one answer.
pub fn a_key_contested_across_an_offline_window_converges_test() {
  let sluice =
    sluice_js.start(tenant: "default", document: "offline-contested-js")
  let doc_a = sluice_js.connect(sluice, "user-a")
  let doc_b = sluice_js.connect(sluice, "user-b")
  sluice_js.settle(sluice)

  watershed_js.go_offline(doc_a)
  sluice_js.settle(sluice)

  watershed_js.set(watershed_js.root(doc_a), "cell", json.string("a"))
  watershed_js.set(watershed_js.root(doc_b), "cell", json.string("b"))
  sluice_js.settle(sluice)

  watershed_js.go_online(doc_a)
  sluice_js.settle(sluice)

  let seen_by_a = watershed_js.get(watershed_js.root(doc_a), "cell")
  seen_by_a
  |> expect.to_equal(watershed_js.get(watershed_js.root(doc_b), "cell"))
  seen_by_a |> option.is_some |> expect.to_be_true()
}

@target(javascript)
/// `go_offline` is only meaningful from a live connection, and `go_online` only
/// from a held one. Both are no-ops otherwise rather than errors, so a UI can
/// bind them to a toggle without tracking the phase itself.
pub fn the_offline_toggle_is_inert_outside_its_phase_test() {
  let sluice = sluice_js.start(tenant: "default", document: "offline-inert-js")
  let doc = sluice_js.connect(sluice, "user-a")
  sluice_js.settle(sluice)

  // Already online.
  watershed_js.go_online(doc)
  watershed_js.diagnostics(doc).phase |> expect.to_equal("ready")

  // Already offline.
  watershed_js.go_offline(doc)
  watershed_js.go_offline(doc)
  sluice_js.settle(sluice)
  watershed_js.diagnostics(doc).phase |> expect.to_equal("reconnecting")

  watershed_js.go_online(doc)
  sluice_js.settle(sluice)
  watershed_js.diagnostics(doc).phase |> expect.to_equal("ready")
}
