//// Typed declarations and snapshot codecs for native SharedTree schemas.
////
//// Snapshots are values, not live references. The stored schema validator
//// checks declarations and content before codecs return a value.

import gleam/dict.{type Dict}
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import watershed/handle
import watershed/tree/schema
import watershed/tree/types.{type TreeError, type TreeValue}

pub opaque type Factory {
  Factory(scope: String)
}

pub fn factory(scope: String) -> Factory {
  Factory(scope)
}

fn name_errors(factory: Factory, name: String) -> List(TreeError) {
  case factory.scope, name {
    "", _ | _, "" -> [
      types.InvalidSchema("Schema scope and name must not be empty"),
    ]
    _, _ -> []
  }
}

type Definition {
  Concrete(
    identifier: String,
    schema: schema.NodeSchema,
    children: List(Definition),
  )
  Deferred(identifier: String, resolve: fn() -> Resolution)
}

type Resolution {
  Resolution(
    identifiers: List(String),
    definitions: List(Definition),
    errors: List(TreeError),
  )
}

type EncodeMode {
  Snapshot
  Construction
}

pub type Identifier {
  Generate
  Assigned(String)
}

pub opaque type Node(a) {
  Node(
    identifiers: List(String),
    definitions: List(Definition),
    errors: List(TreeError),
    encode: fn(EncodeMode, a) -> Result(TreeValue, TreeError),
    decode: fn(TreeValue) -> Result(a, TreeError),
  )
}

pub opaque type Root(a) {
  Root(
    field: schema.FieldSchema,
    definitions: List(Definition),
    errors: List(TreeError),
    encode: fn(EncodeMode, a) -> Result(Option(TreeValue), TreeError),
    decode: fn(Option(TreeValue)) -> Result(a, TreeError),
  )
}

pub opaque type Compiled(a) {
  Compiled(
    stored: schema.StoredSchema,
    view: schema.ViewSchema,
    encode: fn(EncodeMode, a) -> Result(Option(TreeValue), TreeError),
    decode: fn(Option(TreeValue)) -> Result(a, TreeError),
  )
}

pub opaque type Property(record, a) {
  Property(
    key: String,
    root: Root(a),
    encode: fn(EncodeMode, record) -> Result(Option(TreeValue), TreeError),
  )
}

pub opaque type ObjectProperty(record) {
  ObjectProperty(
    key: String,
    field: schema.FieldSchema,
    definitions: List(Definition),
    errors: List(TreeError),
    encode: fn(EncodeMode, record) -> Result(Option(TreeValue), TreeError),
  )
}

pub opaque type ObjectReader(record) {
  ObjectReader(
    fields: List(#(String, TreeValue)),
    properties: List(#(String, schema.FieldSchema)),
  )
}

pub fn required(
  key: String,
  node: Node(a),
  get: fn(record) -> a,
) -> Property(record, a) {
  let root = root(node)
  Property(key, root, fn(mode, record) { root.encode(mode, get(record)) })
}

pub fn optional(
  key: String,
  node: Node(a),
  get: fn(record) -> Option(a),
) -> Property(record, Option(a)) {
  let root = optional_root(node)
  Property(key, root, fn(mode, record) { root.encode(mode, get(record)) })
}

pub fn identifier(
  key: String,
  get: fn(record) -> Identifier,
) -> Property(record, Identifier) {
  let node = string()
  let root =
    Root(
      schema.FieldSchema(schema.Identifier, node.identifiers),
      node.definitions,
      [],
      fn(mode, value) {
        case mode, value {
          _, Assigned(value) -> Ok(Some(types.StringValue(value)))
          Construction, Generate -> Ok(None)
          Snapshot, Generate ->
            Error(types.InvalidEdit(
              [key],
              "Snapshot identifier must be assigned",
            ))
        }
      },
      fn(value) {
        case value {
          Some(types.StringValue(value)) -> Ok(Assigned(value))
          _ -> mismatch()
        }
      },
    )
  Property(key, root, fn(mode, record) { root.encode(mode, get(record)) })
}

fn object_property(property: Property(record, a)) -> ObjectProperty(record) {
  ObjectProperty(
    property.key,
    property.root.field,
    property.root.definitions,
    property.root.errors,
    property.encode,
  )
}

pub fn property(property: Property(record, a)) -> ObjectProperty(record) {
  object_property(property)
}

pub fn read_property(
  reader: ObjectReader(record),
  property: Property(record, a),
) -> Result(a, TreeError) {
  use definition <- result.try(
    list.key_find(reader.properties, property.key)
    |> result.map_error(fn(_) {
      types.InvalidSchema("Undeclared object property: " <> property.key)
    }),
  )
  case definition == property.root.field {
    True -> decode_property(property, reader.fields)
    False ->
      Error(types.InvalidSchema(
        "Object property definition does not match: " <> property.key,
      ))
  }
}

fn decode_property(
  property: Property(record, a),
  fields: List(#(String, TreeValue)),
) -> Result(a, TreeError) {
  let value = case list.key_find(fields, property.key) {
    Ok(value) -> Some(value)
    Error(Nil) -> None
  }
  property.root.decode(value)
}

pub fn object(
  factory: Factory,
  name: String,
  properties: List(ObjectProperty(record)),
  construct: fn(ObjectReader(record)) -> Result(record, TreeError),
) -> Node(record) {
  object_codec(factory, name, properties, fn(fields) {
    construct(ObjectReader(
      fields,
      list.map(properties, fn(property) { #(property.key, property.field) }),
    ))
  })
}

fn object_codec(
  factory: Factory,
  name: String,
  properties: List(ObjectProperty(record)),
  decode: fn(List(#(String, TreeValue))) -> Result(record, TreeError),
) -> Node(record) {
  let identifier = factory.scope <> "." <> name
  let fields = list.map(properties, fn(p) { #(p.key, p.field) }) |> sort_entries
  let duplicate_errors = case
    list.length(list.unique(list.map(fields, fn(f) { f.0 })))
    == list.length(fields)
  {
    True -> []
    False -> [types.InvalidSchema("Duplicate object property")]
  }
  Node(
    [identifier],
    [
      Concrete(
        identifier,
        schema.Object(fields),
        list.flat_map(properties, fn(p) { p.definitions }),
      ),
    ],
    list.flatten([
      name_errors(factory, name),
      duplicate_errors,
      list.flat_map(properties, fn(p) { p.errors }),
    ]),
    fn(mode, value) {
      use fields <- result.try(
        properties
        |> list.try_map(fn(p) {
          result.map(p.encode(mode, value), fn(encoded) {
            option.map(encoded, fn(encoded) { #(p.key, encoded) })
          })
        }),
      )
      Ok(types.ObjectValue(
        identifier,
        fields |> list.filter_map(option.to_result(_, Nil)) |> sort_entries,
      ))
    },
    fn(value) {
      case value {
        types.ObjectValue(actual, fields) if actual == identifier ->
          decode(fields)
        _ -> mismatch()
      }
    },
  )
}

pub fn object0(factory: Factory, name: String) -> Node(Nil) {
  object_codec(factory, name, [], fn(fields) {
    case fields {
      [] -> Ok(Nil)
      _ -> mismatch()
    }
  })
}

pub fn object1(
  factory: Factory,
  name: String,
  construct: fn(a) -> record,
  p1: Property(record, a),
) -> Node(record) {
  object_codec(factory, name, [object_property(p1)], fn(fields) {
    use a <- result.try(decode_property(p1, fields))
    Ok(construct(a))
  })
}

pub fn object2(
  factory: Factory,
  name: String,
  construct: fn(a, b) -> record,
  p1: Property(record, a),
  p2: Property(record, b),
) -> Node(record) {
  object_codec(
    factory,
    name,
    [object_property(p1), object_property(p2)],
    fn(fields) {
      use a <- result.try(decode_property(p1, fields))
      use b <- result.try(decode_property(p2, fields))
      Ok(construct(a, b))
    },
  )
}

pub fn object3(
  factory: Factory,
  name: String,
  construct: fn(a, b, c) -> record,
  p1: Property(record, a),
  p2: Property(record, b),
  p3: Property(record, c),
) -> Node(record) {
  object_codec(
    factory,
    name,
    [object_property(p1), object_property(p2), object_property(p3)],
    fn(fields) {
      use a <- result.try(decode_property(p1, fields))
      use b <- result.try(decode_property(p2, fields))
      use c <- result.try(decode_property(p3, fields))
      Ok(construct(a, b, c))
    },
  )
}

pub fn object4(
  factory: Factory,
  name: String,
  construct: fn(a, b, c, d) -> record,
  p1: Property(record, a),
  p2: Property(record, b),
  p3: Property(record, c),
  p4: Property(record, d),
) -> Node(record) {
  object_codec(
    factory,
    name,
    [
      object_property(p1),
      object_property(p2),
      object_property(p3),
      object_property(p4),
    ],
    fn(fields) {
      use a <- result.try(decode_property(p1, fields))
      use b <- result.try(decode_property(p2, fields))
      use c <- result.try(decode_property(p3, fields))
      use d <- result.try(decode_property(p4, fields))
      Ok(construct(a, b, c, d))
    },
  )
}

pub fn object5(
  factory: Factory,
  name: String,
  construct: fn(a, b, c, d, e) -> record,
  p1: Property(record, a),
  p2: Property(record, b),
  p3: Property(record, c),
  p4: Property(record, d),
  p5: Property(record, e),
) -> Node(record) {
  object_codec(
    factory,
    name,
    [
      object_property(p1),
      object_property(p2),
      object_property(p3),
      object_property(p4),
      object_property(p5),
    ],
    fn(fields) {
      use a <- result.try(decode_property(p1, fields))
      use b <- result.try(decode_property(p2, fields))
      use c <- result.try(decode_property(p3, fields))
      use d <- result.try(decode_property(p4, fields))
      use e <- result.try(decode_property(p5, fields))
      Ok(construct(a, b, c, d, e))
    },
  )
}

pub fn object6(
  factory: Factory,
  name: String,
  construct: fn(a, b, c, d, e, f) -> record,
  p1: Property(record, a),
  p2: Property(record, b),
  p3: Property(record, c),
  p4: Property(record, d),
  p5: Property(record, e),
  p6: Property(record, f),
) -> Node(record) {
  object_codec(
    factory,
    name,
    [
      object_property(p1),
      object_property(p2),
      object_property(p3),
      object_property(p4),
      object_property(p5),
      object_property(p6),
    ],
    fn(fields) {
      use a <- result.try(decode_property(p1, fields))
      use b <- result.try(decode_property(p2, fields))
      use c <- result.try(decode_property(p3, fields))
      use d <- result.try(decode_property(p4, fields))
      use e <- result.try(decode_property(p5, fields))
      use f <- result.try(decode_property(p6, fields))
      Ok(construct(a, b, c, d, e, f))
    },
  )
}

pub fn object7(
  factory: Factory,
  name: String,
  construct: fn(a, b, c, d, e, f, g) -> record,
  p1: Property(record, a),
  p2: Property(record, b),
  p3: Property(record, c),
  p4: Property(record, d),
  p5: Property(record, e),
  p6: Property(record, f),
  p7: Property(record, g),
) -> Node(record) {
  object_codec(
    factory,
    name,
    [
      object_property(p1),
      object_property(p2),
      object_property(p3),
      object_property(p4),
      object_property(p5),
      object_property(p6),
      object_property(p7),
    ],
    fn(fields) {
      use a <- result.try(decode_property(p1, fields))
      use b <- result.try(decode_property(p2, fields))
      use c <- result.try(decode_property(p3, fields))
      use d <- result.try(decode_property(p4, fields))
      use e <- result.try(decode_property(p5, fields))
      use f <- result.try(decode_property(p6, fields))
      use g <- result.try(decode_property(p7, fields))
      Ok(construct(a, b, c, d, e, f, g))
    },
  )
}

pub fn object8(
  factory: Factory,
  name: String,
  construct: fn(a, b, c, d, e, f, g, h) -> record,
  p1: Property(record, a),
  p2: Property(record, b),
  p3: Property(record, c),
  p4: Property(record, d),
  p5: Property(record, e),
  p6: Property(record, f),
  p7: Property(record, g),
  p8: Property(record, h),
) -> Node(record) {
  object_codec(
    factory,
    name,
    [
      object_property(p1),
      object_property(p2),
      object_property(p3),
      object_property(p4),
      object_property(p5),
      object_property(p6),
      object_property(p7),
      object_property(p8),
    ],
    fn(fields) {
      use a <- result.try(decode_property(p1, fields))
      use b <- result.try(decode_property(p2, fields))
      use c <- result.try(decode_property(p3, fields))
      use d <- result.try(decode_property(p4, fields))
      use e <- result.try(decode_property(p5, fields))
      use f <- result.try(decode_property(p6, fields))
      use g <- result.try(decode_property(p7, fields))
      use h <- result.try(decode_property(p8, fields))
      Ok(construct(a, b, c, d, e, f, g, h))
    },
  )
}

fn mismatch() -> Result(a, TreeError) {
  Error(types.CorruptData("typed snapshot", "Unexpected node value"))
}

fn leaf(
  name: String,
  kind: schema.LeafKind,
  encode: fn(a) -> TreeValue,
  decode: fn(TreeValue) -> Result(a, TreeError),
) -> Node(a) {
  let identifier = "com.fluidframework.leaf." <> name
  Node(
    [identifier],
    [Concrete(identifier, schema.Leaf(kind), [])],
    [],
    fn(_, value) { Ok(encode(value)) },
    decode,
  )
}

pub opaque type Variant(sum) {
  Variant(
    identifiers: List(String),
    definitions: List(Definition),
    errors: List(TreeError),
    encode: fn(EncodeMode, sum) -> Result(Option(TreeValue), TreeError),
    decode: fn(TreeValue) -> Result(sum, TreeError),
  )
}

pub fn variant(
  node: Node(a),
  inject: fn(a) -> sum,
  project: fn(sum) -> Option(a),
) -> Variant(sum) {
  Variant(
    node.identifiers,
    node.definitions,
    node.errors,
    fn(mode, value) {
      case project(value) {
        None -> Ok(None)
        Some(value) -> result.map(node.encode(mode, value), Some)
      }
    },
    fn(value) { result.map(node.decode(value), inject) },
  )
}

pub fn union(variants: List(Variant(sum))) -> Node(sum) {
  let identifiers = list.flat_map(variants, fn(v) { v.identifiers })
  let errors = case variants {
    [] -> [types.InvalidSchema("Union must have at least one variant")]
    _ ->
      case list.length(identifiers) == list.length(list.unique(identifiers)) {
        True -> []
        False -> [types.InvalidSchema("Union variants have overlapping types")]
      }
  }
  Node(
    list.sort(identifiers, string.compare),
    list.flat_map(variants, fn(v) { v.definitions }),
    list.append(errors, list.flat_map(variants, fn(v) { v.errors })),
    fn(mode, value) {
      use matches <- result.try(
        list.try_map(variants, fn(v) { v.encode(mode, value) }),
      )
      case list.filter_map(matches, option.to_result(_, Nil)) {
        [value] -> Ok(value)
        _ ->
          Error(types.InvalidEdit(
            [],
            "Union value must match exactly one variant",
          ))
      }
    },
    fn(value) {
      let identifier = schema.value_identifier(value)
      use variant <- result.try(
        list.find(variants, fn(v) { list.contains(v.identifiers, identifier) })
        |> result.map_error(fn(_) {
          types.CorruptData("typed snapshot", "Unknown union variant")
        }),
      )
      variant.decode(value)
    },
  )
}

pub fn lazy(
  factory: Factory,
  name: String,
  resolve: fn() -> Node(a),
) -> Node(a) {
  let identifier = factory.scope <> "." <> name
  Node(
    [identifier],
    [
      Deferred(identifier, fn() {
        let node = resolve()
        Resolution(node.identifiers, node.definitions, node.errors)
      }),
    ],
    name_errors(factory, name),
    fn(mode, value) { resolve().encode(mode, value) },
    fn(value) { resolve().decode(value) },
  )
}

pub fn string() -> Node(String) {
  leaf("string", schema.StringLeaf, types.StringValue, fn(value) {
    case value {
      types.StringValue(value) -> Ok(value)
      _ -> mismatch()
    }
  })
}

pub fn number() -> Node(Float) {
  leaf("number", schema.NumberLeaf, types.NumberValue, fn(value) {
    case value {
      types.NumberValue(value) -> Ok(value)
      _ -> mismatch()
    }
  })
}

pub fn boolean() -> Node(Bool) {
  leaf("boolean", schema.BooleanLeaf, types.BooleanValue, fn(value) {
    case value {
      types.BooleanValue(value) -> Ok(value)
      _ -> mismatch()
    }
  })
}

pub fn null() -> Node(Nil) {
  leaf("null", schema.NullLeaf, fn(_) { types.NullValue }, fn(value) {
    case value {
      types.NullValue -> Ok(Nil)
      _ -> mismatch()
    }
  })
}

pub fn handle() -> Node(handle.Reference) {
  leaf("handle", schema.HandleLeaf, types.HandleValue, fn(value) {
    case value {
      types.HandleValue(value) -> Ok(value)
      _ -> mismatch()
    }
  })
}

pub fn array(
  factory: Factory,
  name: String,
  element: Node(a),
) -> Node(List(a)) {
  let identifier = factory.scope <> "." <> name
  Node(
    [identifier],
    [
      Concrete(
        identifier,
        schema.Array(schema.FieldSchema(schema.Sequence, element.identifiers)),
        element.definitions,
      ),
    ],
    list.append(name_errors(factory, name), element.errors),
    fn(mode, values) {
      result.map(
        list.try_map(values, element.encode(mode, _)),
        types.ArrayValue(identifier, _),
      )
    },
    fn(value) {
      case value {
        types.ArrayValue(actual, values) if actual == identifier ->
          list.try_map(values, element.decode)
        _ -> mismatch()
      }
    },
  )
}

pub fn map(
  factory: Factory,
  name: String,
  value: Node(a),
) -> Node(Dict(String, a)) {
  let identifier = factory.scope <> "." <> name
  Node(
    [identifier],
    [
      Concrete(
        identifier,
        schema.Map(schema.FieldSchema(schema.Optional, value.identifiers)),
        value.definitions,
      ),
    ],
    list.append(name_errors(factory, name), value.errors),
    fn(mode, values) {
      use entries <- result.try(
        values
        |> dict.to_list
        |> sort_entries
        |> list.try_map(fn(entry) {
          result.map(value.encode(mode, entry.1), fn(value) {
            #(entry.0, value)
          })
        }),
      )
      Ok(types.MapValue(identifier, entries))
    },
    fn(snapshot) {
      case snapshot {
        types.MapValue(actual, entries) if actual == identifier -> {
          use entries <- result.try(
            list.try_map(entries, fn(entry) {
              result.map(value.decode(entry.1), fn(value) { #(entry.0, value) })
            }),
          )
          Ok(dict.from_list(entries))
        }
        _ -> mismatch()
      }
    },
  )
}

pub fn root(node: Node(a)) -> Root(a) {
  Root(
    schema.FieldSchema(schema.Required, node.identifiers),
    node.definitions,
    node.errors,
    fn(mode, value) { result.map(node.encode(mode, value), Some) },
    fn(value) {
      case value {
        Some(value) -> node.decode(value)
        None -> mismatch()
      }
    },
  )
}

pub fn optional_root(node: Node(a)) -> Root(Option(a)) {
  Root(
    schema.FieldSchema(schema.Optional, node.identifiers),
    node.definitions,
    node.errors,
    fn(mode, value) {
      case value {
        None -> Ok(None)
        Some(value) -> result.map(node.encode(mode, value), Some)
      }
    },
    fn(value) {
      case value {
        Some(value) -> result.map(node.decode(value), Some)
        None -> Ok(None)
      }
    },
  )
}

pub fn compile(root: Root(a)) -> Result(Compiled(a), TreeError) {
  use _ <- result.try(case root.errors {
    [error, ..] -> Error(error)
    [] -> Ok(Nil)
  })
  use graph <- result.try(collect_definitions(
    root.definitions,
    Graph(dict.new(), dict.new()),
  ))
  let document =
    json.object([
      #("version", json.int(2)),
      #(
        "nodes",
        json.object(
          graph.definitions
          |> dict.to_list
          |> sort_entries
          |> list.map(fn(entry) { #(entry.0, render_node(entry.1)) }),
        ),
      ),
      #("root", render_field(root.field)),
    ])
  use stored <- result.try(schema.stored_from_json(document))
  use view <- result.try(schema.view_from_json(document))
  Ok(Compiled(stored, view, root.encode, root.decode))
}

type Visit {
  Visiting
  Visited
}

type Graph {
  Graph(
    definitions: Dict(String, schema.NodeSchema),
    visits: Dict(String, Visit),
  )
}

fn collect_definitions(
  definitions: List(Definition),
  graph: Graph,
) -> Result(Graph, TreeError) {
  list.try_fold(definitions, graph, collect_definition)
}

fn collect_definition(
  graph: Graph,
  definition: Definition,
) -> Result(Graph, TreeError) {
  case definition {
    Deferred(identifier, resolve) -> {
      let resolved = resolve()
      use _ <- result.try(case resolved.errors {
        [error, ..] -> Error(error)
        [] -> Ok(Nil)
      })
      case resolved.identifiers, resolved.definitions {
        [actual], [Concrete(named, node, _) as concrete]
          if actual == identifier && named == identifier
        ->
          case node {
            schema.Leaf(_) ->
              Error(types.InvalidSchema(
                "Lazy schema must resolve to a named container",
              ))
            _ ->
              case dict.get(graph.visits, identifier) {
                Ok(Visiting) -> check_finite_definition(graph, concrete)
                Ok(Visited) | Error(Nil) -> {
                  let graph =
                    Graph(
                      ..graph,
                      visits: dict.insert(graph.visits, identifier, Visiting),
                    )
                  use graph <- result.try(collect_definition(graph, concrete))
                  Ok(
                    Graph(
                      ..graph,
                      visits: dict.insert(graph.visits, identifier, Visited),
                    ),
                  )
                }
              }
          }
        _, _ ->
          Error(types.InvalidSchema(
            "Lazy schema must resolve to its declared named container: "
            <> identifier,
          ))
      }
    }
    Concrete(identifier, node, children) -> {
      use graph <- result.try(check_definition(graph, identifier, node))
      // Check each finite declaration. Only deferred edges expand the graph.
      collect_definitions(children, graph)
    }
  }
}

fn check_finite_definition(
  graph: Graph,
  definition: Definition,
) -> Result(Graph, TreeError) {
  case definition {
    Deferred(_, _) -> Ok(graph)
    Concrete(identifier, node, children) -> {
      use graph <- result.try(check_definition(graph, identifier, node))
      list.try_fold(children, graph, check_finite_definition)
    }
  }
}

fn check_definition(
  graph: Graph,
  identifier: String,
  node: schema.NodeSchema,
) -> Result(Graph, TreeError) {
  let node = normalize(node)
  case dict.get(graph.definitions, identifier) {
    Ok(existing) if existing != node ->
      Error(types.InvalidSchema("Conflicting node definition: " <> identifier))
    Ok(_) | Error(Nil) ->
      Ok(
        Graph(
          ..graph,
          definitions: dict.insert(graph.definitions, identifier, node),
        ),
      )
  }
}

pub fn stored(compiled: Compiled(a)) -> schema.StoredSchema {
  compiled.stored
}

pub fn view(compiled: Compiled(a)) -> schema.ViewSchema {
  compiled.view
}

@internal
pub fn property_root(property: Property(record, a)) -> Root(a) {
  let root = property.root
  case root.field.cardinality {
    schema.Identifier ->
      Root(
        ..root,
        field: schema.FieldSchema(schema.Required, root.field.allowed_types),
      )
    _ -> root
  }
}

@internal
pub fn property_definition(
  property: Property(record, a),
) -> #(String, schema.FieldSchema) {
  #(property.key, property.root.field)
}

@internal
pub fn allowed_types(node: Node(a)) -> List(String) {
  node.identifiers
}

@internal
pub fn root_cardinality(compiled: Compiled(a)) -> schema.Cardinality {
  schema.root_field_schema(compiled.stored).cardinality
}

pub fn encode(
  compiled: Compiled(a),
  value: a,
) -> Result(Option(TreeValue), TreeError) {
  use encoded <- result.try(compiled.encode(Snapshot, value))
  use _ <- result.try(schema.validate_root_field(compiled.stored, encoded))
  Ok(encoded)
}

pub fn encode_new(
  compiled: Compiled(a),
  value: a,
) -> Result(Option(TreeValue), TreeError) {
  use encoded <- result.try(compiled.encode(Construction, value))
  use _ <- result.try(schema.validate_root_construction(
    compiled.stored,
    encoded,
  ))
  Ok(encoded)
}

pub fn decode(
  compiled: Compiled(a),
  value: Option(TreeValue),
) -> Result(a, TreeError) {
  use _ <- result.try(schema.validate_root_field(compiled.stored, value))
  compiled.decode(value)
}

fn sort_entries(entries: List(#(String, a))) -> List(#(String, a)) {
  list.sort(entries, fn(a, b) { string.compare(a.0, b.0) })
}

fn normalize(node: schema.NodeSchema) -> schema.NodeSchema {
  case node {
    schema.Object(fields) -> schema.Object(sort_entries(fields))
    _ -> node
  }
}

fn render_field(field: schema.FieldSchema) -> json.Json {
  let kind = case field.cardinality {
    schema.Required -> "Value"
    schema.Optional -> "Optional"
    schema.Sequence -> "Sequence"
    schema.Identifier -> "Identifier"
  }
  json.object([
    #("kind", json.string(kind)),
    #("types", json.array(field.allowed_types, json.string)),
  ])
}

fn render_node(node: schema.NodeSchema) -> json.Json {
  let kind = case node {
    schema.Leaf(kind) -> {
      let code = case kind {
        schema.NumberLeaf -> 0
        schema.StringLeaf -> 1
        schema.BooleanLeaf -> 2
        schema.HandleLeaf -> 3
        schema.NullLeaf -> 4
      }
      json.object([#("leaf", json.int(code))])
    }
    schema.Object(fields) ->
      json.object([
        #(
          "object",
          json.object(
            list.map(fields, fn(entry) { #(entry.0, render_field(entry.1)) }),
          ),
        ),
      ])
    schema.Array(elements) ->
      json.object([#("object", json.object([#("", render_field(elements))]))])
    schema.Map(entries) -> json.object([#("map", render_field(entries))])
  }
  json.object([#("kind", kind)])
}
