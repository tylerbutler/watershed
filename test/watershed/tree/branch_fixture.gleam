import gleam/dict
import gleam/dynamic/decode
import gleam/json.{type Json}
import gleam/list
import gleam/option.{None, Some, to_result}
import gleam/result
import gleam/string
import spillway/types as spillway_types
import watershed/channel
import watershed/fluid_ids
import watershed/json_ot.{type JsonValue, VArray, VObject, VString}
import watershed/runtime_core
import watershed/tree/branch
import watershed/tree/change_fixture_codec as fixture_codec
import watershed/tree/codec
import watershed/tree/codec/field_batch
import watershed/tree/fixtures
import watershed/tree/forest
import watershed/tree/history
import watershed/tree/identifier
import watershed/tree/runtime as tree_runtime
import watershed/tree/runtime_fixture
import watershed/tree/schema
import watershed/tree/shared_change
import watershed/tree/types
import watershed/tree_kernel
import watershed/wire
import watershed/wire/fluid_container

const point_type = "org.watershed.shared-tree.branch.Point"

const items_type = "org.watershed.shared-tree.branch.Items"

const root_type = "org.watershed.shared-tree.branch.Root"

const fixture_session = "8f95be09-8376-4ff7-8755-ccd7e8124b06"

const fixture_view = "8f95be09-8376-4ff7-8755-ccd7e8124b05"

const tree_schema = "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.number\":{\"kind\":{\"leaf\":0}},\"com.fluidframework.leaf.string\":{\"kind\":{\"leaf\":1}},\"org.watershed.shared-tree.branch.Items\":{\"kind\":{\"object\":{\"\":{\"kind\":\"Sequence\",\"types\":[\"com.fluidframework.leaf.string\",\"org.watershed.shared-tree.branch.Point\"]}}}},\"org.watershed.shared-tree.branch.Point\":{\"kind\":{\"object\":{\"id\":{\"kind\":\"Identifier\",\"types\":[\"com.fluidframework.leaf.string\"]},\"label\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.string\"]}}}},\"org.watershed.shared-tree.branch.Root\":{\"kind\":{\"object\":{\"count\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.number\"]},\"featured\":{\"kind\":\"Value\",\"types\":[\"org.watershed.shared-tree.branch.Point\"]},\"left\":{\"kind\":\"Value\",\"types\":[\"org.watershed.shared-tree.branch.Items\"]},\"right\":{\"kind\":\"Value\",\"types\":[\"org.watershed.shared-tree.branch.Items\"]},\"title\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.string\"]}}}}},\"root\":{\"kind\":\"Value\",\"types\":[\"org.watershed.shared-tree.branch.Root\"]}}"

const optional_tree_schema = "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.number\":{\"kind\":{\"leaf\":0}},\"com.fluidframework.leaf.string\":{\"kind\":{\"leaf\":1}},\"org.watershed.shared-tree.branch.Items\":{\"kind\":{\"object\":{\"\":{\"kind\":\"Sequence\",\"types\":[\"com.fluidframework.leaf.string\",\"org.watershed.shared-tree.branch.Point\"]}}}},\"org.watershed.shared-tree.branch.Point\":{\"kind\":{\"object\":{\"id\":{\"kind\":\"Identifier\",\"types\":[\"com.fluidframework.leaf.string\"]},\"label\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.string\"]}}}},\"org.watershed.shared-tree.branch.Root\":{\"kind\":{\"object\":{\"count\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.number\"]},\"featured\":{\"kind\":\"Value\",\"types\":[\"org.watershed.shared-tree.branch.Point\"]},\"left\":{\"kind\":\"Value\",\"types\":[\"org.watershed.shared-tree.branch.Items\"]},\"right\":{\"kind\":\"Value\",\"types\":[\"org.watershed.shared-tree.branch.Items\"]},\"title\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.string\"]}}}}},\"root\":{\"kind\":\"Optional\",\"types\":[\"org.watershed.shared-tree.branch.Root\"]}}"

type State {
  State(tree: tree_kernel.TreeState, compressor: fluid_ids.Compressor)
}

const tree_address = "A/_C"

pub fn run(name: String, input: Json) -> Result(Json, String) {
  use _ <- result.try(validate_input(name, input))
  case name {
    "local-branch-isolation" -> run_isolation()
    "local-branch-rebase" -> run_rebase()
    "local-branch-merge" -> run_merge()
    "local-branch-transactions" -> run_transactions()
    "local-branch-allocation" -> run_allocation()
    _ -> Error("unsupported branch fixture " <> name)
  }
}

pub fn projection(name: String, expected: Json) -> Result(Json, String) {
  case name {
    "local-branch-isolation" ->
      validate_projection(expected, [
        #("isolation", ["beforeMerge", "detachedIsolation", "afterMerge"]),
        #("lifetime", [
          "doubleDisposeError", "parentDisposed", "descendantDisposed",
          "descendant", "mainCheckoutDisposed",
        ]),
      ])
    "local-branch-rebase" -> {
      use expected <- result.try(
        validate_projection(expected, [
          #("related-target", ["sourceThenTarget", "targetThenSource"]),
          #("optimistic-main", ["value", "revisions"]),
          #("self-rebase", ["revisions"]),
          #("schema-divergence", [
            "main",
            "forkCanViewWideSchema",
            "forkHistory",
          ]),
        ]),
      )
      native_rebase_projection(expected)
    }
    "local-branch-merge" ->
      validate_projection(expected, [
        #("commit-boundaries", [
          "sourceRevisions",
          "targetRevisions",
          "events",
          "sourceEvents",
        ]),
        #("merge-edge-cases", [
          "repeatedEventCount", "emptyDisposed", "selfPreservedDisposed",
          "selfDefaultDisposed", "defaultDisposed",
        ]),
      ])
    "local-branch-transactions" ->
      validate_projection(expected, [
        #("outer-commit", ["value", "revisions", "events"]),
        #("guards", [
          "sourceGuard", "targetGuard", "sourceMergeGuard", "targetMergeGuard",
          "forkGuard",
        ]),
        #("constraint", ["source", "target", "revisions"]),
        #("cross-checkout", ["error", "changedMain"]),
        #("abort-allocation", [
          "stateRestored", "allocationAdvanced", "before", "after",
        ]),
      ])
    "local-branch-allocation" ->
      validate_projection(expected, [
        #("branch-only", [
          "messages", "allocationRanges", "reservationAdvanced", "before",
          "after",
        ]),
        #("main-publication", ["allocationRanges", "messages"]),
        #("merge-publication", ["identifiers", "allocationRanges", "messages"]),
        #("abort-range", ["allocationAdvanced", "before", "after"]),
      ])
    _ -> Error("unsupported branch fixture projection " <> name)
  }
}

fn validate_input(name: String, input: Json) -> Result(Nil, String) {
  use value <- result.try(fixture_codec.parse(input))
  use _ <- result.try(fixture_codec.exact(value, ["scenarios"]))
  use scenarios <- result.try(fixture_codec.field(
    value,
    "scenarios",
    fixture_codec.items,
  ))
  use scenarios <- result.try(list.try_map(scenarios, fixture_codec.text))
  let required = case name {
    "local-branch-isolation" -> [
      "main-and-nested-forks", "stable-attached-identity",
      "detached-identity-isolation", "arbitrary-related-local-target",
      "parent-disposal-descendant-lifetime", "public-double-disposal",
      "main-view-disposal", "no-branch-tree-submission",
    ]
    "local-branch-rebase" -> [
      "both-edit-orders", "target-unchanged", "common-revision-rewrite",
      "optimistic-main-base", "self-rebase", "schema-divergence",
    ]
    "local-branch-merge" -> [
      "surviving-source-revisions", "one-event-per-source-commit",
      "preserved-source-repeat", "empty-merge",
      "self-merge-preserved-and-default", "default-source-disposal",
    ]
    "local-branch-transactions" -> [
      "nested-abort-and-outer-commit", "source-and-target-operation-guards",
      "active-transaction-fork-guard", "node-in-document-constraint",
      "cross-checkout-callback", "allocation-survives-abort",
    ]
    "local-branch-allocation" -> [
      "shared-compressor", "interleaved-identifiers", "branch-only-reservation",
      "main-triggered-publication", "aborted-range-retained",
      "merge-range-before-tree-use",
    ]
    _ -> []
  }
  case scenarios == required {
    True -> Ok(Nil)
    False -> Error("unsupported branch scenarios for " <> name)
  }
}

fn validate_projection(
  expected: Json,
  fields: List(#(String, List(String))),
) -> Result(Json, String) {
  use value <- result.try(fixture_codec.parse(expected))
  use _ <- result.try(fixture_codec.exact(value, ["observations"]))
  use observations <- result.try(fixture_codec.field(
    value,
    "observations",
    fixture_codec.items,
  ))
  use _ <- result.try(case list.length(observations) == list.length(fields) {
    True -> Ok(Nil)
    False -> Error("branch fixture observation count differs")
  })
  use _ <- result.try(
    list.try_each(list.zip(observations, fields), fn(entry) {
      let #(observation, #(id, names)) = entry
      use _ <- result.try(fixture_codec.exact(observation, ["id", ..names]))
      use actual_id <- result.try(fixture_codec.field(
        observation,
        "id",
        fixture_codec.text,
      ))
      case actual_id == id {
        True -> Ok(Nil)
        False -> Error("branch fixture observation order differs")
      }
    }),
  )
  normalize_field_batches(expected)
}

fn native_rebase_projection(expected: Json) -> Result(Json, String) {
  use value <- result.try(fixture_codec.parse(expected))
  let assert VObject(root) = value
  use observations <- result.try(
    list.key_find(root, "observations")
    |> result.map_error(fn(_) { "branch fixture observations are missing" }),
  )
  let assert VArray([
    related_target,
    optimistic_main,
    self_rebase,
    VObject(schema_divergence),
  ]) = observations
  use id <- result.try(
    list.key_find(schema_divergence, "id")
    |> result.map_error(fn(_) { "source-only schema observation is missing" }),
  )
  use _ <- result.try(case id {
    VString("schema-divergence") -> Ok(Nil)
    _ -> Error("source-only schema observation order differs")
  })
  use main <- result.try(fixture_codec.field(
    VObject(schema_divergence),
    "main",
    fixture_codec.items,
  ))
  use main <- result.try(list.try_map(main, fixture_codec.text))
  use can_view <- result.try(fixture_codec.field(
    VObject(schema_divergence),
    "forkCanViewWideSchema",
    fixture_codec.boolean,
  ))
  use fork_history <- result.try(fixture_codec.field(
    VObject(schema_divergence),
    "forkHistory",
    fixture_codec.items,
  ))
  use fork_history <- result.try(list.try_map(fork_history, fixture_codec.text))
  use _ <- result.try(case main, can_view, fork_history {
    ["B", "C"],
      False,
      [
        "8f95be09-8376-4ff7-8755-ccd7e8124b06",
        "8f95be09-8376-4ff7-8755-ccd7e8124b09",
        "8f95be09-8376-4ff7-8755-ccd7e8124b07",
        "8f95be09-8376-4ff7-8755-ccd7e8124b08",
      ]
    -> Ok(Nil)
    _, _, _ -> Error("source-only schema observation differs")
  })
  Ok(
    json.object([
      #(
        "observations",
        fixture_codec.array([
          fixture_codec_json(related_target),
          fixture_codec_json(optimistic_main),
          fixture_codec_json(self_rebase),
        ]),
      ),
    ]),
  )
}

fn run_isolation() -> Result(Json, String) {
  use core <- result.try(initial_core())
  use view <- result.try(
    schema.view_from_string(tree_schema) |> result.map_error(string.inspect),
  )
  let document = types.DocumentCheckout
  use #(core, parent_id) <- result.try(
    core_result(runtime_core.fork_tree(core, tree_address, document, view)),
  )
  let parent = types.LocalCheckout(parent_id)
  use #(core, nested_id) <- result.try(
    core_result(runtime_core.fork_tree(core, tree_address, parent, view)),
  )
  let nested = types.LocalCheckout(nested_id)
  use #(core, _, parent_outbound) <- result.try(
    core_result(
      runtime_core.submit_tree_edits_on(core, tree_address, parent, [
        types.SetField(["title"], types.StringValue("parent")),
      ]),
    ),
  )
  use #(core, _, nested_outbound) <- result.try(
    core_result(
      runtime_core.submit_tree_edits_on(core, tree_address, nested, [
        types.SetField(["count"], types.NumberValue(7.0)),
      ]),
    ),
  )
  let before_merge_outbound = list.append(parent_outbound, nested_outbound)
  use _ <- result.try(require_no_outbound(
    before_merge_outbound,
    "local isolation edits",
  ))
  use main_before <- result.try(core_visible_json(core, document))
  use parent_before <- result.try(core_visible_json(core, parent))
  use nested_before <- result.try(core_visible_json(core, nested))
  use main_identity <- result.try(core_featured_identity(core, document))
  use parent_identity <- result.try(core_featured_identity(core, parent))
  use nested_identity <- result.try(core_featured_identity(core, nested))

  use #(core, detached_id) <- result.try(
    core_result(runtime_core.fork_tree(core, tree_address, document, view)),
  )
  let detached = types.LocalCheckout(detached_id)
  use forest <- result.try(core_forest(core))
  use detached_checkout <- try_native(branch.checkout(forest, detached))
  use detached_reference <- try_native(
    branch.reference_at(forest, detached_checkout, ["left", "0"]),
  )
  use #(core, _, detached_outbound) <- result.try(
    core_result(
      runtime_core.submit_tree_edits_on(core, tree_address, detached, [
        types.ArrayRemove(["left"], 0, 1),
      ]),
    ),
  )
  use _ <- result.try(require_no_outbound(
    detached_outbound,
    "detached local edit",
  ))
  use forest <- result.try(core_forest(core))
  use detached_checkout <- try_native(branch.checkout(forest, detached))
  use detached_state <- try_native(branch.checkout_state(
    forest,
    detached_checkout,
  ))
  use detached_value <- try_native(tree_kernel.read_reference(
    detached_state,
    detached_reference,
  ))
  use detached_point <- result.try(point_json(detached_value))
  let detached_edit_error = case
    tree_kernel.ensure_attached(detached_state, detached_reference)
  {
    Ok(_) -> ""
    Error(error) -> string.inspect(error)
  }
  use main_after_detach <- result.try(core_visible_json(core, document))

  use #(core, left_id) <- result.try(
    core_result(runtime_core.fork_tree(core, tree_address, document, view)),
  )
  let left = types.LocalCheckout(left_id)
  use #(core, right_id) <- result.try(
    core_result(runtime_core.fork_tree(core, tree_address, document, view)),
  )
  let right = types.LocalCheckout(right_id)
  use #(core, _, left_outbound) <- result.try(
    core_result(
      runtime_core.submit_tree_edits_on(core, tree_address, left, [
        types.SetField(["title"], types.StringValue("arbitrary-target")),
      ]),
    ),
  )
  use _ <- result.try(require_no_outbound(left_outbound, "local branch edit"))
  use #(core, _, local_merge_outbound) <- result.try(
    core_result(runtime_core.merge_tree(core, tree_address, right, left, False)),
  )
  use _ <- result.try(require_no_outbound(
    local_merge_outbound,
    "local target merge",
  ))
  use core <- result.try(
    core_result(runtime_core.dispose_tree_branch(core, tree_address, parent)),
  )
  let double_dispose_error = case
    runtime_core.dispose_tree_branch(core, tree_address, parent)
  {
    Ok(_) -> ""
    Error(error) -> string.inspect(error)
  }
  use #(core, _, descendant_outbound) <- result.try(
    core_result(
      runtime_core.submit_tree_edits_on(core, tree_address, nested, [
        types.SetField(["title"], types.StringValue("descendant-live")),
      ]),
    ),
  )
  use _ <- result.try(require_no_outbound(
    descendant_outbound,
    "descendant local edit",
  ))
  use #(core, _, document_merge_outbound) <- result.try(
    core_result(runtime_core.merge_tree(
      core,
      tree_address,
      document,
      right,
      True,
    )),
  )
  use _ <- result.try(require_outbound(
    document_merge_outbound,
    "document isolation merge",
  ))
  use after_merge <- result.try(core_visible_json(core, document))
  use descendant <- result.try(core_visible_json(core, nested))
  use main_before_dispose <- result.try(core_visible_json(core, document))
  let main_dispose_error = case
    runtime_core.dispose_tree_branch(core, tree_address, document)
  {
    Ok(_) -> ""
    Error(error) -> string.inspect(error)
  }
  use _ <- result.try(case main_dispose_error {
    "" -> Error("document checkout disposal unexpectedly succeeded")
    _ -> Ok(Nil)
  })
  use _ <- result.try(
    runtime_core.tree_read(core, tree_address, ["title"])
    |> result.map_error(string.inspect),
  )
  use main_after_dispose <- result.try(core_visible_json(core, document))
  use _ <- result.try(case main_after_dispose == main_before_dispose {
    True -> Ok(Nil)
    False -> Error("document checkout changed after refused disposal")
  })

  normalize_field_batches(
    json.object([
      #(
        "observations",
        fixture_codec.array([
          json.object([
            #("id", json.string("isolation")),
            #(
              "beforeMerge",
              json.object([
                #("main", main_before),
                #("parent", parent_before),
                #("nested", nested_before),
                #(
                  "identities",
                  json.object([
                    #("main", json.string(main_identity)),
                    #("parent", json.string(parent_identity)),
                    #("nested", json.string(nested_identity)),
                  ]),
                ),
                #(
                  "treeMessages",
                  fixture_codec.array(
                    list.map(before_merge_outbound, fn(operation) {
                      operation.contents
                    }),
                  ),
                ),
              ]),
            ),
            #(
              "detachedIsolation",
              json.object([
                #("detached", detached_point),
                #("main", main_after_detach),
                #("editError", json.string(detached_edit_error)),
              ]),
            ),
            #("afterMerge", after_merge),
          ]),
          json.object([
            #("id", json.string("lifetime")),
            #("doubleDisposeError", json.string(double_dispose_error)),
            #(
              "parentDisposed",
              json.bool(
                runtime_core.tree_branch_status(core, tree_address, parent)
                == runtime_core.BranchDisposed,
              ),
            ),
            #(
              "descendantDisposed",
              json.bool(
                runtime_core.tree_branch_status(core, tree_address, nested)
                == runtime_core.BranchDisposed,
              ),
            ),
            #("descendant", descendant),
            #(
              "mainCheckoutDisposed",
              json.bool(
                runtime_core.tree_branch_status(core, tree_address, document)
                == runtime_core.BranchDisposed,
              ),
            ),
          ]),
        ]),
      ),
    ]),
  )
}

fn run_rebase() -> Result(Json, String) {
  use initial <- result.try(initial_state())
  let forest =
    branch.new(branch.origin("fixture", "document", "tree"), initial.tree)
  let document = branch.document(forest)
  use #(forest, source) <- try_native(branch.fork(forest, document))
  use #(forest, target) <- try_native(branch.fork(forest, document))
  use main_edit <- try_native(branch.author(
    forest,
    document,
    types.SetField(["title"], types.StringValue("main-first")),
    initial.compressor,
  ))
  let assert branch.AuthorResult(forest, Some(_), _, compressor) = main_edit
  use source_edit <- try_native(branch.author(
    forest,
    source,
    types.SetField(["count"], types.NumberValue(1.0)),
    compressor,
  ))
  let assert branch.AuthorResult(forest, Some(_), _, compressor) = source_edit
  use target_edit <- try_native(branch.author(
    forest,
    target,
    types.SetField(["title"], types.StringValue("target")),
    compressor,
  ))
  let assert branch.AuthorResult(forest, Some(_), _, compressor) = target_edit
  use #(branch.ReconcileResult(forest, _, _), compressor) <- try_native(
    branch.rebase_with_compressor(forest, source, target, compressor),
  )
  use source_value <- result.try(visible_json(forest, source))
  use target_value <- result.try(visible_json(forest, target))
  let source_then_target =
    related_target_json(forest, source, target, source_value, target_value)

  use optimistic_edit <- try_native(branch.author(
    forest,
    document,
    types.SetField(["title"], types.StringValue("optimistic-main")),
    compressor,
  ))
  let assert branch.AuthorResult(forest, Some(_), _, compressor) =
    optimistic_edit
  use #(forest, optimistic) <- try_native(branch.fork(forest, document))
  use optimistic_value <- result.try(visible_json(forest, optimistic))
  use #(branch.ReconcileResult(forest, _, _), _) <- try_native(
    branch.rebase_with_compressor(forest, source, source, compressor),
  )
  let self_revisions = checkout_revisions(forest, source)

  use second <- result.try(initial_state())
  let second_forest =
    branch.new(branch.origin("fixture", "document", "tree"), second.tree)
  let second_document = branch.document(second_forest)
  use #(second_forest, second_source) <- try_native(branch.fork(
    second_forest,
    second_document,
  ))
  use #(second_forest, second_target) <- try_native(branch.fork(
    second_forest,
    second_document,
  ))
  use second_target_edit <- try_native(branch.author(
    second_forest,
    second_target,
    types.SetField(["title"], types.StringValue("target-first")),
    second.compressor,
  ))
  let assert branch.AuthorResult(second_forest, Some(_), _, second_compressor) =
    second_target_edit
  use second_source_edit <- try_native(branch.author(
    second_forest,
    second_source,
    types.SetField(["count"], types.NumberValue(2.0)),
    second_compressor,
  ))
  let assert branch.AuthorResult(second_forest, Some(_), _, second_compressor) =
    second_source_edit
  use #(branch.ReconcileResult(second_forest, _, _), _) <- try_native(
    branch.rebase_with_compressor(
      second_forest,
      second_source,
      second_target,
      second_compressor,
    ),
  )
  use second_source_value <- result.try(visible_json(
    second_forest,
    second_source,
  ))
  use second_target_value <- result.try(visible_json(
    second_forest,
    second_target,
  ))
  let target_then_source =
    related_target_json(
      second_forest,
      second_source,
      second_target,
      second_source_value,
      second_target_value,
    )

  Ok(
    json.object([
      #(
        "observations",
        fixture_codec.array([
          json.object([
            #("id", json.string("related-target")),
            #("sourceThenTarget", source_then_target),
            #("targetThenSource", target_then_source),
          ]),
          json.object([
            #("id", json.string("optimistic-main")),
            #("value", optimistic_value),
            #("revisions", string_array(checkout_revisions(forest, optimistic))),
          ]),
          json.object([
            #("id", json.string("self-rebase")),
            #("revisions", string_array(self_revisions)),
          ]),
        ]),
      ),
    ]),
  )
}

fn related_target_json(
  forest: branch.Forest,
  source: branch.Checkout,
  target: branch.Checkout,
  source_value: Json,
  target_value: Json,
) -> Json {
  json.object([
    #("source", source_value),
    #("target", target_value),
    #("sourceRevisions", string_array(checkout_revisions(forest, source))),
    #("targetRevisions", string_array(checkout_revisions(forest, target))),
  ])
}

fn run_merge() -> Result(Json, String) {
  use core <- result.try(initial_core())
  use view <- result.try(
    schema.view_from_string(tree_schema) |> result.map_error(string.inspect),
  )
  use #(core, source_id) <- result.try(
    core_result(runtime_core.fork_tree(
      core,
      tree_address,
      types.DocumentCheckout,
      view,
    )),
  )
  let source = types.LocalCheckout(source_id)
  use #(core, first_events, first_outbound) <- result.try(
    core_result(
      runtime_core.submit_tree_edits_on(core, tree_address, source, [
        types.SetField(["title"], types.StringValue("first")),
      ]),
    ),
  )
  use _ <- result.try(require_no_outbound(first_outbound, "local source edit"))
  use #(core, second_events, second_outbound) <- result.try(
    core_result(
      runtime_core.submit_tree_edits_on(core, tree_address, source, [
        types.SetField(["count"], types.NumberValue(2.0)),
      ]),
    ),
  )
  use _ <- result.try(require_no_outbound(second_outbound, "local source edit"))
  use forest <- result.try(core_forest(core))
  use source_checkout <- try_native(branch.checkout(forest, source))
  let source_revisions = checkout_revisions(forest, source_checkout)
  use #(core, target_events, target_outbound) <- result.try(
    core_result(runtime_core.merge_tree(
      core,
      tree_address,
      types.DocumentCheckout,
      source,
      False,
    )),
  )
  use _ <- result.try(require_outbound(target_outbound, "document merge"))
  use forest <- result.try(core_forest(core))
  use document <- try_native(branch.checkout(forest, types.DocumentCheckout))
  let target_revisions = checkout_revisions(forest, document)
  use compressor <- result.try(core_compressor(core))
  use target_events <- try_native(event_json(forest, target_events, compressor))
  use source_events <- try_native(event_json(
    forest,
    list.append(first_events, second_events),
    compressor,
  ))

  use #(core, repeated, repeated_outbound) <- result.try(
    core_result(runtime_core.merge_tree(
      core,
      tree_address,
      types.DocumentCheckout,
      source,
      False,
    )),
  )
  use _ <- result.try(require_no_outbound(
    repeated_outbound,
    "repeated empty merge",
  ))
  use #(core, empty_id) <- result.try(
    core_result(runtime_core.fork_tree(
      core,
      tree_address,
      types.DocumentCheckout,
      view,
    )),
  )
  let empty = types.LocalCheckout(empty_id)
  use #(core, _, empty_outbound) <- result.try(
    core_result(runtime_core.merge_tree(
      core,
      tree_address,
      types.DocumentCheckout,
      empty,
      True,
    )),
  )
  use _ <- result.try(require_no_outbound(empty_outbound, "empty merge"))
  use #(core, self_id) <- result.try(
    core_result(runtime_core.fork_tree(
      core,
      tree_address,
      types.DocumentCheckout,
      view,
    )),
  )
  let self = types.LocalCheckout(self_id)
  use #(core, _, self_outbound) <- result.try(
    core_result(runtime_core.merge_tree(core, tree_address, self, self, False)),
  )
  use _ <- result.try(require_no_outbound(self_outbound, "preserved self merge"))
  let self_preserved_disposed =
    runtime_core.tree_branch_status(core, tree_address, self)
    == runtime_core.BranchDisposed
  use #(core, _, disposed_self_outbound) <- result.try(
    core_result(runtime_core.merge_tree(core, tree_address, self, self, True)),
  )
  use _ <- result.try(require_no_outbound(
    disposed_self_outbound,
    "disposed self merge",
  ))
  use #(core, default_source_id) <- result.try(
    core_result(runtime_core.fork_tree(
      core,
      tree_address,
      types.DocumentCheckout,
      view,
    )),
  )
  let default_source = types.LocalCheckout(default_source_id)
  use #(core, _, default_edit_outbound) <- result.try(
    core_result(
      runtime_core.submit_tree_edits_on(core, tree_address, default_source, [
        types.SetField(["title"], types.StringValue("default-disposed")),
      ]),
    ),
  )
  use _ <- result.try(require_no_outbound(
    default_edit_outbound,
    "local source edit",
  ))
  use #(core, _, default_merge_outbound) <- result.try(
    core_result(runtime_core.merge_tree(
      core,
      tree_address,
      types.DocumentCheckout,
      default_source,
      True,
    )),
  )
  use _ <- result.try(require_outbound(default_merge_outbound, "document merge"))

  normalize_field_batches(
    json.object([
      #(
        "observations",
        fixture_codec.array([
          json.object([
            #("id", json.string("commit-boundaries")),
            #("sourceRevisions", string_array(source_revisions)),
            #("targetRevisions", string_array(target_revisions)),
            #("events", fixture_codec.array(target_events)),
            #("sourceEvents", fixture_codec.array(source_events)),
          ]),
          json.object([
            #("id", json.string("merge-edge-cases")),
            #("repeatedEventCount", json.int(list.length(repeated))),
            #(
              "emptyDisposed",
              json.bool(
                runtime_core.tree_branch_status(core, tree_address, empty)
                == runtime_core.BranchDisposed,
              ),
            ),
            #("selfPreservedDisposed", json.bool(self_preserved_disposed)),
            #(
              "selfDefaultDisposed",
              json.bool(
                runtime_core.tree_branch_status(core, tree_address, self)
                == runtime_core.BranchDisposed,
              ),
            ),
            #(
              "defaultDisposed",
              json.bool(
                runtime_core.tree_branch_status(
                  core,
                  tree_address,
                  default_source,
                )
                == runtime_core.BranchDisposed,
              ),
            ),
          ]),
        ]),
      ),
    ]),
  )
}

fn run_transactions() -> Result(Json, String) {
  use core <- result.try(initial_core())
  use view <- result.try(
    schema.view_from_string(tree_schema) |> result.map_error(string.inspect),
  )
  use #(core, source_id) <- result.try(
    core_result(runtime_core.fork_tree(
      core,
      tree_address,
      types.DocumentCheckout,
      view,
    )),
  )
  let source = types.LocalCheckout(source_id)
  use core <- result.try(
    core_result(
      runtime_core.begin_tree_transaction_on(
        core,
        tree_address,
        source,
        view,
        [],
      ),
    ),
  )
  use core <- result.try(core_without_output(
    runtime_core.submit_tree_edits_on(core, tree_address, source, [
      types.SetField(["title"], types.StringValue("outer")),
    ]),
    "outer transaction edit",
  ))
  use core <- result.try(
    core_result(
      runtime_core.begin_tree_transaction_on(
        core,
        tree_address,
        source,
        view,
        [],
      ),
    ),
  )
  use core <- result.try(core_without_output(
    runtime_core.submit_tree_edits_on(core, tree_address, source, [
      types.SetField(["count"], types.NumberValue(99.0)),
    ]),
    "nested transaction edit",
  ))
  use core <- result.try(core_without_events(
    runtime_core.abort_tree_transaction_on(core, tree_address, source),
    "nested transaction abort",
  ))
  use core <- result.try(core_without_output(
    runtime_core.submit_tree_edits_on(core, tree_address, source, [
      types.SetField(["count"], types.NumberValue(3.0)),
    ]),
    "outer transaction edit",
  ))
  use #(core, outer_events) <- result.try(core_without_outbound(
    runtime_core.commit_tree_transaction_on(core, tree_address, source),
    "local transaction commit",
  ))
  use outer_value <- result.try(core_visible_json(core, source))
  use forest <- result.try(core_forest(core))
  use source_checkout <- try_native(branch.checkout(forest, source))
  let outer_revisions = checkout_revisions(forest, source_checkout)
  use compressor <- result.try(core_compressor(core))
  use outer_events <- try_native(event_json(forest, outer_events, compressor))

  use guards <- result.try(transaction_guards(view))
  use constraint <- result.try(transaction_constraint(view))
  use cross_checkout <- result.try(transaction_cross_checkout(view))
  use abort_allocation <- result.try(transaction_abort_allocation(view))
  use _ <- result.try(transaction_owner_disposal_refusal(view))

  normalize_field_batches(
    json.object([
      #(
        "observations",
        fixture_codec.array([
          json.object([
            #("id", json.string("outer-commit")),
            #("value", outer_value),
            #("revisions", string_array(outer_revisions)),
            #("events", fixture_codec.array(outer_events)),
          ]),
          guards,
          constraint,
          cross_checkout,
          abort_allocation,
        ]),
      ),
    ]),
  )
}

fn transaction_guards(view: schema.ViewSchema) -> Result(Json, String) {
  use source_guard <- result.try(reconcile_guard(view, True, False))
  use target_guard <- result.try(reconcile_guard(view, False, False))
  use source_merge_guard <- result.try(reconcile_guard(view, True, True))
  use target_merge_guard <- result.try(reconcile_guard(view, False, True))
  use core <- result.try(initial_core())
  use #(core, id) <- result.try(
    core_result(runtime_core.fork_tree(
      core,
      tree_address,
      types.DocumentCheckout,
      view,
    )),
  )
  let source = types.LocalCheckout(id)
  use core <- result.try(
    core_result(
      runtime_core.begin_tree_transaction_on(
        core,
        tree_address,
        source,
        view,
        [],
      ),
    ),
  )
  use fork_guard <- result.try(require_transaction_guard(
    runtime_core.fork_tree(core, tree_address, source, view),
    "source checkout has an active transaction",
    "source-active",
  ))
  Ok(
    json.object([
      #("id", json.string("guards")),
      #("sourceGuard", json.string(source_guard)),
      #("targetGuard", json.string(target_guard)),
      #("sourceMergeGuard", json.string(source_merge_guard)),
      #("targetMergeGuard", json.string(target_merge_guard)),
      #("forkGuard", json.string(fork_guard)),
    ]),
  )
}

fn reconcile_guard(
  view: schema.ViewSchema,
  active_source: Bool,
  merge: Bool,
) -> Result(String, String) {
  use core <- result.try(initial_core())
  use #(core, source_id) <- result.try(
    core_result(runtime_core.fork_tree(
      core,
      tree_address,
      types.DocumentCheckout,
      view,
    )),
  )
  use #(core, target_id) <- result.try(
    core_result(runtime_core.fork_tree(
      core,
      tree_address,
      types.DocumentCheckout,
      view,
    )),
  )
  let source = types.LocalCheckout(source_id)
  let target = types.LocalCheckout(target_id)
  let active = case active_source {
    True -> source
    False -> target
  }
  use core <- result.try(
    core_result(
      runtime_core.begin_tree_transaction_on(
        core,
        tree_address,
        active,
        view,
        [],
      ),
    ),
  )
  let operation = case merge {
    True -> runtime_core.merge_tree(core, tree_address, target, source, False)
    False ->
      runtime_core.rebase_tree_onto(core, tree_address, source, target)
      |> result.map(fn(value) { #(value.0, value.1, []) })
  }
  let token = case active_source, merge {
    True, False -> "source-active"
    False, False -> "target-active"
    True, True -> "source-active"
    False, True -> "target-active"
  }
  require_transaction_guard(
    operation,
    "affected checkout has an active transaction",
    token,
  )
}

fn require_transaction_guard(
  guarded: Result(a, runtime_core.CoreError),
  detail: String,
  token: String,
) -> Result(String, String) {
  case guarded {
    Error(runtime_core.TreeOperationFailed(
      address,
      types.InvalidHistory(actual),
    ))
      if address == tree_address && actual == detail
    -> Ok(token)
    Error(error) ->
      Error(
        "unexpected transaction guard "
        <> string.inspect(error)
        <> "; expected "
        <> detail,
      )
    Ok(_) -> Error("transaction guard operation succeeded")
  }
}

fn transaction_constraint(view: schema.ViewSchema) -> Result(Json, String) {
  use core <- result.try(initial_core())
  use #(core, source_id) <- result.try(
    core_result(runtime_core.fork_tree(
      core,
      tree_address,
      types.DocumentCheckout,
      view,
    )),
  )
  let source = types.LocalCheckout(source_id)
  use core <- result.try(
    core_result(
      runtime_core.begin_tree_transaction_on(core, tree_address, source, view, [
        ["featured"],
      ]),
    ),
  )
  use core <- result.try(core_without_output(
    runtime_core.submit_tree_edits_on(core, tree_address, source, [
      types.SetField(["title"], types.StringValue("constrained-change")),
    ]),
    "constrained transaction edit",
  ))
  use #(core, _) <- result.try(core_without_outbound(
    runtime_core.commit_tree_transaction_on(core, tree_address, source),
    "constrained local transaction commit",
  ))
  use #(core, _, _) <- result.try(
    core_result(
      runtime_core.submit_tree_edits_on(
        core,
        tree_address,
        types.DocumentCheckout,
        [types.SetField(["featured"], point("replacement"))],
      ),
    ),
  )
  use #(core, _) <- result.try(
    core_result(runtime_core.rebase_tree_onto(
      core,
      tree_address,
      source,
      types.DocumentCheckout,
    )),
  )
  use source_value <- result.try(core_visible_json(core, source))
  use target_value <- result.try(core_visible_json(core, types.DocumentCheckout))
  use forest <- result.try(core_forest(core))
  use source_checkout <- try_native(branch.checkout(forest, source))
  Ok(
    json.object([
      #("id", json.string("constraint")),
      #("source", source_value),
      #("target", target_value),
      #("revisions", string_array(checkout_revisions(forest, source_checkout))),
    ]),
  )
}

fn transaction_cross_checkout(view: schema.ViewSchema) -> Result(Json, String) {
  use changed <- result.try(cross_checkout_case(view, False, False))
  use committed <- result.try(cross_checkout_case(view, True, False))
  use failed <- result.try(cross_checkout_case(view, False, True))
  use _ <- result.try(case changed && committed && failed {
    True -> Ok(Nil)
    False -> Error("independent main edit did not survive owner completion")
  })
  Ok(
    json.object([
      #("id", json.string("cross-checkout")),
      #("error", json.string("")),
      #("changedMain", json.bool(changed)),
    ]),
  )
}

fn cross_checkout_case(
  view: schema.ViewSchema,
  commit: Bool,
  callback_error: Bool,
) -> Result(Bool, String) {
  use core <- result.try(initial_core())
  use #(core, source_id) <- result.try(
    core_result(runtime_core.fork_tree(
      core,
      tree_address,
      types.DocumentCheckout,
      view,
    )),
  )
  let source = types.LocalCheckout(source_id)
  use core <- result.try(
    core_result(
      runtime_core.begin_tree_transaction_on(
        core,
        tree_address,
        source,
        view,
        [],
      ),
    ),
  )
  use #(core, main_events, main_outbound) <- result.try(
    core_result(
      runtime_core.submit_tree_edits_on(
        core,
        tree_address,
        types.DocumentCheckout,
        [
          types.SetField(
            ["title"],
            types.StringValue(case callback_error {
              True -> "callback-error"
              False -> "cross-checkout"
            }),
          ),
        ],
      ),
    ),
  )
  use _ <- result.try(require_outbound(main_outbound, "independent main edit"))
  use _ <- result.try(case main_events {
    [#(_, types.DocumentCheckout, channel.TreeCommitApplied(_, _, _, _)), ..] ->
      Ok(Nil)
    _ -> Error("independent main edit emitted no commit event")
  })
  use core <- result.try(case commit {
    True ->
      runtime_core.commit_tree_transaction_on(core, tree_address, source)
      |> core_result
      |> result.map(fn(value) { value.0 })
    False ->
      runtime_core.abort_tree_transaction_on(core, tree_address, source)
      |> core_result
      |> result.map(fn(value) { value.0 })
  })
  runtime_core.tree_read(core, tree_address, ["title"])
  |> result.map_error(string.inspect)
  |> result.map(fn(value) {
    value
    == Some(
      types.StringValue(case callback_error {
        True -> "callback-error"
        False -> "cross-checkout"
      }),
    )
  })
}

fn transaction_abort_allocation(
  view: schema.ViewSchema,
) -> Result(Json, String) {
  use core <- result.try(initial_core())
  use #(core, source_id) <- result.try(
    core_result(runtime_core.fork_tree(
      core,
      tree_address,
      types.DocumentCheckout,
      view,
    )),
  )
  let source = types.LocalCheckout(source_id)
  use before_value <- result.try(core_visible_json(core, source))
  use compressor <- result.try(core_compressor(core))
  use before <- result.try(
    fluid_ids.serialize(compressor, True) |> result.map_error(string.inspect),
  )
  use core <- result.try(
    core_result(
      runtime_core.begin_tree_transaction_on(
        core,
        tree_address,
        source,
        view,
        [],
      ),
    ),
  )
  use core <- result.try(core_without_output(
    runtime_core.submit_tree_edits_on(core, tree_address, source, [
      types.ArrayInsert(["right"], 0, [point("aborted-allocation")]),
    ]),
    "aborted allocation edit",
  ))
  use core <- result.try(core_without_events(
    runtime_core.abort_tree_transaction_on(core, tree_address, source),
    "allocation transaction abort",
  ))
  use after_value <- result.try(core_visible_json(core, source))
  use compressor <- result.try(core_compressor(core))
  use after <- result.try(
    fluid_ids.serialize(compressor, True) |> result.map_error(string.inspect),
  )
  Ok(
    json.object([
      #("id", json.string("abort-allocation")),
      #(
        "stateRestored",
        json.bool(json.to_string(before_value) == json.to_string(after_value)),
      ),
      #(
        "allocationAdvanced",
        json.bool(json.to_string(before) != json.to_string(after)),
      ),
      #("before", before),
      #("after", after),
    ]),
  )
}

fn transaction_owner_disposal_refusal(
  view: schema.ViewSchema,
) -> Result(Nil, String) {
  use core <- result.try(initial_core())
  use #(core, source_id) <- result.try(
    core_result(runtime_core.fork_tree(
      core,
      tree_address,
      types.DocumentCheckout,
      view,
    )),
  )
  let source = types.LocalCheckout(source_id)
  use core <- result.try(
    core_result(
      runtime_core.begin_tree_transaction_on(
        core,
        tree_address,
        source,
        view,
        [],
      ),
    ),
  )
  use _ <- result.try(require_transaction_guard(
    runtime_core.dispose_tree_branch(core, tree_address, source),
    "checkout has an active transaction",
    "owner-active",
  ))
  use _ <- result.try(
    case runtime_core.tree_branch_status(core, tree_address, source) {
      runtime_core.BranchValid -> Ok(Nil)
      _ -> Error("active transaction owner was disposed")
    },
  )
  runtime_core.abort_tree_transaction_on(core, tree_address, source)
  |> core_result
  |> result.map(fn(_) { Nil })
}

fn run_allocation() -> Result(Json, String) {
  use core <- result.try(initial_core())
  use view <- result.try(
    schema.view_from_string(tree_schema) |> result.map_error(string.inspect),
  )
  use #(core, source_id) <- result.try(
    core_result(runtime_core.fork_tree(
      core,
      tree_address,
      types.DocumentCheckout,
      view,
    )),
  )
  let source = types.LocalCheckout(source_id)
  use compressor <- result.try(core_compressor(core))
  use before_branch <- result.try(
    fluid_ids.serialize(compressor, True) |> result.map_error(string.inspect),
  )
  use #(core, _, branch_outbound) <- result.try(
    core_result(
      runtime_core.submit_tree_edits_on(core, tree_address, source, [
        types.ArrayInsert(["right"], 0, [point("branch-id")]),
      ]),
    ),
  )
  use _ <- result.try(require_no_outbound(
    branch_outbound,
    "branch-only allocation",
  ))
  use compressor <- result.try(core_compressor(core))
  use after_branch <- result.try(
    fluid_ids.serialize(compressor, True) |> result.map_error(string.inspect),
  )

  use #(core, _, main_outbound) <- result.try(
    core_result(
      runtime_core.submit_tree_edits_on(
        core,
        tree_address,
        types.DocumentCheckout,
        [types.ArrayInsert(["left"], 1, [point("main-id")])],
      ),
    ),
  )
  use #(main_ranges, main_messages) <- result.try(publication_json(
    main_outbound,
    "main publication",
  ))
  use _ <- result.try(reversed_publication_is_rejected(
    main_outbound,
    "main publication",
  ))
  use core <- result.try(sequence_publication(core, main_outbound))

  use compressor <- result.try(core_compressor(core))
  use before_abort <- result.try(
    fluid_ids.serialize(compressor, True) |> result.map_error(string.inspect),
  )
  use core <- result.try(
    core_result(
      runtime_core.begin_tree_transaction_on(
        core,
        tree_address,
        source,
        view,
        [],
      ),
    ),
  )
  use core <- result.try(core_without_output(
    runtime_core.submit_tree_edits_on(core, tree_address, source, [
      types.ArrayInsert(["right"], 1, [point("aborted-id")]),
    ]),
    "aborted range edit",
  ))
  use core <- result.try(core_without_events(
    runtime_core.abort_tree_transaction_on(core, tree_address, source),
    "range transaction abort",
  ))
  use compressor <- result.try(core_compressor(core))
  use after_abort <- result.try(
    fluid_ids.serialize(compressor, True) |> result.map_error(string.inspect),
  )

  use #(core, _, merge_outbound) <- result.try(
    core_result(runtime_core.merge_tree(
      core,
      tree_address,
      types.DocumentCheckout,
      source,
      True,
    )),
  )
  use #(merge_ranges, merge_messages) <- result.try(publication_json(
    merge_outbound,
    "merge publication",
  ))
  use core <- result.try(sequence_publication(core, merge_outbound))
  use identifiers <- result.try(
    list.try_map(
      [["left", "0", "id"], ["left", "1", "id"], ["right", "0", "id"]],
      fn(path) {
        use value <- result.try(
          runtime_core.tree_read(core, tree_address, path)
          |> result.map_error(string.inspect),
        )
        case value {
          Some(types.StringValue(id)) -> Ok(id)
          _ -> Error("published point has no Identifier")
        }
      },
    ),
  )
  use _ <- result.try(case list.unique(identifiers) == identifiers {
    True -> Ok(Nil)
    False -> Error("interleaved Identifiers are not unique")
  })
  use _ <- result.try(singleton_publication_is_ungrouped(view))

  normalize_field_batches(
    json.object([
      #(
        "observations",
        fixture_codec.array([
          json.object([
            #("id", json.string("branch-only")),
            #("messages", fixture_codec.array([])),
            #("allocationRanges", fixture_codec.array([])),
            #(
              "reservationAdvanced",
              json.bool(
                json.to_string(before_branch) != json.to_string(after_branch),
              ),
            ),
            #("before", before_branch),
            #("after", after_branch),
          ]),
          json.object([
            #("id", json.string("main-publication")),
            #("allocationRanges", fixture_codec.array(main_ranges)),
            #("messages", fixture_codec.array(main_messages)),
          ]),
          json.object([
            #("id", json.string("merge-publication")),
            #("identifiers", string_array(identifiers)),
            #("allocationRanges", fixture_codec.array(merge_ranges)),
            #("messages", fixture_codec.array(merge_messages)),
          ]),
          json.object([
            #("id", json.string("abort-range")),
            #(
              "allocationAdvanced",
              json.bool(
                json.to_string(before_abort) != json.to_string(after_abort),
              ),
            ),
            #("before", before_abort),
            #("after", after_abort),
          ]),
        ]),
      ),
    ]),
  )
}

fn publication_json(
  outbound: List(wire.OutboundOperation),
  operation: String,
) -> Result(#(List(Json), List(Json)), String) {
  let assert [outbound] = outbound
  use batch <- result.try(
    fluid_container.decode(outbound.contents, outbound.metadata)
    |> result.map_error(string.inspect),
  )
  publication_batch_json(batch, operation)
}

fn publication_batch_json(
  batch: fluid_container.DecodedBatch,
  operation: String,
) -> Result(#(List(Json), List(Json)), String) {
  case batch.messages {
    [
      fluid_container.ContainerMessage(
        fluid_container.IdAllocation(range),
        0,
        _,
      ),
      fluid_container.ContainerMessage(
        fluid_container.ChannelOperation(
          fluid_container.Route("A", "_C"),
          contents,
        ),
        1,
        _,
      ),
    ] -> {
      use range <- result.try(
        fluid_ids.creation_range_to_json(range)
        |> result.map_error(string.inspect),
      )
      Ok(#([range], [contents]))
    }
    _ -> Error(operation <> " did not publish one range before one tree op")
  }
}

fn reversed_publication_is_rejected(
  outbound: List(wire.OutboundOperation),
  operation: String,
) -> Result(Nil, String) {
  let assert [outbound] = outbound
  use batch <- result.try(
    fluid_container.decode(outbound.contents, outbound.metadata)
    |> result.map_error(string.inspect),
  )
  let reversed =
    fluid_container.DecodedBatch(
      ..batch,
      messages: list.reverse(batch.messages),
    )
  case publication_batch_json(reversed, operation) {
    Error(_) -> Ok(Nil)
    Ok(_) -> Error(operation <> " accepted reversed message order")
  }
}

fn sequence_publication(
  core: runtime_core.Core,
  outbound: List(wire.OutboundOperation),
) -> Result(runtime_core.Core, String) {
  let assert [outbound] = outbound
  use contents <- result.try(
    json.parse(json.to_string(outbound.contents), decode.dynamic)
    |> result.map_error(fn(_) { "publication contents are not dynamic JSON" }),
  )
  use metadata <- result.try(case outbound.metadata {
    None -> Ok(None)
    Some(value) ->
      json.parse(json.to_string(value), decode.dynamic)
      |> result.map(Some)
      |> result.map_error(fn(_) { "publication metadata is not dynamic JSON" })
  })
  let message =
    spillway_types.SequencedDocumentMessage(
      client_id: Some(core.client_id),
      sequence_number: core.last_seen_sequence_number + 1,
      minimum_sequence_number: core.minimum_sequence_number,
      client_sequence_number: outbound.client_sequence_number,
      reference_sequence_number: outbound.reference_sequence_number,
      message_type: outbound.operation_type,
      contents: contents,
      metadata: metadata,
      server_metadata: None,
      origin: None,
      traces: None,
      timestamp: 0,
      data: None,
    )
  use #(core, _) <- result.try(
    core_result(runtime_core.handle_sequenced(core, message)),
  )
  case core.in_flight {
    [] -> Ok(core)
    _ -> Error("sequenced publication remains in flight")
  }
}

fn singleton_publication_is_ungrouped(
  view: schema.ViewSchema,
) -> Result(Nil, String) {
  use core <- result.try(initial_core())
  use #(core, first_id) <- result.try(
    core_result(runtime_core.fork_tree(
      core,
      tree_address,
      types.DocumentCheckout,
      view,
    )),
  )
  let first = types.LocalCheckout(first_id)
  use #(core, _) <- result.try(core_without_outbound(
    runtime_core.submit_tree_edits_on(core, tree_address, first, [
      types.SetField(["title"], types.StringValue("first")),
    ]),
    "first local edit",
  ))
  use #(core, second_id) <- result.try(
    core_result(runtime_core.fork_tree(core, tree_address, first, view)),
  )
  let second = types.LocalCheckout(second_id)
  use #(core, _) <- result.try(core_without_outbound(
    runtime_core.submit_tree_edits_on(core, tree_address, second, [
      types.SetField(["count"], types.NumberValue(2.0)),
    ]),
    "second local edit",
  ))
  use #(core, _, _) <- result.try(
    core_result(runtime_core.merge_tree(
      core,
      tree_address,
      types.DocumentCheckout,
      first,
      False,
    )),
  )
  use #(_, _, outbound) <- result.try(
    core_result(runtime_core.merge_tree(
      core,
      tree_address,
      types.DocumentCheckout,
      second,
      False,
    )),
  )
  let assert [outbound] = outbound
  use batch <- result.try(
    fluid_container.decode(outbound.contents, outbound.metadata)
    |> result.map_error(string.inspect),
  )
  case batch {
    fluid_container.DecodedBatch(
      False,
      _,
      [
        fluid_container.ContainerMessage(
          fluid_container.ChannelOperation(_, _),
          0,
          _,
        ),
      ],
    ) -> Ok(Nil)
    _ -> Error("singleton publication without a range was grouped")
  }
}

fn checkout_revisions(
  forest: branch.Forest,
  checkout: branch.Checkout,
) -> List(String) {
  let assert Ok(view) = branch.history_view(forest, checkout)
  let trunk =
    list.map(view.sequenced.trunk, fn(entry) { entry.commit.revision })
  let revisions = case branch.checkout_selector(checkout) {
    types.DocumentCheckout ->
      list.append(trunk, list.map(view.pending, fn(commit) { commit.revision }))
    types.LocalCheckout(_) -> {
      let assert Ok(history.LocalBranch(_, base, commits)) =
        branch.local_history(forest, checkout)
      list.append(
        retained_base_path(trunk, base, []),
        list.map(commits, fn(commit) { commit.revision }),
      )
    }
  }
  list.map(revisions, fluid_ids.stable_id_to_string)
}

fn retained_base_path(
  trunk: List(fluid_ids.StableId),
  base: option.Option(fluid_ids.StableId),
  path: List(fluid_ids.StableId),
) -> List(fluid_ids.StableId) {
  case trunk, base {
    _, None -> []
    [], Some(_) -> list.reverse(path)
    [revision, ..rest], Some(base) ->
      case revision == base {
        True -> list.reverse([revision, ..path])
        False -> retained_base_path(rest, Some(base), [revision, ..path])
      }
  }
}

fn event_json(
  forest: branch.Forest,
  events: List(runtime_core.ScopedTreeEvent),
  compressor: fluid_ids.Compressor,
) -> Result(List(Json), types.TreeError) {
  events
  |> list.filter(fn(event) {
    case event.2 {
      channel.TreeCommitApplied(_, _, _, _) -> True
      _ -> False
    }
  })
  |> list.index_map(fn(event, index) { #(event, index) })
  |> list.try_map(fn(entry) {
    let #(event, index) = entry
    let #(_address, selector, metadata) = event
    let assert channel.TreeCommitApplied(revision, kind, local, advertised) =
      metadata
    use checkout <- result.try(branch.checkout(forest, selector))
    use commit <- result.try(commit_at(forest, checkout, revision))
    use change <- result.try(event_change(commit, compressor))
    use factory <- result.try(case advertised {
      False -> Ok(False)
      True -> {
        use #(retained, revertible) <- result.try(branch.retain_revertible(
          forest,
          checkout,
          revision,
          kind,
        ))
        Ok(branch.revertible_is_valid(retained, revertible))
      }
    })
    Ok(
      json.object([
        #("index", json.int(index)),
        #("kind", commit_kind_json(kind)),
        #("local", json.bool(local)),
        #("factory", json.bool(factory)),
        #("change", change),
      ]),
    )
  })
}

fn commit_at(
  forest: branch.Forest,
  checkout: branch.Checkout,
  revision: fluid_ids.StableId,
) -> Result(history.Commit, types.TreeError) {
  use view <- result.try(branch.history_view(forest, checkout))
  let sequenced =
    list.map(view.sequenced.trunk, fn(entry) {
      let history.SequencedCommit(commit, _) = entry
      commit
    })
  let local = case branch.local_history(forest, checkout) {
    Ok(history.LocalBranch(_, _, commits)) -> commits
    Error(_) -> []
  }
  list.find(
    list.append(sequenced, list.append(view.pending, local)),
    fn(commit) { commit.revision == revision },
  )
  |> result.map_error(fn(_) {
    types.InvalidHistory("runtime branch event has no matching commit")
  })
}

fn event_change(
  commit: history.Commit,
  compressor: fluid_ids.Compressor,
) -> Result(Json, types.TreeError) {
  use change <- result.try(codec.encode_changes(
    shared_change.to_changes(commit.change),
    codec.EncodeContext(codec.Fluid310, compressor, None),
    codec.ChangeContext(commit.originator, None, codec.Message),
  ))
  use revision <- result.try(codec.encode_stable_revision(
    commit.revision,
    codec.EncodeContext(codec.Fluid310, compressor, None),
    "branch fixture revision",
  ))
  Ok(
    json.object([
      #("version", json.int(1)),
      #("revision", json.int(revision)),
      #(
        "originatorId",
        json.string(fluid_ids.session_id_to_string(commit.originator)),
      ),
      #("change", change),
    ]),
  )
}

fn commit_kind_json(kind: types.TreeCommitKind) -> Json {
  json.string(case kind {
    types.DefaultCommit -> "Default"
    types.UndoCommit -> "Undo"
    types.RedoCommit -> "Redo"
  })
}

fn initial_state() -> Result(State, String) {
  use session <- result.try(
    fluid_ids.session_id(fixture_session) |> result.map_error(string.inspect),
  )
  use view_id <- result.try(
    fluid_ids.stable_id(fixture_view) |> result.map_error(string.inspect),
  )
  use stored <- result.try(
    schema.stored_from_string(tree_schema) |> result.map_error(string.inspect),
  )
  use optional_stored <- result.try(
    schema.stored_from_string(optional_tree_schema)
    |> result.map_error(string.inspect),
  )
  use optional_view <- result.try(
    schema.view_from_string(optional_tree_schema)
    |> result.map_error(string.inspect),
  )
  use view <- result.try(
    schema.view_from_string(tree_schema) |> result.map_error(string.inspect),
  )
  let compressor = fluid_ids.new(session)
  use #(root, compressor) <- result.try(
    identifier.materialize_value(stored, initial_root(), compressor)
    |> result.map_error(string.inspect),
  )
  use optional_snapshot <- result.try(
    tree_kernel.snapshot_from_parts(
      view_id,
      optional_stored,
      forest.ForestData(None, [], 0),
      history.inspect(history.new(session)).sequenced,
    )
    |> result.map_error(string.inspect),
  )
  use optional_state <- result.try(
    tree_runtime.restore(optional_snapshot, view_id, optional_view, compressor)
    |> result.map_error(string.inspect),
  )
  use #(compressor, revision_id) <- result.try(
    fluid_ids.generate(compressor) |> result.map_error(string.inspect),
  )
  use revision <- result.try(
    fluid_ids.decompress(compressor, revision_id)
    |> result.map_error(string.inspect),
  )
  use order <- result.try(
    codec.identity_order(
      [revision],
      compressor,
      "branch fixture initialization",
    )
    |> result.map_error(string.inspect),
  )
  use data_change <- result.try(
    tree_kernel.author_local_change(
      optional_state,
      revision,
      order,
      types.SetField([], root),
    )
    |> result.map_error(string.inspect),
  )
  use #(initialized, _) <- result.try(
    tree_kernel.apply_local_preview(
      optional_state,
      revision,
      order,
      data_change,
    )
    |> result.map_error(string.inspect),
  )
  use changes <- result.try(
    shared_change.from_changes([
      shared_change.SchemaChange(
        schema.EmptySchema,
        schema.FixedSchema(optional_stored),
        False,
      ),
      ..list.append(shared_change.to_changes(data_change), [
        shared_change.SchemaChange(
          schema.FixedSchema(optional_stored),
          schema.FixedSchema(stored),
          False,
        ),
      ])
    ])
    |> result.map_error(string.inspect),
  )
  use initialized_data <- result.try(
    tree_kernel.visible_data(initialized) |> result.map_error(string.inspect),
  )
  let commit = history.Commit(revision, session, changes)
  use snapshot <- result.try(
    tree_kernel.snapshot_from_parts(
      view_id,
      stored,
      initialized_data,
      history.HistorySnapshot(
        history.InitialBase,
        [history.SequencedCommit(commit, types.SequencePoint(1, 0))],
        [],
        1,
        0,
        [],
      ),
    )
    |> result.map_error(string.inspect),
  )
  use tree <- result.try(
    tree_runtime.restore(snapshot, view_id, view, compressor)
    |> result.map_error(string.inspect),
  )
  let #(compressor, range) = fluid_ids.take_creation_range(compressor)
  use range <- result.try(range |> to_result("initial tree allocated no IDs"))
  use compressor <- result.try(
    fluid_ids.finalize(compressor, range) |> result.map_error(string.inspect),
  )
  Ok(State(tree:, compressor:))
}

fn initial_core() -> Result(runtime_core.Core, String) {
  use initial <- result.try(initial_state())
  use snapshot <- result.try(
    tree_kernel.snapshot(initial.tree) |> result.map_error(string.inspect),
  )
  use view <- result.try(
    schema.view_from_string(tree_schema) |> result.map_error(string.inspect),
  )
  use #(input, _) <- result.try(runtime_fixture.routed_seed_input())
  let assert [tree_view] = input.tree_views
  let input =
    runtime_core.BootstrapSeedInput(
      ..input,
      sequence_number: 1,
      minimum_sequence_number: 0,
      compressor: Some(initial.compressor),
      tree_views: [runtime_core.TreeViewSeed(..tree_view, view:)],
      channels: list.map(input.channels, fn(seed) {
        case seed.route == tree_view.route {
          True ->
            runtime_core.ChannelSeed(
              ..seed,
              snapshot: channel.TreeSnapshot(snapshot),
            )
          False -> seed
        }
      }),
    )
  use seed <- result.try(
    runtime_core.bootstrap_seed(input) |> result.map_error(string.inspect),
  )
  use bootstrapped <- result.try(
    runtime_core.bootstrap_seeded(
      runtime_fixture.connected("fixture", [], 1),
      seed,
    )
    |> result.map_error(string.inspect),
  )
  case bootstrapped {
    runtime_core.Complete(core) -> Ok(core)
    runtime_core.MissingPrefix(_, _, _, _) ->
      Error("branch fixture core bootstrap is missing a prefix")
  }
}

fn initial_root() -> types.TreeValue {
  types.ObjectValue(root_type, [
    #("title", types.StringValue("base")),
    #("count", types.NumberValue(0.0)),
    #("featured", point("featured")),
    #("left", types.ArrayValue(items_type, [point("left")])),
    #("right", types.ArrayValue(items_type, [])),
  ])
}

fn visible_json(
  forest: branch.Forest,
  checkout: branch.Checkout,
) -> Result(Json, String) {
  use data <- result.try(branch.visible_data(forest, checkout) |> native)
  let assert Some(root) = data.root
  root_json(root)
}

fn root_json(value: types.TreeValue) -> Result(Json, String) {
  let assert types.ObjectValue(_, fields) = value
  let assert Ok(types.StringValue(title)) = list.key_find(fields, "title")
  let assert Ok(types.NumberValue(count)) = list.key_find(fields, "count")
  use featured <- result.try(
    list.key_find(fields, "featured")
    |> result.map_error(fn(_) { "root has no featured field" }),
  )
  let assert Ok(types.ArrayValue(_, left)) = list.key_find(fields, "left")
  let assert Ok(types.ArrayValue(_, right)) = list.key_find(fields, "right")
  use featured <- result.try(point_json(featured))
  use left <- result.try(list.try_map(left, point_json))
  use right <- result.try(list.try_map(right, point_json))
  Ok(
    json.object([
      #("title", json.string(title)),
      #("count", json.float(count)),
      #("featured", featured),
      #("left", fixture_codec.array(left)),
      #("right", fixture_codec.array(right)),
    ]),
  )
}

fn point_json(value: types.TreeValue) -> Result(Json, String) {
  let assert types.ObjectValue(_, fields) = value
  let assert Ok(types.StringValue(id)) = list.key_find(fields, "id")
  let assert Ok(types.StringValue(label)) = list.key_find(fields, "label")
  Ok(
    json.object([
      #("id", json.string(id)),
      #("label", json.string(label)),
    ]),
  )
}

fn point(label: String) -> types.TreeValue {
  types.ObjectValue(point_type, [#("label", types.StringValue(label))])
}

fn string_array(values: List(String)) -> Json {
  json.array(values, json.string)
}

fn normalize_field_batches(value: Json) -> Result(Json, String) {
  use value <- result.try(fixture_codec.parse(value))
  normalize_value(value) |> result.map(fixture_codec_json)
}

fn normalize_value(value: JsonValue) -> Result(JsonValue, String) {
  case value {
    VArray(values) ->
      list.try_map(values, normalize_value) |> result.map(VArray)
    VObject(fields) ->
      list.try_map(fields, fn(entry) {
        let #(key, value) = entry
        case key {
          "sourceGuard" | "sourceMergeGuard" ->
            normalize_guard(value, key, "source-active")
            |> result.map(fn(value) { #(key, value) })
          "targetGuard" | "targetMergeGuard" ->
            normalize_guard(value, key, "target-active")
            |> result.map(fn(value) { #(key, value) })
          "forkGuard" ->
            normalize_guard(value, key, "source-active")
            |> result.map(fn(value) { #(key, value) })
          "editError" -> {
            let normalized = case value {
              VString("") -> VString("")
              VString(_) -> VString("error")
              _ -> value
            }
            Ok(#(key, normalized))
          }
          "trees" -> {
            case field_batch.decode(fixture_codec_json(value)) {
              Ok(fields) -> {
                use normalized <- result.try(
                  fixture_codec.parse(
                    json.array(fields, fn(roots) {
                      json.array(roots, fixtures.tree_value_to_json)
                    }),
                  ),
                )
                Ok(#(key, normalized))
              }
              Error(types.UnsupportedFeature(
                _,
                "numeric identifier decoding requires an ID context",
              )) -> Ok(#(key, value))
              Error(error) -> Error(string.inspect(error))
            }
          }
          _ -> normalize_value(value) |> result.map(fn(value) { #(key, value) })
        }
      })
      |> result.map(VObject)
    _ -> Ok(value)
  }
}

fn normalize_guard(
  value: JsonValue,
  field: String,
  token: String,
) -> Result(JsonValue, String) {
  let expected = case field {
    "sourceGuard" ->
      "Error: A view cannot be rebased while it has a pending transaction."
    "targetGuard" ->
      "Error: Views cannot be rebased onto a view that has a pending transaction."
    "sourceMergeGuard" ->
      "Error: Views with an open transaction cannot be merged into another view."
    "targetMergeGuard" ->
      "Error: Views cannot be merged into a view while it has a pending transaction."
    "forkGuard" ->
      "Error: A view cannot be forked while it has a pending transaction."
    _ -> ""
  }
  case value {
    VString(actual) if actual == expected || actual == token ->
      Ok(VString(token))
    _ -> Error("branch transaction guard differs at " <> field)
  }
}

fn fixture_codec_json(value: JsonValue) -> Json {
  json_ot.to_json(value)
}

fn native(value: Result(a, types.TreeError)) -> Result(a, String) {
  result.map_error(value, string.inspect)
}

fn core_result(value: Result(a, runtime_core.CoreError)) -> Result(a, String) {
  result.map_error(value, string.inspect)
}

fn core_without_output(
  value: Result(
    #(runtime_core.Core, List(runtime_core.ScopedTreeEvent), List(a)),
    runtime_core.CoreError,
  ),
  operation: String,
) -> Result(runtime_core.Core, String) {
  use #(core, events, outbound) <- result.try(core_result(value))
  case events, outbound {
    [], [] -> Ok(core)
    _, _ -> Error(operation <> " emitted events or outbound operations")
  }
}

fn core_without_events(
  value: Result(
    #(runtime_core.Core, List(runtime_core.ScopedTreeEvent)),
    runtime_core.CoreError,
  ),
  operation: String,
) -> Result(runtime_core.Core, String) {
  use #(core, events) <- result.try(core_result(value))
  case events {
    [] -> Ok(core)
    _ -> Error(operation <> " emitted events")
  }
}

fn core_without_outbound(
  value: Result(
    #(runtime_core.Core, List(runtime_core.ScopedTreeEvent), List(a)),
    runtime_core.CoreError,
  ),
  operation: String,
) -> Result(#(runtime_core.Core, List(runtime_core.ScopedTreeEvent)), String) {
  use #(core, events, outbound) <- result.try(core_result(value))
  case outbound {
    [] -> Ok(#(core, events))
    _ -> Error(operation <> " emitted outbound operations")
  }
}

fn core_forest(core: runtime_core.Core) -> Result(branch.Forest, String) {
  dict.get(core.tree_checkouts, tree_address)
  |> result.map_error(fn(_) { "branch fixture core has no checkout forest" })
}

fn core_visible_json(
  core: runtime_core.Core,
  selector: types.CheckoutSelector,
) -> Result(Json, String) {
  use value <- result.try(
    runtime_core.tree_read_on(core, tree_address, selector, [])
    |> result.map_error(string.inspect),
  )
  use value <- result.try(value |> to_result("branch fixture root is missing"))
  root_json(value)
}

fn core_featured_identity(
  core: runtime_core.Core,
  selector: types.CheckoutSelector,
) -> Result(String, String) {
  use value <- result.try(
    runtime_core.tree_read_on(core, tree_address, selector, ["featured", "id"])
    |> result.map_error(string.inspect),
  )
  let assert Some(types.StringValue(id)) = value
  Ok(id)
}

fn core_compressor(
  core: runtime_core.Core,
) -> Result(fluid_ids.Compressor, String) {
  core.compressor
  |> to_result("branch fixture core has no compressor")
}

fn require_no_outbound(
  outbound: List(a),
  operation: String,
) -> Result(Nil, String) {
  case outbound {
    [] -> Ok(Nil)
    _ -> Error(operation <> " unexpectedly emitted outbound operations")
  }
}

fn require_outbound(
  outbound: List(a),
  operation: String,
) -> Result(Nil, String) {
  case outbound {
    [] -> Error(operation <> " emitted no outbound operation")
    _ -> Ok(Nil)
  }
}

fn try_native(
  value: Result(a, types.TreeError),
  next: fn(a) -> Result(b, String),
) -> Result(b, String) {
  result.try(native(value), next)
}
