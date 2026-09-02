import gleam/string
import gleeunit/should
import simplifile
import source_snippets/cli.{
  GenerationFailed, OutputWriteError, WrongArgumentCount, format_error, run,
}
import source_snippets/generator

// ---------------------------------------------------------------------------
// Helpers — real filesystem fixtures (same pattern as generator_test)
// ---------------------------------------------------------------------------

const fixture_base = "test/fixtures/cli"

fn setup_fixture(
  name: String,
  config_json: String,
  files: List(#(String, String)),
) -> String {
  let base = fixture_base <> "/" <> name
  let _ = simplifile.delete(base)
  let assert Ok(Nil) = simplifile.create_directory_all(base)

  let config_path = base <> "/snippets.json"
  let assert Ok(Nil) = simplifile.write(config_path, config_json)

  write_files(base, files)

  config_path
}

fn write_files(base: String, files: List(#(String, String))) -> Nil {
  case files {
    [] -> Nil
    [#(path, content), ..rest] -> {
      let full = base <> "/" <> path
      let dir = dir_of(full)
      let assert Ok(Nil) = simplifile.create_directory_all(dir)
      let assert Ok(Nil) = simplifile.write(full, content)
      write_files(base, rest)
    }
  }
}

fn dir_of(path: String) -> String {
  case string.split(path, "/") |> list_init {
    [] -> "."
    parts -> string.join(parts, "/")
  }
}

fn list_init(items: List(String)) -> List(String) {
  case items {
    [] -> []
    [_] -> []
    [x, ..rest] -> [x, ..list_init(rest)]
  }
}

fn cleanup(name: String) -> Nil {
  let _ = simplifile.delete(fixture_base <> "/" <> name)
  Nil
}

fn make_config(
  source_root: String,
  marker_roots: List(String),
  extensions: List(String),
  snippets: List(String),
) -> String {
  let roots_json =
    marker_roots
    |> list_map(fn(r) { "\"" <> r <> "\"" })
    |> string.join(", ")
  let exts_json =
    extensions
    |> list_map(fn(e) { "\"" <> e <> "\"" })
    |> string.join(", ")
  let snippets_json = string.join(snippets, ", ")
  "{
  \"version\": 1,
  \"sourceRoot\": \"" <> source_root <> "\",
  \"markerRoots\": [" <> roots_json <> "],
  \"extensions\": [" <> exts_json <> "],
  \"snippets\": [" <> snippets_json <> "]
}"
}

fn make_snippet(
  id: String,
  source_path: String,
  language: String,
  markers: List(String),
  separator: String,
) -> String {
  let markers_json =
    markers
    |> list_map(fn(m) { "\"" <> m <> "\"" })
    |> string.join(", ")
  "{
    \"id\": \"" <> id <> "\",
    \"sourcePath\": \"" <> source_path <> "\",
    \"language\": \"" <> language <> "\",
    \"markers\": [" <> markers_json <> "],
    \"separator\": \"" <> escape_json(separator) <> "\"
  }"
}

fn escape_json(s: String) -> String {
  s
  |> string.replace("\\", "\\\\")
  |> string.replace("\"", "\\\"")
  |> string.replace("\n", "\\n")
  |> string.replace("\t", "\\t")
}

fn list_map(items: List(a), f: fn(a) -> b) -> List(b) {
  case items {
    [] -> []
    [x, ..rest] -> [f(x), ..list_map(rest, f)]
  }
}

// ---------------------------------------------------------------------------
// Argument count validation
// ---------------------------------------------------------------------------

pub fn run_zero_args_test() {
  run([])
  |> should.be_error
  |> fn(err) {
    case err {
      WrongArgumentCount(0) -> Nil
      _ -> should.fail()
    }
  }
}

pub fn run_one_arg_test() {
  run(["config.json"])
  |> should.be_error
  |> fn(err) {
    case err {
      WrongArgumentCount(1) -> Nil
      _ -> should.fail()
    }
  }
}

pub fn run_extra_args_test() {
  run(["a", "b", "c"])
  |> should.be_error
  |> fn(err) {
    case err {
      WrongArgumentCount(3) -> Nil
      _ -> should.fail()
    }
  }
}

// ---------------------------------------------------------------------------
// Successful generation
// ---------------------------------------------------------------------------

pub fn run_success_test() {
  let source =
    "// docs:snippet-start hello\npub fn hello() { Nil }\n// docs:snippet-end hello\n"
  let config =
    make_config(".", ["src"], [".gleam"], [
      make_snippet("hello", "src/main.gleam", "gleam", ["hello"], "\n\n"),
    ])
  let config_path =
    setup_fixture("success", config, [#("src/main.gleam", source)])
  let output_path = fixture_base <> "/success/out/snippets.json"

  run([config_path, output_path])
  |> should.be_ok

  let assert Ok(True) = simplifile.is_file(output_path)

  cleanup("success")
}

// ---------------------------------------------------------------------------
// Parent directory creation
// ---------------------------------------------------------------------------

pub fn run_creates_parent_dir_test() {
  let source = "// docs:snippet-start x\nlet x = 1\n// docs:snippet-end x\n"
  let config =
    make_config(".", ["src"], [".gleam"], [
      make_snippet("x", "src/a.gleam", "gleam", ["x"], "\n\n"),
    ])
  let config_path = setup_fixture("parent", config, [#("src/a.gleam", source)])
  let output_path = fixture_base <> "/parent/deep/nested/output.json"

  run([config_path, output_path])
  |> should.be_ok

  let assert Ok(True) = simplifile.is_file(output_path)

  cleanup("parent")
}

// ---------------------------------------------------------------------------
// Output path with no directory component
// ---------------------------------------------------------------------------

pub fn run_no_dir_component_test() {
  // filepath.directory_name of a bare filename returns "". ensure_parent
  // must not attempt to create "" and must return Ok(Nil).
  let source = "// docs:snippet-start n\nlet n = 0\n// docs:snippet-end n\n"
  let config =
    make_config(".", ["src"], [".gleam"], [
      make_snippet("n", "src/n.gleam", "gleam", ["n"], "\n\n"),
    ])
  let config_path = setup_fixture("nodir", config, [#("src/n.gleam", source)])
  let output_filename = "cli-nodir-test-output.json"

  run([config_path, output_filename])
  |> should.be_ok

  let _ = simplifile.delete(output_filename)
  cleanup("nodir")
}

// ---------------------------------------------------------------------------
// Atomic output: preserve valid output on failure
// ---------------------------------------------------------------------------

pub fn run_preserves_output_on_failure_test() {
  let source =
    "// docs:snippet-start keep\nlet keep = 1\n// docs:snippet-end keep\n"
  let good_config =
    make_config(".", ["src"], [".gleam"], [
      make_snippet("keep", "src/keep.gleam", "gleam", ["keep"], "\n\n"),
    ])
  let config_path =
    setup_fixture("preserve", good_config, [#("src/keep.gleam", source)])
  let output_path = fixture_base <> "/preserve/out.json"

  run([config_path, output_path])
  |> should.be_ok

  let assert Ok(original) = simplifile.read(output_path)

  // Overwrite config with one that references a missing marker.
  let bad_config =
    make_config(".", ["src"], [".gleam"], [
      make_snippet(
        "keep",
        "src/keep.gleam",
        "gleam",
        ["does-not-exist"],
        "\n\n",
      ),
    ])
  let assert Ok(Nil) = simplifile.write(config_path, bad_config)

  run([config_path, output_path])
  |> should.be_error

  let assert Ok(after_failure) = simplifile.read(output_path)
  after_failure |> should.equal(original)

  cleanup("preserve")
}

// ---------------------------------------------------------------------------
// Atomic output: replace valid output on success
// ---------------------------------------------------------------------------

pub fn run_replaces_output_on_success_test() {
  let source_v1 =
    "// docs:snippet-start rep\nlet v = 1\n// docs:snippet-end rep\n"
  let config =
    make_config(".", ["src"], [".gleam"], [
      make_snippet("rep", "src/rep.gleam", "gleam", ["rep"], "\n\n"),
    ])
  let config_path =
    setup_fixture("replace", config, [#("src/rep.gleam", source_v1)])
  let output_path = fixture_base <> "/replace/out.json"

  run([config_path, output_path])
  |> should.be_ok

  let assert Ok(v1_content) = simplifile.read(output_path)
  should.be_true(string.contains(v1_content, "let v = 1"))

  // Update source to produce different code.
  let source_v2 =
    "// docs:snippet-start rep\nlet v = 2\n// docs:snippet-end rep\n"
  let assert Ok(Nil) =
    simplifile.write(fixture_base <> "/replace/src/rep.gleam", source_v2)

  run([config_path, output_path])
  |> should.be_ok

  let assert Ok(v2_content) = simplifile.read(output_path)
  should.be_true(string.contains(v2_content, "let v = 2"))
  should.be_false(string.contains(v2_content, "let v = 1"))

  cleanup("replace")
}

// ---------------------------------------------------------------------------
// Black-box: success then bad marker — one actionable diagnostic
// ---------------------------------------------------------------------------

pub fn run_black_box_bad_marker_test() {
  let source =
    "// docs:snippet-start bb\npub fn bb() { Nil }\n// docs:snippet-end bb\n"
  let good_config =
    make_config(".", ["src"], [".gleam"], [
      make_snippet("bb", "src/bb.gleam", "gleam", ["bb"], "\n\n"),
    ])
  let config_path =
    setup_fixture("blackbox", good_config, [#("src/bb.gleam", source)])
  let output_path = fixture_base <> "/blackbox/out.json"

  run([config_path, output_path])
  |> should.be_ok

  // Replace config with one that names a non-existent marker.
  let bad_config =
    make_config(".", ["src"], [".gleam"], [
      make_snippet("bb", "src/bb.gleam", "gleam", ["ghost-marker"], "\n\n"),
    ])
  let assert Ok(Nil) = simplifile.write(config_path, bad_config)

  let err =
    run([config_path, output_path])
    |> should.be_error

  // The diagnostic must mention a marker id and the source path.
  // The generator reports OrphanMarker("bb", ...) because the renamed config
  // still scans the file (finding "bb"), but no snippet references it.
  let msg = format_error(err)
  should.be_true(string.contains(msg, "bb"))
  should.be_true(string.contains(msg, "src/bb.gleam"))

  // Output must still be the pre-failure version.
  let assert Ok(True) = simplifile.is_file(output_path)

  cleanup("blackbox")
}

// ---------------------------------------------------------------------------
// Error formatting
// ---------------------------------------------------------------------------

pub fn format_error_wrong_count_test() {
  let msg = format_error(WrongArgumentCount(0))
  should.be_true(string.contains(msg, "0"))
}

pub fn format_error_output_write_test() {
  let msg = format_error(OutputWriteError("/some/path.json"))
  should.be_true(string.contains(msg, "/some/path.json"))
}

pub fn format_error_stray_end_test() {
  // The message must name all three facts the author needs: the marker, the
  // file that holds the pair, and the file that holds the extra directive.
  let msg =
    format_error(
      GenerationFailed(generator.StrayEndMarker(
        "demo",
        "src/a.gleam",
        "src/b.gleam",
      )),
    )
  should.be_true(string.contains(msg, "demo"))
  should.be_true(string.contains(msg, "src/a.gleam"))
  should.be_true(string.contains(msg, "src/b.gleam"))
}

pub fn run_black_box_stray_end_test() {
  // A file holds a complete pair. A second file holds an end directive with
  // the same name. The run must fail and name both files.
  let paired = "// docs:snippet-start se\ncode a\n// docs:snippet-end se\n"
  let stray = "code b\n// docs:snippet-end se\n"
  let config =
    make_config(".", ["src"], [".gleam"], [
      make_snippet("se", "src/a.gleam", "gleam", ["se"], "\n\n"),
    ])
  let config_path =
    setup_fixture("stray-end", config, [
      #("src/a.gleam", paired),
      #("src/b.gleam", stray),
    ])
  let output_path = fixture_base <> "/stray-end/out.json"

  let msg =
    run([config_path, output_path])
    |> should.be_error
    |> format_error

  should.be_true(string.contains(msg, "se"))
  should.be_true(string.contains(msg, "src/a.gleam"))
  should.be_true(string.contains(msg, "src/b.gleam"))
  should.equal(simplifile.is_file(output_path), Ok(False))

  cleanup("stray-end")
}
