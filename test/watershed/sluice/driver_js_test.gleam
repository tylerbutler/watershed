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
import watershed/sluice_js
@target(javascript)
import watershed_js

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
  ready.last_seen_sequence_number |> expect.to_equal(Some(0))
  ready.next_client_sequence_number |> expect.to_equal(Some(1))
  ready.in_flight_count |> expect.to_equal(0)
  ready.buffered_out_of_order_count |> expect.to_equal(0)
  ready.synced |> expect.to_be_true()

  watershed_js.set(watershed_js.root(doc), "k", json.int(1))
  let pending = watershed_js.diagnostics(doc)
  pending.last_seen_sequence_number |> expect.to_equal(Some(0))
  pending.next_client_sequence_number |> expect.to_equal(Some(2))
  pending.in_flight_count |> expect.to_equal(1)
  pending.synced |> expect.to_be_false()

  sluice_js.settle(sluice)
  let sequenced = watershed_js.diagnostics(doc)
  sequenced.last_seen_sequence_number |> expect.to_equal(Some(1))
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
  // The one op is broadcast to both clients: two op frames, SN 1, author a.
  ops |> list.length |> expect.to_equal(2)
  list.all(ops, fn(meta) { meta.0 == 1 }) |> expect.to_be_true()
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
