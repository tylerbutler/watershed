import gleam/float
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import watershed/fluid_ids
import watershed/json_ot.{
  type JsonValue, NFloat, NInt, VArray, VBool, VNull, VNumber, VObject, VString,
}
import watershed/tree/change_fixture_codec as codec
import watershed/tree/forest
import watershed/tree/schema
import watershed/tree/types

const string_leaf = "com.fluidframework.leaf.string"

const number_leaf = "com.fluidframework.leaf.number"

const boolean_leaf = "com.fluidframework.leaf.boolean"

const null_leaf = "com.fluidframework.leaf.null"

const items_type = "org.watershed.shared-tree.m3.Items"

const array_map_type = "org.watershed.shared-tree.m3.ArrayMap"

const point_type = "org.watershed.shared-tree.m3.Point"

const points_type = "org.watershed.shared-tree.m3.Points"

const root_type = "org.watershed.shared-tree.m3.Root"

pub fn run(input: Json) -> Result(Json, String) {
  use input <- result.try(codec.parse(input))
  use _ <- result.try(codec.exact(input, ["profile", "schemas", "scenarios"]))
  use profile <- result.try(codec.get(input, "profile"))
  use _ <- result.try(codec.exact(profile, ["schema", "forest"]))
  use schema_version <- result.try(codec.field(profile, "schema", codec.integer))
  use forest_version <- result.try(codec.field(profile, "forest", codec.integer))
  use _ <- result.try(require(
    schema_version == 2 && forest_version == 2,
    "unsupported array schema-content profile",
  ))
  use schemas <- result.try(codec.get(input, "schemas"))
  use scenarios <- result.try(codec.field(input, "scenarios", codec.items))
  use observations <- result.try(
    list.try_map(scenarios, observe_scenario(_, schemas)),
  )
  Ok(
    json.object([
      #("observations", json.array(observations, fn(value) { value })),
    ]),
  )
}

fn observe_scenario(
  value: JsonValue,
  schemas: JsonValue,
) -> Result(Json, String) {
  use id <- result.try(codec.field(value, "id", codec.text))
  use operation <- result.try(codec.field(value, "operation", codec.text))
  use schema_name <- result.try(codec.field(value, "schema", codec.text))
  use schema_bytes <- result.try(codec.field(value, "schemaBytes", codec.text))
  use declared <- result.try(codec.field(schemas, schema_name, codec.text))
  use _ <- result.try(require(
    declared == schema_bytes,
    id <> ": schema bytes do not match the named schema",
  ))
  use stored <- result.try(
    schema.stored_from_string(schema_bytes) |> result.map_error(string.inspect),
  )
  use initial <- result.try(codec.get(value, "initialState"))
  use root <- result.try(decode_field(
    stored,
    schema.root_field_schema(stored),
    initial,
  ))
  use state <- result.try(
    forest.new(array_fixture_view_id(), stored, Some(root))
    |> result.map_error(string.inspect),
  )
  use result_value <- result.try(case operation {
    "schema" ->
      Ok(
        json.object([
          #("schema", schema.stored_to_json(stored)),
          #("content", value_json(root, True)),
        ]),
      )
    "read" -> {
      use path <- result.try(
        codec.field(value, "path", fn(value) { codec.many(value, codec.text) }),
      )
      use found <- result.try(
        forest.read(state, path) |> result.map_error(string.inspect),
      )
      use found <- result.try(case found {
        Some(found) -> Ok(found)
        None -> Error(id <> ": read path is absent")
      })
      Ok(
        json.object([
          #("value", value_json(found, False)),
          #("container", value_json(root, True)),
        ]),
      )
    }
    "move" -> observe_move(value, stored, state)
    "initialize" ->
      Ok(
        json.object([
          #("content", value_json(root, True)),
          #(
            "compatibility",
            compatibility(True, schema_bytes == declared, True),
          ),
        ]),
      )
    "canView" -> {
      use view_name <- result.try(codec.field(value, "viewSchema", codec.text))
      use view_bytes <- result.try(codec.field(
        value,
        "viewSchemaBytes",
        codec.text,
      ))
      use named_view <- result.try(codec.field(schemas, view_name, codec.text))
      use _ <- result.try(require(
        named_view == view_bytes,
        id <> ": view bytes do not match the named schema",
      ))
      use view <- result.try(
        schema.view_from_string(view_bytes) |> result.map_error(string.inspect),
      )
      let can_view = schema.can_view(stored, view) == Ok(Nil)
      Ok(
        json.object([
          #("storedSchema", json.string(schema_name)),
          #("viewSchema", json.string(view_name)),
          #(
            "compatibility",
            compatibility(can_view, schema_bytes == view_bytes, True),
          ),
          #("content", value_json(root, True)),
        ]),
      )
    }
    "summarize" -> {
      use forest_bytes <- result.try(compressed_forest(root))
      Ok(
        json.object([
          #("schema", json.string(schema_bytes)),
          #("forest", json.string(forest_bytes)),
        ]),
      )
    }
    other -> Error(id <> ": unsupported operation " <> other)
  })
  Ok(
    json.object(case operation {
      "move" -> [
        #("id", json.string(id)),
        #("accepted", json.bool(False)),
        #("result", result_value),
      ]
      _ -> [#("id", json.string(id)), #("result", result_value)]
    }),
  )
}

fn observe_move(
  value: JsonValue,
  stored: schema.StoredSchema,
  state: forest.Forest,
) -> Result(Json, String) {
  use source <- result.try(codec.get(value, "source"))
  use destination <- result.try(codec.get(value, "destination"))
  use source_path <- result.try(
    codec.field(source, "path", fn(value) { codec.many(value, codec.text) }),
  )
  use start <- result.try(codec.field(source, "start", codec.integer))
  use end <- result.try(codec.field(source, "end", codec.integer))
  use _ <- result.try(require(
    start >= 0 && end >= start,
    "move source range is invalid",
  ))
  use destination_path <- result.try(
    codec.field(destination, "path", fn(value) { codec.many(value, codec.text) }),
  )
  use source_values <- result.try(
    forest.array_values(state, source_path) |> result.map_error(string.inspect),
  )
  use destination_type <- result.try(
    forest.array_type(state, destination_path)
    |> result.map_error(string.inspect),
  )
  let moved = source_values |> list.drop(start) |> list.take(end - start)
  case schema.validate_array_elements(stored, destination_type, moved) {
    Ok(Nil) -> Ok(json.object([#("accepted", json.bool(True))]))
    Error(types.InvalidEdit(_, detail)) -> {
      let type_id =
        detail
        |> string.split("node type is not allowed: ")
        |> list.last
        |> result.unwrap(detail)
      Ok(
        json.object([
          #("accepted", json.bool(False)),
          #(
            "error",
            json.string(
              "Error: Type "
              <> type_id
              <> " in source sequence is not allowed in destination.",
            ),
          ),
        ]),
      )
    }
    Error(error) -> Error(string.inspect(error))
  }
}

fn compatibility(can_view: Bool, equivalent: Bool, has_content: Bool) -> Json {
  json.object([
    #("canView", json.bool(can_view)),
    #("canUpgrade", json.bool(can_view)),
    #("isEquivalent", json.bool(equivalent)),
    #("canInitialize", json.bool(!has_content)),
  ])
}

fn decode_field(
  stored: schema.StoredSchema,
  field: schema.FieldSchema,
  value: JsonValue,
) -> Result(types.TreeValue, String) {
  decode_allowed(stored, field.allowed_types, value)
}

fn decode_allowed(
  stored: schema.StoredSchema,
  allowed: List(String),
  value: JsonValue,
) -> Result(types.TreeValue, String) {
  case allowed {
    [] -> Error("value does not match an allowed schema")
    [type_id, ..rest] ->
      case decode_type(stored, type_id, value) {
        Ok(decoded) -> Ok(decoded)
        Error(_) -> decode_allowed(stored, rest, value)
      }
  }
}

fn decode_type(
  stored: schema.StoredSchema,
  type_id: String,
  value: JsonValue,
) -> Result(types.TreeValue, String) {
  case type_id, value {
    type_id, VString(value) if type_id == string_leaf ->
      Ok(types.StringValue(value))
    type_id, VBool(value) if type_id == boolean_leaf ->
      Ok(types.BooleanValue(value))
    type_id, VNull if type_id == null_leaf -> Ok(types.NullValue)
    type_id, VNumber(number) if type_id == number_leaf ->
      number_float(number) |> result.map(types.NumberValue)
    _, _ -> {
      use node <- result.try(
        schema.node_schema(stored, type_id) |> result.map_error(string.inspect),
      )
      case node, value {
        schema.Array(elements), VArray(values) -> {
          use values <- result.try(
            list.try_map(values, decode_field(stored, elements, _)),
          )
          Ok(types.ArrayValue(type_id, values))
        }
        schema.Map(entries), VObject([#("map", VArray(values))]) -> {
          use entries <- result.try(
            list.try_map(values, fn(value) {
              use pair <- result.try(codec.pair(value))
              use key <- result.try(codec.text(pair.0))
              use value <- result.try(decode_field(stored, entries, pair.1))
              Ok(#(key, value))
            }),
          )
          Ok(types.MapValue(type_id, entries))
        }
        schema.Object(_), VObject([#("point", VObject(fields))])
          if type_id == point_type
        -> decode_object(stored, type_id, fields)
        schema.Object(_), VObject(fields) ->
          decode_object(stored, type_id, fields)
        _, _ -> Error("value does not match " <> type_id)
      }
    }
  }
}

fn decode_object(
  stored: schema.StoredSchema,
  type_id: String,
  fields: List(#(String, JsonValue)),
) -> Result(types.TreeValue, String) {
  use fields <- result.try(
    list.try_map(fields, fn(field) {
      use definition <- result.try(
        schema.field_schema(stored, type_id, field.0)
        |> result.map_error(string.inspect),
      )
      use value <- result.try(decode_field(stored, definition, field.1))
      Ok(#(field.0, value))
    }),
  )
  let value = types.ObjectValue(type_id, fields)
  use _ <- result.try(
    schema.validate_subtree(stored, value) |> result.map_error(string.inspect),
  )
  Ok(value)
}

fn number_float(value: json_ot.Number) -> Result(Float, String) {
  case value {
    NFloat(value) -> Ok(value)
    NInt(value) ->
      float.parse(int.to_string(value) <> ".0")
      |> result.map_error(fn(_) { "number is outside the finite range" })
  }
}

fn value_json(value: types.TreeValue, root: Bool) -> Json {
  case value {
    types.StringValue(value) -> json.string(value)
    types.NumberValue(value) -> json.float(value)
    types.BooleanValue(value) -> json.bool(value)
    types.NullValue -> json.null()
    types.ArrayValue(_, elements) -> json.array(elements, value_json(_, False))
    types.MapValue(_, entries) ->
      json.object([
        #(
          "map",
          json.array(entries, fn(entry) {
            json.array(
              [json.string(entry.0), value_json(entry.1, False)],
              fn(value) { value },
            )
          }),
        ),
      ])
    types.ObjectValue(schema_id, fields) -> {
      let object =
        json.object(
          list.map(fields, fn(field) { #(field.0, value_json(field.1, False)) }),
        )
      case root || schema_id != point_type {
        True -> object
        False -> json.object([#("point", object)])
      }
    }
  }
}

fn compressed_forest(root: types.TreeValue) -> Result(String, String) {
  use data <- result.try(compressed_root(root))
  Ok(
    json.object([
      #("keys", json.array(["rootFieldKey"], json.string)),
      #(
        "fields",
        json.object([
          #("version", json.int(2)),
          #("identifiers", json.array([""], json.string)),
          #("shapes", compressed_shapes()),
          #(
            "data",
            json.array([json.array(data, fn(value) { value })], fn(value) {
              value
            }),
          ),
        ]),
      ),
      #("version", json.int(2)),
    ])
    |> json.to_string,
  )
}

fn compressed_shapes() -> Json {
  json.array(
    [
      shape_node(string_leaf, True, [], None),
      shape_node(items_type, False, [#(json.int(0), 4)], None),
      shape_node(
        point_type,
        False,
        [
          #(json.string("label"), 0),
          #(json.string("x"), 7),
        ],
        None,
      ),
      shape_node(array_map_type, False, [], Some(4)),
      json.object([#("a", json.int(6))]),
      shape_node(
        root_type,
        False,
        [
          #(json.string("left"), 1),
          #(json.string("right"), 1),
          #(json.string("byKey"), 3),
          #(json.string("narrow"), 8),
        ],
        None,
      ),
      json.object([#("d", json.int(0))]),
      shape_node(number_leaf, True, [], None),
      shape_node(points_type, False, [#(json.int(0), 9)], None),
      json.object([#("a", json.int(2))]),
    ],
    fn(value) { value },
  )
}

fn shape_node(
  type_id: String,
  value: Bool,
  fields: List(#(Json, Int)),
  extra_fields: Option(Int),
) -> Json {
  let members = [
    #("type", json.string(type_id)),
    #("value", json.bool(value)),
  ]
  let members = case fields {
    [] -> members
    _ ->
      list.append(members, [
        #(
          "fields",
          json.array(fields, fn(field) {
            json.array([field.0, json.int(field.1)], fn(value) { value })
          }),
        ),
      ])
  }
  let members = case extra_fields {
    None -> members
    Some(shape) -> list.append(members, [#("extraFields", json.int(shape))])
  }
  json.object([#("c", json.object(members))])
}

fn compressed_root(root: types.TreeValue) -> Result(List(Json), String) {
  case root {
    types.ObjectValue(schema_id, fields) if schema_id == root_type -> {
      use left <- result.try(object_field(fields, "left"))
      use right <- result.try(object_field(fields, "right"))
      use by_key <- result.try(object_field(fields, "byKey"))
      use narrow <- result.try(object_field(fields, "narrow"))
      use left <- result.try(compressed_items(left))
      use right <- result.try(compressed_items(right))
      use by_key <- result.try(compressed_map(by_key))
      use narrow <- result.try(compressed_points(narrow))
      Ok([
        json.int(5),
        left,
        right,
        by_key,
        narrow,
      ])
    }
    _ -> Error("summarize requires the object array root")
  }
}

fn compressed_items(value: types.TreeValue) -> Result(Json, String) {
  case value {
    types.ArrayValue(schema_id, elements) if schema_id == items_type -> {
      use elements <- result.try(try_flat_map(elements, compressed_any))
      Ok(json.array(elements, fn(value) { value }))
    }
    _ -> Error("expected an Items array")
  }
}

fn compressed_points(value: types.TreeValue) -> Result(Json, String) {
  case value {
    types.ArrayValue(schema_id, elements) if schema_id == points_type -> {
      use elements <- result.try(try_flat_map(elements, compressed_point))
      Ok(json.array(elements, fn(value) { value }))
    }
    _ -> Error("expected a Points array")
  }
}

fn compressed_any(value: types.TreeValue) -> Result(List(Json), String) {
  case value {
    types.StringValue(value) -> Ok([json.int(0), json.string(value)])
    types.NumberValue(value) -> Ok([json.int(7), number_json(value)])
    types.ObjectValue(schema_id, _) if schema_id == point_type -> {
      use point <- result.try(compressed_point(value))
      Ok([json.int(2), ..point])
    }
    types.ArrayValue(schema_id, _) if schema_id == items_type -> {
      use items <- result.try(compressed_items(value))
      Ok([json.int(1), items])
    }
    types.MapValue(schema_id, _) if schema_id == array_map_type -> {
      use map <- result.try(compressed_map(value))
      Ok([json.int(3), map])
    }
    _ -> Error("unsupported compressed array fixture value")
  }
}

fn compressed_point(value: types.TreeValue) -> Result(List(Json), String) {
  case value {
    types.ObjectValue(schema_id, fields) if schema_id == point_type -> {
      use label <- result.try(object_field(fields, "label"))
      use x <- result.try(object_field(fields, "x"))
      case label, x {
        types.StringValue(label), types.NumberValue(x) ->
          Ok([json.string(label), number_json(x)])
        _, _ -> Error("point fields have invalid values")
      }
    }
    _ -> Error("expected a Point object")
  }
}

fn compressed_map(value: types.TreeValue) -> Result(Json, String) {
  case value {
    types.MapValue(schema_id, entries) if schema_id == array_map_type -> {
      use entries <- result.try(
        try_flat_map(entries, fn(entry) {
          use value <- result.try(compressed_any(entry.1))
          Ok([
            case entry.0 {
              "" -> json.int(0)
              key -> json.string(key)
            },
            json.array(value, fn(value) { value }),
          ])
        }),
      )
      Ok(json.array(entries, fn(value) { value }))
    }
    _ -> Error("expected an ArrayMap")
  }
}

fn number_json(value: Float) -> Json {
  case value == float.floor(value) {
    True -> json.int(float.truncate(value))
    False -> json.float(value)
  }
}

fn object_field(
  fields: List(#(String, types.TreeValue)),
  key: String,
) -> Result(types.TreeValue, String) {
  list.key_find(fields, key)
  |> result.map_error(fn(_) { "missing object field " <> key })
}

fn try_flat_map(
  values: List(a),
  apply: fn(a) -> Result(List(b), String),
) -> Result(List(b), String) {
  values
  |> list.try_fold([], fn(items, value) {
    use next <- result.try(apply(value))
    Ok(list.append(items, next))
  })
}

fn array_fixture_view_id() -> fluid_ids.StableId {
  let assert Ok(id) =
    fluid_ids.stable_id("00000000-0000-4000-8000-000000000004")
  id
}

fn require(condition: Bool, detail: String) -> Result(Nil, String) {
  case condition {
    True -> Ok(Nil)
    False -> Error(detail)
  }
}
