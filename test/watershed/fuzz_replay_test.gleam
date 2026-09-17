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
import gleam/option.{Some}
import gleam/result
import gleam/string
import lattice_core/replica_id
import lattice_registers/lww_register
import qcheck
import simplifile
import startest/expect
import watershed/fuzz/claims_model
import watershed/fuzz/counter_model
import watershed/fuzz/directory_model
import watershed/fuzz/g_counter_model
import watershed/fuzz/kernel_fuzz.{type KernelModel}
import watershed/fuzz/kernel_fuzz_test
import watershed/fuzz/lww_map_model
import watershed/fuzz/lww_register_model
import watershed/fuzz/map_model
import watershed/fuzz/or_map_model
import watershed/fuzz/or_map_set_model
import watershed/fuzz/pn_counter_model
import watershed/fuzz/text_model
import watershed/or_map_set_fuzz_test

/// Replays one fixture file, returning `Error` with a human-readable
/// explanation on any decode problem or reproduction mismatch.
fn replay_fixture(path: String) -> Result(Nil, String) {
  use content <- result.try(
    simplifile.read(path)
    |> result.map_error(fn(_) { "could not read fixture " <> path }),
  )
  replay_content(content, path)
}

fn replay_content(content: String, path: String) -> Result(Nil, String) {
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
    "g_counter" -> replay_with(g_counter_model.model(), content, path)
    "lww_map" -> replay_with(lww_map_model.model(), content, path)
    "lww_register" -> replay_with(lww_register_model.model(), content, path)
    "pn_counter" -> replay_with(pn_counter_model.model(), content, path)
    "or_map" -> replay_with(or_map_model.model(), content, path)
    "or_map_set" -> replay_with(or_map_set_model.model(), content, path)
    "directory" -> replay_with(directory_model.model(), content, path)
    "text" -> replay_with(text_model.model(), content, path)
    "toy-sum" ->
      replay_with(kernel_fuzz_test.sum_model_with_check(), content, path)
    other ->
      Error(
        "fixture " <> path <> " references unknown model \"" <> other <> "\"",
      )
  }
}

fn replay_with(
  model: KernelModel(state, operation, view),
  content: String,
  path: String,
) -> Result(Nil, String) {
  let decoder = {
    use client_count <- decode.field("client_count", decode.int)
    use detail <- decode.field("detail", decode.string)
    use script <- decode.field(
      "script",
      kernel_fuzz.script_decoder(model.operation_decoder),
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

pub fn lww_register_failure_fixture_replays_test() -> Nil {
  let model = lww_register_model.model()
  let script = [
    kernel_fuzz.StashedOperation(
      1,
      lww_register_model.LwwCommand(
        "ready",
        7,
        Some(7),
        Some(lww_register.new("ready", 7, replica_id.new("wrong-author"))),
      ),
    ),
    kernel_fuzz.Synchronize,
  ]
  let assert Error(detail) = kernel_fuzz.try_run_script(model, 3, script)
  let content =
    json.object([
      #("model", json.string("lww_register")),
      #("client_count", json.int(3)),
      #("detail", json.string(detail)),
      #("script", kernel_fuzz.script_to_json(model.operation_to_json, script)),
    ])
    |> json.to_string
  replay_content(content, "in-memory LWW-register fixture")
  |> expect.to_equal(Ok(Nil))
}

pub fn or_map_set_failure_fixture_replays_test() -> Nil {
  let model = or_map_set_model.model()
  let script = [
    kernel_fuzz.StashedOperation(
      1,
      or_map_set_fuzz_test.shared_leaf_author_command(),
    ),
    kernel_fuzz.Synchronize,
  ]
  let assert Error(detail) = kernel_fuzz.try_run_script(model, 3, script)
  let content =
    json.object([
      #("model", json.string(model.name)),
      #("client_count", json.int(3)),
      #("detail", json.string(detail)),
      #("script", kernel_fuzz.script_to_json(model.operation_to_json, script)),
    ])
    |> json.to_string
  replay_content(content, "in-memory set-map fixture")
  |> expect.to_equal(Ok(Nil))
}

pub fn or_map_set_generated_failure_fixture_replays_test() -> Nil {
  let model = or_map_set_model.model()
  qcheck.run(
    qcheck.default_config() |> qcheck.with_test_count(20),
    model.gen_operation,
    fn(original) {
      let assert Some(context) = original.context
      let faulty =
        or_map_set_model.SetMapCommand(
          ..original,
          context: Some(
            or_map_set_model.Context(..context, counter: context.counter + 1),
          ),
        )
      let script = [
        kernel_fuzz.StashedOperation(1, faulty),
        kernel_fuzz.Synchronize,
      ]
      let assert Error(detail) = kernel_fuzz.try_run_script(model, 3, script)
      let content =
        json.object([
          #("model", json.string(model.name)),
          #("client_count", json.int(3)),
          #("detail", json.string(detail)),
          #(
            "script",
            kernel_fuzz.script_to_json(model.operation_to_json, script),
          ),
        ])
        |> json.to_string
      replay_content(content, "generated captured set-map fixture")
      |> expect.to_equal(Ok(Nil))
    },
  )
}

pub fn lww_map_fixed_fixture_is_recognized_test() -> Nil {
  let content =
    "{\"model\":\"lww_map\",\"client_count\":3,\"detail\":\"old failure\",\"script\":[]}"
  let assert Error(detail) =
    replay_content(content, "in-memory LWW-map fixture")
  string.contains(detail, "no longer fails") |> expect.to_be_true()
}

pub fn replays_every_saved_failure_fixture_test() -> Nil {
  case simplifile.read_directory(kernel_fuzz.fixtures_directory) {
    // No fixtures yet is not a failure: the directory only gets populated
    // as real failures get captured.
    Error(_) -> Nil
    Ok(files) ->
      files
      |> list.filter(fn(f) { string.ends_with(f, ".json") })
      |> list.each(fn(f) {
        let path = kernel_fuzz.fixtures_directory <> "/" <> f
        case replay_fixture(path) {
          Ok(Nil) -> Nil
          Error(detail) -> panic as detail
        }
      })
  }
}
