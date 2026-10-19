import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import simplifile
import startest/expect
import watershed/fluid_ids
import watershed/json_ot
import watershed/tree/identifier
import watershed/tree/identifier_fixture
import watershed/tree/schema
import watershed/tree/schema_builder as builder
import watershed/tree/transaction
import watershed/tree/types
import watershed/tree_kernel

type Point {
  Point(id: builder.Identifier, label: String)
}

fn point() -> builder.Node(Point) {
  builder.object2(
    builder.factory("com.example.typed"),
    "Point",
    Point,
    builder.identifier(key: "id", get: fn(v: Point) { v.id }),
    builder.required("label", builder.string(), fn(v: Point) { v.label }),
  )
}

pub fn typed_identifier_construction_test() {
  let assert Ok(compiled) = point() |> builder.root |> builder.compile
  builder.encode(compiled, Point(builder.Generate, "new")) |> expect.to_be_error
  builder.encode_new(compiled, Point(builder.Generate, "new"))
  |> expect.to_equal(
    Ok(
      Some(
        types.ObjectValue("com.example.typed.Point", [
          #("label", types.StringValue("new")),
        ]),
      ),
    ),
  )
  builder.decode(
    compiled,
    Some(
      types.ObjectValue("com.example.typed.Point", [
        #("id", types.StringValue("custom")),
        #("label", types.StringValue("new")),
      ]),
    ),
  )
  |> expect.to_equal(Ok(Point(builder.Assigned("custom"), "new")))
  builder.decode(
    compiled,
    Some(
      types.ObjectValue("com.example.typed.Point", [
        #("label", types.StringValue("missing")),
      ]),
    ),
  )
  |> expect.to_be_error
  ["", "custom", "11111111-2222-4333-8444-555555555555"]
  |> list.each(fn(id) {
    let value = Point(builder.Assigned(id), "label")
    let assert Ok(encoded) = builder.encode(compiled, value)
    builder.encode_new(compiled, value) |> expect.to_equal(Ok(encoded))
    builder.decode(compiled, encoded) |> expect.to_equal(Ok(value))
  })
}

type Choice {
  Text(String)
  Item(Point)
}

fn choice() -> builder.Node(Choice) {
  builder.union([
    builder.variant(builder.string(), Text, fn(v) {
      case v {
        Text(text) -> Some(text)
        Item(_) -> None
      }
    }),
    builder.variant(point(), Item, fn(v) {
      case v {
        Item(point) -> Some(point)
        Text(_) -> None
      }
    }),
  ])
}

type Root {
  Root(
    featured: Point,
    left: List(Choice),
    right: List(Choice),
    by_key: dict.Dict(String, Choice),
  )
}

fn root() -> builder.Node(Root) {
  let f = builder.factory("com.example.typed")
  let items = builder.array(f, "Items", choice())
  builder.object4(
    f,
    "Root",
    Root,
    builder.required("featured", point(), fn(v: Root) { v.featured }),
    builder.required("left", items, fn(v: Root) { v.left }),
    builder.required("right", items, fn(v: Root) { v.right }),
    builder.required("byKey", builder.map(f, "ByKey", choice()), fn(v: Root) {
      v.by_key
    }),
  )
}

fn initial() -> Root {
  Root(
    Point(builder.Generate, "featured"),
    [Text("text"), Item(Point(builder.Generate, "nested-array"))],
    [],
    dict.from_list([#("nested", Item(Point(builder.Generate, "nested-map")))]),
  )
}

pub fn typed_identifier_nested_construction_test() {
  let assert Ok(compiled) = root() |> builder.root |> builder.compile
  builder.encode(compiled, initial()) |> expect.to_be_error
  let assert Ok(Some(new)) = builder.encode_new(compiled, initial())
  builder.encode_new(compiled, initial()) |> expect.to_equal(Ok(Some(new)))
  let compressor = fluid_ids.new(identifier_fixture.session())
  let assert Ok(#(materialized, advanced)) =
    identifier.materialize_value(builder.stored(compiled), new, compressor)
  let assert Ok(Root(featured, left, _, by_key)) =
    builder.decode(compiled, Some(materialized))
  let assert builder.Assigned(featured_id) = featured.id
  let assert [Text("text"), Item(Point(builder.Assigned(array_id), _))] = left
  let assert Ok(Item(Point(builder.Assigned(map_id), _))) =
    dict.get(by_key, "nested")
  list.unique([featured_id, array_id, map_id])
  |> list.length
  |> expect.to_equal(3)
  let assert #(_, Some(range)) = fluid_ids.take_creation_range(advanced)
  let assert Some(ids) = range.ids
  ids.count |> expect.to_equal(3)
  builder.encode_new(compiled, initial()) |> expect.to_equal(Ok(Some(new)))
}

type Recursive {
  Recursive(id: builder.Identifier, children: List(Recursive))
}

fn recursive() -> builder.Node(Recursive) {
  let f = builder.factory("com.example")
  builder.object2(
    f,
    "Recursive",
    Recursive,
    builder.identifier("id", fn(v: Recursive) { v.id }),
    builder.required(
      "children",
      builder.array(f, "Children", builder.lazy(f, "Recursive", recursive)),
      fn(v: Recursive) { v.children },
    ),
  )
}

pub fn typed_identifier_recursive_construction_test() {
  let assert Ok(compiled) = recursive() |> builder.root |> builder.compile
  let value = Recursive(builder.Generate, [Recursive(builder.Generate, [])])
  let assert Ok(Some(new)) = builder.encode_new(compiled, value)
  let assert Ok(#(materialized, _)) =
    identifier.materialize_value(
      builder.stored(compiled),
      new,
      fluid_ids.new(identifier_fixture.session()),
    )
  let assert Ok(Recursive(
    builder.Assigned(parent),
    [Recursive(builder.Assigned(child), [])],
  )) = builder.decode(compiled, Some(materialized))
  parent |> expect.to_not_equal(child)
}

pub fn typed_identifier_optional_construction_test() {
  let assert Ok(compiled) = point() |> builder.optional_root |> builder.compile
  builder.encode_new(compiled, None) |> expect.to_equal(Ok(None))
  let assert Ok(Some(new)) =
    builder.encode_new(compiled, Some(Point(builder.Generate, "new")))
  builder.decode(compiled, Some(new)) |> expect.to_be_error
  let holder =
    builder.object1(
      builder.factory("com.example"),
      "Holder",
      fn(v) { v },
      builder.optional("point", point(), fn(v) { v }),
    )
  let assert Ok(compiled) = holder |> builder.root |> builder.compile
  builder.encode_new(compiled, None)
  |> expect.to_equal(Ok(Some(types.ObjectValue("com.example.Holder", []))))
  builder.encode_new(compiled, Some(Point(builder.Generate, "new")))
  |> expect.to_equal(
    Ok(
      Some(
        types.ObjectValue("com.example.Holder", [
          #("point", new),
        ]),
      ),
    ),
  )
  builder.encode(compiled, Some(Point(builder.Generate, "new")))
  |> expect.to_be_error
  Nil
}

pub fn typed_identifier_transaction_allocation_test() {
  let assert Ok(compiled) = point() |> builder.root |> builder.compile
  let assert Ok(Some(base)) =
    builder.encode(compiled, Point(builder.Assigned("before"), "before"))
  let base =
    identifier_fixture.state(
      builder.stored(compiled),
      builder.view(compiled),
      base,
    )
  let assert Ok(Some(new)) =
    builder.encode_new(compiled, Point(builder.Generate, "inserted"))
  let compressor = fluid_ids.new(identifier_fixture.session())
  let assert Ok(open) = transaction.begin(base, compressor, [])
  let assert Ok(open) = transaction.apply_edit(open, types.SetField([], new))
  let assert Ok(Some(preview)) = tree_kernel.read(transaction.state(open), [])
  let assert Ok(Point(builder.Assigned(id), "inserted")) =
    builder.decode(compiled, Some(preview))
  let advanced = transaction.compressor(open)
  let assert #(_, Some(range)) = fluid_ids.take_unfinalized_range(advanced)
  let assert Some(ids) = range.ids
  ids.count |> expect.to_equal(2)
  let assert Ok(#(transaction.Commit(committed, _, _), _)) =
    transaction.finish(open)
  tree_kernel.read(committed, [])
  |> expect.to_equal(Ok(Some(preview)))
  let assert Ok(#(aborted, advanced_after_abort)) = transaction.abort(open)
  tree_kernel.read(aborted, []) |> expect.to_equal(tree_kernel.read(base, []))
  advanced_after_abort |> expect.to_equal(advanced)
  id |> expect.to_not_equal("before")
  let rows = authoring_scenarios()
  ["commit", "abort"]
  |> list.each(fn(action) {
    let assert Ok(observation) =
      list.key_find(rows, "generated-identifiers-" <> action)
    let assert Ok(#(allocation_count, initial_count, survives)) =
      json.parse(
        json.to_string(json_ot.to_json(observation)),
        allocation_observation(),
      )
    allocation_count - initial_count |> expect.to_equal(ids.count)
    survives |> expect.to_equal(action == "commit")
  })
}

fn authoring_scenarios() -> List(#(String, json_ot.JsonValue)) {
  let row = {
    use id <- decode.field("id", decode.string)
    use observations <- decode.field("observations", json_ot.decoder())
    decode.success(#(id, observations))
  }
  let envelope = {
    use rows <- decode.field("scenarios", decode.list(row))
    decode.success(rows)
  }
  let assert Ok(raw) =
    simplifile.read("test/fixtures/shared_tree/typed-api-authoring.json")
  let assert Ok(rows) = json.parse(raw, envelope)
  rows
}

fn allocation_observation() -> decode.Decoder(#(Int, Int, Bool)) {
  use allocations <- decode.field("allocations", decode.list(json_ot.decoder()))
  use initial <- decode.field("initialAllocationCount", decode.int)
  use survives <- decode.field("survives", decode.bool)
  decode.success(#(list.length(allocations), initial, survives))
}

pub fn typed_identifier_pinned_schemas_test() {
  let row = {
    use id <- decode.field("id", decode.string)
    use value <- decode.field("schema", json_ot.decoder())
    decode.success(#(id, value))
  }
  let envelope = {
    use rows <- decode.field("schemas", decode.list(row))
    decode.success(rows)
  }
  let assert Ok(raw) =
    simplifile.read("test/fixtures/shared_tree/typed-api-authoring.json")
  let assert Ok(rows) = json.parse(raw, envelope)
  let f = builder.factory("com.example.typed")
  let assert Ok(optional) =
    builder.object1(
      f,
      "UnionObject",
      fn(v) { v },
      builder.required("value", choice(), fn(v: Choice) { v }),
    )
    |> builder.root
    |> builder.compile
  [
    #("identifier-point", schema_of(point())),
    #("union-root", schema_of(choice())),
    #("union-array", schema_of(builder.array(f, "Items", choice()))),
    #("union-map", schema_of(builder.map(f, "ByKey", choice()))),
    #("union-object", builder.stored(optional)),
  ]
  |> list.each(fn(entry) {
    let assert Ok(persisted) = list.key_find(rows, entry.0)
    let assert Ok(expected) =
      schema.stored_from_json(json_ot.to_json(persisted))
    schema.stored_to_json(entry.1)
    |> json.to_string
    |> expect.to_equal(schema.stored_to_json(expected) |> json.to_string)
  })
}

fn schema_of(node: builder.Node(a)) -> schema.StoredSchema {
  let assert Ok(compiled) = node |> builder.root |> builder.compile
  builder.stored(compiled)
}
