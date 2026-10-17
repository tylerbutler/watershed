import gleam/option.{None, Some}
import gleam/result
import watershed/tree
import watershed/tree/error

pub type Action {
  Insert
  Remove
}

// docs:snippet-start item-counter-watershed-edits
pub fn apply(
  handle: tree.Tree(List(String)),
  action: Action,
) -> Result(Nil, error.Error) {
  use array <- result.try(tree.required_root(handle))
  case action {
    Insert -> tree.array_insert(array, 0, [""])
    Remove -> {
      use first <- result.try(tree.array_get(array, 0))
      case first {
        None -> Ok(Nil)
        Some(_) -> tree.array_remove(array, 0, 1)
      }
    }
  }
}
// docs:snippet-end item-counter-watershed-edits
