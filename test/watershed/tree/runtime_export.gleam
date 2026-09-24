//// Exports native core operations and replays server-delivered messages.

import envoy
import gleam/json
import gleam/string
import simplifile
import watershed/tree/runtime_fixture
import watershed/wire

pub fn main() {
  let input_path = case envoy.get("WATERSHED_TREE_RUNTIME_INPUT") {
    Ok(path) -> path
    Error(_) -> panic as "WATERSHED_TREE_RUNTIME_INPUT is required"
  }
  let output_path = case envoy.get("WATERSHED_TREE_RUNTIME_OUTPUT") {
    Ok(path) -> path
    Error(_) -> panic as "WATERSHED_TREE_RUNTIME_OUTPUT is required"
  }
  let target = case envoy.get("WATERSHED_TREE_RUNTIME_TARGET") {
    Ok("erlang" as value) | Ok("javascript" as value) -> value
    _ -> panic as "WATERSHED_TREE_RUNTIME_TARGET must be erlang or javascript"
  }
  let artifact = case simplifile.read(input_path) {
    Ok(raw) ->
      case json.parse(raw, wire.json_value_decoder()) {
        Ok(input) ->
          case runtime_fixture.export_runtime(input) {
            Ok(output) -> output
            Error(detail) -> panic as { "native runtime export: " <> detail }
          }
        Error(error) ->
          panic as { "invalid native runtime input: " <> string.inspect(error) }
      }
    Error(error) ->
      panic as {
        "could not read native runtime input: " <> string.inspect(error)
      }
  }
  let artifact =
    json.object([
      #("target", json.string(target)),
      #(
        "reference",
        json.object([
          #("package", json.string("@fluidframework/tree")),
          #("version", json.string("3.1.0")),
          #("commit", json.string("c3c5bf0ecd313362e83fe8a02b7d39e7e0736960")),
        ]),
      ),
      #("artifact", artifact),
    ])
  case simplifile.write(output_path, json.to_string(artifact) <> "\n") {
    Ok(_) -> Nil
    Error(error) ->
      panic as {
        "could not write native runtime output: " <> string.inspect(error)
      }
  }
}
