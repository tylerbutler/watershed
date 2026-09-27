import gleam/dynamic/decode
import gleam/json
import watershed/fluid_ids.{type StableId}
import watershed/tree/fixtures
import watershed/tree/schema.{type StoredSchema, type ViewSchema}

pub fn stored(name: String) -> StoredSchema {
  let assert Ok(fixture) = fixtures.load("array-schema-content")
  let assert Ok(raw) =
    json.parse(
      json.to_string(fixture.input),
      decode.at(["schemas", name], decode.string),
    )
  let assert Ok(stored) = schema.stored_from_string(raw)
  stored
}

pub fn view(name: String) -> ViewSchema {
  let assert Ok(fixture) = fixtures.load("array-schema-content")
  let assert Ok(raw) =
    json.parse(
      json.to_string(fixture.input),
      decode.at(["schemas", name], decode.string),
    )
  let assert Ok(view) = schema.view_from_string(raw)
  view
}

pub fn view_id() -> StableId {
  let assert Ok(id) =
    fluid_ids.stable_id("00000000-0000-4000-8000-000000000004")
  id
}
