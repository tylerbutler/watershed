//// A stable, replicated mapping from a client's string id to the integer the
//// OT tie-break (`side`) and sequencing metadata use. Shared by the runtime
//// (which stamps `author`/`self` on sequenced ops) and `channel` (which seeds
//// a json0 kernel's `self`) so every replica derives the same integer for a
//// given client — a prerequisite for convergent tie-breaking.

import gleam/int
import gleam/list
import gleam/string

/// Derive a client's integer id: the numeric suffix after the last `_` when
/// present (Fluid client ids are `<prefix>_<n>`), else a stable hash of the
/// whole string.
pub fn to_int(client_id: String) -> Int {
  case string.split(client_id, "_") |> list.last {
    Ok(raw) ->
      case int.parse(raw) {
        Ok(parsed) -> parsed
        Error(_) -> stable_hash(client_id)
      }
    Error(_) -> stable_hash(client_id)
  }
}

fn stable_hash(client_id: String) -> Int {
  string.to_utf_codepoints(client_id)
  |> list.fold(216_613_626, fn(acc, cp) {
    let next =
      { acc * 16_777_619 + string.utf_codepoint_to_int(cp) } % 2_147_483_647
    case next < 0 {
      True -> 0 - next
      False -> next
    }
  })
}
