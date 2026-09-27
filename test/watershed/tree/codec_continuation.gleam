//// Replays source-authored continuation messages through the native codec.

import envoy
import gleam/json
import gleam/string
import simplifile
import watershed/tree/codec_export

pub fn main() {
  let artifact_path = case envoy.get("WATERSHED_TREE_CODEC_INPUT") {
    Ok(value) -> value
    Error(_) -> panic as "WATERSHED_TREE_CODEC_INPUT is required"
  }
  let consumer_path = case envoy.get("WATERSHED_TREE_CODEC_CONSUMER") {
    Ok(value) -> value
    Error(_) -> panic as "WATERSHED_TREE_CODEC_CONSUMER is required"
  }
  let output_path = case envoy.get("WATERSHED_TREE_CODEC_CONTINUATION_OUTPUT") {
    Ok(value) -> value
    Error(_) -> panic as "WATERSHED_TREE_CODEC_CONTINUATION_OUTPUT is required"
  }
  let artifact = case simplifile.read(artifact_path) {
    Ok(value) -> value
    Error(error) -> panic as { string.inspect(error) }
  }
  let consumer = case simplifile.read(consumer_path) {
    Ok(value) -> value
    Error(error) -> panic as { string.inspect(error) }
  }
  let output = case codec_export.replay_array_continuation(artifact, consumer) {
    Ok(value) -> value
    Error(error) -> panic as { error }
  }
  case simplifile.write(output_path, json.to_string(output) <> "\n") {
    Ok(_) -> Nil
    Error(error) -> panic as { string.inspect(error) }
  }
}
