//// `KernelModel` for `ordered_collection_kernel`.
////
//// The model op carries the acquire callback disposition so the harness's
//// reactive-op capability can emit the follow-on complete/release only after a
//// local acquire successfully sequences.

import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import qcheck
import watershed/fuzz/kernel_fuzz.{
  type KernelModel, type LogEntry, Capabilities, KernelModel,
}
import watershed/ordered_collection_kernel.{
  type JobEntry, type OrderedState, Add, Added, Complete, Completed, JobEntry,
  Release,
}

pub type Disposition {
  CompleteAfterAcquire
  ReleaseAfterAcquire
}

pub type OrderedCommand {
  CommandAdd(raw_value: Int, value: Int)
  CommandAcquire(raw_id: Int, acquire_id: String, disposition: Disposition)
  CommandComplete(raw_id: Int, acquire_id: String)
  CommandRelease(raw_id: Int, acquire_id: String)
}

pub type ModelState {
  ModelState(
    kernel: OrderedState,
    submitted_ids: List(String),
    added: List(Json),
    completed: List(Json),
  )
}

type OracleState {
  OracleState(
    queue: List(Json),
    jobs: Dict(String, JobEntry),
    completed: List(Json),
  )
}

fn init_state() -> ModelState {
  ModelState(
    kernel: ordered_collection_kernel.new(),
    submitted_ids: [],
    added: [],
    completed: [],
  )
}

fn acquire_id(raw_id: Int, client_id: Int) -> String {
  int.to_string(client_id) <> ":" <> int.to_string(raw_id)
}

fn concrete_value(raw_value: Int, client_id: Int) -> Int {
  client_id * 1000 + raw_value
}

fn command_to_kernel_op(
  command: OrderedCommand,
) -> ordered_collection_kernel.OrderedOp {
  case command {
    CommandAdd(_, value) -> Add(json.int(value))
    CommandAcquire(_, acquire_id, _) ->
      ordered_collection_kernel.acquire(acquire_id)
    CommandComplete(_, acquire_id) -> Complete(acquire_id)
    CommandRelease(_, acquire_id) -> Release(acquire_id)
  }
}

fn disposition_to_string(disposition: Disposition) -> String {
  case disposition {
    CompleteAfterAcquire -> "complete"
    ReleaseAfterAcquire -> "release"
  }
}

fn disposition_from_string(value: String) -> Disposition {
  case value {
    "release" -> ReleaseAfterAcquire
    _ -> CompleteAfterAcquire
  }
}

fn op_to_json(command: OrderedCommand) -> Json {
  case command {
    CommandAdd(raw_value, value) ->
      json.object([
        #("tag", json.string("Add")),
        #("raw_value", json.int(raw_value)),
        #("value", json.int(value)),
      ])
    CommandAcquire(raw_id, acquire_id, disposition) ->
      json.object([
        #("tag", json.string("Acquire")),
        #("raw_id", json.int(raw_id)),
        #("acquire_id", json.string(acquire_id)),
        #("disposition", json.string(disposition_to_string(disposition))),
      ])
    CommandComplete(raw_id, acquire_id) ->
      json.object([
        #("tag", json.string("Complete")),
        #("raw_id", json.int(raw_id)),
        #("acquire_id", json.string(acquire_id)),
      ])
    CommandRelease(raw_id, acquire_id) ->
      json.object([
        #("tag", json.string("Release")),
        #("raw_id", json.int(raw_id)),
        #("acquire_id", json.string(acquire_id)),
      ])
  }
}

fn op_decoder() -> decode.Decoder(OrderedCommand) {
  use tag <- decode.field("tag", decode.string)
  case tag {
    "Add" -> {
      use raw_value <- decode.field("raw_value", decode.int)
      use value <- decode.field("value", decode.int)
      decode.success(CommandAdd(raw_value, value))
    }
    "Acquire" -> {
      use raw_id <- decode.field("raw_id", decode.int)
      use acquire_id <- decode.field("acquire_id", decode.string)
      use disposition <- decode.field("disposition", decode.string)
      decode.success(CommandAcquire(
        raw_id,
        acquire_id,
        disposition_from_string(disposition),
      ))
    }
    "Complete" -> {
      use raw_id <- decode.field("raw_id", decode.int)
      use acquire_id <- decode.field("acquire_id", decode.string)
      decode.success(CommandComplete(raw_id, acquire_id))
    }
    "Release" -> {
      use raw_id <- decode.field("raw_id", decode.int)
      use acquire_id <- decode.field("acquire_id", decode.string)
      decode.success(CommandRelease(raw_id, acquire_id))
    }
    _ -> decode.failure(CommandAdd(0, 0), "ordered collection op")
  }
}

fn op_generator() -> qcheck.Generator(OrderedCommand) {
  qcheck.tuple3(
    qcheck.small_non_negative_int(),
    qcheck.small_non_negative_int(),
    qcheck.small_non_negative_int(),
  )
  |> qcheck.map(fn(ints) {
    let raw_id = ints.1 % 16
    case ints.0 % 10 {
      0 | 1 | 2 | 3 -> CommandAdd(ints.2 % 32, 0)
      4 | 5 | 6 | 7 -> {
        let disposition = case ints.0 % 2 {
          0 -> CompleteAfterAcquire
          _ -> ReleaseAfterAcquire
        }
        CommandAcquire(raw_id, "", disposition)
      }
      8 -> CommandComplete(raw_id, "")
      _ -> CommandRelease(raw_id, "")
    }
  })
}

fn completed_from_events(
  events: List(ordered_collection_kernel.OrderedEvent),
) -> List(Json) {
  events
  |> list.filter_map(fn(event) {
    case event {
      Completed(value, _) -> Ok(value)
      Added(..)
      | ordered_collection_kernel.Acquired(..)
      | ordered_collection_kernel.LocalReleased(..) -> Error(Nil)
    }
  })
}

fn add_values_from_events(
  events: List(ordered_collection_kernel.OrderedEvent),
) -> List(Json) {
  events
  |> list.filter_map(fn(event) {
    case event {
      Added(value, True, _) -> Ok(value)
      Added(_, False, _)
      | ordered_collection_kernel.Acquired(..)
      | Completed(..)
      | ordered_collection_kernel.LocalReleased(..) -> Error(Nil)
    }
  })
}

fn submit(
  state: ModelState,
  command: OrderedCommand,
  meta: kernel_fuzz.SubmitMeta,
) -> #(ModelState, Option(OrderedCommand)) {
  case command {
    CommandAdd(raw_value, _) -> {
      let value = concrete_value(raw_value, meta.client_id)
      #(state, Some(CommandAdd(raw_value, value)))
    }
    CommandAcquire(raw_id, _, disposition) -> {
      let id = acquire_id(raw_id, meta.client_id)
      case list.contains(state.submitted_ids, id) {
        True -> #(state, None)
        False -> #(
          ModelState(
            ..state,
            submitted_ids: list.append(state.submitted_ids, [id]),
          ),
          Some(CommandAcquire(raw_id, id, disposition)),
        )
      }
    }
    CommandComplete(raw_id, _) -> #(
      state,
      Some(CommandComplete(raw_id, acquire_id(raw_id, meta.client_id))),
    )
    CommandRelease(raw_id, _) -> #(
      state,
      Some(CommandRelease(raw_id, acquire_id(raw_id, meta.client_id))),
    )
  }
}

fn apply_op(
  state: ModelState,
  command: OrderedCommand,
  author: Int,
  local: Bool,
) -> ModelState {
  case command {
    CommandAdd(_, _value) -> {
      let #(kernel, events) = case local {
        True ->
          ordered_collection_kernel.ack_local(
            state.kernel,
            command_to_kernel_op(command),
            author,
          )
          |> fn(result) {
            let #(kernel, events, _) = result
            #(kernel, events)
          }
        False ->
          ordered_collection_kernel.apply_remote(
            state.kernel,
            command_to_kernel_op(command),
            author,
          )
      }
      ModelState(
        ..state,
        kernel: kernel,
        added: list.append(state.added, add_values_from_events(events)),
      )
    }
    CommandAcquire(_, acquire_id, _) -> {
      let kernel = case local {
        True -> {
          let #(kernel, _events, _outcome) =
            ordered_collection_kernel.ack_local_acquire(
              state.kernel,
              acquire_id,
              Some(author),
            )
          kernel
        }
        False -> {
          let #(kernel, _events, _outcome) =
            ordered_collection_kernel.apply_acquire(
              state.kernel,
              acquire_id,
              Some(author),
            )
          kernel
        }
      }
      ModelState(..state, kernel: kernel)
    }
    CommandComplete(_, _) | CommandRelease(_, _) -> {
      let #(kernel, events) = case local {
        True -> {
          let #(kernel, events, _) =
            ordered_collection_kernel.ack_local(
              state.kernel,
              command_to_kernel_op(command),
              author,
            )
          #(kernel, events)
        }
        False ->
          ordered_collection_kernel.apply_remote(
            state.kernel,
            command_to_kernel_op(command),
            author,
          )
      }
      ModelState(
        ..state,
        kernel: kernel,
        completed: list.append(state.completed, completed_from_events(events)),
      )
    }
  }
}

fn apply_remote(
  state: ModelState,
  command: OrderedCommand,
  meta: kernel_fuzz.SequencedMeta,
) -> Result(ModelState, String) {
  Ok(apply_op(state, command, meta.client_id, False))
}

fn ack_local(
  state: ModelState,
  command: OrderedCommand,
  meta: kernel_fuzz.SequencedMeta,
) -> Result(ModelState, String) {
  Ok(apply_op(state, command, meta.client_id, True))
}

fn react(
  state: ModelState,
  command: OrderedCommand,
  _meta: kernel_fuzz.SequencedMeta,
  self_id: Int,
  is_local: Bool,
) -> List(OrderedCommand) {
  case is_local {
    False -> []
    True ->
      case command {
        CommandAcquire(raw_id, acquire_id, disposition) -> {
          case dict.get(state.kernel.jobs, acquire_id) {
            Ok(JobEntry(_, Some(owner))) if owner == self_id ->
              case disposition {
                CompleteAfterAcquire -> [CommandComplete(raw_id, acquire_id)]
                ReleaseAfterAcquire -> [CommandRelease(raw_id, acquire_id)]
              }
            Ok(JobEntry(_, Some(_))) | Ok(JobEntry(_, None)) | Error(Nil) -> []
          }
        }
        CommandAdd(..) | CommandComplete(..) | CommandRelease(..) -> []
      }
  }
}

fn remove_member(
  state: ModelState,
  leaver: Int,
  _meta: kernel_fuzz.SequencedMeta,
) -> ModelState {
  let #(kernel, _events) =
    ordered_collection_kernel.remove_client(state.kernel, Some(leaver))
  ModelState(..state, kernel: kernel)
}

pub fn observe(
  state: ModelState,
) -> #(List(Json), List(#(String, JobEntry)), List(Json)) {
  #(
    ordered_collection_kernel.summary_queue(state.kernel),
    ordered_collection_kernel.summary_jobs(state.kernel),
    state.completed,
  )
}

fn load_from_synced(state: ModelState, _id: Int) -> ModelState {
  ModelState(
    ..state,
    kernel: ordered_collection_kernel.from_summary(
      ordered_collection_kernel.summary_queue(state.kernel),
      ordered_collection_kernel.summary_jobs(state.kernel),
    ),
  )
}

fn apply_oracle_op(
  state: OracleState,
  entry: #(Int, OrderedCommand),
) -> OracleState {
  let #(author, command) = entry
  case command {
    CommandAdd(_, value) ->
      OracleState(..state, queue: list.append(state.queue, [json.int(value)]))
    CommandAcquire(_, acquire_id, _) ->
      case state.queue {
        [] -> state
        [value, ..rest] ->
          OracleState(
            queue: rest,
            jobs: dict.insert(
              state.jobs,
              acquire_id,
              JobEntry(value, Some(author)),
            ),
            completed: state.completed,
          )
      }
    CommandComplete(_, acquire_id) ->
      case dict.get(state.jobs, acquire_id) {
        Error(_) -> state
        Ok(JobEntry(value, _)) ->
          OracleState(
            ..state,
            jobs: dict.delete(state.jobs, acquire_id),
            completed: list.append(state.completed, [value]),
          )
      }
    CommandRelease(_, acquire_id) ->
      case dict.get(state.jobs, acquire_id) {
        Error(_) -> state
        Ok(JobEntry(value, _)) ->
          OracleState(
            queue: list.append(state.queue, [value]),
            jobs: dict.delete(state.jobs, acquire_id),
            completed: state.completed,
          )
      }
  }
}

fn oracle_remove_member(state: OracleState, leaver: Int) -> OracleState {
  let #(jobs, returned) =
    dict.to_list(state.jobs)
    |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
    |> list.fold(#(state.jobs, []), fn(acc, entry) {
      let #(jobs, returned) = acc
      let #(acquire_id, JobEntry(value, owner)) = entry
      case owner == Some(leaver) {
        True -> #(dict.delete(jobs, acquire_id), list.append(returned, [value]))
        False -> acc
      }
    })
  OracleState(..state, queue: list.append(state.queue, returned), jobs: jobs)
}

fn oracle(
  entries: List(LogEntry(OrderedCommand)),
) -> #(List(Json), List(#(String, JobEntry)), List(Json)) {
  let state =
    list.fold(
      entries,
      OracleState(queue: [], jobs: dict.new(), completed: []),
      fn(state, entry) {
        case entry {
          kernel_fuzz.OpEntry(author, command, _) ->
            apply_oracle_op(state, #(author, command))
          kernel_fuzz.LeaveEntry(leaver) -> oracle_remove_member(state, leaver)
        }
      },
    )
  #(
    state.queue,
    dict.to_list(state.jobs) |> list.sort(fn(a, b) { string.compare(a.0, b.0) }),
    state.completed,
  )
}

fn count(list: List(Json), value: Json) -> Int {
  list.fold(list, 0, fn(total, item) {
    case item == value {
      True -> total + 1
      False -> total
    }
  })
}

fn check_conservation(state: ModelState) -> Result(Nil, String) {
  let in_jobs =
    ordered_collection_kernel.summary_jobs(state.kernel)
    |> list.map(fn(entry) {
      let #(_, JobEntry(value, _)) = entry
      value
    })
  let present =
    ordered_collection_kernel.summary_queue(state.kernel)
    |> list.append(in_jobs)
    |> list.append(state.completed)
  case list.length(present) == list.length(state.added) {
    False ->
      Error(
        "conservation length mismatch: added "
        <> int.to_string(list.length(state.added))
        <> ", present "
        <> int.to_string(list.length(present)),
      )
    True -> {
      let mismatch =
        state.added
        |> list.any(fn(value) {
          count(state.added, value) != count(present, value)
        })
      case mismatch {
        True -> Error("conservation count mismatch")
        False -> Ok(Nil)
      }
    }
  }
}

fn rollback(state: ModelState, command: OrderedCommand) -> ModelState {
  case command {
    CommandAcquire(_, acquire_id, _) ->
      ModelState(
        ..state,
        submitted_ids: list.filter(state.submitted_ids, fn(id) {
          id != acquire_id
        }),
      )
    CommandAdd(..) | CommandComplete(..) | CommandRelease(..) -> state
  }
}

fn apply_stashed(
  state: ModelState,
  command: OrderedCommand,
  meta: kernel_fuzz.SubmitMeta,
) -> #(ModelState, OrderedCommand) {
  case submit(state, command, meta) {
    #(state, Some(routed)) -> #(state, routed)
    #(state, None) -> #(state, CommandRelease(0, ""))
  }
}

pub fn model() -> KernelModel(
  ModelState,
  OrderedCommand,
  #(List(Json), List(#(String, JobEntry)), List(Json)),
) {
  KernelModel(
    name: "ordered_collection",
    init: fn(_id) { init_state() },
    submit: submit,
    apply_remote: apply_remote,
    ack_local: ack_local,
    observe: observe,
    gen_op: op_generator(),
    check: Some(check_conservation),
    canonicalize: None,
    ack_preserves_view: False,
    op_to_json: op_to_json,
    op_decoder: op_decoder(),
    capabilities: Capabilities(
      load_from_synced: Some(load_from_synced),
      oracle: Some(oracle),
      rollback: Some(rollback),
      resubmit: None,
      apply_stashed: Some(apply_stashed),
      react: Some(react),
      remove_member: Some(remove_member),
    ),
  )
}
