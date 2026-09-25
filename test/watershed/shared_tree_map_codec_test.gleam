import gleam/json
import gleam/list
import gleam/option.{Some}
import gleam/string
import startest/expect
import watershed/fluid_ids
import watershed/json_ot.{VArray, VObject, VString}
import watershed/tree/change
import watershed/tree/codec
import watershed/tree/fixtures
import watershed/tree/schema
import watershed/tree/types.{MapValue, StringValue, UnsupportedFeature}

const map_type = "org.watershed.shared-tree.m2.DynamicMap"

pub fn shared_tree_map_codec_decodes_reconnect_map_build_test() -> Nil {
  let assert Ok(fixtures.Case(raw:, ..)) = fixtures.load("map-history-codecs")
  let assert Ok(VObject(raw)) = json_ot.parse_json(json.to_string(raw))
  let assert Ok(VObject(summary)) = list.key_find(raw, "summary")
  let assert Ok(VString(schema_raw)) = list.key_find(summary, "schema")
  let assert Ok(stored) = schema.stored_from_string(schema_raw)
  let assert Ok(VArray([VObject(message), ..])) =
    list.key_find(raw, "reconnect")
  let assert Ok(VObject(reload)) = list.key_find(raw, "reload")
  let assert Ok(VString(compressor_raw)) = list.key_find(reload, "compressor")
  let assert Ok(fresh_session) =
    fluid_ids.session_id("30000000-0000-4000-8000-000000000003")
  let compressor = case
    fluid_ids.deserialize(json.string(compressor_raw), fresh_session)
  {
    Ok(value) -> value
    Error(error) -> panic as { string.inspect(error) }
  }
  let decoded = case
    codec.decode_message_with_schema(
      json.to_string(json_ot.to_json(VObject(message))),
      codec.DecodeContext(codec.Fluid310, compressor),
      stored,
    )
  {
    Ok(value) -> value
    Error(error) -> panic as { string.inspect(error) }
  }
  let assert codec.TreeMessage(
    codec.WireCommit(changes: [codec.DataChange(changeset)], ..),
    _,
  ) = decoded
  let data = change.to_data(changeset)
  let assert [build] = data.builds
  build.trees
  |> expect.to_equal([
    MapValue(map_type, [#("inner", StringValue("pending"))]),
  ])
  let assert Ok(encoded) =
    codec.encode_message(
      decoded,
      codec.EncodeContext(codec.Fluid310, compressor, Some(stored)),
    )
  let assert Ok(again) =
    codec.decode_message_with_schema(
      json.to_string(encoded),
      codec.DecodeContext(codec.Fluid310, compressor),
      stored,
    )
  let assert codec.TreeMessage(
    codec.WireCommit(changes: [codec.DataChange(again_changeset)], ..),
    _,
  ) = again
  change.to_data(again_changeset) |> expect.to_equal(data)
}

pub fn shared_tree_map_codec_rejects_invented_map_field_kind_test() -> Nil {
  let assert Ok(fixtures.Case(input:, raw:, ..)) =
    fixtures.load("map-history-codecs")
  let assert Ok(VObject(input)) = json_ot.parse_json(json.to_string(input))
  let assert Ok(VObject(bytes)) = list.key_find(input, "messageBytes")
  let assert Ok(VString(set)) = list.key_find(bytes, "set")
  let changed =
    set
    |> string.replace("\"fieldKind\":\"Optional\"", "\"fieldKind\":\"Map\"")
  let assert Ok(VObject(raw)) = json_ot.parse_json(json.to_string(raw))
  let assert Ok(VObject(summary)) = list.key_find(raw, "summary")
  let assert Ok(VString(schema_raw)) = list.key_find(summary, "schema")
  let assert Ok(stored) = schema.stored_from_string(schema_raw)
  let assert Ok(VObject(reload)) = list.key_find(raw, "reload")
  let assert Ok(VString(compressor_raw)) = list.key_find(reload, "compressor")
  let assert Ok(session) =
    fluid_ids.session_id("30000000-0000-4000-8000-000000000003")
  let assert Ok(compressor) =
    fluid_ids.deserialize(json.string(compressor_raw), session)
  let assert Error(UnsupportedFeature(_, "field kind Map")) =
    codec.decode_message_with_schema(
      changed,
      codec.DecodeContext(codec.Fluid310, compressor),
      stored,
    )
  Nil
}
