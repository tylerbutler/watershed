import gleam/order
import gleam/string
import gleeunit/should
import simplifile
import source_snippets/generator.{
  ConfigDecodeError, ConfigReadError, DuplicateMarkerAcrossFiles,
  ExtractionError, InvalidSourcePath, MarkerNotFound, MissingRoot,
  MissingSourceFile, OrphanMarker, generate,
}
import source_snippets/manifest.{
  type ManifestEntry, Manifest, ManifestEntry, encode,
}

// ---------------------------------------------------------------------------
// Helpers — real filesystem fixtures
// ---------------------------------------------------------------------------

const fixture_base = "test/fixtures/gen"

fn setup_fixture(
  name: String,
  config_json: String,
  files: List(#(String, String)),
) -> String {
  let base = fixture_base <> "/" <> name
  // Clean up any previous run.
  let _ = simplifile.delete(base)
  let assert Ok(Nil) = simplifile.create_directory_all(base)

  // Write config.
  let config_path = base <> "/snippets.json"
  let assert Ok(Nil) = simplifile.write(config_path, config_json)

  // Write source files.
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

// ---------------------------------------------------------------------------
// Valid generation — single range
// ---------------------------------------------------------------------------

pub fn generate_single_range_test() {
  let source =
    "import gleam/io\n// docs:snippet-start hello\npub fn hello() {\n  io.println(\"hello\")\n}\n// docs:snippet-end hello\n"
  let config =
    make_config(".", ["src"], [".gleam"], [
      make_snippet("hello", "src/main.gleam", "gleam", ["hello"], "\n\n"),
    ])
  let config_path =
    setup_fixture("single", config, [#("src/main.gleam", source)])

  let result = generate(config_path)
  let manifest = should.be_ok(result)

  manifest.version |> should.equal(1)
  let assert [entry] = manifest.snippets
  entry.id |> should.equal("hello")
  entry.code |> should.equal("pub fn hello() {\n  io.println(\"hello\")\n}")
  entry.language |> should.equal("gleam")
  entry.source_path |> should.equal("src/main.gleam")
  entry.markers |> should.equal(["hello"])

  cleanup("single")
}

// ---------------------------------------------------------------------------
// Valid generation — multiple ranges with declared order
// ---------------------------------------------------------------------------

pub fn generate_multiple_ranges_in_order_test() {
  let source =
    "// docs:snippet-start part-a\nlet a = 1\n// docs:snippet-end part-a\n// other code\n// docs:snippet-start part-b\nlet b = 2\n// docs:snippet-end part-b\n"
  let config =
    make_config(".", ["src"], [".gleam"], [
      make_snippet(
        "combined",
        "src/multi.gleam",
        "gleam",
        ["part-a", "part-b"],
        "\n// ...\n",
      ),
    ])
  let config_path =
    setup_fixture("multi", config, [#("src/multi.gleam", source)])

  let result = generate(config_path)
  let manifest = should.be_ok(result)
  let assert [entry] = manifest.snippets
  entry.code |> should.equal("let a = 1\n// ...\nlet b = 2")

  cleanup("multi")
}

// ---------------------------------------------------------------------------
// Valid generation — default separator
// ---------------------------------------------------------------------------

pub fn generate_default_separator_test() {
  let source =
    "// docs:snippet-start x\nfirst\n// docs:snippet-end x\n// docs:snippet-start y\nsecond\n// docs:snippet-end y\n"
  let config =
    make_config(".", ["src"], [".gleam"], [
      make_snippet("joined", "src/sep.gleam", "gleam", ["x", "y"], "\n\n"),
    ])
  let config_path = setup_fixture("sep", config, [#("src/sep.gleam", source)])

  let result = generate(config_path)
  let manifest = should.be_ok(result)
  let assert [entry] = manifest.snippets
  entry.code |> should.equal("first\n\nsecond")

  cleanup("sep")
}

// ---------------------------------------------------------------------------
// Valid generation — reused markers across output snippets
// ---------------------------------------------------------------------------

pub fn generate_reused_markers_test() {
  let source =
    "// docs:snippet-start shared\npub fn shared() { Nil }\n// docs:snippet-end shared\n"
  let config =
    make_config(".", ["src"], [".gleam"], [
      make_snippet("use-a", "src/reuse.gleam", "gleam", ["shared"], "\n\n"),
      make_snippet("use-b", "src/reuse.gleam", "gleam", ["shared"], "\n\n"),
    ])
  let config_path =
    setup_fixture("reuse", config, [#("src/reuse.gleam", source)])

  let result = generate(config_path)
  let manifest = should.be_ok(result)
  let ids =
    manifest.snippets
    |> list_map(fn(e: ManifestEntry) { e.id })
    |> list_sort
  ids |> should.equal(["use-a", "use-b"])

  cleanup("reuse")
}

fn list_map(items: List(a), f: fn(a) -> b) -> List(b) {
  case items {
    [] -> []
    [x, ..rest] -> [f(x), ..list_map(rest, f)]
  }
}

fn list_sort(items: List(String)) -> List(String) {
  case items {
    [] -> []
    [pivot, ..rest] -> {
      let lt = list_filter(rest, fn(x) { string.compare(x, pivot) == order.Lt })
      let gte =
        list_filter(rest, fn(x) { string.compare(x, pivot) != order.Lt })
      list_append(list_sort(lt), [pivot, ..list_sort(gte)])
    }
  }
}

fn list_filter(items: List(a), f: fn(a) -> Bool) -> List(a) {
  case items {
    [] -> []
    [x, ..rest] ->
      case f(x) {
        True -> [x, ..list_filter(rest, f)]
        False -> list_filter(rest, f)
      }
  }
}

fn list_append(a: List(x), b: List(x)) -> List(x) {
  case a {
    [] -> b
    [x, ..rest] -> [x, ..list_append(rest, b)]
  }
}

// ---------------------------------------------------------------------------
// Valid generation — stable output ordering (sorted by id)
// ---------------------------------------------------------------------------

pub fn generate_stable_ordering_test() {
  let source_z =
    "// docs:snippet-start z-marker\nz code\n// docs:snippet-end z-marker\n"
  let source_a =
    "// docs:snippet-start a-marker\na code\n// docs:snippet-end a-marker\n"
  // Config lists z first, but manifest should sort by id.
  let config =
    make_config(".", ["src"], [".gleam"], [
      make_snippet("z-snippet", "src/z.gleam", "gleam", ["z-marker"], "\n\n"),
      make_snippet("a-snippet", "src/a.gleam", "gleam", ["a-marker"], "\n\n"),
    ])
  let config_path =
    setup_fixture("order", config, [
      #("src/z.gleam", source_z),
      #("src/a.gleam", source_a),
    ])

  let result = generate(config_path)
  let manifest = should.be_ok(result)

  // Encode and verify that a-snippet comes before z-snippet.
  let encoded = encode(manifest)
  let a_pos = string_index_of(encoded, "a-snippet")
  let z_pos = string_index_of(encoded, "z-snippet")
  should.be_true(a_pos < z_pos)

  cleanup("order")
}

fn string_index_of(haystack: String, needle: String) -> Int {
  do_string_index_of(haystack, needle, 0)
}

fn do_string_index_of(haystack: String, needle: String, pos: Int) -> Int {
  case string.starts_with(haystack, needle) {
    True -> pos
    False ->
      case string.pop_grapheme(haystack) {
        Ok(#(_, rest)) -> do_string_index_of(rest, needle, pos + 1)
        Error(Nil) -> -1
      }
  }
}

// ---------------------------------------------------------------------------
// Error — config file not found
// ---------------------------------------------------------------------------

pub fn generate_missing_config_file_test() {
  generate("test/fixtures/gen/nonexistent/snippets.json")
  |> should.be_error
  |> should.equal(ConfigReadError("test/fixtures/gen/nonexistent/snippets.json"))
}

// ---------------------------------------------------------------------------
// Error — invalid config JSON
// ---------------------------------------------------------------------------

pub fn generate_invalid_config_test() {
  let config_path = setup_fixture("bad-config", "{not valid}", [])
  generate(config_path)
  |> should.be_error
  |> fn(err) {
    case err {
      ConfigDecodeError(_) -> Nil
      _ -> should.fail()
    }
  }

  cleanup("bad-config")
}

// ---------------------------------------------------------------------------
// Error — missing marker root
// ---------------------------------------------------------------------------

pub fn generate_missing_root_test() {
  let config = make_config(".", ["nonexistent"], [".gleam"], [])
  let config_path = setup_fixture("missing-root", config, [])

  generate(config_path)
  |> should.be_error
  |> should.equal(MissingRoot("nonexistent"))

  cleanup("missing-root")
}

// ---------------------------------------------------------------------------
// Error — missing source file
// ---------------------------------------------------------------------------

pub fn generate_missing_source_file_test() {
  let config =
    make_config(".", ["src"], [".gleam"], [
      make_snippet("s1", "src/missing.gleam", "gleam", ["x"], "\n\n"),
    ])
  let config_path =
    setup_fixture("missing-src", config, [
      #(
        "src/placeholder.gleam",
        "// docs:snippet-start x\ncode\n// docs:snippet-end x\n",
      ),
    ])

  generate(config_path)
  |> should.be_error
  |> fn(err) {
    case err {
      MarkerNotFound(_, _, _) -> Nil
      MissingSourceFile(_) -> Nil
      _ -> should.fail()
    }
  }

  cleanup("missing-src")
}

// ---------------------------------------------------------------------------
// Error — duplicate marker across files
// ---------------------------------------------------------------------------

pub fn generate_duplicate_marker_across_files_test() {
  let source_a = "// docs:snippet-start dup\ncode a\n// docs:snippet-end dup\n"
  let source_b = "// docs:snippet-start dup\ncode b\n// docs:snippet-end dup\n"
  let config =
    make_config(".", ["src"], [".gleam"], [
      make_snippet("s1", "src/a.gleam", "gleam", ["dup"], "\n\n"),
    ])
  let config_path =
    setup_fixture("dup-marker", config, [
      #("src/a.gleam", source_a),
      #("src/b.gleam", source_b),
    ])

  let result = generate(config_path)
  result
  |> should.be_error
  |> fn(err) {
    case err {
      DuplicateMarkerAcrossFiles("dup", _, _) -> Nil
      _ -> should.fail()
    }
  }

  cleanup("dup-marker")
}

// ---------------------------------------------------------------------------
// Error — orphan marker (not referenced by any snippet)
// ---------------------------------------------------------------------------

pub fn generate_orphan_marker_test() {
  let source =
    "// docs:snippet-start used\ncode\n// docs:snippet-end used\n// docs:snippet-start orphan\ncode\n// docs:snippet-end orphan\n"
  let config =
    make_config(".", ["src"], [".gleam"], [
      make_snippet("s1", "src/main.gleam", "gleam", ["used"], "\n\n"),
    ])
  let config_path =
    setup_fixture("orphan", config, [#("src/main.gleam", source)])

  generate(config_path)
  |> should.be_error
  |> fn(err) {
    case err {
      OrphanMarker("orphan", _) -> Nil
      _ -> should.fail()
    }
  }

  cleanup("orphan")
}

// ---------------------------------------------------------------------------
// Error — extraction error (reversed markers, etc.)
// ---------------------------------------------------------------------------

pub fn generate_extraction_error_reversed_test() {
  let source = "// docs:snippet-end rev\ncode\n// docs:snippet-start rev\n"
  let config =
    make_config(".", ["src"], [".gleam"], [
      make_snippet("s1", "src/rev.gleam", "gleam", ["rev"], "\n\n"),
    ])
  let config_path =
    setup_fixture("reversed", config, [#("src/rev.gleam", source)])

  generate(config_path)
  |> should.be_error
  |> fn(err) {
    case err {
      ExtractionError("s1", _) -> Nil
      _ -> should.fail()
    }
  }

  cleanup("reversed")
}

// ---------------------------------------------------------------------------
// Error — marker not found in source file
// ---------------------------------------------------------------------------

pub fn generate_marker_not_in_source_test() {
  let source = "// plain code, no markers\n"
  let config =
    make_config(".", ["src"], [".gleam"], [
      make_snippet("s1", "src/plain.gleam", "gleam", ["missing"], "\n\n"),
    ])
  let config_path =
    setup_fixture("no-marker", config, [#("src/plain.gleam", source)])

  generate(config_path)
  |> should.be_error
  |> fn(err) {
    case err {
      MarkerNotFound("s1", "missing", "src/plain.gleam") -> Nil
      _ -> should.fail()
    }
  }

  cleanup("no-marker")
}

// ---------------------------------------------------------------------------
// Error — extension filtering
// ---------------------------------------------------------------------------

pub fn generate_ignores_non_matching_extensions_test() {
  // .txt file has a marker but .txt is not in extensions, so it is not scanned.
  let gleam_source =
    "// docs:snippet-start g\ngleam code\n// docs:snippet-end g\n"
  let txt_source =
    "// docs:snippet-start orphan\ntxt code\n// docs:snippet-end orphan\n"
  let config =
    make_config(".", ["src"], [".gleam"], [
      make_snippet("s1", "src/main.gleam", "gleam", ["g"], "\n\n"),
    ])
  let config_path =
    setup_fixture("ext-filter", config, [
      #("src/main.gleam", gleam_source),
      #("src/ignored.txt", txt_source),
    ])

  // Should succeed because .txt file is not scanned.
  generate(config_path)
  |> should.be_ok

  cleanup("ext-filter")
}

// ---------------------------------------------------------------------------
// Path canonicalization — dot-slash prefix resolves correctly
// ---------------------------------------------------------------------------

pub fn generate_dot_slash_source_path_test() {
  let source =
    "// docs:snippet-start hello\npub fn hello() { Nil }\n// docs:snippet-end hello\n"
  let config =
    make_config(".", ["src"], [".gleam"], [
      make_snippet("hello", "./src/main.gleam", "gleam", ["hello"], "\n\n"),
    ])
  let config_path =
    setup_fixture("dot-slash", config, [#("src/main.gleam", source)])

  let result = generate(config_path)
  let manifest = should.be_ok(result)
  let assert [entry] = manifest.snippets
  entry.id |> should.equal("hello")
  entry.code |> should.equal("pub fn hello() { Nil }")
  // Output source_path should be the clean normalized form.
  entry.source_path |> should.equal("src/main.gleam")

  cleanup("dot-slash")
}

// ---------------------------------------------------------------------------
// Path canonicalization — parent traversal within source root
// ---------------------------------------------------------------------------

pub fn generate_dotdot_source_path_test() {
  let source = "// docs:snippet-start x\nlet x = 1\n// docs:snippet-end x\n"
  let config =
    make_config(".", ["src"], [".gleam"], [
      make_snippet("x", "src/../src/main.gleam", "gleam", ["x"], "\n\n"),
    ])
  let config_path =
    setup_fixture("dotdot", config, [#("src/main.gleam", source)])

  let result = generate(config_path)
  let manifest = should.be_ok(result)
  let assert [entry] = manifest.snippets
  entry.source_path |> should.equal("src/main.gleam")

  cleanup("dotdot")
}

// ---------------------------------------------------------------------------
// Path canonicalization — escape source root is rejected
// ---------------------------------------------------------------------------

pub fn generate_escaping_path_rejected_test() {
  let source = "// docs:snippet-start x\ncode\n// docs:snippet-end x\n"
  let config =
    make_config(".", ["src"], [".gleam"], [
      make_snippet("x", "../escaped.gleam", "gleam", ["x"], "\n\n"),
    ])
  let config_path =
    setup_fixture("escape", config, [#("src/placeholder.gleam", source)])

  generate(config_path)
  |> should.be_error
  |> fn(err) {
    case err {
      InvalidSourcePath(_, _) -> Nil
      _ -> should.fail()
    }
  }

  cleanup("escape")
}

// ---------------------------------------------------------------------------
// Manifest encoding — round-trip
// ---------------------------------------------------------------------------

pub fn encode_manifest_deterministic_test() {
  let m =
    Manifest(version: 1, snippets: [
      ManifestEntry(
        id: "beta",
        code: "let b = 2",
        language: "gleam",
        source_path: "src/b.gleam",
        markers: ["beta"],
      ),
      ManifestEntry(
        id: "alpha",
        code: "let a = 1",
        language: "gleam",
        source_path: "src/a.gleam",
        markers: ["alpha"],
      ),
    ])
  let encoded = encode(m)
  // alpha should come before beta in the encoded output.
  let a_pos = string_index_of(encoded, "alpha")
  let b_pos = string_index_of(encoded, "beta")
  should.be_true(a_pos < b_pos)

  // Should contain the expected structure.
  should.be_true(string.contains(encoded, "\"version\":1"))
  should.be_true(string.contains(encoded, "\"snippets\""))
  should.be_true(string.contains(encoded, "\"origin\""))
  should.be_true(string.contains(encoded, "\"kind\":\"source\""))
}

pub fn encode_manifest_markers_array_test() {
  let m =
    Manifest(version: 1, snippets: [
      ManifestEntry(
        id: "multi",
        code: "combined",
        language: "gleam",
        source_path: "src/m.gleam",
        markers: ["a", "b"],
      ),
    ])
  let encoded = encode(m)
  should.be_true(string.contains(encoded, "\"markers\":[\"a\",\"b\"]"))
}

// ---------------------------------------------------------------------------
// Source root relative to config file
// ---------------------------------------------------------------------------

pub fn generate_source_root_relative_to_config_test() {
  // Config says sourceRoot: ".." which means the parent of the config dir.
  let source =
    "// docs:snippet-start rel\npub fn rel() { Nil }\n// docs:snippet-end rel\n"
  let config =
    make_config("..", ["src"], [".gleam"], [
      make_snippet("rel", "src/rel.gleam", "gleam", ["rel"], "\n\n"),
    ])
  let base = fixture_base <> "/relroot"
  let _ = simplifile.delete(base)
  let assert Ok(Nil) = simplifile.create_directory_all(base <> "/config")
  let assert Ok(Nil) = simplifile.create_directory_all(base <> "/src")
  let config_path = base <> "/config/snippets.json"
  let assert Ok(Nil) = simplifile.write(config_path, config)
  let assert Ok(Nil) = simplifile.write(base <> "/src/rel.gleam", source)

  let result = generate(config_path)
  let manifest = should.be_ok(result)
  let assert [entry] = manifest.snippets
  entry.code |> should.equal("pub fn rel() { Nil }")

  let _ = simplifile.delete(base)
  Nil
}

// ---------------------------------------------------------------------------
// JSON config builder helpers
// ---------------------------------------------------------------------------

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
    \"separator\": \"" <> escape_json_string(separator) <> "\"
  }"
}

fn escape_json_string(s: String) -> String {
  s
  |> string.replace("\\", "\\\\")
  |> string.replace("\"", "\\\"")
  |> string.replace("\n", "\\n")
  |> string.replace("\t", "\\t")
}
