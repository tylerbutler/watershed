import gleam/list
import gleam/string
import gleeunit/should
import lustre/dev/query
import lustre/element
import watershed_site/sudoku/runtime
import watershed_site/sudoku/view

fn target(id: String) {
  query.element(query.attribute("data-testid", id))
}

pub fn static_view_preserves_the_no_javascript_fallback_test() {
  let html = view.static() |> element.to_string
  [
    "SharedMap sudoku cells, live",
    "Client A replica",
    "Client B replica",
    "Client C replica",
    "Race the same cell",
    "Place corner givens",
    "The live demo needs JavaScript",
    "data-testid=\"sudoku-fallback\"",
  ]
  |> list.each(fn(expected) {
    let assert True = string.contains(html, expected) as expected
  })
  view.static()
  |> query.find_all(query.element(query.class("sudoku-cell")))
  |> should.equal([])
}

pub fn ready_view_has_three_accessible_boards_test() {
  let assert Ok(rig) = runtime.start_rig()
  let model = runtime.update(runtime.init().0, runtime.Started(0, Ok(rig))).0
  let rendered = view.view(model, view.Options(False))
  rendered
  |> query.find_all(query.element(query.class("sudoku-cell")))
  |> list.length
  |> should.equal(243)
  let assert Ok(cell) = rendered |> query.find(target("cell-a-0-0"))
  let html = element.to_string(cell)
  string.contains(html, "role=\"gridcell\"") |> should.be_true()
  string.contains(
    html,
    "Client A row 1, column 1, empty. Type 1 through 9 to set; Delete clears.",
  )
  |> should.be_true()
}
