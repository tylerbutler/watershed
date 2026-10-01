import gleam/json
import gleam/list
import gleam/option.{Some}
import watershed/channel
import watershed/fluid_ids
import watershed/runtime_core
import watershed/tree/forest
import watershed/tree/history
import watershed/tree/runtime_fixture
import watershed/tree/schema
import watershed/tree/types
import watershed/tree_kernel
import watershed/wire/fluid_container

pub const point_type = "org.watershed.shared-tree.identifiers.Point"

pub const pair_type = "org.watershed.shared-tree.identifiers.Pair"

pub const items_type = "org.watershed.shared-tree.identifiers.Items"

pub const map_type = "org.watershed.shared-tree.identifiers.PointsByKey"

pub const root_type = "org.watershed.shared-tree.identifiers.Root"

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
