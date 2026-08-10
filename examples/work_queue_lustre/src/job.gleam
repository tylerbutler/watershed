//// The queue's element type.
////
//// Jobs are self-contained payloads in the queue, not references into a side
//// map — a second channel of job metadata would add nothing but an atomicity
//// problem. An `OrderedCollection` holds arbitrary `gleam/json` values, so the
//// shape is the app's business:
////
//// ```json
//// { "id": "web-4821-3", "label": "transcode video #3", "created_by": "web-4821" }
//// ```
////
//// Decoding is fallible on purpose: a peer running an older build can leave a
//// value here that doesn't match. The board renders those as a placeholder
//// card rather than crashing.

import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}

pub type Job {
  Job(id: String, label: String, created_by: String)
}

pub fn to_json(job: Job) -> Json {
  json.object([
    #("id", json.string(job.id)),
    #("label", json.string(job.label)),
    #("created_by", json.string(job.created_by)),
  ])
}

pub fn decoder() -> Decoder(Job) {
  use id <- decode.field("id", decode.string)
  use label <- decode.field("label", decode.string)
  use created_by <- decode.field("created_by", decode.string)
  decode.success(Job(id:, label:, created_by:))
}

/// Decode a raw queue value, falling back to a visible placeholder so one
/// malformed element can't take the board down.
pub fn from_json(value: Json) -> Job {
  case json.parse(json.to_string(value), decoder()) {
    Ok(job) -> job
    Error(_) -> Job(id: "?", label: "(unreadable job)", created_by: "—")
  }
}
