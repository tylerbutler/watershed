import watershed/tree/types

@target(javascript)
import watershed
@target(erlang)
import watershed_beam

pub type Item

pub type ItemState

@target(javascript)
pub fn javascript(tree: watershed.SharedTree(Item, ItemState)) {
  watershed.tree_set(tree, ["text"], types.StringValue("value"))
}

@target(erlang)
pub fn erlang(tree: watershed_beam.SharedTree(Item, ItemState)) {
  watershed_beam.tree_set(tree, ["text"], types.StringValue("value"))
}
