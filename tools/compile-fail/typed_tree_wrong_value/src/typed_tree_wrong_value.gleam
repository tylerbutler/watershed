import watershed/tree
import watershed/tree/schema_builder as builder

pub type Item {
  Item(text: String)
}

pub fn invalid(node: tree.Ref(Item), field: builder.Property(Item, String)) {
  tree.set(node, field, 42)
}
