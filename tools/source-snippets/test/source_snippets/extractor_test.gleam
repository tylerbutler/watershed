import gleam/string
import gleeunit/should
import source_snippets/extractor.{
  type MarkerRange, DuplicateEnd, DuplicateStart, Empty, MarkerRange,
  MismatchedEnd, MissingEnd, MissingStart, Nested, Reversed, extract,
  marker_names,
}

// ---------------------------------------------------------------------------
// marker_names
// ---------------------------------------------------------------------------

pub fn marker_names_returns_all_start_names_test() {
  "// docs:snippet-start foo\ncode\n// docs:snippet-end foo\n// docs:snippet-start bar\nmore\n// docs:snippet-end bar"
  |> marker_names
  |> should.equal(["foo", "bar"])
}

pub fn marker_names_empty_when_no_markers_test() {
  "just code\nno markers"
  |> marker_names
  |> should.equal([])
}

pub fn marker_names_ignores_end_directives_test() {
  "// docs:snippet-end orphan\n"
  |> marker_names
  |> should.equal([])
}

// ---------------------------------------------------------------------------
// extract — valid ranges
// ---------------------------------------------------------------------------

pub fn extract_top_level_range_test() {
  "// docs:snippet-start greet\npub fn hello() {\n  Nil\n}\n// docs:snippet-end greet"
  |> extract("test.gleam", "greet")
  |> should.be_ok
  |> should.equal(MarkerRange(name: "greet", code: "pub fn hello() {\n  Nil\n}"))
}

pub fn extract_indented_range_is_dedented_test() {
  "  // docs:snippet-start indent\n  let x = 1\n  let y = 2\n  // docs:snippet-end indent"
  |> extract("test.gleam", "indent")
  |> should.be_ok
  |> should.equal(MarkerRange(name: "indent", code: "let x = 1\nlet y = 2"))
}

pub fn extract_preserves_internal_blank_lines_test() {
  "// docs:snippet-start blank\nline one\n\nline two\n// docs:snippet-end blank"
  |> extract("test.gleam", "blank")
  |> should.be_ok
  |> should.equal(MarkerRange(name: "blank", code: "line one\n\nline two"))
}

pub fn extract_strips_trailing_whitespace_test() {
  "// docs:snippet-start ws\nlet x = 1   \nlet y = 2\t\n// docs:snippet-end ws"
  |> extract("test.gleam", "ws")
  |> should.be_ok
  |> should.equal(MarkerRange(name: "ws", code: "let x = 1\nlet y = 2"))
}

pub fn extract_excludes_marker_directives_from_code_test() {
  let source = "// docs:snippet-start x\nfoo()\n// docs:snippet-end x"
  let code =
    extract(source, "test.gleam", "x")
    |> should.be_ok
    |> fn(r: MarkerRange) { r.code }
  should.be_false(string.contains(code, "docs:snippet-start"))
  should.be_false(string.contains(code, "docs:snippet-end"))
}

pub fn extract_selects_correct_marker_from_multiple_test() {
  let source =
    "// docs:snippet-start a\nline a\n// docs:snippet-end a\n// docs:snippet-start b\nline b\n// docs:snippet-end b"
  extract(source, "test.gleam", "b")
  |> should.be_ok
  |> should.equal(MarkerRange(name: "b", code: "line b"))
}

pub fn extract_dedents_relative_indentation_test() {
  "    // docs:snippet-start rel\n    outer\n      inner\n    // docs:snippet-end rel"
  |> extract("test.gleam", "rel")
  |> should.be_ok
  |> should.equal(MarkerRange(name: "rel", code: "outer\n  inner"))
}

// ---------------------------------------------------------------------------
// extract — error cases
// ---------------------------------------------------------------------------

pub fn extract_missing_start_test() {
  "// docs:snippet-end foo\n"
  |> extract("src/a.gleam", "foo")
  |> should.be_error
  |> should.equal(MissingStart("src/a.gleam", "foo"))
}

pub fn extract_missing_start_when_no_markers_test() {
  "just code"
  |> extract("src/a.gleam", "missing")
  |> should.be_error
  |> should.equal(MissingStart("src/a.gleam", "missing"))
}

pub fn extract_missing_end_test() {
  "// docs:snippet-start foo\ncode\n"
  |> extract("src/b.gleam", "foo")
  |> should.be_error
  |> should.equal(MissingEnd("src/b.gleam", "foo"))
}

pub fn extract_duplicate_start_test() {
  "// docs:snippet-start dup\ncode\n// docs:snippet-start dup\nmore\n// docs:snippet-end dup"
  |> extract("src/c.gleam", "dup")
  |> should.be_error
  |> should.equal(DuplicateStart("src/c.gleam", "dup"))
}

pub fn extract_duplicate_end_test() {
  "// docs:snippet-start dup\ncode\n// docs:snippet-end dup\n// docs:snippet-end dup"
  |> extract("src/d.gleam", "dup")
  |> should.be_error
  |> should.equal(DuplicateEnd("src/d.gleam", "dup"))
}

pub fn extract_reversed_markers_test() {
  "// docs:snippet-end rev\ncode\n// docs:snippet-start rev"
  |> extract("src/e.gleam", "rev")
  |> should.be_error
  |> should.equal(Reversed("src/e.gleam", "rev"))
}

pub fn extract_nested_marker_test() {
  "// docs:snippet-start outer\ncode\n// docs:snippet-start inner\nmore\n// docs:snippet-end outer"
  |> extract("src/f.gleam", "outer")
  |> should.be_error
  |> should.equal(Nested("src/f.gleam", "outer", "inner"))
}

pub fn extract_mismatched_end_test() {
  "// docs:snippet-start outer\ncode\n// docs:snippet-end other\nmore\n// docs:snippet-end outer"
  |> extract("src/g.gleam", "outer")
  |> should.be_error
  |> should.equal(MismatchedEnd("src/g.gleam", "outer", "other"))
}

pub fn extract_empty_range_test() {
  "// docs:snippet-start empty\n// docs:snippet-end empty"
  |> extract("src/h.gleam", "empty")
  |> should.be_error
  |> should.equal(Empty("src/h.gleam", "empty"))
}

pub fn extract_blank_only_range_is_empty_test() {
  "// docs:snippet-start blank\n   \n\n// docs:snippet-end blank"
  |> extract("src/i.gleam", "blank")
  |> should.be_error
  |> should.equal(Empty("src/i.gleam", "blank"))
}
