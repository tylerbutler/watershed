import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/set
import gleam/string
import watershed/tree/schema
import watershed/tree/types

type SchemaEntry {
  SchemaEntry(id: String, raw: String)
}

type Scenario {
  Scenario(id: String, stored: String, requested: String, operation: String)
}

type RawProbe {
  RawProbe(id: String, raw: String)
}

type Input {
  Input(
    schemas: List(SchemaEntry),
    scenarios: List(Scenario),
    refusals: List(Scenario),
    raw_probes: List(RawProbe),
  )
}

type ObservationStatus {
  ObservationStatus(
    id: String,
    can_view: Bool,
    can_upgrade: Bool,
    is_equivalent: Bool,
  )
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
      run_scenario(catalog, scenario)
    }),
  )
  use refusals <- result.try(
    list.try_map(input.refusals, fn(scenario) {
      run_refusal_scenario(catalog, scenario)
    }),
  )
  let assert [first, ..] = input.scenarios
  use baseline_raw <- result.try(find_schema(catalog, first.stored))
  use baseline <- result.try(
    schema.view_from_string(baseline_raw)
    |> result.map_error(fn(error) {
      "invalid raw probe baseline: " <> string.inspect(error)
    }),
  )
  use raw_probes <- result.try(
    list.try_map(input.raw_probes, fn(probe) { run_raw_probe(probe, baseline) }),
  )
  Ok(
    json.object([
      #("observations", json.array(observations, fn(value) { value })),
      #("refusals", json.array(refusals, fn(value) { value })),
      #("rawProbes", json.array(raw_probes, fn(value) { value })),
    ]),
  )
}

pub fn compatibility_projection(input: Json) -> Result(Json, String) {
  use observations <- result.try(
    json.parse(json.to_string(input), {
      use observations <- decode.field(
        "observations",
        decode.list(observation_status_decoder()),
      )
      decode.success(observations)
    })
    |> result.map_error(fn(error) {
      "invalid schema compatibility observations: " <> string.inspect(error)
    }),
  )
  Ok(
    json.object([
      #(
        "observations",
        json.array(observations, fn(observation) {
          json.object([
            #("id", json.string(observation.id)),
            #(
              "compatibility",
              json.object([
                #("canView", json.bool(observation.can_view)),
                #("canUpgrade", json.bool(observation.can_upgrade)),
                #("isEquivalent", json.bool(observation.is_equivalent)),
              ]),
            ),
          ])
        }),
      ),
    ]),
  )
}

fn run_scenario(
  catalog: dict.Dict(String, String),
  scenario: Scenario,
) -> Result(Json, String) {
  use _ <- result.try(check_operation(scenario, "compatibility"))
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
  native_observation(scenario.id, stored, view)
}

fn run_refusal_scenario(
  catalog: dict.Dict(String, String),
  scenario: Scenario,
) -> Result(Json, String) {
  use _ <- result.try(check_operation(scenario, "prepare-upgrade"))
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
  use preparation <- result.try(preparation_json(scenario.id, stored, view))
  let classification = case status.can_upgrade {
    True -> "m4-profile-exclusion"
    False -> "upstream-refusal"
  }
  Ok(
    json.object([
      #("id", json.string(scenario.id)),
      #("classification", json.string(classification)),
      #("compatibility", compatibility_json(status)),
      #("preparation", preparation),
    ]),
  )
}

fn native_observation(
  id: String,
  stored: schema.StoredSchema,
  view: schema.ViewSchema,
) -> Result(Json, String) {
  use status <- result.try(
    schema.compatibility(stored, view)
    |> result.map_error(fn(error) {
      id <> ": compatibility error: " <> string.inspect(error)
    }),
  )
  use preparation <- result.try(preparation_json(id, stored, view))
  Ok(
    json.object([
      #("id", json.string(id)),
      #("compatibility", compatibility_json(status)),
      #("preparation", preparation),
    ]),
  )
}

fn preparation_json(
  id: String,
  stored: schema.StoredSchema,
  view: schema.ViewSchema,
) -> Result(Json, String) {
  case schema.prepare_upgrade(stored, view) {
    Ok(None) ->
      Ok(
        json.object([
          #("outcome", json.string("no-op")),
          #("error", json.null()),
        ]),
      )
    Ok(Some(_)) ->
      Ok(
        json.object([
          #("outcome", json.string("upgrade")),
          #("error", json.null()),
        ]),
      )
    Error(types.InvalidSchema(detail)) ->
      Ok(
        json.object([
          #("outcome", json.string("refused")),
          #("error", json.string(detail)),
        ]),
      )
    Error(error) ->
      Error(id <> ": unexpected upgrade error: " <> string.inspect(error))
  }
}

fn run_raw_probe(
  probe: RawProbe,
  baseline: schema.ViewSchema,
) -> Result(Json, String) {
  case schema.stored_from_string(probe.raw) {
    Error(error) ->
      Ok(
        json.object([
          #("id", json.string(probe.id)),
          #("parsed", json.bool(False)),
          #("classification", json.string("stored-decode-refusal")),
          #("error", json.string(string.inspect(error))),
        ]),
      )
    Ok(stored) -> {
      use status <- result.try(
        schema.compatibility(stored, baseline)
        |> result.map_error(fn(error) {
          probe.id <> ": compatibility error: " <> string.inspect(error)
        }),
      )
      Ok(
        json.object([
          #("id", json.string(probe.id)),
          #("parsed", json.bool(True)),
          #("classification", json.string("compatibility")),
          #("compatibility", compatibility_json(status)),
        ]),
      )
    }
  }
}

fn compatibility_json(status: schema.Compatibility) -> Json {
  json.object([
    #("canView", json.bool(status.can_view)),
    #("canUpgrade", json.bool(status.can_upgrade)),
    #("isEquivalent", json.bool(status.is_equivalent)),
  ])
}

fn check_operation(
  scenario: Scenario,
  expected: String,
) -> Result(Nil, String) {
  case scenario.operation == expected {
    True -> Ok(Nil)
    False -> Error(scenario.id <> ": unknown operation " <> scenario.operation)
  }
}

fn validate_input(input: Input) -> Result(Nil, String) {
  use _ <- result.try(case input.schemas, input.scenarios {
    [], _ -> Error("schema evolution schemas must not be empty")
    _, [] -> Error("schema evolution scenarios must not be empty")
    _, _ -> Ok(Nil)
  })
  use _ <- result.try(unique_ids(
    input.schemas,
    fn(entry) { entry.id },
    "schema",
  ))
  use _ <- result.try(unique_ids(
    input.scenarios,
    fn(scenario) { scenario.id },
    "scenario",
  ))
  use _ <- result.try(unique_ids(
    input.refusals,
    fn(scenario) { scenario.id },
    "refusal",
  ))
  unique_ids(input.raw_probes, fn(probe) { probe.id }, "raw probe")
}

fn unique_ids(
  values: List(a),
  identifier: fn(a) -> String,
  kind: String,
) -> Result(Nil, String) {
  values
  |> list.try_fold(set.new(), fn(ids, value) {
    let id = identifier(value)
    case string.is_empty(id) || set.contains(ids, id) {
      True -> Error("empty or duplicate " <> kind <> " id: " <> id)
      False -> Ok(set.insert(ids, id))
    }
  })
  |> result.map(fn(_) { Nil })
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
    Input([], [], [], []),
    {
      use schemas <- decode.field("schemas", decode.list(schema_decoder()))
      use scenarios <- decode.field(
        "scenarios",
        decode.list(scenario_decoder()),
      )
      use refusals <- decode.field("refusals", decode.list(scenario_decoder()))
      use raw_probes <- decode.field(
        "rawProbes",
        decode.list(raw_probe_decoder()),
      )
      decode.success(Input(schemas:, scenarios:, refusals:, raw_probes:))
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

fn raw_probe_decoder() -> Decoder(RawProbe) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  exact_decoder(fields, ["id", "raw"], RawProbe("", ""), {
    use id <- decode.field("id", decode.string)
    use raw <- decode.field("raw", decode.string)
    decode.success(RawProbe(id:, raw:))
  })
}

fn observation_status_decoder() -> Decoder(ObservationStatus) {
  use id <- decode.field("id", decode.string)
  use compatibility <- decode.field("compatibility", {
    use can_view <- decode.field("canView", decode.bool)
    use can_upgrade <- decode.field("canUpgrade", decode.bool)
    use is_equivalent <- decode.field("isEquivalent", decode.bool)
    decode.success(#(can_view, can_upgrade, is_equivalent))
  })
  decode.success(ObservationStatus(
    id:,
    can_view: compatibility.0,
    can_upgrade: compatibility.1,
    is_equivalent: compatibility.2,
  ))
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
