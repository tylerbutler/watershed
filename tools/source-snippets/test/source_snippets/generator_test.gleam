import gleam/option
import gleam/order
import gleam/string
import gleeunit/should
import simplifile
import source_snippets/extractor
import source_snippets/generator.{
  ConfigDecodeError, ConfigReadError, DuplicateMarkerAcrossFiles,
  ExtractionError, InvalidSourcePath, MarkerNotFound, MissingRoot,
  MissingSourceFile, OrphanMarker, generate,
}
import source_snippets/manifest.{
  type ManifestEntry, FileOrigin, Manifest, ManifestEntry, MarkerOrigin, encode,
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
  entry.origin |> should.equal(MarkerOrigin(["hello"]))

  cleanup("single")
}

// ---------------------------------------------------------------------------
// Valid generation — whole file
// ---------------------------------------------------------------------------

/// A module whose head comment sits above a marked range.
///
/// The formatter puts a blank line on each side of a directive line that
/// stands between two items. The fixture has the same shape as a formatted
/// module, so the test proves the seam collapses to one blank line.
const whole_file_source = "//// Module documentation.
////
//// A second line of module documentation.

import gleam/io

// docs:snippet-start greet
/// Prints a greeting.
pub fn greet() {
  io.println(\"hello\")
}

// docs:snippet-end greet

pub fn other() {
  Nil
}
"

const whole_file_expected = "//// Module documentation.
////
//// A second line of module documentation.

import gleam/io

/// Prints a greeting.
pub fn greet() {
  io.println(\"hello\")
}

pub fn other() {
  Nil
}
"

pub fn generate_whole_file_test() {
  let config =
    make_config(".", ["src"], [".gleam"], [
      make_whole_file_snippet("listing", "src/main.gleam", "gleam"),
      make_snippet("greet", "src/main.gleam", "gleam", ["greet"], "\n\n"),
    ])
  let config_path =
    setup_fixture("wholefile", config, [#("src/main.gleam", whole_file_source)])

  let manifest = should.be_ok(generate(config_path))

  let assert Ok(listing) = find_entry(manifest.snippets, "listing")
  listing.code |> should.equal(whole_file_expected)
  listing.language |> should.equal("gleam")
  listing.source_path |> should.equal("src/main.gleam")
  listing.origin |> should.equal(FileOrigin)

  // The marked range in the same file still generates from its markers.
  let assert Ok(greet) = find_entry(manifest.snippets, "greet")
  greet.code
  |> should.equal(
    "/// Prints a greeting.\npub fn greet() {\n  io.println(\"hello\")\n}",
  )
  greet.origin |> should.equal(MarkerOrigin(["greet"]))

  cleanup("wholefile")
}

pub fn generate_whole_file_keeps_module_documentation_test() {
  let config =
    make_config(".", ["src"], [".gleam"], [
      make_whole_file_snippet("listing", "src/main.gleam", "gleam"),
      make_snippet("greet", "src/main.gleam", "gleam", ["greet"], "\n\n"),
    ])
  let config_path =
    setup_fixture("wholedocs", config, [#("src/main.gleam", whole_file_source)])

  let manifest = should.be_ok(generate(config_path))
  let assert Ok(listing) = find_entry(manifest.snippets, "listing")

  string.starts_with(listing.code, "//// Module documentation.")
  |> should.be_true
  string.contains(listing.code, "docs:snippet-") |> should.be_false

  cleanup("wholedocs")
}

/// A whole-file snippet is not a marker reference.
///
/// The whole file holds the marker pair, but no snippet names it. The
/// generator must report the orphan instead of counting the file listing
/// as a reference.
pub fn generate_whole_file_does_not_reference_markers_test() {
  let config =
    make_config(".", ["src"], [".gleam"], [
      make_whole_file_snippet("listing", "src/main.gleam", "gleam"),
    ])
  let config_path =
    setup_fixture("wholeorphan", config, [
      #("src/main.gleam", whole_file_source),
    ])

  generate(config_path)
  |> should.be_error
  |> should.equal(OrphanMarker("greet", "src/main.gleam"))

  cleanup("wholeorphan")
}

pub fn generate_whole_file_missing_source_test() {
  let config =
    make_config(".", ["src"], [".gleam"], [
      make_whole_file_snippet("listing", "src/gone.gleam", "gleam"),
    ])
  let config_path =
    setup_fixture("wholemissing", config, [#("src/main.gleam", "let a = 1\n")])

  generate(config_path)
  |> should.be_error
  |> should.equal(MissingSourceFile("src/gone.gleam"))

  cleanup("wholemissing")
}

fn find_entry(
  entries: List(ManifestEntry),
  id: String,
) -> Result(ManifestEntry, Nil) {
  case entries {
    [] -> Error(Nil)
    [entry, ..rest] ->
      case entry.id == id {
        True -> Ok(entry)
        False -> find_entry(rest, id)
      }
  }
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
// Scanner exclusions
//
// A broad marker root reaches the generated build directory, where the
// compiler keeps copies of the same source. The copies carry the same marker
// names, so the scan must skip the excluded directories by name.
// ---------------------------------------------------------------------------

const excluded_dir_files = [
  #(
    "src/main.gleam",
    "// docs:snippet-start hello\ncode\n// docs:snippet-end hello\n",
  ),
  #(
    "src/build/dev/copy.gleam",
    "// docs:snippet-start hello\ncode\n// docs:snippet-end hello\n",
  ),
]

pub fn generate_without_exclusions_sees_build_copy_test() {
  let config =
    make_config(".", ["src"], [".gleam"], [
      make_snippet("s1", "src/main.gleam", "gleam", ["hello"], "\n\n"),
    ])
  let config_path = setup_fixture("no-exclusions", config, excluded_dir_files)

  generate(config_path)
  |> should.be_error
  |> fn(err) {
    case err {
      DuplicateMarkerAcrossFiles("hello", _, _) -> Nil
      _ -> should.fail()
    }
  }

  cleanup("no-exclusions")
}

pub fn generate_skips_excluded_directories_test() {
  let config =
    make_config_with_exclusions(".", ["src"], [".gleam"], ["build"], [
      make_snippet("s1", "src/main.gleam", "gleam", ["hello"], "\n\n"),
    ])
  let config_path = setup_fixture("exclusions", config, excluded_dir_files)

  let manifest = should.be_ok(generate(config_path))
  let assert [entry] = manifest.snippets
  entry.source_path |> should.equal("src/main.gleam")

  cleanup("exclusions")
}

pub fn generate_exclusion_matches_directory_name_only_test() {
  // A file named `build.gleam` is not a `build` directory, so the scan keeps
  // it and reports its unreferenced marker.
  let config =
    make_config_with_exclusions(".", ["src"], [".gleam"], ["build"], [
      make_snippet("s1", "src/main.gleam", "gleam", ["hello"], "\n\n"),
    ])
  let config_path =
    setup_fixture("exclusion-name", config, [
      #(
        "src/main.gleam",
        "// docs:snippet-start hello\ncode\n// docs:snippet-end hello\n",
      ),
      #(
        "src/build.gleam",
        "// docs:snippet-start stray\ncode\n// docs:snippet-end stray\n",
      ),
    ])

  generate(config_path)
  |> should.be_error
  |> fn(err) {
    case err {
      OrphanMarker("stray", "src/build.gleam") -> Nil
      _ -> should.fail()
    }
  }

  cleanup("exclusion-name")
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

pub fn generate_split_marker_across_files_test() {
  let source_a = "// docs:snippet-start split\ncode a\n"
  let source_b = "code b\n// docs:snippet-end split\n"
  let config =
    make_config(".", ["src"], [".gleam"], [
      make_snippet("s1", "src/a.gleam", "gleam", ["split"], "\n\n"),
    ])
  let config_path =
    setup_fixture("split-marker", config, [
      #("src/a.gleam", source_a),
      #("src/b.gleam", source_b),
    ])

  generate(config_path)
  |> should.be_error
  |> fn(err) {
    case err {
      ExtractionError("s1", extractor.MissingEnd("src/a.gleam", "split")) -> Nil
      _ -> should.fail()
    }
  }

  cleanup("split-marker")
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
// Error — an end directive with no start
//
// The scan reads start directives and end directives. An end directive with
// no start directive is a broken pair. A scan that reads start directives
// alone cannot see the broken pair, so the scan reads both.
// ---------------------------------------------------------------------------

pub fn generate_dangling_end_unreferenced_test() {
  let source =
    "// docs:snippet-start used\ncode\n// docs:snippet-end used\n// docs:snippet-end stray\n"
  let config =
    make_config(".", ["src"], [".gleam"], [
      make_snippet("s1", "src/main.gleam", "gleam", ["used"], "\n\n"),
    ])
  let config_path =
    setup_fixture("dangling-end", config, [#("src/main.gleam", source)])

  generate(config_path)
  |> should.be_error
  |> fn(err) {
    case err {
      OrphanMarker("stray", "src/main.gleam") -> Nil
      _ -> should.fail()
    }
  }

  cleanup("dangling-end")
}

pub fn generate_dangling_end_configured_test() {
  let source = "code\n// docs:snippet-end stray\n"
  let config =
    make_config(".", ["src"], [".gleam"], [
      make_snippet("s1", "src/main.gleam", "gleam", ["stray"], "\n\n"),
    ])
  let config_path =
    setup_fixture("dangling-end-configured", config, [
      #("src/main.gleam", source),
    ])

  generate(config_path)
  |> should.be_error
  |> fn(err) {
    case err {
      ExtractionError("s1", extractor.MissingStart("src/main.gleam", "stray")) ->
        Nil
      _ -> should.fail()
    }
  }

  cleanup("dangling-end-configured")
}

pub fn generate_dangling_start_unreferenced_test() {
  let source =
    "// docs:snippet-start used\ncode\n// docs:snippet-end used\n// docs:snippet-start stray\n"
  let config =
    make_config(".", ["src"], [".gleam"], [
      make_snippet("s1", "src/main.gleam", "gleam", ["used"], "\n\n"),
    ])
  let config_path =
    setup_fixture("dangling-start", config, [#("src/main.gleam", source)])

  generate(config_path)
  |> should.be_error
  |> fn(err) {
    case err {
      OrphanMarker("stray", "src/main.gleam") -> Nil
      _ -> should.fail()
    }
  }

  cleanup("dangling-start")
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
        origin: MarkerOrigin(["beta"]),
      ),
      ManifestEntry(
        id: "alpha",
        code: "let a = 1",
        language: "gleam",
        source_path: "src/a.gleam",
        origin: MarkerOrigin(["alpha"]),
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
        origin: MarkerOrigin(["a", "b"]),
      ),
    ])
  let encoded = encode(m)
  should.be_true(string.contains(encoded, "\"markers\":[\"a\",\"b\"]"))
}

/// The manifest must not describe a file listing as a marker range.
pub fn encode_manifest_whole_file_origin_test() {
  let m =
    Manifest(version: 1, snippets: [
      ManifestEntry(
        id: "listing",
        code: "//// docs\n",
        language: "gleam",
        source_path: "src/m.gleam",
        origin: FileOrigin,
      ),
    ])
  let encoded = encode(m)
  should.be_true(string.contains(encoded, "\"kind\":\"file\""))
  should.be_false(string.contains(encoded, "\"markers\""))
  should.be_false(string.contains(encoded, "\"kind\":\"source\""))
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
  make_config_json(source_root, marker_roots, extensions, option.None, snippets)
}

fn make_config_with_exclusions(
  source_root: String,
  marker_roots: List(String),
  extensions: List(String),
  exclude_dirs: List(String),
  snippets: List(String),
) -> String {
  make_config_json(
    source_root,
    marker_roots,
    extensions,
    option.Some(exclude_dirs),
    snippets,
  )
}

fn make_config_json(
  source_root: String,
  marker_roots: List(String),
  extensions: List(String),
  exclude_dirs: option.Option(List(String)),
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
  let exclusions_json = case exclude_dirs {
    option.None -> ""
    option.Some(dirs) ->
      "\n  \"excludeDirs\": ["
      <> {
        dirs
        |> list_map(fn(d) { "\"" <> d <> "\"" })
        |> string.join(", ")
      }
      <> "],"
  }
  let snippets_json = string.join(snippets, ", ")
  "{
  \"version\": 1,
  \"sourceRoot\": \"" <> source_root <> "\",
  \"markerRoots\": [" <> roots_json <> "],
  \"extensions\": [" <> exts_json <> "]," <> exclusions_json <> "
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

fn make_whole_file_snippet(
  id: String,
  source_path: String,
  language: String,
) -> String {
  "{
    \"id\": \"" <> id <> "\",
    \"sourcePath\": \"" <> source_path <> "\",
    \"language\": \"" <> language <> "\",
    \"wholeFile\": true
  }"
}

fn escape_json_string(s: String) -> String {
  s
  |> string.replace("\\", "\\\\")
  |> string.replace("\"", "\\\"")
  |> string.replace("\n", "\\n")
  |> string.replace("\t", "\\t")
}
