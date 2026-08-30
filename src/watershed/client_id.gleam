//// A stable, replicated mapping from the string id of a client to an integer.
//// The operational transform (OT) tie-break field `side` and the sequencing
//// metadata use that integer.
////
//// Two callers share this mapping. The runtime stamps `author` and `self` on
//// sequenced operations. The `channel` module seeds the `self` field of a
//// json0 kernel. Every replica must derive the same integer for a given
//// client, or the tie-break does not converge.

import gleam/int
import gleam/list
import gleam/string

/// Derive the integer id of a client. If the string has a numeric suffix after
/// the last `_`, use that suffix. Fluid client ids have the form
/// `<prefix>_<n>`. If there is no such suffix, use a stable hash of the whole
/// string.
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
  |> list.fold(216_613_626, fn(acc, codepoint) {
    let next =
      { acc * 16_777_619 + string.utf_codepoint_to_int(codepoint) }
      % 2_147_483_647
    case next < 0 {
      True -> 0 - next
      False -> next
    }
  })
}
