//// Optimistic edit lifecycle sample for `/runtime/optimistic`.
////
//// The snippet shows a local `set` followed by an immediate `get` that
//// reads back the pending value before the server has seen it. This is a
//// fixture: the `survey` map is assumed to exist; the module compiles but
//// is not wired to a transport.

import gleam/json
import gleam/result
import watershed

// docs:snippet-start optimistic-local
pub fn optimistic_edit(
  survey: watershed.SharedMap,
) -> Result(json.Json, String) {
  // set applies to your replica *now* — get reads it back before the
  // server has seen it. The UI never waits on the network.
  watershed.set(survey, "depth-07", json.float(3.4))
  use value <- result.try(
    watershed.get(survey, "depth-07")
    |> result.map_error(fn(_) { "Could not read the optimistic value" }),
  )
  // value == json.float(3.4), already visible. This value is *pending*:
  // drawn in magenta, a prediction of where the server's order will
  // place it.
  Ok(value)
}
// docs:snippet-end optimistic-local
