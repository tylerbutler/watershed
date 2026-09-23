import gleam/json
import gleam/option.{None, Some}
import startest/expect
import watershed/fluid_ids
import watershed/tree/codec

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
