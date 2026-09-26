import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/set
import gleam/string
import watershed/fluid_ids
import watershed/json_ot.{type JsonValue, VArray, VObject, VString}
import watershed/tree/change
import watershed/tree/change_fixture_codec as fixture_codec
import watershed/tree/codec
import watershed/tree/fixtures
import watershed/tree/forest
import watershed/tree/optional_field
import watershed/tree/schema
import watershed/tree/shared_change
import watershed/tree/types.{AtomId, StringValue}

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

type AlgebraState {
  AlgebraState(
    originator: fluid_ids.SessionId,
    compressor: fluid_ids.Compressor,
    schema_change: shared_change.TaggedChange,
    data_change: shared_change.TaggedChange,
    second_data_revision: fluid_ids.StableId,
    second_schema_change: shared_change.TaggedChange,
    empty_change: shared_change.TaggedChange,
    inverse_revision: fluid_ids.StableId,
    schema_encodings: List(SchemaEncoding),
    data_encoding: JsonValue,
  )
}

type SchemaEncoding {
  SchemaEncoding(
    before: schema.SchemaState,
    after: schema.SchemaState,
    old: JsonValue,
    new: JsonValue,
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

pub fn run_algebra(input: Json) -> Result(Json, String) {
  use input <- result.try(fixture_codec.parse(input))
  use _ <- result.try(
    fixture_codec.exact(input, [
      "schemas", "revisions", "operands", "transitions", "scenarios",
    ]),
  )
  use state <- result.try(algebra_state(input))
  use scenarios <- result.try(fixture_codec.field(
    input,
    "scenarios",
    fixture_codec.items,
  ))
  use observations <- result.try(
    list.try_map(scenarios, fn(scenario) {
      use _ <- result.try(fixture_codec.exact(scenario, ["id"]))
      use id <- result.try(fixture_codec.field(
        scenario,
        "id",
        fixture_codec.text,
      ))
      run_algebra_scenario(id, state)
    }),
  )
  Ok(
    json.object([
      #("observations", json.array(observations, fn(value) { value })),
    ]),
  )
}

fn algebra_state(input: JsonValue) -> Result(AlgebraState, String) {
  let assert Ok(originator) =
    fluid_ids.session_id("00000000-0000-4000-8000-000000000000")
  use revisions <- result.try(fixture_codec.get(input, "revisions"))
  use revision_numbers <- result.try(algebra_revision_numbers(revisions))
  let maximum = list.fold(revision_numbers, 0, int_max)
  use compressor <- result.try(algebra_compressor(originator, maximum + 1))
  use schema_revision <- result.try(algebra_revision(
    revisions,
    "schema",
    originator,
    compressor,
  ))
  use data_revision <- result.try(algebra_revision(
    revisions,
    "data",
    originator,
    compressor,
  ))
  use second_data_revision <- result.try(algebra_revision(
    revisions,
    "secondData",
    originator,
    compressor,
  ))
  use second_schema_revision <- result.try(algebra_revision(
    revisions,
    "secondSchema",
    originator,
    compressor,
  ))
  use inverse_revision <- result.try(algebra_revision(
    revisions,
    "inverse",
    originator,
    compressor,
  ))
  use catalog <- result.try(algebra_schema_catalog(input))
  use transitions <- result.try(fixture_codec.field(
    input,
    "transitions",
    fixture_codec.items,
  ))
  use transitions <- result.try(
    list.try_map(transitions, fn(transition) {
      decode_transition(transition, catalog, originator, compressor)
    }),
  )
  use schema_transition <- result.try(find_transition(
    transitions,
    schema_revision,
  ))
  use second_schema_transition <- result.try(find_transition(
    transitions,
    second_schema_revision,
  ))
  use operands <- result.try(fixture_codec.get(input, "operands"))
  use _ <- result.try(
    fixture_codec.exact(operands, [
      "schemaChange", "dataChange", "secondSchemaChange", "emptyChange",
    ]),
  )
  use _ <- result.try(
    fixture_codec.field(operands, "schemaChange", fn(value) {
      compare_schema_operand(value, schema_transition.1)
    }),
  )
  use _ <- result.try(
    fixture_codec.field(operands, "secondSchemaChange", fn(value) {
      compare_schema_operand(value, second_schema_transition.1)
    }),
  )
  use data_encoding <- result.try(
    fixture_codec.field(operands, "dataChange", fn(value) {
      single_outer_change(value, "data")
    }),
  )
  use identity_order <- result.try(algebra_identity_order(
    originator,
    compressor,
    maximum,
  ))
  use data <- result.try(
    fixture_codec.field(operands, "dataChange", fn(value) {
      decode_data_operand(
        value,
        data_revision,
        originator,
        compressor,
        identity_order,
      )
    }),
  )
  use empty <- result.try(fixture_codec.field(
    operands,
    "emptyChange",
    decode_empty_operand,
  ))
  Ok(AlgebraState(
    originator:,
    compressor:,
    schema_change: schema_transition.0,
    data_change: data,
    second_data_revision:,
    second_schema_change: second_schema_transition.0,
    empty_change: shared_change.TaggedChange(None, None, empty),
    inverse_revision:,
    schema_encodings: [schema_transition.1, second_schema_transition.1],
    data_encoding:,
  ))
}

fn compare_schema_operand(
  operand: JsonValue,
  encoding: SchemaEncoding,
) -> Result(Nil, String) {
  fixtures.first_difference(
    json_ot.to_json(operand),
    schema_operand_json(encoding),
  )
  |> result.map_error(fn(path) {
    "schema operand and transition differ at " <> path
  })
}

fn schema_operand_json(encoding: SchemaEncoding) -> Json {
  json.object([
    #(
      "changes",
      json.array(
        [
          json.object([
            #("type", json.string("schema")),
            #(
              "innerChange",
              json.object([
                #(
                  "schema",
                  json.object([
                    #("old", json_ot.to_json(encoding.old)),
                    #("new", json_ot.to_json(encoding.new)),
                  ]),
                ),
                #("isInverse", json.bool(False)),
              ]),
            ),
          ]),
        ],
        fn(value) { value },
      ),
    ),
  ])
}

fn algebra_revision_numbers(value: JsonValue) -> Result(List(Int), String) {
  use _ <- result.try(
    fixture_codec.exact(value, [
      "schema", "data", "secondData", "secondSchema", "inverse",
    ]),
  )
  list.try_map(
    ["schema", "data", "secondData", "secondSchema", "inverse"],
    fn(name) { fixture_codec.field(value, name, fixture_codec.integer) },
  )
}

fn algebra_compressor(
  originator: fluid_ids.SessionId,
  count: Int,
) -> Result(fluid_ids.Compressor, String) {
  use compressor <- result.try(generate_ids(fluid_ids.new(originator), count))
  let #(compressor, range) = fluid_ids.take_creation_range(compressor)
  case range {
    None -> Ok(compressor)
    Some(range) ->
      fluid_ids.finalize(compressor, range)
      |> result.map_error(string.inspect)
  }
}

fn generate_ids(
  compressor: fluid_ids.Compressor,
  count: Int,
) -> Result(fluid_ids.Compressor, String) {
  case count {
    0 -> Ok(compressor)
    _ -> {
      use #(compressor, _) <- result.try(
        fluid_ids.generate(compressor) |> result.map_error(string.inspect),
      )
      generate_ids(compressor, count - 1)
    }
  }
}

fn algebra_revision(
  revisions: JsonValue,
  name: String,
  originator: fluid_ids.SessionId,
  compressor: fluid_ids.Compressor,
) -> Result(fluid_ids.StableId, String) {
  use value <- result.try(fixture_codec.field(
    revisions,
    name,
    fixture_codec.integer,
  ))
  codec.decode_stable_revision(
    value,
    originator,
    codec.DecodeContext(codec.Fluid310, compressor),
    "algebra revision",
  )
  |> result.map_error(string.inspect)
}

fn algebra_identity_order(
  originator: fluid_ids.SessionId,
  compressor: fluid_ids.Compressor,
  maximum: Int,
) -> Result(change.IdentityOrder, String) {
  use revisions <- result.try(
    algebra_revisions(originator, compressor, 0, maximum, []),
  )
  codec.identity_order(revisions, compressor, "algebra identity order")
  |> result.map_error(string.inspect)
}

fn algebra_revisions(
  originator: fluid_ids.SessionId,
  compressor: fluid_ids.Compressor,
  current: Int,
  maximum: Int,
  revisions: List(fluid_ids.StableId),
) -> Result(List(fluid_ids.StableId), String) {
  case current > maximum {
    True -> Ok(list.reverse(revisions))
    False -> {
      use revision <- result.try(
        codec.decode_stable_revision(
          current,
          originator,
          codec.DecodeContext(codec.Fluid310, compressor),
          "algebra identity order",
        )
        |> result.map_error(string.inspect),
      )
      algebra_revisions(originator, compressor, current + 1, maximum, [
        revision,
        ..revisions
      ])
    }
  }
}

fn algebra_schema_catalog(
  input: JsonValue,
) -> Result(dict.Dict(String, schema.StoredSchema), String) {
  use entries <- result.try(fixture_codec.field(
    input,
    "schemas",
    fixture_codec.items,
  ))
  use entries <- result.try(
    list.try_map(entries, fn(entry) {
      use _ <- result.try(fixture_codec.exact(entry, ["id", "raw"]))
      use id <- result.try(fixture_codec.field(entry, "id", fixture_codec.text))
      use raw <- result.try(fixture_codec.field(
        entry,
        "raw",
        fixture_codec.text,
      ))
      use stored <- result.try(
        schema.stored_from_string(raw) |> result.map_error(string.inspect),
      )
      Ok(#(id, stored))
    }),
  )
  Ok(dict.from_list(entries))
}

fn decode_transition(
  value: JsonValue,
  catalog: dict.Dict(String, schema.StoredSchema),
  originator: fluid_ids.SessionId,
  compressor: fluid_ids.Compressor,
) -> Result(#(shared_change.TaggedChange, SchemaEncoding), String) {
  use _ <- result.try(
    fixture_codec.exact(value, ["revision", "before", "after", "change"]),
  )
  use revision_number <- result.try(fixture_codec.field(
    value,
    "revision",
    fixture_codec.integer,
  ))
  use revision <- result.try(
    codec.decode_stable_revision(
      revision_number,
      originator,
      codec.DecodeContext(codec.Fluid310, compressor),
      "schema transition revision",
    )
    |> result.map_error(string.inspect),
  )
  use before_id <- result.try(fixture_codec.field(
    value,
    "before",
    fixture_codec.text,
  ))
  use after_id <- result.try(fixture_codec.field(
    value,
    "after",
    fixture_codec.text,
  ))
  use before <- result.try(
    dict.get(catalog, before_id)
    |> result.map_error(fn(_) { "unknown transition schema " <> before_id }),
  )
  use after <- result.try(
    dict.get(catalog, after_id)
    |> result.map_error(fn(_) { "unknown transition schema " <> after_id }),
  )
  use encoded <- result.try(fixture_codec.get(value, "change"))
  use inner <- result.try(single_outer_change(encoded, "schema"))
  use _ <- result.try(fixture_codec.exact(inner, ["schema", "isInverse"]))
  use is_inverse <- result.try(fixture_codec.field(
    inner,
    "isInverse",
    fixture_codec.boolean,
  ))
  use _ <- result.try(case is_inverse {
    False -> Ok(Nil)
    True -> Error("input schema transition must not be inverse")
  })
  use schema_value <- result.try(fixture_codec.get(inner, "schema"))
  use _ <- result.try(fixture_codec.exact(schema_value, ["old", "new"]))
  use old <- result.try(fixture_codec.get(schema_value, "old"))
  use new <- result.try(fixture_codec.get(schema_value, "new"))
  let before = schema.FixedSchema(before)
  let after = schema.FixedSchema(after)
  let change =
    shared_change.from_changes([
      shared_change.SchemaChange(before, after, False),
    ])
  use change <- result.try(change |> result.map_error(string.inspect))
  Ok(#(
    shared_change.TaggedChange(Some(revision), None, change),
    SchemaEncoding(before, after, old, new),
  ))
}

fn find_transition(
  transitions: List(#(shared_change.TaggedChange, SchemaEncoding)),
  revision: fluid_ids.StableId,
) -> Result(#(shared_change.TaggedChange, SchemaEncoding), String) {
  list.find(transitions, fn(transition) {
    transition.0.revision == Some(revision)
  })
  |> result.map_error(fn(_) { "missing schema transition revision" })
}

fn decode_data_operand(
  value: JsonValue,
  revision: fluid_ids.StableId,
  originator: fluid_ids.SessionId,
  compressor: fluid_ids.Compressor,
  identity_order: change.IdentityOrder,
) -> Result(shared_change.TaggedChange, String) {
  use inner <- result.try(single_outer_change(value, "data"))
  use data <- result.try(decode_internal_data(
    inner,
    originator,
    compressor,
    identity_order,
  ))
  Ok(shared_change.TaggedChange(
    Some(revision),
    None,
    shared_change.from_data(data),
  ))
}

fn decode_internal_data(
  value: JsonValue,
  originator: fluid_ids.SessionId,
  compressor: fluid_ids.Compressor,
  identity_order: change.IdentityOrder,
) -> Result(change.Changeset, String) {
  use max_local_id <- result.try(fixture_codec.field(
    value,
    "maxId",
    fixture_codec.integer,
  ))
  use revisions <- result.try(
    fixture_codec.field(value, "revisions", fn(value) {
      fixture_codec.many(value, fn(value) {
        use revision <- result.try(
          fixture_codec.field(value, "revision", fn(value) {
            decode_internal_revision(value, originator, compressor)
          }),
        )
        let rollback = case fixture_codec.get(value, "rollbackOf") {
          Error(_) -> Ok(None)
          Ok(value) ->
            decode_internal_revision(value, originator, compressor)
            |> result.map(Some)
        }
        use rollback <- result.try(rollback)
        Ok(change.RevisionInfo(revision, rollback))
      })
    }),
  )
  use fields <- result.try(
    fixture_codec.field(value, "fieldChanges", fn(value) {
      decode_internal_fields(value, originator, compressor)
    }),
  )
  use nodes <- result.try(
    fixture_codec.field(value, "nodeChanges", fn(value) {
      decode_internal_nodes(value, originator, compressor)
    }),
  )
  use parents <- result.try(
    fixture_codec.field(value, "nodeToParent", fn(value) {
      decode_internal_parents(value, originator, compressor)
    }),
  )
  use aliases <- result.try(
    fixture_codec.field(value, "nodeAliases", fn(value) {
      decode_internal_aliases(value, originator, compressor)
    }),
  )
  let builds = case fixture_codec.get(value, "builds") {
    Error(_) -> Ok([])
    Ok(value) -> decode_internal_builds(value, originator, compressor)
  }
  use builds <- result.try(builds)
  let destroys = case fixture_codec.get(value, "destroys") {
    Error(_) -> Ok([])
    Ok(value) -> decode_internal_destroys(value, originator, compressor)
  }
  use destroys <- result.try(destroys)
  change.from_data(
    change.ChangeData(
      max_local_id:,
      revisions:,
      fields:,
      nodes:,
      parents:,
      aliases:,
      builds:,
      destroys:,
      refreshers: [],
    ),
    identity_order,
  )
  |> result.map_error(string.inspect)
}

fn decode_internal_revision(
  value: JsonValue,
  originator: fluid_ids.SessionId,
  compressor: fluid_ids.Compressor,
) -> Result(fluid_ids.StableId, String) {
  use value <- result.try(fixture_codec.integer(value))
  codec.decode_stable_revision(
    value,
    originator,
    codec.DecodeContext(codec.Fluid310, compressor),
    "algebra data revision",
  )
  |> result.map_error(string.inspect)
}

fn decode_internal_atom(
  value: JsonValue,
  originator: fluid_ids.SessionId,
  compressor: fluid_ids.Compressor,
) -> Result(types.AtomId, String) {
  case value {
    VObject(_) -> {
      use local_id <- result.try(fixture_codec.field(
        value,
        "localId",
        fixture_codec.integer,
      ))
      use revision <- result.try(
        fixture_codec.field(value, "revision", fn(value) {
          decode_internal_revision(value, originator, compressor)
        }),
      )
      Ok(AtomId(Some(revision), local_id))
    }
    VArray([revision, local_id]) -> {
      use revision <- result.try(decode_internal_revision(
        revision,
        originator,
        compressor,
      ))
      use local_id <- result.try(fixture_codec.integer(local_id))
      Ok(AtomId(Some(revision), local_id))
    }
    _ -> Error("invalid algebra atom")
  }
}

fn decode_internal_fields(
  value: JsonValue,
  originator: fluid_ids.SessionId,
  compressor: fluid_ids.Compressor,
) -> Result(List(#(String, change.FieldChange)), String) {
  use entries <- result.try(internal_map_entries(value))
  list.try_map(entries, fn(entry) {
    use #(key, field) <- result.try(fixture_codec.pair(entry))
    use key <- result.try(fixture_codec.text(key))
    use kind <- result.try(fixture_codec.field(
      field,
      "fieldKind",
      fixture_codec.text,
    ))
    use encoded <- result.try(fixture_codec.get(field, "change"))
    case kind {
      "ModularEditBuilder.Generic" -> {
        use children <- result.try(internal_btree_entries(encoded))
        use children <- result.try(
          list.try_map(children, fn(child) {
            use index <- result.try(fixture_codec.integer(child.0))
            use id <- result.try(decode_internal_atom(
              child.1,
              originator,
              compressor,
            ))
            Ok(#(index, id))
          }),
        )
        Ok(#(key, change.GenericField(children)))
      }
      "Value" | "Optional" -> {
        use replacement <- result.try(
          fixture_codec.field(encoded, "valueReplace", fn(replacement) {
            use was_empty <- result.try(fixture_codec.field(
              replacement,
              "isEmpty",
              fixture_codec.boolean,
            ))
            let source = case fixture_codec.get(replacement, "src") {
              Error(_) -> Ok(None)
              Ok(source) ->
                decode_internal_atom(source, originator, compressor)
                |> result.map(optional_field.Detached)
                |> result.map(Some)
            }
            use source <- result.try(source)
            use detach <- result.try(
              fixture_codec.field(replacement, "dst", fn(value) {
                decode_internal_atom(value, originator, compressor)
              }),
            )
            Ok(optional_field.Replacement(was_empty, source, detach))
          }),
        )
        let field_change = optional_field.FieldChange([], [], Some(replacement))
        Ok(
          #(key, case kind {
            "Value" -> change.ValueField(field_change)
            _ -> change.OptionalField(field_change)
          }),
        )
      }
      _ -> Error("unsupported algebra field kind " <> kind)
    }
  })
}

fn decode_internal_nodes(
  value: JsonValue,
  originator: fluid_ids.SessionId,
  compressor: fluid_ids.Compressor,
) -> Result(List(#(types.AtomId, change.NodeChange)), String) {
  use entries <- result.try(internal_btree_entries(value))
  list.try_map(entries, fn(entry) {
    use id <- result.try(decode_internal_atom(entry.0, originator, compressor))
    use fields <- result.try(
      fixture_codec.field(entry.1, "fieldChanges", fn(value) {
        decode_internal_fields(value, originator, compressor)
      }),
    )
    Ok(#(id, change.NodeChange(fields)))
  })
}

fn decode_internal_parents(
  value: JsonValue,
  originator: fluid_ids.SessionId,
  compressor: fluid_ids.Compressor,
) -> Result(List(#(types.AtomId, change.ParentField)), String) {
  use entries <- result.try(internal_btree_entries(value))
  list.try_map(entries, fn(entry) {
    use id <- result.try(decode_internal_atom(entry.0, originator, compressor))
    use field <- result.try(fixture_codec.field(
      entry.1,
      "field",
      fixture_codec.text,
    ))
    let parent = case fixture_codec.get(entry.1, "parent") {
      Error(_) -> Ok(None)
      Ok(parent) ->
        decode_internal_atom(parent, originator, compressor)
        |> result.map(Some)
    }
    use parent <- result.try(parent)
    Ok(#(id, change.ParentField(parent, field)))
  })
}

fn decode_internal_aliases(
  value: JsonValue,
  originator: fluid_ids.SessionId,
  compressor: fluid_ids.Compressor,
) -> Result(List(#(types.AtomId, types.AtomId)), String) {
  use entries <- result.try(internal_btree_entries(value))
  list.try_map(entries, fn(entry) {
    use source <- result.try(decode_internal_atom(
      entry.0,
      originator,
      compressor,
    ))
    use destination <- result.try(decode_internal_atom(
      entry.1,
      originator,
      compressor,
    ))
    Ok(#(source, destination))
  })
}

fn decode_internal_builds(
  value: JsonValue,
  originator: fluid_ids.SessionId,
  compressor: fluid_ids.Compressor,
) -> Result(List(forest.Build), String) {
  use entries <- result.try(internal_btree_entries(value))
  list.try_map(entries, fn(entry) {
    use id <- result.try(decode_internal_atom(entry.0, originator, compressor))
    use tree <- result.try(decode_internal_tree(entry.1))
    Ok(forest.Build(id, [tree]))
  })
}

fn decode_internal_destroys(
  value: JsonValue,
  originator: fluid_ids.SessionId,
  compressor: fluid_ids.Compressor,
) -> Result(List(forest.Destroy), String) {
  use entries <- result.try(internal_btree_entries(value))
  list.try_map(entries, fn(entry) {
    use id <- result.try(decode_internal_atom(entry.0, originator, compressor))
    use count <- result.try(fixture_codec.integer(entry.1))
    Ok(forest.Destroy(id, count))
  })
}

fn decode_internal_tree(value: JsonValue) -> Result(types.TreeValue, String) {
  use kind <- result.try(fixture_codec.field(value, "type", fixture_codec.text))
  case kind {
    "com.fluidframework.leaf.string" -> {
      use value <- result.try(fixture_codec.field(
        value,
        "value",
        fixture_codec.text,
      ))
      Ok(StringValue(value))
    }
    _ -> Error("unsupported algebra build type " <> kind)
  }
}

fn internal_map_entries(value: JsonValue) -> Result(List(JsonValue), String) {
  use kind <- result.try(fixture_codec.field(value, "$type", fixture_codec.text))
  case kind {
    "Map" -> fixture_codec.field(value, "entries", fixture_codec.items)
    _ -> Error("expected an internal Map")
  }
}

fn internal_btree_entries(
  value: JsonValue,
) -> Result(List(#(JsonValue, JsonValue)), String) {
  use root <- result.try(fixture_codec.get(value, "_root"))
  use keys <- result.try(fixture_codec.field(root, "keys", fixture_codec.items))
  use values <- result.try(fixture_codec.field(
    root,
    "values",
    fixture_codec.items,
  ))
  case list.length(values) >= list.length(keys) {
    True -> Ok(list.zip(keys, list.take(values, list.length(keys))))
    False -> Error("internal tree has fewer values than keys")
  }
}

fn decode_empty_operand(
  value: JsonValue,
) -> Result(shared_change.Changeset, String) {
  use _ <- result.try(fixture_codec.exact(value, ["changes"]))
  use changes <- result.try(fixture_codec.field(
    value,
    "changes",
    fixture_codec.items,
  ))
  case changes {
    [] -> Ok(shared_change.empty())
    _ -> Error("empty operand contains changes")
  }
}

fn single_outer_change(
  value: JsonValue,
  expected: String,
) -> Result(JsonValue, String) {
  use _ <- result.try(fixture_codec.exact(value, ["changes"]))
  use changes <- result.try(fixture_codec.field(
    value,
    "changes",
    fixture_codec.items,
  ))
  case changes {
    [item] -> {
      use _ <- result.try(fixture_codec.exact(item, ["type", "innerChange"]))
      use kind <- result.try(fixture_codec.field(
        item,
        "type",
        fixture_codec.text,
      ))
      case kind == expected {
        True -> fixture_codec.get(item, "innerChange")
        False -> Error("unexpected outer change type " <> kind)
      }
    }
    _ -> Error("operand must contain one outer change")
  }
}

fn run_algebra_scenario(
  id: String,
  state: AlgebraState,
) -> Result(Json, String) {
  case id {
    "schema-over-data" ->
      rebase_observation(id, state.schema_change, state.data_change, state)
    "data-over-schema" ->
      rebase_observation(id, state.data_change, state.schema_change, state)
    "schema-over-schema" ->
      rebase_observation(
        id,
        state.schema_change,
        state.second_schema_change,
        state,
      )
    "empty-operand" ->
      rebase_observation(id, state.schema_change, state.empty_change, state)
    "data-schema-data-schema-compose" -> compose_observation(id, state)
    "inverse-schema-encoding-refusal" -> inverse_observation(id, state)
    _ -> Error("unknown algebra scenario " <> id)
  }
}

fn rebase_observation(
  id: String,
  value: shared_change.TaggedChange,
  over: shared_change.TaggedChange,
  state: AlgebraState,
) -> Result(Json, String) {
  use context <- result.try(
    change.rebase_context(list.append(
      shared_change.revision_infos(value),
      shared_change.revision_infos(over),
    ))
    |> result.map_error(string.inspect),
  )
  use rebased <- result.try(
    shared_change.rebase(value, over, context)
    |> result.map_error(string.inspect),
  )
  use encoded <- result.try(encode_outer(rebased, None, state))
  Ok(json.object([#("id", json.string(id)), #("change", encoded)]))
}

fn compose_observation(
  id: String,
  state: AlgebraState,
) -> Result(Json, String) {
  let second_data =
    shared_change.TaggedChange(
      Some(state.second_data_revision),
      None,
      state.data_change.change,
    )
  let changes = [
    state.data_change,
    state.schema_change,
    second_data,
    state.second_schema_change,
  ]
  use composed <- result.try(
    shared_change.compose(changes) |> result.map_error(string.inspect),
  )
  use encoded <- result.try(encode_outer(composed, None, state))
  use revisions <- result.try(
    list.try_map(changes, fn(tagged) {
      case tagged.revision {
        None -> Error("composed algebra change has no revision")
        Some(revision) -> encode_revision(revision, state)
      }
    }),
  )
  Ok(
    json.object([
      #("id", json.string(id)),
      #(
        "kinds",
        json.array(shared_change.to_changes(composed), fn(item) {
          json.string(case item {
            shared_change.DataChange(_) -> "data"
            shared_change.SchemaChange(_, _, _) -> "schema"
          })
        }),
      ),
      #("change", encoded),
      #("revisions", json.array(revisions, fn(value) { value })),
    ]),
  )
}

fn inverse_observation(
  id: String,
  state: AlgebraState,
) -> Result(Json, String) {
  let second_data =
    shared_change.TaggedChange(
      Some(state.second_data_revision),
      None,
      state.data_change.change,
    )
  use composed <- result.try(
    shared_change.compose([
      state.data_change,
      state.schema_change,
      second_data,
      state.second_schema_change,
    ])
    |> result.map_error(string.inspect),
  )
  use inverted <- result.try(
    shared_change.invert(
      shared_change.TaggedChange(
        state.second_schema_change.revision,
        None,
        composed,
      ),
      True,
      state.inverse_revision,
    )
    |> result.map_error(string.inspect),
  )
  use encoded <- result.try(encode_outer(
    inverted,
    Some(state.inverse_revision),
    state,
  ))
  let error = case encode_for_wire(inverted) {
    Ok(_) -> "missing inverse schema encoding refusal"
    Error(detail) -> detail
  }
  use revision <- result.try(encode_revision(state.inverse_revision, state))
  Ok(
    json.object([
      #("id", json.string(id)),
      #("error", json.string(error)),
      #("change", encoded),
      #("revision", revision),
    ]),
  )
}

fn encode_outer(
  value: shared_change.Changeset,
  tagged_revision: Option(fluid_ids.StableId),
  state: AlgebraState,
) -> Result(Json, String) {
  use changes <- result.try(
    list.try_map(shared_change.to_changes(value), fn(item) {
      case item {
        shared_change.DataChange(data) -> {
          use inner <- result.try(case tagged_revision {
            None -> Ok(json_ot.to_json(state.data_encoding))
            Some(inverse_revision) -> {
              use rollback_revision <- result.try(
                case change.to_data(data).revisions {
                  [change.RevisionInfo(revision, Some(rollback_of))]
                    if revision == inverse_revision
                  -> Ok(rollback_of)
                  _ -> Error("invalid inverted algebra data metadata")
                },
              )
              inverse_data_json(
                state.data_encoding,
                inverse_revision,
                rollback_revision,
                state,
              )
            }
          })
          Ok(
            json.object([
              #("type", json.string("data")),
              #("innerChange", inner),
            ]),
          )
        }
        shared_change.SchemaChange(before, after, is_inverse) -> {
          use encoding <- result.try(find_schema_encoding(
            state.schema_encodings,
            before,
            after,
            is_inverse,
          ))
          Ok(
            json.object([
              #("type", json.string("schema")),
              #(
                "innerChange",
                json.object([
                  #(
                    "schema",
                    json.object([
                      #("old", json_ot.to_json(encoding.0)),
                      #("new", json_ot.to_json(encoding.1)),
                    ]),
                  ),
                  #("isInverse", json.bool(is_inverse)),
                ]),
              ),
            ]),
          )
        }
      }
    }),
  )
  Ok(json.object([#("changes", json.array(changes, fn(value) { value }))]))
}

fn find_schema_encoding(
  encodings: List(SchemaEncoding),
  before: schema.SchemaState,
  after: schema.SchemaState,
  is_inverse: Bool,
) -> Result(#(JsonValue, JsonValue), String) {
  use encoding <- result.try(
    list.find(encodings, fn(encoding) {
      case is_inverse {
        False -> encoding.before == before && encoding.after == after
        True -> encoding.before == after && encoding.after == before
      }
    })
    |> result.map_error(fn(_) { "missing schema encoding" }),
  )
  case is_inverse {
    False -> Ok(#(encoding.old, encoding.new))
    True -> Ok(#(encoding.new, encoding.old))
  }
}

fn encode_for_wire(value: shared_change.Changeset) -> Result(Nil, String) {
  case
    list.any(shared_change.to_changes(value), fn(item) {
      case item {
        shared_change.SchemaChange(_, _, True) -> True
        _ -> False
      }
    })
  {
    True -> Error("Error: 0x933")
    False -> Ok(Nil)
  }
}

fn encode_revision(
  revision: fluid_ids.StableId,
  state: AlgebraState,
) -> Result(Json, String) {
  codec.encode_stable_revision(
    revision,
    codec.EncodeContext(codec.Fluid310, state.compressor, None),
    "algebra revision",
  )
  |> result.map(json.int)
  |> result.map_error(string.inspect)
}

fn inverse_data_json(
  original: JsonValue,
  inverse_revision: fluid_ids.StableId,
  rollback_revision: fluid_ids.StableId,
  state: AlgebraState,
) -> Result(Json, String) {
  use field_changes <- result.try(fixture_codec.field(
    original,
    "fieldChanges",
    inverse_internal_fields,
  ))
  use node_changes <- result.try(fixture_codec.field(
    original,
    "nodeChanges",
    inverse_internal_nodes,
  ))
  use parents <- result.try(fixture_codec.field(
    original,
    "nodeToParent",
    strip_shared_tree,
  ))
  use aliases <- result.try(fixture_codec.get(original, "nodeAliases"))
  use cross_fields <- result.try(fixture_codec.get(original, "crossFieldKeys"))
  use max_id <- result.try(fixture_codec.get(original, "maxId"))
  use builds <- result.try(fixture_codec.get(original, "builds"))
  use destroys <- result.try(internal_destroys_from_builds(builds))
  use inverse_revision <- result.try(encode_revision_int(
    inverse_revision,
    state,
  ))
  use rollback_revision <- result.try(encode_revision_int(
    rollback_revision,
    state,
  ))
  Ok(
    json.object([
      #("fieldChanges", json_ot.to_json(field_changes)),
      #("nodeChanges", json_ot.to_json(node_changes)),
      #("nodeToParent", json_ot.to_json(parents)),
      #("nodeAliases", json_ot.to_json(aliases)),
      #("crossFieldKeys", json_ot.to_json(cross_fields)),
      #(
        "revisions",
        json.array(
          [
            json.object([
              #("revision", json.int(inverse_revision)),
              #("rollbackOf", json.int(rollback_revision)),
            ]),
          ],
          fn(value) { value },
        ),
      ),
      #("maxId", json_ot.to_json(max_id)),
      #("destroys", json_ot.to_json(destroys)),
    ]),
  )
}

fn inverse_internal_fields(value: JsonValue) -> Result(JsonValue, String) {
  use entries <- result.try(internal_map_entries(value))
  use entries <- result.try(
    list.try_map(entries, fn(entry) {
      use #(key, field) <- result.try(fixture_codec.pair(entry))
      use kind <- result.try(fixture_codec.field(
        field,
        "fieldKind",
        fixture_codec.text,
      ))
      case kind {
        "Value" | "Optional" -> {
          use encoded <- result.try(fixture_codec.get(field, "change"))
          use replacement <- result.try(fixture_codec.get(
            encoded,
            "valueReplace",
          ))
          use is_empty <- result.try(fixture_codec.get(replacement, "isEmpty"))
          use source <- result.try(fixture_codec.get(replacement, "src"))
          use destination <- result.try(fixture_codec.get(replacement, "dst"))
          let replacement =
            VObject([
              #("isEmpty", is_empty),
              #("dst", source),
              #("src", destination),
            ])
          use moves <- result.try(fixture_codec.get(encoded, "moves"))
          use children <- result.try(fixture_codec.get(encoded, "childChanges"))
          Ok(
            VArray([
              key,
              VObject([
                #("fieldKind", VString(kind)),
                #(
                  "change",
                  VObject([
                    #("moves", moves),
                    #("childChanges", children),
                    #("valueReplace", replacement),
                  ]),
                ),
              ]),
            ]),
          )
        }
        _ -> Ok(entry)
      }
    }),
  )
  Ok(
    VObject([
      #("$type", VString("Map")),
      #("entries", VArray(entries)),
    ]),
  )
}

fn inverse_internal_nodes(value: JsonValue) -> Result(JsonValue, String) {
  use root <- result.try(fixture_codec.get(value, "_root"))
  use keys <- result.try(fixture_codec.get(root, "keys"))
  use values <- result.try(fixture_codec.field(
    root,
    "values",
    fixture_codec.items,
  ))
  use values <- result.try(
    list.try_map(values, fn(node) {
      use fields <- result.try(fixture_codec.field(
        node,
        "fieldChanges",
        inverse_internal_fields,
      ))
      Ok(VObject([#("fieldChanges", fields)]))
    }),
  )
  use max_size <- result.try(fixture_codec.get(value, "_maxNodeSize"))
  Ok(
    VObject([
      #("_root", VObject([#("keys", keys), #("values", VArray(values))])),
      #("_maxNodeSize", max_size),
    ]),
  )
}

fn strip_shared_tree(value: JsonValue) -> Result(JsonValue, String) {
  use root <- result.try(fixture_codec.get(value, "_root"))
  use keys <- result.try(fixture_codec.get(root, "keys"))
  use values <- result.try(fixture_codec.get(root, "values"))
  use max_size <- result.try(fixture_codec.get(value, "_maxNodeSize"))
  Ok(
    VObject([
      #("_root", VObject([#("keys", keys), #("values", values)])),
      #("_maxNodeSize", max_size),
    ]),
  )
}

fn internal_destroys_from_builds(
  value: JsonValue,
) -> Result(JsonValue, String) {
  use root <- result.try(fixture_codec.get(value, "_root"))
  use keys <- result.try(fixture_codec.get(root, "keys"))
  use builds <- result.try(fixture_codec.field(
    root,
    "values",
    fixture_codec.items,
  ))
  use counts <- result.try(
    list.try_map(builds, fn(build) {
      fixture_codec.get(build, "topLevelLength")
    }),
  )
  use max_size <- result.try(fixture_codec.get(value, "_maxNodeSize"))
  Ok(
    VObject([
      #("_root", VObject([#("keys", keys), #("values", VArray(counts))])),
      #("_maxNodeSize", max_size),
    ]),
  )
}

fn encode_revision_int(
  revision: fluid_ids.StableId,
  state: AlgebraState,
) -> Result(Int, String) {
  codec.encode_stable_revision(
    revision,
    codec.EncodeContext(codec.Fluid310, state.compressor, None),
    "algebra revision",
  )
  |> result.map_error(string.inspect)
}

fn int_max(left: Int, right: Int) -> Int {
  case left > right {
    True -> left
    False -> right
  }
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
