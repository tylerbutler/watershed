import watershed/tree

pub type Item {
  Item(text: String)
}

pub fn invalid(node: tree.Ref(Item)) {
  tree.set(node, ["text"], "value")
}
