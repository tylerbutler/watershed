import gleam/bit_array
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import startest/expect
import watershed/fluid_ids
import watershed/json_ot.{VObject}
import watershed/tree/fixtures
import watershed/tree/id_fixture

const session_a = "10000000-0000-4000-8000-000000000001"

const session_b = "20000000-0000-4000-8000-000000000002"

fn session(raw: String) -> fluid_ids.SessionId {
  let assert Ok(session) = fluid_ids.session_id(raw)
  session
}

fn generate(
  state: fluid_ids.Compressor,
  count: Int,
) -> #(fluid_ids.Compressor, List(fluid_ids.SessionSpaceId)) {
  case count {
    0 -> #(state, [])
    _ -> {
      let assert Ok(#(state, id)) = fluid_ids.generate(state)
      let #(state, rest) = generate(state, count - 1)
      #(state, [id, ..rest])
    }
  }
}

fn range(
  owner: fluid_ids.SessionId,
  first: Int,
  count: Int,
  size: Int,
  locals: List(#(Int, Int)),
) -> fluid_ids.CreationRange {
  fluid_ids.CreationRange(
    owner,
    Some(fluid_ids.RangeIds(first, count, size, locals)),
  )
}

pub fn shared_tree_id_finalization_preserves_identity_test() {
  let assert Ok(session) = fluid_ids.session_id(session_a)
  let assert Ok(#(state, local)) = fluid_ids.new(session) |> fluid_ids.generate
  let assert Ok(before) = fluid_ids.decompress(state, local)
  let assert #(state, Some(range)) = fluid_ids.take_creation_range(state)
  let assert Ok(state) = fluid_ids.finalize(state, range)
  let assert Ok(after) = fluid_ids.decompress(state, local)
  after |> expect.to_equal(before)
  fluid_ids.stable_id_to_string(after) |> expect.to_equal(session_a)
  fluid_ids.session_space_id_to_int(local) |> expect.to_equal(-1)
  let assert Ok(op) = fluid_ids.to_op(state, local)
  fluid_ids.op_id_to_int(op) |> expect.to_equal(0)
  fluid_ids.from_op(state, op, session) |> expect.to_equal(Ok(local))
  fluid_ids.recompress(state, before) |> expect.to_equal(Ok(Some(local)))
  fluid_ids.take_creation_range(state) |> expect.to_equal(#(state, None))
}

pub fn shared_tree_ids_uuid_and_integer_validation_test() {
  [
    "",
    "10000000-0000-1000-8000-000000000001",
    "10000000-0000-4000-7000-000000000001",
    "10000000-0000-4000-c000-000000000001",
    "10000000-0000-4000-8000-00000000000z",
    "+0000000-0000-4000-8000-000000000001",
    "10000000-0000-4000-8000-0000000000010",
  ]
  |> list.each(fn(raw) {
    fluid_ids.session_id(raw) |> expect.to_be_error
    fluid_ids.stable_id(raw) |> expect.to_be_error
  })
  let assert Ok(id) =
    fluid_ids.stable_id("ABCDEFAB-CDEF-4ABC-bDEF-ABCDEFABCDEF")
  fluid_ids.stable_id_to_string(id)
  |> expect.to_equal("abcdefab-cdef-4abc-bdef-abcdefabcdef")
  let unsafe = 9_007_199_254_740_991 + 1
  [unsafe, -unsafe]
  |> list.each(fn(id) {
    fluid_ids.op_id(id) |> expect.to_be_error
    fluid_ids.session_space_id(id) |> expect.to_be_error
  })
  [-9_007_199_254_740_991, 0, 9_007_199_254_740_991]
  |> list.each(fn(id) {
    let assert Ok(op) = fluid_ids.op_id(id)
    let assert Ok(local) = fluid_ids.session_space_id(id)
    fluid_ids.op_id_to_int(op) |> expect.to_equal(id)
    fluid_ids.session_space_id_to_int(local) |> expect.to_equal(id)
  })
}

pub fn shared_tree_ids_uuid_carry_preserves_version_and_variant_test() {
  let #(state, ids) =
    fluid_ids.new(session("00000000-0000-4fff-bfff-fffffffffffe"))
    |> generate(3)
  list.map(ids, fn(id) {
    let assert Ok(stable) = fluid_ids.decompress(state, id)
    fluid_ids.stable_id_to_string(stable)
  })
  |> expect.to_equal([
    "00000000-0000-4fff-bfff-fffffffffffe",
    "00000000-0000-4fff-bfff-ffffffffffff",
    "00000000-0001-4000-8000-000000000000",
  ])
  let state = fluid_ids.new(session("ffffffff-ffff-4fff-bfff-ffffffffffff"))
  let assert Ok(#(state, _)) = fluid_ids.generate(state)
  fluid_ids.generate(state)
  |> expect.to_equal(Error(fluid_ids.IdSpaceExhausted))
}

pub fn shared_tree_ids_invalid_ranges_are_atomic_test() {
  let owner = session(session_b)
  let state = fluid_ids.new(session(session_a))
  [
    range(owner, 1, 0, 3, []),
    range(owner, 0, 1, 3, []),
    range(owner, 1, -1, 3, []),
    range(owner, 1, 1, 0, []),
    range(owner, 1, 1, 1_048_577, []),
    range(owner, 1, 9_007_199_254_740_991 + 1, 3, []),
    range(owner, 9_007_199_254_740_991, 2, 3, []),
    range(owner, 1, 2, 3, [#(0, 1)]),
    range(owner, 1, 2, 3, [#(1, 0)]),
    range(owner, 1, 2, 3, [#(1, 3)]),
    range(owner, 1, 2, 3, [#(2, 1), #(1, 1)]),
    range(owner, 1, 2, 3, [#(1, 2), #(2, 1)]),
  ]
  |> list.each(fn(invalid) {
    fluid_ids.finalize(state, invalid) |> expect.to_be_error
    let assert Ok(#(_, id)) = fluid_ids.generate(state)
    fluid_ids.session_space_id_to_int(id) |> expect.to_equal(-1)
  })
  fluid_ids.with_cluster_size(state, 0) |> expect.to_be_error
  fluid_ids.with_cluster_size(state, 1_048_577) |> expect.to_be_error
  fluid_ids.finalize(state, range(owner, 2, 1, 3, []))
  |> expect.to_equal(Error(fluid_ids.OutOfOrder(1, 2)))
  let first = range(owner, 1, 2, 3, [#(1, 2)])
  let assert Ok(state) = fluid_ids.finalize(state, first)
  fluid_ids.finalize(state, first)
  |> expect.to_equal(Error(fluid_ids.OutOfOrder(3, 1)))
  fluid_ids.finalize(state, range(owner, 4, 1, 3, []))
  |> expect.to_equal(Error(fluid_ids.OutOfOrder(3, 4)))
  fluid_ids.finalize(state, range(owner, 3, 1, 3, []))
  |> expect.to_be_ok
  Nil
}

pub fn shared_tree_ids_eager_normalization_and_pending_range_test() {
  let owner = session(session_a)
  let assert Ok(state) = fluid_ids.new(owner) |> fluid_ids.with_cluster_size(2)
  let #(state, _) = generate(state, 1)
  let assert #(state, Some(first)) = fluid_ids.take_creation_range(state)
  let assert Ok(state) = fluid_ids.finalize(state, first)
  let #(state, ids) = generate(state, 3)
  list.map(ids, fluid_ids.session_space_id_to_int)
  |> expect.to_equal([1, 2, -4])
  let assert #(taken, Some(next)) = fluid_ids.take_creation_range(state)
  next |> expect.to_equal(range(owner, 2, 3, 2, [#(4, 1)]))
  fluid_ids.take_unfinalized_range(taken)
  |> expect.to_equal(#(taken, Some(next)))
  let assert Ok(finalized) = fluid_ids.finalize(taken, next)
  let assert Ok(op) = fluid_ids.op_id(3)
  let assert Ok(local) = fluid_ids.from_op(finalized, op, owner)
  fluid_ids.session_space_id_to_int(local) |> expect.to_equal(-4)
  let assert Ok(state) =
    fluid_ids.new(session(session_b)) |> fluid_ids.finalize(first)
  let assert Ok(state) = fluid_ids.finalize(state, next)
  let assert Ok(op) = fluid_ids.op_id(-4)
  let assert Ok(remote) = fluid_ids.from_op(state, op, owner)
  fluid_ids.session_space_id_to_int(remote) |> expect.to_equal(3)
  let assert Ok(stable) = fluid_ids.decompress(state, remote)
  fluid_ids.stable_id_to_string(stable)
  |> expect.to_equal("10000000-0000-4000-8000-000000000004")
}

pub fn shared_tree_ids_unknown_ids_and_collisions_are_errors_test() {
  let state = fluid_ids.new(session(session_a))
  [-1, 0, 5]
  |> list.each(fn(id) {
    let assert Ok(local) = fluid_ids.session_space_id(id)
    let assert Ok(op) = fluid_ids.op_id(id)
    fluid_ids.decompress(state, local) |> expect.to_be_error
    fluid_ids.to_op(state, local) |> expect.to_be_error
    fluid_ids.from_op(state, op, session(session_a)) |> expect.to_be_error
    fluid_ids.from_op(state, op, session(session_b)) |> expect.to_be_error
  })
  let owner = session(session_b)
  let assert Ok(state) =
    fluid_ids.finalize(state, range(owner, 1, 2, 3, [#(1, 2)]))
  let colliding = session("20000000-0000-4000-8000-000000000004")
  fluid_ids.finalize(state, range(colliding, 1, 1, 3, [#(1, 1)]))
  |> expect.to_be_error
  let assert Ok(stable) = fluid_ids.stable_id(session_a)
  fluid_ids.recompress(state, stable) |> expect.to_equal(Ok(None))
}

pub fn shared_tree_ids_upstream_fixture_test() {
  fixtures.assert_case("id-ranges", id_fixture.run)
}

fn wire(bytes: BitArray) -> json.Json {
  json.string(bit_array.base64_encode(bytes, True))
}

fn numbers(values: List(Int)) -> BitArray {
  values
  |> list.map(fn(value) { <<int.to_float(value):float-little>> })
  |> bit_array.concat
}

fn uuid_a_bytes() -> BitArray {
  <<1:32-little, 0:32-little, 0:32-little, 4_194_304:32-little>>
}

pub fn shared_tree_ids_empty_serialization_layout_test() {
  let state = fluid_ids.new(session(session_a))
  let expected =
    wire(<<
      numbers([2, 1, 1, 0]):bits,
      uuid_a_bytes():bits,
      numbers([0, 1, 0]):bits,
    >>)
  let assert Ok(serialized) = fluid_ids.serialize(state, True)
  fixtures.first_difference(serialized, expected) |> expect.to_equal(Ok(Nil))
  let assert Ok(restored) =
    fluid_ids.deserialize(serialized, session(session_a))
  restored |> expect.to_equal(state)
  let assert Ok(summary) = fluid_ids.serialize(state, False)
  fixtures.first_difference(summary, wire(numbers([2, 0, 0, 0])))
  |> expect.to_equal(Ok(Nil))
}

pub fn shared_tree_ids_upstream_bytes_restore_pending_and_summary_test() {
  let assert Ok(fixture) = fixtures.load("id-ranges")
  let assert Ok(serialized) =
    json.parse(
      json.to_string(fixture.input),
      decode.at(
        ["operations", "restoration", "ongoing", "serialized"],
        decode.string,
      ),
    )
  let assert Ok(state) =
    fluid_ids.deserialize(json.string(serialized), session(session_a))
  let assert Ok(#(state, id)) = fluid_ids.generate(state)
  fluid_ids.session_space_id_to_int(id) |> expect.to_equal(-6)
  let assert Ok(stable) = fluid_ids.decompress(state, id)
  fluid_ids.stable_id_to_string(stable)
  |> expect.to_equal("10000000-0000-4000-8000-000000000006")
  let assert Ok(again) = fluid_ids.serialize(state, True)
  fluid_ids.deserialize(again, session(session_a)) |> expect.to_equal(Ok(state))
  fluid_ids.deserialize(again, session(session_b))
  |> expect.to_equal(Error(fluid_ids.SessionMismatch))
  let assert Ok(summary) = fluid_ids.serialize(state, False)
  fluid_ids.deserialize(summary, session(session_a))
  |> expect.to_equal(Error(fluid_ids.SessionMismatch))
}

pub fn shared_tree_ids_serialization_rejects_corrupt_layouts_test() {
  let uuid = uuid_a_bytes()
  [
    <<>>,
    numbers([2]),
    numbers([2, 3, 0, 0]),
    numbers([2, 0, -1, 0]),
    numbers([2, 0, 0, 1]),
    numbers([2, 1, 0, 0, 0, 1, 0]),
    <<numbers([2, 0, 1, 0]):bits, uuid:bits, 0>>,
    <<numbers([2, 0, 2, 0]):bits, uuid:bits, uuid:bits>>,
    <<numbers([2, 0, 1, 1]):bits, uuid:bits, numbers([1, 5, 2]):bits>>,
    <<numbers([2, 0, 1, 1]):bits, uuid:bits, numbers([0, 0, 0]):bits>>,
    <<numbers([2, 0, 1, 1]):bits, uuid:bits, numbers([0, 2, 3]):bits>>,
    <<numbers([2, 0, 1, 2]):bits, uuid:bits, numbers([0, 5, 2, 0, 3, 1]):bits>>,
    <<numbers([2, 1, 1, 0]):bits, uuid:bits, numbers([2, 4, 1, 1, 2]):bits>>,
    <<numbers([2, 1, 1, 0]):bits, uuid:bits, numbers([2, 1, 1, 1, 3]):bits>>,
    <<numbers([2, 1, 1, 0]):bits, uuid:bits, numbers([2, 1, 0]):bits>>,
    <<
      numbers([2, 0, 1, 0]):bits,
      0:32-little,
      0:32-little,
      0:32-little,
      67_108_864:32-little,
    >>,
    <<numbers([2, 0]):bits, 0.5:float-little, numbers([0]):bits>>,
    <<
      numbers([2, 0]):bits,
      9_007_199_254_740_992.0:float-little,
      numbers([0]):bits,
    >>,
    <<
      numbers([2, 0]):bits,
      0:32-little,
      2_146_435_072:32-little,
      numbers([0]):bits,
    >>,
    <<
      numbers([2, 0]):bits,
      0:32-little,
      3_220_176_896:32-little,
      numbers([0]):bits,
    >>,
  ]
  |> list.each(fn(bytes) {
    fluid_ids.deserialize(wire(bytes), session(session_b)) |> expect.to_be_error
  })
  [1, 3]
  |> list.each(fn(version) {
    fluid_ids.deserialize(wire(numbers([version, 0, 0, 0])), session(session_b))
    |> expect.to_equal(Error(fluid_ids.UnsupportedVersion(version)))
  })
  ["not base64", "AAAA=", "!!!!", ""]
  |> list.each(fn(data) {
    fluid_ids.deserialize(json.string(data), session(session_b))
    |> expect.to_be_error
  })
  fluid_ids.deserialize(json.int(2), session(session_b)) |> expect.to_be_error
  Nil
}

pub fn shared_tree_ids_safe_integer_exhaustion_is_atomic_test() {
  let owner = session(session_b)
  let state = fluid_ids.new(session(session_a))
  fluid_ids.finalize(state, range(owner, 1, 9_007_199_254_740_991, 1, []))
  |> expect.to_equal(Error(fluid_ids.IdSpaceExhausted))
  let gen = 9_007_199_254_740_990
  let bytes = <<
    numbers([2, 1, 1, 0]):bits,
    uuid_a_bytes():bits,
    numbers([gen, 1, 1, 1, gen]):bits,
  >>
  let assert Ok(full) = fluid_ids.deserialize(wire(bytes), session(session_a))
  fluid_ids.generate(full) |> expect.to_equal(Error(fluid_ids.IdSpaceExhausted))
  let assert Ok(last) = fluid_ids.session_space_id(-gen)
  let assert Ok(stable) = fluid_ids.decompress(full, last)
  fluid_ids.stable_id_to_string(stable)
  |> expect.to_equal("10000000-0000-4000-801f-fffffffffffe")
  fluid_ids.recompress(full, stable) |> expect.to_equal(Ok(Some(last)))
}

pub fn shared_tree_ids_restore_rejects_pending_uuid_overflow_test() {
  let owner = session("ffffffff-ffff-4fff-bfff-ffffffffffff")
  let bytes = <<
    numbers([2, 1, 1, 0]):bits,
    4_294_967_295:32-little,
    4_294_967_295:32-little,
    4_294_967_295:32-little,
    67_108_863:32-little,
    numbers([2, 1, 1, 1, 2]):bits,
  >>
  fluid_ids.deserialize(wire(bytes), owner)
  |> expect.to_equal(Error(fluid_ids.IdSpaceExhausted))
}

pub fn shared_tree_ids_large_cluster_offsets_stay_exact_test() {
  let half = 4_503_599_627_370_496
  let owner = session(session_b)
  let other = session("30000000-0000-4000-8000-000000000003")
  let state = fluid_ids.new(session(session_a))
  let assert Ok(state) =
    fluid_ids.finalize(state, range(owner, 1, half, 1, [#(1, half)]))
  let assert Ok(state) =
    fluid_ids.finalize(state, range(other, 1, 1, 1, [#(1, 1)]))
  let assert Ok(state) =
    fluid_ids.finalize(state, range(owner, half + 1, 3, 1, [#(half + 2, 2)]))
  let assert Ok(local_op) = fluid_ids.op_id(-half - 2)
  let assert Ok(final_id) = fluid_ids.from_op(state, local_op, owner)
  fluid_ids.session_space_id_to_int(final_id) |> expect.to_equal(half + 3)
  let assert Ok(stable) = fluid_ids.decompress(state, final_id)
  fluid_ids.stable_id_to_string(stable)
  |> expect.to_equal("20000000-0000-4000-8010-000000000003")
  fluid_ids.recompress(state, stable) |> expect.to_equal(Ok(Some(final_id)))
}

pub fn shared_tree_ids_range_json_is_validated_test() {
  let owner = session(session_a)
  let expected = range(owner, 1, 2, 3, [#(1, 2)])
  let assert Ok(encoded) = fluid_ids.creation_range_to_json(expected)
  fluid_ids.creation_range_from_json(encoded) |> expect.to_equal(Ok(expected))
  let empty = fluid_ids.CreationRange(owner, None)
  let assert Ok(encoded) = fluid_ids.creation_range_to_json(empty)
  fluid_ids.creation_range_from_json(encoded) |> expect.to_equal(Ok(empty))
  [
    "{\"sessionId\":\"" <> session_a <> "\",\"ids\":null}",
    "{\"sessionId\":\"not a UUID\"}",
    "{\"sessionId\":\""
      <> session_a
      <> "\",\"ids\":{\"firstGenCount\":1,\"count\":1.5,\"requestedClusterSize\":3,\"localIdRanges\":[]}}",
    "{\"sessionId\":\""
      <> session_a
      <> "\",\"ids\":{\"firstGenCount\":1,\"count\":9007199254740992,\"requestedClusterSize\":3,\"localIdRanges\":[]}}",
    "{\"sessionId\":\""
      <> session_a
      <> "\",\"ids\":{\"firstGenCount\":1,\"count\":2,\"requestedClusterSize\":3,\"localIdRanges\":[[1,2,3]]}}",
  ]
  |> list.each(fn(raw) {
    let assert Ok(value) = json.parse(raw, json_ot.decoder())
    fluid_ids.creation_range_from_json(json_ot.to_json(value))
    |> expect.to_be_error
  })
  let raw = "{\"sessionId\":\"" <> session_a <> "\",\"extra\":true}"
  let assert Ok(value) = json.parse(raw, json_ot.decoder())
  fluid_ids.creation_range_from_json(json_ot.to_json(value))
  |> expect.to_equal(Ok(empty))
}

pub fn shared_tree_ids_fixture_runner_uses_input_test() {
  let assert Ok(fixture) = fixtures.load("id-ranges")
  let assert Ok(VObject(fields)) =
    json.parse(json.to_string(fixture.input), json_ot.decoder())
  let assert Ok(four) = json.parse("4", json_ot.decoder())
  let changed =
    VObject(
      list.map(fields, fn(field) {
        case field.0 {
          "clusterSize" -> #("clusterSize", four)
          _ -> field
        }
      }),
    )
    |> json_ot.to_json
  let assert Ok(actual) = id_fixture.run(changed)
  fixtures.first_difference(actual, fixture.expected) |> expect.to_be_error
  id_fixture.run(json.object([])) |> expect.to_be_error
  Nil
}
