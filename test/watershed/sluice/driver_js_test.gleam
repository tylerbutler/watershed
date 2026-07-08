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
import gleam/option.{Some}
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
