import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import simplifile
import startest.{describe, it}
import startest/expect
import startest/test_tree.{type TestTree}
import watershed/json_ot.{type JsonValue, VObject}
import watershed/rich_text
import watershed/rich_text/utf16

const fixture_dir = "test/fixtures/shared_rich_text"

pub fn rich_text_fixture_tests() -> TestTree {
  let assert Ok(files) = simplifile.read_directory(fixture_dir)
  let files =
    files
    |> list.filter(string.ends_with(_, ".json"))
    |> list.sort(string.compare)
  describe(
    "shared rich text oracle",
    list.map(files, fn(file) { it(file, fn() { replay_fixture(file) }) }),
  )
}

pub fn normalization_and_malformed_input_test() {
  let assert Ok(delta) =
    rich_text.delta_from_json_string(
      "[{\"delete\":1},{\"insert\":\"a\"},{\"delete\":2},{\"retain\":3}]",
    )
  encoded_delta(delta) |> expect.to_equal("[{\"insert\":\"a\"},{\"delete\":3}]")
  rich_text.delta_from_json_string("[{\"insert\":null}]")
  |> expect.to_equal(
    Error(rich_text.Malformed("operation 0", "null insert is invalid")),
  )
  rich_text.delta_from_json_string("[{\"retain\":0}]")
  |> expect.to_equal(
    Error(rich_text.Malformed(
      "operation 0",
      "retain must be a positive integer",
    )),
  )
  rich_text.delta_from_json_string("[{\"insert\":\"x\",\"delete\":1}]")
  |> expect.to_equal(
    Error(rich_text.Malformed("operation 0", "must have exactly one action key")),
  )
  rich_text.delta_from_json_string("[{\"insert\":\"x\",\"unknown\":true}]")
  |> expect.to_equal(
    Error(rich_text.Malformed("operation 0", "contains an unknown field")),
  )
}

pub fn compose_apply_invert_and_utf16_test() {
  utf16.boundary("A😀B", 2) |> expect.to_equal(False)
  let assert Ok(base) =
    rich_text.document_from_json_string("[{\"insert\":\"A😀B\"}]")
  let assert Ok(delta) =
    rich_text.delta_from_json_string(
      "[{\"retain\":1},{\"insert\":\"x\"},{\"delete\":2}]",
    )
  let assert Ok(applied) = rich_text.apply(base, delta)
  encoded_document(applied) |> expect.to_equal("[{\"insert\":\"AxB\"}]")
  let assert Ok(inverse) = rich_text.invert(delta, base)
  let assert Ok(restored) = rich_text.apply(applied, inverse)
  restored |> expect.to_equal(base)
  rich_text.document_from_json_string("[{\"insert\":\"A😀B\"}]")
  |> expect.to_equal(Ok(base))
  let assert Ok(split) =
    rich_text.delta_from_json_string("[{\"retain\":2},{\"delete\":1}]")
  rich_text.apply(base, split)
  |> expect.to_equal(Error(rich_text.InvalidBoundary(2)))
}

pub fn direct_algebra_surrogate_boundaries_are_checked_test() {
  let assert Ok(emoji) =
    rich_text.delta_from_json_string("[{\"insert\":\"😀\"}]")
  let assert Ok(split) =
    rich_text.delta_from_json_string("[{\"retain\":1},{\"delete\":1}]")

  // Compose must split the left insert at this boundary, so it reports the
  // UTF-16 offset rather than leaking the iterator's old pattern-match panic.
  rich_text.compose(emoji, split)
  |> expect.to_equal(Error(rich_text.InvalidBoundary(1)))

  let assert Ok(base) =
    rich_text.document_from_json_string("[{\"insert\":\"😀\"}]")
  rich_text.invert(split, base)
  |> expect.to_equal(Error(rich_text.InvalidBoundary(1)))

  // Transform itself does not split inserts in Quill's control flow, but its
  // public checked Result ensures any iterator split is typed rather than raw.
  case rich_text.transform(split, emoji, rich_text.Left) {
    Ok(_) -> Nil
    Error(error) ->
      panic as { "unexpected transform error: " <> string.inspect(error) }
  }
}

pub fn delete_then_insert_cursor_and_selection_test() {
  // The retain holds the insertion after the deleted prefix in canonical
  // operation order. The delete must leave `offset` unchanged so the cursor
  // and range collapse before later operations are considered.
  let assert Ok(delta) =
    rich_text.delta_from_json_string(
      "[{\"delete\":5},{\"retain\":1},{\"insert\":\"abc\"}]",
    )

  // Local priority reaches the later insertion after the deletion.
  rich_text.transform_position(delta, 6, True) |> expect.to_equal(Ok(4))
  let assert Ok(cursor) = rich_text.selection(6, 0)
  rich_text.transform_selection(delta, cursor, True)
  |> expect.to_equal(Ok(rich_text.Selection(4, 0)))

  // Remote priority leaves the cursor at the retained boundary.
  rich_text.transform_position(delta, 6, False) |> expect.to_equal(Ok(1))
  rich_text.transform_selection(delta, cursor, False)
  |> expect.to_equal(Ok(rich_text.Selection(1, 0)))
}

pub fn same_position_side_and_selection_test() {
  let assert Ok(a) = rich_text.delta_from_json_string("[{\"insert\":\"A\"}]")
  let assert Ok(b) = rich_text.delta_from_json_string("[{\"insert\":\"B\"}]")
  let assert Ok(left) = rich_text.transform(a, b, rich_text.Left)
  left
  |> encoded_delta
  |> expect.to_equal("[{\"retain\":1},{\"insert\":\"A\"}]")
  let assert Ok(right) = rich_text.transform(a, b, rich_text.Right)
  right
  |> encoded_delta
  |> expect.to_equal("[{\"insert\":\"A\"}]")
  let assert Ok(composed) = rich_text.compose(a, b)
  rich_text.transform_position(composed, 0, True) |> expect.to_equal(Ok(2))
  let assert Ok(selection) = rich_text.selection(0, 0)
  rich_text.transform_selection(composed, selection, True)
  |> expect.to_equal(Ok(rich_text.Selection(2, 0)))
}

fn replay_fixture(file: String) {
  let assert Ok(raw) = simplifile.read(fixture_dir <> "/" <> file)
  let assert Ok(VObject(root)) = json_ot.from_json_string(raw)
  let base_json = required(root, "base")
  let deltas = object(required(root, "deltas"))
  let a_json = required(deltas, "a")
  let assert Ok(base) = rich_text.document_from_json(base_json)
  let assert Ok(a) = rich_text.delta_from_json(a_json)
  expect_document(base, required(object(required(root, "normalized")), "base"))
  expect_delta(
    a,
    required(
      object(required(object(required(root, "normalized")), "deltas")),
      "a",
    ),
  )
  let apply = object(required(root, "apply"))
  let assert Ok(applied_a) = rich_text.apply(base, a)
  expect_document(applied_a, required(apply, "a"))
  let inverse = object(required(root, "inverse"))
  let assert Ok(inverse_a) = rich_text.invert(a, base)
  expect_delta(inverse_a, required(inverse, "a"))
  let composed = case get(deltas, "b") {
    None -> None
    Some(b_json) -> {
      let assert Ok(b) = rich_text.delta_from_json(b_json)
      let assert Ok(applied_b) = rich_text.apply(base, b)
      expect_document(applied_b, required(apply, "b"))
      let assert Ok(composed) = rich_text.compose(a, b)
      expect_delta(composed, required(root, "compose"))
      let inverse_composed = case rich_text.invert(composed, base) {
        Ok(value) -> value
        Error(error) ->
          panic as { "composed inverse failed: " <> string.inspect(error) }
      }
      expect_delta(inverse_composed, required(inverse, "compose"))
      let transform = object(required(root, "transform"))
      let assert Ok(left) = rich_text.transform(a, b, rich_text.Left)
      expect_delta(left, required(transform, "left"))
      let assert Ok(right) = rich_text.transform(a, b, rich_text.Right)
      expect_delta(right, required(transform, "right"))
      let assert Ok(b_star) = rich_text.transform(b, a, rich_text.Right)
      let assert Ok(after_a_then_b) = rich_text.apply(applied_a, b_star)
      let assert Ok(a_star) = rich_text.transform(a, b, rich_text.Left)
      let assert Ok(after_b_then_a) = rich_text.apply(applied_b, a_star)
      after_a_then_b |> expect.to_equal(after_b_then_a)
      case get(apply, "compose") {
        None -> Nil
        Some(expected) -> {
          let assert Ok(applied_composed) = rich_text.apply(base, composed)
          expect_document(applied_composed, expected)
        }
      }
      Some(composed)
    }
  }
  check_cursor_and_selection(root, a, composed)
}

fn expect_document(actual: rich_text.Document, expected: JsonValue) {
  let assert Ok(expected) = rich_text.document_from_json(expected)
  actual |> encoded_document |> expect.to_equal(encoded_document(expected))
}

fn expect_delta(actual: rich_text.Delta, expected: JsonValue) {
  let assert Ok(expected) = rich_text.delta_from_json(expected)
  actual |> encoded_delta |> expect.to_equal(encoded_delta(expected))
}

fn encoded_document(document: rich_text.Document) -> String {
  rich_text.document_to_json(document) |> json.to_string
}

fn encoded_delta(delta: rich_text.Delta) -> String {
  rich_text.delta_to_json(delta) |> json.to_string
}

fn required(fields: List(#(String, JsonValue)), key: String) -> JsonValue {
  let assert Ok(value) = list.key_find(fields, key)
  value
}

fn get(fields: List(#(String, JsonValue)), key: String) -> Option(JsonValue) {
  case list.key_find(fields, key) {
    Ok(value) -> Some(value)
    Error(_) -> None
  }
}

fn object(value: JsonValue) -> List(#(String, JsonValue)) {
  let assert VObject(fields) = value
  fields
}

fn check_cursor_and_selection(
  root: List(#(String, JsonValue)),
  a: rich_text.Delta,
  composed: Option(rich_text.Delta),
) {
  let cursor = object(required(root, "cursor"))
  let cursor_delta = through_delta(required(cursor, "through"), a, composed)
  rich_text.transform_position(
    cursor_delta,
    integer(required(cursor, "index")),
    boolean(required(cursor, "isOwnOp")),
  )
  |> expect.to_equal(Ok(integer(required(cursor, "result"))))

  let selection = object(required(root, "selection"))
  let selection_delta =
    through_delta(required(selection, "through"), a, composed)
  let assert Ok(input) =
    rich_text.selection(
      integer(required(selection, "index")),
      integer(required(selection, "length")),
    )
  let result = object(required(selection, "result"))
  rich_text.transform_selection(
    selection_delta,
    input,
    boolean(required(selection, "isOwnOp")),
  )
  |> expect.to_equal(
    Ok(rich_text.Selection(
      integer(required(result, "index")),
      integer(required(result, "length")),
    )),
  )
}

fn through_delta(
  through: JsonValue,
  a: rich_text.Delta,
  composed: Option(rich_text.Delta),
) -> rich_text.Delta {
  case through {
    json_ot.VString("a") -> a
    json_ot.VString("compose") -> {
      let assert Some(delta) = composed
      delta
    }
    _ -> panic as "unknown fixture delta"
  }
}

fn integer(value: JsonValue) -> Int {
  let assert json_ot.VNumber(json_ot.NInt(value)) = value
  value
}

fn boolean(value: JsonValue) -> Bool {
  let assert json_ot.VBool(value) = value
  value
}
