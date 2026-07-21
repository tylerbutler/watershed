//// The playlist's element type.
////
//// A `SharedSequence` holds arbitrary `gleam/json` values, so the element
//// shape is the app's business, not the DDS's. Each track is a small object:
////
//// ```json
//// { "title": "Windowlicker", "artist": "Aphex Twin", "added_by": "web-4821" }
//// ```
////
//// Decoding is fallible on purpose: a peer running an older build (or a
//// hand-edited document) can leave a value here that doesn't match. The view
//// renders those as a placeholder row rather than crashing the app, and they
//// still reorder and delete correctly because those ops address by index.

import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}

pub type Track {
  Track(title: String, artist: String, added_by: String)
}

pub fn to_json(track: Track) -> Json {
  json.object([
    #("title", json.string(track.title)),
    #("artist", json.string(track.artist)),
    #("added_by", json.string(track.added_by)),
  ])
}

pub fn decoder() -> Decoder(Track) {
  use title <- decode.field("title", decode.string)
  use artist <- decode.field("artist", decode.string)
  use added_by <- decode.field("added_by", decode.string)
  decode.success(Track(title:, artist:, added_by:))
}

/// Decode a raw sequence value, falling back to a visible placeholder so one
/// malformed element can't take the list down.
pub fn from_json(value: Json) -> Track {
  case json.parse(json.to_string(value), decoder()) {
    Ok(track) -> track
    Error(_) -> Track(title: "(unreadable track)", artist: "—", added_by: "—")
  }
}
