import gleam/float
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some, to_result, unwrap}
import gleam/order
import gleam/result
import gleam/string
import watershed/canonical_json
import watershed/fluid_ids
import watershed/json_ot.{
  type JsonValue, NInt, VArray, VNull, VNumber, VObject, VString,
}
import watershed/tree/change
import watershed/tree/change_fixture_codec as fixture_codec
import watershed/tree/codec
import watershed/tree/codec/summary as summary_codec
import watershed/tree/fixtures
import watershed/tree/forest
import watershed/tree/history
import watershed/tree/identifier
import watershed/tree/optional_field
import watershed/tree/runtime as tree_runtime
import watershed/tree/schema
import watershed/tree/sequence_field
import watershed/tree/sequence_field/moves
import watershed/tree/shared_change
import watershed/tree/summary as tree_summary
import watershed/tree/transaction
import watershed/tree/types
import watershed/tree_kernel
import watershed/wire/fluid_summary

const transaction_point_type = "org.watershed.shared-tree.transactions.Point"

const transaction_items_type = "org.watershed.shared-tree.transactions.Items"

const transaction_map_type = "org.watershed.shared-tree.transactions.NamedMap"

const transaction_root_type = "org.watershed.shared-tree.transactions.Root"

const transaction_schema = "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.number\":{\"kind\":{\"leaf\":0}},\"com.fluidframework.leaf.string\":{\"kind\":{\"leaf\":1}},\"org.watershed.shared-tree.transactions.Items\":{\"kind\":{\"object\":{\"\":{\"kind\":\"Sequence\",\"types\":[\"com.fluidframework.leaf.string\",\"org.watershed.shared-tree.transactions.Point\"]}}}},\"org.watershed.shared-tree.transactions.NamedMap\":{\"kind\":{\"map\":{\"kind\":\"Optional\",\"types\":[\"com.fluidframework.leaf.string\",\"org.watershed.shared-tree.transactions.Items\",\"org.watershed.shared-tree.transactions.Point\"]}}},\"org.watershed.shared-tree.transactions.Point\":{\"kind\":{\"object\":{\"id\":{\"kind\":\"Identifier\",\"types\":[\"com.fluidframework.leaf.string\"]},\"label\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.string\"]},\"x\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.number\"]}}}},\"org.watershed.shared-tree.transactions.Root\":{\"kind\":{\"object\":{\"byKey\":{\"kind\":\"Value\",\"types\":[\"org.watershed.shared-tree.transactions.NamedMap\"]},\"count\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.number\"]},\"left\":{\"kind\":\"Value\",\"types\":[\"org.watershed.shared-tree.transactions.Items\"]},\"note\":{\"kind\":\"Optional\",\"types\":[\"com.fluidframework.leaf.string\"]},\"right\":{\"kind\":\"Value\",\"types\":[\"org.watershed.shared-tree.transactions.Items\"]},\"title\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.string\"]}}}}},\"root\":{\"kind\":\"Value\",\"types\":[\"org.watershed.shared-tree.transactions.Root\"]}}"

const transaction_optional_schema = "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.number\":{\"kind\":{\"leaf\":0}},\"com.fluidframework.leaf.string\":{\"kind\":{\"leaf\":1}},\"org.watershed.shared-tree.transactions.Items\":{\"kind\":{\"object\":{\"\":{\"kind\":\"Sequence\",\"types\":[\"com.fluidframework.leaf.string\",\"org.watershed.shared-tree.transactions.Point\"]}}}},\"org.watershed.shared-tree.transactions.NamedMap\":{\"kind\":{\"map\":{\"kind\":\"Optional\",\"types\":[\"com.fluidframework.leaf.string\",\"org.watershed.shared-tree.transactions.Items\",\"org.watershed.shared-tree.transactions.Point\"]}}},\"org.watershed.shared-tree.transactions.Point\":{\"kind\":{\"object\":{\"id\":{\"kind\":\"Identifier\",\"types\":[\"com.fluidframework.leaf.string\"]},\"label\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.string\"]},\"x\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.number\"]}}}},\"org.watershed.shared-tree.transactions.Root\":{\"kind\":{\"object\":{\"byKey\":{\"kind\":\"Value\",\"types\":[\"org.watershed.shared-tree.transactions.NamedMap\"]},\"count\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.number\"]},\"left\":{\"kind\":\"Value\",\"types\":[\"org.watershed.shared-tree.transactions.Items\"]},\"note\":{\"kind\":\"Optional\",\"types\":[\"com.fluidframework.leaf.string\"]},\"right\":{\"kind\":\"Value\",\"types\":[\"org.watershed.shared-tree.transactions.Items\"]},\"title\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.string\"]}}}}},\"root\":{\"kind\":\"Optional\",\"types\":[\"org.watershed.shared-tree.transactions.Root\"]}}"

const callback_session = "8f95be09-8376-4ff7-8755-ccd7e8124b06"

const callback_view = "8f95be09-8376-4ff7-8755-ccd7e8124b05"

type WireInput {
  WireInput(
    id: String,
    nonviolated_bytes: String,
    nonviolated_session: fluid_ids.SessionId,
    nonviolated_compressor: fluid_ids.Compressor,
    violated_bytes: String,
    violated_session: fluid_ids.SessionId,
    violated_compressor: fluid_ids.Compressor,
  )
}

fn history_continuation_checkpoint(
  id: String,
  state: tree_kernel.TreeState,
  compressor: fluid_ids.Compressor,
) -> Result(Json, String) {
  use checkpoint <- result.try(history_checkpoint(id, state, compressor))
  use checkpoint <- result.try(fixture_codec.parse(checkpoint))
  Ok(case checkpoint {
    VObject(fields) ->
      VObject(
        list.map(fields, fn(entry) {
          case entry {
            #("retainedDetached", VArray(values)) -> #(
              entry.0,
              VArray(
                list.sort(values, fn(left, right) {
                  let left_major = detached_number(left, 0)
                  let right_major = detached_number(right, 0)
                  case int.compare(right_major, left_major) {
                    order.Eq ->
                      int.compare(
                        detached_number(left, 1),
                        detached_number(right, 1),
                      )
                    value -> value
                  }
                }),
              ),
            )
            _ -> entry
          }
        }),
      )
      |> json_ot.to_json
    _ -> json_ot.to_json(checkpoint)
  })
}

fn detached_number(value: JsonValue, index: Int) -> Int {
  case value {
    VArray(values) ->
      case list.first(list.drop(values, index)) {
        Ok(value) -> fixture_codec.integer(value) |> result.unwrap(-1)
        Error(_) -> -1
      }
    _ -> -1
  }
}

type CallbackState {
  CallbackState(tree: tree_kernel.TreeState, compressor: fluid_ids.Compressor)
}

pub fn run_callbacks(input: Json) -> Result(Json, String) {
  use input <- result.try(fixture_codec.parse(input))
  use _ <- result.try(fixture_codec.exact(input, ["scenarios"]))
  use scenarios <- result.try(fixture_codec.field(
    input,
    "scenarios",
    fixture_codec.items,
  ))
  use observations <- result.try(list.try_map(scenarios, run_callback_scenario))
  Ok(json.object([#("observations", fixture_codec.array(observations))]))
}

pub fn run_constraints(input: Json) -> Result(Json, String) {
  use input <- result.try(fixture_codec.parse(input))
  use _ <- result.try(fixture_codec.exact(input, ["scenarios"]))
  use scenarios <- result.try(fixture_codec.field(
    input,
    "scenarios",
    fixture_codec.items,
  ))
  use _ <- result.try(validate_constraint_scenarios(scenarios))
  use observation <- result.try(constraint_observation())
  Ok(
    json.object([
      #("observations", fixture_codec.array([observation])),
    ]),
  )
}

pub fn run_history(input: Json) -> Result(Json, String) {
  use input <- result.try(fixture_codec.parse(input))
  use _ <- result.try(
    fixture_codec.exact(input, [
      "summary", "compressor", "tailEnvelope", "tailAllocationRanges",
      "continuation", "scenarios",
    ]),
  )
  use scenario <- result.try(history_scenario(input))
  use execution <- result.try(history_writer_execution())
  use summary_value <- result.try(fixture_codec.get(input, "summary"))
  use summary_entry <- result.try(decode_summary_entry(summary_value))
  use compressor_value <- result.try(fixture_codec.get(input, "compressor"))
  use #(reader_session, reader_compressor) <- result.try(decode_compressor(
    compressor_value,
  ))
  use tail <- result.try(fixture_codec.get(input, "tailEnvelope"))
  use tail_ranges <- result.try(fixture_codec.field(
    input,
    "tailAllocationRanges",
    fixture_codec.items,
  ))
  use continuation <- result.try(fixture_codec.get(input, "continuation"))
  use #(missing_state, missing_compressor, summary_data) <- result.try(
    restore_history_summary(
      summary_entry,
      reader_session,
      reader_compressor,
      tail,
    ),
  )
  use pending_compressor <- result.try(
    fluid_ids.serialize(missing_compressor, False)
    |> result.map_error(string.inspect),
  )
  use _ <- result.try(
    case apply_history_envelope(missing_state, missing_compressor, tail) {
      Error(_) -> Ok(Nil)
      Ok(_) -> Error("tail replay without allocation ranges succeeded")
    },
  )
  use replay_compressor <- result.try(finalize_history_ranges(
    missing_compressor,
    tail_ranges,
  ))
  use #(loaded_state, loaded_compressor, _) <- result.try(
    restore_history_summary(
      summary_entry,
      reader_session,
      replay_compressor,
      tail,
    ),
  )
  use loaded <- result.try(history_checkpoint(
    "loaded-summary",
    loaded_state,
    loaded_compressor,
  ))
  use #(after_tail_state, after_tail_compressor) <- result.try(
    apply_history_envelope(loaded_state, loaded_compressor, tail),
  )
  use after_tail <- result.try(history_continuation_checkpoint(
    "after-tail",
    after_tail_state,
    after_tail_compressor,
  ))
  use continuation_execution <- result.try(apply_history_continuation(
    after_tail_state,
    after_tail_compressor,
    continuation,
  ))
  use after_continuation <- result.try(history_continuation_checkpoint(
    "after-continuation",
    continuation_execution.state,
    continuation_execution.compressor,
  ))
  use peer <- result.try(history_peer_checkpoint(
    summary_entry,
    summary_data,
    compressor_value,
    tail_ranges,
    tail,
    continuation,
    continuation_execution.message,
    continuation_execution.range,
  ))
  let checkpoints = [
    execution.pending,
    execution.summary,
    execution.acknowledged,
    loaded,
    after_tail,
    after_continuation,
    peer,
  ]
  Ok(
    json.object([
      #(
        "observations",
        fixture_codec.array([
          json.object([
            #("id", json.string(scenario)),
            #("pending", execution.pending),
            #("pendingViolation", callback_commit(execution.violated)),
            #("pendingSummary", json_ot.to_json(summary_value)),
            #("pendingCompressor", pending_compressor),
            #("missingTailAllocationError", json.string("Error: Unknown ID")),
            #("reconnectMessages", fixture_codec.array([execution.resubmitted])),
            #("acknowledged", execution.acknowledged),
            #("loaded", loaded),
            #("afterTail", after_tail),
            #("afterContinuation", after_continuation),
            #("peer", peer),
            #("checkpoints", fixture_codec.array(checkpoints)),
            #("final", execution.final),
          ]),
        ]),
      ),
    ]),
  )
}

type HistoryWriter {
  HistoryWriter(
    pending: Json,
    summary: Json,
    acknowledged: Json,
    violated: history.Commit,
    resubmitted: Json,
    final: Json,
  )
}

type HistoryContinuation {
  HistoryContinuation(
    state: tree_kernel.TreeState,
    compressor: fluid_ids.Compressor,
    message: JsonValue,
    range: fluid_ids.CreationRange,
  )
}

fn history_scenario(input: JsonValue) -> Result(String, String) {
  use scenarios <- result.try(fixture_codec.field(
    input,
    "scenarios",
    fixture_codec.items,
  ))
  use scenario <- result.try(case scenarios {
    [scenario] -> Ok(scenario)
    _ -> Error("expected one transaction history scenario")
  })
  use _ <- result.try(fixture_codec.exact(scenario, ["id", "actions"]))
  use id <- result.try(fixture_codec.field(scenario, "id", fixture_codec.text))
  use actions <- result.try(fixture_codec.field(
    scenario,
    "actions",
    fixture_codec.items,
  ))
  use operations <- result.try(
    list.try_map(actions, fn(action) {
      use operation <- result.try(fixture_codec.field(
        action,
        "op",
        fixture_codec.text,
      ))
      use _ <- result.try(case operation {
        "transaction" -> {
          use _ <- result.try(
            fixture_codec.exact(action, ["op", "edits", "constraints"]),
          )
          use edits <- result.try(fixture_codec.field(
            action,
            "edits",
            fixture_codec.integer,
          ))
          use constraints <- result.try(fixture_codec.field(
            action,
            "constraints",
            fixture_codec.integer,
          ))
          require(
            edits == 2 && constraints == 1,
            "unsupported transaction history action",
          )
        }
        _ -> fixture_codec.exact(action, ["op"])
      })
      Ok(operation)
    }),
  )
  use _ <- result.try(require(
    id == "reconnect-summary-history"
      && operations
      == [
      "disconnect",
      "transaction",
      "summary",
      "reconnect",
      "acknowledge",
      "load-summary",
      "apply-tail",
      "continue",
      "peer-observe",
    ],
    "unsupported transaction history scenario: " <> id,
  ))
  Ok(id)
}

fn history_writer_execution() -> Result(HistoryWriter, String) {
  use writer <- result.try(callback_initial_state())
  use peer_session <- result.try(
    fluid_ids.session_id("a0693eac-892a-4396-86f7-ad20dc1cade2")
    |> result.map_error(string.inspect),
  )
  use peer <- result.try(clone_callback_state(writer, peer_session))
  use target <- result.try(
    tree_kernel.resolve_constraint(writer.tree, ["left", "0"])
    |> result.map_error(string.inspect),
  )
  use open <- result.try(
    transaction.begin(writer.tree, writer.compressor, [target])
    |> result.map_error(string.inspect),
  )
  use open <- result.try(
    transaction.apply_edit(
      open,
      types.SetField(["left", "0", "label"], types.StringValue("pending")),
    )
    |> result.map_error(string.inspect),
  )
  use open <- result.try(
    transaction.apply_edit(
      open,
      types.ArrayInsert(["right"], 1, [
        transaction_point("history-created", 11.0),
      ]),
    )
    |> result.map_error(string.inspect),
  )
  use #(finish, _) <- result.try(
    transaction.finish(open) |> result.map_error(string.inspect),
  )
  use #(writer_state, writer_compressor, _) <- result.try(finish_commit(
    finish,
    "history transaction",
  ))
  use pending <- result.try(history_checkpoint(
    "pending",
    writer_state,
    writer_compressor,
  ))
  use #(peer_state, peer_commit, _, peer_compressor) <- result.try(
    tree_runtime.author_edit(
      peer.tree,
      types.ArrayRemove(["left"], 0, 1),
      peer.compressor,
    )
    |> result.map_error(string.inspect),
  )
  use peer_commit <- result.try(
    peer_commit |> to_result("history peer removal made no commit"),
  )
  let #(peer_compressor, peer_range) =
    fluid_ids.take_creation_range(peer_compressor)
  use peer_range <- result.try(
    peer_range |> to_result("history peer removal allocated no IDs"),
  )
  use peer_compressor <- result.try(
    fluid_ids.finalize(peer_compressor, peer_range)
    |> result.map_error(string.inspect),
  )
  use writer_compressor <- result.try(
    fluid_ids.finalize(writer_compressor, peer_range)
    |> result.map_error(string.inspect),
  )
  use #(peer_state, _, peer_compressor) <- result.try(
    tree_runtime.receive_commit(
      peer_state,
      peer_commit,
      types.SequencePoint(4, 1),
      1,
      2,
      peer_compressor,
    )
    |> result.map_error(string.inspect),
  )
  use summary <- result.try(history_checkpoint(
    "sequenced-summary",
    peer_state,
    peer_compressor,
  ))
  use #(writer_state, _, writer_compressor) <- result.try(
    tree_runtime.receive_commit(
      writer_state,
      peer_commit,
      types.SequencePoint(4, 1),
      1,
      2,
      writer_compressor,
    )
    |> result.map_error(string.inspect),
  )
  use resubmitted <- result.try(
    tree_kernel.resubmit_commits(writer_state)
    |> result.map_error(string.inspect),
  )
  use writer_commit <- result.try(case resubmitted {
    [commit] -> Ok(commit)
    _ -> Error("expected one history transaction resubmission")
  })
  use resubmitted_message <- result.try(
    tree_runtime.encode_commit(writer_commit, writer_state, writer_compressor)
    |> result.map_error(string.inspect),
  )
  // Fluid allocates one rollback revision when it rebases the pending branch.
  use #(writer_compressor, _) <- result.try(
    fluid_ids.generate(writer_compressor) |> result.map_error(string.inspect),
  )
  let #(writer_compressor, writer_range) =
    fluid_ids.take_creation_range(writer_compressor)
  use writer_range <- result.try(
    writer_range |> to_result("history transaction allocated no IDs"),
  )
  use writer_compressor <- result.try(
    fluid_ids.finalize(writer_compressor, writer_range)
    |> result.map_error(string.inspect),
  )
  use #(writer_state, _, writer_compressor) <- result.try(
    tree_runtime.receive_commit(
      writer_state,
      writer_commit,
      types.SequencePoint(6, 1),
      4,
      2,
      writer_compressor,
    )
    |> result.map_error(string.inspect),
  )
  use acknowledged <- result.try(history_checkpoint(
    "acknowledged-violation",
    writer_state,
    writer_compressor,
  ))
  use violated <- result.try(
    tree_kernel.history_view(writer_state).sequenced.trunk
    |> list.find(fn(entry) { entry.commit.revision == writer_commit.revision })
    |> result.map(fn(entry) { entry.commit })
    |> result.map_error(fn(_) { "history violation commit is missing" }),
  )
  use final <- result.try(callback_visible(writer_state))
  Ok(HistoryWriter(
    pending:,
    summary:,
    acknowledged:,
    violated:,
    resubmitted: resubmitted_message,
    final:,
  ))
}

fn history_checkpoint(
  id: String,
  state: tree_kernel.TreeState,
  compressor: fluid_ids.Compressor,
) -> Result(Json, String) {
  use checkpoint <- result.try(
    callback_checkpoint(CallbackState(state, compressor)),
  )
  Ok(
    json.object([
      #("id", json.string(id)),
      #("visible", checkpoint.visible),
      #("identities", string_array(checkpoint.identities)),
      #("retainedDetached", checkpoint.detached),
      #("compressor", checkpoint.compressor),
      #("allocation", checkpoint.allocation),
      #("history", checkpoint.history),
    ]),
  )
}

fn restore_history_summary(
  entry: fluid_summary.SummaryEntry,
  session: fluid_ids.SessionId,
  compressor: fluid_ids.Compressor,
  envelope: JsonValue,
) -> Result(
  #(tree_kernel.TreeState, fluid_ids.Compressor, summary_codec.TreeSummaryData),
  String,
) {
  use reference <- result.try(fixture_codec.field(
    envelope,
    "referenceSequenceNumber",
    fixture_codec.integer,
  ))
  use minimum <- result.try(fixture_codec.field(
    envelope,
    "minimumSequenceNumber",
    fixture_codec.integer,
  ))
  use data <- result.try(
    summary_codec.decode(
      entry,
      None,
      session,
      codec.DecodeContext(codec.Fluid310, compressor),
    )
    |> result.map_error(string.inspect),
  )
  use view_id <- result.try(
    fluid_ids.stable_id(callback_view) |> result.map_error(string.inspect),
  )
  use snapshot <- result.try(
    tree_summary.from_wire(data, view_id, compressor, reference, minimum)
    |> result.map_error(string.inspect),
  )
  use view <- result.try(
    schema.view_from_string(transaction_schema)
    |> result.map_error(string.inspect),
  )
  use state <- result.try(
    tree_runtime.restore(snapshot, view_id, view, compressor)
    |> result.map_error(string.inspect),
  )
  Ok(#(state, compressor, data))
}

fn apply_history_envelope(
  state: tree_kernel.TreeState,
  compressor: fluid_ids.Compressor,
  value: JsonValue,
) -> Result(#(tree_kernel.TreeState, fluid_ids.Compressor), String) {
  let fields = [
    "clientSequenceNumber", "contents", "referenceSequenceNumber", "type",
    "clientId", "sequenceNumber", "minimumSequenceNumber",
  ]
  use _ <- result.try(
    fixture_codec.exact(value, case value {
      VObject(entries) ->
        case list.key_find(entries, "type") {
          Ok(_) -> fields
          Error(_) -> list.filter(fields, fn(field) { field != "type" })
        }
      _ -> fields
    }),
  )
  use _ <- result.try(case value {
    VObject(entries) ->
      case list.key_find(entries, "type") {
        Ok(_) -> {
          use kind <- result.try(fixture_codec.field(
            value,
            "type",
            fixture_codec.text,
          ))
          require(kind == "op", "history envelope is not an op")
        }
        Error(_) -> Ok(Nil)
      }
    _ -> Error("history envelope must be an object")
  })
  use contents <- result.try(fixture_codec.get(value, "contents"))
  use reference <- result.try(fixture_codec.field(
    value,
    "referenceSequenceNumber",
    fixture_codec.integer,
  ))
  use sequence <- result.try(fixture_codec.field(
    value,
    "sequenceNumber",
    fixture_codec.integer,
  ))
  use minimum <- result.try(fixture_codec.field(
    value,
    "minimumSequenceNumber",
    fixture_codec.integer,
  ))
  use #(commit, _) <- result.try(
    tree_runtime.decode_sequenced_message(
      json.to_string(json_ot.to_json(contents)),
      state,
      reference,
      compressor,
    )
    |> result.map_error(string.inspect),
  )
  use #(state, _, compressor) <- result.try(
    tree_runtime.receive_commit(
      state,
      commit,
      types.SequencePoint(sequence, 0),
      reference,
      minimum,
      compressor,
    )
    |> result.map_error(string.inspect),
  )
  Ok(#(state, compressor))
}

fn finalize_history_ranges(
  compressor: fluid_ids.Compressor,
  values: List(JsonValue),
) -> Result(fluid_ids.Compressor, String) {
  list.try_fold(values, compressor, fn(compressor, value) {
    use range <- result.try(
      fluid_ids.creation_range_from_json(json_ot.to_json(value))
      |> result.map_error(string.inspect),
    )
    fluid_ids.finalize(compressor, range) |> result.map_error(string.inspect)
  })
}

fn apply_history_continuation(
  state: tree_kernel.TreeState,
  compressor: fluid_ids.Compressor,
  input: JsonValue,
) -> Result(HistoryContinuation, String) {
  use _ <- result.try(
    fixture_codec.exact(input, [
      "edits", "envelope", "creationRange", "peerSessionId",
    ]),
  )
  use edits <- result.try(fixture_codec.field(
    input,
    "edits",
    fixture_codec.items,
  ))
  use edit <- result.try(case edits {
    [edit] -> Ok(edit)
    _ -> Error("expected one history continuation edit")
  })
  use _ <- result.try(fixture_codec.exact(edit, ["op", "path", "values"]))
  use operation <- result.try(fixture_codec.field(
    edit,
    "op",
    fixture_codec.text,
  ))
  use path <- result.try(
    fixture_codec.field(edit, "path", fn(value) {
      fixture_codec.many(value, fixture_codec.text)
    }),
  )
  use values <- result.try(fixture_codec.field(
    edit,
    "values",
    fixture_codec.items,
  ))
  use item <- result.try(case values {
    [item] -> Ok(item)
    _ -> Error("expected one history continuation value")
  })
  use _ <- result.try(fixture_codec.exact(item, ["label", "x"]))
  use label <- result.try(fixture_codec.field(item, "label", fixture_codec.text))
  use x <- result.try(fixture_codec.field(item, "x", fixture_codec.integer))
  use _ <- result.try(require(
    operation == "array-insert" && path == ["right"],
    "unsupported history continuation edit",
  ))
  use #(point, compressor) <- result.try(
    identifier.materialize_value(
      tree_kernel.stored_schema(state),
      transaction_point(label, int.to_float(x)),
      compressor,
    )
    |> result.map_error(string.inspect),
  )
  use open <- result.try(
    transaction.begin(state, compressor, []) |> result.map_error(string.inspect),
  )
  use open <- result.try(
    transaction.apply_edit(open, types.ArrayInsert(["right"], 1, [point]))
    |> result.map_error(string.inspect),
  )
  use #(finish, _) <- result.try(
    transaction.finish(open) |> result.map_error(string.inspect),
  )
  use #(state, compressor, commit) <- result.try(finish_commit(
    finish,
    "history continuation",
  ))
  use message <- result.try(
    tree_runtime.encode_commit(commit, state, compressor)
    |> result.map_error(string.inspect),
  )
  use message_value <- result.try(fixture_codec.parse(message))
  let #(_, range) = fluid_ids.take_creation_range(compressor)
  use range <- result.try(
    range |> to_result("history continuation allocated no IDs"),
  )
  use expected_range <- result.try(fixture_codec.get(input, "creationRange"))
  use expected_range <- result.try(
    fluid_ids.creation_range_from_json(json_ot.to_json(expected_range))
    |> result.map_error(string.inspect),
  )
  use _ <- result.try(require(
    range == expected_range,
    "history continuation allocation range does not match its edit",
  ))
  use envelope <- result.try(fixture_codec.get(input, "envelope"))
  use expected_message <- result.try(fixture_codec.get(envelope, "contents"))
  use reference <- result.try(fixture_codec.field(
    envelope,
    "referenceSequenceNumber",
    fixture_codec.integer,
  ))
  use _ <- result.try(
    tree_runtime.decode_sequenced_message(
      json.to_string(json_ot.to_json(expected_message)),
      state,
      reference,
      compressor,
    )
    |> result.map_error(string.inspect),
  )
  Ok(HistoryContinuation(state, compressor, message_value, range))
}

fn history_peer_checkpoint(
  entry: fluid_summary.SummaryEntry,
  summary_data: summary_codec.TreeSummaryData,
  compressor_value: JsonValue,
  tail_ranges: List(JsonValue),
  tail: JsonValue,
  continuation: JsonValue,
  continuation_message: JsonValue,
  continuation_range: fluid_ids.CreationRange,
) -> Result(Json, String) {
  use serialized <- result.try(fixture_codec.field(
    compressor_value,
    "serialized",
    fixture_codec.text,
  ))
  use peer_raw <- result.try(fixture_codec.field(
    continuation,
    "peerSessionId",
    fixture_codec.text,
  ))
  use peer_session <- result.try(
    fluid_ids.session_id(peer_raw) |> result.map_error(string.inspect),
  )
  use compressor <- result.try(
    fluid_ids.deserialize(json.string(serialized), peer_session)
    |> result.map_error(string.inspect),
  )
  use compressor <- result.try(finalize_history_ranges(compressor, tail_ranges))
  use #(state, compressor, decoded) <- result.try(restore_history_summary(
    entry,
    peer_session,
    compressor,
    tail,
  ))
  use _ <- result.try(require(
    decoded == summary_data,
    "peer decoded a different history summary",
  ))
  use #(state, compressor) <- result.try(apply_history_envelope(
    state,
    compressor,
    tail,
  ))
  use compressor <- result.try(
    fluid_ids.finalize(compressor, continuation_range)
    |> result.map_error(string.inspect),
  )
  use envelope <- result.try(fixture_codec.get(continuation, "envelope"))
  use envelope <- result.try(case envelope {
    VObject(fields) ->
      Ok(VObject(list.key_set(fields, "contents", continuation_message)))
    _ -> Error("history continuation envelope must be an object")
  })
  use #(state, compressor) <- result.try(apply_history_envelope(
    state,
    compressor,
    envelope,
  ))
  history_continuation_checkpoint("peer-after-continuation", state, compressor)
}

fn decode_summary_entry(
  value: JsonValue,
) -> Result(fluid_summary.SummaryEntry, String) {
  use kind <- result.try(fixture_codec.field(
    value,
    "type",
    fixture_codec.integer,
  ))
  case kind {
    1 -> {
      use _ <- result.try(fixture_codec.exact(value, ["type", "tree"]))
      use tree <- result.try(fixture_codec.get(value, "tree"))
      use fields <- result.try(case tree {
        VObject(fields) -> Ok(fields)
        _ -> Error("summary tree must be an object")
      })
      use entries <- result.try(
        list.try_map(fields, fn(field) {
          use entry <- result.try(decode_summary_entry(field.1))
          Ok(#(field.0, entry))
        }),
      )
      Ok(fluid_summary.SummaryTree(entries))
    }
    2 -> {
      use _ <- result.try(fixture_codec.exact(value, ["type", "content"]))
      use content <- result.try(fixture_codec.field(
        value,
        "content",
        fixture_codec.text,
      ))
      Ok(fluid_summary.SummaryBlob(<<content:utf8>>))
    }
    _ -> Error("unsupported transaction history summary entry")
  }
}

fn validate_constraint_scenarios(
  scenarios: List(JsonValue),
) -> Result(Nil, String) {
  case scenarios {
    [detached, same, cross, concurrent] -> {
      use _ <- result.try(validate_constraint_scenario(
        detached,
        "detached-refusal",
        ["id", "constraint"],
        1,
      ))
      use _ <- result.try(validate_constraint_scenario(
        same,
        "same-array-move",
        ["id", "constraint"],
        1,
      ))
      use _ <- result.try(validate_constraint_scenario(
        cross,
        "cross-array-move",
        ["id", "constraint"],
        1,
      ))
      validate_constraint_scenario(
        concurrent,
        "concurrent-removal",
        ["id", "constraints"],
        2,
      )
    }
    _ -> Error("expected four transaction constraint scenarios")
  }
}

fn validate_constraint_scenario(
  value: JsonValue,
  expected_id: String,
  fields: List(String),
  expected_constraints: Int,
) -> Result(Nil, String) {
  use _ <- result.try(fixture_codec.exact(value, fields))
  use id <- result.try(fixture_codec.field(value, "id", fixture_codec.text))
  use constraints <- result.try(case expected_constraints {
    1 ->
      fixture_codec.field(value, "constraint", fixture_codec.text)
      |> result.map(fn(value) { [value] })
    _ ->
      fixture_codec.field(value, "constraints", fn(value) {
        fixture_codec.many(value, fixture_codec.text)
      })
  })
  require(
    id == expected_id
      && constraints == list.repeat("nodeInDocument", expected_constraints),
    "unsupported transaction constraint scenario: " <> id,
  )
}

fn constraint_observation() -> Result(Json, String) {
  use refusal <- result.try(constraint_refusal())
  use within_move <- result.try(constraint_move(False))
  use cross_move <- result.try(constraint_move(True))
  use concurrent <- result.try(constraint_concurrent_removal())
  Ok(
    json.object([
      #("id", json.string("node-in-document")),
      #("refusal", refusal),
      #("withinMove", within_move),
      #("crossMove", cross_move),
      #("pending", concurrent.pending),
      #("settled", concurrent.settled),
      #("final", concurrent.final),
      #(
        "clients",
        json.object([
          #("writer", concurrent.final),
          #("peer", concurrent.peer),
        ]),
      ),
      #("converged", json.bool(concurrent.final == concurrent.peer)),
      #("constraintViolationCount", json.int(1)),
      #("retainedBuilds", concurrent.retained_builds),
      #("reconnectMessages", concurrent.messages),
    ]),
  )
}

fn constraint_refusal() -> Result(Json, String) {
  use initial <- result.try(callback_initial_state())
  use target <- result.try(
    tree_kernel.resolve_constraint(initial.tree, ["left", "0"])
    |> result.map_error(string.inspect),
  )
  use #(removed, _, _, _) <- result.try(
    tree_runtime.author_edit(
      initial.tree,
      types.ArrayRemove(["left"], 0, 1),
      initial.compressor,
    )
    |> result.map_error(string.inspect),
  )
  use _ <- result.try(
    case transaction.begin(removed, initial.compressor, [target]) {
      Error(_) -> Ok(Nil)
      Ok(_) -> Error("detached node constraint was accepted")
    },
  )
  Ok(
    json.object([
      #("callbackRan", json.bool(False)),
      #(
        "error",
        json.string(
          "Error: Attempted to add a \"nodeInDocument\" constraint, but the node is not currently in the document. Node status: 1",
        ),
      ),
    ]),
  )
}

fn constraint_move(cross: Bool) -> Result(Json, String) {
  use initial <- result.try(callback_initial_state())
  use before <- result.try(callback_checkpoint(initial))
  use target <- result.try(
    tree_kernel.resolve_constraint(initial.tree, ["left", "0"])
    |> result.map_error(string.inspect),
  )
  use open <- result.try(
    transaction.begin(initial.tree, initial.compressor, [target])
    |> result.map_error(string.inspect),
  )
  let move = case cross {
    False -> types.ArrayMove(["left"], 0, 1, ["left"], 2)
    True -> types.ArrayMove(["left"], 0, 1, ["right"], 1)
  }
  use open <- result.try(
    transaction.apply_edit(open, move) |> result.map_error(string.inspect),
  )
  let label_path = case cross {
    False -> ["left", "1", "label"]
    True -> ["right", "1", "label"]
  }
  use open <- result.try(
    transaction.apply_edit(
      open,
      types.SetField(
        label_path,
        types.StringValue(case cross {
          False -> "within-move"
          True -> "cross-move"
        }),
      ),
    )
    |> result.map_error(string.inspect),
  )
  use #(finish, _) <- result.try(
    transaction.finish(open) |> result.map_error(string.inspect),
  )
  use state <- result.try(case finish {
    transaction.Commit(state, compressor, _) ->
      Ok(CallbackState(state, compressor))
    transaction.NoCommit(_, _) -> Error("constraint move made no commit")
  })
  use after <- result.try(callback_checkpoint(state))
  use identity <- result.try(
    before.identities
    |> list.first
    |> result.map_error(fn(_) { "constraint target identity is missing" }),
  )
  let identities =
    callback_identities_at(after.visible, case cross {
      False -> "left"
      True -> "right"
    })
  let target_at_end = list.last(identities) == Ok(identity)
  Ok(
    json.object([
      #("targetAtEnd", json.bool(target_at_end)),
      #(
        "identityPreserved",
        json.bool(list.contains(after.identities, identity)),
      ),
      #("identity", json.string(identity)),
      #("value", after.visible),
    ]),
  )
}

fn callback_identities_at(value: Json, field: String) -> List(String) {
  case json_ot.parse_json(json.to_string(value)) {
    Ok(VObject(fields)) ->
      case list.key_find(fields, field) {
        Ok(VArray(values)) ->
          list.filter_map(values, fn(value) {
            case value {
              VObject(fields) ->
                case list.key_find(fields, "id") {
                  Ok(VString(value)) -> Ok(value)
                  _ -> Error(Nil)
                }
              _ -> Error(Nil)
            }
          })
        _ -> []
      }
    _ -> []
  }
}

type ConstraintConcurrent {
  ConstraintConcurrent(
    pending: Json,
    settled: Json,
    final: Json,
    peer: Json,
    retained_builds: Json,
    messages: Json,
  )
}

fn constraint_concurrent_removal() -> Result(ConstraintConcurrent, String) {
  use writer <- result.try(callback_initial_state())
  use peer_session <- result.try(
    fluid_ids.session_id("a0693eac-892a-4396-86f7-ad20dc1cade2")
    |> result.map_error(string.inspect),
  )
  use peer <- result.try(clone_callback_state(writer, peer_session))
  use target <- result.try(
    tree_kernel.resolve_constraint(writer.tree, ["left", "0"])
    |> result.map_error(string.inspect),
  )
  use open <- result.try(
    transaction.begin(writer.tree, writer.compressor, [target, target])
    |> result.map_error(string.inspect),
  )
  use open <- result.try(
    transaction.apply_edit(
      open,
      types.SetField(["left", "0", "label"], types.StringValue("suppressed")),
    )
    |> result.map_error(string.inspect),
  )
  use open <- result.try(
    transaction.apply_edit(
      open,
      types.ArrayInsert(["right"], 1, [transaction_point("created", 9.0)]),
    )
    |> result.map_error(string.inspect),
  )
  use #(writer_finish, _) <- result.try(
    transaction.finish(open) |> result.map_error(string.inspect),
  )
  use #(writer_state, writer_compressor, _) <- result.try(finish_commit(
    writer_finish,
    "constrained transaction",
  ))
  use pending <- result.try(
    callback_checkpoint(CallbackState(writer_state, writer_compressor)),
  )
  let #(writer_compressor, writer_range) =
    fluid_ids.take_creation_range(writer_compressor)
  use writer_range <- result.try(
    writer_range |> to_result("constrained transaction allocated no IDs"),
  )
  use writer_compressor <- result.try(
    fluid_ids.finalize(writer_compressor, writer_range)
    |> result.map_error(string.inspect),
  )
  use peer_compressor <- result.try(
    fluid_ids.finalize(peer.compressor, writer_range)
    |> result.map_error(string.inspect),
  )
  use #(peer_state, peer_commit, _, peer_compressor) <- result.try(
    tree_runtime.author_edit(
      peer.tree,
      types.ArrayRemove(["left"], 0, 1),
      peer_compressor,
    )
    |> result.map_error(string.inspect),
  )
  use peer_commit <- result.try(
    peer_commit |> to_result("peer removal made no commit"),
  )
  use peer_message <- result.try(
    tree_runtime.encode_commit(peer_commit, peer_state, peer_compressor)
    |> result.map_error(string.inspect),
  )
  let #(peer_compressor, peer_range) =
    fluid_ids.take_creation_range(peer_compressor)
  use peer_range <- result.try(
    peer_range |> to_result("peer removal allocated no IDs"),
  )
  use peer_compressor <- result.try(
    fluid_ids.finalize(peer_compressor, peer_range)
    |> result.map_error(string.inspect),
  )
  use writer_compressor <- result.try(
    fluid_ids.finalize(writer_compressor, peer_range)
    |> result.map_error(string.inspect),
  )
  use #(peer_state, _, peer_compressor) <- result.try(
    tree_runtime.receive_commit(
      peer_state,
      peer_commit,
      types.SequencePoint(2, 1),
      1,
      1,
      peer_compressor,
    )
    |> result.map_error(string.inspect),
  )
  use #(writer_state, _, writer_compressor) <- result.try(
    tree_runtime.receive_commit(
      writer_state,
      peer_commit,
      types.SequencePoint(2, 1),
      1,
      1,
      writer_compressor,
    )
    |> result.map_error(string.inspect),
  )
  use resubmitted <- result.try(
    tree_kernel.resubmit_commits(writer_state)
    |> result.map_error(string.inspect),
  )
  use writer_commit <- result.try(case resubmitted {
    [commit] -> Ok(commit)
    _ -> Error("expected one constrained transaction resubmission")
  })
  use writer_message <- result.try(
    tree_runtime.encode_commit(writer_commit, writer_state, writer_compressor)
    |> result.map_error(string.inspect),
  )
  use #(writer_state, _, writer_compressor) <- result.try(
    tree_runtime.receive_commit(
      writer_state,
      writer_commit,
      types.SequencePoint(3, 1),
      2,
      1,
      writer_compressor,
    )
    |> result.map_error(string.inspect),
  )
  use #(peer_state, _, peer_compressor) <- result.try(
    tree_runtime.receive_commit(
      peer_state,
      writer_commit,
      types.SequencePoint(3, 1),
      2,
      1,
      peer_compressor,
    )
    |> result.map_error(string.inspect),
  )
  use final <- result.try(
    callback_checkpoint(CallbackState(writer_state, writer_compressor)),
  )
  use peer_final <- result.try(
    callback_checkpoint(CallbackState(peer_state, peer_compressor)),
  )
  let settled = callback_history(tree_kernel.history_view(writer_state))
  use violated <- result.try(
    tree_kernel.history_view(writer_state).sequenced.trunk
    |> list.find(fn(entry) { entry.commit.revision == writer_commit.revision })
    |> result.map(fn(entry) { entry.commit })
    |> result.map_error(fn(_) { "violated transaction is missing from history" }),
  )
  use retained_builds <- result.try(
    violated.change
    |> shared_change.to_changes
    |> list.find_map(fn(value) {
      case value {
        shared_change.DataChange(value) -> {
          let projected = callback_change(value)
          case fixture_codec.parse(projected) {
            Ok(projected) -> fixture_codec.get(projected, "builds")
            Error(error) -> Error(error)
          }
        }
        shared_change.SchemaChange(..) ->
          Error("violated transaction data change is missing")
      }
    })
    |> result.map(json_ot.to_json)
    |> result.map_error(fn(_) {
      "violated transaction retained builds are missing"
    }),
  )
  Ok(ConstraintConcurrent(
    pending: pending.history,
    settled:,
    final: final.visible,
    peer: peer_final.visible,
    retained_builds:,
    messages: fixture_codec.array([
      peer_message,
      peer_message,
      writer_message,
    ]),
  ))
}

fn finish_commit(
  value: transaction.Finish,
  label: String,
) -> Result(
  #(tree_kernel.TreeState, fluid_ids.Compressor, history.Commit),
  String,
) {
  case value {
    transaction.Commit(state, compressor, commit) ->
      Ok(#(state, compressor, commit))
    transaction.NoCommit(_, _) -> Error(label <> " made no commit")
  }
}

fn clone_callback_state(
  source: CallbackState,
  session: fluid_ids.SessionId,
) -> Result(CallbackState, String) {
  use encoded <- result.try(
    fluid_ids.serialize(source.compressor, False)
    |> result.map_error(string.inspect),
  )
  use compressor <- result.try(
    fluid_ids.deserialize(encoded, session) |> result.map_error(string.inspect),
  )
  use snapshot <- result.try(
    tree_kernel.snapshot(source.tree) |> result.map_error(string.inspect),
  )
  use view_id <- result.try(
    fluid_ids.stable_id(callback_view) |> result.map_error(string.inspect),
  )
  use view <- result.try(
    schema.view_from_string(transaction_schema)
    |> result.map_error(string.inspect),
  )
  use state <- result.try(
    tree_runtime.restore(snapshot, view_id, view, compressor)
    |> result.map_error(string.inspect),
  )
  Ok(CallbackState(state, compressor))
}

fn run_callback_scenario(value: JsonValue) -> Result(Json, String) {
  use id <- result.try(fixture_codec.field(value, "id", fixture_codec.text))
  use _ <- result.try(validate_callback_scenario(value, id))
  use initial <- result.try(callback_initial_state())
  use before <- result.try(callback_checkpoint(initial))
  use open <- result.try(
    transaction.begin(initial.tree, initial.compressor, [])
    |> result.map_error(string.inspect),
  )
  use #(finish, events, reads, outcome) <- result.try(
    execute_callback(id, open, []),
  )
  use #(state, compressor, commit) <- result.try(case finish {
    transaction.NoCommit(state, compressor) -> Ok(#(state, compressor, None))
    transaction.Commit(state, compressor, commit) ->
      Ok(#(state, compressor, Some(commit)))
  })
  use submitted <- result.try(case commit {
    None -> Ok([])
    Some(commit) ->
      tree_runtime.encode_commit(commit, state, compressor)
      |> result.map(fn(message) { [message] })
      |> result.map_error(string.inspect)
  })
  let compressor = case commit {
    None -> compressor
    Some(_) -> fluid_ids.take_creation_range(compressor).0
  }
  let after_state = CallbackState(state, compressor)
  use after <- result.try(callback_checkpoint(after_state))
  let view = tree_kernel.history_view(state)
  let fields = [
    #("id", json.string(id)),
    #("reads", fixture_codec.array(list.reverse(reads))),
    #("events", callback_events(events, after.visible)),
    #(
      "commitCount",
      json.int(case commit {
        None -> 0
        Some(_) -> 1
      }),
    ),
    #("pendingCommitCount", json.int(list.length(view.pending))),
    #("submittedMessages", fixture_codec.array(submitted)),
    #("final", after.visible),
    #(
      "identity",
      json.object([
        #("nodes", string_array(after.identities)),
        #("before", string_array(before.identities)),
        #(
          "preserved",
          string_array(
            list.filter(before.identities, fn(identity) {
              list.contains(after.identities, identity)
            }),
          ),
        ),
      ]),
    ),
    #(
      "allocation",
      json.object([
        #("before", before.allocation),
        #("after", after.allocation),
      ]),
    ),
    #("compressor", after.compressor),
    #("retainedDetached", after.detached),
    #("history", callback_history(view)),
    #("depth", json.int(0)),
    ..outcome
  ]
  Ok(json.object(fields))
}

type CallbackCheckpoint {
  CallbackCheckpoint(
    visible: Json,
    identities: List(String),
    allocation: Json,
    compressor: Json,
    detached: Json,
    history: Json,
  )
}

fn callback_initial_state() -> Result(CallbackState, String) {
  use session <- result.try(
    fluid_ids.session_id(callback_session) |> result.map_error(string.inspect),
  )
  use view_id <- result.try(
    fluid_ids.stable_id(callback_view) |> result.map_error(string.inspect),
  )
  use stored <- result.try(
    schema.stored_from_string(transaction_schema)
    |> result.map_error(string.inspect),
  )
  use optional_stored <- result.try(
    schema.stored_from_string(transaction_optional_schema)
    |> result.map_error(string.inspect),
  )
  use optional_view <- result.try(
    schema.view_from_string(transaction_optional_schema)
    |> result.map_error(string.inspect),
  )
  use view <- result.try(
    schema.view_from_string(transaction_schema)
    |> result.map_error(string.inspect),
  )
  let compressor = fluid_ids.new(session)
  use #(root, compressor) <- result.try(
    identifier.materialize_value(stored, transaction_initial_root(), compressor)
    |> result.map_error(string.inspect),
  )
  let empty = history.inspect(history.new(session)).sequenced
  use optional_snapshot <- result.try(
    tree_kernel.snapshot_from_parts(
      view_id,
      optional_stored,
      forest.ForestData(None, [], 0),
      empty,
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
      "transaction fixture initialization",
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
  let initialized_history =
    history.HistorySnapshot(
      history.InitialBase,
      [
        history.SequencedCommit(commit, types.SequencePoint(1, 0)),
      ],
      [],
      1,
      0,
    )
  use snapshot <- result.try(
    tree_kernel.snapshot_from_parts(
      view_id,
      stored,
      initialized_data,
      initialized_history,
    )
    |> result.map_error(string.inspect),
  )
  use state <- result.try(
    tree_runtime.restore(snapshot, view_id, view, compressor)
    |> result.map_error(string.inspect),
  )
  let #(compressor, range) = fluid_ids.take_creation_range(compressor)
  use range <- result.try(
    range |> to_result("initial tree did not allocate IDs"),
  )
  use compressor <- result.try(
    fluid_ids.finalize(compressor, range) |> result.map_error(string.inspect),
  )
  Ok(CallbackState(state, compressor))
}

fn transaction_initial_root() -> types.TreeValue {
  types.ObjectValue(transaction_root_type, [
    #("title", types.StringValue("base")),
    #("note", types.StringValue("seed")),
    #("count", types.NumberValue(0.0)),
    #(
      "left",
      types.ArrayValue(transaction_items_type, [
        transaction_point("left-a", 1.0),
        transaction_point("left-b", 2.0),
      ]),
    ),
    #(
      "right",
      types.ArrayValue(transaction_items_type, [
        transaction_point("right-a", 3.0),
      ]),
    ),
    #(
      "byKey",
      types.MapValue(transaction_map_type, [
        #("seed", types.StringValue("value")),
      ]),
    ),
  ])
}

fn transaction_point(label: String, x: Float) -> types.TreeValue {
  types.ObjectValue(transaction_point_type, [
    #("label", types.StringValue(label)),
    #("x", types.NumberValue(x)),
  ])
}

fn validate_callback_scenario(
  value: JsonValue,
  id: String,
) -> Result(Nil, String) {
  case id {
    "success-all-fields" -> {
      use _ <- result.try(
        fixture_codec.exact(value, ["id", "api", "operations"]),
      )
      use api <- result.try(fixture_codec.field(
        value,
        "api",
        fixture_codec.text,
      ))
      use operations <- result.try(fixture_codec.field(
        value,
        "operations",
        fixture_codec.items,
      ))
      use operations <- result.try(list.try_map(operations, fixture_codec.text))
      require(
        api == "Tree.runTransaction"
          && operations
          == [
          "object-set",
          "object-delete",
          "map-set",
          "map-delete",
          "array-insert",
          "array-remove",
          "array-replace",
          "same-array-move",
          "cross-array-move",
        ],
        "unsupported success transaction scenario",
      )
    }
    "invalid-edit-rollback" -> {
      use _ <- result.try(
        fixture_codec.exact(value, ["id", "api", "operation"]),
      )
      use operation <- result.try(fixture_codec.field(
        value,
        "operation",
        fixture_codec.text,
      ))
      require(
        operation == "array-remove-negative-index",
        "unsupported invalid transaction operation",
      )
    }
    "outer-rollback" | "nested-success" | "nested-rollback" | "no-op" ->
      fixture_codec.exact(value, ["id", "api"])
    _ -> Error("unsupported transaction callback scenario: " <> id)
  }
}

fn execute_callback(
  id: String,
  open: transaction.Transaction,
  reads: List(Json),
) -> Result(
  #(
    transaction.Finish,
    tree_kernel.ChangeEvents,
    List(Json),
    List(#(String, Json)),
  ),
  String,
) {
  case id {
    "success-all-fields" -> callback_success(open, reads)
    "outer-rollback" -> {
      use open <- result.try(callback_edit(
        open,
        types.SetField(["title"], types.StringValue("rolled-back")),
      ))
      use open <- result.try(callback_edit(
        open,
        types.ArrayInsert(["left"], 2, [transaction_point("temporary", 99.0)]),
      ))
      use read <- result.try(callback_read("before-rollback", open))
      use #(state, compressor) <- result.try(
        transaction.abort(open) |> result.map_error(string.inspect),
      )
      Ok(
        #(
          transaction.NoCommit(state, compressor),
          tree_kernel.ChangeEvents([], False),
          [read, ..reads],
          [],
        ),
      )
    }
    "nested-success" -> {
      use open <- result.try(callback_edit(
        open,
        types.SetField(["title"], types.StringValue("outer")),
      ))
      let open = transaction.begin_nested(open)
      use open <- result.try(callback_edit(
        open,
        types.SetField(["count"], types.NumberValue(2.0)),
      ))
      use read <- result.try(callback_read("inner", open))
      use open <- result.try(
        transaction.commit_nested(open) |> result.map_error(string.inspect),
      )
      use open <- result.try(callback_edit(
        open,
        types.ArrayInsert(["left"], 2, [types.StringValue("after-inner")]),
      ))
      finish_callback(open, [read, ..reads], [])
    }
    "nested-rollback" -> {
      use open <- result.try(callback_edit(
        open,
        types.SetField(["title"], types.StringValue("outer")),
      ))
      let nested = transaction.begin_nested(open)
      use nested <- result.try(callback_edit(
        nested,
        types.SetField(["count"], types.NumberValue(99.0)),
      ))
      use nested <- result.try(callback_edit(
        nested,
        types.ArrayInsert(["left"], 2, [types.StringValue("inner")]),
      ))
      use inner <- result.try(callback_read("inner-before-rollback", nested))
      use open <- result.try(
        transaction.abort_nested(nested) |> result.map_error(string.inspect),
      )
      use after <- result.try(callback_read("after-inner-rollback", open))
      use open <- result.try(callback_edit(
        open,
        types.ArrayInsert(["right"], 1, [
          types.StringValue("outer-continued"),
        ]),
      ))
      finish_callback(open, [after, inner, ..reads], [])
    }
    "no-op" -> {
      use read <- result.try(callback_read("inside", open))
      finish_callback(open, [read, ..reads], [])
    }
    "invalid-edit-rollback" -> {
      use before <- result.try(
        callback_checkpoint(CallbackState(
          transaction.state(open),
          transaction.compressor(open),
        )),
      )
      use open <- result.try(callback_edit(
        open,
        types.SetField(["title"], types.StringValue("before-invalid")),
      ))
      use read <- result.try(callback_read("valid-edit-before-invalid", open))
      use _ <- result.try(
        case transaction.apply_edit(open, types.ArrayRemove(["left"], -1, 1)) {
          Error(types.InvalidEdit(_, _)) -> Ok(Nil)
          Error(error) ->
            Error("invalid transaction edit returned " <> string.inspect(error))
          Ok(_) -> Error("invalid transaction edit succeeded")
        },
      )
      let error =
        "Error: Expected non-negative index passed to TreeArrayNode.removeAt, got -1."
      use #(state, compressor) <- result.try(
        transaction.abort(open) |> result.map_error(string.inspect),
      )
      use after <- result.try(
        callback_checkpoint(CallbackState(state, compressor)),
      )
      Ok(
        #(
          transaction.NoCommit(state, compressor),
          tree_kernel.ChangeEvents([], False),
          [read, ..reads],
          [
            #("error", json.string(error)),
            #("nativeFailure", json.bool(True)),
            #("transactionResult", json.string("rollback")),
            #(
              "state",
              json.object([
                #("before", callback_state_json(before)),
                #("after", callback_state_json(after)),
              ]),
            ),
            #("localCompressorAdvanced", json.bool(True)),
          ],
        ),
      )
    }
    _ -> Error("unsupported transaction callback scenario: " <> id)
  }
}

fn callback_success(
  open: transaction.Transaction,
  reads: List(Json),
) -> Result(
  #(
    transaction.Finish,
    tree_kernel.ChangeEvents,
    List(Json),
    List(#(String, Json)),
  ),
  String,
) {
  use #(open, reads) <- result.try(callback_step(
    open,
    reads,
    "object-set",
    types.SetField(["title"], types.StringValue("object")),
  ))
  use #(open, reads) <- result.try(callback_step(
    open,
    reads,
    "object-delete",
    types.ClearField(["note"]),
  ))
  use #(open, reads) <- result.try(callback_step(
    open,
    reads,
    "map-set",
    types.MapSet(["byKey"], "added", types.StringValue("map")),
  ))
  use #(open, reads) <- result.try(callback_step(
    open,
    reads,
    "map-delete",
    types.MapDelete(["byKey"], "seed"),
  ))
  use #(open, reads) <- result.try(callback_step(
    open,
    reads,
    "array-insert",
    types.ArrayInsert(["left"], 2, [types.StringValue("inserted")]),
  ))
  use #(open, reads) <- result.try(callback_step(
    open,
    reads,
    "array-remove",
    types.ArrayRemove(["left"], 2, 3),
  ))
  use open <- result.try(callback_edit(open, types.ArrayRemove(["left"], 1, 2)))
  use open <- result.try(callback_edit(
    open,
    types.ArrayInsert(["left"], 1, [transaction_point("replacement", 4.0)]),
  ))
  use read <- result.try(callback_read("array-replace", open))
  let reads = [read, ..reads]
  use #(open, reads) <- result.try(callback_step(
    open,
    reads,
    "same-array-move",
    types.ArrayMove(["left"], 0, 1, ["left"], 2),
  ))
  use #(open, reads) <- result.try(callback_step(
    open,
    reads,
    "cross-array-move",
    types.ArrayMove(["left"], 1, 2, ["right"], 1),
  ))
  finish_callback(open, reads, [])
}

fn callback_step(
  open: transaction.Transaction,
  reads: List(Json),
  name: String,
  edit: types.Edit,
) -> Result(#(transaction.Transaction, List(Json)), String) {
  use open <- result.try(callback_edit(open, edit))
  use read <- result.try(callback_read(name, open))
  Ok(#(open, [read, ..reads]))
}

fn callback_edit(
  open: transaction.Transaction,
  edit: types.Edit,
) -> Result(transaction.Transaction, String) {
  transaction.apply_edit(open, edit) |> result.map_error(string.inspect)
}

fn callback_read(
  step: String,
  open: transaction.Transaction,
) -> Result(Json, String) {
  use visible <- result.try(callback_visible(transaction.state(open)))
  Ok(
    json.object([
      #("step", json.string(step)),
      #("value", visible),
    ]),
  )
}

fn finish_callback(
  open: transaction.Transaction,
  reads: List(Json),
  outcome: List(#(String, Json)),
) -> Result(
  #(
    transaction.Finish,
    tree_kernel.ChangeEvents,
    List(Json),
    List(#(String, Json)),
  ),
  String,
) {
  transaction.finish(open)
  |> result.map(fn(value) { #(value.0, value.1, reads, outcome) })
  |> result.map_error(string.inspect)
}

fn callback_checkpoint(
  value: CallbackState,
) -> Result(CallbackCheckpoint, String) {
  use data <- result.try(
    tree_kernel.visible_data(value.tree) |> result.map_error(string.inspect),
  )
  use visible <- result.try(callback_visible_value(
    data.root |> unwrap(types.NullValue),
  ))
  use ongoing <- result.try(
    fluid_ids.serialize(value.compressor, True)
    |> result.map_error(string.inspect),
  )
  use summary <- result.try(
    fluid_ids.serialize(value.compressor, False)
    |> result.map_error(string.inspect),
  )
  use detached <- result.try(callback_detached(data.detached, value.compressor))
  let identities = callback_identities(data.root |> unwrap(types.NullValue))
  Ok(CallbackCheckpoint(
    visible:,
    identities:,
    allocation: json.object([
      #(
        "sessionId",
        json.string(
          fluid_ids.session_id_to_string(fluid_ids.local_session(
            value.compressor,
          )),
        ),
      ),
      #("ongoing", ongoing),
    ]),
    compressor: summary,
    detached:,
    history: callback_history(tree_kernel.history_view(value.tree)),
  ))
}

fn callback_state_json(value: CallbackCheckpoint) -> Json {
  json.object([
    #("visible", value.visible),
    #("identities", string_array(value.identities)),
    #("retainedDetached", value.detached),
    #("compressor", value.compressor),
    #("allocation", value.allocation),
    #("history", value.history),
  ])
}

fn callback_visible(state: tree_kernel.TreeState) -> Result(Json, String) {
  use data <- result.try(
    tree_kernel.visible_data(state) |> result.map_error(string.inspect),
  )
  callback_visible_value(data.root |> unwrap(types.NullValue))
}

fn callback_visible_value(value: types.TreeValue) -> Result(Json, String) {
  case value {
    types.StringValue(value) -> Ok(json.string(value))
    types.NumberValue(value) ->
      Ok(case int.to_float(float.truncate(value)) == value {
        True -> json.int(float.truncate(value))
        False -> json.float(value)
      })
    types.BooleanValue(value) -> Ok(json.bool(value))
    types.NullValue -> Ok(json.null())
    types.ArrayValue(_, values) ->
      list.try_map(values, callback_visible_value)
      |> result.map(fixture_codec.array)
    types.MapValue(_, entries) ->
      entries
      |> list.sort(fn(left, right) { canonical_json.compare(left.0, right.0) })
      |> list.try_map(fn(entry) {
        use value <- result.try(callback_visible_value(entry.1))
        Ok(fixture_codec.array([json.string(entry.0), value]))
      })
      |> result.map(fixture_codec.array)
    types.ObjectValue(identifier, fields)
      if identifier == transaction_root_type
    -> {
      use title <- result.try(callback_required_field(fields, "title"))
      let note = case list.key_find(fields, "note") {
        Ok(value) -> callback_visible_value(value)
        Error(_) -> Ok(json.null())
      }
      use note <- result.try(note)
      use count <- result.try(callback_required_field(fields, "count"))
      use left <- result.try(callback_required_field(fields, "left"))
      use right <- result.try(callback_required_field(fields, "right"))
      use by_key <- result.try(callback_required_field(fields, "byKey"))
      Ok(
        json.object([
          #("title", title),
          #("note", note),
          #("count", count),
          #("left", left),
          #("right", right),
          #("byKey", by_key),
        ]),
      )
    }
    types.ObjectValue(identifier, fields)
      if identifier == transaction_point_type
    -> {
      use id <- result.try(callback_required_field(fields, "id"))
      use label <- result.try(callback_required_field(fields, "label"))
      use x <- result.try(callback_required_field(fields, "x"))
      Ok(
        json.object([
          #("id", id),
          #("label", label),
          #("x", x),
        ]),
      )
    }
    types.ObjectValue(_, fields) ->
      list.try_map(fields, fn(field) {
        use value <- result.try(callback_visible_value(field.1))
        Ok(#(field.0, value))
      })
      |> result.map(json.object)
  }
}

fn callback_required_field(
  fields: List(#(String, types.TreeValue)),
  name: String,
) -> Result(Json, String) {
  use value <- result.try(
    list.key_find(fields, name)
    |> result.map_error(fn(_) { "transaction field is missing: " <> name }),
  )
  callback_visible_value(value)
}

fn callback_identities(value: types.TreeValue) -> List(String) {
  case value {
    types.ObjectValue(identifier, fields)
      if identifier == transaction_point_type
    ->
      case list.key_find(fields, "id") {
        Ok(types.StringValue(id)) -> [id]
        _ -> []
      }
    types.ObjectValue(_, fields) ->
      list.flat_map(fields, fn(field) { callback_identities(field.1) })
    types.ArrayValue(_, values) -> list.flat_map(values, callback_identities)
    types.MapValue(_, entries) ->
      list.flat_map(entries, fn(entry) { callback_identities(entry.1) })
    _ -> []
  }
}

fn callback_events(events: tree_kernel.ChangeEvents, visible: Json) -> Json {
  fixture_codec.array(
    list.map(events.events, fn(_) {
      json.object([
        #("kind", json.string("changed")),
        #("value", visible),
        #("depth", json.int(0)),
      ])
    }),
  )
}

fn callback_history(value: history.HistoryView) -> Json {
  json.object([
    #("pending", fixture_codec.array(list.map(value.pending, callback_commit))),
    #(
      "trunk",
      fixture_codec.array(
        list.map(value.sequenced.trunk, fn(value) {
          callback_commit(value.commit)
        }),
      ),
    ),
  ])
}

fn callback_commit(value: history.Commit) -> Json {
  json.object([
    #("revision", json.string(fluid_ids.stable_id_to_string(value.revision))),
    #(
      "changes",
      fixture_codec.array(
        list.map(shared_change.to_changes(value.change), fn(change) {
          case change {
            shared_change.DataChange(change) ->
              json.object([
                #("type", json.string("data")),
                #("change", callback_change(change)),
              ])
            shared_change.SchemaChange(before, after, is_inverse) ->
              json.object([
                #("type", json.string("schema")),
                #(
                  "change",
                  json.object([
                    #(
                      "schema",
                      json.object([
                        #("old", callback_schema_state(before)),
                        #("new", callback_schema_state(after)),
                      ]),
                    ),
                    #("isInverse", json.bool(is_inverse)),
                  ]),
                ),
              ])
          }
        }),
      ),
    ),
  ])
}

fn callback_schema_state(value: schema.SchemaState) -> Json {
  case value {
    schema.EmptySchema ->
      json.object([
        #("version", json.int(2)),
        #("nodes", json.object([])),
        #(
          "root",
          json.object([
            #("kind", json.string("Forbidden")),
            #("types", json.array([], fn(value) { value })),
          ]),
        ),
      ])
    schema.FixedSchema(value) -> schema.stored_to_json(value)
  }
}

fn callback_change(value: change.Changeset) -> Json {
  let data = change.to_data(value)
  let delta =
    change.into_delta(change.TaggedChange(None, None, value))
    |> result.map(forest.delta_data)
    |> result.unwrap(forest.DeltaData(None, [], [], [], [], [], []))
  let aliases = canonical_aliases(data.aliases)
  let parents =
    list.map(data.parents, fn(entry) {
      let change.ParentField(parent, field) = entry.1
      #(
        entry.0,
        change.ParentField(
          option.map(parent, fn(parent) {
            resolve_alias(parent, data.aliases, [])
          }),
          field,
        ),
      )
    })
    |> list.sort(fn(left, right) {
      let depth =
        int.compare(
          callback_parent_depth(left.0, data.parents, []),
          callback_parent_depth(right.0, data.parents, []),
        )
      case depth {
        order.Eq -> {
          let change.ParentField(_, left_field) = left.1
          let change.ParentField(_, right_field) = right.1
          case canonical_json.compare(left_field, right_field) {
            order.Eq -> int.compare(left.0.local_id, right.0.local_id)
            value -> value
          }
        }
        value -> value
      }
    })
  let nodes =
    list.sort(data.nodes, fn(left, right) {
      let depth =
        int.compare(
          callback_parent_depth(left.0, parents, []),
          callback_parent_depth(right.0, parents, []),
        )
      case depth {
        order.Eq -> int.compare(left.0.local_id, right.0.local_id)
        value -> value
      }
    })
  json.object([
    #("maxId", json.int(data.max_local_id)),
    #(
      "revisions",
      fixture_codec.array(
        list.map(data.revisions, fn(info) {
          json.object([
            #(
              "revision",
              json.string(fluid_ids.stable_id_to_string(info.revision)),
            ),
            #("rollbackOf", case info.rollback_of {
              None -> json.null()
              Some(revision) ->
                json.string(fluid_ids.stable_id_to_string(revision))
            }),
          ])
        }),
      ),
    ),
    #("fields", callback_fields(data.fields)),
    #(
      "nodes",
      fixture_codec.array(
        list.map(nodes, fn(entry) {
          let change.NodeChange(
            fields,
            node_exists_constraint,
            node_exists_constraint_on_revert,
          ) = entry.1
          json.object([
            #("id", atom_json(entry.0)),
            #(
              "change",
              json.object([
                #("fields", callback_fields(fields)),
                #(
                  "nodeExistsConstraint",
                  callback_constraint(node_exists_constraint),
                ),
                #(
                  "nodeExistsConstraintOnRevert",
                  callback_constraint(node_exists_constraint_on_revert),
                ),
              ]),
            ),
          ])
        }),
      ),
    ),
    #(
      "parents",
      fixture_codec.array(
        list.map(parents, fn(entry) {
          let change.ParentField(parent, field) = entry.1
          json.object([
            #("id", atom_json(entry.0)),
            #("parent", case parent {
              None -> json.null()
              Some(parent) -> atom_json(parent)
            }),
            #("field", json.string(field)),
          ])
        }),
      ),
    ),
    #(
      "aliases",
      fixture_codec.array(
        list.map(aliases, fn(entry) {
          json.object([
            #("id", atom_json(entry.0)),
            #("target", atom_json(entry.1)),
          ])
        }),
      ),
    ),
    #("builds", fixture_codec.array(list.map(data.builds, build_json))),
    #(
      "destroys",
      fixture_codec.array(
        list.map(data.destroys, fn(value) {
          let forest.Destroy(id, count) = value
          json.object([
            #("id", atom_json(id)),
            #("count", json.int(count)),
          ])
        }),
      ),
    ),
    #("refreshers", fixture_codec.array(list.map(data.refreshers, build_json))),
    #("constraintViolationCount", json.int(data.constraint_violation_count)),
    #("delta", callback_delta(delta)),
  ])
  |> canonical_graph
}

fn callback_parent_depth(
  id: types.AtomId,
  parents: List(#(types.AtomId, change.ParentField)),
  seen: List(types.AtomId),
) -> Int {
  case list.contains(seen, id) {
    True -> panic as "transaction parent graph must be acyclic"
    False ->
      case list.key_find(parents, id) {
        Ok(change.ParentField(Some(parent), _)) ->
          1 + callback_parent_depth(parent, parents, [id, ..seen])
        _ -> 0
      }
  }
}

type CanonicalAtoms {
  CanonicalAtoms(mappings: List(#(types.AtomId, types.AtomId)), next: Int)
}

fn resolve_alias(
  value: types.AtomId,
  aliases: List(#(types.AtomId, types.AtomId)),
  seen: List(types.AtomId),
) -> types.AtomId {
  case list.contains(seen, value) {
    True -> panic as "transaction alias graph must be acyclic"
    False ->
      case list.key_find(aliases, value) {
        Ok(target) -> resolve_alias(target, aliases, [value, ..seen])
        Error(_) -> value
      }
  }
}

fn canonical_aliases(
  values: List(#(types.AtomId, types.AtomId)),
) -> List(#(types.AtomId, types.AtomId)) {
  values
  |> list.fold(#([], []), fn(state, entry) {
    let #(entries, targets) = state
    let target = resolve_alias(entry.1, values, [])
    case list.contains(targets, target) {
      True -> state
      False -> #([#(entry.0, target), ..entries], [target, ..targets])
    }
  })
  |> fn(state) { list.reverse(state.0) }
}

fn canonical_graph(value: Json) -> Json {
  let assert Ok(value) = fixture_codec.parse(value)
  let value = case value {
    VObject(fields) ->
      VObject(
        list.map(fields, fn(entry) {
          case entry.0 {
            "aliases" | "builds" | "refreshers" | "destroys" -> #(
              entry.0,
              canonical_graph_entries(entry.1),
            )
            _ -> entry
          }
        }),
      )
    _ -> value
  }
  let #(value, state) = canonical_json_atoms(value, CanonicalAtoms([], 0))
  case value {
    VObject(fields) ->
      VObject(
        list.map(fields, fn(entry) {
          case entry.0 {
            "maxId" -> #("maxId", VNumber(NInt(state.next - 1)))
            "aliases"
            | "parents"
            | "nodes"
            | "builds"
            | "refreshers"
            | "destroys" -> #(entry.0, canonical_graph_entries(entry.1))
            _ -> entry
          }
        }),
      )
      |> json_ot.to_json
    _ -> panic as "transaction change must be an object"
  }
}

fn canonical_graph_entries(value: JsonValue) -> JsonValue {
  case value {
    VArray(values) ->
      VArray(
        list.sort(values, fn(left, right) {
          int.compare(graph_entry_local_id(left), graph_entry_local_id(right))
        }),
      )
    _ -> value
  }
}

fn graph_entry_local_id(value: JsonValue) -> Int {
  fixture_codec.field(value, "id", fn(value) {
    fixture_codec.field(value, "localId", fixture_codec.integer)
  })
  |> result.unwrap(-1)
}

fn canonical_json_atoms(
  value: JsonValue,
  state: CanonicalAtoms,
) -> #(JsonValue, CanonicalAtoms) {
  case value {
    VObject(fields) ->
      case fixture_codec.atom(value) {
        Ok(atom) -> canonical_atom(atom, state)
        Error(_) -> {
          let #(fields, state) =
            list.fold(fields, #([], state), fn(acc, entry) {
              let #(entries, state) = acc
              let #(value, state) = canonical_json_atoms(entry.1, state)
              #([#(entry.0, value), ..entries], state)
            })
          #(VObject(list.reverse(fields)), state)
        }
      }
    VArray(values) -> {
      let #(values, state) =
        list.fold(values, #([], state), fn(acc, value) {
          let #(values, state) = acc
          let #(value, state) = canonical_json_atoms(value, state)
          #([value, ..values], state)
        })
      #(VArray(list.reverse(values)), state)
    }
    _ -> #(value, state)
  }
}

fn canonical_atom(
  atom: types.AtomId,
  state: CanonicalAtoms,
) -> #(JsonValue, CanonicalAtoms) {
  case list.key_find(state.mappings, atom) {
    Ok(canonical) -> #(atom_value(canonical), state)
    Error(_) -> {
      let canonical = types.AtomId(atom.revision, state.next)
      #(
        atom_value(canonical),
        CanonicalAtoms([#(atom, canonical), ..state.mappings], state.next + 1),
      )
    }
  }
}

fn atom_value(value: types.AtomId) -> JsonValue {
  VObject([
    #("revision", case value.revision {
      None -> VNull
      Some(value) -> VString(fluid_ids.stable_id_to_string(value))
    }),
    #("localId", VNumber(NInt(value.local_id))),
  ])
}

fn callback_fields(values: List(#(String, change.FieldChange))) -> Json {
  fixture_codec.array(
    list.map(values, fn(entry) {
      json.object([
        #("field", json.string(entry.0)),
        #("kind", json.string(callback_field_kind(entry.1))),
        #("operation", callback_field_operation(entry.1)),
      ])
    }),
  )
}

fn callback_field_kind(value: change.FieldChange) -> String {
  case value {
    change.ValueField(_) -> "Value"
    change.OptionalField(_) -> "Optional"
    change.SequenceField(_) -> "Sequence"
    change.GenericField(_) -> "Generic"
    change.IdentifierField -> "Identifier"
  }
}

fn callback_field_operation(value: change.FieldChange) -> Json {
  case value {
    change.IdentifierField -> json.object([])
    change.GenericField(children) ->
      json.object([
        #(
          "children",
          fixture_codec.array(
            list.map(children, fn(child) {
              fixture_codec.array([json.int(child.0), atom_json(child.1)])
            }),
          ),
        ),
      ])
    change.ValueField(value) | change.OptionalField(value) -> {
      let optional_field.FieldChange(moves, children, replacement) = value
      json.object([
        #(
          "moves",
          fixture_codec.array(
            list.map(moves, fn(move) {
              fixture_codec.array([atom_json(move.0), atom_json(move.1)])
            }),
          ),
        ),
        #(
          "children",
          fixture_codec.array(
            list.map(children, fn(child) {
              fixture_codec.array([
                callback_register(child.0),
                atom_json(child.1),
              ])
            }),
          ),
        ),
        #("replacement", case replacement {
          None -> json.null()
          Some(optional_field.Replacement(was_empty, source, detach)) ->
            json.object([
              #("wasEmpty", json.bool(was_empty)),
              #("source", case source {
                None -> json.null()
                Some(source) -> callback_register(source)
              }),
              #("detach", atom_json(detach)),
            ])
        }),
      ])
    }
    change.SequenceField(value) ->
      json.object([
        #(
          "marks",
          fixture_codec.array(
            list.map(sequence_field.to_marks(value), fn(mark) {
              let sequence_field.Mark(count, cell, effect, child) = mark
              json.object([
                #("count", json.int(count)),
                #("cell", case cell {
                  None -> json.null()
                  Some(cell) -> atom_json(cell)
                }),
                #("effect", callback_sequence_effect(effect)),
                #("child", case child {
                  None -> json.null()
                  Some(child) -> atom_json(child)
                }),
              ])
            }),
          ),
        ),
      ])
  }
}

fn callback_register(value: optional_field.RegisterId) -> Json {
  case value {
    optional_field.Active -> json.string("self")
    optional_field.Detached(id) -> atom_json(id)
  }
}

fn callback_sequence_effect(value: sequence_field.Effect) -> Json {
  case value {
    sequence_field.Noop ->
      callback_sequence_effect_parts("Noop", None, None, None)
    sequence_field.Attach(attach) -> callback_sequence_attach(attach)
    sequence_field.Detach(detach) -> callback_sequence_detach(detach)
    sequence_field.AttachAndDetach(attach, detach) ->
      json.object([
        #("type", json.string("AttachAndDetach")),
        #("attach", callback_sequence_attach(attach)),
        #("detach", callback_sequence_detach(detach)),
      ])
    sequence_field.Rename(id) ->
      callback_sequence_effect_parts("Rename", None, None, Some(id))
  }
}

fn callback_sequence_attach(value: sequence_field.Attach) -> Json {
  case value {
    sequence_field.Insert(id) ->
      callback_sequence_effect_parts("Insert", Some(id), None, None)
    sequence_field.MoveIn(id, endpoint) ->
      callback_sequence_effect_parts("MoveIn", Some(id), endpoint, None)
  }
}

fn callback_sequence_detach(value: sequence_field.Detach) -> Json {
  case value {
    sequence_field.Remove(id, override) ->
      callback_sequence_effect_parts("Remove", Some(id), None, override)
    sequence_field.MoveOut(id, endpoint, override) ->
      callback_sequence_effect_parts("MoveOut", Some(id), endpoint, override)
  }
}

fn callback_sequence_effect_parts(
  kind: String,
  id: Option(types.AtomId),
  endpoint: Option(types.AtomId),
  override: Option(types.AtomId),
) -> Json {
  json.object([
    #("type", json.string(kind)),
    #("id", case id {
      None -> json.null()
      Some(id) -> atom_json(id)
    }),
    #("finalEndpoint", case endpoint {
      None -> json.null()
      Some(endpoint) -> atom_json(endpoint)
    }),
    #("idOverride", case override {
      None -> json.null()
      Some(override) -> atom_json(override)
    }),
  ])
}

fn callback_constraint(
  value: option.Option(change.NodeExistsConstraint),
) -> Json {
  case value {
    None -> json.null()
    Some(change.NodeExistsConstraint(violated)) ->
      json.object([#("violated", json.bool(violated))])
  }
}

fn callback_delta(value: forest.DeltaData) -> Json {
  json.object([
    #("fields", callback_delta_fields(value.fields)),
    #("builds", fixture_codec.array(list.map(value.build, build_json))),
    #("refreshers", fixture_codec.array(list.map(value.refreshers, build_json))),
    #(
      "global",
      fixture_codec.array(
        list.map(value.global, fn(value) {
          let forest.DetachedChange(id, fields) = value
          json.object([
            #("id", atom_json(id)),
            #("fields", callback_delta_fields(fields)),
          ])
        }),
      ),
    ),
    #(
      "renames",
      fixture_codec.array(
        list.map(value.rename, fn(value) {
          let forest.Rename(old_id, new_id, count) = value
          json.object([
            #("old", atom_json(old_id)),
            #("new", atom_json(new_id)),
            #("count", json.int(count)),
          ])
        }),
      ),
    ),
    #(
      "destroys",
      fixture_codec.array(
        list.map(value.destroy, fn(value) {
          let forest.Destroy(id, count) = value
          json.object([
            #("id", atom_json(id)),
            #("count", json.int(count)),
          ])
        }),
      ),
    ),
  ])
}

fn callback_delta_fields(values: List(#(String, forest.FieldDelta))) -> Json {
  fixture_codec.array(
    list.map(values, fn(entry) {
      let forest.FieldDelta(marks) = entry.1
      json.object([
        #("field", json.string(entry.0)),
        #(
          "marks",
          fixture_codec.array(
            list.map(marks, fn(mark) {
              let forest.Mark(count, attach, detach, fields) = mark
              json.object([
                #("count", json.int(count)),
                #("attach", case attach {
                  None -> json.null()
                  Some(id) -> atom_json(id)
                }),
                #("detach", case detach {
                  None -> json.null()
                  Some(id) -> atom_json(id)
                }),
                #("fields", callback_delta_fields(fields)),
              ])
            }),
          ),
        ),
      ])
    }),
  )
}

fn callback_detached(
  values: List(forest.DetachedTreeData),
  compressor: fluid_ids.Compressor,
) -> Result(Json, String) {
  use values <- result.try(
    list.try_map(values, fn(value) {
      use revision <- result.try(case value.id.revision {
        None -> Ok(json.null())
        Some(revision) -> {
          use compressed <- result.try(
            fluid_ids.recompress(compressor, revision)
            |> result.map_error(string.inspect),
          )
          use compressed <- result.try(
            compressed |> to_result("detached revision is unknown"),
          )
          use operation <- result.try(
            fluid_ids.to_op(compressor, compressed)
            |> result.map_error(string.inspect),
          )
          Ok(json.int(fluid_ids.op_id_to_int(operation)))
        }
      })
      Ok(
        fixture_codec.array([
          revision,
          json.int(value.id.local_id),
          fixtures.tree_value_to_json(value.value),
        ]),
      )
    }),
  )
  Ok(fixture_codec.array(values))
}

fn string_array(values: List(String)) -> Json {
  fixture_codec.array(list.map(values, json.string))
}

fn require(condition: Bool, message: String) -> Result(Nil, String) {
  case condition {
    True -> Ok(Nil)
    False -> Error(message)
  }
}

pub fn run_wire(input: Json) -> Result(Json, String) {
  use input <- result.try(fixture_codec.parse(input))
  use parsed <- result.try(decode_input(input))
  use nonviolated <- result.try(decode_message(
    parsed.nonviolated_bytes,
    parsed.nonviolated_compressor,
  ))
  use violated <- result.try(decode_message(
    parsed.violated_bytes,
    parsed.violated_compressor,
  ))
  Ok(
    json.object([
      #(
        "observations",
        fixture_codec.array([
          json.object([
            #("id", json.string(parsed.id)),
            #("nonviolated", nonviolated.0),
            #("violated", violated.0),
            #(
              "message",
              json.object([
                #("nonviolated", nonviolated.1),
                #("violated", violated.1),
              ]),
            ),
            #(
              "messageBytes",
              json.object([
                #("nonviolated", json.string(nonviolated.2)),
                #("violated", json.string(violated.2)),
              ]),
            ),
            #(
              "compressorSessions",
              json.object([
                #(
                  "nonviolated",
                  json.string(fluid_ids.session_id_to_string(
                    parsed.nonviolated_session,
                  )),
                ),
                #(
                  "violated",
                  json.string(fluid_ids.session_id_to_string(
                    parsed.violated_session,
                  )),
                ),
              ]),
            ),
          ]),
        ]),
      ),
    ]),
  )
}

fn decode_input(value: JsonValue) -> Result(WireInput, String) {
  use _ <- result.try(
    fixture_codec.exact(value, [
      "messageBytes",
      "compressor",
      "context",
      "operands",
      "scenarios",
    ]),
  )
  use context <- result.try(fixture_codec.get(value, "context"))
  use _ <- result.try(decode_context(context))
  use operands <- result.try(fixture_codec.get(value, "operands"))
  use _ <- result.try(require_object(operands, "operands"))
  use scenarios <- result.try(fixture_codec.field(
    value,
    "scenarios",
    fixture_codec.items,
  ))
  use id <- result.try(case scenarios {
    [scenario] -> fixture_codec.field(scenario, "id", fixture_codec.text)
    _ -> Error("expected one transaction wire scenario")
  })
  use _ <- result.try(case id {
    "modular-v5-shared-tree-v5" -> Ok(Nil)
    _ -> Error("unsupported transaction wire scenario: " <> id)
  })
  use message_bytes <- result.try(fixture_codec.get(value, "messageBytes"))
  use nonviolated_bytes <- result.try(fixture_codec.field(
    message_bytes,
    "nonviolated",
    fixture_codec.text,
  ))
  use violated_bytes <- result.try(fixture_codec.field(
    message_bytes,
    "violated",
    fixture_codec.text,
  ))
  use _ <- result.try(fixture_codec.field(
    message_bytes,
    "over",
    fixture_codec.text,
  ))
  use compressors <- result.try(fixture_codec.get(value, "compressor"))
  use nonviolated <- result.try(fixture_codec.field(
    compressors,
    "nonviolated",
    decode_compressor,
  ))
  use violated <- result.try(fixture_codec.field(
    compressors,
    "violated",
    decode_compressor,
  ))
  use _ <- result.try(fixture_codec.field(
    compressors,
    "over",
    decode_compressor,
  ))
  Ok(WireInput(
    id:,
    nonviolated_bytes:,
    nonviolated_session: nonviolated.0,
    nonviolated_compressor: nonviolated.1,
    violated_bytes:,
    violated_session: violated.0,
    violated_compressor: violated.1,
  ))
}

fn decode_context(value: JsonValue) -> Result(Nil, String) {
  use _ <- result.try(
    fixture_codec.exact(value, [
      "message",
      "sharedTreeChange",
      "modularChange",
      "minVersionForCollab",
    ]),
  )
  use message <- result.try(fixture_codec.field(
    value,
    "message",
    fixture_codec.integer,
  ))
  use shared_tree <- result.try(fixture_codec.field(
    value,
    "sharedTreeChange",
    fixture_codec.integer,
  ))
  use modular <- result.try(fixture_codec.field(
    value,
    "modularChange",
    fixture_codec.integer,
  ))
  use minimum <- result.try(fixture_codec.field(
    value,
    "minVersionForCollab",
    fixture_codec.text,
  ))
  case message, shared_tree, modular, minimum {
    7, 5, 5, "2.117.0" -> Ok(Nil)
    _, _, _, _ -> Error("unsupported transaction wire context")
  }
}

fn decode_compressor(
  value: JsonValue,
) -> Result(#(fluid_ids.SessionId, fluid_ids.Compressor), String) {
  use _ <- result.try(fixture_codec.exact(value, ["serialized", "sessionId"]))
  use serialized <- result.try(fixture_codec.field(
    value,
    "serialized",
    fixture_codec.text,
  ))
  use session_raw <- result.try(fixture_codec.field(
    value,
    "sessionId",
    fixture_codec.text,
  ))
  use session <- result.try(
    fluid_ids.session_id(session_raw)
    |> result.map_error(string.inspect),
  )
  use compressor <- result.try(
    fluid_ids.deserialize(json.string(serialized), session)
    |> result.map_error(string.inspect),
  )
  Ok(#(session, compressor))
}

fn decode_message(
  bytes: String,
  compressor: fluid_ids.Compressor,
) -> Result(#(Json, Json, String), String) {
  use message <- result.try(
    json_ot.parse_json(bytes) |> result.map_error(string.inspect),
  )
  use compressor_before <- result.try(
    fluid_ids.serialize(compressor, True)
    |> result.map_error(string.inspect),
  )
  use message <- result.try(
    codec.decode_message(
      json.to_string(json_ot.to_json(message)),
      codec.DecodeContext(codec.Fluid310, compressor),
    )
    |> result.map_error(string.inspect),
  )
  use #(revision, originator, changeset) <- result.try(case message {
    codec.TreeMessage(
      codec.WireCommit(
        revision:,
        originator:,
        changes: [shared_change.DataChange(changeset)],
        ..,
      ),
      _,
    ) -> Ok(#(revision, originator, changeset))
    _ -> Error("expected one SharedTree data change")
  })
  use encoded <- result.try(
    codec.encode_message(
      message,
      codec.EncodeContext(codec.Fluid310, compressor, option.None),
    )
    |> result.map_error(string.inspect),
  )
  let encoded_bytes = json.to_string(encoded)
  use compressor_after <- result.try(
    fluid_ids.serialize(compressor, True)
    |> result.map_error(string.inspect),
  )
  use _ <- result.try(
    case json.to_string(compressor_after) == json.to_string(compressor_before) {
      True -> Ok(Nil)
      False -> Error("message codec mutated compressor state")
    },
  )
  use delta <- result.try(
    change.into_delta(change.TaggedChange(Some(revision), None, changeset))
    |> result.map_error(string.inspect),
  )
  Ok(#(
    observe(revision, originator, changeset, forest.delta_data(delta)),
    encoded,
    encoded_bytes,
  ))
}

fn observe(
  revision: fluid_ids.StableId,
  originator: fluid_ids.SessionId,
  changeset: change.Changeset,
  delta: forest.DeltaData,
) -> Json {
  let data = change.to_data(changeset)
  let constraints =
    data.nodes
    |> list.flat_map(fn(entry) {
      case entry.1.node_exists_constraint {
        None -> []
        Some(constraint) -> [
          json.object([#("violated", json.bool(constraint.violated))]),
        ]
      }
    })
  json.object([
    #("revision", json.string(fluid_ids.stable_id_to_string(revision))),
    #("originator", json.string(fluid_ids.session_id_to_string(originator))),
    #("changeset", fixture_codec.state_json(changeset)),
    #(
      "crossFieldKeys",
      fixture_codec.array(list.map(data.cross_field_keys, cross_field_key_json)),
    ),
    #("delta", delta_json(delta)),
    #("violations", json.int(data.constraint_violation_count)),
    #("constraints", fixture_codec.array(constraints)),
    #("builds", fixture_codec.array(list.map(data.builds, build_json))),
    #("refreshers", fixture_codec.array(list.map(data.refreshers, build_json))),
  ])
}

fn cross_field_key_json(value: change.CrossFieldKey) -> Json {
  let change.CrossFieldKey(key, count, field) = value
  let moves.Key(side, revision, local_id) = key
  let moves.FieldId(parent, field_name) = field
  json.object([
    #(
      "side",
      json.string(case side {
        moves.Source -> "source"
        moves.Destination -> "destination"
      }),
    ),
    #("revision", case revision {
      None -> json.null()
      Some(value) -> json.string(fluid_ids.stable_id_to_string(value))
    }),
    #("localId", json.int(local_id)),
    #("count", json.int(count)),
    #("parent", case parent {
      None -> json.null()
      Some(value) -> atom_json(value)
    }),
    #("field", json.string(field_name)),
  ])
}

fn delta_json(value: forest.DeltaData) -> Json {
  json.object([
    #("latestRevision", case value.latest_revision {
      None -> json.null()
      Some(value) -> json.string(fluid_ids.stable_id_to_string(value))
    }),
    #("fields", field_deltas_json(value.fields)),
    #("builds", fixture_codec.array(list.map(value.build, build_json))),
    #("refreshers", fixture_codec.array(list.map(value.refreshers, build_json))),
    #(
      "global",
      fixture_codec.array(
        list.map(value.global, fn(value) {
          let forest.DetachedChange(id, fields) = value
          json.object([
            #("id", atom_json(id)),
            #("fields", field_deltas_json(fields)),
          ])
        }),
      ),
    ),
    #(
      "renames",
      fixture_codec.array(
        list.map(value.rename, fn(value) {
          let forest.Rename(old_id, new_id, count) = value
          json.object([
            #("old", atom_json(old_id)),
            #("new", atom_json(new_id)),
            #("count", json.int(count)),
          ])
        }),
      ),
    ),
    #(
      "destroys",
      fixture_codec.array(
        list.map(value.destroy, fn(value) {
          let forest.Destroy(id, count) = value
          json.object([
            #("id", atom_json(id)),
            #("count", json.int(count)),
          ])
        }),
      ),
    ),
  ])
}

fn field_deltas_json(values: List(#(String, forest.FieldDelta))) -> Json {
  fixture_codec.array(
    list.map(values, fn(value) {
      json.object([
        #("field", json.string(value.0)),
        #("delta", field_delta_json(value.1)),
      ])
    }),
  )
}

fn field_delta_json(value: forest.FieldDelta) -> Json {
  let forest.FieldDelta(marks) = value
  fixture_codec.array(
    list.map(marks, fn(mark) {
      let forest.Mark(count, attach, detach, fields) = mark
      json.object([
        #("count", json.int(count)),
        #("attach", case attach {
          None -> json.null()
          Some(value) -> atom_json(value)
        }),
        #("detach", case detach {
          None -> json.null()
          Some(value) -> atom_json(value)
        }),
        #("fields", field_deltas_json(fields)),
      ])
    }),
  )
}

fn build_json(value: forest.Build) -> Json {
  json.object([
    #("id", atom_json(value.id)),
    #("trees", json.array(value.trees, fixtures.tree_value_to_json)),
  ])
}

fn atom_json(value: types.AtomId) -> Json {
  json.object([
    #("revision", case value.revision {
      None -> json.null()
      Some(value) -> json.string(fluid_ids.stable_id_to_string(value))
    }),
    #("localId", json.int(value.local_id)),
  ])
}

fn require_object(value: JsonValue, name: String) -> Result(Nil, String) {
  case value {
    VObject(_) -> Ok(Nil)
    _ -> Error("expected an object for " <> name)
  }
}
