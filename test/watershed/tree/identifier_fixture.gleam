import gleam/bit_array
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import spillway/types as spillway_types
import watershed/canonical_json
import watershed/channel
import watershed/fluid_ids
import watershed/json_ot.{
  type JsonValue, NInt, VArray, VBool, VNull, VNumber, VObject, VString,
}
import watershed/runtime_core
import watershed/tree/change
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
import watershed/tree/shared_change
import watershed/tree/summary as tree_summary
import watershed/tree/transaction
import watershed/tree/types
import watershed/tree_kernel
import watershed/wire
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
  use #(compressor, expected_revision) <- result.try(
    case has_initialization_commit {
      True ->
        generate_stable(compressor)
        |> result.map(fn(value) { #(value.0, Some(value.1)) })
        |> result.map_error(string.inspect)
      False -> Ok(#(compressor, None))
    },
  )
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
    True, [summary_codec.SummaryCommit(commit, _, _)], [] -> {
      let codec.WireCommit(revision, originator, _, _) = commit
      use expected <- result.try(
        expected_revision
        |> option.to_result("initialization revision is absent"),
      )
      use _ <- result.try(require(
        revision == expected,
        "initialization revision does not match compressor allocation",
      ))
      require(
        originator == fluid_ids.local_session(compressor),
        "initialization originator does not match compressor session",
      )
    }
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
  use restored_data <- result.try(
    tree_kernel.visible_data(restored) |> result.map_error(string.inspect),
  )
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
  use _ <- result.try(case trunk {
    [summary_codec.SummaryCommit(commit, _, _)] -> {
      use #(replayed_schema, replayed_data) <- result.try(replay_initialization(
        commit,
      ))
      use _ <- result.try(require(
        replayed_schema == summary_stored,
        "initialization replay does not produce the summary schema",
      ))
      require(
        replayed_data == restored_data,
        "initialization replay does not produce the summary forest",
      )
    }
    [] -> Ok(Nil)
    _ -> Error("initialization history is not canonical")
  })
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

fn replay_initialization(
  commit: codec.WireCommit,
) -> Result(#(schema.StoredSchema, forest.ForestData), String) {
  let codec.WireCommit(revision, _, changes, _) = commit
  use #(schema_state, replayed) <- result.try(
    list.try_fold(changes, #(schema.EmptySchema, None), fn(state, item) {
      case item {
        shared_change.SchemaChange(before, after, _) -> {
          use _ <- result.try(require(
            before == state.0,
            "initialization schema changes are not contiguous",
          ))
          use replayed <- result.try(case after, state.1 {
            schema.FixedSchema(stored), None ->
              forest.new(view_id(), stored, None)
              |> result.map(Some)
              |> result.map_error(string.inspect)
            schema.FixedSchema(stored), Some(replayed) ->
              forest.replace_schema(replayed, stored)
              |> result.map(Some)
              |> result.map_error(string.inspect)
            schema.EmptySchema, _ ->
              Error("initialization returns to an empty schema")
          })
          Ok(#(after, replayed))
        }
        shared_change.DataChange(data) -> {
          use replayed <- result.try(
            state.1
            |> option.to_result("initialization data has no schema"),
          )
          use delta <- result.try(
            change.into_delta(change.TaggedChange(Some(revision), None, data))
            |> result.map_error(string.inspect),
          )
          use replayed <- result.try(
            forest.apply_delta(replayed, delta)
            |> result.map_error(string.inspect),
          )
          Ok(#(state.0, Some(replayed)))
        }
      }
    }),
  )
  use stored <- result.try(case schema_state {
    schema.FixedSchema(stored) -> Ok(stored)
    schema.EmptySchema -> Error("initialization does not set a schema")
  })
  use replayed <- result.try(
    replayed |> option.to_result("initialization does not create a forest"),
  )
  use data <- result.try(
    forest.export_data(replayed) |> result.map_error(string.inspect),
  )
  Ok(#(stored, data))
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
  case has_retry_controls(actions) {
    True -> run_retry(id, actions, stored, initial, sessions, compressors)
    False ->
      case operation {
        "validate-schema" -> run_schema_validation(id, first)
        "compare-schema" -> run_schema_comparison(id, first)
        "decode-field-change" -> run_identifier_field_change(id, first)
        "construct" ->
          run_constructs(id, actions, stored, sessions, compressors)
        "set" | "clear" | "insert" ->
          run_value_actions(id, actions, stored, initial, sessions, compressors)
        "allocate-id"
        | "deliver-range"
        | "encode-field-batch"
        | "decode-field-batch" ->
          run_field_batch(id, actions, sessions, compressors, ranges)
        "summarize" ->
          run_initial_summary(
            id,
            actions,
            stored,
            initial,
            sessions,
            compressors,
          )
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
        "remove" ->
          run_remove(id, actions, stored, initial, sessions, compressors)
        "move" -> run_move(id, actions, stored, initial, sessions, compressors)
        _ -> Error(id <> ": unsupported Identifier action " <> operation)
      }
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
      let #(_, allocation) = fluid_ids.take_creation_range(compressor)
      use allocation_events <- result.try(allocation_events_from_range(
        value,
        Some(revision),
        compressor,
        allocation,
      ))
      Ok(
        json.object([
          #("id", json.string(id)),
          #("value", visible_json(value)),
          #("allocationEvents", allocation_events),
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
        "insert" -> {
          use events <- result.try(edit_allocation_events(
            after,
            commit.revision,
            after_compressor,
          ))
          Ok(
            json.object([
              #("id", json.string(id)),
              #("events", events),
            ]),
          )
        }
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
  actions: List(JsonValue),
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
  let #(compressor, allocation) = fluid_ids.take_creation_range(compressor)
  use compressor <- result.try(case allocation {
    Some(range) ->
      fluid_ids.finalize(compressor, range) |> result.map_error(string.inspect)
    None -> Ok(compressor)
  })
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
  use #(after, _, _) <- result.try(apply_ordered_actions(
    state(stored, full_view(), root),
    compressor,
    list.drop(actions, 1),
  ))
  use after_root <- result.try(visible_root(after))
  use allocation_events <- result.try(allocation_events_from_range(
    root,
    None,
    compressor,
    allocation,
  ))
  Ok(
    json.object([
      #("id", json.string(id)),
      #("value", visible_json(after_root)),
      #("summary", summary_json(encoded)),
      #("allocationEvents", allocation_events),
    ]),
  )
}

fn run_summary_tail(
  id: String,
  actions: List(JsonValue),
) -> Result(json.Json, String) {
  use #(load, apply, trailing) <- result.try(case actions {
    [load, apply, ..trailing] -> Ok(#(load, apply, trailing))
    _ -> Error(id <> ": summary tail needs load and apply actions")
  })
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
  use #(continued, continued_compressor) <- result.try(case finished.0 {
    transaction.Commit(state, compressor, _) -> Ok(#(state, compressor))
    transaction.NoCommit(_, _) ->
      Error("summary continuation produced no commit")
  })
  use #(continued, _, _) <- result.try(apply_ordered_actions(
    continued,
    continued_compressor,
    trailing,
  ))
  use final_root <- result.try(visible_root(continued))
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
      #("value", case trailing {
        [] -> visible_json(after)
        _ -> visible_json(final_root)
      }),
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
  use #(restored, compressor, generated) <- result.try(apply_ordered_actions(
    base,
    base_compressor,
    actions,
  ))
  use root <- result.try(visible_root(restored))
  let visible =
    tree_kernel.visible_data(restored) != tree_kernel.visible_data(base)
  Ok(
    json.object([
      #("id", json.string(id)),
      #("generated", generated |> option.unwrap("") |> json.string),
      #("visible", json.bool(visible)),
      #("compressorAdvanced", json.bool(compressor != base_compressor)),
      #("value", visible_json(root)),
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

fn apply_ordered_actions(
  state: tree_kernel.TreeState,
  compressor: fluid_ids.Compressor,
  actions: List(JsonValue),
) -> Result(
  #(tree_kernel.TreeState, fluid_ids.Compressor, Option(String)),
  String,
) {
  list.try_fold(actions, #(state, compressor, None), fn(current, action) {
    use operation <- result.try(fixture_codec.field(
      action,
      "op",
      fixture_codec.text,
    ))
    case operation {
      "transaction" -> {
        use open <- result.try(
          transaction.begin(current.0, current.1, [])
          |> result.map_error(string.inspect),
        )
        use #(edited, generated) <- result.try(apply_transaction_action(
          open,
          action,
        ))
        use outcome <- result.try(optional_text(action, "result", "commit"))
        use #(state, compressor) <- result.try(case outcome {
          "rollback" ->
            transaction.abort(edited) |> result.map_error(string.inspect)
          "commit" -> {
            use finished <- result.try(
              transaction.finish(edited) |> result.map_error(string.inspect),
            )
            case finished.0 {
              transaction.NoCommit(state, _) ->
                Ok(#(state, transaction.compressor(edited)))
              transaction.Commit(state, compressor, _) ->
                Ok(#(state, compressor))
            }
          }
          _ -> Error("unsupported transaction result " <> outcome)
        })
        Ok(#(state, compressor, generated |> option.or(current.2)))
      }
      "set" | "clear" | "insert" | "remove" | "move" -> {
        use edit <- result.try(decode_edit(action))
        use #(state, commit, _, compressor) <- result.try(
          tree_runtime.author_edit(current.0, edit, current.1)
          |> result.map_error(string.inspect),
        )
        use _ <- result.try(
          commit |> option.to_result("ordered action produced no commit"),
        )
        let generated = case operation {
          "insert" -> inserted_identifier(state, action) |> option.from_result
          _ -> None
        }
        Ok(#(state, compressor, generated |> option.or(current.2)))
      }
      _ -> Error("unsupported ordered action " <> operation)
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
  use #(base, compressor) <- result.try(persistence_base(
    stored,
    initial,
    sessions,
    compressors,
  ))
  use root <- result.try(visible_root(base))
  use local <- result.try(runtime_identifier_core(
    root,
    compressor,
    "identifier-client-0",
  ))
  use remote_session <- result.try(input_session(sessions, "remote"))
  use serialized <- result.try(
    fluid_ids.serialize(compressor, False) |> result.map_error(string.inspect),
  )
  use remote_compressor <- result.try(
    fluid_ids.deserialize(serialized, remote_session)
    |> result.map_error(string.inspect),
  )
  use peer <- result.try(runtime_identifier_core(
    root,
    remote_compressor,
    "identifier-peer",
  ))
  let explicit_catch_up = has_retry_action(actions, "catch-up")
  let explicit_ack = has_retry_action(actions, "ack")
  use state <- result.try(run_retry_actions(
    RetryState(local, peer, True, True, None, None, 0, 0),
    actions,
    explicit_catch_up,
    explicit_ack,
  ))
  use identifier <- result.try(
    runtime_core.tree_read(state.local, "A/_C", ["left", "2", "id"])
    |> result.map_error(string.inspect)
    |> result.try(fn(value) { option.to_result(value, "retry id is absent") }),
  )
  use peer_identifier <- result.try(
    runtime_core.tree_read(state.peer, "A/_C", ["left", "2", "id"])
    |> result.map_error(string.inspect)
    |> result.try(fn(value) {
      option.to_result(value, "peer retry id is absent")
    }),
  )
  use accepted_identifier <- result.try(
    runtime_core.tree_read(state.local, "A/_C", ["left", "2", "id"])
    |> result.map_error(string.inspect)
    |> result.try(fn(value) {
      option.to_result(value, "accepted retry id is absent")
    }),
  )
  use peer_root <- result.try(
    runtime_core.tree_read(state.peer, "A/_C", [])
    |> result.map_error(string.inspect)
    |> result.try(fn(value) {
      option.to_result(value, "peer retry root is absent")
    }),
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
      #("pendingAfterAck", json.int(list.length(state.local.in_flight))),
      #("peerApplyCount", json.int(state.peer_apply_count)),
      #("resubmittedCount", json.int(state.resubmitted_count)),
    ]),
  )
}

type RetryState {
  RetryState(
    local: runtime_core.Core,
    peer: runtime_core.Core,
    connected: Bool,
    live: Bool,
    outbound: Option(wire.OutboundOperation),
    accepted: Option(spillway_types.SequencedDocumentMessage),
    peer_apply_count: Int,
    resubmitted_count: Int,
  )
}

fn run_retry_actions(
  state: RetryState,
  actions: List(JsonValue),
  explicit_catch_up: Bool,
  explicit_ack: Bool,
) -> Result(RetryState, String) {
  case actions {
    [] -> Ok(state)
    [action, ..rest] -> {
      use operation <- result.try(fixture_codec.field(
        action,
        "op",
        fixture_codec.text,
      ))
      case operation {
        "set" ->
          run_retry_edit_actions(
            state,
            actions,
            explicit_catch_up,
            explicit_ack,
          )
        "clear" ->
          run_retry_edit_actions(
            state,
            actions,
            explicit_catch_up,
            explicit_ack,
          )
        "insert" ->
          run_retry_edit_actions(
            state,
            actions,
            explicit_catch_up,
            explicit_ack,
          )
        "remove" ->
          run_retry_edit_actions(
            state,
            actions,
            explicit_catch_up,
            explicit_ack,
          )
        "move" ->
          run_retry_edit_actions(
            state,
            actions,
            explicit_catch_up,
            explicit_ack,
          )
        "disconnect" -> {
          use _ <- result.try(require(
            state.connected,
            "retry client is already disconnected",
          ))
          run_retry_actions(
            RetryState(..state, connected: False, live: False),
            rest,
            explicit_catch_up,
            explicit_ack,
          )
        }
        "reconnect" -> {
          use _ <- result.try(require(
            !state.connected,
            "retry client is already connected",
          ))
          let checkpoint = case state.accepted {
            Some(message) -> message.sequence_number
            None -> state.local.last_seen_sequence_number
          }
          use local <- result.try(
            runtime_core.adopt_reconnect(
              state.local,
              runtime_fixture.connected("identifier-client-1", [], checkpoint),
            )
            |> result.map_error(string.inspect),
          )
          let local = case explicit_catch_up {
            True -> local
            False -> runtime_core.go_live(local)
          }
          run_retry_actions(
            RetryState(
              ..state,
              local:,
              connected: True,
              live: !explicit_catch_up,
            ),
            rest,
            explicit_catch_up,
            explicit_ack,
          )
        }
        "accept" -> {
          use _ <- result.try(require(
            state.connected && state.live,
            "retry submission cannot be accepted while disconnected",
          ))
          use outbound <- result.try(
            state.outbound
            |> option.to_result("retry submission is absent"),
          )
          use #(state, message) <- result.try(accept_retry_submission(
            state,
            outbound,
          ))
          run_retry_actions(
            RetryState(..state, accepted: Some(message)),
            rest,
            explicit_catch_up,
            explicit_ack,
          )
        }
        "catch-up" -> {
          use _ <- result.try(require(
            state.connected && !state.live,
            "retry catch-up needs a reconnected client",
          ))
          use local <- result.try(case state.accepted {
            Some(message) ->
              runtime_core.handle_sequenced(state.local, message)
              |> result.map(fn(value) { value.0 })
              |> result.map_error(string.inspect)
            None -> Ok(state.local)
          })
          run_retry_actions(
            RetryState(..state, local: runtime_core.go_live(local), live: True),
            rest,
            explicit_catch_up,
            explicit_ack,
          )
        }
        "resubmit" -> {
          use _ <- result.try(require(
            state.connected && state.live,
            "retry resubmit needs a live connection",
          ))
          use #(local, outbounds) <- result.try(
            runtime_core.resubmit(state.local)
            |> result.map_error(string.inspect),
          )
          use #(state, accepted) <- result.try(case outbounds {
            [] -> Ok(#(RetryState(..state, local:), state.accepted))
            [outbound] -> {
              use #(accepted_state, message) <- result.try(
                accept_retry_submission(
                  RetryState(..state, local:, outbound: Some(outbound)),
                  outbound,
                ),
              )
              Ok(#(
                RetryState(
                  ..accepted_state,
                  resubmitted_count: state.resubmitted_count + 1,
                ),
                Some(message),
              ))
            }
            _ -> Error("retry resubmit produced multiple submissions")
          })
          use state <- result.try(case explicit_ack, accepted {
            False, Some(message) ->
              runtime_core.handle_sequenced(state.local, message)
              |> result.map(fn(value) { RetryState(..state, local: value.0) })
              |> result.map_error(string.inspect)
            _, _ -> Ok(state)
          })
          run_retry_actions(
            RetryState(..state, accepted:),
            rest,
            explicit_catch_up,
            explicit_ack,
          )
        }
        "ack" | "duplicate-ack" -> {
          use message <- result.try(
            state.accepted
            |> option.to_result("retry acknowledgement is absent"),
          )
          use #(local, _) <- result.try(
            runtime_core.handle_sequenced(state.local, message)
            |> result.map_error(string.inspect),
          )
          run_retry_actions(
            RetryState(..state, local:),
            rest,
            explicit_catch_up,
            explicit_ack,
          )
        }
        _ -> Error("unsupported retry action " <> operation)
      }
    }
  }
}

fn run_retry_edit_actions(
  state: RetryState,
  actions: List(JsonValue),
  explicit_catch_up: Bool,
  explicit_ack: Bool,
) -> Result(RetryState, String) {
  use #(edits, rest) <- result.try(retry_edits(actions))
  use #(local, _, outbound) <- result.try(
    runtime_core.submit_tree_edits(state.local, "A/_C", edits)
    |> result.map_error(string.inspect),
  )
  use outbound <- result.try(
    list.first(outbound)
    |> result.map_error(fn(_) { "retry edit produced no submission" }),
  )
  run_retry_actions(
    RetryState(..state, local:, outbound: Some(outbound)),
    rest,
    explicit_catch_up,
    explicit_ack,
  )
}

fn retry_edits(
  actions: List(JsonValue),
) -> Result(#(List(types.Edit), List(JsonValue)), String) {
  case actions {
    [action, ..rest] ->
      case fixture_codec.field(action, "op", fixture_codec.text) {
        Ok(operation) ->
          case is_edit_operation(operation) {
            True -> {
              use edit <- result.try(decode_edit(action))
              use #(edits, rest) <- result.try(retry_edits(rest))
              Ok(#([edit, ..edits], rest))
            }
            False -> Ok(#([], actions))
          }
        Error(_) -> Ok(#([], actions))
      }
    [] -> Ok(#([], []))
  }
}

fn is_edit_operation(operation: String) -> Bool {
  list.contains(["set", "clear", "insert", "remove", "move"], operation)
}

fn accept_retry_submission(
  state: RetryState,
  outbound: wire.OutboundOperation,
) -> Result(#(RetryState, spillway_types.SequencedDocumentMessage), String) {
  let message =
    sequenced_from_outbound(
      outbound,
      state.local.client_id,
      state.peer.last_seen_sequence_number + 1,
    )
  use #(peer, ingested) <- result.try(
    runtime_core.handle_sequenced(state.peer, message)
    |> result.map_error(string.inspect),
  )
  let applied = case ingested.events {
    [] -> 0
    _ -> 1
  }
  Ok(#(
    RetryState(
      ..state,
      peer:,
      peer_apply_count: state.peer_apply_count + applied,
    ),
    message,
  ))
}

fn runtime_identifier_core(
  root: types.TreeValue,
  compressor: fluid_ids.Compressor,
  client_id: String,
) -> Result(runtime_core.Core, String) {
  use seed <- result.try(
    runtime_core.bootstrap_seed(
      runtime_core.BootstrapSeedInput(
        ..full_seed_input(root),
        compressor: Some(compressor),
      ),
    )
    |> result.map_error(string.inspect),
  )
  use bootstrapped <- result.try(
    runtime_core.bootstrap_seeded(
      runtime_fixture.connected(client_id, [], 0),
      seed,
    )
    |> result.map_error(string.inspect),
  )
  case bootstrapped {
    runtime_core.Complete(core) -> Ok(core)
    runtime_core.MissingPrefix(_, _, _, _) ->
      Error("Identifier retry bootstrap has a missing prefix")
  }
}

fn sequenced_from_outbound(
  outbound: wire.OutboundOperation,
  client_id: String,
  sequence_number: Int,
) -> spillway_types.SequencedDocumentMessage {
  let assert Ok(contents) =
    json.parse(json.to_string(outbound.contents), decode.dynamic)
  let metadata = case outbound.metadata {
    Some(value) -> {
      let assert Ok(value) = json.parse(json.to_string(value), decode.dynamic)
      Some(value)
    }
    None -> None
  }
  spillway_types.SequencedDocumentMessage(
    client_id: Some(client_id),
    sequence_number: sequence_number,
    minimum_sequence_number: 0,
    client_sequence_number: outbound.client_sequence_number,
    reference_sequence_number: outbound.reference_sequence_number,
    message_type: "op",
    contents: contents,
    metadata: metadata,
    server_metadata: None,
    origin: None,
    timestamp: 0,
    data: None,
    traces: None,
  )
}

fn has_retry_action(actions: List(JsonValue), operation: String) -> Bool {
  list.any(actions, fn(action) {
    fixture_codec.field(action, "op", fixture_codec.text) == Ok(operation)
  })
}

fn has_retry_controls(actions: List(JsonValue)) -> Bool {
  list.any(
    [
      "disconnect",
      "reconnect",
      "catch-up",
      "resubmit",
      "accept",
      "ack",
      "duplicate-ack",
    ],
    has_retry_action(actions, _),
  )
}

fn run_remove(
  id: String,
  actions: List(JsonValue),
  stored: schema.StoredSchema,
  initial: types.TreeValue,
  sessions: JsonValue,
  compressors: JsonValue,
) -> Result(json.Json, String) {
  use action <- result.try(
    list.first(actions)
    |> result.map_error(fn(_) { id <> ": remove action is absent" }),
  )
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
  use #(after, _, _) <- result.try(apply_ordered_actions(
    after,
    compressor,
    list.drop(actions, 1),
  ))
  use root <- result.try(visible_root(after))
  Ok(
    json.object([
      #("id", json.string(id)),
      #("identifier", case identifier {
        types.StringValue(value) -> json.string(value)
        _ -> json.null()
      }),
      #("repair", fixture_codec.array(repair)),
      #("retainedForest", forest_data_json(data)),
      #("value", visible_json(root)),
    ]),
  )
}

fn run_move(
  id: String,
  actions: List(JsonValue),
  stored: schema.StoredSchema,
  initial: types.TreeValue,
  sessions: JsonValue,
  compressors: JsonValue,
) -> Result(json.Json, String) {
  use action <- result.try(
    list.first(actions)
    |> result.map_error(fn(_) { id <> ": move action is absent" }),
  )
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
  use #(after, _, _, compressor) <- result.try(
    tree_runtime.author_edit(base, edit, compressor)
    |> result.map_error(string.inspect),
  )
  use moved <- result.try(
    tree_kernel.reference_at(after, ["right", "0"])
    |> result.map_error(string.inspect),
  )
  use #(after, _, _) <- result.try(apply_ordered_actions(
    after,
    compressor,
    list.drop(actions, 1),
  ))
  use root <- result.try(visible_root(after))
  Ok(
    json.object([
      #("id", json.string(id)),
      #("identifier", case identifier {
        types.StringValue(value) -> json.string(value)
        _ -> json.null()
      }),
      #("identityPreserved", json.bool(reference == moved)),
      #("value", visible_json(root)),
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

fn allocation_events_from_range(
  value: types.TreeValue,
  revision: Option(fluid_ids.StableId),
  compressor: fluid_ids.Compressor,
  allocation: Option(fluid_ids.CreationRange),
) -> Result(json.Json, String) {
  let bounds = allocation_bounds(allocation)
  use identifiers <- result.try(
    identifier_paths(value, [])
    |> list.try_fold([], fn(identifiers, entry) {
      case fluid_ids.stable_id(entry.1) {
        Error(_) -> Ok(identifiers)
        Ok(stable) ->
          case fluid_ids.recompress(compressor, stable) {
            Ok(Some(value)) -> {
              use operation <- result.try(
                fluid_ids.to_op(compressor, value)
                |> result.map_error(string.inspect),
              )
              let operation = fluid_ids.op_id_to_int(operation)
              case operation_in_bounds(operation, bounds) {
                True -> Ok([#(operation, entry.0), ..identifiers])
                False -> Ok(identifiers)
              }
            }
            Ok(None) -> Ok(identifiers)
            Error(error) -> Error(string.inspect(error))
          }
      }
    }),
  )
  use revision_op <- result.try(case revision {
    Some(revision) ->
      case fluid_ids.recompress(compressor, revision) {
        Ok(Some(value)) ->
          fluid_ids.to_op(compressor, value)
          |> result.map(fluid_ids.op_id_to_int)
          |> result.map_error(string.inspect)
        Ok(None) -> Error("allocation revision is absent from the compressor")
        Error(error) -> Error(string.inspect(error))
      }
    None -> Ok(-1)
  })
  Ok(allocation_event_json(identifiers, revision_op))
}

fn edit_allocation_events(
  state: tree_kernel.TreeState,
  revision: fluid_ids.StableId,
  compressor: fluid_ids.Compressor,
) -> Result(json.Json, String) {
  use data <- result.try(
    tree_kernel.visible_data(state) |> result.map_error(string.inspect),
  )
  use value <- result.try(
    data.root |> option.to_result("allocation event root is absent"),
  )
  let #(_, allocation) = fluid_ids.take_creation_range(compressor)
  allocation_events_from_range(value, Some(revision), compressor, allocation)
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
    case revision >= 0 {
      True ->
        list.append(events, [
          json.object([
            #("ordinal", json.int(list.length(events) + 1)),
            #("kind", json.string("revision")),
            #("path", json.array([], fn(value) { value })),
            #("op", json.int(revision)),
          ]),
        ])
      False -> events
    },
    fn(value) { value },
  )
}

fn allocation_bounds(
  allocation: Option(fluid_ids.CreationRange),
) -> Option(#(Int, Int)) {
  case allocation {
    Some(fluid_ids.CreationRange(_, Some(ids))) ->
      Some(#(ids.first_gen_count - 1, ids.first_gen_count + ids.count - 2))
    _ -> None
  }
}

fn operation_in_bounds(operation: Int, bounds: Option(#(Int, Int))) -> Bool {
  case bounds {
    Some(bounds) -> operation >= bounds.0 && operation <= bounds.1
    None -> False
  }
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

fn require(value: Bool, detail: String) -> Result(Nil, String) {
  case value {
    True -> Ok(Nil)
    False -> Error(detail)
  }
}
