import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode.{type Decoder}
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/set
import gleam/string
import watershed/fluid_ids.{type StableId}
import watershed/json_ot.{type JsonValue, VBool, VNull, VNumber, VString}
import watershed/tree/forest
import watershed/tree/optional_field as field
import watershed/tree/schema
import watershed/tree/types

const max_safe_integer = 9_007_199_254_740_991

const optional_schema = "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.string\":{\"kind\":{\"leaf\":1}},\"com.fluidframework.leaf.null\":{\"kind\":{\"leaf\":4}}},\"root\":{\"kind\":\"Optional\",\"types\":[\"com.fluidframework.leaf.string\",\"com.fluidframework.leaf.null\"]}}"

type RevisionTable {
  RevisionTable(entries: List(#(Int, StableId)))
}

type NamedChange {
  NamedChange(change: field.FieldChange, revision: Option(StableId))
}

type Input {
  Input(
    changes: Json,
    operations: Json,
    swap_application: Json,
    swap_algebra: Json,
    revisions: Json,
    table: RevisionTable,
    scenarios: List(Json),
  )
}

type Scenario {
  Scenario(
    id: String,
    changes: Dict(String, field.FieldChange),
    actions: List(Json),
    forest: Option(Json),
  )
}

type ComposeCallback {
  ComposeCallback(
    input: Option(types.AtomId),
    over: Option(types.AtomId),
    returned: types.AtomId,
  )
}

type RebaseCallback {
  RebaseCallback(
    input: Option(types.AtomId),
    over: Option(types.AtomId),
    state: field.AttachState,
    returned: Option(types.AtomId),
  )
}

type ComposeContext {
  ComposeContext(remaining: List(ComposeCallback), calls: List(ComposeCallback))
}

type RebaseContext {
  RebaseContext(remaining: List(RebaseCallback), calls: List(RebaseCallback))
}

type Execution {
  Execution(
    changes: Dict(String, field.FieldChange),
    action_ids: set.Set(String),
    result_ids: set.Set(String),
    checkpoints: List(Json),
    tree: Option(forest.Forest),
  )
}

pub fn run(input: Json) -> Result(Json, String) {
  use decoded <- result.try(
    json.parse(json.to_string(input), input_decoder())
    |> result.map_error(fn(error) {
      "invalid field fixture: " <> string.inspect(error)
    }),
  )
  use _ <- result.try(validate_scenario_ids(decoded.scenarios))
  use original <- result.try(run_original(decoded))
  use scenarios <- result.try(
    list.try_map(decoded.scenarios, run_scenario(_, decoded.table)),
  )
  Ok(
    json.object([
      #("observations", array(original)),
      #("scenarios", array(scenarios)),
    ]),
  )
}

fn validate_scenario_ids(scenarios: List(Json)) -> Result(Nil, String) {
  case scenarios {
    [] -> Error("field fixture scenarios must not be empty")
    [_, ..] -> {
      use _ <- result.try(
        list.try_fold(scenarios, set.new(), fn(seen, scenario) {
          use id <- result.try(read(scenario, ["id"], decode.string))
          case string.is_empty(id) || set.contains(seen, id) {
            True -> Error("empty or duplicate field scenario id: " <> id)
            False -> Ok(set.insert(seen, id))
          }
        }),
      )
      Ok(Nil)
    }
  }
}

fn input_decoder() -> Decoder(Input) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  exact_decoder(
    fields,
    [
      "codecs",
      "revisions",
      "changes",
      "operations",
      "swapApplication",
      "swapAlgebra",
      "revisionTable",
      "scenarios",
    ],
    Input(
      json.null(),
      json.null(),
      json.null(),
      json.null(),
      json.null(),
      RevisionTable([]),
      [],
    ),
    {
      use _ <- decode.field("codecs", codecs_decoder())
      use revisions <- decode.field("revisions", json_decoder())
      use changes <- decode.field("changes", json_decoder())
      use operations <- decode.field("operations", json_decoder())
      use swap_application <- decode.field("swapApplication", json_decoder())
      use swap_algebra <- decode.field("swapAlgebra", json_decoder())
      use entries <- decode.field(
        "revisionTable",
        decode.list(revision_entry_decoder()),
      )
      use table <- decode.then(validate_revision_table(entries))
      use scenarios <- decode.field("scenarios", decode.list(json_decoder()))
      decode.success(Input(
        changes:,
        operations:,
        swap_application:,
        swap_algebra:,
        revisions:,
        table:,
        scenarios:,
      ))
    },
  )
}

fn codecs_decoder() -> Decoder(Nil) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  exact_decoder(fields, ["optional", "required"], Nil, {
    use optional <- decode.field("optional", decode.int)
    use required <- decode.field("required", decode.int)
    case optional == 2 && required == 2 {
      True -> decode.success(Nil)
      False -> decode.failure(Nil, "supported optional and required codec 2")
    }
  })
}

fn revision_entry_decoder() -> Decoder(#(Int, StableId)) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  exact_decoder(fields, ["revision", "stableId"], #(0, empty_stable()), {
    use revision <- decode.field("revision", decode.int)
    use raw <- decode.field("stableId", decode.string)
    case fluid_ids.stable_id(raw) {
      Ok(stable) -> decode.success(#(revision, stable))
      Error(_) -> decode.failure(#(0, empty_stable()), "valid stable revision")
    }
  })
}

fn validate_revision_table(
  entries: List(#(Int, StableId)),
) -> Decoder(RevisionTable) {
  case entries {
    [] -> decode.failure(RevisionTable([]), "nonempty revision table")
    [_, ..] -> {
      let numbers = list.map(entries, fn(entry) { entry.0 })
      let stable = list.map(entries, fn(entry) { entry.1 })
      case
        list.all(numbers, fn(value) { value >= 0 })
        && list.length(list.unique(numbers)) == list.length(numbers)
        && list.length(list.unique(stable)) == list.length(stable)
      {
        True -> decode.success(RevisionTable(entries))
        False ->
          decode.failure(
            RevisionTable([]),
            "unique numeric and stable revision mappings",
          )
      }
    }
  }
}

fn run_original(input: Input) -> Result(List(Json), String) {
  use revisions <- result.try(original_revisions(input.revisions, input.table))
  let #(
    first_revision,
    second_revision,
    _inverse_revision,
    _replacement_revision,
  ) = revisions
  use changes <- result.try(original_changes(
    input.changes,
    first_revision,
    second_revision,
    input.table,
  ))
  use #(compose_left_name, compose_right_name, compose_revision) <- result.try(
    original_compose_operation(input.operations, input.table),
  )
  use compose_left <- result.try(original_change(changes, compose_left_name))
  use compose_right <- result.try(original_change(changes, compose_right_name))
  use #(composed, _) <- result.try(
    field.compose(
      compose_left.change,
      compose_right.change,
      Nil,
      unexpected_compose,
    )
    |> native("original compose"),
  )
  let changes =
    dict.insert(
      changes,
      "compose",
      NamedChange(composed, Some(compose_revision)),
    )
  use #(invert_name, is_rollback, operation_inverse_revision) <- result.try(
    original_invert_operation(input.operations, input.table),
  )
  use invert_change <- result.try(original_change(changes, invert_name))
  use #(inverted, _) <- result.try(
    field.invert(
      invert_change.change,
      is_rollback,
      Some(operation_inverse_revision),
      -1,
    )
    |> native("original invert"),
  )
  use #(rebase_change_name, rebase_over_name) <- result.try(
    original_rebase_operation(input.operations),
  )
  use rebase_change <- result.try(original_change(changes, rebase_change_name))
  use rebase_over <- result.try(original_change(changes, rebase_over_name))
  use #(rebased, _) <- result.try(
    field.rebase(
      rebase_change.change,
      rebase_over.change,
      Nil,
      unexpected_rebase,
    )
    |> native("original rebase"),
  )
  use #(replace_name, obsolete, updated) <- result.try(
    original_replace_operation(input.operations, input.table),
  )
  use replace_change <- result.try(original_change(changes, replace_name))
  use replaced <- result.try(
    field.replace_revisions(replace_change.change, obsolete, Some(updated))
    |> native("original revision replacement"),
  )
  use swap <- result.try(original_change(changes, "swap"))
  use compose_json <- result.try(v2_encode(
    composed,
    Some(compose_revision),
    input.table,
  ))
  use invert_json <- result.try(v2_encode(
    inverted,
    Some(operation_inverse_revision),
    input.table,
  ))
  use rebase_json <- result.try(v2_encode(
    rebased,
    rebase_change.revision,
    input.table,
  ))
  use swap_encoded <- result.try(v2_encode(
    swap.change,
    swap.revision,
    input.table,
  ))
  use replaced_json <- result.try(v2_encode(
    replaced,
    Some(updated),
    input.table,
  ))
  use refusal <- result.try(direct_swap_refusal(
    input.swap_application,
    swap.change,
    input.table,
  ))
  use mapping <- result.try(swap_mapping(input.swap_algebra, input.table))
  Ok([
    operation_encoded("compose", compose_json),
    operation_encoded("invert", invert_json),
    operation_encoded("rebase", rebase_json),
    operation_encoded("simultaneous-swap", swap_encoded),
    refusal,
    mapping,
    operation_encoded("replace-revisions", replaced_json),
  ])
}

fn original_changes(
  input: Json,
  first_revision: StableId,
  second_revision: StableId,
  table: RevisionTable,
) -> Result(Dict(String, NamedChange), String) {
  use fields <- result.try(object_fields(input, "changes"))
  use _ <- result.try(exact_fields_result(
    fields,
    ["optional", "required", "swap"],
    "changes",
  ))
  use optional_json <- result.try(read_json(input, ["optional"]))
  use required_json <- result.try(read_json(input, ["required"]))
  use swap_json <- result.try(read_json(input, ["swap"]))
  use optional <- result.try(v2_change(
    optional_json,
    Some(first_revision),
    table,
  ))
  use required <- result.try(v2_change(
    required_json,
    Some(second_revision),
    table,
  ))
  use swap <- result.try(v2_change(swap_json, Some(first_revision), table))
  Ok(
    dict.from_list([
      #("optional", NamedChange(optional, Some(first_revision))),
      #("required", NamedChange(required, Some(second_revision))),
      #("swap", NamedChange(swap, Some(first_revision))),
    ]),
  )
}

fn original_change(
  changes: Dict(String, NamedChange),
  name: String,
) -> Result(NamedChange, String) {
  dict.get(changes, name)
  |> result.map_error(fn(_) { "unknown original change: " <> name })
}

fn original_revisions(
  input: Json,
  table: RevisionTable,
) -> Result(#(StableId, StableId, StableId, StableId), String) {
  use fields <- result.try(object_fields(input, "revisions"))
  use _ <- result.try(exact_fields_result(
    fields,
    ["first", "second", "inverse", "replacement"],
    "revisions",
  ))
  use first <- result.try(read(input, ["first"], decode.int))
  use second <- result.try(read(input, ["second"], decode.int))
  use inverse <- result.try(read(input, ["inverse"], decode.int))
  use replacement <- result.try(read(input, ["replacement"], decode.int))
  use first <- result.try(revision(table, first))
  use second <- result.try(revision(table, second))
  use inverse <- result.try(revision(table, inverse))
  use replacement <- result.try(revision(table, replacement))
  Ok(#(first, second, inverse, replacement))
}

fn original_operations(input: Json) -> Result(Nil, String) {
  use fields <- result.try(object_fields(input, "operations"))
  exact_fields_result(
    fields,
    ["compose", "invert", "rebase", "replaceRevisions"],
    "operations",
  )
}

fn original_compose_operation(
  input: Json,
  table: RevisionTable,
) -> Result(#(String, String, StableId), String) {
  use _ <- result.try(original_operations(input))
  use operation <- result.try(read_json(input, ["compose"]))
  use fields <- result.try(object_fields(operation, "compose operation"))
  use _ <- result.try(exact_fields_result(
    fields,
    ["left", "right", "revisionMetadata"],
    "compose operation",
  ))
  use left <- result.try(read(operation, ["left"], decode.string))
  use right <- result.try(read(operation, ["right"], decode.string))
  use metadata <- result.try(read_json(operation, ["revisionMetadata"]))
  use metadata_fields <- result.try(object_fields(
    metadata,
    "compose revisionMetadata",
  ))
  use _ <- result.try(exact_fields_result(
    metadata_fields,
    ["revisions", "base", "rollbackRevisions"],
    "compose revisionMetadata",
  ))
  use revisions <- result.try(read(
    metadata,
    ["revisions"],
    decode.list(decode.int),
  ))
  use base_number <- result.try(read(metadata, ["base"], decode.int))
  use rollback_revisions <- result.try(read(
    metadata,
    ["rollbackRevisions"],
    decode.list(decode.int),
  ))
  use _ <- result.try(
    list.try_each(revisions, fn(number) {
      revision(table, number) |> result.map(fn(_) { Nil })
    }),
  )
  use base <- result.try(revision(table, base_number))
  use _ <- result.try(
    list.try_each(rollback_revisions, fn(number) {
      revision(table, number) |> result.map(fn(_) { Nil })
    }),
  )
  Ok(#(left, right, base))
}

fn original_invert_operation(
  input: Json,
  table: RevisionTable,
) -> Result(#(String, Bool, StableId), String) {
  use operation <- result.try(read_json(input, ["invert"]))
  use fields <- result.try(object_fields(operation, "invert operation"))
  use _ <- result.try(exact_fields_result(
    fields,
    ["change", "isRollback", "inverseRevision"],
    "invert operation",
  ))
  use change <- result.try(read(operation, ["change"], decode.string))
  use is_rollback <- result.try(read(operation, ["isRollback"], decode.bool))
  use inverse_number <- result.try(read(
    operation,
    ["inverseRevision"],
    decode.int,
  ))
  use inverse_revision <- result.try(revision(table, inverse_number))
  Ok(#(change, is_rollback, inverse_revision))
}

fn original_rebase_operation(input: Json) -> Result(#(String, String), String) {
  use operation <- result.try(read_json(input, ["rebase"]))
  use fields <- result.try(object_fields(operation, "rebase operation"))
  use _ <- result.try(exact_fields_result(
    fields,
    ["change", "over"],
    "rebase operation",
  ))
  use change <- result.try(read(operation, ["change"], decode.string))
  use over <- result.try(read(operation, ["over"], decode.string))
  Ok(#(change, over))
}

fn original_replace_operation(
  input: Json,
  table: RevisionTable,
) -> Result(#(String, List(Option(StableId)), StableId), String) {
  use operation <- result.try(read_json(input, ["replaceRevisions"]))
  use fields <- result.try(object_fields(
    operation,
    "replaceRevisions operation",
  ))
  use _ <- result.try(exact_fields_result(
    fields,
    ["change", "obsolete", "updated"],
    "replaceRevisions operation",
  ))
  use change <- result.try(read(operation, ["change"], decode.string))
  use obsolete_numbers <- result.try(read(
    operation,
    ["obsolete"],
    decode.list(decode.int),
  ))
  use obsolete <- result.try(
    list.try_map(obsolete_numbers, fn(number) {
      revision(table, number) |> result.map(Some)
    }),
  )
  use updated_number <- result.try(read(operation, ["updated"], decode.int))
  use updated <- result.try(revision(table, updated_number))
  Ok(#(change, obsolete, updated))
}

fn direct_swap_refusal(
  input: Json,
  swap: field.FieldChange,
  table: RevisionTable,
) -> Result(Json, String) {
  use fields <- result.try(object_fields(input, "swapApplication"))
  use _ <- result.try(exact_fields_result(
    fields,
    ["operation", "revision", "registers"],
    "swapApplication",
  ))
  use operation <- result.try(read(input, ["operation"], decode.string))
  use _ <- result.try(case operation {
    "apply-original-simultaneous-swap" -> Ok(Nil)
    _ -> Error("unknown swap application operation: " <> operation)
  })
  use revision_number <- result.try(read(input, ["revision"], decode.int))
  use revision <- result.try(revision(table, revision_number))
  use registers <- result.try(
    json.parse(
      json.to_string(input),
      decode.at(["registers"], decode.list(register_content_decoder(table))),
    )
    |> decode_error("swapApplication.registers"),
  )
  use #(first_source, second_source) <- result.try(occupied_swap_sources(
    swap,
    registers,
  ))
  use stored <- result.try(stored_schema())
  use view <- result.try(first_revision(table))
  use tree <- result.try(
    forest.new(view, stored, None) |> native("swap forest"),
  )
  let builds =
    list.map(registers, fn(entry) { forest.Build(entry.0, [entry.1]) })
  use tree <- result.try(apply_builds(tree, builds))
  use _ <- result.try(read_detached(tree, first_source))
  use _ <- result.try(read_detached(tree, second_source))
  use before <- result.try(forest.export_data(tree) |> native("swap before"))
  use delta <- result.try(
    field.into_delta(swap, unexpected_child_delta)
    |> native("swap delta"),
  )
  use delta <- result.try(field_delta_to_forest(delta, Some(revision), []))
  let applied = forest.apply_delta(tree, delta)
  use _ <- result.try(case applied {
    Error(types.CorruptData(
      "rename",
      "sources are missing or destinations form an occupied cycle",
    )) -> Ok(Nil)
    Error(error) -> Error("unexpected swap refusal: " <> string.inspect(error))
    Ok(_) -> Error("the native forest accepted an occupied rename cycle")
  })
  use after <- result.try(forest.export_data(tree) |> native("swap after"))
  use _ <- result.try(case after == before {
    True -> Ok(Nil)
    False -> Error("occupied rename refusal changed forest state")
  })
  case registers {
    [first, second] -> {
      use first_value <- result.try(read_detached(tree, first.0))
      use second_value <- result.try(read_detached(tree, second.0))
      Ok(
        json.object([
          #(
            "operation",
            json.string("simultaneous-swap-direct-application-refusal"),
          ),
          #("status", json.string("rejected")),
          #("reason", json.string("occupied-rename-cycle")),
          #(
            "postFailureForestRead",
            json.object([
              #("status", json.string("accepted")),
              #(
                "value",
                json.object([
                  #("first", tree_value_to_plain_json(first_value)),
                  #("second", tree_value_to_plain_json(second_value)),
                ]),
              ),
            ]),
          ),
        ]),
      )
    }
    _ -> Error("swapApplication must contain exactly two registers")
  }
}

fn occupied_swap_sources(
  swap: field.FieldChange,
  registers: List(#(types.AtomId, types.TreeValue)),
) -> Result(#(types.AtomId, types.AtomId), String) {
  case swap, registers {
    field.FieldChange(
      moves: [
        #(first_source, first_destination),
        #(second_source, second_destination),
      ],
      child_changes: [],
      replacement: None,
    ),
      [first_register, second_register]
    -> {
      let supplied = [first_register.0, second_register.0]
      case
        first_source != first_destination
        && first_source == second_destination
        && first_destination == second_source
        && first_register.0 != second_register.0
        && list.contains(supplied, first_source)
        && list.contains(supplied, second_source)
      {
        True -> Ok(#(first_source, second_source))
        False ->
          Error(
            "swapApplication requires an occupied two-register swap over the supplied registers",
          )
      }
    }
    _, _ ->
      Error(
        "swapApplication requires an occupied two-register swap over the supplied registers",
      )
  }
}

fn register_content_decoder(
  table: RevisionTable,
) -> Decoder(#(types.AtomId, types.TreeValue)) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  exact_decoder(fields, ["id", "content"], #(empty_atom(), types.NullValue), {
    use id <- decode.field("id", atom_decoder(table))
    use content <- decode.field("content", plain_tree_value_decoder())
    decode.success(#(id, content))
  })
}

fn swap_mapping(input: Json, table: RevisionTable) -> Result(Json, String) {
  use fields <- result.try(object_fields(input, "swapAlgebra"))
  use _ <- result.try(exact_fields_result(
    fields,
    ["operation", "change", "over"],
    "swapAlgebra",
  ))
  use operation <- result.try(read(input, ["operation"], decode.string))
  use _ <- result.try(case operation {
    "rebase-child-changes-over-simultaneous-swap" -> Ok(Nil)
    _ -> Error("unknown swap algebra operation: " <> operation)
  })
  use change <- result.try(decode_at(
    input,
    ["change"],
    legacy_change_decoder(table),
    "swap change",
  ))
  use over <- result.try(decode_at(
    input,
    ["over"],
    legacy_change_decoder(table),
    "swap over",
  ))
  let callback = fn(
    node: Option(types.AtomId),
    over_node: Option(types.AtomId),
    _: field.AttachState,
    calls: List(#(Option(types.AtomId), Option(types.AtomId))),
  ) {
    case node {
      Some(node) -> Ok(#(Some(node), [#(node |> Some, over_node), ..calls]))
      None ->
        Error(types.CorruptData(
          "fixture.swap.callback",
          "Missing authored child",
        ))
    }
  }
  use #(rebased, _) <- result.try(
    field.rebase(change, over, [], callback) |> native("swap algebra"),
  )
  use mappings <- result.try(zip_mappings(
    change.child_changes,
    rebased.child_changes,
    table,
  ))
  Ok(
    json.object([
      #("operation", json.string("simultaneous-swap-algebra-mapping")),
      #("mappings", array(mappings)),
    ]),
  )
}

fn zip_mappings(
  before: List(#(field.RegisterId, types.AtomId)),
  after: List(#(field.RegisterId, types.AtomId)),
  table: RevisionTable,
) -> Result(List(Json), String) {
  case before, after {
    [], [] -> Ok([])
    [#(field.Detached(from), node), ..before],
      [#(field.Detached(to), output), ..after]
    -> {
      use _ <- result.try(case node == output {
        True -> Ok(Nil)
        False -> Error("swap algebra changed child identity")
      })
      use node <- result.try(atom_to_structural_json(node, table))
      use from <- result.try(atom_to_structural_json(from, table))
      use to <- result.try(atom_to_structural_json(to, table))
      use rest <- result.try(zip_mappings(before, after, table))
      Ok([
        json.object([
          #("node", node),
          #("from", from),
          #("to", to),
        ]),
        ..rest
      ])
    }
    _, _ -> Error("swap algebra produced an unexpected mapping shape")
  }
}

fn run_scenario(raw: Json, table: RevisionTable) -> Result(Json, String) {
  use scenario <- result.try(decode_scenario(raw, table))
  use tree <- result.try(case scenario.forest {
    None -> Ok(None)
    Some(input) -> initialize_forest(input, table) |> result.map(Some)
  })
  let result_ids = scenario.changes |> dict.keys |> set.from_list
  let state =
    Execution(
      changes: scenario.changes,
      action_ids: set.new(),
      result_ids:,
      checkpoints: [],
      tree:,
    )
  use state <- result.try(
    list.try_fold(scenario.actions, state, fn(state, action) {
      run_action(scenario.id, action, state, table)
    }),
  )
  Ok(
    json.object([
      #("id", json.string(scenario.id)),
      #("checkpoints", array(list.reverse(state.checkpoints))),
    ]),
  )
}

fn decode_scenario(
  raw: Json,
  table: RevisionTable,
) -> Result(Scenario, String) {
  json.parse(json.to_string(raw), scenario_decoder(table))
  |> result.map_error(fn(error) {
    "invalid field scenario: " <> string.inspect(error)
  })
}

fn scenario_decoder(table: RevisionTable) -> Decoder(Scenario) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  let expected = case dict.has_key(fields, "forest") {
    True -> ["id", "changes", "actions", "forest"]
    False -> ["id", "changes", "actions"]
  }
  exact_decoder(fields, expected, Scenario("", dict.new(), [], None), {
    use id <- decode.field("id", decode.string)
    use changes <- decode.field(
      "changes",
      decode.dict(decode.string, change_decoder(table)),
    )
    use actions <- decode.field("actions", decode.list(json_decoder()))
    use forest <- decode.optional_field(
      "forest",
      None,
      decode.map(json_decoder(), Some),
    )
    case string.is_empty(id) || list.is_empty(actions) {
      True ->
        decode.failure(
          Scenario("", dict.new(), [], None),
          "nonempty scenario id and actions",
        )
      False -> decode.success(Scenario(id:, changes:, actions:, forest:))
    }
  })
}

fn run_action(
  scenario_id: String,
  action: Json,
  state: Execution,
  table: RevisionTable,
) -> Result(Execution, String) {
  use fields <- result.try(object_fields(action, scenario_id <> " action"))
  use id <- result.try(read(action, ["id"], decode.string))
  use operation <- result.try(read(action, ["op"], decode.string))
  use _ <- result.try(
    case string.is_empty(id) || set.contains(state.action_ids, id) {
      True -> Error(scenario_id <> ": empty or duplicate action id: " <> id)
      False -> Ok(Nil)
    },
  )
  let state = Execution(..state, action_ids: set.insert(state.action_ids, id))
  let location = scenario_id <> "." <> id
  case operation {
    "set" -> {
      use _ <- result.try(exact_action(
        fields,
        ["id", "op", "result", "wasEmpty", "fill", "detach"],
        location,
      ))
      use name <- result.try(result_name(action, state, location))
      use was_empty <- result.try(read(action, ["wasEmpty"], decode.bool))
      use fill <- result.try(decode_at(
        action,
        ["fill"],
        atom_decoder(table),
        location <> ".fill",
      ))
      use detach <- result.try(decode_at(
        action,
        ["detach"],
        atom_decoder(table),
        location <> ".detach",
      ))
      add_result(state, id, name, field.set(was_empty, fill, detach), [], table)
    }
    "clear" -> {
      use _ <- result.try(exact_action(
        fields,
        ["id", "op", "result", "wasEmpty", "detach"],
        location,
      ))
      use name <- result.try(result_name(action, state, location))
      use was_empty <- result.try(read(action, ["wasEmpty"], decode.bool))
      use detach <- result.try(decode_at(
        action,
        ["detach"],
        atom_decoder(table),
        location <> ".detach",
      ))
      add_result(state, id, name, field.clear(was_empty, detach), [], table)
    }
    "replaceRevisions" -> {
      use _ <- result.try(exact_action(
        fields,
        ["id", "op", "result", "change", "obsolete", "updated"],
        location,
      ))
      use name <- result.try(result_name(action, state, location))
      use change <- result.try(change_reference(
        action,
        "change",
        state,
        location,
      ))
      use obsolete <- result.try(decode_at(
        action,
        ["obsolete"],
        decode.list(revision_option_decoder(table)),
        location <> ".obsolete",
      ))
      use updated <- result.try(decode_at(
        action,
        ["updated"],
        revision_option_decoder(table),
        location <> ".updated",
      ))
      use changed <- result.try(
        field.replace_revisions(change, obsolete, updated)
        |> native(location),
      )
      add_result(state, id, name, changed, [], table)
    }
    "compose" -> compose_action(action, fields, state, table, location, id)
    "invert" -> invert_action(action, fields, state, table, location, id)
    "rebase" -> rebase_action(action, fields, state, table, location, id)
    "intoDelta" -> delta_action(action, fields, state, table, location, id)
    _ -> Error(location <> ": unknown field action: " <> operation)
  }
}

fn compose_action(
  action: Json,
  fields: Dict(String, Dynamic),
  state: Execution,
  table: RevisionTable,
  location: String,
  id: String,
) -> Result(Execution, String) {
  use _ <- result.try(exact_action(
    fields,
    ["id", "op", "result", "left", "right", "callbacks"],
    location,
  ))
  use name <- result.try(result_name(action, state, location))
  use left <- result.try(change_reference(action, "left", state, location))
  use right <- result.try(change_reference(action, "right", state, location))
  use callbacks <- result.try(decode_at(
    action,
    ["callbacks"],
    decode.list(compose_callback_decoder(table)),
    location <> ".callbacks",
  ))
  let context = ComposeContext(callbacks, [])
  use #(change, context) <- result.try(
    field.compose(left, right, context, compose_callback)
    |> native(location),
  )
  use _ <- result.try(case context.remaining {
    [] -> Ok(Nil)
    [_, ..] -> Error(location <> ": compose callback table was not consumed")
  })
  use calls <- result.try(
    list.reverse(context.calls)
    |> list.try_map(compose_callback_to_json(_, table)),
  )
  add_result(state, id, name, change, [#("callbacks", array(calls))], table)
}

fn compose_callback(
  input: Option(types.AtomId),
  over: Option(types.AtomId),
  context: ComposeContext,
) -> Result(#(types.AtomId, ComposeContext), types.TreeError) {
  case context.remaining {
    [] ->
      Error(types.CorruptData("fixture.compose.callback", "Unexpected callback"))
    [expected, ..remaining] -> {
      case expected.input == input && expected.over == over {
        False ->
          Error(types.CorruptData(
            "fixture.compose.callback",
            "Callback arguments do not match the script",
          ))
        True ->
          Ok(#(
            expected.returned,
            ComposeContext(remaining, [expected, ..context.calls]),
          ))
      }
    }
  }
}

fn invert_action(
  action: Json,
  fields: Dict(String, Dynamic),
  state: Execution,
  table: RevisionTable,
  location: String,
  id: String,
) -> Result(Execution, String) {
  use _ <- result.try(exact_action(
    fields,
    [
      "id",
      "op",
      "result",
      "change",
      "isRollback",
      "inverseRevision",
      "lastLocalId",
    ],
    location,
  ))
  use name <- result.try(result_name(action, state, location))
  use change <- result.try(change_reference(action, "change", state, location))
  use rollback <- result.try(read(action, ["isRollback"], decode.bool))
  use revision <- result.try(decode_at(
    action,
    ["inverseRevision"],
    revision_option_decoder(table),
    location <> ".inverseRevision",
  ))
  use last <- result.try(read(action, ["lastLocalId"], decode.int))
  use #(change, next) <- result.try(
    field.invert(change, rollback, revision, last) |> native(location),
  )
  let allocated = case next > last {
    True ->
      int.range(from: last + 1, to: next + 1, with: [], run: fn(values, value) {
        list.append(values, [value])
      })
    False -> []
  }
  add_result(
    state,
    id,
    name,
    change,
    [
      #(
        "allocations",
        json.object([
          #("start", json.int(last)),
          #("allocated", array(list.map(allocated, json.int))),
          #("end", json.int(next)),
        ]),
      ),
    ],
    table,
  )
}

fn rebase_action(
  action: Json,
  fields: Dict(String, Dynamic),
  state: Execution,
  table: RevisionTable,
  location: String,
  id: String,
) -> Result(Execution, String) {
  use _ <- result.try(exact_action(
    fields,
    ["id", "op", "result", "change", "over", "callbacks"],
    location,
  ))
  use name <- result.try(result_name(action, state, location))
  use change <- result.try(change_reference(action, "change", state, location))
  use over <- result.try(change_reference(action, "over", state, location))
  use callbacks <- result.try(decode_at(
    action,
    ["callbacks"],
    decode.list(rebase_callback_decoder(table)),
    location <> ".callbacks",
  ))
  let context = RebaseContext(callbacks, [])
  use #(change, context) <- result.try(
    field.rebase(change, over, context, rebase_callback)
    |> native(location),
  )
  use _ <- result.try(case context.remaining {
    [] -> Ok(Nil)
    [_, ..] -> Error(location <> ": rebase callback table was not consumed")
  })
  use calls <- result.try(
    list.reverse(context.calls)
    |> list.try_map(rebase_callback_to_json(_, table)),
  )
  add_result(state, id, name, change, [#("callbacks", array(calls))], table)
}

fn rebase_callback(
  input: Option(types.AtomId),
  over: Option(types.AtomId),
  state: field.AttachState,
  context: RebaseContext,
) -> Result(#(Option(types.AtomId), RebaseContext), types.TreeError) {
  case context.remaining {
    [] ->
      Error(types.CorruptData("fixture.rebase.callback", "Unexpected callback"))
    [expected, ..remaining] -> {
      case
        expected.input == input
        && expected.over == over
        && expected.state == state
      {
        False ->
          Error(types.CorruptData(
            "fixture.rebase.callback",
            "Callback arguments do not match the script",
          ))
        True ->
          Ok(#(
            expected.returned,
            RebaseContext(remaining, [expected, ..context.calls]),
          ))
      }
    }
  }
}

fn delta_action(
  action: Json,
  fields: Dict(String, Dynamic),
  state: Execution,
  table: RevisionTable,
  location: String,
  id: String,
) -> Result(Execution, String) {
  let apply = dict.has_key(fields, "applyToForest")
  let expected = case apply {
    True -> ["id", "op", "change", "childDeltas", "applyToForest", "revision"]
    False -> ["id", "op", "change", "childDeltas"]
  }
  use _ <- result.try(exact_action(fields, expected, location))
  use change <- result.try(change_reference(action, "change", state, location))
  use children <- result.try(decode_at(
    action,
    ["childDeltas"],
    decode.list(child_delta_decoder(table)),
    location <> ".childDeltas",
  ))
  use _ <- result.try(validate_child_deltas(change, children, location))
  use delta <- result.try(
    field.into_delta(change, fn(node) {
      case list.key_find(children, node) {
        Ok(fields) -> Ok(fields)
        Error(Nil) ->
          Error(types.CorruptData(
            "fixture.delta.callback",
            "Unexpected child delta callback",
          ))
      }
    })
    |> native(location),
  )
  use delta_json <- result.try(field_delta_to_json(delta, table))
  use #(tree, extras) <- result.try(case apply {
    False -> Ok(#(state.tree, []))
    True -> {
      use flag <- result.try(read(action, ["applyToForest"], decode.bool))
      use _ <- result.try(case flag {
        True -> Ok(Nil)
        False -> Error(location <> ": applyToForest must be true when present")
      })
      use revision <- result.try(decode_at(
        action,
        ["revision"],
        revision_option_decoder(table),
        location <> ".revision",
      ))
      use tree <- result.try(case state.tree {
        None -> Error(location <> ": forest action has no forest input")
        Some(tree) -> Ok(tree)
      })
      use forest_delta <- result.try(field_delta_to_forest(delta, revision, []))
      use tree <- result.try(
        forest.apply_delta(tree, forest_delta) |> native(location),
      )
      use observed <- result.try(observe_field_forest(tree, table))
      Ok(#(Some(tree), [#("forest", observed)]))
    }
  })
  let checkpoint =
    json.object([#("id", json.string(id)), #("delta", delta_json), ..extras])
  Ok(Execution(..state, tree:, checkpoints: [checkpoint, ..state.checkpoints]))
}

fn add_result(
  state: Execution,
  action_id: String,
  name: String,
  change: field.FieldChange,
  extras: List(#(String, Json)),
  table: RevisionTable,
) -> Result(Execution, String) {
  use encoded <- result.try(change_to_json(change, table))
  let checkpoint =
    json.object([
      #("id", json.string(action_id)),
      #("result", encoded),
      ..extras
    ])
  Ok(
    Execution(
      ..state,
      changes: dict.insert(state.changes, name, change),
      result_ids: set.insert(state.result_ids, name),
      checkpoints: [checkpoint, ..state.checkpoints],
    ),
  )
}

fn result_name(
  action: Json,
  state: Execution,
  location: String,
) -> Result(String, String) {
  use name <- result.try(read(action, ["result"], decode.string))
  case string.is_empty(name) || set.contains(state.result_ids, name) {
    True -> Error(location <> ": empty or duplicate result id: " <> name)
    False -> Ok(name)
  }
}

fn change_reference(
  action: Json,
  key: String,
  state: Execution,
  location: String,
) -> Result(field.FieldChange, String) {
  use name <- result.try(read(action, [key], decode.string))
  dict.get(state.changes, name)
  |> result.map_error(fn(_) {
    location <> ": unresolved or forward change reference: " <> name
  })
}

fn initialize_forest(
  input: Json,
  table: RevisionTable,
) -> Result(forest.Forest, String) {
  use fields <- result.try(object_fields(input, "forest"))
  use _ <- result.try(exact_fields_result(
    fields,
    ["schema", "initialRoot", "builds", "detachedRegisters"],
    "forest",
  ))
  use _ <- result.try(validate_forest_schema(input))
  use initial <- result.try(decode_at(
    input,
    ["initialRoot"],
    initial_root_decoder(),
    "forest.initialRoot",
  ))
  use builds <- result.try(decode_at(
    input,
    ["builds"],
    decode.list(forest_build_decoder(table)),
    "forest.builds",
  ))
  use expected <- result.try(decode_at(
    input,
    ["detachedRegisters"],
    decode.list(forest_build_decoder(table)),
    "forest.detachedRegisters",
  ))
  use stored <- result.try(stored_schema())
  use view <- result.try(first_revision(table))
  use tree <- result.try(
    forest.new(view, stored, initial) |> native("forest initial root"),
  )
  use tree <- result.try(apply_builds(tree, builds))
  use actual <- result.try(forest.export_data(tree) |> native("forest builds"))
  let actual =
    list.map(actual.detached, fn(entry) {
      forest.Build(entry.id, [entry.value])
    })
  case actual == expected {
    True -> Ok(tree)
    False -> Error("forest builds do not match initial detached registers")
  }
}

fn validate_forest_schema(input: Json) -> Result(Nil, String) {
  use schema <- result.try(read_json(input, ["schema"]))
  use fields <- result.try(object_fields(schema, "forest.schema"))
  use _ <- result.try(exact_fields_result(
    fields,
    ["rootField", "cardinality", "values"],
    "forest.schema",
  ))
  case
    read(schema, ["rootField"], decode.string),
    read(schema, ["cardinality"], decode.string),
    read(schema, ["values"], decode.string)
  {
    Ok("root"), Ok("optional"), Ok("json-compatible") -> Ok(Nil)
    _, _, _ -> Error("unsupported forest schema")
  }
}

fn apply_builds(
  tree: forest.Forest,
  builds: List(forest.Build),
) -> Result(forest.Forest, String) {
  use delta <- result.try(
    forest.delta(
      forest.DeltaData(
        latest_revision: None,
        fields: [],
        build: builds,
        refreshers: [],
        global: [],
        rename: [],
        destroy: [],
      ),
    )
    |> native("forest builds"),
  )
  forest.apply_delta(tree, delta) |> native("forest builds")
}

fn observe_field_forest(
  tree: forest.Forest,
  table: RevisionTable,
) -> Result(Json, String) {
  use data <- result.try(
    forest.export_data(tree) |> native("forest observation"),
  )
  use detached <- result.try(
    list.try_map(data.detached, fn(entry) {
      use id <- result.try(atom_to_structural_json(entry.id, table))
      Ok(
        json.object([
          #("id", id),
          #("value", tree_value_to_plain_json(entry.value)),
        ]),
      )
    }),
  )
  Ok(
    json.object([
      #(
        "root",
        json.object([
          #("present", json.bool(option.is_some(data.root))),
          #("value", case data.root {
            None -> json.null()
            Some(value) -> tree_value_to_plain_json(value)
          }),
        ]),
      ),
      #("detachedRegisters", array(detached)),
    ]),
  )
}

fn read_detached(
  tree: forest.Forest,
  id: types.AtomId,
) -> Result(types.TreeValue, String) {
  use reference <- result.try(
    forest.locate_detached(tree, id) |> native("detached register"),
  )
  forest.read_node(tree, reference) |> native("detached register")
}

fn field_delta_to_forest(
  delta: field.FieldDelta,
  revision: Option(StableId),
  builds: List(forest.Build),
) -> Result(forest.Delta, String) {
  let fields = case delta.local {
    None -> []
    Some(local) -> [#("rootFieldKey", local)]
  }
  forest.delta(
    forest.DeltaData(
      latest_revision: revision,
      fields:,
      build: builds,
      refreshers: [],
      global: delta.global,
      rename: delta.rename,
      destroy: [],
    ),
  )
  |> native("field delta")
}

fn change_decoder(table: RevisionTable) -> Decoder(field.FieldChange) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  exact_decoder(
    fields,
    ["moves", "childChanges", "replacement"],
    field.empty(),
    {
      use moves <- decode.field("moves", decode.list(atom_pair_decoder(table)))
      use children <- decode.field(
        "childChanges",
        decode.list(child_change_decoder(table)),
      )
      use replacement <- decode.field(
        "replacement",
        decode.optional(replacement_decoder(table)),
      )
      let change = field.FieldChange(moves, children, replacement)
      case field.validate(change) {
        Ok(change) -> decode.success(change)
        Error(_) -> decode.failure(field.empty(), "valid field change")
      }
    },
  )
}

fn legacy_change_decoder(table: RevisionTable) -> Decoder(field.FieldChange) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  let expected = case dict.has_key(fields, "valueReplace") {
    True -> ["moves", "childChanges", "valueReplace"]
    False -> ["moves", "childChanges"]
  }
  exact_decoder(fields, expected, field.empty(), {
    use moves <- decode.field("moves", decode.list(atom_pair_decoder(table)))
    use children <- decode.field(
      "childChanges",
      decode.list(legacy_child_change_decoder(table)),
    )
    use replacement <- decode.optional_field(
      "valueReplace",
      None,
      decode.map(legacy_replacement_decoder(table), Some),
    )
    let change = field.FieldChange(moves, children, replacement)
    case field.validate(change) {
      Ok(change) -> decode.success(change)
      Error(_) -> decode.failure(field.empty(), "valid legacy field change")
    }
  })
}

fn atom_pair_decoder(
  table: RevisionTable,
) -> Decoder(#(types.AtomId, types.AtomId)) {
  use pair <- decode.then(decode.list(decode.dynamic))
  case pair {
    [_, _] -> {
      use first <- decode.field(0, atom_decoder(table))
      use second <- decode.field(1, atom_decoder(table))
      decode.success(#(first, second))
    }
    _ -> decode.failure(#(empty_atom(), empty_atom()), "two atom move")
  }
}

fn child_change_decoder(
  table: RevisionTable,
) -> Decoder(#(field.RegisterId, types.AtomId)) {
  use pair <- decode.then(decode.list(decode.dynamic))
  case pair {
    [_, _] -> {
      use register <- decode.field(0, register_decoder(table))
      use node <- decode.field(1, atom_decoder(table))
      decode.success(#(register, node))
    }
    _ ->
      decode.failure(#(field.Active, empty_atom()), "register and child atom")
  }
}

fn legacy_child_change_decoder(
  table: RevisionTable,
) -> Decoder(#(field.RegisterId, types.AtomId)) {
  use pair <- decode.then(decode.list(decode.dynamic))
  case pair {
    [_, _] -> {
      use register <- decode.field(
        0,
        decode.map(atom_decoder(table), field.Detached),
      )
      use node <- decode.field(1, atom_decoder(table))
      decode.success(#(register, node))
    }
    _ ->
      decode.failure(
        #(field.Active, empty_atom()),
        "detached register and child atom",
      )
  }
}

fn replacement_decoder(table: RevisionTable) -> Decoder(field.Replacement) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  exact_decoder(
    fields,
    ["wasEmpty", "source", "detachId"],
    field.Replacement(True, None, empty_atom()),
    {
      use was_empty <- decode.field("wasEmpty", decode.bool)
      use source <- decode.field(
        "source",
        decode.optional(register_decoder(table)),
      )
      use detach <- decode.field("detachId", atom_decoder(table))
      decode.success(field.Replacement(was_empty, source, detach))
    },
  )
}

fn legacy_replacement_decoder(
  table: RevisionTable,
) -> Decoder(field.Replacement) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  let expected = case dict.has_key(fields, "src") {
    True -> ["isEmpty", "src", "dst"]
    False -> ["isEmpty", "dst"]
  }
  exact_decoder(fields, expected, field.Replacement(True, None, empty_atom()), {
    use was_empty <- decode.field("isEmpty", decode.bool)
    use source <- decode.optional_field(
      "src",
      None,
      decode.map(atom_decoder(table), fn(id) { Some(field.Detached(id)) }),
    )
    use detach <- decode.field("dst", atom_decoder(table))
    decode.success(field.Replacement(was_empty, source, detach))
  })
}

fn register_decoder(table: RevisionTable) -> Decoder(field.RegisterId) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  use kind <- decode.field("kind", decode.string)
  case kind {
    "active" ->
      exact_decoder(
        fields,
        ["kind"],
        field.Active,
        decode.success(field.Active),
      )
    "detached" ->
      exact_decoder(fields, ["kind", "id"], field.Active, {
        use id <- decode.field("id", atom_decoder(table))
        decode.success(field.Detached(id))
      })
    _ -> decode.failure(field.Active, "active or detached register")
  }
}

fn atom_decoder(table: RevisionTable) -> Decoder(types.AtomId) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  exact_decoder(fields, ["revision", "localId"], empty_atom(), {
    use revision <- decode.field("revision", revision_option_decoder(table))
    use local_id <- decode.field("localId", decode.int)
    case local_id >= 0 && local_id <= max_safe_integer {
      True -> decode.success(types.AtomId(revision, local_id))
      False -> decode.failure(empty_atom(), "nonnegative safe atom localId")
    }
  })
}

fn revision_option_decoder(table: RevisionTable) -> Decoder(Option(StableId)) {
  decode.optional(decode.int)
  |> decode.then(fn(value) {
    case value {
      None -> decode.success(None)
      Some(value) ->
        case revision(table, value) {
          Ok(value) -> decode.success(Some(value))
          Error(_) -> decode.failure(None, "mapped numeric revision")
        }
    }
  })
}

fn compose_callback_decoder(table: RevisionTable) -> Decoder(ComposeCallback) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  exact_decoder(
    fields,
    ["input", "over", "result"],
    ComposeCallback(None, None, empty_atom()),
    {
      use input <- decode.field("input", decode.optional(atom_decoder(table)))
      use over <- decode.field("over", decode.optional(atom_decoder(table)))
      use returned <- decode.field("result", atom_decoder(table))
      decode.success(ComposeCallback(input, over, returned))
    },
  )
}

fn rebase_callback_decoder(table: RevisionTable) -> Decoder(RebaseCallback) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  exact_decoder(
    fields,
    ["input", "over", "state", "result"],
    RebaseCallback(None, None, field.Attached, None),
    {
      use input <- decode.field("input", decode.optional(atom_decoder(table)))
      use over <- decode.field("over", decode.optional(atom_decoder(table)))
      use state <- decode.field("state", attach_state_decoder())
      use returned <- decode.field(
        "result",
        decode.optional(atom_decoder(table)),
      )
      decode.success(RebaseCallback(input, over, state, returned))
    },
  )
}

fn attach_state_decoder() -> Decoder(field.AttachState) {
  use state <- decode.then(decode.string)
  case state {
    "attached" -> decode.success(field.Attached)
    "detached" -> decode.success(field.DetachedNode)
    _ -> decode.failure(field.Attached, "attached or detached state")
  }
}

fn child_delta_decoder(
  table: RevisionTable,
) -> Decoder(#(types.AtomId, List(#(String, forest.FieldDelta)))) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  exact_decoder(fields, ["node", "fields"], #(empty_atom(), []), {
    use node <- decode.field("node", atom_decoder(table))
    use fields <- decode.field("fields", field_map_decoder(table))
    decode.success(#(node, fields))
  })
}

fn validate_child_deltas(
  change: field.FieldChange,
  children: List(#(types.AtomId, List(#(String, forest.FieldDelta)))),
  location: String,
) -> Result(Nil, String) {
  let expected = list.map(change.child_changes, fn(child) { child.1 })
  let supplied = list.map(children, fn(child) { child.0 })
  case expected == supplied {
    True -> Ok(Nil)
    False -> Error(location <> ": child delta table does not match callbacks")
  }
}

fn field_map_decoder(
  table: RevisionTable,
) -> Decoder(List(#(String, forest.FieldDelta))) {
  decode.list({
    use pair <- decode.then(decode.list(decode.dynamic))
    case pair {
      [_, _] -> {
        use key <- decode.field(0, decode.string)
        use delta <- decode.field(1, field_delta_decoder(table))
        decode.success(#(key, delta))
      }
      _ ->
        decode.failure(#("", forest.FieldDelta([])), "two-element field entry")
    }
  })
}

fn field_delta_decoder(table: RevisionTable) -> Decoder(forest.FieldDelta) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  exact_decoder(fields, ["marks"], forest.FieldDelta([]), {
    use marks <- decode.field("marks", decode.list(mark_decoder(table)))
    decode.success(forest.FieldDelta(marks))
  })
}

fn mark_decoder(table: RevisionTable) -> Decoder(forest.Mark) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  let allowed = ["count", "attach", "detach", "fields"]
  case list.all(dict.keys(fields), fn(key) { list.contains(allowed, key) }) {
    False ->
      decode.failure(
        forest.Mark(0, None, None, []),
        "mark with supported fields",
      )
    True -> {
      use count <- decode.field("count", decode.int)
      use attach <- decode.optional_field(
        "attach",
        None,
        decode.optional(atom_decoder(table)),
      )
      use detach <- decode.optional_field(
        "detach",
        None,
        decode.optional(atom_decoder(table)),
      )
      use nested <- decode.optional_field(
        "fields",
        [],
        decode.recursive(fn() { field_map_decoder(table) }),
      )
      decode.success(forest.Mark(count, attach, detach, nested))
    }
  }
}

fn initial_root_decoder() -> Decoder(Option(types.TreeValue)) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  exact_decoder(fields, ["present", "value"], None, {
    use present <- decode.field("present", decode.bool)
    use value <- decode.field("value", plain_tree_value_decoder())
    case present {
      True -> decode.success(Some(value))
      False ->
        case value {
          types.NullValue -> decode.success(None)
          _ -> decode.failure(None, "null absent forest root value")
        }
    }
  })
}

fn forest_build_decoder(table: RevisionTable) -> Decoder(forest.Build) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  exact_decoder(fields, ["id", "value"], forest.Build(empty_atom(), []), {
    use id <- decode.field("id", atom_decoder(table))
    use value <- decode.field("value", plain_tree_value_decoder())
    decode.success(forest.Build(id, [value]))
  })
}

fn plain_tree_value_decoder() -> Decoder(types.TreeValue) {
  use value <- decode.then(json_ot.decoder())
  case value {
    VString(value) -> decode.success(types.StringValue(value))
    VBool(value) -> decode.success(types.BooleanValue(value))
    VNumber(value) -> decode.success(types.NumberValue(number_to_float(value)))
    VNull -> decode.success(types.NullValue)
    _ -> decode.failure(types.NullValue, "supported primitive tree value")
  }
}

fn change_to_json(
  change: field.FieldChange,
  table: RevisionTable,
) -> Result(Json, String) {
  use moves <- result.try(
    list.try_map(change.moves, fn(move) {
      use source <- result.try(atom_to_structural_json(move.0, table))
      use destination <- result.try(atom_to_structural_json(move.1, table))
      Ok(array([source, destination]))
    }),
  )
  use children <- result.try(
    list.try_map(change.child_changes, fn(child) {
      use register <- result.try(register_to_json(child.0, table))
      use node <- result.try(atom_to_structural_json(child.1, table))
      Ok(array([register, node]))
    }),
  )
  use replacement <- result.try(case change.replacement {
    None -> Ok(json.null())
    Some(replacement) -> {
      use source <- result.try(case replacement.source {
        None -> Ok(json.null())
        Some(source) -> register_to_json(source, table)
      })
      use detach <- result.try(atom_to_structural_json(
        replacement.detach_id,
        table,
      ))
      Ok(
        json.object([
          #("wasEmpty", json.bool(replacement.was_empty)),
          #("source", source),
          #("detachId", detach),
        ]),
      )
    }
  })
  Ok(
    json.object([
      #("moves", array(moves)),
      #("childChanges", array(children)),
      #("replacement", replacement),
    ]),
  )
}

fn register_to_json(
  register: field.RegisterId,
  table: RevisionTable,
) -> Result(Json, String) {
  case register {
    field.Active -> Ok(json.object([#("kind", json.string("active"))]))
    field.Detached(id) -> {
      use id <- result.try(atom_to_structural_json(id, table))
      Ok(
        json.object([
          #("kind", json.string("detached")),
          #("id", id),
        ]),
      )
    }
  }
}

fn atom_to_structural_json(
  id: types.AtomId,
  table: RevisionTable,
) -> Result(Json, String) {
  use revision <- result.try(case id.revision {
    None -> Ok(json.null())
    Some(revision) -> revision_number(table, revision) |> result.map(json.int)
  })
  Ok(
    json.object([
      #("revision", revision),
      #("localId", json.int(id.local_id)),
    ]),
  )
}

fn field_delta_to_json(
  delta: field.FieldDelta,
  table: RevisionTable,
) -> Result(Json, String) {
  use local <- result.try(case delta.local {
    None -> Ok(json.null())
    Some(local) -> forest_field_delta_to_json(local, table)
  })
  use global <- result.try(
    list.try_map(delta.global, fn(change) {
      use id <- result.try(atom_to_structural_json(change.id, table))
      use fields <- result.try(field_map_to_json(change.fields, table))
      Ok(json.object([#("id", id), #("fields", fields)]))
    }),
  )
  use rename <- result.try(
    list.try_map(delta.rename, fn(rename) {
      use old <- result.try(atom_to_structural_json(rename.old_id, table))
      use new <- result.try(atom_to_structural_json(rename.new_id, table))
      Ok(
        json.object([
          #("oldId", old),
          #("newId", new),
          #("count", json.int(rename.count)),
        ]),
      )
    }),
  )
  Ok(
    json.object([
      #("local", local),
      #("global", array(global)),
      #("rename", array(rename)),
    ]),
  )
}

fn field_map_to_json(
  fields: List(#(String, forest.FieldDelta)),
  table: RevisionTable,
) -> Result(Json, String) {
  use fields <- result.try(
    list.try_map(fields, fn(entry) {
      use delta <- result.try(forest_field_delta_to_json(entry.1, table))
      Ok(array([json.string(entry.0), delta]))
    }),
  )
  Ok(array(fields))
}

fn forest_field_delta_to_json(
  delta: forest.FieldDelta,
  table: RevisionTable,
) -> Result(Json, String) {
  use marks <- result.try(list.try_map(delta.marks, mark_to_json(_, table)))
  Ok(json.object([#("marks", array(marks))]))
}

fn mark_to_json(
  mark: forest.Mark,
  table: RevisionTable,
) -> Result(Json, String) {
  use attach <- result.try(optional_atom_to_json(mark.attach, table))
  use detach <- result.try(optional_atom_to_json(mark.detach, table))
  use fields <- result.try(field_map_to_json(mark.fields, table))
  let full =
    json.object([
      #("count", json.int(mark.count)),
      #("attach", attach),
      #("detach", detach),
      #("fields", fields),
    ])
  case
    mark.attach == None && mark.detach == None && list.is_empty(mark.fields)
  {
    True -> Ok(json.object([#("count", json.int(mark.count))]))
    False -> Ok(full)
  }
}

fn optional_atom_to_json(
  id: Option(types.AtomId),
  table: RevisionTable,
) -> Result(Json, String) {
  case id {
    None -> Ok(json.null())
    Some(id) -> atom_to_structural_json(id, table)
  }
}

fn compose_callback_to_json(
  callback: ComposeCallback,
  table: RevisionTable,
) -> Result(Json, String) {
  use input <- result.try(optional_atom_to_json(callback.input, table))
  use over <- result.try(optional_atom_to_json(callback.over, table))
  use returned <- result.try(atom_to_structural_json(callback.returned, table))
  Ok(
    json.object([
      #("input", input),
      #("over", over),
      #("result", returned),
    ]),
  )
}

fn rebase_callback_to_json(
  callback: RebaseCallback,
  table: RevisionTable,
) -> Result(Json, String) {
  use input <- result.try(optional_atom_to_json(callback.input, table))
  use over <- result.try(optional_atom_to_json(callback.over, table))
  use returned <- result.try(optional_atom_to_json(callback.returned, table))
  let state = case callback.state {
    field.Attached -> "attached"
    field.DetachedNode -> "detached"
  }
  Ok(
    json.object([
      #("input", input),
      #("over", over),
      #("state", json.string(state)),
      #("result", returned),
    ]),
  )
}

fn v2_change(
  input: Json,
  current_revision: Option(StableId),
  table: RevisionTable,
) -> Result(field.FieldChange, String) {
  use fields <- result.try(object_fields(input, "V2 field change"))
  use _ <- result.try(
    case
      list.all(dict.keys(fields), fn(key) {
        list.contains(["m", "c", "r"], key)
      })
    {
      True -> Ok(Nil)
      False -> Error("V2 field change has an unknown property")
    },
  )
  use moves <- result.try(case dict.has_key(fields, "m") {
    False -> Ok([])
    True ->
      decode_at(
        input,
        ["m"],
        decode.list(v2_move_decoder(current_revision, table)),
        "V2 moves",
      )
  })
  use children <- result.try(case dict.has_key(fields, "c") {
    False -> Ok([])
    True -> Error("V2 child content is not supported by this field fixture")
  })
  use replacement <- result.try(case dict.has_key(fields, "r") {
    False -> Ok(None)
    True ->
      decode_at(
        input,
        ["r"],
        v2_replacement_decoder(current_revision, table),
        "V2 replacement",
      )
      |> result.map(Some)
  })
  let change = field.FieldChange(moves, children, replacement)
  field.validate(change) |> native("V2 field change")
}

fn v2_move_decoder(
  current_revision: Option(StableId),
  table: RevisionTable,
) -> Decoder(#(types.AtomId, types.AtomId)) {
  use pair <- decode.then(decode.list(json_ot.decoder()))
  case pair {
    [first, second] ->
      case
        v2_atom(first, current_revision, table),
        v2_atom(second, current_revision, table)
      {
        Ok(first), Ok(second) -> decode.success(#(first, second))
        _, _ -> decode.failure(#(empty_atom(), empty_atom()), "valid V2 atoms")
      }
    _ -> decode.failure(#(empty_atom(), empty_atom()), "two V2 atoms")
  }
}

fn v2_replacement_decoder(
  current_revision: Option(StableId),
  table: RevisionTable,
) -> Decoder(field.Replacement) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  case
    list.all(dict.keys(fields), fn(key) { list.contains(["e", "s", "d"], key) })
    && dict.has_key(fields, "e")
    && dict.has_key(fields, "d")
  {
    False ->
      decode.failure(
        field.Replacement(True, None, empty_atom()),
        "V2 replacement fields",
      )
    True -> {
      use was_empty <- decode.field("e", decode.bool)
      use detach_value <- decode.field("d", json_ot.decoder())
      case v2_atom(detach_value, current_revision, table) {
        Error(_) ->
          decode.failure(
            field.Replacement(True, None, empty_atom()),
            "valid V2 detach atom",
          )
        Ok(detach) -> {
          use source <- decode.then(case dict.has_key(fields, "s") {
            False -> decode.success(None)
            True -> {
              use value <- decode.field("s", json_ot.decoder())
              case value {
                VNull -> decode.success(Some(field.Active))
                _ ->
                  case v2_atom(value, current_revision, table) {
                    Ok(id) -> decode.success(Some(field.Detached(id)))
                    Error(_) -> decode.failure(None, "valid V2 source atom")
                  }
              }
            }
          })
          decode.success(field.Replacement(was_empty, source, detach))
        }
      }
    }
  }
}

fn v2_atom(
  value: JsonValue,
  current_revision: Option(StableId),
  table: RevisionTable,
) -> Result(types.AtomId, String) {
  case value {
    VNumber(number) -> {
      use local <- result.try(number_to_int(number))
      valid_atom(current_revision, local)
    }
    json_ot.VArray([VNumber(local), VNumber(revision_number)]) -> {
      use local <- result.try(number_to_int(local))
      use revision_number <- result.try(number_to_int(revision_number))
      use revision <- result.try(revision(table, revision_number))
      valid_atom(Some(revision), local)
    }
    _ -> Error("invalid V2 atom encoding")
  }
}

fn v2_encode(
  change: field.FieldChange,
  current_revision: Option(StableId),
  table: RevisionTable,
) -> Result(Json, String) {
  use moves <- result.try(
    list.try_map(change.moves, fn(move) {
      use source <- result.try(v2_atom_to_json(move.0, current_revision, table))
      use destination <- result.try(v2_atom_to_json(
        move.1,
        current_revision,
        table,
      ))
      Ok(array([source, destination]))
    }),
  )
  use replacement <- result.try(case change.replacement {
    None -> Ok(None)
    Some(replacement) -> {
      use detach <- result.try(v2_atom_to_json(
        replacement.detach_id,
        current_revision,
        table,
      ))
      use source <- result.try(case replacement.source {
        None -> Ok(None)
        Some(field.Active) -> Ok(Some(json.null()))
        Some(field.Detached(id)) ->
          v2_atom_to_json(id, current_revision, table) |> result.map(Some)
      })
      let fields = [
        #("e", json.bool(replacement.was_empty)),
        #("d", detach),
      ]
      let fields = case source {
        None -> fields
        Some(source) -> [
          #("e", json.bool(replacement.was_empty)),
          #("d", detach),
          #("s", source),
        ]
      }
      Ok(Some(json.object(fields)))
    }
  })
  let fields = []
  let fields = case list.is_empty(moves) {
    True -> fields
    False -> list.append(fields, [#("m", array(moves))])
  }
  let fields = case change.child_changes {
    [] -> fields
    [_, ..] -> fields
  }
  let fields = case replacement {
    None -> fields
    Some(replacement) -> list.append(fields, [#("r", replacement)])
  }
  Ok(json.object(fields))
}

fn v2_atom_to_json(
  id: types.AtomId,
  current_revision: Option(StableId),
  table: RevisionTable,
) -> Result(Json, String) {
  case id.revision == current_revision {
    True -> Ok(json.int(id.local_id))
    False -> {
      use revision <- result.try(case id.revision {
        None -> Error("anonymous V2 atom outside its encoding revision")
        Some(revision) -> revision_number(table, revision)
      })
      Ok(array([json.int(id.local_id), json.int(revision)]))
    }
  }
}

fn operation_encoded(operation: String, encoded: Json) -> Json {
  json.object([
    #("operation", json.string(operation)),
    #("encoded", encoded),
  ])
}

fn revision(table: RevisionTable, value: Int) -> Result(StableId, String) {
  table.entries
  |> list.key_find(value)
  |> result.map_error(fn(_) {
    "numeric revision is absent from revisionTable: " <> int.to_string(value)
  })
}

fn revision_number(
  table: RevisionTable,
  value: StableId,
) -> Result(Int, String) {
  case list.find(table.entries, fn(entry) { entry.1 == value }) {
    Ok(entry) -> Ok(entry.0)
    Error(Nil) -> Error("stable revision is absent from revisionTable")
  }
}

fn first_revision(table: RevisionTable) -> Result(StableId, String) {
  case table.entries {
    [entry, ..] -> Ok(entry.1)
    [] -> Error("revisionTable is empty")
  }
}

fn stored_schema() -> Result(schema.StoredSchema, String) {
  schema.stored_from_string(optional_schema)
  |> result.map_error(fn(error) {
    "invalid field fixture schema: " <> string.inspect(error)
  })
}

fn valid_atom(
  revision: Option(StableId),
  local_id: Int,
) -> Result(types.AtomId, String) {
  case local_id >= 0 && local_id <= max_safe_integer {
    True -> Ok(types.AtomId(revision, local_id))
    False -> Error("atom localId is outside the safe nonnegative range")
  }
}

fn number_to_int(number: json_ot.Number) -> Result(Int, String) {
  case number {
    json_ot.NInt(value) -> Ok(value)
    json_ot.NFloat(_) -> Error("V2 atom identifier must be an integer")
  }
}

fn number_to_float(number: json_ot.Number) -> Float {
  case number {
    json_ot.NInt(value) -> int.to_float(value)
    json_ot.NFloat(value) -> value
  }
}

fn empty_atom() -> types.AtomId {
  types.AtomId(None, 0)
}

fn empty_stable() -> StableId {
  let assert Ok(value) =
    fluid_ids.stable_id("00000000-0000-4000-8000-000000000000")
  value
}

fn unexpected_compose(
  _: Option(types.AtomId),
  _: Option(types.AtomId),
  _: Nil,
) -> Result(#(types.AtomId, Nil), types.TreeError) {
  Error(types.CorruptData(
    "fixture.original.compose",
    "Unexpected child callback",
  ))
}

fn unexpected_rebase(
  _: Option(types.AtomId),
  _: Option(types.AtomId),
  _: field.AttachState,
  _: Nil,
) -> Result(#(Option(types.AtomId), Nil), types.TreeError) {
  Error(types.CorruptData(
    "fixture.original.rebase",
    "Unexpected child callback",
  ))
}

fn unexpected_child_delta(
  _: types.AtomId,
) -> Result(List(#(String, forest.FieldDelta)), types.TreeError) {
  Error(types.CorruptData("fixture.original.delta", "Unexpected child callback"))
}

fn native(
  value: Result(a, types.TreeError),
  location: String,
) -> Result(a, String) {
  value
  |> result.map_error(fn(error) {
    location <> ": native field error: " <> string.inspect(error)
  })
}

fn exact_action(
  fields: Dict(String, Dynamic),
  expected: List(String),
  location: String,
) -> Result(Nil, String) {
  exact_fields_result(fields, expected, location <> " action")
}

fn exact_fields_result(
  fields: Dict(String, Dynamic),
  expected: List(String),
  location: String,
) -> Result(Nil, String) {
  case exact_fields(fields, expected) {
    True -> Ok(Nil)
    False -> Error(location <> " must contain exact supported fields")
  }
}

fn exact_decoder(
  fields: Dict(String, Dynamic),
  expected: List(String),
  placeholder: a,
  decoder: Decoder(a),
) -> Decoder(a) {
  case exact_fields(fields, expected) {
    True -> decoder
    False -> decode.failure(placeholder, "object with exact fields")
  }
}

fn exact_fields(fields: Dict(String, Dynamic), expected: List(String)) -> Bool {
  dict.size(fields) == list.length(expected)
  && list.all(expected, fn(field) { dict.has_key(fields, field) })
}

fn object_fields(
  input: Json,
  location: String,
) -> Result(Dict(String, Dynamic), String) {
  json.parse(json.to_string(input), decode.dict(decode.string, decode.dynamic))
  |> result.map_error(fn(error) {
    location <> " must be an object: " <> string.inspect(error)
  })
}

fn read(
  input: Json,
  path: List(String),
  decoder: Decoder(a),
) -> Result(a, String) {
  json.parse(json.to_string(input), decode.at(path, decoder))
  |> result.map_error(fn(error) {
    "invalid field input at "
    <> string.join(path, ".")
    <> ": "
    <> string.inspect(error)
  })
}

fn read_json(input: Json, path: List(String)) -> Result(Json, String) {
  read(input, path, json_ot.decoder()) |> result.map(json_ot.to_json)
}

fn decode_at(
  input: Json,
  path: List(String),
  decoder: Decoder(a),
  location: String,
) -> Result(a, String) {
  json.parse(json.to_string(input), decode.at(path, decoder))
  |> decode_error(location)
}

fn decode_error(
  value: Result(a, json.DecodeError),
  location: String,
) -> Result(a, String) {
  value
  |> result.map_error(fn(error) { location <> ": " <> string.inspect(error) })
}

fn json_decoder() -> Decoder(Json) {
  decode.map(json_ot.decoder(), json_ot.to_json)
}

fn tree_value_to_plain_json(value: types.TreeValue) -> Json {
  case value {
    types.StringValue(value) -> json.string(value)
    types.NumberValue(value) -> json.float(value)
    types.BooleanValue(value) -> json.bool(value)
    types.NullValue -> json.null()
    types.ObjectValue(_, _) -> json.null()
  }
}

fn array(values: List(Json)) -> Json {
  json.array(values, fn(value) { value })
}
