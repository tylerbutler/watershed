import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
import gleam/string
import watershed/canonical_json
import watershed/fluid_ids.{type StableId}
import watershed/json_ot.{type JsonValue, VNull, VObject}
import watershed/tree/change_fixture_codec as codec
import watershed/tree/forest
import watershed/tree/sequence_field
import watershed/tree/sequence_field/compose
import watershed/tree/sequence_field/invert
import watershed/tree/sequence_field/moves
import watershed/tree/sequence_field/rebase
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

type ComposeState {
  ComposeState(context: Context, callbacks: List(Json))
}

type InvertState {
  InvertState(context: Context, aliases: sequence_field.AliasContext)
}

type RebaseState {
  RebaseState(
    authored: Context,
    base: Context,
    output: Context,
    callbacks: List(Json),
  )
}

pub fn run_editor(input: Json) -> Result(Json, String) {
  use value <- result.try(codec.parse(input))
  use _ <- result.try(codec.exact(value, ["scenarios"]))
  use scenarios <- result.try(codec.field(value, "scenarios", codec.items))
  use observations <- result.try(run_scenarios(scenarios, []))
  Ok(json.object([#("observations", array(list.reverse(observations)))]))
}

pub fn run_compose_invert(input: Json) -> Result(Json, String) {
  use value <- result.try(codec.parse(input))
  use _ <- result.try(codec.exact(value, ["scenarios"]))
  use scenarios <- result.try(codec.field(value, "scenarios", codec.items))
  use observations <- result.try(run_algebra_scenarios(scenarios, []))
  Ok(json.object([#("observations", array(list.reverse(observations)))]))
}

pub fn run_rebase(input: Json) -> Result(Json, String) {
  use value <- result.try(codec.parse(input))
  use _ <- result.try(codec.exact(value, ["scenarios"]))
  use scenarios <- result.try(codec.field(value, "scenarios", codec.items))
  use observations <- result.try(run_rebase_scenarios(scenarios, []))
  Ok(json.object([#("observations", array(list.reverse(observations)))]))
}

fn run_rebase_scenarios(
  scenarios: List(JsonValue),
  observations: List(Json),
) -> Result(List(Json), String) {
  case scenarios {
    [] -> Ok(observations)
    [scenario, ..rest] -> {
      use observation <- result.try(run_rebase_scenario(scenario))
      run_rebase_scenarios(rest, [observation, ..observations])
    }
  }
}

fn run_rebase_scenario(value: JsonValue) -> Result(Json, String) {
  use id <- result.try(codec.field(value, "id", codec.text))
  use operation <- result.try(codec.field(value, "operation", codec.text))
  use _ <- result.try(case operation {
    "rebase" -> Ok(Nil)
    _ -> Error("unsupported sequence rebase operation: " <> operation)
  })
  use revisions <- result.try(
    codec.field(value, "revisions", fn(value) {
      codec.many(value, codec.integer)
    }),
  )
  use operands <- result.try(
    codec.field(value, "operands", fn(value) { Ok(value) }),
  )
  use context <- result.try(
    context(list.unique(list.append(revisions, collect_revisions(operands)))),
  )
  use authored_value <- result.try(
    codec.field(operands, "change", fn(value) { Ok(value) }),
  )
  use base_value <- result.try(
    codec.field(operands, "base", fn(value) { Ok(value) }),
  )
  use #(authored, authored_revision, authored_context) <- result.try(
    decode_tagged(authored_value, context),
  )
  use #(base, base_revision, base_context) <- result.try(decode_tagged(
    base_value,
    context,
  ))
  let state = RebaseState(authored_context, base_context, context, [])
  use #(rebased, state, move_context) <- result.try(
    rebase.rebase(
      authored,
      base,
      state,
      rebase_children,
      rebase_algebra(context, authored_revision, base_revision),
      fixture_field(),
      moves.new(),
    )
    |> native_error,
  )
  let #(invalidated, move_context) =
    moves.take_invalidated_for(move_context, fixture_field())
  use #(rebased, state) <- result.try(case invalidated {
    False -> Ok(#(rebased, state))
    True ->
      rebase.rebase(
        authored,
        base,
        state,
        rebase_children,
        rebase_algebra(context, authored_revision, base_revision),
        fixture_field(),
        move_context,
      )
      |> native_error
      |> result.map(fn(value) { #(value.0, value.1) })
  })
  let RebaseState(output:, callbacks:, ..) = state
  use value <- result.try(encode_change(rebased, output))
  let result_json =
    json.object([
      #("value", value),
      #("callbacks", array(list.reverse(callbacks))),
    ])
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

fn run_algebra_scenarios(
  scenarios: List(JsonValue),
  observations: List(Json),
) -> Result(List(Json), String) {
  case scenarios {
    [] -> Ok(observations)
    [scenario, ..rest] -> {
      use observation <- result.try(run_algebra_scenario(scenario))
      run_algebra_scenarios(rest, [observation, ..observations])
    }
  }
}

fn run_algebra_scenario(value: JsonValue) -> Result(Json, String) {
  use id <- result.try(codec.field(value, "id", codec.text))
  use operation <- result.try(codec.field(value, "operation", codec.text))
  use revisions <- result.try(
    codec.field(value, "revisions", fn(value) {
      codec.many(value, codec.integer)
    }),
  )
  use operands <- result.try(
    codec.field(value, "operands", fn(value) { Ok(value) }),
  )
  use context <- result.try(
    context(list.unique(list.append(revisions, collect_revisions(operands)))),
  )
  use result_json <- result.try(case operation {
    "codec" -> run_codec(operands, context)
    "compose" -> run_compose(operands, context)
    "compose-invert" -> run_compose_and_invert(operands, context)
    "invert" -> run_invert(operands, context)
    "replace-revisions" -> run_replace_revisions(operands, context)
    "prune" -> run_prune(operands, context)
    "removed-roots" -> run_removed_roots(operands, context)
    _ -> Error("unsupported sequence algebra operation: " <> operation)
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

fn collect_revisions(value: JsonValue) -> List(Int) {
  case value {
    VObject(fields) ->
      list.flat_map(fields, fn(entry) {
        case entry.0 {
          "revision" | "major" | "replacement" | "inverseRevision" ->
            case codec.integer(entry.1) {
              Ok(value) -> [value]
              Error(_) -> collect_revisions(entry.1)
            }
          "obsolete" ->
            case codec.items(entry.1) {
              Ok(values) ->
                list.filter_map(values, fn(value) {
                  codec.integer(value) |> result.map_error(fn(_) { Nil })
                })
              Error(_) -> []
            }
          _ -> collect_revisions(entry.1)
        }
      })
    json_ot.VArray(values) -> list.flat_map(values, collect_revisions)
    _ -> []
  }
}

fn run_codec(operands: JsonValue, context: Context) -> Result(Json, String) {
  use #(change, context) <- result.try(
    codec.field(operands, "change", decode_change(_, context)),
  )
  use changes <- result.try(encode_change(change, context))
  use delta <- result.try(encode_delta_for(change, context))
  Ok(
    json.object([
      #("changes", changes),
      #("delta", delta),
    ]),
  )
}

fn run_compose(operands: JsonValue, context: Context) -> Result(Json, String) {
  use encoded <- result.try(codec.field(operands, "changes", codec.items))
  use #(tagged, context) <- result.try(decode_changes(encoded, context, []))
  let changes = list.map(tagged, fn(pair) { pair.0 })
  let chronology = list.map(tagged, fn(pair) { pair.1 })
  use operands_json <- result.try(
    list.try_map(changes, encode_change(_, context)),
  )
  let state = ComposeState(context, [])
  use empty <- result.try(sequence_field.from_marks([]) |> native_error)
  use #(composed, state, _) <- result.try(
    compose_changes(
      [empty, ..changes],
      state,
      moves.new(),
      algebra_with_revisions(context, chronology),
    )
    |> native_error,
  )
  let ComposeState(context, callbacks) = state
  use composed <- result.try(encode_change(composed, context))
  Ok(
    json.object([
      #("operands", array(operands_json)),
      #("callbacks", array(list.reverse(callbacks))),
      #("composed", composed),
    ]),
  )
}

fn run_compose_and_invert(
  operands: JsonValue,
  context: Context,
) -> Result(Json, String) {
  use tagged <- result.try(
    codec.field(operands, "change", decode_tagged(_, context)),
  )
  let #(change, original_revision, context) = tagged
  use inverse_revision <- result.try(
    codec.field(operands, "inverseRevision", decode_revision(_, context)),
  )
  use is_rollback <- result.try(codec.field(
    operands,
    "isRollback",
    codec.boolean,
  ))
  use aliases <- result.try(
    sequence_field.new_alias_context([
      #(Some(original_revision), max_local_id(change)),
    ])
    |> native_error,
  )
  let invert_state = InvertState(context, aliases)
  use #(inverted, invert_state, move_context) <- result.try(
    invert.invert(
      change,
      is_rollback,
      invert_state,
      fixture_alias,
      Some(inverse_revision),
      fixture_field(),
      moves.new(),
    )
    |> native_error,
  )
  let InvertState(context, _) = invert_state
  let compose_state = ComposeState(context, [])
  use #(composed, compose_state, _) <- result.try(
    compose.compose(
      change,
      inverted,
      compose_state,
      compose_children,
      algebra_with_revisions(context, [original_revision, inverse_revision]),
      fixture_field(),
      move_context,
    )
    |> native_error,
  )
  let ComposeState(context, _) = compose_state
  use change_json <- result.try(encode_change(change, context))
  use inverted_json <- result.try(encode_change(inverted, context))
  use composed_json <- result.try(encode_change(composed, context))
  Ok(
    json.object([
      #("operands", array([change_json, inverted_json])),
      #("composed", composed_json),
      #("inverted", inverted_json),
    ]),
  )
}

fn run_invert(operands: JsonValue, context: Context) -> Result(Json, String) {
  use tagged <- result.try(
    codec.field(operands, "change", decode_tagged(_, context)),
  )
  let #(change, original_revision, context) = tagged
  use inverse_revision <- result.try(
    codec.field(operands, "inverseRevision", decode_revision(_, context)),
  )
  use is_rollback <- result.try(codec.field(
    operands,
    "isRollback",
    codec.boolean,
  ))
  use aliases <- result.try(
    sequence_field.new_alias_context([
      #(Some(original_revision), max_local_id(change)),
    ])
    |> native_error,
  )
  let initial_state = InvertState(context, aliases)
  use #(inverted, state, move_context) <- result.try(
    invert.invert(
      change,
      is_rollback,
      initial_state,
      fixture_alias,
      Some(inverse_revision),
      fixture_field(),
      moves.new(),
    )
    |> native_error,
  )
  let #(invalidated, move_context) = moves.take_invalidated(move_context)
  use #(inverted, state) <- result.try(case invalidated {
    [] -> Ok(#(inverted, state))
    _ ->
      invert.invert(
        change,
        is_rollback,
        state,
        fixture_alias,
        Some(inverse_revision),
        fixture_field(),
        move_context,
      )
      |> native_error
      |> result.map(fn(result) { #(result.0, result.1) })
  })
  let InvertState(context, _) = state
  encode_change(inverted, context)
}

fn run_replace_revisions(
  operands: JsonValue,
  context: Context,
) -> Result(Json, String) {
  use #(change, context) <- result.try(
    codec.field(operands, "change", decode_change(_, context)),
  )
  use obsolete <- result.try(
    codec.field(operands, "obsolete", fn(value) {
      codec.many(value, decode_revision(_, context))
    }),
  )
  use replacement <- result.try(
    codec.field(operands, "replacement", decode_revision(_, context)),
  )
  use changed <- result.try(
    sequence_field.replace_revisions(change, fn(id, _) {
      case id.revision {
        Some(revision) ->
          case list.contains(obsolete, revision) {
            True -> Ok(types.AtomId(Some(replacement), id.local_id))
            False -> Ok(id)
          }
        _ -> Ok(id)
      }
    })
    |> native_error,
  )
  use input <- result.try(encode_change(change, context))
  use obsolete <- result.try(
    list.try_map(obsolete, fn(revision) {
      source_revision(revision, context) |> result.map(json.int)
    }),
  )
  use replacement <- result.try(source_revision(replacement, context))
  use changed <- result.try(encode_change(changed, context))
  Ok(
    json.object([
      #("input", input),
      #("obsolete", array(obsolete)),
      #("replacement", json.int(replacement)),
      #("result", changed),
    ]),
  )
}

fn run_prune(operands: JsonValue, context: Context) -> Result(Json, String) {
  use #(change, context) <- result.try(
    codec.field(operands, "change", decode_change(_, context)),
  )
  use change <- result.try(
    sequence_field.prune(change, fn(_) { Ok(None) }) |> native_error,
  )
  encode_change(change, context)
}

fn run_removed_roots(
  operands: JsonValue,
  context: Context,
) -> Result(Json, String) {
  use #(change, context) <- result.try(
    codec.field(operands, "change", decode_change(_, context)),
  )
  use child_roots <- result.try(
    codec.field(operands, "childRemovedRoots", fn(value) {
      codec.many(value, decode_delta_atom(_, context))
    }),
  )
  use roots <- result.try(
    sequence_field.relevant_removed_roots(change, fn(_) { Ok(child_roots) })
    |> native_error,
  )
  use roots <- result.try(list.try_map(roots, encode_delta_id(_, context)))
  Ok(array(roots))
}

fn decode_changes(
  encoded: List(JsonValue),
  context: Context,
  output: List(#(sequence_field.Changeset, StableId)),
) -> Result(#(List(#(sequence_field.Changeset, StableId)), Context), String) {
  case encoded {
    [] -> Ok(#(list.reverse(output), context))
    [value, ..rest] -> {
      use #(change, revision, context) <- result.try(decode_tagged(
        value,
        context,
      ))
      decode_changes(rest, context, [#(change, revision), ..output])
    }
  }
}

fn decode_tagged(
  value: JsonValue,
  context: Context,
) -> Result(#(sequence_field.Changeset, StableId, Context), String) {
  use change <- result.try(
    codec.field(value, "change", fn(value) { Ok(value) }),
  )
  use revision <- result.try(
    codec.field(value, "revision", decode_revision(_, context)),
  )
  use #(change, context) <- result.try(decode_change(change, context))
  Ok(#(change, revision, context))
}

fn decode_change(
  value: JsonValue,
  context: Context,
) -> Result(#(sequence_field.Changeset, Context), String) {
  use marks <- result.try(codec.items(value))
  use #(marks, context) <- result.try(decode_marks(marks, context, []))
  use change <- result.try(
    sequence_field.from_marks(list.reverse(marks)) |> native_error,
  )
  Ok(#(change, context))
}

fn decode_marks(
  values: List(JsonValue),
  context: Context,
  output: List(sequence_field.Mark),
) -> Result(#(List(sequence_field.Mark), Context), String) {
  case values {
    [] -> Ok(#(output, context))
    [value, ..rest] -> {
      use #(mark, context) <- result.try(decode_mark(value, context))
      decode_marks(rest, context, [mark, ..output])
    }
  }
}

fn decode_mark(
  value: JsonValue,
  context: Context,
) -> Result(#(sequence_field.Mark, Context), String) {
  use count <- result.try(codec.field(value, "count", codec.integer))
  use cell_id <- result.try(optional_field(
    value,
    "cellId",
    fn(value) { decode_atom(value, context) |> result.map(Some) },
    None,
  ))
  use #(child, context) <- result.try(optional_child(value, context))
  use effect <- result.try(optional_field(
    value,
    "type",
    decode_effect(_, value, context),
    sequence_field.Noop,
  ))
  Ok(#(sequence_field.Mark(count, cell_id, effect, child), context))
}

fn decode_effect(
  type_value: JsonValue,
  value: JsonValue,
  context: Context,
) -> Result(sequence_field.Effect, String) {
  use name <- result.try(codec.text(type_value))
  case name {
    "Insert" ->
      decode_effect_atom(value, context)
      |> result.map(sequence_field.Insert)
      |> result.map(sequence_field.Attach)
    "MoveIn" ->
      decode_move_in(value, context) |> result.map(sequence_field.Attach)
    "Remove" ->
      decode_remove(value, context) |> result.map(sequence_field.Detach)
    "MoveOut" ->
      decode_move_out(value, context) |> result.map(sequence_field.Detach)
    "AttachAndDetach" -> {
      use attach <- result.try(
        codec.field(value, "attach", decode_attach(_, context)),
      )
      use detach <- result.try(
        codec.field(value, "detach", decode_detach(_, context)),
      )
      Ok(sequence_field.AttachAndDetach(attach, detach))
    }
    "Rename" ->
      codec.field(value, "idOverride", decode_atom(_, context))
      |> result.map(sequence_field.Rename)
    _ -> Error("unsupported sequence mark type: " <> name)
  }
}

fn decode_attach(
  value: JsonValue,
  context: Context,
) -> Result(sequence_field.Attach, String) {
  use name <- result.try(codec.field(value, "type", codec.text))
  case name {
    "Insert" ->
      decode_effect_atom(value, context) |> result.map(sequence_field.Insert)
    "MoveIn" -> decode_move_in(value, context)
    _ -> Error("unsupported sequence attach type: " <> name)
  }
}

fn decode_detach(
  value: JsonValue,
  context: Context,
) -> Result(sequence_field.Detach, String) {
  use name <- result.try(codec.field(value, "type", codec.text))
  case name {
    "Remove" -> decode_remove(value, context)
    "MoveOut" -> decode_move_out(value, context)
    _ -> Error("unsupported sequence detach type: " <> name)
  }
}

fn decode_move_in(
  value: JsonValue,
  context: Context,
) -> Result(sequence_field.Attach, String) {
  use id <- result.try(decode_effect_atom(value, context))
  use endpoint <- result.try(optional_field(
    value,
    "finalEndpoint",
    fn(value) { decode_atom(value, context) |> result.map(Some) },
    None,
  ))
  Ok(sequence_field.MoveIn(id, endpoint))
}

fn decode_remove(
  value: JsonValue,
  context: Context,
) -> Result(sequence_field.Detach, String) {
  use id <- result.try(decode_effect_atom(value, context))
  use id_override <- result.try(optional_field(
    value,
    "idOverride",
    fn(value) { decode_atom(value, context) |> result.map(Some) },
    None,
  ))
  Ok(sequence_field.Remove(id, id_override))
}

fn decode_move_out(
  value: JsonValue,
  context: Context,
) -> Result(sequence_field.Detach, String) {
  use id <- result.try(decode_effect_atom(value, context))
  use endpoint <- result.try(optional_field(
    value,
    "finalEndpoint",
    fn(value) { decode_atom(value, context) |> result.map(Some) },
    None,
  ))
  use id_override <- result.try(optional_field(
    value,
    "idOverride",
    fn(value) { decode_atom(value, context) |> result.map(Some) },
    None,
  ))
  Ok(sequence_field.MoveOut(id, endpoint, id_override))
}

fn decode_effect_atom(
  value: JsonValue,
  context: Context,
) -> Result(types.AtomId, String) {
  use local_id <- result.try(codec.field(value, "id", codec.integer))
  use revision <- result.try(optional_field(
    value,
    "revision",
    fn(value) { decode_revision(value, context) |> result.map(Some) },
    None,
  ))
  Ok(types.AtomId(revision, local_id))
}

fn optional_child(
  value: JsonValue,
  context: Context,
) -> Result(#(Option(types.AtomId), Context), String) {
  case value {
    VObject(fields) ->
      case list.key_find(fields, "changes") {
        Error(Nil) -> Ok(#(None, context))
        Ok(value) -> {
          use child <- result.try(decode_child(value, context))
          let Context(revisions, children) = context
          Ok(#(Some(child.id), Context(revisions, [child, ..children])))
        }
      }
    _ -> Error("expected a sequence mark object")
  }
}

fn compose_changes(
  changes: List(sequence_field.Changeset),
  state: ComposeState,
  move_context: moves.Context,
  algebra: sequence_field.AlgebraContext,
) -> Result(
  #(sequence_field.Changeset, ComposeState, moves.Context),
  types.TreeError,
) {
  case changes {
    [] -> {
      use empty <- result.try(sequence_field.from_marks([]))
      Ok(#(empty, state, move_context))
    }
    [change] -> Ok(#(change, state, move_context))
    [first, second, ..rest] -> {
      use #(composed, state, move_context) <- result.try(compose_pair_fixture(
        first,
        second,
        state,
        move_context,
        algebra,
      ))
      compose_changes([composed, ..rest], state, move_context, algebra)
    }
  }
}

fn compose_pair_fixture(
  first: sequence_field.Changeset,
  second: sequence_field.Changeset,
  state: ComposeState,
  move_context: moves.Context,
  algebra: sequence_field.AlgebraContext,
) -> Result(
  #(sequence_field.Changeset, ComposeState, moves.Context),
  types.TreeError,
) {
  use #(composed, next_state, move_context) <- result.try(compose.compose(
    first,
    second,
    state,
    compose_children,
    algebra,
    fixture_field(),
    move_context,
  ))
  let #(invalidated, move_context) = moves.take_invalidated(move_context)
  case invalidated {
    [] -> Ok(#(composed, next_state, move_context))
    _ ->
      compose.compose(
        first,
        second,
        state,
        compose_children,
        algebra,
        fixture_field(),
        move_context,
      )
  }
}

fn compose_children(
  left: Option(types.AtomId),
  right: Option(types.AtomId),
  state: ComposeState,
) -> Result(#(types.AtomId, ComposeState), types.TreeError) {
  let ComposeState(context, callbacks) = state
  let callback =
    json.object([
      #("left", option_child_json(left, context)),
      #("right", option_child_json(right, context)),
    ])
  let assert Some(id) = case left {
    Some(id) -> Some(id)
    None -> right
  }
  use left_child <- result.try(find_child(left, context))
  use right_child <- result.try(find_child(right, context))
  use child <- result.try(merge_child(id, left_child, right_child))
  let Context(revisions, children) = context
  Ok(#(
    id,
    ComposeState(Context(revisions, put_child_value(children, child)), [
      callback,
      ..callbacks
    ]),
  ))
}

fn rebase_children(
  authored_id: Option(types.AtomId),
  base_id: Option(types.AtomId),
  attach_state: sequence_field.AttachState,
  state: RebaseState,
) -> Result(#(Option(types.AtomId), RebaseState), types.TreeError) {
  let RebaseState(authored, base, output, callbacks) = state
  let callback =
    json.object([
      #("change", option_child_json(authored_id, authored)),
      #("base", option_child_json(base_id, base)),
    ])
  use authored_child <- result.try(find_child(authored_id, authored))
  use base_child <- result.try(find_child(base_id, base))
  use child <- result.try(rebase_child_value(
    authored_id,
    authored_child,
    base_child,
    attach_state,
  ))
  let Context(revisions, children) = output
  let output = case child {
    Some(child) -> Context(revisions, put_child_value(children, child))
    None -> output
  }
  Ok(#(
    child |> option.map(fn(child) { child.id }),
    RebaseState(authored, base, output, [callback, ..callbacks]),
  ))
}

fn rebase_child_value(
  authored_id: Option(types.AtomId),
  authored: Option(Child),
  base: Option(Child),
  _attach_state: sequence_field.AttachState,
) -> Result(Option(Child), types.TreeError) {
  case authored_id, authored, base {
    None, None, _ -> Ok(None)
    None, Some(_), _ ->
      Error(types.CorruptData(
        "sequence fixture child",
        "authored child has no identifier",
      ))
    Some(id), Some(authored), None -> Ok(Some(Child(..authored, id:)))
    Some(id), Some(authored), Some(base) -> {
      use authored_input <- result.try(require_child_context(
        authored.input_context,
        authored.output_context,
      ))
      use base_context <- result.try(require_child_context(
        base.input_context,
        base.output_context,
      ))
      case authored_input, base_context {
        None, _ -> normalize_child(id, authored) |> result.map(Some)
        Some(#(authored_input, _)), Some(#(base_input, base_output)) -> {
          use _ <- result.try(case authored_input == base_input {
            True -> Ok(Nil)
            False ->
              Error(types.CorruptData(
                "sequence fixture child",
                "rebased child input context does not match base input context",
              ))
          })
          Ok(
            Some(Child(
              id,
              authored.source_revision,
              Some(base_output),
              authored.intentions,
              Some(compose_intentions(base_output, authored.intentions)),
            )),
          )
        }
        Some(_), None -> Ok(Some(Child(..authored, id:)))
      }
    }
    Some(_), None, _ ->
      Error(types.CorruptData(
        "sequence fixture child",
        "unknown authored child change",
      ))
  }
}

fn require_child_context(
  input: Option(List(Int)),
  output: Option(List(Int)),
) -> Result(Option(#(List(Int), List(Int))), types.TreeError) {
  case input, output {
    None, None -> Ok(None)
    Some(input), Some(output) -> Ok(Some(#(input, output)))
    _, _ ->
      Error(types.CorruptData(
        "sequence fixture child",
        "child change has incomplete context",
      ))
  }
}

fn option_child_json(id: Option(types.AtomId), context: Context) -> Json {
  case id {
    None -> json.null()
    Some(id) -> encode_child(id, context) |> result.unwrap(json.null())
  }
}

fn find_child(
  id: Option(types.AtomId),
  context: Context,
) -> Result(Option(Child), types.TreeError) {
  let Context(children:, ..) = context
  case id {
    None -> Ok(None)
    Some(id) ->
      list.find(children, fn(child) { child.id == id })
      |> result.map(Some)
      |> result.map_error(fn(_) {
        types.CorruptData("sequence fixture child", "unknown child change")
      })
  }
}

fn merge_child(
  id: types.AtomId,
  left: Option(Child),
  right: Option(Child),
) -> Result(Child, types.TreeError) {
  case left, right {
    Some(left), Some(right) -> compose_child_changes(id, left, right)
    Some(child), None | None, Some(child) -> normalize_child(id, child)
    None, None ->
      Error(types.CorruptData(
        "sequence fixture child",
        "cannot compose two missing child changes",
      ))
  }
}

fn compose_child_changes(
  id: types.AtomId,
  left: Child,
  right: Child,
) -> Result(Child, types.TreeError) {
  compose_child_list(id, left.source_revision, [left, right], None, None, [])
}

fn compose_child_list(
  id: types.AtomId,
  source_revision: Option(Int),
  children: List(Child),
  input_context: Option(List(Int)),
  output_context: Option(List(Int)),
  intentions: List(Int),
) -> Result(Child, types.TreeError) {
  case children {
    [] ->
      case intentions, input_context, output_context {
        [], _, _ -> Ok(Child(id, source_revision, None, [], None))
        _, Some(input), Some(output) ->
          Ok(Child(id, source_revision, Some(input), intentions, Some(output)))
        _, _, _ ->
          Error(types.CorruptData(
            "sequence fixture child",
            "child change has incomplete context",
          ))
      }
    [child, ..rest] ->
      case child.input_context, child.output_context {
        None, None ->
          compose_child_list(
            id,
            source_revision,
            rest,
            input_context,
            output_context,
            intentions,
          )
        Some(input), Some(_) -> {
          use _ <- result.try(case output_context {
            None -> Ok(Nil)
            Some(output) ->
              case output == input {
                True -> Ok(Nil)
                False ->
                  Error(types.CorruptData(
                    "sequence fixture child",
                    "child input context does not match previous output context",
                  ))
              }
          })
          let output =
            compose_intentions(
              option.unwrap(output_context, input),
              child.intentions,
            )
          compose_child_list(
            id,
            source_revision,
            rest,
            option.or(input_context, Some(input)),
            Some(output),
            compose_intentions(intentions, child.intentions),
          )
        }
        _, _ ->
          Error(types.CorruptData(
            "sequence fixture child",
            "child change has incomplete context",
          ))
      }
  }
}

fn normalize_child(
  id: types.AtomId,
  child: Child,
) -> Result(Child, types.TreeError) {
  case child.input_context, child.output_context {
    None, None -> Ok(Child(id, child.source_revision, None, [], None))
    Some(input), Some(_) -> {
      let intentions = compose_intentions([], child.intentions)
      case intentions {
        [] -> Ok(Child(id, child.source_revision, None, [], None))
        _ ->
          Ok(Child(
            id,
            child.source_revision,
            Some(input),
            intentions,
            Some(compose_intentions(input, child.intentions)),
          ))
      }
    }
    _, _ ->
      Error(types.CorruptData(
        "sequence fixture child",
        "child change has incomplete context",
      ))
  }
}

fn compose_intentions(base: List(Int), extras: List(Int)) -> List(Int) {
  case extras {
    [] -> base
    [extra, ..rest] -> {
      let next = case pop_last_int(base) {
        Ok(#(prefix, last)) if last == 0 - extra -> prefix
        _ -> list.append(base, [extra])
      }
      compose_intentions(next, rest)
    }
  }
}

fn pop_last_int(values: List(Int)) -> Result(#(List(Int), Int), Nil) {
  case values {
    [] -> Error(Nil)
    [value] -> Ok(#([], value))
    [value, ..rest] -> {
      use #(prefix, last) <- result.try(pop_last_int(rest))
      Ok(#([value, ..prefix], last))
    }
  }
}

fn put_child_value(children: List(Child), child: Child) -> List(Child) {
  [child, ..list.filter(children, fn(existing) { existing.id != child.id })]
}

fn fixture_alias(
  id: types.AtomId,
  state: InvertState,
) -> Result(#(Int, InvertState), types.TreeError) {
  let InvertState(context, aliases) = state
  use #(local_id, aliases) <- result.try(sequence_field.alias(id, aliases))
  Ok(#(local_id, InvertState(context, aliases)))
}

fn fixture_field() -> moves.FieldId {
  moves.FieldId(None, "field")
}

fn algebra(context: Context) -> sequence_field.AlgebraContext {
  let Context(revisions:, ..) = context
  algebra_with_revisions(context, list.map(revisions, fn(pair) { pair.1 }))
}

fn algebra_with_revisions(
  context: Context,
  revisions: List(StableId),
) -> sequence_field.AlgebraContext {
  sequence_field.AlgebraContext(
    compare_atoms: fn(first, second) {
      use first_revision <- result.try(atom_revision_index(first, context))
      use second_revision <- result.try(atom_revision_index(second, context))
      Ok(case int.compare(first_revision, second_revision) {
        order.Eq -> int.compare(first.local_id, second.local_id)
        other -> other
      })
    },
    revision_index: fn(revision) {
      case revision_window_position(revisions, revision, 0) {
        Ok(index) -> Ok(Some(index))
        Error(_) ->
          case revision_position(revision, context) {
            Ok(_) -> Ok(None)
            Error(_) ->
              Error(types.InvalidHistory("fixture revision is unknown"))
          }
      }
    },
    rollback_of: fn(_) { Ok(None) },
  )
}

fn revision_window_position(
  revisions: List(StableId),
  revision: StableId,
  index: Int,
) -> Result(Int, Nil) {
  case revisions {
    [] -> Error(Nil)
    [candidate, ..rest] ->
      case candidate == revision {
        True -> Ok(index)
        False -> revision_window_position(rest, revision, index + 1)
      }
  }
}

fn rebase_algebra(
  context: Context,
  authored_revision: StableId,
  base_revision: StableId,
) -> sequence_field.AlgebraContext {
  let identity = algebra(context)
  sequence_field.AlgebraContext(
    compare_atoms: identity.compare_atoms,
    revision_index: fn(revision) {
      case revision == base_revision, revision == authored_revision {
        True, _ -> Ok(Some(0))
        _, True -> Ok(Some(1))
        False, False ->
          case revision_position(revision, context) {
            Ok(_) -> Ok(None)
            Error(_) ->
              Error(types.InvalidHistory("fixture revision is unknown"))
          }
      }
    },
    rollback_of: identity.rollback_of,
  )
}

fn atom_revision_index(
  id: types.AtomId,
  context: Context,
) -> Result(Int, types.TreeError) {
  case id.revision {
    None -> Ok(-1)
    Some(revision) ->
      revision_position(revision, context)
      |> result.map_error(fn(_) {
        types.InvalidHistory("fixture atom revision has no identity order")
      })
  }
}

fn revision_position(revision: StableId, context: Context) -> Result(Int, Nil) {
  let Context(revisions:, ..) = context
  revision_position_loop(revisions, revision, 0)
}

fn revision_position_loop(
  revisions: List(#(Int, StableId)),
  revision: StableId,
  index: Int,
) -> Result(Int, Nil) {
  case revisions {
    [] -> Error(Nil)
    [entry, ..rest] ->
      case entry.1 == revision {
        True -> Ok(index)
        False -> revision_position_loop(rest, revision, index + 1)
      }
  }
}

fn max_local_id(change: sequence_field.Changeset) -> Int {
  sequence_field.to_marks(change)
  |> list.fold(-1, fn(maximum, mark) {
    let maximum = max_atom(maximum, mark.cell_id, mark.count)
    let maximum = max_atom(maximum, mark.child, 1)
    max_effect(maximum, mark.effect, mark.count)
  })
}

fn max_effect(maximum: Int, effect: sequence_field.Effect, count: Int) -> Int {
  case effect {
    sequence_field.Noop -> maximum
    sequence_field.Rename(id) -> max_atom(maximum, Some(id), count)
    sequence_field.Attach(attach) -> max_attach(maximum, attach, count)
    sequence_field.Detach(detach) -> max_detach(maximum, detach, count)
    sequence_field.AttachAndDetach(attach, detach) ->
      max_detach(max_attach(maximum, attach, count), detach, count)
  }
}

fn max_attach(maximum: Int, attach: sequence_field.Attach, count: Int) -> Int {
  case attach {
    sequence_field.Insert(id) -> max_atom(maximum, Some(id), count)
    sequence_field.MoveIn(id, endpoint) ->
      max_atom(max_atom(maximum, Some(id), count), endpoint, count)
  }
}

fn max_detach(maximum: Int, detach: sequence_field.Detach, count: Int) -> Int {
  case detach {
    sequence_field.Remove(id, id_override) ->
      max_atom(max_atom(maximum, Some(id), count), id_override, count)
    sequence_field.MoveOut(id, endpoint, id_override) ->
      max_atom(
        max_atom(max_atom(maximum, Some(id), count), endpoint, count),
        id_override,
        count,
      )
  }
}

fn max_atom(maximum: Int, id: Option(types.AtomId), count: Int) -> Int {
  case id {
    None -> maximum
    Some(id) -> int.max(maximum, id.local_id + count - 1)
  }
}

fn decode_delta_atom(
  value: JsonValue,
  context: Context,
) -> Result(types.AtomId, String) {
  use local_id <- result.try(codec.field(value, "minor", codec.integer))
  use revision <- result.try(
    codec.field(value, "major", fn(value) {
      case value {
        VNull -> Ok(None)
        _ -> decode_revision(value, context) |> result.map(Some)
      }
    }),
  )
  Ok(types.AtomId(revision, local_id))
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
  let #(input_context, intentions, output_context) = case
    input_context,
    output_context
  {
    Some(input), Some(output) -> #(Some(input), intentions, Some(output))
    _, _ -> #(None, [], None)
  }
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
  use values <- result.try(context_revisions(revisions, 1, []))
  Ok(Context(values, []))
}

fn context_revisions(
  revisions: List(Int),
  index: Int,
  output: List(#(Int, StableId)),
) -> Result(List(#(Int, StableId)), String) {
  case revisions {
    [] -> Ok(list.reverse(output))
    [revision, ..rest] -> {
      use _ <- result.try(case list.key_find(output, revision) {
        Ok(_) -> Error("duplicate fixture revision")
        Error(Nil) -> Ok(Nil)
      })
      use stable <- result.try(revision_for(index))
      context_revisions(rest, index + 1, [#(revision, stable), ..output])
    }
  }
}

fn revision_for(index: Int) -> Result(StableId, String) {
  let suffix =
    index
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
