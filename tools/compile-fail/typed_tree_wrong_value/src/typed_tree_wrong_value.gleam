import watershed/tree/typed.{type Field, type Required}

@target(javascript)
import watershed
@target(erlang)
import watershed_beam

pub type Item

pub type ItemState

@target(javascript)
pub fn javascript(
  node: watershed.TreeNode(Item, ItemState),
  field: Field(Item, String, Required),
) {
  watershed.tree_set(node, field, 42)
}

@target(erlang)
pub fn erlang(
  node: watershed_beam.TreeNode(Item, ItemState),
  field: Field(Item, String, Required),
) {
  watershed_beam.tree_set(node, field, 42)
}
