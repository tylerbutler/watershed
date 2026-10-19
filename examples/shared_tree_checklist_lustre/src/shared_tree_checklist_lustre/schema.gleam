import gleam/result
import shared_tree_checklist_lustre/checklist
import watershed/tree/schema_builder as builder
import watershed/tree/types

fn factory() -> builder.Factory {
  builder.factory("shared_tree_checklist")
}

pub fn text() -> builder.Property(checklist.Item, String) {
  builder.required("text", builder.string(), fn(item: checklist.Item) {
    item.text
  })
}

pub fn completed() -> builder.Property(checklist.Item, Bool) {
  builder.required("completed", builder.boolean(), fn(item: checklist.Item) {
    item.completed
  })
}

pub fn item() -> builder.Node(checklist.Item) {
  builder.object3(
    factory(),
    "Item",
    checklist.Item,
    builder.required("id", builder.string(), fn(item: checklist.Item) {
      item.id
    }),
    text(),
    completed(),
  )
}

pub fn title() -> builder.Property(checklist.Checklist, String) {
  builder.required("title", builder.string(), fn(value: checklist.Checklist) {
    value.title
  })
}

pub fn items() -> builder.Property(checklist.Checklist, List(checklist.Item)) {
  builder.required(
    "items",
    builder.array(factory(), "Items", item()),
    fn(value: checklist.Checklist) { value.items },
  )
}

pub fn configuration() -> builder.Root(checklist.Checklist) {
  builder.object(
    factory(),
    "Checklist",
    [builder.property(title()), builder.property(items())],
    fn(reader) {
      use title <- result.try(builder.read_property(reader, title()))
      use items <- result.try(builder.read_property(reader, items()))
      use _ <- result.try(
        checklist.validate_unique_ids(items)
        |> result.map_error(fn(detail) { types.InvalidEdit(["items"], detail) }),
      )
      Ok(checklist.Checklist(title, items))
    },
  )
  |> builder.root
}

pub fn initial() -> checklist.Checklist {
  checklist.empty()
}
