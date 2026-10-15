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

pub opaque type Node(a) {
  Node(
    identifier: String,
    definitions: List(#(String, schema.NodeSchema)),
    errors: List(TreeError),
    encode: fn(a) -> TreeValue,
    decode: fn(TreeValue) -> Result(a, TreeError),
  )
}

pub opaque type Root(a) {
  Root(
    field: schema.FieldSchema,
    definitions: List(#(String, schema.NodeSchema)),
    errors: List(TreeError),
    encode: fn(a) -> Option(TreeValue),
    decode: fn(Option(TreeValue)) -> Result(a, TreeError),
  )
}

pub opaque type Compiled(a) {
  Compiled(
    stored: schema.StoredSchema,
    view: schema.ViewSchema,
    encode: fn(a) -> Option(TreeValue),
    decode: fn(Option(TreeValue)) -> Result(a, TreeError),
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
  Node(identifier, [#(identifier, schema.Leaf(kind))], [], encode, decode)
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
    identifier,
    [
      #(
        identifier,
        schema.Array(schema.FieldSchema(schema.Sequence, [element.identifier])),
      ),
      ..element.definitions
    ],
    list.append(name_errors(factory, name), element.errors),
    fn(values) {
      types.ArrayValue(identifier, list.map(values, element.encode))
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
    identifier,
    [
      #(
        identifier,
        schema.Map(schema.FieldSchema(schema.Optional, [value.identifier])),
      ),
      ..value.definitions
    ],
    list.append(name_errors(factory, name), value.errors),
    fn(values) {
      types.MapValue(
        identifier,
        values
          |> dict.to_list
          |> sort_entries
          |> list.map(fn(entry) { #(entry.0, value.encode(entry.1)) }),
      )
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
    schema.FieldSchema(schema.Required, [node.identifier]),
    node.definitions,
    node.errors,
    fn(value) { Some(node.encode(value)) },
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
    schema.FieldSchema(schema.Optional, [node.identifier]),
    node.definitions,
    node.errors,
    fn(value) { option.map(value, node.encode) },
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
  use definitions <- result.try(
    list.try_fold(root.definitions, dict.new(), fn(definitions, entry) {
      let #(identifier, definition) = entry
      let definition = normalize(definition)
      case dict.get(definitions, identifier) {
        Ok(existing) if existing != definition ->
          Error(types.InvalidSchema(
            "Conflicting node definition: " <> identifier,
          ))
        Ok(_) | Error(Nil) ->
          Ok(dict.insert(definitions, identifier, definition))
      }
    }),
  )
  let document =
    json.object([
      #("version", json.int(2)),
      #(
        "nodes",
        json.object(
          definitions
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

pub fn stored(compiled: Compiled(a)) -> schema.StoredSchema {
  compiled.stored
}

pub fn view(compiled: Compiled(a)) -> schema.ViewSchema {
  compiled.view
}

pub fn encode(
  compiled: Compiled(a),
  value: a,
) -> Result(Option(TreeValue), TreeError) {
  let encoded = compiled.encode(value)
  use _ <- result.try(schema.validate_root_field(compiled.stored, encoded))
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
