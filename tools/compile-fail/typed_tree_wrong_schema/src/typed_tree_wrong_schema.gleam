import watershed/tree/typed.{type Field, type Required}

@target(javascript)
import watershed
@target(erlang)
import watershed_beam

pub type Item

pub type Other

pub type ItemState

@target(javascript)
pub fn javascript(
  node: watershed.TreeNode(Item, ItemState),
  field: Field(Other, String, Required),
) {
  watershed.tree_get(node, field)
}

@target(erlang)
pub fn erlang(
  node: watershed_beam.TreeNode(Item, ItemState),
  field: Field(Other, String, Required),
) {
  watershed_beam.tree_get(node, field)
}
