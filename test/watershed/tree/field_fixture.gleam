import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode.{type Decoder}
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import watershed/fluid_ids.{type StableId}
import watershed/tree/forest
import watershed/tree/optional_field
import watershed/tree/schema
import watershed/tree/types.{
  type AtomId, type TreeError, AtomId, CorruptData, StringValue,
}

const max_safe_integer = 9_007_199_254_740_991

const string_schema = "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.string\":{\"kind\":{\"leaf\":1}}},\"root\":{\"kind\":\"Optional\",\"types\":[\"com.fluidframework.leaf.string\"]}}"

type Revisions {
  Revisions(first: Int, second: Int, inverse: Int, replacement: Int)
}

type NamedChanges {
  NamedChanges(
    optional: optional_field.FieldChange,
    required: optional_field.FieldChange,
    swap: optional_field.FieldChange,
  )
}

type ComposeOperation {
  ComposeOperation(
    left: String,
    right: String,
    metadata_revisions: List(Int),
    metadata_base: Int,
    rollback_revisions: List(Int),
  )
}

type InvertOperation {
  InvertOperation(change: String, is_rollback: Bool, inverse_revision: Int)
}

type RebaseOperation {
  RebaseOperation(change: String, over: String)
}

type ReplaceOperation {
  ReplaceOperation(change: String, obsolete: List(Int), updated: Int)
}

type Operations {
  Operations(
    compose: ComposeOperation,
    invert: InvertOperation,
    rebase: RebaseOperation,
    replace_revisions: ReplaceOperation,
  )
}

type SwapRegister {
  SwapRegister(id: AtomId, content: String)
}

type SwapApplication {
  SwapApplication(
    operation: String,
    revision: Int,
    registers: List(SwapRegister),
  )
}

type SwapAlgebra {
  SwapAlgebra(
    operation: String,
    change: optional_field.FieldChange,
    over: optional_field.FieldChange,
  )
}

type Input {
  Input(
    revisions: Revisions,
    changes: NamedChanges,
    operations: Operations,
    swap_application: SwapApplication,
    swap_algebra: SwapAlgebra,
    expanded: Option(Dynamic),
  )
}

type EncodedInput {
  EncodedInput(revision: Int, change: optional_field.FieldChange)
}

type ChildCallback {
  PreferFirstThenSecond
  PreferChangeThenBase
  Constant(AtomId)
}

type ExpandedCompose {
  ExpandedCompose(
    id: String,
    first: EncodedInput,
    second: EncodedInput,
    output_revision: Int,
    callback: ChildCallback,
  )
}

type ExpandedInvert {
  ExpandedInvert(
    id: String,
    change: EncodedInput,
    is_rollback: Bool,
    inverse_revision: Int,
    max_local_id: Int,
  )
}

type ExpandedRebase {
  ExpandedRebase(
    id: String,
    change: EncodedInput,
    over: EncodedInput,
    output_revision: Int,
    callback: ChildCallback,
  )
}

type ExpandedDelta {
  ExpandedDelta(change: EncodedInput, field: String)
}

type ExpandedReplace {
  ExpandedReplace(
    id: String,
    change: EncodedInput,
    obsolete: List(Int),
    updated: Int,
    output_revision: Int,
  )
}

type InvalidMapping {
  InvalidMapping(id: String, change: optional_field.FieldChange)
}

type Expanded {
  Expanded(
    changes: Dict(String, EncodedInput),
    compose: List(ExpandedCompose),
    invert: List(ExpandedInvert),
    rebase: List(ExpandedRebase),
    into_delta: ExpandedDelta,
    replace_revisions: ExpandedReplace,
    invalid_mappings: List(InvalidMapping),
  )
}

pub fn run(input: Json) -> Result(Json, String) {
  use input <- result.try(
    json.parse(json.to_string(input), input_decoder())
    |> result.map_error(fn(error) {
      "invalid field fixture: " <> string.inspect(error)
    }),
  )
  use _ <- result.try(validate_revisions(input.revisions))
  use _ <- result.try(validate_operations(input))
  use #(composed, _) <- result.try(
    tree_result(
      optional_field.compose(
        named_change(input.changes, input.operations.compose.left),
        named_change(input.changes, input.operations.compose.right),
        Nil,
        fn(left, right, state) {
          case left, right {
            Some(id), _ | None, Some(id) -> Ok(#(id, state))
            None, None ->
              Error(CorruptData("field fixture", "child change is missing"))
          }
        },
      ),
    ),
  )
  use #(inverted, _) <- result.try(
    tree_result(optional_field.invert(
      select_change(input.operations.invert.change, input.changes, composed),
      input.operations.invert.is_rollback,
      Some(revision_id(input.operations.invert.inverse_revision)),
      -1,
    )),
  )
  use #(rebased, _) <- result.try(
    tree_result(
      optional_field.rebase(
        named_change(input.changes, input.operations.rebase.change),
        named_change(input.changes, input.operations.rebase.over),
        Nil,
        fn(change, over, _, state) {
          Ok(#(
            case change {
              Some(_) -> change
              None -> over
            },
            state,
          ))
        },
      ),
    ),
  )
  use replaced <- result.try(
    tree_result(
      optional_field.replace_revisions(
        named_change(input.changes, input.operations.replace_revisions.change),
        fn(id) {
          case revision_number(id.revision) {
            Ok(revision) ->
              case
                list.contains(
                  input.operations.replace_revisions.obsolete,
                  revision,
                )
              {
                True ->
                  Ok(AtomId(
                    Some(revision_id(input.operations.replace_revisions.updated)),
                    id.local_id,
                  ))
                False -> Ok(id)
              }
            Error(detail) ->
              Error(CorruptData("field fixture revision", detail))
          }
        },
      ),
    ),
  )
  use swap_refusal <- result.try(run_swap_application(
    input.swap_application,
    input.changes.swap,
  ))
  use swap_mapping <- result.try(run_swap_algebra(input.swap_algebra))
  use _optional <- result.try(encode_change(
    input.changes.optional,
    input.revisions.first,
  ))
  use _required <- result.try(encode_change(
    input.changes.required,
    input.revisions.second,
  ))
  use compose <- result.try(encode_change(composed, input.revisions.second))
  use invert <- result.try(encode_change(inverted, input.revisions.inverse))
  use rebase <- result.try(encode_change(rebased, input.revisions.second))
  use swap <- result.try(encode_change(
    input.changes.swap,
    input.revisions.first,
  ))
  use replaced <- result.try(encode_change(
    replaced,
    input.revisions.replacement,
  ))
  let observations = [
    observation("compose", compose),
    observation("invert", invert),
    observation("rebase", rebase),
    observation("simultaneous-swap", swap),
    swap_refusal,
    swap_mapping,
    observation("replace-revisions", replaced),
  ]
  case input.expanded {
    None -> Ok(observations)
    Some(expanded) -> {
      use expanded <- result.try(
        decode.run(expanded, expanded_decoder())
        |> result.map_error(fn(error) {
          "invalid expanded field fixture: " <> string.inspect(error)
        }),
      )
      use expanded_observations <- result.try(run_expanded(
        expanded,
        input.revisions,
      ))
      Ok(list.append(observations, expanded_observations))
    }
  }
  |> result.map(fn(observations) {
    json.object([
      #("observations", json.array(observations, fn(value) { value })),
    ])
  })
}

fn input_decoder() -> Decoder(Input) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  use revisions <- decode.field("revisions", revisions_decoder())
  exact_decoder(
    fields,
    case dict.has_key(fields, "expanded") {
      True -> [
        "codecs",
        "revisions",
        "changes",
        "operations",
        "expanded",
        "swapApplication",
        "swapAlgebra",
      ]
      False -> [
        "codecs",
        "revisions",
        "changes",
        "operations",
        "swapApplication",
        "swapAlgebra",
      ]
    },
    Input(
      revisions,
      NamedChanges(
        optional_field.FieldChange([], [], None),
        optional_field.FieldChange([], [], None),
        optional_field.FieldChange([], [], None),
      ),
      Operations(
        ComposeOperation("", "", [], 0, []),
        InvertOperation("", False, 0),
        RebaseOperation("", ""),
        ReplaceOperation("", [], 0),
      ),
      SwapApplication("", 0, []),
      SwapAlgebra(
        "",
        optional_field.FieldChange([], [], None),
        optional_field.FieldChange([], [], None),
      ),
      None,
    ),
    {
      use _ <- decode.field("codecs", codecs_decoder())
      use changes <- decode.field("changes", changes_decoder(revisions))
      use operations <- decode.field("operations", operations_decoder())
      use swap_application <- decode.field(
        "swapApplication",
        swap_application_decoder(),
      )
      use swap_algebra <- decode.field("swapAlgebra", swap_algebra_decoder())
      use expanded <- decode.optional_field(
        "expanded",
        None,
        decode.dynamic |> decode.map(Some),
      )
      decode.success(Input(
        revisions,
        changes,
        operations,
        swap_application,
        swap_algebra,
        expanded,
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
      False -> decode.failure(Nil, "field codec version 2")
    }
  })
}

fn expanded_decoder() -> Decoder(Expanded) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  exact_decoder(
    fields,
    [
      "changes",
      "compose",
      "invert",
      "rebase",
      "intoDelta",
      "replaceRevisions",
      "invalidMappings",
    ],
    Expanded(
      dict.new(),
      [],
      [],
      [],
      ExpandedDelta(
        EncodedInput(0, optional_field.FieldChange([], [], None)),
        "",
      ),
      ExpandedReplace(
        "",
        EncodedInput(0, optional_field.FieldChange([], [], None)),
        [],
        0,
        0,
      ),
      [],
    ),
    {
      use changes <- decode.field(
        "changes",
        decode.dict(decode.string, encoded_input_decoder()),
      )
      use compose <- decode.field(
        "compose",
        decode.list(expanded_compose_decoder()),
      )
      use invert <- decode.field(
        "invert",
        decode.list(expanded_invert_decoder()),
      )
      use rebase <- decode.field(
        "rebase",
        decode.list(expanded_rebase_decoder()),
      )
      use into_delta <- decode.field("intoDelta", expanded_delta_decoder())
      use replace <- decode.field(
        "replaceRevisions",
        expanded_replace_decoder(),
      )
      use invalid <- decode.field(
        "invalidMappings",
        decode.list(invalid_mapping_decoder()),
      )
      decode.success(Expanded(
        changes,
        compose,
        invert,
        rebase,
        into_delta,
        replace,
        invalid,
      ))
    },
  )
}

fn encoded_input_decoder() -> Decoder(EncodedInput) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  use revision <- decode.field("revision", revision_number_decoder())
  exact_decoder(
    fields,
    ["revision", "data"],
    EncodedInput(0, optional_field.FieldChange([], [], None)),
    {
      use change <- decode.field("data", change_decoder(revision))
      decode.success(EncodedInput(revision, change))
    },
  )
}

fn expanded_compose_decoder() -> Decoder(ExpandedCompose) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  exact_decoder(
    fields,
    ["id", "first", "second", "outputRevision", "childCallback"],
    ExpandedCompose(
      "",
      EncodedInput(0, optional_field.FieldChange([], [], None)),
      EncodedInput(0, optional_field.FieldChange([], [], None)),
      0,
      PreferFirstThenSecond,
    ),
    {
      use id <- decode.field("id", decode.string)
      use first <- decode.field("first", encoded_input_decoder())
      use second <- decode.field("second", encoded_input_decoder())
      use output <- decode.field("outputRevision", revision_number_decoder())
      use callback <- decode.field("childCallback", compose_callback_decoder())
      decode.success(ExpandedCompose(id, first, second, output, callback))
    },
  )
}

fn expanded_invert_decoder() -> Decoder(ExpandedInvert) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  exact_decoder(
    fields,
    [
      "id",
      "change",
      "isRollback",
      "inverseRevision",
      "maxLocalId",
    ],
    ExpandedInvert(
      "",
      EncodedInput(0, optional_field.FieldChange([], [], None)),
      False,
      0,
      -1,
    ),
    {
      use id <- decode.field("id", decode.string)
      use change <- decode.field("change", encoded_input_decoder())
      use rollback <- decode.field("isRollback", decode.bool)
      use inverse <- decode.field("inverseRevision", revision_number_decoder())
      use max_local_id <- decode.field("maxLocalId", decode.int)
      decode.success(ExpandedInvert(id, change, rollback, inverse, max_local_id))
    },
  )
}

fn expanded_rebase_decoder() -> Decoder(ExpandedRebase) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  exact_decoder(
    fields,
    ["id", "change", "over", "outputRevision", "childCallback"],
    ExpandedRebase(
      "",
      EncodedInput(0, optional_field.FieldChange([], [], None)),
      EncodedInput(0, optional_field.FieldChange([], [], None)),
      0,
      PreferChangeThenBase,
    ),
    {
      use id <- decode.field("id", decode.string)
      use change <- decode.field("change", encoded_input_decoder())
      use over <- decode.field("over", encoded_input_decoder())
      use output <- decode.field("outputRevision", revision_number_decoder())
      use callback <- decode.field("childCallback", rebase_callback_decoder())
      decode.success(ExpandedRebase(id, change, over, output, callback))
    },
  )
}

fn expanded_delta_decoder() -> Decoder(ExpandedDelta) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  exact_decoder(
    fields,
    ["change", "childDelta"],
    ExpandedDelta(EncodedInput(0, optional_field.FieldChange([], [], None)), ""),
    {
      use change <- decode.field("change", encoded_input_decoder())
      use field <- decode.field("childDelta", child_delta_decoder())
      decode.success(ExpandedDelta(change, field))
    },
  )
}

fn child_delta_decoder() -> Decoder(String) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  exact_decoder(fields, ["selector", "field"], "", {
    use selector <- decode.field("selector", decode.string)
    use field <- decode.field("field", decode.string)
    case selector {
      "local-id-count" -> decode.success(field)
      _ -> decode.failure("", "known child delta selector")
    }
  })
}

fn expanded_replace_decoder() -> Decoder(ExpandedReplace) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  exact_decoder(
    fields,
    ["id", "change", "obsolete", "updated", "outputRevision"],
    ExpandedReplace(
      "",
      EncodedInput(0, optional_field.FieldChange([], [], None)),
      [],
      0,
      0,
    ),
    {
      use id <- decode.field("id", decode.string)
      use change <- decode.field("change", encoded_input_decoder())
      use obsolete <- decode.field(
        "obsolete",
        decode.list(revision_number_decoder()),
      )
      use updated <- decode.field("updated", revision_number_decoder())
      use output <- decode.field("outputRevision", revision_number_decoder())
      decode.success(ExpandedReplace(id, change, obsolete, updated, output))
    },
  )
}

fn invalid_mapping_decoder() -> Decoder(InvalidMapping) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  exact_decoder(
    fields,
    ["id", "change"],
    InvalidMapping("", optional_field.FieldChange([], [], None)),
    {
      use id <- decode.field("id", decode.string)
      use change <- decode.field("change", raw_change_decoder())
      decode.success(InvalidMapping(id, change))
    },
  )
}

fn compose_callback_decoder() -> Decoder(ChildCallback) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  use selector <- decode.field("selector", decode.string)
  case selector {
    "prefer-first-then-second" ->
      exact_decoder(
        fields,
        ["selector"],
        PreferFirstThenSecond,
        decode.success(PreferFirstThenSecond),
      )
    "constant" ->
      exact_decoder(fields, ["selector", "result"], PreferFirstThenSecond, {
        use id <- decode.field("result", raw_atom_decoder())
        decode.success(Constant(id))
      })
    _ -> decode.failure(PreferFirstThenSecond, "known compose callback")
  }
}

fn rebase_callback_decoder() -> Decoder(ChildCallback) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  exact_decoder(fields, ["selector"], PreferChangeThenBase, {
    use selector <- decode.field("selector", decode.string)
    case selector {
      "prefer-change-then-base" -> decode.success(PreferChangeThenBase)
      _ -> decode.failure(PreferChangeThenBase, "known rebase callback")
    }
  })
}

fn revisions_decoder() -> Decoder(Revisions) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  exact_decoder(
    fields,
    ["first", "second", "inverse", "replacement"],
    Revisions(0, 0, 0, 0),
    {
      use first <- decode.field("first", revision_number_decoder())
      use second <- decode.field("second", revision_number_decoder())
      use inverse <- decode.field("inverse", revision_number_decoder())
      use replacement <- decode.field("replacement", revision_number_decoder())
      decode.success(Revisions(first, second, inverse, replacement))
    },
  )
}

fn changes_decoder(revisions: Revisions) -> Decoder(NamedChanges) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  exact_decoder(
    fields,
    ["optional", "required", "swap"],
    NamedChanges(
      optional_field.FieldChange([], [], None),
      optional_field.FieldChange([], [], None),
      optional_field.FieldChange([], [], None),
    ),
    {
      use optional <- decode.field("optional", change_decoder(revisions.first))
      use required <- decode.field("required", change_decoder(revisions.second))
      use swap <- decode.field("swap", change_decoder(revisions.first))
      decode.success(NamedChanges(optional, required, swap))
    },
  )
}

fn operations_decoder() -> Decoder(Operations) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  exact_decoder(
    fields,
    ["compose", "invert", "rebase", "replaceRevisions"],
    Operations(
      ComposeOperation("", "", [], 0, []),
      InvertOperation("", False, 0),
      RebaseOperation("", ""),
      ReplaceOperation("", [], 0),
    ),
    {
      use compose <- decode.field("compose", compose_operation_decoder())
      use invert <- decode.field("invert", invert_operation_decoder())
      use rebase <- decode.field("rebase", rebase_operation_decoder())
      use replace <- decode.field(
        "replaceRevisions",
        replace_operation_decoder(),
      )
      decode.success(Operations(compose, invert, rebase, replace))
    },
  )
}

fn compose_operation_decoder() -> Decoder(ComposeOperation) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  exact_decoder(
    fields,
    ["left", "right", "revisionMetadata"],
    ComposeOperation("", "", [], 0, []),
    {
      use left <- decode.field("left", decode.string)
      use right <- decode.field("right", decode.string)
      use metadata <- decode.field(
        "revisionMetadata",
        revision_metadata_decoder(),
      )
      decode.success(ComposeOperation(
        left,
        right,
        metadata.0,
        metadata.1,
        metadata.2,
      ))
    },
  )
}

fn revision_metadata_decoder() -> Decoder(#(List(Int), Int, List(Int))) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  exact_decoder(
    fields,
    ["revisions", "base", "rollbackRevisions"],
    #([], 0, []),
    {
      use revisions <- decode.field(
        "revisions",
        decode.list(revision_number_decoder()),
      )
      use base <- decode.field("base", revision_number_decoder())
      use rollbacks <- decode.field(
        "rollbackRevisions",
        decode.list(revision_number_decoder()),
      )
      decode.success(#(revisions, base, rollbacks))
    },
  )
}

fn invert_operation_decoder() -> Decoder(InvertOperation) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  exact_decoder(
    fields,
    ["change", "isRollback", "inverseRevision"],
    InvertOperation("", False, 0),
    {
      use change <- decode.field("change", decode.string)
      use rollback <- decode.field("isRollback", decode.bool)
      use revision <- decode.field("inverseRevision", revision_number_decoder())
      decode.success(InvertOperation(change, rollback, revision))
    },
  )
}

fn rebase_operation_decoder() -> Decoder(RebaseOperation) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  exact_decoder(fields, ["change", "over"], RebaseOperation("", ""), {
    use change <- decode.field("change", decode.string)
    use over <- decode.field("over", decode.string)
    decode.success(RebaseOperation(change, over))
  })
}

fn replace_operation_decoder() -> Decoder(ReplaceOperation) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  exact_decoder(
    fields,
    ["change", "obsolete", "updated"],
    ReplaceOperation("", [], 0),
    {
      use change <- decode.field("change", decode.string)
      use obsolete <- decode.field(
        "obsolete",
        decode.list(revision_number_decoder()),
      )
      use updated <- decode.field("updated", revision_number_decoder())
      decode.success(ReplaceOperation(change, obsolete, updated))
    },
  )
}

fn swap_application_decoder() -> Decoder(SwapApplication) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  exact_decoder(
    fields,
    ["operation", "revision", "registers"],
    SwapApplication("", 0, []),
    {
      use operation <- decode.field("operation", decode.string)
      use revision <- decode.field("revision", revision_number_decoder())
      use registers <- decode.field(
        "registers",
        decode.list(swap_register_decoder()),
      )
      decode.success(SwapApplication(operation, revision, registers))
    },
  )
}

fn swap_register_decoder() -> Decoder(SwapRegister) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  exact_decoder(fields, ["id", "content"], SwapRegister(AtomId(None, 0), ""), {
    use id <- decode.field("id", raw_atom_decoder())
    use content <- decode.field("content", decode.string)
    decode.success(SwapRegister(id, content))
  })
}

fn swap_algebra_decoder() -> Decoder(SwapAlgebra) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  exact_decoder(
    fields,
    ["operation", "change", "over"],
    SwapAlgebra(
      "",
      optional_field.FieldChange([], [], None),
      optional_field.FieldChange([], [], None),
    ),
    {
      use operation <- decode.field("operation", decode.string)
      use change <- decode.field("change", raw_change_decoder())
      use over <- decode.field("over", raw_change_decoder())
      decode.success(SwapAlgebra(operation, change, over))
    },
  )
}

fn change_decoder(
  context_revision: Int,
) -> Decoder(optional_field.FieldChange) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  case only_fields(fields, ["m", "c", "r"]) {
    False ->
      decode.failure(
        optional_field.FieldChange([], [], None),
        "optional field V2 change",
      )
    True -> {
      use moves <- decode.optional_field(
        "m",
        [],
        decode.list(move_decoder(context_revision)),
      )
      use children <- decode.optional_field(
        "c",
        [],
        decode.list(child_decoder(context_revision)),
      )
      use replacement <- decode.optional_field(
        "r",
        None,
        replacement_decoder(context_revision) |> decode.map(Some),
      )
      decode.success(optional_field.FieldChange(moves, children, replacement))
    }
  }
}

fn move_decoder(context_revision: Int) -> Decoder(#(AtomId, AtomId)) {
  use pair <- decode.then(decode.list(decode.dynamic))
  case pair {
    [_, _] -> {
      use source <- decode.field(0, encoded_atom_decoder(context_revision))
      use destination <- decode.field(1, encoded_atom_decoder(context_revision))
      decode.success(#(source, destination))
    }
    _ -> decode.failure(#(AtomId(None, 0), AtomId(None, 0)), "field move")
  }
}

fn child_decoder(
  context_revision: Int,
) -> Decoder(#(optional_field.RegisterId, AtomId)) {
  use pair <- decode.then(decode.list(decode.dynamic))
  case pair {
    [_, _] -> {
      use register <- decode.field(0, register_decoder(context_revision))
      use child <- decode.field(1, encoded_node_id_decoder())
      decode.success(#(register, child))
    }
    _ ->
      decode.failure(
        #(optional_field.Active, AtomId(None, 0)),
        "field child change",
      )
  }
}

fn encoded_node_id_decoder() -> Decoder(AtomId) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  exact_decoder(fields, ["fieldChanges"], AtomId(None, 0), {
    use changes <- decode.field(
      "fieldChanges",
      decode.list(encoded_node_id_field_decoder()),
    )
    case changes {
      [id] -> decode.success(id)
      _ -> decode.failure(AtomId(None, 0), "encoded field child change")
    }
  })
}

fn encoded_node_id_field_decoder() -> Decoder(AtomId) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  exact_decoder(fields, ["fieldKey", "fieldKind", "change"], AtomId(None, 0), {
    use field_key <- decode.field("fieldKey", decode.string)
    use field_kind <- decode.field("fieldKind", decode.string)
    case field_key == "watershed-node-id" && field_kind == "watershed-node-id" {
      True -> {
        use change <- decode.field("change", raw_atom_decoder())
        decode.success(change)
      }
      False -> decode.failure(AtomId(None, 0), "encoded field child identity")
    }
  })
}

fn replacement_decoder(
  context_revision: Int,
) -> Decoder(optional_field.Replacement) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  case
    only_fields(fields, ["e", "s", "d"])
    && dict.has_key(fields, "e")
    && dict.has_key(fields, "d")
  {
    False ->
      decode.failure(
        optional_field.Replacement(False, None, AtomId(None, 0)),
        "field replacement",
      )
    True -> {
      use empty <- decode.field("e", decode.bool)
      use source <- decode.optional_field(
        "s",
        None,
        register_decoder(context_revision) |> decode.map(Some),
      )
      use destination <- decode.field(
        "d",
        encoded_atom_decoder(context_revision),
      )
      decode.success(optional_field.Replacement(empty, source, destination))
    }
  }
}

fn register_decoder(
  context_revision: Int,
) -> Decoder(optional_field.RegisterId) {
  decode.optional(encoded_atom_decoder(context_revision))
  |> decode.map(fn(atom) {
    case atom {
      None -> optional_field.Active
      Some(atom) -> optional_field.Detached(atom)
    }
  })
}

fn encoded_atom_decoder(context_revision: Int) -> Decoder(AtomId) {
  decode.one_of(
    {
      use local <- decode.then(safe_local_id_decoder())
      decode.success(AtomId(Some(revision_id(context_revision)), local))
    },
    [
      {
        use pair <- decode.then(decode.list(decode.dynamic))
        case pair {
          [_, _] -> {
            use local <- decode.field(0, safe_local_id_decoder())
            use revision <- decode.field(1, revision_number_decoder())
            decode.success(AtomId(Some(revision_id(revision)), local))
          }
          _ -> decode.failure(AtomId(None, 0), "encoded atom identifier")
        }
      },
    ],
  )
}

fn raw_change_decoder() -> Decoder(optional_field.FieldChange) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  case
    only_fields(fields, ["moves", "childChanges", "valueReplace"])
    && dict.has_key(fields, "moves")
    && dict.has_key(fields, "childChanges")
  {
    False ->
      decode.failure(
        optional_field.FieldChange([], [], None),
        "raw field change",
      )
    True -> {
      use moves <- decode.field("moves", decode.list(raw_move_decoder()))
      use children <- decode.field(
        "childChanges",
        decode.list(raw_child_decoder()),
      )
      use replacement <- decode.optional_field(
        "valueReplace",
        None,
        raw_replacement_decoder() |> decode.map(Some),
      )
      decode.success(optional_field.FieldChange(moves, children, replacement))
    }
  }
}

fn raw_move_decoder() -> Decoder(#(AtomId, AtomId)) {
  use pair <- decode.then(decode.list(decode.dynamic))
  case pair {
    [_, _] -> {
      use source <- decode.field(0, raw_atom_decoder())
      use destination <- decode.field(1, raw_atom_decoder())
      decode.success(#(source, destination))
    }
    _ -> decode.failure(#(AtomId(None, 0), AtomId(None, 0)), "raw move")
  }
}

fn raw_child_decoder() -> Decoder(#(optional_field.RegisterId, AtomId)) {
  use pair <- decode.then(decode.list(decode.dynamic))
  case pair {
    [_, _] -> {
      use register <- decode.field(0, raw_register_decoder())
      use child <- decode.field(1, raw_atom_decoder())
      decode.success(#(register, child))
    }
    _ ->
      decode.failure(
        #(optional_field.Active, AtomId(None, 0)),
        "raw child change",
      )
  }
}

fn raw_replacement_decoder() -> Decoder(optional_field.Replacement) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  case
    only_fields(fields, ["isEmpty", "src", "dst"])
    && dict.has_key(fields, "isEmpty")
    && dict.has_key(fields, "dst")
  {
    False ->
      decode.failure(
        optional_field.Replacement(False, None, AtomId(None, 0)),
        "raw replacement",
      )
    True -> {
      use empty <- decode.field("isEmpty", decode.bool)
      use source <- decode.optional_field(
        "src",
        None,
        raw_register_decoder() |> decode.map(Some),
      )
      use destination <- decode.field("dst", raw_atom_decoder())
      decode.success(optional_field.Replacement(empty, source, destination))
    }
  }
}

fn raw_register_decoder() -> Decoder(optional_field.RegisterId) {
  decode.one_of(
    {
      use value <- decode.then(decode.string)
      case value {
        "self" -> decode.success(optional_field.Active)
        _ -> decode.failure(optional_field.Active, "raw field register")
      }
    },
    [raw_atom_decoder() |> decode.map(optional_field.Detached)],
  )
}

fn raw_atom_decoder() -> Decoder(AtomId) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  exact_decoder(fields, ["revision", "localId"], AtomId(None, 0), {
    use revision <- decode.field("revision", revision_number_decoder())
    use local <- decode.field("localId", safe_local_id_decoder())
    decode.success(AtomId(Some(revision_id(revision)), local))
  })
}

fn run_expanded(
  expanded: Expanded,
  revisions: Revisions,
) -> Result(List(Json), String) {
  use _ <- result.try(validate_expanded(expanded, revisions))
  use compose <- result.try(run_expanded_compose(expanded.compose, []))
  use invert <- result.try(run_expanded_invert(expanded.invert, []))
  use rebase <- result.try(run_expanded_rebase(expanded.rebase, []))
  use delta <- result.try(run_expanded_delta(expanded.into_delta))
  use replace <- result.try(run_expanded_replace(expanded.replace_revisions))
  Ok(list.flatten([compose, invert, rebase, [delta, replace]]))
}

fn validate_expanded(
  expanded: Expanded,
  revisions: Revisions,
) -> Result(Nil, String) {
  let expected_changes = [
    "clearPresent",
    "clearAbsent",
    "activeSourceNoop",
    "childThenClear",
    "childOnClearedRegister",
    "baseChildThenClear",
    "authoredChild",
    "richRevisionChange",
  ]
  use _ <- result.try(require(
    dict.size(expanded.changes) == list.length(expected_changes)
      && list.all(expected_changes, fn(name) {
      dict.has_key(expanded.changes, name)
    }),
    "expanded change metadata is incomplete",
  ))
  use _ <- result.try(
    expanded.changes
    |> dict.values
    |> list.try_each(fn(input) {
      use _ <- result.try(validate_known_revision(input.revision, revisions))
      tree_result(optional_field.validate(input.change))
    }),
  )
  use _ <- result.try(require(
    !list.is_empty(expanded.compose)
      && !list.is_empty(expanded.invert)
      && !list.is_empty(expanded.rebase),
    "expanded operations must not be empty",
  ))
  use _ <- result.try(
    list.try_each(expanded.compose, fn(operation) {
      use _ <- result.try(validate_known_revision(
        operation.first.revision,
        revisions,
      ))
      use _ <- result.try(validate_known_revision(
        operation.second.revision,
        revisions,
      ))
      validate_known_revision(operation.output_revision, revisions)
    }),
  )
  use _ <- result.try(
    list.try_each(expanded.invert, fn(operation) {
      use _ <- result.try(validate_known_revision(
        operation.change.revision,
        revisions,
      ))
      require(
        operation.inverse_revision == revisions.inverse,
        "expanded inverse revision is invalid",
      )
    }),
  )
  use _ <- result.try(
    list.try_each(expanded.rebase, fn(operation) {
      use _ <- result.try(validate_known_revision(
        operation.change.revision,
        revisions,
      ))
      use _ <- result.try(validate_known_revision(
        operation.over.revision,
        revisions,
      ))
      validate_known_revision(operation.output_revision, revisions)
    }),
  )
  use _ <- result.try(validate_known_revision(
    expanded.into_delta.change.revision,
    revisions,
  ))
  use _ <- result.try(require(
    expanded.replace_revisions.obsolete == [revisions.first, revisions.second]
      && expanded.replace_revisions.updated == revisions.replacement
      && expanded.replace_revisions.output_revision == revisions.replacement,
    "expanded replacement metadata is invalid",
  ))
  use _ <- result.try(
    list.try_each(expanded.invalid_mappings, fn(mapping) {
      case optional_field.validate(mapping.change) {
        Error(_) -> Ok(Nil)
        Ok(Nil) -> Error("invalid mapping was accepted: " <> mapping.id)
      }
    }),
  )
  use _ <- result.try(require(
    list.map(expanded.invalid_mappings, fn(mapping) { mapping.id })
      == [
      "duplicate-move-source",
      "duplicate-move-destination",
      "duplicate-child-register",
    ],
    "invalid mapping inventory is incomplete",
  ))
  Ok(Nil)
}

fn validate_known_revision(
  revision: Int,
  revisions: Revisions,
) -> Result(Nil, String) {
  require(
    list.contains(
      [
        revisions.first,
        revisions.second,
        revisions.inverse,
        revisions.replacement,
      ],
      revision,
    ),
    "expanded operation uses an unknown revision",
  )
}

fn run_expanded_compose(
  operations: List(ExpandedCompose),
  output: List(Json),
) -> Result(List(Json), String) {
  case operations {
    [] -> Ok(list.reverse(output))
    [operation, ..rest] -> {
      use #(change, callbacks) <- result.try(
        tree_result(
          optional_field.compose(
            operation.first.change,
            operation.second.change,
            [],
            fn(first, second, callbacks) {
              use observation <- result.try(json_child_pair(
                "first",
                first,
                "second",
                second,
              ))
              use child <- result.try(case operation.callback {
                PreferFirstThenSecond ->
                  case first, second {
                    Some(id), _ | None, Some(id) -> Ok(id)
                    None, None ->
                      Error(CorruptData(
                        "field fixture",
                        "child change is missing",
                      ))
                  }
                Constant(id) -> Ok(id)
                PreferChangeThenBase ->
                  Error(CorruptData("field fixture", "invalid compose callback"))
              })
              Ok(#(child, [observation, ..callbacks]))
            },
          ),
        ),
      )
      use encoded <- result.try(encode_change(change, operation.output_revision))
      let observation =
        json.object([
          #("operation", json.string("compose-expanded")),
          #("id", json.string(operation.id)),
          #("encoded", encoded),
          #(
            "callbacks",
            json.array(list.reverse(callbacks), fn(value) { value }),
          ),
        ])
      run_expanded_compose(rest, [observation, ..output])
    }
  }
}

fn run_expanded_invert(
  operations: List(ExpandedInvert),
  output: List(Json),
) -> Result(List(Json), String) {
  case operations {
    [] -> Ok(list.reverse(output))
    [operation, ..rest] -> {
      use #(change, max_local_id) <- result.try(
        tree_result(optional_field.invert(
          operation.change.change,
          operation.is_rollback,
          Some(revision_id(operation.inverse_revision)),
          operation.max_local_id,
        )),
      )
      use encoded <- result.try(encode_change(
        change,
        operation.inverse_revision,
      ))
      let observation =
        json.object([
          #("operation", json.string("invert-expanded")),
          #("id", json.string(operation.id)),
          #("encoded", encoded),
          #(
            "allocator",
            json.object([
              #("before", json.int(operation.max_local_id)),
              #("after", json.int(max_local_id)),
            ]),
          ),
        ])
      run_expanded_invert(rest, [observation, ..output])
    }
  }
}

fn run_expanded_rebase(
  operations: List(ExpandedRebase),
  output: List(Json),
) -> Result(List(Json), String) {
  case operations {
    [] -> Ok(list.reverse(output))
    [operation, ..rest] -> {
      use #(change, callbacks) <- result.try(
        tree_result(
          optional_field.rebase(
            operation.change.change,
            operation.over.change,
            [],
            fn(change, over, attach_state, callbacks) {
              use callback <- result.try(json_rebase_callback(
                change,
                over,
                attach_state,
              ))
              let rebased = case operation.callback {
                PreferChangeThenBase ->
                  case change {
                    Some(_) -> change
                    None -> over
                  }
                _ -> None
              }
              Ok(#(rebased, [callback, ..callbacks]))
            },
          ),
        ),
      )
      use encoded <- result.try(encode_change(change, operation.output_revision))
      let observation =
        json.object([
          #("operation", json.string("rebase-expanded")),
          #("id", json.string(operation.id)),
          #("encoded", encoded),
          #(
            "callbacks",
            json.array(list.reverse(callbacks), fn(value) { value }),
          ),
        ])
      run_expanded_rebase(rest, [observation, ..output])
    }
  }
}

fn run_expanded_delta(operation: ExpandedDelta) -> Result(Json, String) {
  use delta <- result.try(
    tree_result(
      optional_field.into_delta(operation.change.change, fn(child) {
        Ok([
          #(
            operation.field,
            forest.FieldDelta([
              forest.Mark(child.local_id, None, None, []),
            ]),
          ),
        ])
      }),
    ),
  )
  use encoded <- result.try(encode_field_delta(delta))
  Ok(
    json.object([
      #("operation", json.string("into-delta-expanded")),
      #("delta", encoded),
    ]),
  )
}

fn run_expanded_replace(operation: ExpandedReplace) -> Result(Json, String) {
  use changed <- result.try(
    tree_result(
      optional_field.replace_revisions(operation.change.change, fn(id) {
        case revision_number(id.revision) {
          Error(detail) -> Error(CorruptData("field fixture revision", detail))
          Ok(revision) ->
            case list.contains(operation.obsolete, revision) {
              False -> Ok(id)
              True ->
                Ok(AtomId(Some(revision_id(operation.updated)), id.local_id))
            }
        }
      }),
    ),
  )
  use encoded <- result.try(encode_change(changed, operation.output_revision))
  Ok(
    json.object([
      #("operation", json.string("replace-revisions-expanded")),
      #("id", json.string(operation.id)),
      #("encoded", encoded),
    ]),
  )
}

fn json_child_pair(
  first_name: String,
  first: Option(AtomId),
  second_name: String,
  second: Option(AtomId),
) -> Result(Json, TreeError) {
  use first <- result.try(json_optional_raw_atom(first))
  use second <- result.try(json_optional_raw_atom(second))
  Ok(
    json.object([
      #(first_name, first),
      #(second_name, second),
    ]),
  )
}

fn json_rebase_callback(
  change: Option(AtomId),
  over: Option(AtomId),
  attach_state: optional_field.AttachState,
) -> Result(Json, TreeError) {
  use change <- result.try(json_optional_raw_atom(change))
  use over <- result.try(json_optional_raw_atom(over))
  Ok(
    json.object([
      #("change", change),
      #("over", over),
      #(
        "attachState",
        json.string(case attach_state {
          optional_field.Attached -> "attached"
          optional_field.DetachedNode -> "detached"
        }),
      ),
    ]),
  )
}

fn json_optional_raw_atom(value: Option(AtomId)) -> Result(Json, TreeError) {
  case value {
    None -> Ok(json.null())
    Some(value) ->
      encode_raw_atom(value)
      |> result.map_error(fn(detail) {
        CorruptData("field fixture revision", detail)
      })
  }
}

fn encode_field_delta(
  delta: optional_field.FieldChangeDelta,
) -> Result(Json, String) {
  use local <- result.try(case delta.local {
    None -> Ok(json.null())
    Some(local) -> encode_forest_field_delta(local)
  })
  use global <- result.try(
    list.try_map(delta.global, fn(change) {
      use id <- result.try(encode_delta_id(change.id))
      use fields <- result.try(encode_field_map(change.fields))
      Ok(
        json.object([
          #("id", id),
          #("fields", fields),
        ]),
      )
    }),
  )
  use rename <- result.try(
    list.try_map(delta.rename, fn(rename) {
      use old_id <- result.try(encode_delta_id(rename.old_id))
      use new_id <- result.try(encode_delta_id(rename.new_id))
      Ok(
        json.object([
          #("count", json.int(rename.count)),
          #("oldId", old_id),
          #("newId", new_id),
        ]),
      )
    }),
  )
  Ok(
    json.object([
      #("local", local),
      #("global", json.array(global, fn(value) { value })),
      #("rename", json.array(rename, fn(value) { value })),
    ]),
  )
}

fn encode_forest_field_delta(delta: forest.FieldDelta) -> Result(Json, String) {
  use marks <- result.try(
    list.try_map(delta.marks, fn(mark) {
      use attach <- result.try(encode_optional_delta_id(mark.attach))
      use detach <- result.try(encode_optional_delta_id(mark.detach))
      use fields <- result.try(encode_field_map(mark.fields))
      Ok(
        json.object([
          #("count", json.int(mark.count)),
          #("attach", attach),
          #("detach", detach),
          #("fields", fields),
        ]),
      )
    }),
  )
  Ok(
    json.object([
      #("marks", json.array(marks, fn(value) { value })),
    ]),
  )
}

fn encode_field_map(
  fields: List(#(String, forest.FieldDelta)),
) -> Result(Json, String) {
  use fields <- result.try(
    list.try_map(fields, fn(field) {
      use delta <- result.try(encode_forest_field_delta(field.1))
      Ok(json.array([json.string(field.0), delta], fn(value) { value }))
    }),
  )
  Ok(json.array(fields, fn(value) { value }))
}

fn encode_optional_delta_id(id: Option(AtomId)) -> Result(Json, String) {
  case id {
    None -> Ok(json.null())
    Some(id) -> encode_delta_id(id)
  }
}

fn encode_delta_id(id: AtomId) -> Result(Json, String) {
  use revision <- result.try(revision_number(id.revision))
  Ok(
    json.object([
      #("minor", json.int(id.local_id)),
      #("major", json.int(revision)),
    ]),
  )
}

fn run_swap_application(
  input: SwapApplication,
  change: optional_field.FieldChange,
) -> Result(Json, String) {
  use _ <- result.try(require(
    input.operation == "apply-original-simultaneous-swap",
    "unknown swap application selector",
  ))
  use _ <- result.try(require(
    list.length(input.registers) == 2,
    "swap needs two registers",
  ))
  let optional_field.FieldChange(moves, _, replacement) = change
  use _ <- result.try(require(
    replacement == None,
    "swap replacement is not allowed",
  ))
  use _ <- result.try(require(list.length(moves) == 2, "swap needs two moves"))
  let assert [first_move, second_move] = moves
  use _ <- result.try(require(
    first_move.0 == second_move.1 && first_move.1 == second_move.0,
    "rename is not a two-register cycle",
  ))
  let register_ids = list.map(input.registers, fn(register) { register.id })
  use _ <- result.try(require(
    list.contains(register_ids, first_move.0)
      && list.contains(register_ids, second_move.0),
    "swap source is missing",
  ))
  use stored <- result.try(
    tree_result(schema.stored_from_string(string_schema)),
  )
  use view <- result.try(stable_id(999))
  use state <- result.try(tree_result(forest.new(view, stored, None)))
  use build <- result.try(
    tree_result(
      forest.delta(
        forest.DeltaData(
          latest_revision: Some(revision_id(input.revision)),
          fields: [],
          build: list.map(input.registers, fn(register) {
            forest.Build(register.id, [StringValue(register.content)])
          }),
          refreshers: [],
          global: [],
          rename: [],
          destroy: [],
        ),
      ),
    ),
  )
  use state <- result.try(tree_result(forest.apply_delta(state, build)))
  use before <- result.try(tree_result(forest.export_data(state)))
  use field_delta <- result.try(
    tree_result(optional_field.into_delta(change, fn(_) { Ok([]) })),
  )
  use rename <- result.try(
    tree_result(
      forest.delta(
        forest.DeltaData(
          latest_revision: Some(revision_id(input.revision)),
          fields: [],
          build: [],
          refreshers: [],
          global: field_delta.global,
          rename: field_delta.rename,
          destroy: [],
        ),
      ),
    ),
  )
  let application = forest.apply_delta(state, rename)
  use after <- result.try(tree_result(forest.export_data(state)))
  use _ <- result.try(require(
    before == after,
    "rename refusal changed the forest",
  ))
  use _ <- result.try(case application {
    Error(CorruptData(
      "rename",
      "sources are missing or destinations form an occupied cycle",
    )) -> Ok(Nil)
    Error(error) ->
      Error(
        "swap application failed before occupied cycle: "
        <> string.inspect(error),
      )
    Ok(_) -> Error("occupied rename cycle was accepted")
  })
  let assert [first, second] = input.registers
  use first_content <- result.try(read_detached_string(state, first.id))
  use second_content <- result.try(read_detached_string(state, second.id))
  Ok(
    json.object([
      #(
        "operation",
        json.string("simultaneous-swap-direct-application-refusal"),
      ),
      #("status", json.string("rejected")),
      #("error", json.string("Error: 0x7cf")),
      #(
        "postFailureForestRead",
        json.object([
          #("status", json.string("accepted")),
          #(
            "value",
            json.object([
              #("first", json.string(first_content)),
              #("second", json.string(second_content)),
            ]),
          ),
        ]),
      ),
    ]),
  )
}

fn read_detached_string(
  state: forest.Forest,
  id: AtomId,
) -> Result(String, String) {
  use reference <- result.try(tree_result(forest.locate_detached(state, id)))
  use value <- result.try(tree_result(forest.read_node(state, reference)))
  case value {
    StringValue(value) -> Ok(value)
    _ -> Error("swap register is not a string")
  }
}

fn run_swap_algebra(input: SwapAlgebra) -> Result(Json, String) {
  use _ <- result.try(require(
    input.operation == "rebase-child-changes-over-simultaneous-swap",
    "unknown swap algebra selector",
  ))
  use #(rebased, _) <- result.try(
    tree_result(
      optional_field.rebase(
        input.change,
        input.over,
        Nil,
        fn(change, over, _, state) {
          Ok(#(
            case change {
              Some(_) -> change
              None -> over
            },
            state,
          ))
        },
      ),
    ),
  )
  use mappings <- result.try(map_swap_children(input.change, rebased))
  Ok(
    json.object([
      #("operation", json.string("simultaneous-swap-algebra-mapping")),
      #("mappings", json.array(mappings, fn(value) { value })),
    ]),
  )
}

fn map_swap_children(
  input: optional_field.FieldChange,
  output: optional_field.FieldChange,
) -> Result(List(Json), String) {
  let optional_field.FieldChange(_, input_children, _) = input
  let optional_field.FieldChange(_, output_children, _) = output
  case input_children, output_children {
    [], [] -> Ok([])
    [input, ..input_rest], [output, ..output_rest] -> {
      use from <- result.try(detached_register(input.0))
      use to <- result.try(detached_register(output.0))
      use node <- result.try(encode_raw_atom(input.1))
      use from <- result.try(encode_raw_atom(from))
      use to <- result.try(encode_raw_atom(to))
      use rest <- result.try(map_swap_children(
        optional_field.FieldChange([], input_rest, None),
        optional_field.FieldChange([], output_rest, None),
      ))
      Ok([
        json.object([
          #("node", node),
          #("from", from),
          #("to", to),
        ]),
        ..rest
      ])
    }
    _, _ -> Error("swap algebra changed the child count")
  }
}

fn detached_register(
  register: optional_field.RegisterId,
) -> Result(AtomId, String) {
  case register {
    optional_field.Detached(id) -> Ok(id)
    optional_field.Active -> Error("swap algebra used the active register")
  }
}

fn observation(operation: String, encoded: Json) -> Json {
  json.object([
    #("operation", json.string(operation)),
    #("encoded", encoded),
  ])
}

fn encode_change(
  change: optional_field.FieldChange,
  context_revision: Int,
) -> Result(Json, String) {
  let optional_field.FieldChange(moves, children, replacement) = change
  use moves <- result.try(
    list.try_map(moves, fn(move) {
      use source <- result.try(encode_atom(move.0, context_revision))
      use destination <- result.try(encode_atom(move.1, context_revision))
      Ok(json.array([source, destination], fn(value) { value }))
    }),
  )
  use children <- result.try(
    list.try_map(children, fn(child) {
      use register <- result.try(encode_register(child.0, context_revision))
      use child_change <- result.try(encode_node_id(child.1))
      Ok(json.array([register, child_change], fn(value) { value }))
    }),
  )
  use replacement <- result.try(case replacement {
    None -> Ok(None)
    Some(replacement) -> {
      use destination <- result.try(encode_atom(
        replacement.detach_id,
        context_revision,
      ))
      use source <- result.try(case replacement.source {
        None -> Ok(None)
        Some(source) ->
          encode_register(source, context_revision) |> result.map(Some)
      })
      let fields = [
        #("e", json.bool(replacement.was_empty)),
        #("d", destination),
      ]
      let fields = case source {
        None -> fields
        Some(source) -> [#("s", source), ..fields]
      }
      Ok(Some(json.object(fields)))
    }
  })
  let fields = []
  let fields = case moves {
    [] -> fields
    _ -> [#("m", json.array(moves, fn(value) { value })), ..fields]
  }
  let fields = case children {
    [] -> fields
    _ -> [#("c", json.array(children, fn(value) { value })), ..fields]
  }
  let fields = case replacement {
    None -> fields
    Some(replacement) -> [#("r", replacement), ..fields]
  }
  Ok(json.object(list.reverse(fields)))
}

fn encode_register(
  register: optional_field.RegisterId,
  context_revision: Int,
) -> Result(Json, String) {
  case register {
    optional_field.Active -> Ok(json.null())
    optional_field.Detached(id) -> encode_atom(id, context_revision)
  }
}

fn encode_atom(id: AtomId, context_revision: Int) -> Result(Json, String) {
  use revision <- result.try(revision_number(id.revision))
  case revision == context_revision {
    True -> Ok(json.int(id.local_id))
    False ->
      Ok(
        json.array([json.int(id.local_id), json.int(revision)], fn(value) {
          value
        }),
      )
  }
}

fn encode_raw_atom(id: AtomId) -> Result(Json, String) {
  use revision <- result.try(revision_number(id.revision))
  Ok(
    json.object([
      #("revision", json.int(revision)),
      #("localId", json.int(id.local_id)),
    ]),
  )
}

fn encode_node_id(id: AtomId) -> Result(Json, String) {
  use change <- result.try(encode_raw_atom(id))
  Ok(
    json.object([
      #(
        "fieldChanges",
        json.array(
          [
            json.object([
              #("fieldKey", json.string("watershed-node-id")),
              #("fieldKind", json.string("watershed-node-id")),
              #("change", change),
            ]),
          ],
          fn(value) { value },
        ),
      ),
    ]),
  )
}

fn validate_revisions(revisions: Revisions) -> Result(Nil, String) {
  let values = [
    revisions.first,
    revisions.second,
    revisions.inverse,
    revisions.replacement,
  ]
  use _ <- result.try(require(
    list.length(list.unique(values)) == 4,
    "field revisions must be distinct",
  ))
  list.try_each(values, fn(value) {
    stable_id(value) |> result.map(fn(_) { Nil })
  })
}

fn validate_operations(input: Input) -> Result(Nil, String) {
  let revisions = input.revisions
  let compose = input.operations.compose
  use _ <- result.try(require(
    compose.metadata_revisions == [revisions.first, revisions.second],
    "compose revision metadata is incomplete",
  ))
  use _ <- result.try(require(
    compose.metadata_base == revisions.second,
    "compose base revision is invalid",
  ))
  use _ <- result.try(require(
    compose.rollback_revisions == [revisions.first],
    "compose rollback metadata is invalid",
  ))
  use _ <- result.try(require(
    input.operations.invert.inverse_revision == revisions.inverse,
    "inverse revision is invalid",
  ))
  use _ <- result.try(require(
    input.operations.replace_revisions.updated == revisions.replacement,
    "replacement revision is invalid",
  ))
  use _ <- result.try(require(
    input.operations.replace_revisions.obsolete
      == [revisions.first, revisions.second],
    "obsolete revisions are invalid",
  ))
  use _ <- result.try(named_change_result(input.changes, compose.left))
  use _ <- result.try(named_change_result(input.changes, compose.right))
  use _ <- result.try(named_change_result(
    input.changes,
    input.operations.rebase.change,
  ))
  use _ <- result.try(named_change_result(
    input.changes,
    input.operations.rebase.over,
  ))
  use _ <- result.try(require(
    input.operations.invert.change == "compose",
    "unknown invert change selector",
  ))
  named_change_result(input.changes, input.operations.replace_revisions.change)
  |> result.map(fn(_) { Nil })
}

fn named_change(
  changes: NamedChanges,
  name: String,
) -> optional_field.FieldChange {
  let assert Ok(change) = named_change_result(changes, name)
  change
}

fn named_change_result(
  changes: NamedChanges,
  name: String,
) -> Result(optional_field.FieldChange, String) {
  case name {
    "optional" -> Ok(changes.optional)
    "required" -> Ok(changes.required)
    "swap" -> Ok(changes.swap)
    _ -> Error("unknown field change selector: " <> name)
  }
}

fn select_change(
  name: String,
  changes: NamedChanges,
  composed: optional_field.FieldChange,
) -> optional_field.FieldChange {
  case name {
    "compose" -> composed
    _ -> named_change(changes, name)
  }
}

fn revision_number(revision: Option(StableId)) -> Result(Int, String) {
  case revision {
    None -> Error("anonymous revision is not in the field fixture")
    Some(revision) -> find_revision(revision, 0)
  }
}

fn find_revision(revision: StableId, candidate: Int) -> Result(Int, String) {
  case candidate > 999 {
    True -> Error("unknown stable revision in the field fixture")
    False ->
      case revision_id(candidate) == revision {
        True -> Ok(candidate)
        False -> find_revision(revision, candidate + 1)
      }
  }
}

fn revision_id(value: Int) -> StableId {
  let assert Ok(id) = stable_id(value)
  id
}

fn stable_id(value: Int) -> Result(StableId, String) {
  use _ <- result.try(require(
    value >= 0 && value <= 999,
    "invalid fixture revision",
  ))
  let suffix = value |> int.to_string |> string.pad_start(12, "0")
  fluid_ids.stable_id("00000000-0000-4000-8000-" <> suffix)
  |> result.map_error(fn(_) { "invalid fixture stable revision" })
}

fn revision_number_decoder() -> Decoder(Int) {
  use value <- decode.then(decode.int)
  case value >= 0 && value <= 999 {
    True -> decode.success(value)
    False -> decode.failure(0, "nonnegative fixture revision")
  }
}

fn safe_local_id_decoder() -> Decoder(Int) {
  use value <- decode.then(decode.int)
  case value >= 0 && value <= max_safe_integer {
    True -> decode.success(value)
    False -> decode.failure(0, "nonnegative safe atom localId")
  }
}

fn tree_result(value: Result(a, TreeError)) -> Result(a, String) {
  value |> result.map_error(string.inspect)
}

fn require(valid: Bool, detail: String) -> Result(Nil, String) {
  case valid {
    True -> Ok(Nil)
    False -> Error(detail)
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

fn only_fields(fields: Dict(String, Dynamic), allowed: List(String)) -> Bool {
  fields
  |> dict.keys
  |> list.all(fn(field) { list.contains(allowed, field) })
}
