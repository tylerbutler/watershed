//// The bracket's register value type.
////
//// A `RegisterCollection` holds arbitrary `gleam/json` values, so a match's
//// result crosses the wire as one JSON object with both fields, never one
//// field at a time — the two must always change together in a single
//// `register_write`, so there is no window where a winner is recorded
//// without a score or vice versa:
////
//// ```json
//// { "winner": "Beatrix", "score": "3-1" }
//// ```
////
//// Decoding is fallible on purpose: a peer running an older build can leave a
//// value here that doesn't match. Callers render those as a visible
//// placeholder rather than crashing.

import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}

import bracket.{type MatchResult, MatchResult}

pub fn to_json(result: MatchResult) -> Json {
  json.object([
    #("winner", json.string(result.winner)),
    #("score", json.string(result.score)),
  ])
}

pub fn decoder() -> Decoder(MatchResult) {
  use winner <- decode.field("winner", decode.string)
  use score <- decode.field("score", decode.string)
  decode.success(MatchResult(winner:, score:))
}

/// Decode a raw register value, falling back to a visible placeholder so one
/// malformed result can't take the bracket down.
pub fn from_json(value: Json) -> MatchResult {
  case json.parse(json.to_string(value), decoder()) {
    Ok(result) -> result
    Error(_) -> MatchResult(winner: "?", score: "(unreadable result)")
  }
}
