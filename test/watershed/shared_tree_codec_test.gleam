import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import startest/expect
import watershed/fluid_ids
import watershed/tree/change
import watershed/tree/codec
import watershed/tree/fixtures
import watershed/tree/forest
import watershed/tree/optional_field
import watershed/tree/schema
import watershed/tree/types
import watershed/wire

const session_a = "10000000-0000-4000-8000-000000000001"

fn session(raw: String) -> fluid_ids.SessionId {
  let assert Ok(session) = fluid_ids.session_id(raw)
  session
}

pub fn shared_tree_codec_empty_schema_test() {
  let raw =
    "{\"version\":2,\"nodes\":{},\"root\":{\"kind\":\"Forbidden\",\"types\":[]}}"
  let assert Ok(codec.EmptySchema) = codec.decode_schema(raw)
  let assert Ok(encoded) = codec.encode_schema(codec.EmptySchema)
  codec.decode_schema(json.to_string(encoded))
  |> expect.to_equal(Ok(codec.EmptySchema))
}

pub fn shared_tree_codec_rejects_noncanonical_empty_schema_test() {
  let assert Error(_) =
    codec.decode_schema(
      "{\"version\":2,\"nodes\":{},\"root\":{\"kind\":\"Forbidden\",\"types\":[]},\"metadata\":{}}",
    )
  Nil
}

pub fn shared_tree_codec_revision_uses_compressor_space_test() {
  let owner = session(session_a)
  let assert Ok(#(compressor, local)) =
    fluid_ids.new(owner) |> fluid_ids.generate
  let assert #(compressor, Some(range)) =
    fluid_ids.take_creation_range(compressor)
  let assert Ok(compressor) = fluid_ids.finalize(compressor, range)
  let assert Ok(stable) = fluid_ids.decompress(compressor, local)
  let decode_context = codec.DecodeContext(codec.Fluid310, compressor)
  let encode_context = codec.EncodeContext(codec.Fluid310, compressor, None)
  let assert Ok(encoded) =
    codec.encode_stable_revision(stable, encode_context, "revision")
  encoded |> expect.to_equal(0)
  codec.decode_stable_revision(encoded, owner, decode_context, "revision")
  |> expect.to_equal(Ok(stable))
}

pub fn shared_tree_codec_revision_requires_known_context_test() {
  let owner = session(session_a)
  let compressor = fluid_ids.new(owner)
  let assert Ok(stable) = fluid_ids.stable_id(session_a)
  let assert Error(_) =
    codec.encode_stable_revision(
      stable,
      codec.EncodeContext(codec.Fluid310, compressor, None),
      "revision",
    )
  let assert Error(_) =
    codec.decode_stable_revision(
      -1,
      owner,
      codec.DecodeContext(codec.Fluid310, compressor),
      "revision",
    )
  Nil
}

pub fn shared_tree_codec_decodes_raw_v7_generic_message_test() {
  let fixture_result = fixtures.load("tree-codecs")
  fixture_result |> expect.to_be_ok
  let assert Ok(fixture) = fixture_result
  let fixtures.Case(input:, ..) = fixture
  let allocation_decoder =
    decode.at(["contents", "contents"], decode.dynamic)
    |> decode.map(wire.dynamic_to_json)
  let metadata_decoder = {
    use raw <- decode.field("raw", decode.string)
    use session <- decode.field("session", decode.string)
    use compressor <- decode.field("compressor", decode.string)
    use allocations <- decode.field(
      "allocationMessages",
      decode.list(allocation_decoder),
    )
    decode.success(#(raw, session, compressor, allocations))
  }
  let parsed =
    json.parse(
      json.to_string(input),
      decode.at(["metadataMessage"], metadata_decoder),
    )
  parsed |> expect.to_be_ok
  let assert Ok(#(raw, local_session, serialized, allocations)) = parsed
  let session_result = fluid_ids.session_id(local_session)
  session_result |> expect.to_be_ok
  let assert Ok(local_session) = session_result
  let compressor_result =
    fluid_ids.deserialize(json.string(serialized), local_session)
  compressor_result |> expect.to_be_ok
  let assert Ok(compressor) = compressor_result
  let finalized =
    list.try_fold(allocations, compressor, fn(compressor, encoded) {
      let assert Ok(range) = fluid_ids.creation_range_from_json(encoded)
      case range.session_id == local_session {
        True -> Ok(compressor)
        False -> fluid_ids.finalize(compressor, range)
      }
    })
  finalized |> expect.to_be_ok
  let assert Ok(compressor) = finalized
  let assert Ok(before) = fluid_ids.serialize(compressor, True)
  let context = codec.DecodeContext(codec.Fluid310, compressor)
  let decoded = codec.decode_message(raw, context)
  decoded |> expect.to_be_ok
  let assert Ok(message) = decoded
  let codec.TreeMessage(
    codec.WireCommit(revision, originator, changes, metadata),
    extras,
  ) = message
  fluid_ids.session_id_to_string(originator)
  |> expect.to_equal("a0693eac-892a-4396-86f7-ad20dc1cade2")
  fluid_ids.stable_id_to_string(revision)
  |> expect.to_equal("a0693eac-892a-4396-86f7-ad20dc1cade2")
  let assert [codec.DataChange(data_change)] = changes
  let data = change.to_data(data_change)
  data.max_local_id |> expect.to_equal(2)
  let assert [#("rootFieldKey", change.GenericField([#(0, child_id)]))] =
    data.fields
  child_id.local_id |> expect.to_equal(3)
  let assert [
    #(_, change.NodeChange([#("title", change.ValueField(title_change))])),
  ] = data.nodes
  let assert Some(replacement) = title_change.replacement
  replacement.was_empty |> expect.to_be_false
  let assert Some(optional_field.Detached(source)) = replacement.source
  source.local_id |> expect.to_equal(0)
  replacement.detach_id.local_id |> expect.to_equal(1)
  let assert [build] = data.builds
  build.id.local_id |> expect.to_equal(0)
  build.trees |> expect.to_equal([types.StringValue("right")])
  let assert Some(codec.CustomMetadata(Some(value), children)) = metadata
  json.to_string(value)
  |> string.contains("\"source\":\"watershed\"")
  |> expect.to_be_true
  list.length(children) |> expect.to_equal(2)
  let assert [#("toleratedEnvelopeProperty", extra)] = extras
  json.to_string(extra) |> expect.to_equal("{\"preserved\":true}")
  let assert Ok(encoded) =
    codec.encode_message(
      message,
      codec.EncodeContext(codec.Fluid310, compressor, None),
    )
  codec.decode_message(json.to_string(encoded), context)
  |> expect.to_equal(Ok(message))
  fluid_ids.serialize(compressor, True) |> expect.to_equal(Ok(before))
}

pub fn shared_tree_codec_decodes_optional_clear_test() {
  let scenario = scenario_message("optional", 2)
  scenario |> expect.to_be_ok
  let assert Ok(#(raw, local_session, serialized, allocations)) = scenario
  let assert Ok(local_session) = fluid_ids.session_id(local_session)
  let assert Ok(compressor) =
    fluid_ids.deserialize(json.string(serialized), local_session)
  let finalized =
    list.try_fold(allocations, compressor, fn(compressor, encoded) {
      let assert Ok(range) = fluid_ids.creation_range_from_json(encoded)
      case range.session_id == local_session {
        True -> Ok(compressor)
        False -> fluid_ids.finalize(compressor, range)
      }
    })
  finalized |> expect.to_be_ok
  let assert Ok(compressor) = finalized
  let decoded =
    codec.decode_message(raw, codec.DecodeContext(codec.Fluid310, compressor))
  decoded |> expect.to_be_ok
  let assert Ok(codec.TreeMessage(
    codec.WireCommit(_, _, [codec.DataChange(changes)], _),
    _,
  )) = decoded
  let data = change.to_data(changes)
  let assert [#("rootFieldKey", change.GenericField([#(0, root_change)]))] =
    data.fields
  let assert Ok(change.NodeChange([#("note", change.OptionalField(note_change))])) =
    list.key_find(data.nodes, root_change)
  let assert Some(replacement) = note_change.replacement
  replacement.was_empty |> expect.to_be_false
  replacement.source |> expect.to_equal(None)
  replacement.detach_id.local_id |> expect.to_equal(0)
}

pub fn shared_tree_codec_preserves_bootstrap_change_order_test() {
  let assert Ok(#(raw, local_session, serialized, _)) =
    scenario_message("same-field", 0)
  let assert Ok(local_session) = fluid_ids.session_id(local_session)
  let assert Ok(compressor) =
    fluid_ids.deserialize(json.string(serialized), local_session)
  let assert Ok(codec.TreeMessage(
    codec.WireCommit(
      _,
      _,
      [
        codec.SchemaChange(codec.EmptySchema, codec.FixedSchema(_)),
        codec.DataChange(_),
        codec.SchemaChange(codec.FixedSchema(_), codec.FixedSchema(_)),
      ],
      _,
    ),
    _,
  )) =
    codec.decode_message(raw, codec.DecodeContext(codec.Fluid310, compressor))
  Nil
}

pub fn shared_tree_codec_normalizes_empty_metadata_tree_test() {
  let owner = session(session_a)
  let assert Ok(#(compressor, local)) =
    fluid_ids.new(owner) |> fluid_ids.generate
  let assert #(compressor, Some(range)) =
    fluid_ids.take_creation_range(compressor)
  let assert Ok(compressor) = fluid_ids.finalize(compressor, range)
  let assert Ok(operation) = fluid_ids.to_op(compressor, local)
  let raw =
    "{\"revision\":"
    <> int.to_string(fluid_ids.op_id_to_int(operation))
    <> ",\"originatorId\":\""
    <> session_a
    <> "\",\"changeset\":[],\"version\":7,\"customMetadata\":{\"c\":[{}]}}"
  let assert Ok(codec.TreeMessage(codec.WireCommit(_, _, _, metadata), _)) =
    codec.decode_message(raw, codec.DecodeContext(codec.Fluid310, compressor))
  metadata |> expect.to_equal(None)
}

pub fn shared_tree_codec_encodes_native_authored_change_test() {
  let owner = session(session_a)
  let assert Ok(#(compressor, local)) =
    fluid_ids.new(owner) |> fluid_ids.generate
  let assert #(compressor, Some(range)) =
    fluid_ids.take_creation_range(compressor)
  let assert Ok(compressor) = fluid_ids.finalize(compressor, range)
  let assert Ok(revision) = fluid_ids.decompress(compressor, local)
  let schema_raw =
    "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.string\":{\"kind\":{\"leaf\":1}}},\"root\":{\"kind\":\"Optional\",\"types\":[\"com.fluidframework.leaf.string\"]}}"
  let assert Ok(stored) = schema.stored_from_string(schema_raw)
  let assert Ok(initial) = forest.new(revision, stored, None)
  let assert Ok(order) = codec.identity_order([revision], compressor, "change")
  let assert Ok(authored) =
    change.edit(
      stored,
      initial,
      revision,
      types.SetField([], types.StringValue("native")),
      order,
    )
  let change_context = codec.ChangeContext(owner, Some(revision), codec.Message)
  let assert Ok(encoded) =
    codec.encode_modular(
      authored,
      codec.EncodeContext(codec.Fluid310, compressor, Some(stored)),
      change_context,
    )
  let assert Ok(decoded) =
    codec.decode_modular(
      encoded,
      codec.DecodeContext(codec.Fluid310, compressor),
      change_context,
    )
  change.to_data(decoded) |> expect.to_equal(change.to_data(authored))
}

pub fn shared_tree_codec_untagged_revisions_round_trip_test() {
  let owner = session(session_a)
  let assert Ok(#(compressor, first)) =
    fluid_ids.new(owner) |> fluid_ids.generate
  let assert Ok(#(compressor, second)) = fluid_ids.generate(compressor)
  let assert #(compressor, Some(range)) =
    fluid_ids.take_creation_range(compressor)
  let assert Ok(compressor) = fluid_ids.finalize(compressor, range)
  let assert Ok(first_revision) = fluid_ids.decompress(compressor, first)
  let assert Ok(second_revision) = fluid_ids.decompress(compressor, second)
  let encoded =
    json.object([
      #("changes", json.array([], fn(value) { value })),
      #(
        "revisions",
        json.array(
          [
            json.object([#("revision", json.int(0))]),
            json.object([
              #("revision", json.int(1)),
              #("rollbackOf", json.int(0)),
            ]),
          ],
          fn(value) { value },
        ),
      ),
    ])
  let decode_context = codec.DecodeContext(codec.Fluid310, compressor)
  let change_context = codec.ChangeContext(owner, None, codec.Summary)
  let assert Ok(change_set) =
    codec.decode_modular(encoded, decode_context, change_context)
  change.to_data(change_set).revisions
  |> expect.to_equal([
    change.RevisionInfo(first_revision, None),
    change.RevisionInfo(second_revision, Some(first_revision)),
  ])
  let assert Ok(round_trip) =
    codec.encode_modular(
      change_set,
      codec.EncodeContext(codec.Fluid310, compressor, None),
      change_context,
    )
  codec.decode_modular(round_trip, decode_context, change_context)
  |> expect.to_equal(Ok(change_set))
}

pub fn shared_tree_codec_rejects_tagged_revision_mismatch_test() {
  let owner = session(session_a)
  let assert Ok(#(compressor, first)) =
    fluid_ids.new(owner) |> fluid_ids.generate
  let assert Ok(#(compressor, _)) = fluid_ids.generate(compressor)
  let assert #(compressor, Some(range)) =
    fluid_ids.take_creation_range(compressor)
  let assert Ok(compressor) = fluid_ids.finalize(compressor, range)
  let assert Ok(first_revision) = fluid_ids.decompress(compressor, first)
  let encoded =
    json.object([
      #("changes", json.array([], fn(value) { value })),
      #(
        "revisions",
        json.array([json.object([#("revision", json.int(1))])], fn(value) {
          value
        }),
      ),
    ])
  let assert Error(types.CorruptData(_, _)) =
    codec.decode_modular(
      encoded,
      codec.DecodeContext(codec.Fluid310, compressor),
      codec.ChangeContext(owner, Some(first_revision), codec.Message),
    )
  Nil
}

pub fn shared_tree_codec_rejects_unknown_message_version_test() {
  let owner = session(session_a)
  let context = codec.DecodeContext(codec.Fluid310, fluid_ids.new(owner))
  let assert Error(types.UnsupportedFormat("Message", "6")) =
    codec.decode_message(
      "{\"revision\":0,\"originatorId\":\"10000000-0000-4000-8000-000000000001\",\"changeset\":[],\"version\":6}",
      context,
    )
  Nil
}

fn scenario_message(
  id: String,
  message_index: Int,
) -> Result(#(String, String, String, List(json.Json)), Nil) {
  let allocation_decoder =
    decode.at(["contents", "contents"], decode.dynamic)
    |> decode.map(wire.dynamic_to_json)
  let scenario_decoder = {
    use scenario_id <- decode.field("id", decode.string)
    use session <- decode.field("session", decode.string)
    use compressor <- decode.field("compressor", decode.string)
    use allocations <- decode.field(
      "allocationMessages",
      decode.list(allocation_decoder),
    )
    use messages <- decode.field("messages", decode.list(decode.string))
    decode.success(#(scenario_id, session, compressor, allocations, messages))
  }
  let assert Ok(fixture) = fixtures.load("tree-codecs")
  let fixtures.Case(input:, ..) = fixture
  let input_decoder = {
    use scenarios <- decode.field("scenarios", decode.list(scenario_decoder))
    decode.success(scenarios)
  }
  let assert Ok(scenarios) = json.parse(json.to_string(input), input_decoder)
  let assert Ok(#(_, session, compressor, allocations, messages)) =
    list.find(
      scenarios,
      fn(scenario: #(String, String, String, List(json.Json), List(String))) {
        scenario.0 == id
      },
    )
  let assert Ok(raw) = list_get(messages, message_index)
  Ok(#(raw, session, compressor, allocations))
}

fn list_get(values: List(value), index: Int) -> Result(value, Nil) {
  case index, values {
    0, [value, ..] -> Ok(value)
    index, [_, ..rest] if index > 0 -> list_get(rest, index - 1)
    _, _ -> Error(Nil)
  }
}
