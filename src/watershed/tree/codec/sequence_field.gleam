//// Fluid 3.1.0 Sequence field V3 wire codec.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import watershed/json_ot.{type JsonValue, NInt, VArray, VNumber, VObject}
import watershed/tree/sequence_field
import watershed/tree/types.{type AtomId, type TreeError, CorruptData}

const max_safe_integer = 9_007_199_254_740_991

const min_safe_integer = -9_007_199_254_740_991

/// Decode one Sequence V3 changeset.
///
/// The callbacks keep atom and child encoding in the owning modular codec.
pub fn decode(
  value: JsonValue,
  state: state,
  decode_atom: fn(JsonValue, String) -> Result(AtomId, TreeError),
  decode_child: fn(JsonValue, state, String) ->
    Result(#(AtomId, state), TreeError),
  location: String,
) -> Result(#(sequence_field.Changeset, state), TreeError) {
  use values <- result.try(array(value, location))
  use #(marks, state) <- result.try(
    decode_marks(values, state, decode_atom, decode_child, location, 0, []),
  )
  use change <- result.try(
    sequence_field.from_marks(list.reverse(marks))
    |> result.map_error(fn(error) { at_location(error, location) }),
  )
  Ok(#(change, state))
}

fn decode_marks(
  values: List(JsonValue),
  state: state,
  decode_atom: fn(JsonValue, String) -> Result(AtomId, TreeError),
  decode_child: fn(JsonValue, state, String) ->
    Result(#(AtomId, state), TreeError),
  location: String,
  index: Int,
  marks: List(sequence_field.Mark),
) -> Result(#(List(sequence_field.Mark), state), TreeError) {
  case values {
    [] -> Ok(#(marks, state))
    [value, ..rest] -> {
      let mark_location = location <> "[" <> int.to_string(index) <> "]"
      use members <- result.try(object(value, mark_location))
      use _ <- result.try(only_keys(
        members,
        ["effect", "cellId", "changes", "count"],
        mark_location,
      ))
      use count_value <- result.try(required(
        members,
        "count",
        mark_location <> ".count",
      ))
      use count <- result.try(positive_integer(
        count_value,
        mark_location <> ".count",
      ))
      use cell_id <- result.try(case optional(members, "cellId") {
        None -> Ok(None)
        Some(value) ->
          decode_atom(value, mark_location <> ".cellId")
          |> result.map(Some)
      })
      use effect <- result.try(case optional(members, "effect") {
        None -> Ok(sequence_field.Noop)
        Some(value) ->
          decode_effect(value, decode_atom, mark_location <> ".effect")
      })
      use #(child, state) <- result.try(case optional(members, "changes") {
        None -> Ok(#(None, state))
        Some(value) ->
          decode_child(value, state, mark_location <> ".changes")
          |> result.map(fn(decoded) { #(Some(decoded.0), decoded.1) })
      })
      decode_marks(rest, state, decode_atom, decode_child, location, index + 1, [
        sequence_field.Mark(count, cell_id, effect, child),
        ..marks
      ])
    }
  }
}

fn decode_effect(
  value: JsonValue,
  decode_atom: fn(JsonValue, String) -> Result(AtomId, TreeError),
  location: String,
) -> Result(sequence_field.Effect, TreeError) {
  use members <- result.try(object(value, location))
  case members {
    [#("insert", value)] ->
      decode_attach(value, "insert", decode_atom, location <> ".insert")
      |> result.map(sequence_field.Attach)
    [#("moveIn", value)] ->
      decode_attach(value, "moveIn", decode_atom, location <> ".moveIn")
      |> result.map(sequence_field.Attach)
    [#("remove", value)] ->
      decode_detach(value, "remove", decode_atom, location <> ".remove")
      |> result.map(sequence_field.Detach)
    [#("moveOut", value)] ->
      decode_detach(value, "moveOut", decode_atom, location <> ".moveOut")
      |> result.map(sequence_field.Detach)
    [#("attachAndDetach", value)] ->
      decode_attach_and_detach(
        value,
        decode_atom,
        location <> ".attachAndDetach",
      )
    [#("rename", value)] -> {
      use members <- result.try(object(value, location <> ".rename"))
      use _ <- result.try(exact_keys(
        members,
        ["idOverride"],
        location <> ".rename",
      ))
      use value <- result.try(required(
        members,
        "idOverride",
        location <> ".rename.idOverride",
      ))
      decode_atom(value, location <> ".rename.idOverride")
      |> result.map(sequence_field.Rename)
    }
    _ -> Error(CorruptData(location, "mark effect must contain one operation"))
  }
}

fn decode_attach_and_detach(
  value: JsonValue,
  decode_atom: fn(JsonValue, String) -> Result(AtomId, TreeError),
  location: String,
) -> Result(sequence_field.Effect, TreeError) {
  use members <- result.try(object(value, location))
  use _ <- result.try(exact_keys(members, ["attach", "detach"], location))
  use attach <- result.try(required(members, "attach", location <> ".attach"))
  use detach <- result.try(required(members, "detach", location <> ".detach"))
  use attach <- result.try(decode_union_attach(
    attach,
    decode_atom,
    location <> ".attach",
  ))
  use detach <- result.try(decode_union_detach(
    detach,
    decode_atom,
    location <> ".detach",
  ))
  Ok(sequence_field.AttachAndDetach(attach, detach))
}

fn decode_union_attach(
  value: JsonValue,
  decode_atom: fn(JsonValue, String) -> Result(AtomId, TreeError),
  location: String,
) -> Result(sequence_field.Attach, TreeError) {
  use members <- result.try(object(value, location))
  case members {
    [#("insert", value)] ->
      decode_attach(value, "insert", decode_atom, location <> ".insert")
    [#("moveIn", value)] ->
      decode_attach(value, "moveIn", decode_atom, location <> ".moveIn")
    _ -> Error(CorruptData(location, "attach must contain one operation"))
  }
}

fn decode_union_detach(
  value: JsonValue,
  decode_atom: fn(JsonValue, String) -> Result(AtomId, TreeError),
  location: String,
) -> Result(sequence_field.Detach, TreeError) {
  use members <- result.try(object(value, location))
  case members {
    [#("remove", value)] ->
      decode_detach(value, "remove", decode_atom, location <> ".remove")
    [#("moveOut", value)] ->
      decode_detach(value, "moveOut", decode_atom, location <> ".moveOut")
    _ -> Error(CorruptData(location, "detach must contain one operation"))
  }
}

fn decode_attach(
  value: JsonValue,
  kind: String,
  decode_atom: fn(JsonValue, String) -> Result(AtomId, TreeError),
  location: String,
) -> Result(sequence_field.Attach, TreeError) {
  use members <- result.try(object(value, location))
  use _ <- result.try(only_keys(
    members,
    case kind {
      "insert" -> ["id", "revision"]
      _ -> ["id", "revision", "finalEndpoint"]
    },
    location,
  ))
  use id <- result.try(decode_effect_id(members, decode_atom, location))
  case kind {
    "insert" -> Ok(sequence_field.Insert(id))
    _ -> {
      use endpoint <- result.try(decode_optional_atom(
        optional(members, "finalEndpoint"),
        decode_atom,
        location <> ".finalEndpoint",
      ))
      Ok(sequence_field.MoveIn(id, endpoint))
    }
  }
}

fn decode_detach(
  value: JsonValue,
  kind: String,
  decode_atom: fn(JsonValue, String) -> Result(AtomId, TreeError),
  location: String,
) -> Result(sequence_field.Detach, TreeError) {
  use members <- result.try(object(value, location))
  use _ <- result.try(only_keys(
    members,
    case kind {
      "remove" -> ["id", "revision", "idOverride"]
      _ -> ["id", "revision", "finalEndpoint", "idOverride"]
    },
    location,
  ))
  use id <- result.try(decode_effect_id(members, decode_atom, location))
  use id_override <- result.try(decode_optional_atom(
    optional(members, "idOverride"),
    decode_atom,
    location <> ".idOverride",
  ))
  case kind {
    "remove" -> Ok(sequence_field.Remove(id, id_override))
    _ -> {
      use endpoint <- result.try(decode_optional_atom(
        optional(members, "finalEndpoint"),
        decode_atom,
        location <> ".finalEndpoint",
      ))
      Ok(sequence_field.MoveOut(id, endpoint, id_override))
    }
  }
}

fn decode_effect_id(
  members: List(#(String, JsonValue)),
  decode_atom: fn(JsonValue, String) -> Result(AtomId, TreeError),
  location: String,
) -> Result(AtomId, TreeError) {
  use id <- result.try(required(members, "id", location <> ".id"))
  use _ <- result.try(integer(id, location <> ".id"))
  let encoded = case optional(members, "revision") {
    None -> id
    Some(revision) -> VArray([id, revision])
  }
  use decoded <- result.try(decode_atom(encoded, location <> ".id"))
  case decoded.revision {
    Some(_) -> Ok(decoded)
    None ->
      Error(CorruptData(
        location <> ".revision",
        "an effect ID requires a revision",
      ))
  }
}

fn decode_optional_atom(
  value: Option(JsonValue),
  decode_atom: fn(JsonValue, String) -> Result(AtomId, TreeError),
  location: String,
) -> Result(Option(AtomId), TreeError) {
  case value {
    None -> Ok(None)
    Some(value) -> decode_atom(value, location) |> result.map(Some)
  }
}

/// Encode one checked Sequence V3 changeset.
pub fn encode(
  change: sequence_field.Changeset,
  state: state,
  encode_atom: fn(AtomId, String) -> Result(JsonValue, TreeError),
  encode_child: fn(AtomId, state, String) ->
    Result(#(JsonValue, state), TreeError),
  location: String,
) -> Result(#(JsonValue, state), TreeError) {
  use #(marks, state) <- result.try(
    encode_marks(
      sequence_field.to_marks(change),
      state,
      encode_atom,
      encode_child,
      location,
      0,
      [],
    ),
  )
  Ok(#(VArray(list.reverse(marks)), state))
}

fn encode_marks(
  marks: List(sequence_field.Mark),
  state: state,
  encode_atom: fn(AtomId, String) -> Result(JsonValue, TreeError),
  encode_child: fn(AtomId, state, String) ->
    Result(#(JsonValue, state), TreeError),
  location: String,
  index: Int,
  output: List(JsonValue),
) -> Result(#(List(JsonValue), state), TreeError) {
  case marks {
    [] -> Ok(#(output, state))
    [mark, ..rest] -> {
      let mark_location = location <> "[" <> int.to_string(index) <> "]"
      use effect <- result.try(encode_effect(
        mark.effect,
        encode_atom,
        mark_location <> ".effect",
      ))
      use cell_id <- result.try(encode_optional_atom(
        mark.cell_id,
        encode_atom,
        mark_location <> ".cellId",
      ))
      use #(child, state) <- result.try(case mark.child {
        None -> Ok(#(None, state))
        Some(child) ->
          encode_child(child, state, mark_location <> ".changes")
          |> result.map(fn(encoded) { #(Some(encoded.0), encoded.1) })
      })
      let members = [#("count", VNumber(NInt(mark.count)))]
      let members = case effect {
        None -> members
        Some(value) -> [#("effect", value), ..members]
      }
      let members = case cell_id {
        None -> members
        Some(value) -> list.append(members, [#("cellId", value)])
      }
      let members = case child {
        None -> members
        Some(value) -> list.append(members, [#("changes", value)])
      }
      encode_marks(rest, state, encode_atom, encode_child, location, index + 1, [
        VObject(members),
        ..output
      ])
    }
  }
}

fn encode_effect(
  effect: sequence_field.Effect,
  encode_atom: fn(AtomId, String) -> Result(JsonValue, TreeError),
  location: String,
) -> Result(Option(JsonValue), TreeError) {
  case effect {
    sequence_field.Noop -> Ok(None)
    sequence_field.Attach(attach) ->
      encode_attach(attach, encode_atom, location)
      |> result.map(fn(value) { Some(VObject([value])) })
    sequence_field.Detach(detach) ->
      encode_detach(detach, encode_atom, location)
      |> result.map(fn(value) { Some(VObject([value])) })
    sequence_field.AttachAndDetach(attach, detach) -> {
      use attach <- result.try(encode_attach(
        attach,
        encode_atom,
        location <> ".attachAndDetach.attach",
      ))
      use detach <- result.try(encode_detach(
        detach,
        encode_atom,
        location <> ".attachAndDetach.detach",
      ))
      Ok(
        Some(
          VObject([
            #(
              "attachAndDetach",
              VObject([
                #("attach", VObject([attach])),
                #("detach", VObject([detach])),
              ]),
            ),
          ]),
        ),
      )
    }
    sequence_field.Rename(id) -> {
      use id <- result.try(encode_atom(id, location <> ".rename.idOverride"))
      Ok(
        Some(
          VObject([
            #("rename", VObject([#("idOverride", id)])),
          ]),
        ),
      )
    }
  }
}

fn encode_attach(
  attach: sequence_field.Attach,
  encode_atom: fn(AtomId, String) -> Result(JsonValue, TreeError),
  location: String,
) -> Result(#(String, JsonValue), TreeError) {
  case attach {
    sequence_field.Insert(id) -> {
      use members <- result.try(encode_effect_id(
        id,
        encode_atom,
        location <> ".insert",
      ))
      Ok(#("insert", VObject(members)))
    }
    sequence_field.MoveIn(id, endpoint) -> {
      use members <- result.try(encode_effect_id(
        id,
        encode_atom,
        location <> ".moveIn",
      ))
      use endpoint <- result.try(encode_optional_atom(
        endpoint,
        encode_atom,
        location <> ".moveIn.finalEndpoint",
      ))
      let members = case endpoint {
        None -> members
        Some(value) -> list.append(members, [#("finalEndpoint", value)])
      }
      Ok(#("moveIn", VObject(members)))
    }
  }
}

fn encode_detach(
  detach: sequence_field.Detach,
  encode_atom: fn(AtomId, String) -> Result(JsonValue, TreeError),
  location: String,
) -> Result(#(String, JsonValue), TreeError) {
  case detach {
    sequence_field.Remove(id, id_override) -> {
      use members <- result.try(encode_effect_id(
        id,
        encode_atom,
        location <> ".remove",
      ))
      use id_override <- result.try(encode_optional_atom(
        id_override,
        encode_atom,
        location <> ".remove.idOverride",
      ))
      let members = case id_override {
        None -> members
        Some(value) -> list.append(members, [#("idOverride", value)])
      }
      Ok(#("remove", VObject(members)))
    }
    sequence_field.MoveOut(id, endpoint, id_override) -> {
      use members <- result.try(encode_effect_id(
        id,
        encode_atom,
        location <> ".moveOut",
      ))
      use endpoint <- result.try(encode_optional_atom(
        endpoint,
        encode_atom,
        location <> ".moveOut.finalEndpoint",
      ))
      use id_override <- result.try(encode_optional_atom(
        id_override,
        encode_atom,
        location <> ".moveOut.idOverride",
      ))
      let members = case endpoint {
        None -> members
        Some(value) -> list.append(members, [#("finalEndpoint", value)])
      }
      let members = case id_override {
        None -> members
        Some(value) -> list.append(members, [#("idOverride", value)])
      }
      Ok(#("moveOut", VObject(members)))
    }
  }
}

fn encode_effect_id(
  id: AtomId,
  encode_atom: fn(AtomId, String) -> Result(JsonValue, TreeError),
  location: String,
) -> Result(List(#(String, JsonValue)), TreeError) {
  use encoded <- result.try(encode_atom(id, location <> ".id"))
  case encoded {
    VNumber(NInt(local_id)) -> Ok([#("id", VNumber(NInt(local_id)))])
    VArray([VNumber(NInt(local_id)), revision]) ->
      Ok([
        #("id", VNumber(NInt(local_id))),
        #("revision", revision),
      ])
    _ ->
      Error(CorruptData(location <> ".id", "atom encoder returned invalid data"))
  }
}

fn encode_optional_atom(
  value: Option(AtomId),
  encode_atom: fn(AtomId, String) -> Result(JsonValue, TreeError),
  location: String,
) -> Result(Option(JsonValue), TreeError) {
  case value {
    None -> Ok(None)
    Some(value) -> encode_atom(value, location) |> result.map(Some)
  }
}

fn object(
  value: JsonValue,
  location: String,
) -> Result(List(#(String, JsonValue)), TreeError) {
  case value {
    VObject(members) -> Ok(members)
    _ -> Error(CorruptData(location, "expected an object"))
  }
}

fn array(
  value: JsonValue,
  location: String,
) -> Result(List(JsonValue), TreeError) {
  case value {
    VArray(values) -> Ok(values)
    _ -> Error(CorruptData(location, "expected an array"))
  }
}

fn integer(value: JsonValue, location: String) -> Result(Int, TreeError) {
  case value {
    VNumber(NInt(value))
      if value >= min_safe_integer && value <= max_safe_integer
    -> Ok(value)
    _ -> Error(CorruptData(location, "expected a safe integer"))
  }
}

fn positive_integer(
  value: JsonValue,
  location: String,
) -> Result(Int, TreeError) {
  use value <- result.try(integer(value, location))
  case value > 0 {
    True -> Ok(value)
    False -> Error(CorruptData(location, "expected a positive integer"))
  }
}

fn required(
  members: List(#(String, JsonValue)),
  name: String,
  location: String,
) -> Result(JsonValue, TreeError) {
  list.key_find(members, name)
  |> result.map_error(fn(_) {
    CorruptData(location, "required value is missing")
  })
}

fn optional(
  members: List(#(String, JsonValue)),
  name: String,
) -> Option(JsonValue) {
  case list.key_find(members, name) {
    Ok(value) -> Some(value)
    Error(_) -> None
  }
}

fn only_keys(
  members: List(#(String, JsonValue)),
  names: List(String),
  location: String,
) -> Result(Nil, TreeError) {
  use _ <- result.try(
    case has_duplicate_keys(list.map(members, fn(item) { item.0 })) {
      True ->
        Error(CorruptData(location, "object contains a duplicate property"))
      False -> Ok(Nil)
    },
  )
  list.try_each(members, fn(member) {
    case list.contains(names, member.0) {
      True -> Ok(Nil)
      False ->
        Error(CorruptData(
          location <> "." <> member.0,
          "property is not supported",
        ))
    }
  })
}

fn exact_keys(
  members: List(#(String, JsonValue)),
  names: List(String),
  location: String,
) -> Result(Nil, TreeError) {
  use _ <- result.try(only_keys(members, names, location))
  list.try_each(names, fn(name) {
    case list.key_find(members, name) {
      Ok(_) -> Ok(Nil)
      Error(_) ->
        Error(CorruptData(location <> "." <> name, "required value is missing"))
    }
  })
}

fn has_duplicate_keys(keys: List(String)) -> Bool {
  case keys {
    [] -> False
    [first, ..rest] -> list.contains(rest, first) || has_duplicate_keys(rest)
  }
}

fn at_location(error: TreeError, location: String) -> TreeError {
  case error {
    CorruptData(_, detail) -> CorruptData(location, detail)
    other -> other
  }
}
