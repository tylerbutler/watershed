import watershed/tree
import watershed/tree/schema_builder as builder

pub type Item {
  Item(text: String)
}

pub type Other {
  Other(text: String)
}

pub fn invalid(node: tree.Ref(Item), field: builder.Property(Other, String)) {
  tree.get(node, field)
}
