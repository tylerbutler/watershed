import gleam/json
import gleam/option.{Some}
import watershed/fluid_ids
import watershed/tree/forest
import watershed/tree/history
import watershed/tree/schema
import watershed/tree/types
import watershed/tree_kernel

pub const point_type = "org.watershed.shared-tree.identifiers.Point"

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
