//// A real app-package convergence test (plan HM4): two browser clients edit
//// the same document and converge — with no levee server, driven entirely by
//// the in-memory `sluice_js`. This is the state of the art the sluice replaces:
//// the examples used to verify by hand in two browser tabs.
////
//// It runs under `gleam test` on the JavaScript target because delivery is
//// explicit and synchronous — `settle` drains every queued frame before the
//// assertions read the converged state.

import gleam/json
import gleam/list
import gleam/option.{Some}
import gleam/string
import gleeunit/should

import watershed/sluice_js
import watershed_js

fn same_entries(
  a: List(#(String, json.Json)),
  b: List(#(String, json.Json)),
) -> Bool {
  let normalize = fn(entries: List(#(String, json.Json))) {
    entries
    |> list.map(fn(entry) { #(entry.0, json.to_string(entry.1)) })
    |> list.sort(fn(x, y) { string.compare(x.0, y.0) })
  }
  normalize(a) == normalize(b)
}

pub fn two_clients_converge_on_a_shared_map_test() {
  let sluice = sluice_js.start(tenant: "default", document: "sudoku-conv")
  let doc_a = sluice_js.connect(sluice, "user-a")
  let doc_b = sluice_js.connect(sluice, "user-b")
  // Complete both handshakes before editing.
  sluice_js.settle(sluice)

  let board_a = watershed_js.root(doc_a)
  let board_b = watershed_js.root(doc_b)

  // Two players fill cells concurrently, including a same-cell race.
  watershed_js.set(board_a, "r0c0", json.int(5))
  watershed_js.set(board_b, "r1c1", json.int(3))
  watershed_js.set(board_a, "r4c4", json.string("a"))
  watershed_js.set(board_b, "r4c4", json.string("b"))
  sluice_js.settle(sluice)

  // Deterministically converged — no polling, no server.
  watershed_js.get(board_a, "r0c0") |> should.equal(Some(json.int(5)))
  watershed_js.get(board_b, "r1c1") |> should.equal(Some(json.int(3)))
  // Both players see the same winner for the contested cell.
  watershed_js.get(board_a, "r4c4")
  |> should.equal(watershed_js.get(board_b, "r4c4"))
  same_entries(watershed_js.entries(board_a), watershed_js.entries(board_b))
  |> should.be_true

  // A third player joining later replays history to the same board.
  let doc_c = sluice_js.connect(sluice, "user-c")
  sluice_js.settle(sluice)
  same_entries(
    watershed_js.entries(watershed_js.root(doc_c)),
    watershed_js.entries(board_a),
  )
  |> should.be_true
}
