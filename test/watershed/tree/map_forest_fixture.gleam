import gleam/json.{type Json}
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import watershed/canonical_json
import watershed/fluid_ids
import watershed/json_ot.{type JsonValue, VArray, VString}
import watershed/tree/change_fixture_codec as codec
import watershed/tree/fixtures
import watershed/tree/forest
import watershed/tree/types

pub fn schema(input: Json, name: String) -> Result(String, String) {
  use input <- result.try(codec.parse(input))
  use schemas <- result.try(codec.get(input, "schemas"))
  codec.field(schemas, name, codec.text)
}

pub fn text_field(input: Json, name: String) -> Result(String, String) {
  use input <- result.try(codec.parse(input))
  codec.field(input, name, codec.text)
}

pub fn schema_content_expected(expected: Json) -> Result(Json, String) {
  use observation <- result.try(find_observation(expected, "schema-and-content"))
  use entries <- result.try(codec.field(observation, "entries", codec.items))
  let entries = sort_entries(entries)
  use keys <- result.try(
    list.try_map(entries, fn(entry) {
      use pair <- result.try(codec.pair(entry))
      codec.text(pair.0)
    }),
  )
  Ok(
    json.object([
      #("keys", json.array(keys, json.string)),
      #("entries", json.array(entries, json_value_to_json)),
    ]),
  )
}

pub fn field_expected(
  expected: Json,
  id: String,
  stage: String,
) -> Result(Json, String) {
  use observation <- result.try(find_observation(expected, id))
  use state <- result.try(codec.get(observation, stage))
  normalize_field_state(state)
}

pub fn observe_schema_content(
  state: forest.Forest,
) -> Result(Json, types.TreeError) {
  use entries <- result.try(forest.map_entries(state, []))
  let entries = sort_tree_entries(entries)
  Ok(
    json.object([
      #(
        "keys",
        json.array(list.map(entries, fn(entry) { entry.0 }), json.string),
      ),
      #(
        "entries",
        json.array(entries, fn(entry) {
          json.array(
            [json.string(entry.0), schema_value_to_json(entry.1)],
            fn(value) { value },
          )
        }),
      ),
    ]),
  )
}

pub fn observe_field(
  state: forest.Forest,
  path: List(String),
) -> Result(Json, types.TreeError) {
  use entries <- result.try(forest.map_entries(state, path))
  use data <- result.try(forest.export_data(state))
  let detached =
    data.detached
    |> list.map(fn(entry) {
      json.object([
        #("id", atom_to_json(entry.id)),
        #("value", fixtures.tree_value_to_json(entry.value)),
      ])
    })
    |> sort_json
  Ok(
    json.object([
      #(
        "entries",
        entries
          |> sort_tree_entries
          |> json.array(fn(entry) {
            json.array(
              [json.string(entry.0), fixtures.tree_value_to_json(entry.1)],
              fn(value) { value },
            )
          }),
      ),
      #("detached", json.array(detached, fn(value) { value })),
    ]),
  )
}

fn find_observation(expected: Json, id: String) -> Result(JsonValue, String) {
  use expected <- result.try(codec.parse(expected))
  use observations <- result.try(codec.field(
    expected,
    "observations",
    codec.items,
  ))
  observations
  |> list.find(fn(observation) {
    codec.field(observation, "id", codec.text) == Ok(id)
  })
  |> result.map_error(fn(_) { "missing observation " <> id })
}

fn normalize_field_state(state: JsonValue) -> Result(Json, String) {
  use entries <- result.try(codec.field(state, "entries", codec.items))
  use detached <- result.try(codec.field(state, "detached", codec.items))
  use detached <- result.try(
    list.try_map(detached, fn(entry) {
      use id <- result.try(codec.get(entry, "id"))
      use value <- result.try(codec.get(entry, "value"))
      Ok(
        json.object([
          #("id", json_value_to_json(id)),
          #("value", json_value_to_json(value)),
        ]),
      )
    }),
  )
  Ok(
    json.object([
      #(
        "entries",
        entries
          |> sort_entries
          |> json.array(json_value_to_json),
      ),
      #("detached", detached |> sort_json |> json.array(fn(value) { value })),
    ]),
  )
}

fn schema_value_to_json(value: types.TreeValue) -> Json {
  case value {
    types.StringValue(value) -> json.string(value)
    types.BooleanValue(value) -> json.bool(value)
    types.NumberValue(value) -> json.float(value)
    types.NullValue -> json.null()
    types.ObjectValue(schema_id, fields) ->
      json.object([
        #("kind", json.string("object")),
        #("type", json.string(schema_id)),
        #(
          "fields",
          fields
            |> sort_tree_entries
            |> json.array(fn(field) {
              json.array(
                [json.string(field.0), schema_value_to_json(field.1)],
                fn(value) { value },
              )
            }),
        ),
      ])
    types.MapValue(schema_id, entries) ->
      json.object([
        #("kind", json.string("map")),
        #("type", json.string(schema_id)),
        #(
          "entries",
          entries
            |> sort_tree_entries
            |> json.array(fn(entry) {
              json.array(
                [json.string(entry.0), schema_value_to_json(entry.1)],
                fn(value) { value },
              )
            }),
        ),
      ])
  }
}

fn sort_entries(entries: List(JsonValue)) -> List(JsonValue) {
  list.sort(entries, fn(left, right) {
    canonical_json.compare(entry_key(left), entry_key(right))
  })
}

fn entry_key(entry: JsonValue) -> String {
  case entry {
    VArray([VString(key), _]) -> key
    _ -> ""
  }
}

fn sort_tree_entries(
  entries: List(#(String, types.TreeValue)),
) -> List(#(String, types.TreeValue)) {
  list.sort(entries, fn(left, right) { canonical_json.compare(left.0, right.0) })
}

fn sort_json(values: List(Json)) -> List(Json) {
  list.sort(values, fn(left, right) {
    canonical_json.compare(json_sort_key(left), json_sort_key(right))
  })
}

fn json_sort_key(value: Json) -> String {
  case json.parse(json.to_string(value), json_ot.decoder()) {
    Ok(value) -> canonical_json.to_string(value)
    Error(_) -> json.to_string(value)
  }
}

fn atom_to_json(id: types.AtomId) -> Json {
  json.object([
    #("revision", case id.revision {
      None -> json.null()
      Some(revision) -> json.string(fluid_ids.stable_id_to_string(revision))
    }),
    #("localId", json.int(id.local_id)),
  ])
}

fn json_value_to_json(value: JsonValue) -> Json {
  json_ot.to_json(value)
}
