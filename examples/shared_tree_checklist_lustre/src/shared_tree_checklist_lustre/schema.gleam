import gleam/result
import shared_tree_checklist_lustre/checklist
import watershed/tree/schema_builder as builder
import watershed/tree/types

fn factory() -> builder.Factory {
  builder.factory(scope: "shared_tree_checklist")
}

pub fn text() -> builder.Property(checklist.Item, String) {
  builder.required(
    key: "text",
    node: builder.string(),
    get: fn(item: checklist.Item) { item.text },
  )
}

pub fn completed() -> builder.Property(checklist.Item, Bool) {
  builder.required(
    key: "completed",
    node: builder.boolean(),
    get: fn(item: checklist.Item) { item.completed },
  )
}

pub fn item() -> builder.Node(checklist.Item) {
  builder.object3(
    factory(),
    "Item",
    checklist.Item,
    builder.required(
      key: "id",
      node: builder.string(),
      get: fn(item: checklist.Item) { item.id },
    ),
    text(),
    completed(),
  )
}

pub fn title() -> builder.Property(checklist.Checklist, String) {
  builder.required(
    key: "title",
    node: builder.string(),
    get: fn(value: checklist.Checklist) { value.title },
  )
}

pub fn items() -> builder.Property(checklist.Checklist, List(checklist.Item)) {
  builder.required(
    key: "items",
    node: builder.array(factory: factory(), name: "Items", element: item()),
    get: fn(value: checklist.Checklist) { value.items },
  )
}

pub fn configuration() -> builder.Root(checklist.Checklist) {
  builder.object(
    factory: factory(),
    name: "Checklist",
    properties: [builder.property(title()), builder.property(items())],
    construct: fn(reader) {
      use title <- result.try(builder.read_property(reader:, property: title()))
      use items <- result.try(builder.read_property(reader:, property: items()))
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
