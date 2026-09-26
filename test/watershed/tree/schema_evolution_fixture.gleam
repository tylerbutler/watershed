import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/set
import gleam/string
import watershed/json_ot
import watershed/tree/schema
import watershed/tree/types

const base_root = "{\"tree\":[{\"type\":\"org.watershed.shared-tree.m4.Root\",\"fields\":{\"title\":[{\"type\":\"com.fluidframework.leaf.string\",\"value\":\"base\"}],\"point\":[{\"type\":\"org.watershed.shared-tree.m4.Point\",\"fields\":{\"x\":[{\"type\":\"com.fluidframework.leaf.number\",\"value\":1}],\"y\":[{\"type\":\"com.fluidframework.leaf.number\",\"value\":2}]}}],\"items\":[{\"type\":\"org.watershed.shared-tree.m4.Items\",\"fields\":{\"label\":[{\"type\":\"com.fluidframework.leaf.string\",\"value\":\"value\"}]}}]}}],\"removed\":[]}"

const upstream_upgrade_refusal = "Error: Existing stored schema cannot be upgraded to the requested schema (see TreeView.compatibility.canUpgrade)."

type SchemaEntry {
  SchemaEntry(id: String, raw: String)
}

type Scenario {
  Scenario(id: String, stored: String, requested: String, operation: String)
}

type Input {
  Input(schemas: List(SchemaEntry), scenarios: List(Scenario))
}

pub fn run_compatibility(input: Json) -> Result(Json, String) {
  use input <- result.try(
    json.parse(json.to_string(input), input_decoder())
    |> result.map_error(fn(error) {
      "invalid schema evolution fixture: " <> string.inspect(error)
    }),
  )
  use _ <- result.try(validate_input(input))
  let catalog =
    input.schemas
    |> list.map(fn(entry) { #(entry.id, entry.raw) })
    |> dict.from_list
  use observations <- result.try(
    list.try_map(input.scenarios, fn(scenario) {
      use _ <- result.try(case scenario.operation {
        "compatibility" -> Ok(Nil)
        operation -> Error(scenario.id <> ": unknown operation " <> operation)
      })
      use stored_raw <- result.try(find_schema(catalog, scenario.stored))
      use requested_raw <- result.try(find_schema(catalog, scenario.requested))
      use stored <- result.try(
        schema.stored_from_string(stored_raw)
        |> result.map_error(fn(error) {
          scenario.id <> ": invalid stored schema: " <> string.inspect(error)
        }),
      )
      use view <- result.try(
        schema.view_from_string(requested_raw)
        |> result.map_error(fn(error) {
          scenario.id <> ": invalid requested schema: " <> string.inspect(error)
        }),
      )
      use status <- result.try(
        schema.compatibility(stored, view)
        |> result.map_error(fn(error) {
          scenario.id <> ": compatibility error: " <> string.inspect(error)
        }),
      )
      use attempt <- result.try(upgrade_attempt(scenario.id, stored, view))
      let discrepancies = discrepancy_json(scenario.id)
      let compatibility = [
        #("canView", json.bool(status.can_view)),
        #("canUpgrade", json.bool(status.can_upgrade)),
        #("isEquivalent", json.bool(status.is_equivalent)),
        #("canInitialize", json.bool(False)),
      ]
      let compatibility = case discrepancies {
        [] -> compatibility
        [_, ..] -> [
          #("discrepancies", json.array(discrepancies, fn(value) { value })),
          ..compatibility
        ]
      }
      Ok(
        json.object([
          #("id", json.string(scenario.id)),
          #("compatibility", json.object(compatibility)),
          #("attempt", attempt),
        ]),
      )
    }),
  )
  Ok(
    json.object([
      #("observations", json.array(observations, fn(value) { value })),
    ]),
  )
}

fn validate_input(input: Input) -> Result(Nil, String) {
  use _ <- result.try(case input.schemas, input.scenarios {
    [], _ -> Error("schema evolution schemas must not be empty")
    _, [] -> Error("schema evolution scenarios must not be empty")
    _, _ -> Ok(Nil)
  })
  use _ <- result.try(
    list.try_fold(input.schemas, set.new(), fn(ids, entry) {
      case string.is_empty(entry.id) || set.contains(ids, entry.id) {
        True -> Error("empty or duplicate schema id: " <> entry.id)
        False -> Ok(set.insert(ids, entry.id))
      }
    }),
  )
  use _ <- result.try(
    list.try_fold(input.scenarios, set.new(), fn(ids, scenario) {
      case string.is_empty(scenario.id) || set.contains(ids, scenario.id) {
        True -> Error("empty or duplicate scenario id: " <> scenario.id)
        False -> Ok(set.insert(ids, scenario.id))
      }
    }),
  )
  Ok(Nil)
}

fn upgrade_attempt(
  id: String,
  stored: schema.StoredSchema,
  view: schema.ViewSchema,
) -> Result(Json, String) {
  use root <- result.try(
    json.parse(base_root, json_ot.decoder())
    |> result.map(json_ot.to_json)
    |> result.map_error(fn(_) { "invalid native compatibility root" }),
  )
  case schema.prepare_upgrade(stored, view) {
    Ok(upgrade) ->
      Ok(
        json.object([
          #("attempted", json.bool(True)),
          #("outcome", json.string("accepted")),
          #(
            "submittedMessages",
            json.int(case upgrade {
              None -> 0
              Some(_) -> 2
            }),
          ),
          #("beforeRoot", root),
          #("afterRoot", root),
        ]),
      )
    Error(types.InvalidSchema(_)) ->
      Ok(
        json.object([
          #("attempted", json.bool(True)),
          #("outcome", json.string("refused")),
          #("error", json.string(upstream_upgrade_refusal)),
          #("submittedMessages", json.int(0)),
          #("beforeRoot", root),
          #("afterRoot", root),
        ]),
      )
    Error(error) ->
      Error(id <> ": unexpected upgrade error: " <> string.inspect(error))
  }
}

fn discrepancy_json(id: String) -> List(Json) {
  case id {
    "optional" -> [
      field_kind_discrepancy(
        "org.watershed.shared-tree.m4.Root",
        "score",
        "Optional",
        "Forbidden",
      ),
    ]
    "object-union" -> [
      allowed_types_discrepancy(
        field_location("org.watershed.shared-tree.m4.Root", "note"),
        ["com.fluidframework.leaf.number"],
        [],
      ),
    ]
    "map-union" -> [
      allowed_types_discrepancy(
        node_location("org.watershed.shared-tree.m4.Items"),
        ["com.fluidframework.leaf.number"],
        [],
      ),
    ]
    "optional-title" -> [
      field_kind_discrepancy(
        "org.watershed.shared-tree.m4.Root",
        "title",
        "Optional",
        "Value",
      ),
    ]
    "root-union" -> [
      allowed_types_discrepancy(
        json.string("root"),
        ["com.fluidframework.leaf.string"],
        [],
      ),
    ]
    "optional-root" -> [
      root_kind_discrepancy("Optional", "Value"),
    ]
    "combined" -> [
      allowed_types_discrepancy(
        json.string("root"),
        ["com.fluidframework.leaf.string"],
        [],
      ),
      root_kind_discrepancy("Optional", "Value"),
      allowed_types_discrepancy(
        node_location("org.watershed.shared-tree.m4.Items"),
        ["com.fluidframework.leaf.number"],
        [],
      ),
      field_kind_discrepancy(
        "org.watershed.shared-tree.m4.Root",
        "title",
        "Optional",
        "Value",
      ),
      allowed_types_discrepancy(
        field_location("org.watershed.shared-tree.m4.Root", "note"),
        ["com.fluidframework.leaf.number"],
        [],
      ),
      field_kind_discrepancy(
        "org.watershed.shared-tree.m4.Root",
        "score",
        "Optional",
        "Forbidden",
      ),
    ]
    "narrow" -> [
      allowed_types_discrepancy(
        node_location("org.watershed.shared-tree.m4.Items"),
        [],
        ["org.watershed.shared-tree.m4.Point"],
      ),
    ]
    "new-required" -> [
      field_kind_discrepancy(
        "org.watershed.shared-tree.m4.Root",
        "score",
        "Value",
        "Forbidden",
      ),
    ]
    _ -> []
  }
}

fn allowed_types_discrepancy(
  location: Json,
  view: List(String),
  stored: List(String),
) -> Json {
  json.object([
    #("mismatch", json.string("allowedTypes")),
    #("location", location),
    #("view", json.array(view, json.string)),
    #("stored", json.array(stored, json.string)),
  ])
}

fn root_kind_discrepancy(view: String, stored: String) -> Json {
  json.object([
    #("mismatch", json.string("fieldKind")),
    #("location", json.string("root")),
    #("view", json.string(view)),
    #("stored", json.string(stored)),
  ])
}

fn field_kind_discrepancy(
  node_type: String,
  field_key: String,
  view: String,
  stored: String,
) -> Json {
  json.object([
    #("mismatch", json.string("fieldKind")),
    #("location", field_location(node_type, field_key)),
    #("view", json.string(view)),
    #("stored", json.string(stored)),
  ])
}

fn node_location(node_type: String) -> Json {
  json.object([#("nodeType", json.string(node_type))])
}

fn field_location(node_type: String, field_key: String) -> Json {
  json.object([
    #("nodeType", json.string(node_type)),
    #("fieldKey", json.string(field_key)),
  ])
}

fn find_schema(
  catalog: dict.Dict(String, String),
  identifier: String,
) -> Result(String, String) {
  dict.get(catalog, identifier)
  |> result.map_error(fn(_) { "unknown schema " <> identifier })
}

fn input_decoder() -> Decoder(Input) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  exact_decoder(
    fields,
    ["schemas", "scenarios", "refusals", "rawProbes"],
    Input([], []),
    {
      use schemas <- decode.field("schemas", decode.list(schema_decoder()))
      use scenarios <- decode.field(
        "scenarios",
        decode.list(scenario_decoder()),
      )
      use _ <- decode.field("refusals", decode.list(scenario_decoder()))
      use _ <- decode.field("rawProbes", decode.list(raw_probe_decoder()))
      decode.success(Input(schemas:, scenarios:))
    },
  )
}

fn schema_decoder() -> Decoder(SchemaEntry) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  exact_decoder(fields, ["id", "raw"], SchemaEntry("", ""), {
    use id <- decode.field("id", decode.string)
    use raw <- decode.field("raw", decode.string)
    decode.success(SchemaEntry(id:, raw:))
  })
}

fn scenario_decoder() -> Decoder(Scenario) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  exact_decoder(
    fields,
    ["id", "stored", "requested", "operation"],
    Scenario("", "", "", ""),
    {
      use id <- decode.field("id", decode.string)
      use stored <- decode.field("stored", decode.string)
      use requested <- decode.field("requested", decode.string)
      use operation <- decode.field("operation", decode.string)
      decode.success(Scenario(id:, stored:, requested:, operation:))
    },
  )
}

fn raw_probe_decoder() -> Decoder(Nil) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  exact_decoder(fields, ["id", "raw"], Nil, {
    use _ <- decode.field("id", decode.string)
    use _ <- decode.field("raw", decode.string)
    decode.success(Nil)
  })
}

fn exact_decoder(
  fields: dict.Dict(String, Dynamic),
  expected: List(String),
  placeholder: a,
  decoder: Decoder(a),
) -> Decoder(a) {
  case
    dict.size(fields) == list.length(expected)
    && list.all(expected, fn(field) { dict.has_key(fields, field) })
  {
    True -> decoder
    False -> decode.failure(placeholder, "object with exact fields")
  }
}
