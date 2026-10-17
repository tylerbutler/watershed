import gleam/option.{type Option, None, Some}
import watershed/tree
import watershed/tree/schema_builder as builder

pub type Item {
  Item(text: String)
}

pub fn invalid(node: tree.Ref(Item), field: builder.Property(Item, String)) {
  tree.set(node, field, None)
}

pub fn invalid_optional_value(
  node: tree.Ref(Item),
  field: builder.Property(Item, Option(String)),
) {
  tree.set(node, field, Some(42))
}
