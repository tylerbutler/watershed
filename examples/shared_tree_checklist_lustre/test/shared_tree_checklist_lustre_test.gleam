import gleam/option.{None, Some}
import gleeunit
import shared_tree_checklist_lustre/checklist
import shared_tree_checklist_lustre/schema as document_schema
import watershed/tree/schema
import watershed/tree/types

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn initial_tree_matches_the_stored_schema_test() {
  let assert Ok(Nil) =
    schema.validate_root(document_schema.stored(), document_schema.initial())
}

pub fn decode_and_prepare_every_required_operation_test() {
  let root =
    document_schema.checklist_value([
      #("a", "first", False),
      #("b", "second", True),
      #("c", "third", False),
    ])
  let assert Ok(value) = checklist.decode(root)
  let assert Ok(types.ArrayInsert(["items"], 3, [inserted])) =
    checklist.add(value, "d", "fourth")
  let assert True = inserted == document_schema.item_value("d", "fourth", False)
  let assert Ok(types.SetField(
    ["items", "1", "text"],
    types.StringValue("renamed"),
  )) = checklist.edit(value, "b", "renamed")
  let assert Ok(types.SetField(
    ["items", "1", "completed"],
    types.BooleanValue(False),
  )) = checklist.toggle(value, "b")
  let assert Ok(types.ArrayRemove(["items"], 1, 2)) =
    checklist.delete(value, "b")
  let assert Ok(Some(types.ArrayMove(["items"], 1, 2, ["items"], 0))) =
    checklist.move_up(value, "b")
  let assert Ok(Some(types.ArrayMove(["items"], 1, 2, ["items"], 3))) =
    checklist.move_down(value, "b")
}

pub fn boundary_moves_and_stale_ids_do_not_submit_edits_test() {
  let root =
    document_schema.checklist_value([
      #("a", "first", False),
      #("b", "second", False),
    ])
  let assert Ok(value) = checklist.decode(root)
  let assert Ok(None) = checklist.move_up(value, "a")
  let assert Ok(None) = checklist.move_down(value, "b")
  let assert Error("checklist item missing is no longer present") =
    checklist.delete(value, "missing")
}

pub fn decoder_rejects_duplicate_ids_and_malformed_items_test() {
  let duplicate =
    document_schema.checklist_value([
      #("same", "first", False),
      #("same", "second", True),
    ])
  let assert Error("duplicate checklist item id same") =
    checklist.decode(duplicate)
  let malformed =
    types.ObjectValue("shared_tree_checklist.Checklist", [
      #("title", types.StringValue("SharedTree checklist")),
      #(
        "items",
        types.ArrayValue("shared_tree_checklist.Items", [
          types.ObjectValue("shared_tree_checklist.Item", [
            #("id", types.StringValue("a")),
            #("text", types.StringValue("missing completion")),
          ]),
        ]),
      ),
    ])
  let assert Error(_) = checklist.decode(malformed)
}
