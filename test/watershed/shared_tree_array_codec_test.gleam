import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import startest/expect
import watershed/fluid_ids
import watershed/json_ot
import watershed/tree/array_codec_fixture
import watershed/tree/codec/sequence_field as sequence_codec
import watershed/tree/fixtures
import watershed/tree/sequence_field
import watershed/tree/types.{type AtomId, AtomId, CorruptData}
import watershed/wire

const revision_a = "10000000-0000-4000-8000-000000000001"

const revision_b = "20000000-0000-4000-8000-000000000002"

pub fn shared_tree_array_codecs_match_upstream_test() -> Nil {
  fixtures.assert_case("array-codecs", array_codec_fixture.run)
}

pub fn sequence_v3_codec_threads_child_state_and_all_mark_fields_test() -> Nil {
  let raw =
    "[{\"count\":2},{\"count\":1,\"effect\":{\"insert\":{\"id\":1}},\"cellId\":1},{\"count\":1,\"effect\":{\"remove\":{\"id\":2,\"idOverride\":[20,\""
    <> revision_b
    <> "\"]}}},{\"count\":1,\"effect\":{\"moveIn\":{\"id\":3,\"finalEndpoint\":[30,\""
    <> revision_b
    <> "\"]}},\"cellId\":3},{\"count\":1,\"effect\":{\"moveOut\":{\"id\":4,\"finalEndpoint\":40,\"idOverride\":41}}},{\"count\":1,\"effect\":{\"attachAndDetach\":{\"attach\":{\"insert\":{\"id\":5}},\"detach\":{\"remove\":{\"id\":6}}}},\"cellId\":5},{\"count\":1,\"effect\":{\"rename\":{\"idOverride\":7}},\"cellId\":6},{\"count\":1,\"changes\":\"child\"}]"
  let value = case json_ot.parse_json(raw) {
    Ok(value) -> value
    Error(error) -> panic as { string.inspect(error) }
  }
  let revision_a = case fluid_ids.stable_id(revision_a) {
    Ok(revision) -> revision
    Error(_) -> panic as { "invalid revision A" }
  }
  let revision_b = case fluid_ids.stable_id(revision_b) {
    Ok(revision) -> revision
    Error(_) -> panic as { "invalid revision B" }
  }
  let decode_atom = fn(value, location) {
    case value {
      json_ot.VNumber(json_ot.NInt(local_id)) ->
        Ok(AtomId(Some(revision_a), local_id))
      json_ot.VArray([
        json_ot.VNumber(json_ot.NInt(local_id)),
        json_ot.VString(encoded),
      ]) ->
        fluid_ids.stable_id(encoded)
        |> result.map(fn(revision) { AtomId(Some(revision), local_id) })
        |> result.map_error(fn(_) {
          CorruptData(location, "invalid test revision")
        })
      _ -> Error(CorruptData(location, "invalid test atom"))
    }
  }
  let decode_child = fn(value, state, location) {
    case value {
      json_ot.VString("child") -> Ok(#(AtomId(Some(revision_b), 99), state + 1))
      _ -> Error(CorruptData(location, "invalid test child"))
    }
  }
  let decoded = case
    sequence_codec.decode(value, 0, decode_atom, decode_child, "sequence")
  {
    Ok(value) -> value
    Error(error) -> panic as { string.inspect(error) }
  }
  let #(decoded, state) = decoded
  state |> expect.to_equal(1)
  let marks = sequence_field.to_marks(decoded)
  list.length(marks) |> expect.to_equal(8)
  let endpoint_mark = case marks |> list.drop(3) |> list.first {
    Ok(mark) -> mark
    Error(_) -> panic as { "missing endpoint mark" }
  }
  let endpoint_revision = case endpoint_mark {
    sequence_field.Mark(
      1,
      Some(AtomId(_, 3)),
      sequence_field.Attach(sequence_field.MoveIn(
        AtomId(_, 3),
        Some(AtomId(Some(endpoint_revision), 30)),
      )),
      None,
    ) -> endpoint_revision
    other -> panic as { string.inspect(other) }
  }
  endpoint_revision |> expect.to_equal(revision_b)
  let encode_atom = fn(id: AtomId, location) {
    case id.revision {
      Some(revision) if revision == revision_a ->
        Ok(json_ot.VNumber(json_ot.NInt(id.local_id)))
      Some(revision) ->
        Ok(
          json_ot.VArray([
            json_ot.VNumber(json_ot.NInt(id.local_id)),
            json_ot.VString(fluid_ids.stable_id_to_string(revision)),
          ]),
        )
      None -> Error(CorruptData(location, "missing test revision"))
    }
  }
  let encode_child = fn(id, state, location) {
    case id == AtomId(Some(revision_b), 99) {
      True -> Ok(#(json_ot.VString("child"), state + 1))
      False -> Error(CorruptData(location, "invalid test child"))
    }
  }
  let #(encoded, encoded_state) = case
    sequence_codec.encode(decoded, 0, encode_atom, encode_child, "sequence")
  {
    Ok(value) -> value
    Error(error) -> panic as { string.inspect(error) }
  }
  encoded_state |> expect.to_equal(1)
  wire.json_semantically_equal(json_ot.to_json(encoded), json_ot.to_json(value))
  |> expect.to_be_true
}

pub fn sequence_v3_codec_propagates_callback_and_validation_errors_test() -> Nil {
  let assert Ok(revision) = fluid_ids.stable_id(revision_a)
  let decode_atom = fn(value, location) {
    case value {
      json_ot.VNumber(json_ot.NInt(local_id)) ->
        Ok(AtomId(Some(revision), local_id))
      _ -> Error(CorruptData(location, "invalid test atom"))
    }
  }
  let decode_child = fn(_value, state, location) {
    Error(CorruptData(location, int.to_string(state)))
  }
  [
    "[{\"count\":0}]",
    "[{\"count\":1,\"extra\":true}]",
    "[{\"count\":1,\"effect\":{\"insert\":{\"id\":0},\"remove\":{\"id\":1}}}]",
  ]
  |> list.each(fn(raw) {
    let assert Ok(value) = json_ot.parse_json(raw)
    let assert Error(_) =
      sequence_codec.decode(value, 7, decode_atom, decode_child, "sequence")
    Nil
  })
  let assert Ok(value) = json_ot.parse_json("[{\"count\":1,\"changes\":false}]")
  let assert Error(CorruptData("sequence[0].changes", "7")) =
    sequence_codec.decode(value, 7, decode_atom, decode_child, "sequence")
  let assert Ok(value) =
    json_ot.parse_json(
      "[{\"count\":1,\"effect\":{\"insert\":{\"id\":0}},\"cellId\":0}]",
    )
  let assert Error(CorruptData(
    "sequence[0].effect.insert.revision",
    "an effect ID requires a revision",
  )) =
    sequence_codec.decode(
      value,
      7,
      fn(_value, _location) { Ok(AtomId(None, 0)) },
      decode_child,
      "sequence",
    )
  Nil
}

pub fn sequence_v3_codec_decodes_reserved_rename_representation_test() -> Nil {
  let assert Ok(revision) = fluid_ids.stable_id(revision_a)
  let assert Ok(value) =
    json_ot.parse_json(
      "[{\"count\":1,\"cellId\":0,\"effect\":{\"attachAndDetach\":{\"attach\":{\"moveIn\":{\"id\":-1}},\"detach\":{\"moveOut\":{\"id\":-1,\"idOverride\":1}}}}}]",
    )
  let decode_atom = fn(value, location) {
    case value {
      json_ot.VNumber(json_ot.NInt(local_id)) if local_id >= 0 ->
        Ok(AtomId(Some(revision), local_id))
      _ -> Error(CorruptData(location, "invalid local identifier"))
    }
  }
  let assert Ok(#(decoded, Nil)) =
    sequence_codec.decode(
      value,
      Nil,
      decode_atom,
      fn(_value, _state, location) {
        Error(CorruptData(location, "unexpected child"))
      },
      "sequence",
    )
  sequence_field.to_marks(decoded)
  |> expect.to_equal([
    sequence_field.Mark(
      1,
      Some(AtomId(Some(revision), 0)),
      sequence_field.Rename(AtomId(Some(revision), 1)),
      None,
    ),
  ])
}

fn assert_reserved_rename_subtype(raw: String) -> Nil {
  let assert Ok(revision) = fluid_ids.stable_id(revision_a)
  let decode_atom = fn(value, location) {
    case value {
      json_ot.VNumber(json_ot.NInt(local_id)) if local_id >= 0 ->
        Ok(AtomId(Some(revision), local_id))
      _ -> Error(CorruptData(location, "invalid local identifier"))
    }
  }
  let assert Ok(value) = json_ot.parse_json(raw)
  let assert Ok(#(decoded, Nil)) =
    sequence_codec.decode(
      value,
      Nil,
      decode_atom,
      fn(_value, _state, location) {
        Error(CorruptData(location, "unexpected child"))
      },
      "sequence",
    )
  sequence_field.to_marks(decoded)
  |> expect.to_equal([
    sequence_field.Mark(
      1,
      Some(AtomId(Some(revision), 0)),
      sequence_field.Rename(AtomId(Some(revision), 1)),
      None,
    ),
  ])
}

pub fn sequence_v3_codec_decodes_reserved_move_in_remove_test() -> Nil {
  assert_reserved_rename_subtype(
    "[{\"count\":1,\"cellId\":0,\"effect\":{\"attachAndDetach\":{\"attach\":{\"moveIn\":{\"id\":-1}},\"detach\":{\"remove\":{\"id\":2,\"idOverride\":1}}}}}]",
  )
}

pub fn sequence_v3_codec_decodes_reserved_insert_move_out_test() -> Nil {
  assert_reserved_rename_subtype(
    "[{\"count\":1,\"cellId\":0,\"effect\":{\"attachAndDetach\":{\"attach\":{\"insert\":{\"id\":-1}},\"detach\":{\"moveOut\":{\"id\":-1,\"idOverride\":1}}}}}]",
  )
}

pub fn sequence_v3_codec_accepts_open_attach_and_detach_object_test() -> Nil {
  let assert Ok(revision) = fluid_ids.stable_id(revision_a)
  let assert Ok(value) =
    json_ot.parse_json(
      "[{\"count\":1,\"cellId\":2,\"effect\":{\"attachAndDetach\":{\"attach\":{\"insert\":{\"id\":2}},\"detach\":{\"remove\":{\"id\":3}},\"extra\":true}}}]",
    )
  let decode_atom = fn(value, location) {
    case value {
      json_ot.VNumber(json_ot.NInt(local_id)) if local_id >= 0 ->
        Ok(AtomId(Some(revision), local_id))
      _ -> Error(CorruptData(location, "invalid local identifier"))
    }
  }
  let assert Ok(#(decoded, Nil)) =
    sequence_codec.decode(
      value,
      Nil,
      decode_atom,
      fn(_value, _state, location) {
        Error(CorruptData(location, "unexpected child"))
      },
      "sequence",
    )
  sequence_field.to_marks(decoded)
  |> expect.to_equal([
    sequence_field.Mark(
      1,
      Some(AtomId(Some(revision), 2)),
      sequence_field.AttachAndDetach(
        sequence_field.Insert(AtomId(Some(revision), 2)),
        sequence_field.Remove(AtomId(Some(revision), 3), None),
      ),
      None,
    ),
  ])
}

pub fn sequence_v3_codec_rejects_reserved_rename_near_misses_test() -> Nil {
  let assert Ok(revision) = fluid_ids.stable_id(revision_a)
  let decode_atom = fn(value, location) {
    case value {
      json_ot.VNumber(json_ot.NInt(local_id)) if local_id >= 0 ->
        Ok(AtomId(Some(revision), local_id))
      _ -> Error(CorruptData(location, "invalid local identifier"))
    }
  }
  [
    "[{\"count\":1,\"cellId\":0,\"effect\":{\"moveIn\":{\"id\":-1}}}]",
    "[{\"count\":1,\"cellId\":0,\"effect\":{\"attachAndDetach\":{\"attach\":{\"moveIn\":{\"id\":-1}},\"detach\":{\"moveOut\":{\"id\":-1}}}}}]",
    "[{\"count\":1,\"cellId\":0,\"effect\":{\"attachAndDetach\":{\"attach\":{\"moveIn\":{\"id\":-1,\"extra\":true}},\"detach\":{\"moveOut\":{\"id\":-1,\"idOverride\":1}}}}}]",
  ]
  |> list.each(fn(raw) {
    let assert Ok(value) = json_ot.parse_json(raw)
    let assert Error(_) =
      sequence_codec.decode(
        value,
        Nil,
        decode_atom,
        fn(_value, _state, location) {
          Error(CorruptData(location, "unexpected child"))
        },
        "sequence",
      )
    Nil
  })
}
