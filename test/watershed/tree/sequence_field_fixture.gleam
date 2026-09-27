import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import watershed/canonical_json
import watershed/fluid_ids.{type StableId}
import watershed/json_ot.{type JsonValue, VNull, VObject}
import watershed/tree/change_fixture_codec as codec
import watershed/tree/forest
import watershed/tree/sequence_field
import watershed/tree/types

type Context {
  Context(revisions: List(#(Int, StableId)), children: List(Child))
}

type Child {
  Child(
    id: types.AtomId,
    source_revision: Option(Int),
    input_context: Option(List(Int)),
    intentions: List(Int),
    output_context: Option(List(Int)),
  )
}

pub fn run_editor(input: Json) -> Result(Json, String) {
  use value <- result.try(codec.parse(input))
  use _ <- result.try(codec.exact(value, ["scenarios"]))
  use scenarios <- result.try(codec.field(value, "scenarios", codec.items))
  use observations <- result.try(run_scenarios(scenarios, []))
  Ok(json.object([#("observations", array(list.reverse(observations)))]))
}

fn run_scenarios(
  scenarios: List(JsonValue),
  observations: List(Json),
) -> Result(List(Json), String) {
  case scenarios {
    [] -> Ok(observations)
    [scenario, ..rest] -> {
      use observation <- result.try(run_scenario(scenario))
      run_scenarios(rest, [observation, ..observations])
    }
  }
}

fn run_scenario(value: JsonValue) -> Result(Json, String) {
  use id <- result.try(codec.field(value, "id", codec.text))
  use operation <- result.try(codec.field(value, "operation", codec.text))
  use revisions <- result.try(
    codec.field(value, "revisions", fn(value) {
      codec.many(value, codec.integer)
    }),
  )
  use context <- result.try(context(revisions))
  use operands <- result.try(
    codec.field(value, "operands", fn(value) { Ok(value) }),
  )
  use #(result_json, _) <- result.try(case operation {
    "insert" -> run_insert(operands, context)
    "remove" -> run_remove(operands, context)
    "move" -> run_move(operands, context)
    "move-endpoints" -> run_move_endpoints(operands, context)
    "child-changes" -> run_children(operands, context)
    _ -> Error("unsupported sequence editor operation: " <> operation)
  })
  Ok(
    json.object([
      #("id", json.string(id)),
      #("executed", json.bool(True)),
      #("accepted", json.bool(True)),
      #("value", result_json),
      #("result", result_json),
    ]),
  )
}

fn run_insert(
  operands: JsonValue,
  context: Context,
) -> Result(#(Json, Context), String) {
  use index <- result.try(codec.field(operands, "index", codec.integer))
  use count <- result.try(codec.field(operands, "count", codec.integer))
  use first_id <- result.try(
    codec.field(operands, "firstId", decode_atom(_, context)),
  )
  use revision <- result.try(
    codec.field(operands, "revision", decode_revision(_, context)),
  )
  use change <- result.try(
    sequence_field.insert(index, count, first_id, Some(revision))
    |> native_error,
  )
  encode_result(change, context)
}

fn run_remove(
  operands: JsonValue,
  context: Context,
) -> Result(#(Json, Context), String) {
  use index <- result.try(codec.field(operands, "sourceIndex", codec.integer))
  use count <- result.try(codec.field(operands, "count", codec.integer))
  use local_id <- result.try(codec.field(operands, "detachId", codec.integer))
  use revision <- result.try(
    codec.field(operands, "revision", decode_revision(_, context)),
  )
  use change <- result.try(
    sequence_field.remove(index, count, types.AtomId(Some(revision), local_id))
    |> native_error,
  )
  encode_result(change, context)
}

fn run_move(
  operands: JsonValue,
  context: Context,
) -> Result(#(Json, Context), String) {
  use source <- result.try(codec.field(operands, "sourceIndex", codec.integer))
  use count <- result.try(codec.field(operands, "count", codec.integer))
  use destination <- result.try(codec.field(
    operands,
    "destinationIndex",
    codec.integer,
  ))
  use local_id <- result.try(codec.field(operands, "detachId", codec.integer))
  use attach_id <- result.try(
    codec.field(operands, "attachId", decode_atom(_, context)),
  )
  use revision <- result.try(
    codec.field(operands, "revision", decode_revision(_, context)),
  )
  use change <- result.try(
    sequence_field.move(
      source,
      count,
      destination,
      types.AtomId(Some(revision), local_id),
      attach_id,
    )
    |> native_error,
  )
  encode_result(change, context)
}

fn run_move_endpoints(
  operands: JsonValue,
  context: Context,
) -> Result(#(Json, Context), String) {
  use source <- result.try(codec.field(operands, "sourceIndex", codec.integer))
  use count <- result.try(codec.field(operands, "count", codec.integer))
  use destination <- result.try(codec.field(
    operands,
    "destinationIndex",
    codec.integer,
  ))
  use local_id <- result.try(codec.field(operands, "moveId", codec.integer))
  use attach_id <- result.try(
    codec.field(operands, "attachId", decode_atom(_, context)),
  )
  use revision <- result.try(
    codec.field(operands, "revision", decode_revision(_, context)),
  )
  let id = types.AtomId(Some(revision), local_id)
  use out <- result.try(
    sequence_field.move_out(source, count, id) |> native_error,
  )
  use into <- result.try(
    sequence_field.move_in(destination, count, id, attach_id)
    |> native_error,
  )
  use out_change <- result.try(encode_change(out, context))
  use in_change <- result.try(encode_change(into, context))
  use out_delta <- result.try(encode_delta_for(out, context))
  use in_delta <- result.try(encode_delta_for(into, context))
  Ok(#(
    json.object([
      #("change", json.object([#("out", out_change), #("in", in_change)])),
      #("delta", json.object([#("out", out_delta), #("in", in_delta)])),
    ]),
    context,
  ))
}

fn run_children(
  operands: JsonValue,
  context: Context,
) -> Result(#(Json, Context), String) {
  use encoded <- result.try(codec.field(operands, "children", codec.items))
  use #(changes, children) <- result.try(
    list.try_fold(encoded, #([], []), fn(output, entry) {
      use index <- result.try(codec.field(entry, "index", codec.integer))
      use child <- result.try(
        codec.field(entry, "node", decode_child(_, context)),
      )
      Ok(#([#(index, child.id), ..output.0], [child, ..output.1]))
    }),
  )
  let context = Context(..context, children: list.reverse(children))
  use change <- result.try(
    sequence_field.build_child_changes(list.reverse(changes))
    |> native_error,
  )
  encode_result(change, context)
}

fn encode_result(
  change: sequence_field.Changeset,
  context: Context,
) -> Result(#(Json, Context), String) {
  use encoded_change <- result.try(encode_change(change, context))
  use delta <- result.try(encode_delta_for(change, context))
  Ok(#(
    json.object([
      #("change", encoded_change),
      #("delta", delta),
    ]),
    context,
  ))
}

fn encode_delta_for(
  change: sequence_field.Changeset,
  context: Context,
) -> Result(Json, String) {
  use delta <- result.try(
    sequence_field.into_delta(change, fn(id) { child_delta(id, context) })
    |> native_error,
  )
  encode_delta(delta, context)
}

fn child_delta(
  id: types.AtomId,
  context: Context,
) -> Result(List(#(String, forest.FieldDelta)), types.TreeError) {
  let Context(children:, ..) = context
  case list.find(children, fn(child) { child.id == id }) {
    Error(Nil) ->
      Error(types.CorruptData("sequence fixture", "unknown child change"))
    Ok(child) ->
      case child.intentions {
        [] -> Ok([])
        intentions ->
          Ok([
            #(
              "testIntentions",
              forest.FieldDelta(
                list.map(intentions, fn(count) {
                  forest.Mark(count, None, None, [])
                }),
              ),
            ),
          ])
      }
  }
}

fn decode_atom(
  value: JsonValue,
  context: Context,
) -> Result(types.AtomId, String) {
  use _ <- result.try(codec.exact(value, ["revision", "localId"]))
  use revision <- result.try(
    codec.field(value, "revision", fn(value) {
      case value {
        VNull -> Ok(None)
        _ -> decode_revision(value, context) |> result.map(Some)
      }
    }),
  )
  use local_id <- result.try(codec.field(value, "localId", codec.integer))
  Ok(types.AtomId(revision, local_id))
}

fn decode_child(value: JsonValue, context: Context) -> Result(Child, String) {
  use local_id <- result.try(codec.field(value, "localId", codec.integer))
  use source_revision <- result.try(optional_field(
    value,
    "revision",
    fn(value) { codec.integer(value) |> result.map(Some) },
    None,
  ))
  use revision <- result.try(case source_revision {
    None -> Ok(None)
    Some(revision) ->
      decode_revision_number(revision, context) |> result.map(Some)
  })
  use test_change <- result.try(
    codec.field(value, "testChange", fn(value) { Ok(value) }),
  )
  use input_context <- result.try(optional_integer_list(
    test_change,
    "inputContext",
  ))
  use intentions <- result.try(
    codec.field(test_change, "intentions", fn(value) {
      codec.many(value, codec.integer)
    }),
  )
  use output_context <- result.try(optional_integer_list(
    test_change,
    "outputContext",
  ))
  Ok(Child(
    types.AtomId(revision, local_id),
    source_revision,
    input_context,
    intentions,
    output_context,
  ))
}

fn optional_integer_list(
  value: JsonValue,
  key: String,
) -> Result(Option(List(Int)), String) {
  optional_field(
    value,
    key,
    fn(value) { codec.many(value, codec.integer) |> result.map(Some) },
    None,
  )
}

fn optional_field(
  value: JsonValue,
  key: String,
  decode: fn(JsonValue) -> Result(a, String),
  default: a,
) -> Result(a, String) {
  case value {
    VObject(fields) ->
      case list.key_find(fields, key) {
        Ok(value) -> decode(value)
        Error(Nil) -> Ok(default)
      }
    _ -> Error("expected an object for " <> key)
  }
}

fn context(revisions: List(Int)) -> Result(Context, String) {
  use values <- result.try(
    list.try_map(revisions, fn(revision) {
      revision_for(revision) |> result.map(fn(stable) { #(revision, stable) })
    }),
  )
  Ok(Context(values, []))
}

fn revision_for(revision: Int) -> Result(StableId, String) {
  let suffix =
    revision
    |> int.absolute_value
    |> int.to_base_string(16)
    |> result.unwrap("0")
    |> string.pad_start(12, "0")
  fluid_ids.stable_id("10000000-0000-4000-8000-" <> suffix)
  |> result.map_error(string.inspect)
}

fn decode_revision(
  value: JsonValue,
  context: Context,
) -> Result(StableId, String) {
  use revision <- result.try(codec.integer(value))
  decode_revision_number(revision, context)
}

fn decode_revision_number(
  revision: Int,
  context: Context,
) -> Result(StableId, String) {
  let Context(revisions:, ..) = context
  list.key_find(revisions, revision)
  |> result.map_error(fn(_) {
    "atom uses an undeclared revision: " <> int.to_string(revision)
  })
}

fn source_revision(
  revision: StableId,
  context: Context,
) -> Result(Int, String) {
  let Context(revisions:, ..) = context
  list.find(revisions, fn(pair) { pair.1 == revision })
  |> result.map(fn(pair) { pair.0 })
  |> result.map_error(fn(_) { "unknown fixture revision" })
}

fn encode_change(
  change: sequence_field.Changeset,
  context: Context,
) -> Result(Json, String) {
  use marks <- result.try(
    list.try_map(sequence_field.to_marks(change), encode_mark(_, context)),
  )
  Ok(array(marks))
}

fn encode_mark(
  mark: sequence_field.Mark,
  context: Context,
) -> Result(Json, String) {
  let base = [#("count", json.int(mark.count))]
  use fields <- result.try(add_cell_and_child(base, mark, context))
  use fields <- result.try(case mark.effect {
    sequence_field.Noop -> Ok(fields)
    sequence_field.Attach(attach) ->
      encode_attach(attach, context)
      |> result.map(fn(effect) { list.append(effect, fields) })
    sequence_field.Detach(detach) ->
      encode_detach(detach, context)
      |> result.map(fn(effect) { list.append(effect, fields) })
    sequence_field.AttachAndDetach(attach, detach) -> {
      use attach <- result.try(encode_effect_attach(attach, context))
      use detach <- result.try(encode_effect_detach(detach, context))
      Ok(list.append(
        [
          #("type", json.string("AttachAndDetach")),
          #("attach", attach),
          #("detach", detach),
        ],
        fields,
      ))
    }
    sequence_field.Rename(id_override) -> {
      use id_override <- result.try(encode_atom(id_override, context))
      Ok(list.append(
        [
          #("type", json.string("Rename")),
          #("idOverride", id_override),
        ],
        fields,
      ))
    }
  })
  Ok(json.object(fields))
}

fn add_cell_and_child(
  fields: List(#(String, Json)),
  mark: sequence_field.Mark,
  context: Context,
) -> Result(List(#(String, Json)), String) {
  use fields <- result.try(case mark.cell_id {
    None -> Ok(fields)
    Some(id) ->
      encode_atom(id, context)
      |> result.map(fn(id) { list.append(fields, [#("cellId", id)]) })
  })
  case mark.child {
    None -> Ok(fields)
    Some(id) -> {
      use child <- result.try(encode_child(id, context))
      Ok(list.append(fields, [#("changes", child)]))
    }
  }
}

fn encode_attach(
  attach: sequence_field.Attach,
  context: Context,
) -> Result(List(#(String, Json)), String) {
  case attach {
    sequence_field.Insert(id) -> encode_id_effect("Insert", id, context)
    sequence_field.MoveIn(id, endpoint) -> {
      use fields <- result.try(encode_id_effect("MoveIn", id, context))
      add_optional_atom(fields, "finalEndpoint", endpoint, context)
    }
  }
}

fn encode_detach(
  detach: sequence_field.Detach,
  context: Context,
) -> Result(List(#(String, Json)), String) {
  case detach {
    sequence_field.Remove(id, id_override) -> {
      use fields <- result.try(encode_id_effect("Remove", id, context))
      add_optional_atom(fields, "idOverride", id_override, context)
    }
    sequence_field.MoveOut(id, endpoint, id_override) -> {
      use fields <- result.try(encode_id_effect("MoveOut", id, context))
      use fields <- result.try(add_optional_atom(
        fields,
        "finalEndpoint",
        endpoint,
        context,
      ))
      add_optional_atom(fields, "idOverride", id_override, context)
    }
  }
}

fn encode_effect_attach(
  attach: sequence_field.Attach,
  context: Context,
) -> Result(Json, String) {
  encode_attach(attach, context) |> result.map(json.object)
}

fn encode_effect_detach(
  detach: sequence_field.Detach,
  context: Context,
) -> Result(Json, String) {
  encode_detach(detach, context) |> result.map(json.object)
}

fn encode_id_effect(
  name: String,
  id: types.AtomId,
  context: Context,
) -> Result(List(#(String, Json)), String) {
  use revision <- result.try(optional_revision_json(id.revision, context))
  let fields = [
    #("type", json.string(name)),
    #("id", json.int(id.local_id)),
  ]
  Ok(case revision {
    None -> fields
    Some(revision) -> list.append(fields, [#("revision", revision)])
  })
}

fn add_optional_atom(
  fields: List(#(String, Json)),
  name: String,
  id: Option(types.AtomId),
  context: Context,
) -> Result(List(#(String, Json)), String) {
  case id {
    None -> Ok(fields)
    Some(id) ->
      encode_atom(id, context)
      |> result.map(fn(id) { list.append(fields, [#(name, id)]) })
  }
}

fn encode_atom(id: types.AtomId, context: Context) -> Result(Json, String) {
  use revision <- result.try(optional_revision_json(id.revision, context))
  Ok(
    json.object([
      #("revision", case revision {
        None -> json.null()
        Some(revision) -> revision
      }),
      #("localId", json.int(id.local_id)),
    ]),
  )
}

fn optional_revision_json(
  revision: Option(StableId),
  context: Context,
) -> Result(Option(Json), String) {
  case revision {
    None -> Ok(None)
    Some(revision) ->
      source_revision(revision, context)
      |> result.map(json.int)
      |> result.map(Some)
  }
}

fn encode_child(id: types.AtomId, context: Context) -> Result(Json, String) {
  let Context(children:, ..) = context
  use child <- result.try(
    list.find(children, fn(child) { child.id == id })
    |> result.map_error(fn(_) { "unknown child change" }),
  )
  let fields = [
    #("localId", json.int(child.id.local_id)),
    #(
      "testChange",
      json.object(
        option_json_field("inputContext", child.input_context)
        |> list.append([
          #("intentions", int_array(child.intentions)),
        ])
        |> list.append(option_json_field("outputContext", child.output_context)),
      ),
    ),
  ]
  Ok(
    json.object(case child.source_revision {
      None -> fields
      Some(revision) -> [#("revision", json.int(revision)), ..fields]
    }),
  )
}

fn option_json_field(
  name: String,
  value: Option(List(Int)),
) -> List(#(String, Json)) {
  case value {
    None -> []
    Some(values) -> [#(name, int_array(values))]
  }
}

fn int_array(values: List(Int)) -> Json {
  json.array(values, json.int)
}

fn encode_delta(
  delta: sequence_field.DeltaResult,
  context: Context,
) -> Result(Json, String) {
  use local <- result.try(case delta.local {
    None -> Ok([])
    Some(local) ->
      encode_field_delta(local, context)
      |> result.map(fn(local) { [#("local", local)] })
  })
  use global <- result.try(
    list.try_map(delta.global, fn(change) {
      use id <- result.try(encode_delta_id(change.id, context))
      use fields <- result.try(encode_fields(change.fields, context))
      Ok(json.object([#("id", id), #("fields", fields)]))
    }),
  )
  use rename <- result.try(
    list.try_map(delta.rename, fn(rename) {
      use old_id <- result.try(encode_delta_id(rename.old_id, context))
      use new_id <- result.try(encode_delta_id(rename.new_id, context))
      Ok(
        json.object([
          #("count", json.int(rename.count)),
          #("oldId", old_id),
          #("newId", new_id),
        ]),
      )
    }),
  )
  let fields = case global {
    [] -> local
    global -> list.append(local, [#("global", array(global))])
  }
  let fields = case rename {
    [] -> fields
    rename -> list.append(fields, [#("rename", array(rename))])
  }
  Ok(json.object(fields))
}

fn encode_field_delta(
  delta: forest.FieldDelta,
  context: Context,
) -> Result(Json, String) {
  use marks <- result.try(
    list.try_map(delta.marks, fn(mark) {
      use attach <- result.try(optional_delta_id(mark.attach, context))
      use detach <- result.try(optional_delta_id(mark.detach, context))
      use fields <- result.try(encode_fields(mark.fields, context))
      let encoded = [#("count", json.int(mark.count))]
      let encoded = case attach {
        None -> encoded
        Some(attach) -> list.append(encoded, [#("attach", attach)])
      }
      let encoded = case detach {
        None -> encoded
        Some(detach) -> list.append(encoded, [#("detach", detach)])
      }
      let encoded = case mark.fields {
        [] -> encoded
        _ -> list.append(encoded, [#("fields", fields)])
      }
      Ok(json.object(encoded))
    }),
  )
  Ok(json.object([#("marks", array(marks))]))
}

fn encode_fields(
  fields: List(#(String, forest.FieldDelta)),
  context: Context,
) -> Result(Json, String) {
  use fields <- result.try(
    fields
    |> list.sort(fn(left, right) { canonical_json.compare(left.0, right.0) })
    |> list.try_map(fn(field) {
      use delta <- result.try(encode_field_delta(field.1, context))
      Ok(array([json.string(field.0), delta]))
    }),
  )
  Ok(array(fields))
}

fn optional_delta_id(
  id: Option(types.AtomId),
  context: Context,
) -> Result(Option(Json), String) {
  case id {
    None -> Ok(None)
    Some(id) -> encode_delta_id(id, context) |> result.map(Some)
  }
}

fn encode_delta_id(id: types.AtomId, context: Context) -> Result(Json, String) {
  use major <- result.try(case id.revision {
    None -> Ok(json.null())
    Some(revision) -> source_revision(revision, context) |> result.map(json.int)
  })
  Ok(
    json.object([
      #("minor", json.int(id.local_id)),
      #("major", major),
    ]),
  )
}

fn native_error(value: Result(a, types.TreeError)) -> Result(a, String) {
  result.map_error(value, string.inspect)
}

fn array(values: List(Json)) -> Json {
  json.array(values, fn(value) { value })
}
