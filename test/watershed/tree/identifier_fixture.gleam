import gleam/bit_array
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import watershed/canonical_json
import watershed/channel
import watershed/fluid_ids
import watershed/json_ot.{
  type JsonValue, NInt, VArray, VBool, VNull, VNumber, VObject, VString,
}
import watershed/runtime_core
import watershed/tree/change_fixture_codec as fixture_codec
import watershed/tree/codec
import watershed/tree/codec/field_batch
import watershed/tree/codec/summary as summary_codec
import watershed/tree/forest
import watershed/tree/history
import watershed/tree/identifier
import watershed/tree/runtime as tree_runtime
import watershed/tree/runtime_fixture
import watershed/tree/schema
import watershed/tree/summary as tree_summary
import watershed/tree/transaction
import watershed/tree/types
import watershed/tree_kernel
import watershed/wire/fluid_container
import watershed/wire/fluid_summary

pub const point_type = "org.watershed.shared-tree.identifiers.Point"

pub const pair_type = "org.watershed.shared-tree.identifiers.Pair"

pub const items_type = "org.watershed.shared-tree.identifiers.Items"

pub const map_type = "org.watershed.shared-tree.identifiers.PointsByKey"

pub const root_type = "org.watershed.shared-tree.identifiers.Root"

pub fn run(input: json.Json) -> Result(json.Json, String) {
  use input <- result.try(fixture_codec.parse(input))
  use _ <- result.try(
    fixture_codec.exact(input, [
      "version",
      "schema",
      "initialTree",
      "sessions",
      "compressors",
      "idRanges",
      "scenarios",
    ]),
  )
  use version <- result.try(fixture_codec.field(
    input,
    "version",
    fixture_codec.integer,
  ))
  use _ <- result.try(require(
    version == 1,
    "unsupported Identifier input version",
  ))
  use schema_value <- result.try(fixture_codec.get(input, "schema"))
  use stored <- result.try(
    schema.stored_from_json(json_ot.to_json(schema_value))
    |> result.map_error(string.inspect),
  )
  use initial_value <- result.try(fixture_codec.get(input, "initialTree"))
  use initial <- result.try(decode_captured_tree(initial_value))
  use sessions <- result.try(fixture_codec.get(input, "sessions"))
  use compressors <- result.try(fixture_codec.get(input, "compressors"))
  use ranges <- result.try(fixture_codec.field(
    input,
    "idRanges",
    fixture_codec.items,
  ))
  use scenarios <- result.try(fixture_codec.field(
    input,
    "scenarios",
    fixture_codec.items,
  ))
  use observations <- result.try(
    list.try_map(scenarios, fn(scenario) {
      run_scenario(scenario, stored, initial, sessions, compressors, ranges)
    }),
  )
  Ok(json.object([#("observations", fixture_codec.array(observations))]))
}

pub fn initial_summary_semantics(
  input: json.Json,
  encoded: JsonValue,
  has_initialization_commit: Bool,
) -> Result(json.Json, String) {
  use input <- result.try(fixture_codec.parse(input))
  use schema_value <- result.try(fixture_codec.get(input, "schema"))
  use stored <- result.try(
    schema.stored_from_json(json_ot.to_json(schema_value))
    |> result.map_error(string.inspect),
  )
  use initial_value <- result.try(fixture_codec.get(input, "initialTree"))
  use initial <- result.try(decode_captured_tree(initial_value))
  use sessions <- result.try(fixture_codec.get(input, "sessions"))
  use compressors <- result.try(fixture_codec.get(input, "compressors"))
  use local <- result.try(input_session(sessions, "local"))
  use compressor <- result.try(input_compressor(
    compressors,
    sessions,
    "initial",
  ))
  use #(root, compressor) <- result.try(
    identifier.materialize_value(stored, initial, compressor)
    |> result.map_error(string.inspect),
  )
  use compressor <- result.try(finalize_local_ids(compressor))
  use compressor <- result.try(case has_initialization_commit {
    True ->
      fluid_ids.generate(compressor)
      |> result.map(fn(value) { value.0 })
      |> result.map_error(string.inspect)
    False -> Ok(compressor)
  })
  use entry <- result.try(summary_entry(encoded))
  use data <- result.try(
    summary_codec.decode(
      entry,
      None,
      local,
      codec.DecodeContext(codec.Fluid310, compressor),
    )
    |> result.map_error(string.inspect),
  )
  let summary_codec.TreeSummaryData(
    summary_stored,
    summary_codec.ForestSummary(fields),
    summary_codec.DetachedFieldIndex(detached, max_id),
    summary_codec.EditManagerSummary(trunk, branches),
  ) = data
  use _ <- result.try(case has_initialization_commit, trunk, branches {
    True, [_], [] -> Ok(Nil)
    False, [], [] -> Ok(Nil)
    True, _, _ ->
      Error("upstream initialization history is not one isolated commit")
    False, _, _ -> Error("native initialization history is not empty")
  })
  use snapshot <- result.try(
    tree_summary.from_wire(data, view_id(), compressor, 2, 2)
    |> result.map_error(string.inspect),
  )
  use restored <- result.try(
    tree_kernel.restore(snapshot, view_id(), local, full_view())
    |> result.map_error(string.inspect),
  )
  use restored_root <- result.try(visible_root(restored))
  use restored_json <- result.try(
    json_ot.parse_json(json.to_string(visible_json(restored_root)))
    |> result.map_error(string.inspect),
  )
  use root_json <- result.try(
    json_ot.parse_json(json.to_string(visible_json(root)))
    |> result.map_error(string.inspect),
  )
  use _ <- result.try(require(
    canonical_json.to_string(restored_json)
      == canonical_json.to_string(root_json),
    "initial summary does not restore the captured tree",
  ))
  Ok(
    json.object([
      #("schema", schema.stored_to_json(summary_stored)),
      #(
        "forest",
        json.object(
          list.map(fields, fn(field) {
            #(field.0, json.array(field.1, visible_json))
          }),
        ),
      ),
      #(
        "detached",
        detached
          |> list.map(fn(entry) {
            let summary_codec.DetachedField(major, minor, root) = entry
            json.object([
              #("major", case major {
                summary_codec.RootRevision -> json.null()
                summary_codec.StableRevision(value) ->
                  json.string(fluid_ids.stable_id_to_string(value))
              }),
              #("minor", json.int(minor)),
              #("root", json.int(root)),
            ])
          })
          |> fixture_codec.array,
      ),
      #("maxDetachedId", json.int(max_id)),
      #(
        "history",
        json.object([
          #("trunk", fixture_codec.array([])),
          #("branches", fixture_codec.array([])),
        ]),
      ),
    ]),
  )
}

pub fn stored() -> schema.StoredSchema {
  let assert Ok(value) = schema.stored_from_json(schema_json("Identifier"))
  value
}

pub fn view(kind: String) -> schema.ViewSchema {
  let assert Ok(value) =
    schema.view_from_string(json.to_string(schema_json(kind)))
  value
}

pub fn point(identifier: String, label: String) -> types.TreeValue {
  types.ObjectValue(point_type, [
    #("id", types.StringValue(identifier)),
    #("label", types.StringValue(label)),
  ])
}

pub fn full_stored() -> schema.StoredSchema {
  let assert Ok(value) =
    schema.stored_from_string(
      "{\"version\":2,\"nodes\":{
        \"com.fluidframework.leaf.string\":{\"kind\":{\"leaf\":1}},
        \"org.watershed.shared-tree.identifiers.Items\":{\"kind\":{\"object\":{
          \"\":{\"kind\":\"Sequence\",\"types\":[
            \"org.watershed.shared-tree.identifiers.Pair\",
            \"org.watershed.shared-tree.identifiers.Point\"
          ]}
        }}},
        \"org.watershed.shared-tree.identifiers.Pair\":{\"kind\":{\"object\":{
          \"firstId\":{\"kind\":\"Identifier\",\"types\":[\"com.fluidframework.leaf.string\"]},
          \"label\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.string\"]},
          \"pairOnly\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.string\"]},
          \"secondId\":{\"kind\":\"Identifier\",\"types\":[\"com.fluidframework.leaf.string\"]}
        }}},
        \"org.watershed.shared-tree.identifiers.Point\":{\"kind\":{\"object\":{
          \"id\":{\"kind\":\"Identifier\",\"types\":[\"com.fluidframework.leaf.string\"]},
          \"label\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.string\"]}
        }}},
        \"org.watershed.shared-tree.identifiers.PointsByKey\":{\"kind\":{\"map\":{
          \"kind\":\"Optional\",\"types\":[
            \"org.watershed.shared-tree.identifiers.Pair\",
            \"org.watershed.shared-tree.identifiers.Point\"
          ]
        }}},
        \"org.watershed.shared-tree.identifiers.Root\":{\"kind\":{\"object\":{
          \"byKey\":{\"kind\":\"Value\",\"types\":[\"org.watershed.shared-tree.identifiers.PointsByKey\"]},
          \"child\":{\"kind\":\"Value\",\"types\":[\"org.watershed.shared-tree.identifiers.Point\"]},
          \"left\":{\"kind\":\"Value\",\"types\":[\"org.watershed.shared-tree.identifiers.Items\"]},
          \"right\":{\"kind\":\"Value\",\"types\":[\"org.watershed.shared-tree.identifiers.Items\"]}
        }}}
      },\"root\":{\"kind\":\"Value\",\"types\":[\"org.watershed.shared-tree.identifiers.Root\"]}}",
    )
  value
}

pub fn full_view() -> schema.ViewSchema {
  let assert Ok(value) =
    full_stored()
    |> schema.stored_to_json
    |> json.to_string
    |> schema.view_from_string
  value
}

pub fn full_root(
  child: types.TreeValue,
  left: List(types.TreeValue),
  right: List(types.TreeValue),
  by_key: List(#(String, types.TreeValue)),
) -> types.TreeValue {
  types.ObjectValue(root_type, [
    #("child", child),
    #("left", types.ArrayValue(items_type, left)),
    #("right", types.ArrayValue(items_type, right)),
    #("byKey", types.MapValue(map_type, by_key)),
  ])
}

pub fn pair(
  first_id: String,
  second_id: String,
  label: String,
) -> types.TreeValue {
  types.ObjectValue(pair_type, [
    #("firstId", types.StringValue(first_id)),
    #("secondId", types.StringValue(second_id)),
    #("label", types.StringValue(label)),
    #("pairOnly", types.StringValue(label)),
  ])
}

pub fn state(
  stored: schema.StoredSchema,
  view: schema.ViewSchema,
  root: types.TreeValue,
) -> tree_kernel.TreeState {
  let initial = history.inspect(history.new(session())).sequenced
  let assert Ok(snapshot) =
    tree_kernel.snapshot_from_parts(
      view_id(),
      stored,
      forest.ForestData(Some(root), [], 0),
      initial,
    )
  let assert Ok(value) =
    tree_kernel.restore(snapshot, view_id(), session(), view)
  value
}

fn state_for_session(
  stored: schema.StoredSchema,
  view: schema.ViewSchema,
  root: types.TreeValue,
  local_session: fluid_ids.SessionId,
) -> Result(tree_kernel.TreeState, String) {
  use snapshot <- result.try(
    tree_kernel.snapshot_from_parts(
      view_id(),
      stored,
      forest.ForestData(Some(root), [], 0),
      history.HistorySnapshot(history.InitialBase, [], [], 0, 0),
    )
    |> result.map_error(string.inspect),
  )
  tree_kernel.restore(snapshot, view_id(), local_session, view)
  |> result.map_error(string.inspect)
}

pub fn seed_input() -> runtime_core.BootstrapSeedInput {
  let assert Ok(#(input, _)) = runtime_fixture.routed_seed_input()
  let assert [tree_view] = input.tree_views
  let view = view("Identifier")
  let assert Ok(snapshot) =
    tree_kernel.snapshot_from_parts(
      tree_view.view_id,
      stored(),
      forest.ForestData(Some(point("literal-custom-id", "before")), [], 0),
      history.HistorySnapshot(history.InitialBase, [], [], 0, 0),
    )
  runtime_core.BootstrapSeedInput(
    ..input,
    sequence_number: 0,
    minimum_sequence_number: 0,
    tree_views: [runtime_core.TreeViewSeed(..tree_view, view:)],
    channels: list.map(input.channels, fn(seed) {
      case seed.route == tree_view.route {
        True ->
          runtime_core.ChannelSeed(
            ..seed,
            snapshot: channel.TreeSnapshot(snapshot),
          )
        False -> seed
      }
    }),
    bootstrap_map: fluid_container.Route("A", "root"),
  )
}

pub fn full_seed_input(
  root: types.TreeValue,
) -> runtime_core.BootstrapSeedInput {
  let assert Ok(#(input, _)) = runtime_fixture.routed_seed_input()
  let assert [tree_view] = input.tree_views
  let view = full_view()
  let assert Ok(snapshot) =
    tree_kernel.snapshot_from_parts(
      tree_view.view_id,
      full_stored(),
      forest.ForestData(Some(root), [], 0),
      history.HistorySnapshot(history.InitialBase, [], [], 0, 0),
    )
  runtime_core.BootstrapSeedInput(
    ..input,
    sequence_number: 0,
    minimum_sequence_number: 0,
    tree_views: [runtime_core.TreeViewSeed(..tree_view, view:)],
    channels: list.map(input.channels, fn(seed) {
      case seed.route == tree_view.route {
        True ->
          runtime_core.ChannelSeed(
            ..seed,
            snapshot: channel.TreeSnapshot(snapshot),
          )
        False -> seed
      }
    }),
    bootstrap_map: fluid_container.Route("A", "root"),
  )
}

pub fn pair_stored() -> schema.StoredSchema {
  let assert Ok(value) =
    schema.stored_from_json(
      json.object([
        #("version", json.int(2)),
        #(
          "nodes",
          json.object([
            #(
              "com.fluidframework.leaf.string",
              json.object([#("kind", json.object([#("leaf", json.int(1))]))]),
            ),
            #(
              point_type,
              json.object([
                #(
                  "kind",
                  json.object([
                    #(
                      "object",
                      json.object([
                        #(
                          "id",
                          field("Identifier", "com.fluidframework.leaf.string"),
                        ),
                        #(
                          "label",
                          field("Value", "com.fluidframework.leaf.string"),
                        ),
                      ]),
                    ),
                  ]),
                ),
              ]),
            ),
            #(
              "Pair",
              json.object([
                #(
                  "kind",
                  json.object([
                    #(
                      "object",
                      json.object([
                        #("left", field("Value", point_type)),
                        #("right", field("Value", point_type)),
                      ]),
                    ),
                  ]),
                ),
              ]),
            ),
          ]),
        ),
        #("root", field("Value", "Pair")),
      ]),
    )
  value
}

pub fn pair_view() -> schema.ViewSchema {
  let assert Ok(value) =
    pair_stored()
    |> schema.stored_to_json
    |> json.to_string
    |> schema.view_from_string
  value
}

pub fn session() -> fluid_ids.SessionId {
  let assert Ok(value) =
    fluid_ids.session_id("10000000-0000-4000-8000-000000000001")
  value
}

pub fn sender_session() -> fluid_ids.SessionId {
  let assert Ok(value) =
    fluid_ids.session_id("11111111-1111-4111-8111-111111111111")
  value
}

pub fn receiver_session() -> fluid_ids.SessionId {
  let assert Ok(value) =
    fluid_ids.session_id("22222222-2222-4222-8222-222222222222")
  value
}

fn view_id() -> fluid_ids.StableId {
  let assert Ok(value) =
    fluid_ids.stable_id("30000000-0000-4000-8000-000000000003")
  value
}

fn schema_json(kind: String) -> json.Json {
  json.object([
    #("version", json.int(2)),
    #(
      "nodes",
      json.object([
        #(
          "com.fluidframework.leaf.string",
          json.object([#("kind", json.object([#("leaf", json.int(1))]))]),
        ),
        #(
          point_type,
          json.object([
            #(
              "kind",
              json.object([
                #(
                  "object",
                  json.object([
                    #("id", field(kind, "com.fluidframework.leaf.string")),
                    #("label", field("Value", "com.fluidframework.leaf.string")),
                  ]),
                ),
              ]),
            ),
          ]),
        ),
      ]),
    ),
    #("root", field("Value", point_type)),
  ])
}

fn field(kind: String, type_id: String) -> json.Json {
  json.object([
    #("kind", json.string(kind)),
    #("types", json.array([type_id], json.string)),
  ])
}

fn run_scenario(
  scenario: JsonValue,
  stored: schema.StoredSchema,
  initial: types.TreeValue,
  sessions: JsonValue,
  compressors: JsonValue,
  ranges: List(JsonValue),
) -> Result(json.Json, String) {
  use _ <- result.try(fixture_codec.exact(scenario, ["id", "actions"]))
  use id <- result.try(fixture_codec.field(scenario, "id", fixture_codec.text))
  use actions <- result.try(fixture_codec.field(
    scenario,
    "actions",
    fixture_codec.items,
  ))
  use first <- result.try(
    list.first(actions) |> result.map_error(fn(_) { id <> ": missing actions" }),
  )
  use operation <- result.try(fixture_codec.field(
    first,
    "op",
    fixture_codec.text,
  ))
  case operation {
    "validate-schema" -> run_schema_validation(id, first)
    "compare-schema" -> run_schema_comparison(id, first)
    "decode-field-change" -> run_identifier_field_change(id, first)
    "construct" -> run_constructs(id, actions, stored, sessions, compressors)
    "set" | "clear" | "insert" ->
      run_value_actions(id, actions, stored, initial, sessions, compressors)
    "allocate-id"
    | "deliver-range"
    | "encode-field-batch"
    | "decode-field-batch" ->
      run_field_batch(id, actions, sessions, compressors, ranges)
    "summarize" ->
      run_initial_summary(id, stored, initial, sessions, compressors)
    "load-summary" -> run_summary_tail(id, actions)
    "transaction" ->
      run_transaction_actions(
        id,
        actions,
        stored,
        initial,
        sessions,
        compressors,
      )
    "disconnect" ->
      run_retry(id, actions, stored, initial, sessions, compressors)
    "remove" -> run_remove(id, first, stored, initial, sessions, compressors)
    "move" -> run_move(id, first, stored, initial, sessions, compressors)
    _ -> Error(id <> ": unsupported Identifier action " <> operation)
  }
}

fn run_schema_validation(
  id: String,
  action: JsonValue,
) -> Result(json.Json, String) {
  use schema_value <- result.try(fixture_codec.get(action, "schema"))
  let declared_unsupported =
    fixture_codec.get(action, "nativeProfileSupported") == Ok(VBool(False))
  case schema.stored_from_json(json_ot.to_json(schema_value)) {
    Error(types.InvalidSchema(detail)) ->
      case
        declared_unsupported
        && string.contains(
          detail,
          "identifier field must be a named string field",
        )
      {
        True ->
          Ok(
            json.object([
              #("id", json.string(id)),
              #("nativeProfileSupported", json.bool(False)),
            ]),
          )
        False -> Error(string.inspect(types.InvalidSchema(detail)))
      }
    Error(error) -> Error(string.inspect(error))
    Ok(_) if declared_unsupported ->
      Error(id <> ": schema was declared outside the native profile")
    Ok(stored) -> {
      let pair_fields =
        ["firstId", "secondId"]
        |> list.filter_map(fn(name) {
          case schema.field_schema(stored, pair_type, name) {
            Ok(value) -> Ok(field_schema_json(value))
            Error(_) -> Error(Nil)
          }
        })
      use point_field <- result.try(
        schema.field_schema(stored, point_type, "id")
        |> result.map_error(string.inspect),
      )
      Ok(
        json.object([
          #("id", json.string(id)),
          #("field", field_schema_json(point_field)),
          #("fields", fixture_codec.array(pair_fields)),
        ]),
      )
    }
  }
}

fn run_identifier_field_change(
  id: String,
  action: JsonValue,
) -> Result(json.Json, String) {
  use encoded <- result.try(fixture_codec.get(action, "encoded"))
  let field =
    json.object([
      #("fieldKey", json.string("id")),
      #("fieldKind", json.string("Identifier")),
      #("change", json_ot.to_json(encoded)),
    ])
  let payload =
    json.array(
      [
        json.object([
          #(
            "data",
            json.object([
              #("changes", json.array([field], fn(value) { value })),
            ]),
          ),
        ]),
      ],
      fn(value) { value },
    )
  let compressor = fluid_ids.new(session())
  let decode_context = codec.DecodeContext(codec.Fluid310, compressor)
  let change_context = codec.ChangeContext(session(), None, codec.Message)
  use decoded <- result.try(
    codec.decode_changes(payload, decode_context, change_context)
    |> result.map_error(string.inspect),
  )
  use reencoded <- result.try(
    codec.encode_changes(
      decoded,
      codec.EncodeContext(codec.Fluid310, compressor, None),
      change_context,
    )
    |> result.map_error(string.inspect),
  )
  use canonical <- result.try(identifier_change_value(reencoded))
  Ok(
    json.object([
      #("id", json.string(id)),
      #("encoded", canonical),
      #("decodedNoncanonical", canonical),
    ]),
  )
}

fn run_schema_comparison(
  id: String,
  action: JsonValue,
) -> Result(json.Json, String) {
  use from <- result.try(fixture_codec.field(action, "from", fixture_codec.text))
  use to <- result.try(fixture_codec.field(action, "to", fixture_codec.text))
  let allowed =
    schema.can_view(view(from) |> schema.view_to_stored, view(to))
    |> result.is_ok
  Ok(
    json.object([
      #("id", json.string(id)),
      #("allowed", json.bool(allowed)),
    ]),
  )
}

fn run_constructs(
  id: String,
  actions: List(JsonValue),
  stored: schema.StoredSchema,
  sessions: JsonValue,
  compressors: JsonValue,
) -> Result(json.Json, String) {
  use compressor <- result.try(input_compressor(
    compressors,
    sessions,
    "initial",
  ))
  use #(values, compressor) <- result.try(
    list.try_fold(actions, #([], compressor), fn(state, action) {
      let value = case fixture_codec.get(action, "value") {
        Error(_) -> fixture_codec.get(action, "fields")
        Ok(value) -> Ok(value)
      }
      use fields <- result.try(value)
      use type_id <- result.try(fixture_codec.field(
        action,
        "schema",
        fixture_codec.text,
      ))
      use value <- result.try(
        decode_captured_tree(
          VObject([
            #("schema", VString(type_id)),
            #("fields", fields),
          ]),
        ),
      )
      use #(value, next) <- result.try(
        identifier.materialize_value(stored, value, state.1)
        |> result.map_error(string.inspect),
      )
      Ok(#([value, ..state.0], next))
    }),
  )
  let values = list.reverse(values)
  case values {
    [types.ObjectValue(type_id, fields)] if type_id == point_type ->
      Ok(
        json.object([
          #("id", json.string(id)),
          #("value", field_string(fields, "id")),
        ]),
      )
    [types.ObjectValue(type_id, fields)] if type_id == pair_type ->
      Ok(
        json.object([
          #("id", json.string(id)),
          #(
            "values",
            json.array(
              [
                field_string(fields, "firstId"),
                field_string(fields, "secondId"),
              ],
              fn(value) { value },
            ),
          ),
        ]),
      )
    [value] -> {
      use #(compressor, revision) <- result.try(
        generate_stable(compressor) |> result.map_error(string.inspect),
      )
      let _ = compressor
      Ok(
        json.object([
          #("id", json.string(id)),
          #("value", visible_json(value)),
          #("allocationEvents", allocation_events(value, revision, compressor)),
        ]),
      )
    }
    values ->
      Ok(
        json.object([
          #("id", json.string(id)),
          #(
            "values",
            json.array(
              list.map(values, fn(value) {
                case value {
                  types.ObjectValue(_, fields) -> field_string(fields, "id")
                  _ -> json.null()
                }
              }),
              fn(value) { value },
            ),
          ),
        ]),
      )
  }
}

fn run_value_actions(
  id: String,
  actions: List(JsonValue),
  stored: schema.StoredSchema,
  initial: types.TreeValue,
  sessions: JsonValue,
  compressors: JsonValue,
) -> Result(json.Json, String) {
  use compressor <- result.try(input_compressor(
    compressors,
    sessions,
    "initial",
  ))
  use action <- result.try(
    list.first(actions) |> result.map_error(fn(_) { id <> ": missing action" }),
  )
  use operation <- result.try(fixture_codec.field(
    action,
    "op",
    fixture_codec.text,
  ))
  use edit <- result.try(decode_edit(action))
  case actions {
    [_, _, ..] -> {
      use #(state, compressor) <- result.try(persistence_base(
        stored,
        initial,
        sessions,
        compressors,
      ))
      run_replacements(id, actions, state, compressor)
    }
    _ -> {
      let state = state(stored, full_view(), initial)
      run_one_value_action(id, operation, edit, state, compressor)
    }
  }
}

fn run_one_value_action(
  id: String,
  operation: String,
  edit: types.Edit,
  state: tree_kernel.TreeState,
  compressor: fluid_ids.Compressor,
) -> Result(json.Json, String) {
  case tree_runtime.author_edit(state, edit, compressor) {
    Error(_) ->
      Ok(
        json.object([
          #("id", json.string(id)),
          #("refused", json.bool(True)),
          #(
            "nativeErrorCategory",
            json.string(case operation {
              "clear" -> "UsageError"
              _ -> "Error"
            }),
          ),
        ]),
      )
    Ok(#(after, Some(commit), _, after_compressor)) ->
      case operation {
        "insert" ->
          Ok(
            json.object([
              #("id", json.string(id)),
              #(
                "events",
                edit_allocation_events(
                  after,
                  edit,
                  commit.revision,
                  after_compressor,
                ),
              ),
            ]),
          )
        _ -> {
          use value <- result.try(
            tree_kernel.read(after, ["child"])
            |> result.map_error(string.inspect)
            |> result.try(fn(value) {
              option.to_result(value, "child is absent")
            }),
          )
          Ok(
            json.object([
              #("id", json.string(id)),
              #("value", visible_json(value)),
            ]),
          )
        }
      }
    Ok(_) -> Error(id <> ": action produced no commit")
  }
}

fn run_field_batch(
  id: String,
  actions: List(JsonValue),
  sessions: JsonValue,
  compressors: JsonValue,
  ranges: List(JsonValue),
) -> Result(json.Json, String) {
  use states <- result.try(load_compressors(compressors, sessions))
  use result_state <- result.try(
    list.try_fold(actions, BatchState(states, [], [], []), fn(state, action) {
      run_batch_action(state, action, ranges)
    }),
  )
  let decoded = list.reverse(result_state.decoded)
  let encoded = list.reverse(result_state.encoded)
  let refusals = list.reverse(result_state.refusals)
  case decoded, encoded, refusals {
    [value], [], [] -> {
      use encoded_value <- result.try(last_decoded_input(actions))
      let fields = [
        #("id", json.string(id)),
        #("decoded", json.string(value)),
      ]
      let fields = case encoded_value {
        VString("0") -> [#("discriminator", json.int(0)), ..fields]
        VNumber(number) -> [
          #("encoded", json_ot.to_json(VNumber(number))),
          ..fields
        ]
        _ -> fields
      }
      let fields = case has_finalized_allocation(actions) {
        True -> [
          #("value", json.string(value)),
          #("allocatedAfterFinalization", json.bool(True)),
          ..fields
        ]
        False -> fields
      }
      Ok(json.object(fields))
    }
    [], [value], [] ->
      Ok(
        json.object([
          #("id", json.string(id)),
          #("encoded", value),
        ]),
      )
    [], [message, summary], [] ->
      Ok(
        json.object([
          #("id", json.string(id)),
          #("message", message),
          #("summary", summary),
        ]),
      )
    [], [], [refusal] ->
      Ok(
        json.object([
          #("id", json.string(id)),
          #("refused", json.bool(True)),
          #("nativeErrorCategory", json.string("Error")),
          #("value", refusal),
        ]),
      )
    [], [], refusals ->
      Ok(
        json.object([
          #("id", json.string(id)),
          #(
            "refusals",
            json.array(refusals, fn(value) {
              json.object([
                #("value", value),
                #("nativeErrorCategory", json.string("Error")),
              ])
            }),
          ),
        ]),
      )
    _, _, _ -> Error(id <> ": unsupported FieldBatch action result")
  }
}

type BatchState {
  BatchState(
    states: List(#(String, fluid_ids.Compressor)),
    decoded: List(String),
    encoded: List(json.Json),
    refusals: List(json.Json),
  )
}

fn run_batch_action(
  state: BatchState,
  action: JsonValue,
  ranges: List(JsonValue),
) -> Result(BatchState, String) {
  use operation <- result.try(fixture_codec.field(
    action,
    "op",
    fixture_codec.text,
  ))
  case operation {
    "allocate-id" -> {
      use name <- result.try(fixture_codec.field(
        action,
        "compressor",
        fixture_codec.text,
      ))
      use compressor <- result.try(named_compressor(state.states, name))
      use #(compressor, _) <- result.try(
        fluid_ids.generate(compressor) |> result.map_error(string.inspect),
      )
      Ok(
        BatchState(
          ..state,
          states: list.key_set(state.states, name, compressor),
        ),
      )
    }
    "deliver-range" -> {
      use name <- result.try(fixture_codec.field(
        action,
        "compressor",
        fixture_codec.text,
      ))
      use index <- result.try(fixture_codec.field(
        action,
        "range",
        fixture_codec.integer,
      ))
      use range <- result.try(
        ranges
        |> list.drop(index)
        |> list.first
        |> result.map_error(fn(_) { "allocation range is absent" }),
      )
      use range <- result.try(
        fluid_ids.creation_range_from_json(json_ot.to_json(range))
        |> result.map_error(string.inspect),
      )
      use compressor <- result.try(named_compressor(state.states, name))
      use compressor <- result.try(
        fluid_ids.finalize(compressor, range)
        |> result.map_error(string.inspect),
      )
      Ok(
        BatchState(
          ..state,
          states: list.key_set(state.states, name, compressor),
        ),
      )
    }
    "decode-field-batch" -> {
      let name = case
        fixture_codec.field(action, "compressor", fixture_codec.text)
      {
        Ok(value) -> value
        Error(_) -> "initial"
      }
      use compressor <- result.try(named_compressor(state.states, name))
      use encoded <- result.try(fixture_codec.get(action, "encoded"))
      use value <- result.try(fixture_codec.get(encoded, "value"))
      use purpose <- result.try(fixture_codec.field(
        action,
        "purpose",
        fixture_codec.text,
      ))
      use context <- result.try(id_context(action, purpose, compressor))
      case
        field_batch.decode_with_context(
          identifier_batch(json_ot.to_json(value)),
          None,
          context,
        )
      {
        Ok([[types.StringValue(value)]]) ->
          Ok(BatchState(..state, decoded: [value, ..state.decoded]))
        Ok(_) -> Error("Identifier FieldBatch decoded an unexpected shape")
        Error(_) ->
          Ok(
            BatchState(..state, refusals: [
              json_ot.to_json(value),
              ..state.refusals
            ]),
          )
      }
    }
    "encode-field-batch" -> {
      use value <- result.try(fixture_codec.field(
        action,
        "value",
        fixture_codec.text,
      ))
      use purpose <- result.try(fixture_codec.field(
        action,
        "purpose",
        fixture_codec.text,
      ))
      use compressor_name <- result.try(optional_text(
        action,
        "compressor",
        "initial",
      ))
      use compressor <- result.try(named_compressor(
        state.states,
        compressor_name,
      ))
      use context <- result.try(encode_id_context(
        action,
        purpose,
        compressor,
        value,
      ))
      use batch <- result.try(
        field_batch.encode_with_context(
          [
            [
              types.ObjectValue("IdentifierCodecNode", [
                #("id", types.StringValue(value)),
              ]),
            ],
          ],
          Some(identifier_codec_schema()),
          context,
        )
        |> result.map_error(string.inspect),
      )
      use encoded <- result.try(encoded_identifier_value(batch))
      Ok(BatchState(..state, encoded: [encoded, ..state.encoded]))
    }
    _ -> Error("unsupported FieldBatch action " <> operation)
  }
}

fn run_initial_summary(
  id: String,
  stored: schema.StoredSchema,
  initial: types.TreeValue,
  sessions: JsonValue,
  compressors: JsonValue,
) -> Result(json.Json, String) {
  use local <- result.try(input_session(sessions, "local"))
  use compressor <- result.try(input_compressor(
    compressors,
    sessions,
    "initial",
  ))
  use #(root, compressor) <- result.try(
    identifier.materialize_value(stored, initial, compressor)
    |> result.map_error(string.inspect),
  )
  use compressor <- result.try(finalize_local_ids(compressor))
  use view_id <- result.try(
    fluid_ids.stable_id("70000000-0000-4000-8000-000000000007")
    |> result.map_error(string.inspect),
  )
  use snapshot <- result.try(
    tree_kernel.snapshot_from_parts(
      view_id,
      stored,
      forest.ForestData(Some(root), [], 1),
      history.HistorySnapshot(history.InitialBase, [], [], 0, 0),
    )
    |> result.map_error(string.inspect),
  )
  use wire <- result.try(
    tree_summary.to_wire(snapshot) |> result.map_error(string.inspect),
  )
  use encoded <- result.try(
    summary_codec.encode(
      wire,
      local,
      codec.EncodeContext(codec.Fluid310, compressor, Some(stored)),
    )
    |> result.map_error(string.inspect),
  )
  Ok(
    json.object([
      #("id", json.string(id)),
      #("value", visible_json(root)),
      #("summary", summary_json(encoded)),
      #("allocationEvents", identifier_allocation_events(root, compressor)),
    ]),
  )
}

fn run_summary_tail(
  id: String,
  actions: List(JsonValue),
) -> Result(json.Json, String) {
  let assert [load, apply] = actions
  use summary_value <- result.try(fixture_codec.get(load, "summary"))
  use summary_entry <- result.try(summary_entry(summary_value))
  use serialized <- result.try(fixture_codec.field(
    load,
    "compressor",
    fixture_codec.text,
  ))
  use session_raw <- result.try(fixture_codec.field(
    load,
    "session",
    fixture_codec.text,
  ))
  use session <- result.try(
    fluid_ids.session_id(session_raw) |> result.map_error(string.inspect),
  )
  use compressor <- result.try(
    fluid_ids.deserialize(json.string(serialized), session)
    |> result.map_error(string.inspect),
  )
  use data <- result.try(
    summary_codec.decode(
      summary_entry,
      None,
      session,
      codec.DecodeContext(codec.Fluid310, compressor),
    )
    |> result.map_error(string.inspect),
  )
  use view_id <- result.try(
    fluid_ids.stable_id("70000000-0000-4000-8000-000000000007")
    |> result.map_error(string.inspect),
  )
  use snapshot <- result.try(
    tree_summary.from_wire(data, view_id, compressor, 2, 2)
    |> result.map_error(string.inspect),
  )
  use state <- result.try(
    tree_kernel.restore(snapshot, view_id, session, full_view())
    |> result.map_error(string.inspect),
  )
  use before <- result.try(visible_root(state))
  use compressor <- result.try(finalize_action_ranges(compressor, apply))
  use messages <- result.try(fixture_codec.field(
    apply,
    "messages",
    fixture_codec.items,
  ))
  use #(state, compressor) <- result.try(
    list.try_fold(messages, #(state, compressor), fn(current, message) {
      apply_tail_message(current.0, current.1, message)
    }),
  )
  use after <- result.try(visible_root(state))
  use reference <- result.try(
    tree_kernel.reference_at(state, ["byKey", "tail"])
    |> result.map_error(string.inspect),
  )
  use open <- result.try(
    transaction.begin(state, compressor, []) |> result.map_error(string.inspect),
  )
  use open <- result.try(
    transaction.apply_edit(
      open,
      types.MapSet(
        ["byKey"],
        "continued",
        types.ObjectValue(point_type, [
          #("label", types.StringValue("continued")),
        ]),
      ),
    )
    |> result.map_error(string.inspect),
  )
  use open <- result.try(
    transaction.apply_edit(
      open,
      types.SetField(
        ["byKey", "continued", "label"],
        types.StringValue("continued-final"),
      ),
    )
    |> result.map_error(string.inspect),
  )
  use finished <- result.try(
    transaction.finish(open) |> result.map_error(string.inspect),
  )
  let assert #(transaction.Commit(continued, _, _), _) = finished
  use continued_identifier <- result.try(
    tree_kernel.read(continued, ["byKey", "continued", "id"])
    |> result.map_error(string.inspect)
    |> result.try(fn(value) {
      option.to_result(value, "continued Identifier is absent")
    }),
  )
  use continued_reference <- result.try(
    tree_kernel.reference_at(continued, ["byKey", "tail"])
    |> result.map_error(string.inspect),
  )
  Ok(
    json.object([
      #("id", json.string(id)),
      #("value", visible_json(after)),
      #("before", visible_json(before)),
      #("messages", fixture_codec.array(list.map(messages, json_ot.to_json))),
      #(
        "idRanges",
        fixture_codec.field(apply, "idRanges", fixture_codec.items)
          |> result.unwrap([])
          |> list.map(json_ot.to_json)
          |> fixture_codec.array,
      ),
      #("continuedIdentifier", visible_json(continued_identifier)),
      #(
        "continuationReferenceStable",
        json.bool(reference == continued_reference),
      ),
    ]),
  )
}

fn run_transaction_actions(
  id: String,
  actions: List(JsonValue),
  stored: schema.StoredSchema,
  initial: types.TreeValue,
  sessions: JsonValue,
  compressors: JsonValue,
) -> Result(json.Json, String) {
  use #(base, base_compressor) <- result.try(persistence_base(
    stored,
    initial,
    sessions,
    compressors,
  ))
  let assert [action] = actions
  let assert Ok(open) = transaction.begin(base, base_compressor, [])
  use #(edited, generated) <- result.try(apply_transaction_action(open, action))
  use outcome <- result.try(optional_text(action, "result", "rollback"))
  use #(restored, compressor) <- result.try(case outcome {
    "rollback" -> transaction.abort(edited) |> result.map_error(string.inspect)
    "commit" -> {
      use finished <- result.try(
        transaction.finish(edited) |> result.map_error(string.inspect),
      )
      case finished.0 {
        transaction.NoCommit(state, compressor) -> Ok(#(state, compressor))
        transaction.Commit(state, compressor, _) -> Ok(#(state, compressor))
      }
    }
    _ -> Error(id <> ": unsupported transaction result " <> outcome)
  })
  let visible =
    tree_kernel.visible_data(restored) != tree_kernel.visible_data(base)
  Ok(
    json.object([
      #("id", json.string(id)),
      #("generated", generated |> option.unwrap("") |> json.string),
      #("visible", json.bool(visible)),
      #("compressorAdvanced", json.bool(compressor != base_compressor)),
      #(
        "value",
        visible_root(restored)
          |> result.map(visible_json)
          |> result.unwrap(json.null()),
      ),
    ]),
  )
}

fn apply_transaction_action(
  open: transaction.Transaction,
  action: JsonValue,
) -> Result(#(transaction.Transaction, Option(String)), String) {
  use actions <- result.try(fixture_codec.field(
    action,
    "actions",
    fixture_codec.items,
  ))
  list.try_fold(actions, #(open, None), fn(current, action) {
    use operation <- result.try(fixture_codec.field(
      action,
      "op",
      fixture_codec.text,
    ))
    case operation {
      "transaction" -> {
        let nested = transaction.begin_nested(current.0)
        use #(nested, generated) <- result.try(apply_transaction_action(
          nested,
          action,
        ))
        use outcome <- result.try(optional_text(action, "result", "commit"))
        use open <- result.try(case outcome {
          "commit" ->
            transaction.commit_nested(nested)
            |> result.map_error(string.inspect)
          "rollback" ->
            transaction.abort_nested(nested)
            |> result.map_error(string.inspect)
          _ -> Error("unsupported nested transaction result " <> outcome)
        })
        Ok(#(open, generated |> option.or(current.1)))
      }
      "set" | "clear" | "insert" | "remove" | "move" -> {
        use edit <- result.try(decode_edit(action))
        use open <- result.try(
          transaction.apply_edit(current.0, edit)
          |> result.map_error(string.inspect),
        )
        let generated = case operation {
          "insert" -> inserted_identifier(transaction.state(open), action)
          _ -> Error(Nil)
        }
        Ok(#(open, generated |> option.from_result |> option.or(current.1)))
      }
      _ -> Error("unsupported transaction action " <> operation)
    }
  })
}

fn inserted_identifier(
  state: tree_kernel.TreeState,
  action: JsonValue,
) -> Result(String, Nil) {
  use path <- result.try(
    action_path(action, "path")
    |> result.map_error(fn(_) { Nil }),
  )
  use index <- result.try(
    fixture_codec.field(action, "index", fixture_codec.integer)
    |> result.map_error(fn(_) { Nil }),
  )
  use value <- result.try(
    tree_kernel.read(state, list.append(path, [int.to_string(index), "id"]))
    |> result.map_error(fn(_) { Nil }),
  )
  case value {
    Some(types.StringValue(value)) -> Ok(value)
    _ -> Error(Nil)
  }
}

fn optional_text(
  value: JsonValue,
  name: String,
  fallback: String,
) -> Result(String, String) {
  case fixture_codec.get(value, name) {
    Error(_) -> Ok(fallback)
    Ok(value) -> fixture_codec.text(value)
  }
}

fn run_retry(
  id: String,
  actions: List(JsonValue),
  stored: schema.StoredSchema,
  initial: types.TreeValue,
  sessions: JsonValue,
  compressors: JsonValue,
) -> Result(json.Json, String) {
  use operations <- result.try(
    list.try_map(actions, fn(action) {
      fixture_codec.field(action, "op", fixture_codec.text)
    }),
  )
  use _ <- result.try(require(
    operations == ["disconnect", "insert", "reconnect", "resubmit"]
      || operations == ["disconnect", "insert", "set", "reconnect", "resubmit"],
    "retry actions must disconnect, edit, reconnect, and resubmit in order",
  ))
  use #(base, compressor) <- result.try(persistence_base(
    stored,
    initial,
    sessions,
    compressors,
  ))
  let edit_actions =
    actions
    |> list.filter(fn(action) {
      case fixture_codec.field(action, "op", fixture_codec.text) {
        Ok("insert") | Ok("set") | Ok("clear") | Ok("remove") | Ok("move") ->
          True
        _ -> False
      }
    })
  use open <- result.try(
    transaction.begin(base, compressor, [])
    |> result.map_error(string.inspect),
  )
  use open <- result.try(
    list.try_fold(edit_actions, open, fn(open, action) {
      use edit <- result.try(decode_edit(action))
      transaction.apply_edit(open, edit)
      |> result.map_error(string.inspect)
    }),
  )
  use finished <- result.try(
    transaction.finish(open) |> result.map_error(string.inspect),
  )
  let assert #(transaction.Commit(after, compressor, commit), _) = finished
  use identifier <- result.try(
    tree_kernel.read(after, ["left", "2", "id"])
    |> result.map_error(string.inspect)
    |> result.try(fn(value) { option.to_result(value, "retry id is absent") }),
  )
  use retries <- result.try(
    tree_kernel.resubmit_commits(after) |> result.map_error(string.inspect),
  )
  use retry <- result.try(
    list.first(retries) |> result.map_error(fn(_) { "retry commit is absent" }),
  )
  use resubmitted <- result.try(
    tree_runtime.encode_commit(retry, after, compressor)
    |> result.map_error(string.inspect),
  )
  let #(compressor, range) = fluid_ids.take_unfinalized_range(compressor)
  use range <- result.try(
    range |> option.to_result("retry allocation range is absent"),
  )
  use remote_session <- result.try(input_session(sessions, "remote"))
  let remote = fluid_ids.new(remote_session)
  use initial_compressor <- result.try(input_compressor(
    compressors,
    sessions,
    "initial",
  ))
  use #(_, initial_compressor) <- result.try(
    identifier.materialize_value(stored, initial, initial_compressor)
    |> result.map_error(string.inspect),
  )
  let #(_, initial_range) = fluid_ids.take_creation_range(initial_compressor)
  use initial_range <- result.try(
    initial_range |> option.to_result("initial allocation range is absent"),
  )
  use remote <- result.try(
    fluid_ids.finalize(remote, initial_range)
    |> result.map_error(string.inspect),
  )
  use remote <- result.try(
    fluid_ids.finalize(remote, range)
    |> result.map_error(string.inspect),
  )
  use root <- result.try(visible_root(base))
  use remote_state <- result.try(state_for_session(
    stored,
    full_view(),
    root,
    remote_session,
  ))
  use #(peer_commit, _) <- result.try(
    tree_runtime.decode_sequenced_message(
      json.to_string(resubmitted),
      remote_state,
      0,
      remote,
    )
    |> result.map_error(string.inspect),
  )
  use #(peer, _, _) <- result.try(
    tree_runtime.receive_commit(
      remote_state,
      peer_commit,
      types.SequencePoint(1, 0),
      0,
      0,
      remote,
    )
    |> result.map_error(string.inspect),
  )
  use peer_identifier <- result.try(
    tree_kernel.read(peer, ["left", "2", "id"])
    |> result.map_error(string.inspect)
    |> result.try(fn(value) {
      option.to_result(value, "peer retry id is absent")
    }),
  )
  use peer_root <- result.try(visible_root(peer))
  use #(acknowledged, _, _) <- result.try(
    tree_runtime.receive_commit(
      after,
      commit,
      types.SequencePoint(1, 0),
      0,
      0,
      compressor,
    )
    |> result.map_error(string.inspect),
  )
  use accepted_identifier <- result.try(
    tree_kernel.read(acknowledged, ["left", "2", "id"])
    |> result.map_error(string.inspect)
    |> result.try(fn(value) {
      option.to_result(value, "accepted retry id is absent")
    }),
  )
  use after_ack <- result.try(
    tree_kernel.resubmit_commits(acknowledged)
    |> result.map_error(string.inspect),
  )
  Ok(
    json.object([
      #("id", json.string(id)),
      #("identifier", case identifier {
        types.StringValue(value) -> json.string(value)
        _ -> json.null()
      }),
      #("peerObserved", json.bool(peer_identifier == identifier)),
      #("peerValue", visible_json(peer_root)),
      #("acceptedIdentifier", visible_json(accepted_identifier)),
      #("pendingAfterAck", json.int(list.length(after_ack))),
    ]),
  )
}

fn run_remove(
  id: String,
  action: JsonValue,
  stored: schema.StoredSchema,
  initial: types.TreeValue,
  sessions: JsonValue,
  compressors: JsonValue,
) -> Result(json.Json, String) {
  use #(base, compressor) <- result.try(persistence_base(
    stored,
    initial,
    sessions,
    compressors,
  ))
  use identifier <- result.try(
    tree_kernel.read(base, ["left", "0", "id"])
    |> result.map_error(string.inspect)
    |> result.try(fn(value) { option.to_result(value, "removed id is absent") }),
  )
  use edit <- result.try(decode_edit(action))
  use #(after, commit, _, compressor) <- result.try(
    tree_runtime.author_edit(base, edit, compressor)
    |> result.map_error(string.inspect),
  )
  use commit <- result.try(
    commit |> option.to_result("remove commit is absent"),
  )
  let _ = commit
  use data <- result.try(
    tree_kernel.visible_data(after) |> result.map_error(string.inspect),
  )
  use repair <- result.try(
    list.try_map(data.detached, fn(detached) {
      let forest.DetachedTreeData(id, _, _, value) = detached
      use revision <- result.try(
        id.revision
        |> option.to_result("retained tree has no revision")
        |> result.try(fn(revision) {
          fluid_ids.recompress(compressor, revision)
          |> result.map_error(string.inspect)
        })
        |> result.try(fn(value) {
          option.to_result(value, "retained revision is unknown")
        }),
      )
      use operation <- result.try(
        fluid_ids.to_op(compressor, revision)
        |> result.map_error(string.inspect),
      )
      Ok(
        json.array(
          [
            json.int(fluid_ids.op_id_to_int(operation)),
            json.int(id.local_id),
            internal_tree_json(value),
          ],
          fn(value) { value },
        ),
      )
    }),
  )
  Ok(
    json.object([
      #("id", json.string(id)),
      #("identifier", case identifier {
        types.StringValue(value) -> json.string(value)
        _ -> json.null()
      }),
      #("repair", fixture_codec.array(repair)),
      #("retainedForest", forest_data_json(data)),
    ]),
  )
}

fn run_move(
  id: String,
  action: JsonValue,
  stored: schema.StoredSchema,
  initial: types.TreeValue,
  sessions: JsonValue,
  compressors: JsonValue,
) -> Result(json.Json, String) {
  use #(base, compressor) <- result.try(persistence_base(
    stored,
    initial,
    sessions,
    compressors,
  ))
  use reference <- result.try(
    tree_kernel.reference_at(base, ["left", "0"])
    |> result.map_error(string.inspect),
  )
  use identifier <- result.try(
    tree_kernel.read(base, ["left", "0", "id"])
    |> result.map_error(string.inspect)
    |> result.try(fn(value) { option.to_result(value, "moved id is absent") }),
  )
  use edit <- result.try(decode_edit(action))
  use #(after, _, _, _) <- result.try(
    tree_runtime.author_edit(base, edit, compressor)
    |> result.map_error(string.inspect),
  )
  use moved <- result.try(
    tree_kernel.reference_at(after, ["right", "0"])
    |> result.map_error(string.inspect),
  )
  Ok(
    json.object([
      #("id", json.string(id)),
      #("identifier", case identifier {
        types.StringValue(value) -> json.string(value)
        _ -> json.null()
      }),
      #("identityPreserved", json.bool(reference == moved)),
    ]),
  )
}

fn run_replacements(
  id: String,
  actions: List(JsonValue),
  base: tree_kernel.TreeState,
  compressor: fluid_ids.Compressor,
) -> Result(json.Json, String) {
  use before_reference <- result.try(
    tree_kernel.reference_at(base, ["child"])
    |> result.map_error(string.inspect),
  )
  use #(after, compressor) <- result.try(
    list.try_fold(actions, #(base, compressor), fn(current, action) {
      use edit <- result.try(decode_edit(action))
      use #(state, commit, _, compressor) <- result.try(
        tree_runtime.author_edit(current.0, edit, current.1)
        |> result.map_error(string.inspect),
      )
      use _ <- result.try(
        commit |> option.to_result("replacement produced no commit"),
      )
      Ok(#(state, compressor))
    }),
  )
  let _ = compressor
  use after_reference <- result.try(
    tree_kernel.reference_at(after, ["child"])
    |> result.map_error(string.inspect),
  )
  use identifier <- result.try(
    tree_kernel.read(after, ["child", "id"])
    |> result.map_error(string.inspect)
    |> result.try(fn(value) {
      option.to_result(value, "replacement id is absent")
    }),
  )
  use stable <- result.try(
    tree_kernel.reference_at(after, ["left", "0"])
    |> result.map_error(string.inspect),
  )
  use stable_again <- result.try(
    tree_kernel.reference_at(after, ["left", "0"])
    |> result.map_error(string.inspect),
  )
  use root <- result.try(visible_root(after))
  Ok(
    json.object([
      #("id", json.string(id)),
      #("identifier", case identifier {
        types.StringValue(value) -> json.string(value)
        _ -> json.null()
      }),
      #("nodeReplaced", json.bool(before_reference != after_reference)),
      #("sameNodeTokenStable", json.bool(stable == stable_again)),
      #("value", visible_json(root)),
    ]),
  )
}

fn decode_captured_tree(value: JsonValue) -> Result(types.TreeValue, String) {
  case value {
    VString(value) -> Ok(types.StringValue(value))
    VBool(value) -> Ok(types.BooleanValue(value))
    VNumber(json_ot.NInt(value)) -> Ok(types.NumberValue(int.to_float(value)))
    VNumber(json_ot.NFloat(value)) -> Ok(types.NumberValue(value))
    VNull -> Ok(types.NullValue)
    VObject(_) -> {
      use type_id <- result.try(fixture_codec.field(
        value,
        "schema",
        fixture_codec.text,
      ))
      use raw_fields <- result.try(fixture_codec.get(value, "fields"))
      use members <- result.try(object_members(raw_fields, "captured fields"))
      use decoded <- result.try(
        list.try_map(members, fn(entry) {
          use child <- result.try(decode_captured_field(entry.0, entry.1))
          Ok(#(entry.0, child))
        }),
      )
      let decoded = case type_id == root_type {
        True -> order_root_fields(decoded)
        False -> decoded
      }
      Ok(types.ObjectValue(type_id, decoded))
    }
    VArray(_) -> Error("captured tree root must name its schema")
  }
}

fn decode_captured_field(
  key: String,
  value: JsonValue,
) -> Result(types.TreeValue, String) {
  case value {
    VArray(values) if key == "byKey" -> {
      use entries <- result.try(
        list.try_map(values, fn(value) {
          use #(key, value) <- result.try(fixture_codec.pair(value))
          use key <- result.try(fixture_codec.text(key))
          use value <- result.try(decode_captured_tree(value))
          Ok(#(key, value))
        }),
      )
      Ok(types.MapValue(map_type, entries))
    }
    VArray(values) -> {
      use values <- result.try(list.try_map(values, decode_captured_tree))
      Ok(types.ArrayValue(items_type, values))
    }
    _ -> decode_captured_tree(value)
  }
}

fn order_root_fields(
  fields: List(#(String, types.TreeValue)),
) -> List(#(String, types.TreeValue)) {
  ["child", "left", "right", "byKey"]
  |> list.filter_map(fn(key) {
    list.key_find(fields, key)
    |> result.map(fn(value) { #(key, value) })
  })
}

fn decode_edit(action: JsonValue) -> Result(types.Edit, String) {
  use operation <- result.try(fixture_codec.field(
    action,
    "op",
    fixture_codec.text,
  ))
  case operation {
    "set" -> {
      use path <- result.try(action_path(action, "path"))
      use value <- result.try(fixture_codec.get(action, "value"))
      use value <- result.try(decode_captured_tree(value))
      Ok(types.SetField(path, value))
    }
    "clear" -> {
      use path <- result.try(action_path(action, "path"))
      Ok(types.ClearField(path))
    }
    "insert" -> {
      use path <- result.try(action_path(action, "path"))
      use index <- result.try(fixture_codec.field(
        action,
        "index",
        fixture_codec.integer,
      ))
      use value <- result.try(fixture_codec.get(action, "value"))
      use value <- result.try(decode_captured_tree(value))
      Ok(types.ArrayInsert(path, index, [value]))
    }
    "remove" -> {
      use path <- result.try(action_path(action, "path"))
      use index <- result.try(fixture_codec.field(
        action,
        "index",
        fixture_codec.integer,
      ))
      use count <- result.try(fixture_codec.field(
        action,
        "count",
        fixture_codec.integer,
      ))
      Ok(types.ArrayRemove(path, index, count))
    }
    "move" -> {
      use from <- result.try(action_path(action, "from"))
      use to <- result.try(action_path(action, "to"))
      use count <- result.try(fixture_codec.field(
        action,
        "count",
        fixture_codec.integer,
      ))
      use #(source, source_index) <- result.try(array_endpoint(from, 0))
      use #(destination, destination_index) <- result.try(array_endpoint(to, 0))
      Ok(types.ArrayMove(
        source,
        source_index,
        count,
        destination,
        destination_index,
      ))
    }
    _ -> Error("unsupported edit action " <> operation)
  }
}

fn action_path(value: JsonValue, name: String) -> Result(List(String), String) {
  use parts <- result.try(fixture_codec.field(value, name, fixture_codec.items))
  list.try_map(parts, fn(part) {
    case part {
      VString(value) -> Ok(value)
      VNumber(json_ot.NInt(value)) -> Ok(int.to_string(value))
      _ -> Error(name <> " contains an invalid path segment")
    }
  })
}

fn array_endpoint(
  path: List(String),
  end_index: Int,
) -> Result(#(List(String), Int), String) {
  case list.reverse(path) {
    ["end", ..rest] -> Ok(#(list.reverse(rest), end_index))
    [index, ..rest] -> {
      use index <- result.try(
        int.parse(index)
        |> result.map_error(fn(_) { "array endpoint has no integer index" }),
      )
      Ok(#(list.reverse(rest), index))
    }
    [] -> Error("array endpoint is empty")
  }
}

fn visible_json(value: types.TreeValue) -> json.Json {
  case value {
    types.StringValue(value) -> json.string(value)
    types.NumberValue(value) -> json.float(value)
    types.BooleanValue(value) -> json.bool(value)
    types.NullValue -> json.null()
    types.ObjectValue(_, fields) ->
      json.object(
        list.map(fields, fn(entry) { #(entry.0, visible_json(entry.1)) }),
      )
    types.MapValue(_, entries) ->
      json.array(
        list.map(entries, fn(entry) {
          json.array([json.string(entry.0), visible_json(entry.1)], fn(value) {
            value
          })
        }),
        fn(value) { value },
      )
    types.ArrayValue(_, values) -> json.array(values, visible_json)
  }
}

fn internal_tree_json(value: types.TreeValue) -> json.Json {
  case value {
    types.StringValue(value) ->
      json.object([
        #("type", json.string("com.fluidframework.leaf.string")),
        #("value", json.string(value)),
      ])
    types.ObjectValue(type_id, fields) ->
      json.object([
        #("type", json.string(type_id)),
        #(
          "fields",
          json.object(
            list.map(fields, fn(entry) {
              #(
                entry.0,
                json.array([internal_tree_json(entry.1)], fn(value) { value }),
              )
            }),
          ),
        ),
      ])
    _ -> visible_json(value)
  }
}

fn forest_data_json(value: forest.ForestData) -> json.Json {
  json.object([
    #(
      "root",
      value.root
        |> option.map(visible_json)
        |> option.unwrap(json.null()),
    ),
    #(
      "detached",
      value.detached
        |> list.map(fn(detached) {
          let forest.DetachedTreeData(id, root, revision, value) = detached
          json.object([
            #("id", atom_json(id)),
            #("root", json.int(root)),
            #(
              "latestRelevantRevision",
              revision
                |> option.map(fluid_ids.stable_id_to_string)
                |> option.map(json.string)
                |> option.unwrap(json.null()),
            ),
            #("value", internal_tree_json(value)),
          ])
        })
        |> fixture_codec.array,
    ),
    #("nextDetachedRootId", json.int(value.next_detached_root_id)),
  ])
}

fn atom_json(value: types.AtomId) -> json.Json {
  json.object([
    #(
      "revision",
      value.revision
        |> option.map(fluid_ids.stable_id_to_string)
        |> option.map(json.string)
        |> option.unwrap(json.null()),
    ),
    #("localId", json.int(value.local_id)),
  ])
}

fn field_string(
  fields: List(#(String, types.TreeValue)),
  key: String,
) -> json.Json {
  case list.key_find(fields, key) {
    Ok(types.StringValue(value)) -> json.string(value)
    _ -> json.null()
  }
}

fn field_schema_json(value: schema.FieldSchema) -> json.Json {
  let schema.FieldSchema(kind, types) = value
  json.object([
    #(
      "kind",
      json.string(case kind {
        schema.Identifier -> "Identifier"
        schema.Required -> "Value"
        schema.Optional -> "Optional"
        schema.Sequence -> "Sequence"
      }),
    ),
    #("types", json.array(types, json.string)),
  ])
}

fn input_session(
  value: JsonValue,
  name: String,
) -> Result(fluid_ids.SessionId, String) {
  use raw <- result.try(fixture_codec.field(value, name, fixture_codec.text))
  fluid_ids.session_id(raw) |> result.map_error(string.inspect)
}

fn input_compressor(
  compressors: JsonValue,
  sessions: JsonValue,
  name: String,
) -> Result(fluid_ids.Compressor, String) {
  use raw <- result.try(fixture_codec.field(
    compressors,
    name,
    fixture_codec.text,
  ))
  let session_name = case name {
    "remote" -> "remote"
    "summary" -> "summary"
    _ -> "local"
  }
  use session <- result.try(input_session(sessions, session_name))
  fluid_ids.deserialize(json.string(raw), session)
  |> result.map_error(string.inspect)
}

fn load_compressors(
  compressors: JsonValue,
  sessions: JsonValue,
) -> Result(List(#(String, fluid_ids.Compressor)), String) {
  use entries <- result.try(object_members(compressors, "compressors"))
  list.try_map(entries, fn(entry) {
    use value <- result.try(input_compressor(compressors, sessions, entry.0))
    Ok(#(entry.0, value))
  })
}

fn named_compressor(
  values: List(#(String, fluid_ids.Compressor)),
  name: String,
) -> Result(fluid_ids.Compressor, String) {
  list.key_find(values, name)
  |> result.map_error(fn(_) { "missing compressor " <> name })
}

fn id_context(
  action: JsonValue,
  purpose: String,
  compressor: fluid_ids.Compressor,
) -> Result(field_batch.IdContext, String) {
  case purpose {
    "summary" -> Ok(field_batch.SummaryIds(compressor))
    "message" -> {
      use raw <- result.try(fixture_codec.field(
        action,
        "originator",
        fixture_codec.text,
      ))
      use originator <- result.try(
        fluid_ids.session_id(raw) |> result.map_error(string.inspect),
      )
      Ok(field_batch.MessageIds(compressor, originator))
    }
    _ -> Error("unsupported Identifier purpose " <> purpose)
  }
}

fn encode_id_context(
  action: JsonValue,
  purpose: String,
  compressor: fluid_ids.Compressor,
  value: String,
) -> Result(field_batch.IdContext, String) {
  case purpose {
    "summary" -> Ok(field_batch.SummaryIds(compressor))
    "message" ->
      case fixture_codec.get(action, "originator") {
        Ok(value) -> {
          use raw <- result.try(fixture_codec.text(value))
          use originator <- result.try(
            fluid_ids.session_id(raw) |> result.map_error(string.inspect),
          )
          Ok(field_batch.MessageIds(compressor, originator))
        }
        Error(_) ->
          case fluid_ids.stable_id(value) {
            Error(_) ->
              Ok(field_batch.MessageIds(
                compressor,
                fluid_ids.local_session(compressor),
              ))
            Ok(stable) ->
              case fluid_ids.recompress(compressor, stable) {
                Ok(None) | Error(fluid_ids.UnknownId(_)) ->
                  Ok(field_batch.MessageIds(
                    compressor,
                    fluid_ids.local_session(compressor),
                  ))
                _ -> Error("missing field originator")
              }
          }
      }
    _ -> Error("unsupported Identifier purpose " <> purpose)
  }
}

fn identifier_codec_schema() -> schema.StoredSchema {
  let assert Ok(value) =
    schema.stored_from_json(
      json.object([
        #("version", json.int(2)),
        #(
          "nodes",
          json.object([
            #(
              "com.fluidframework.leaf.string",
              json.object([#("kind", json.object([#("leaf", json.int(1))]))]),
            ),
            #(
              "IdentifierCodecNode",
              json.object([
                #(
                  "kind",
                  json.object([
                    #(
                      "object",
                      json.object([
                        #(
                          "id",
                          field("Identifier", "com.fluidframework.leaf.string"),
                        ),
                      ]),
                    ),
                  ]),
                ),
              ]),
            ),
          ]),
        ),
        #("root", field("Value", "IdentifierCodecNode")),
      ]),
    )
  value
}

fn encoded_identifier_value(value: json.Json) -> Result(json.Json, String) {
  use value <- result.try(
    json_ot.parse_json(json.to_string(value))
    |> result.map_error(string.inspect),
  )
  find_encoded_identifier(value)
  |> result.map(json_ot.to_json)
  |> result.map_error(fn(_) {
    "encoded Identifier FieldBatch has an unexpected shape"
  })
}

fn find_encoded_identifier(value: JsonValue) -> Result(JsonValue, Nil) {
  case value {
    VArray([VNumber(NInt(4)), value, ..]) -> Ok(value)
    VArray(values) -> find_encoded_identifier_values(values)
    VObject(fields) -> find_encoded_identifier_entries(fields)
    _ -> Error(Nil)
  }
}

fn find_encoded_identifier_entries(
  values: List(#(String, JsonValue)),
) -> Result(JsonValue, Nil) {
  case values {
    [] -> Error(Nil)
    [value, ..rest] ->
      case find_encoded_identifier(value.1) {
        Ok(value) -> Ok(value)
        Error(_) -> find_encoded_identifier_entries(rest)
      }
  }
}

fn find_encoded_identifier_values(
  values: List(JsonValue),
) -> Result(JsonValue, Nil) {
  case values {
    [] -> Error(Nil)
    [value, ..rest] ->
      case find_encoded_identifier(value) {
        Ok(value) -> Ok(value)
        Error(_) -> find_encoded_identifier_values(rest)
      }
  }
}

fn identifier_change_value(value: json.Json) -> Result(json.Json, String) {
  use value <- result.try(
    json_ot.parse_json(json.to_string(value))
    |> result.map_error(string.inspect),
  )
  find_identifier_change(value)
  |> result.map(json_ot.to_json)
  |> result.map_error(fn(_) { "encoded Identifier field change is absent" })
}

fn find_identifier_change(value: JsonValue) -> Result(JsonValue, Nil) {
  case value {
    VObject(fields) ->
      case list.key_find(fields, "fieldKind"), list.key_find(fields, "change") {
        Ok(VString("Identifier")), Ok(encoded) -> Ok(encoded)
        _, _ -> find_identifier_change_entries(fields)
      }
    VArray(values) -> find_identifier_change_values(values)
    _ -> Error(Nil)
  }
}

fn find_identifier_change_entries(
  values: List(#(String, JsonValue)),
) -> Result(JsonValue, Nil) {
  case values {
    [] -> Error(Nil)
    [value, ..rest] ->
      case find_identifier_change(value.1) {
        Ok(value) -> Ok(value)
        Error(_) -> find_identifier_change_entries(rest)
      }
  }
}

fn find_identifier_change_values(
  values: List(JsonValue),
) -> Result(JsonValue, Nil) {
  case values {
    [] -> Error(Nil)
    [value, ..rest] ->
      case find_identifier_change(value) {
        Ok(value) -> Ok(value)
        Error(_) -> find_identifier_change_values(rest)
      }
  }
}

fn identifier_batch(value: json.Json) -> json.Json {
  json.object([
    #("version", json.int(2)),
    #(
      "identifiers",
      json.array([json.string("com.fluidframework.leaf.string")], fn(value) {
        value
      }),
    ),
    #(
      "shapes",
      json.array(
        [
          json.object([
            #(
              "c",
              json.object([
                #("type", json.int(0)),
                #("value", json.int(0)),
              ]),
            ),
          ]),
        ],
        fn(value) { value },
      ),
    ),
    #(
      "data",
      json.array(
        [json.array([json.int(0), value], fn(value) { value })],
        fn(value) { value },
      ),
    ),
  ])
}

fn last_decoded_input(actions: List(JsonValue)) -> Result(JsonValue, String) {
  use action <- result.try(
    list.find(actions, fn(action) {
      fixture_codec.field(action, "op", fixture_codec.text)
      == Ok("decode-field-batch")
    })
    |> result.map_error(fn(_) { "decode action is absent" }),
  )
  use encoded <- result.try(fixture_codec.get(action, "encoded"))
  fixture_codec.get(encoded, "value")
}

fn has_finalized_allocation(actions: List(JsonValue)) -> Bool {
  list.any(actions, fn(action) {
    fixture_codec.field(action, "op", fixture_codec.text) == Ok("allocate-id")
    && fixture_codec.field(action, "compressor", fixture_codec.text)
    == Ok("summary")
  })
}

fn generate_stable(
  compressor: fluid_ids.Compressor,
) -> Result(#(fluid_ids.Compressor, fluid_ids.StableId), fluid_ids.IdError) {
  use #(compressor, local) <- result.try(fluid_ids.generate(compressor))
  use stable <- result.try(fluid_ids.decompress(compressor, local))
  Ok(#(compressor, stable))
}

fn allocation_events(
  value: types.TreeValue,
  revision: fluid_ids.StableId,
  compressor: fluid_ids.Compressor,
) -> json.Json {
  allocation_events_offset(value, revision, compressor, 0)
}

fn identifier_allocation_events(
  value: types.TreeValue,
  compressor: fluid_ids.Compressor,
) -> json.Json {
  let identifiers =
    identifier_paths(value, [])
    |> list.filter_map(fn(entry) {
      case fluid_ids.stable_id(entry.1) {
        Error(_) -> Error(Nil)
        Ok(stable) ->
          case fluid_ids.recompress(compressor, stable) {
            Ok(Some(compressed)) ->
              case fluid_ids.to_op(compressor, compressed) {
                Ok(operation) ->
                  Ok(#(fluid_ids.op_id_to_int(operation), entry.0))
                Error(_) -> Error(Nil)
              }
            _ -> Error(Nil)
          }
      }
    })
    |> list.sort(fn(a, b) { int.compare(a.0, b.0) })
  identifiers
  |> list.index_map(fn(entry, index) {
    json.object([
      #("ordinal", json.int(index + 1)),
      #("kind", json.string("identifier")),
      #("path", json.array(entry.1, fn(value) { value })),
      #("op", json.int(entry.0)),
    ])
  })
  |> fixture_codec.array
}

fn allocation_events_offset(
  value: types.TreeValue,
  revision: fluid_ids.StableId,
  compressor: fluid_ids.Compressor,
  offset: Int,
) -> json.Json {
  let identifiers =
    identifier_paths(value, [])
    |> list.filter_map(fn(entry) {
      case fluid_ids.stable_id(entry.1) {
        Error(_) -> Error(Nil)
        Ok(stable) ->
          case fluid_ids.recompress(compressor, stable) {
            Ok(Some(value)) ->
              Ok(#(
                absolute(fluid_ids.session_space_id_to_int(value)) + offset,
                entry.0,
              ))
            _ -> Error(Nil)
          }
      }
    })
  let revision_op = case fluid_ids.recompress(compressor, revision) {
    Ok(Some(value)) ->
      absolute(fluid_ids.session_space_id_to_int(value)) + offset
    _ ->
      case offset < 0 {
        True -> list.length(identifiers)
        False -> 0
      }
  }
  allocation_event_json(identifiers, revision_op)
}

fn edit_allocation_events(
  state: tree_kernel.TreeState,
  _edit: types.Edit,
  revision: fluid_ids.StableId,
  compressor: fluid_ids.Compressor,
) -> json.Json {
  let value = case tree_kernel.visible_data(state) {
    Ok(data) -> data.root |> option.unwrap(types.NullValue)
    Error(_) -> types.NullValue
  }
  let identifiers =
    identifier_paths(value, [])
    |> list.filter_map(fn(entry) {
      case fluid_ids.stable_id(entry.1) {
        Error(_) -> Error(Nil)
        Ok(stable) ->
          case fluid_ids.recompress(compressor, stable) {
            Ok(Some(value)) ->
              Ok(#(absolute(fluid_ids.session_space_id_to_int(value)), entry.0))
            _ -> Error(Nil)
          }
      }
    })
  let revision_op = case fluid_ids.recompress(compressor, revision) {
    Ok(Some(value)) -> absolute(fluid_ids.session_space_id_to_int(value))
    _ -> 0
  }
  allocation_event_json(identifiers, revision_op)
}

fn allocation_event_json(
  identifiers: List(#(Int, List(json.Json))),
  revision: Int,
) -> json.Json {
  let identifiers =
    identifiers
    |> list.filter(fn(entry) { entry.0 >= 0 })
    |> list.sort(fn(a, b) { int.compare(a.0, b.0) })
  let events =
    identifiers
    |> list.index_map(fn(entry, index) {
      let #(operation, path) = entry
      json.object([
        #("ordinal", json.int(index + 1)),
        #("kind", json.string("identifier")),
        #("path", json.array(path, fn(value) { value })),
        #("op", json.int(operation)),
      ])
    })
  json.array(
    list.append(events, [
      json.object([
        #("ordinal", json.int(list.length(events) + 1)),
        #("kind", json.string("revision")),
        #("path", json.array([], fn(value) { value })),
        #("op", json.int(revision)),
      ]),
    ]),
    fn(value) { value },
  )
}

fn identifier_paths(
  value: types.TreeValue,
  path: List(json.Json),
) -> List(#(List(json.Json), String)) {
  case value {
    types.ObjectValue(_, fields) ->
      list.flat_map(fields, fn(entry) {
        case entry.0, entry.1 {
          "id", types.StringValue(value)
          | "firstId", types.StringValue(value)
          | "secondId", types.StringValue(value)
          -> [#(list.append(path, [json.string(entry.0)]), value)]
          _, child ->
            identifier_paths(child, list.append(path, [json.string(entry.0)]))
        }
      })
    types.MapValue(_, entries) ->
      list.flat_map(entries, fn(entry) {
        identifier_paths(entry.1, list.append(path, [json.string(entry.0)]))
      })
    types.ArrayValue(_, values) ->
      values
      |> list.index_map(fn(value, index) {
        identifier_paths(value, list.append(path, [json.int(index)]))
      })
      |> list.flatten
    _ -> []
  }
}

fn summary_entry(
  value: JsonValue,
) -> Result(fluid_summary.SummaryEntry, String) {
  use kind <- result.try(fixture_codec.field(
    value,
    "type",
    fixture_codec.integer,
  ))
  case kind {
    1 -> {
      use tree <- result.try(fixture_codec.get(value, "tree"))
      use fields <- result.try(object_members(tree, "summary tree"))
      use fields <- result.try(
        list.try_map(fields, fn(entry) {
          use child <- result.try(summary_entry(entry.1))
          Ok(#(entry.0, child))
        }),
      )
      Ok(fluid_summary.SummaryTree(fields))
    }
    2 -> {
      use content <- result.try(fixture_codec.field(
        value,
        "content",
        fixture_codec.text,
      ))
      Ok(fluid_summary.SummaryBlob(<<content:utf8>>))
    }
    _ -> Error("unsupported summary entry")
  }
}

fn summary_json(value: fluid_summary.SummaryEntry) -> json.Json {
  case value {
    fluid_summary.SummaryTree(entries) ->
      json.object([
        #("type", json.int(1)),
        #(
          "tree",
          json.object(
            list.map(entries, fn(entry) { #(entry.0, summary_json(entry.1)) }),
          ),
        ),
      ])
    fluid_summary.SummaryBlob(bytes) ->
      json.object([
        #("type", json.int(2)),
        #("content", case bit_array.to_string(bytes) {
          Ok(value) -> json.string(value)
          Error(_) -> json.string("")
        }),
      ])
    fluid_summary.SummaryHandle(path, _) ->
      json.object([
        #("type", json.int(3)),
        #("handle", json.string(path)),
      ])
  }
}

fn finalize_action_ranges(
  compressor: fluid_ids.Compressor,
  action: JsonValue,
) -> Result(fluid_ids.Compressor, String) {
  use ranges <- result.try(fixture_codec.field(
    action,
    "idRanges",
    fixture_codec.items,
  ))
  list.try_fold(ranges, compressor, fn(compressor, range) {
    use range <- result.try(
      fluid_ids.creation_range_from_json(json_ot.to_json(range))
      |> result.map_error(string.inspect),
    )
    fluid_ids.finalize(compressor, range)
    |> result.map_error(string.inspect)
  })
}

fn finalize_local_ids(
  compressor: fluid_ids.Compressor,
) -> Result(fluid_ids.Compressor, String) {
  let #(compressor, range) = fluid_ids.take_creation_range(compressor)
  case range {
    None -> Ok(compressor)
    Some(range) ->
      fluid_ids.finalize(compressor, range)
      |> result.map_error(string.inspect)
  }
}

fn apply_tail_message(
  state: tree_kernel.TreeState,
  compressor: fluid_ids.Compressor,
  value: JsonValue,
) -> Result(#(tree_kernel.TreeState, fluid_ids.Compressor), String) {
  use contents <- result.try(fixture_codec.get(value, "contents"))
  use reference <- result.try(fixture_codec.field(
    value,
    "referenceSequenceNumber",
    fixture_codec.integer,
  ))
  use sequence <- result.try(fixture_codec.field(
    value,
    "sequenceNumber",
    fixture_codec.integer,
  ))
  use minimum <- result.try(fixture_codec.field(
    value,
    "minimumSequenceNumber",
    fixture_codec.integer,
  ))
  use #(commit, _) <- result.try(
    tree_runtime.decode_sequenced_message(
      json.to_string(json_ot.to_json(contents)),
      state,
      reference,
      compressor,
    )
    |> result.map_error(string.inspect),
  )
  use #(state, _, compressor) <- result.try(
    tree_runtime.receive_commit(
      state,
      commit,
      types.SequencePoint(sequence, 0),
      reference,
      minimum,
      compressor,
    )
    |> result.map_error(string.inspect),
  )
  Ok(#(state, compressor))
}

fn visible_root(
  state: tree_kernel.TreeState,
) -> Result(types.TreeValue, String) {
  use data <- result.try(
    tree_kernel.visible_data(state) |> result.map_error(string.inspect),
  )
  data.root |> option.to_result("Identifier tree has no root")
}

fn persistence_base(
  stored: schema.StoredSchema,
  initial: types.TreeValue,
  sessions: JsonValue,
  compressors: JsonValue,
) -> Result(#(tree_kernel.TreeState, fluid_ids.Compressor), String) {
  use compressor <- result.try(input_compressor(
    compressors,
    sessions,
    "initial",
  ))
  use #(root, compressor) <- result.try(
    identifier.materialize_value(stored, initial, compressor)
    |> result.map_error(string.inspect),
  )
  use compressor <- result.try(finalize_local_ids(compressor))
  Ok(#(state(stored, full_view(), root), compressor))
}

fn object_members(
  value: JsonValue,
  name: String,
) -> Result(List(#(String, JsonValue)), String) {
  case value {
    VObject(fields) -> Ok(fields)
    _ -> Error(name <> " is not an object")
  }
}

fn absolute(value: Int) -> Int {
  case value < 0 {
    True -> 0 - value
    False -> value
  }
}

fn require(value: Bool, detail: String) -> Result(Nil, String) {
  case value {
    True -> Ok(Nil)
    False -> Error(detail)
  }
}
