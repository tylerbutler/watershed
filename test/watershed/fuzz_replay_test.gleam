//// Fuzz failure fixture replay (F4): every JSON file in
//// `test/fixtures/fuzz_failures/` — written by `kernel_fuzz.dump_failure`
//// whenever `run_script` fails — gets decoded and replayed here. A
//// captured failing script becomes a permanent regression test the moment
//// its fixture lands on disk, with no manual transcription into a new test
//// function.
////
//// Contract: a fixture's script must reproduce the *exact same* failure
//// detail it was captured with. That's the harness's answer to "kill a
//// run, re-run it, get an identical failure" — deterministic replay from
//// a saved script, independent of qcheck's (opaque, unprintable) seed.
//// If a fixture ever stops failing (the underlying bug got fixed), this
//// test fails loudly telling you to update or delete it, rather than
//// silently starting to pass.

import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import simplifile
import watershed/fuzz/claims_model
import watershed/fuzz/counter_model
import watershed/fuzz/kernel_fuzz.{type KernelModel}
import watershed/fuzz/kernel_fuzz_test
import watershed/fuzz/map_model
import watershed/fuzz/or_map_model
import watershed/fuzz/pn_counter_model

/// Replays one fixture file, returning `Error` with a human-readable
/// explanation on any decode problem or reproduction mismatch.
fn replay_fixture(path: String) -> Result(Nil, String) {
  use content <- result.try(
    simplifile.read(path)
    |> result.map_error(fn(_) { "could not read fixture " <> path }),
  )
  use model_name <- result.try(
    json.parse(content, decode.field("model", decode.string, decode.success))
    |> result.map_error(fn(_) {
      "could not decode \"model\" field in fixture " <> path
    }),
  )
  case model_name {
    "counter" -> replay_with(counter_model.model(), content, path)
    "map" -> replay_with(map_model.model(), content, path)
    "claims" -> replay_with(claims_model.model(), content, path)
    "pn_counter" -> replay_with(pn_counter_model.model(), content, path)
    "or_map" -> replay_with(or_map_model.model(), content, path)
    "toy-sum" ->
      replay_with(kernel_fuzz_test.sum_model_with_check(), content, path)
    other ->
      Error(
        "fixture " <> path <> " references unknown model \"" <> other <> "\"",
      )
  }
}

fn replay_with(
  model: KernelModel(state, op, view),
  content: String,
  path: String,
) -> Result(Nil, String) {
  let decoder = {
    use client_count <- decode.field("client_count", decode.int)
    use detail <- decode.field("detail", decode.string)
    use script <- decode.field(
      "script",
      kernel_fuzz.script_decoder(model.op_decoder),
    )
    decode.success(#(client_count, detail, script))
  }
  use #(client_count, expected_detail, script) <- result.try(
    json.parse(content, decoder)
    |> result.map_error(fn(_) {
      "could not decode client_count/detail/script in fixture " <> path
    }),
  )
  case kernel_fuzz.try_run_script(model, client_count, script) {
    Ok(Nil) ->
      Error(
        "fixture "
        <> path
        <> " no longer fails (recorded failure: "
        <> expected_detail
        <> "). If the underlying bug was fixed, delete or update this fixture.",
      )
    Error(detail) if detail == expected_detail -> Ok(Nil)
    Error(detail) ->
      Error(
        "fixture "
        <> path
        <> " reproduced a DIFFERENT failure than recorded.\nrecorded: "
        <> expected_detail
        <> "\nreplayed: "
        <> detail,
      )
  }
}

pub fn replays_every_saved_failure_fixture_test() {
  case simplifile.read_directory(kernel_fuzz.fixtures_dir) {
    // No fixtures yet is not a failure: the directory only gets populated
    // as real failures get captured.
    Error(_) -> Nil
    Ok(files) ->
      files
      |> list.filter(fn(f) { string.ends_with(f, ".json") })
      |> list.each(fn(f) {
        let path = kernel_fuzz.fixtures_dir <> "/" <> f
        case replay_fixture(path) {
          Ok(Nil) -> Nil
          Error(detail) -> panic as detail
        }
      })
  }
}
