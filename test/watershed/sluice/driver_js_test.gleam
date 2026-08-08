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
    Ok(_) ->
      panic as "expected map handle resolution to fail for SharedSequence"
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
