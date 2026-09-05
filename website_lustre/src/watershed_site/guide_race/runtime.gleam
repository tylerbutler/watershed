import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import lustre/effect.{type Effect}
import retro_tutorial_lustre/board
import retro_tutorial_lustre/document_schema
import retro_tutorial_lustre/note
import watershed
import watershed/or_map_kernel
import watershed/sluice_js
import watershed_lustre

pub type Replica {
  Alpha
  Beta
}

pub type Phase {
  Static
  Starting
  Ready
  Delivering
  Failed
}

pub type PendingMarker {
  PendingMarker(
    sequence_number: Int,
    author: String,
    targets: List(String),
    key: String,
  )
}

pub type FlowMarker {
  FlowMarker(id: Int, from: String, to: String, label: String)
}

pub type LogEntry {
  LogEntry(sequence_number: Int, author: String, event: String, target: String)
}

pub type Model {
  Model(
    phase: Phase,
    rig: Option(Rig),
    alpha: board.Snapshot,
    beta: board.Snapshot,
    pending: List(PendingMarker),
    flows: List(FlowMarker),
    log: List(LogEntry),
    generation: Int,
    latency_ms: Int,
    race_locked: Bool,
    delivery_active: Bool,
    converged: Bool,
    error: Option(String),
    latest_sequence: Int,
  )
}

pub type Msg {
  Start
  Started(generation: Int, outcome: Result(Rig, DemoError))
  RunAddRace
  AddRaceSubmitted(generation: Int, outcome: Result(RaceMutation, DemoError))
  RunVoteRace
  VoteRaceSubmitted(generation: Int, outcome: Result(RaceMutation, DemoError))
  Deliver(generation: Int)
  Delivered(generation: Int, outcome: Result(DeliveryState, DemoError))
  ClearFlow(generation: Int, marker_id: Int)
  SetLatency(Int)
  Reset
  ResetDone(generation: Int, outcome: Result(Rig, DemoError))
  AnimationFailed(reason: String)
}

pub opaque type Rig {
  Rig(
    sluice: sluice_js.Sluice,
    alpha: ReplicaState,
    beta: ReplicaState,
    initial_alpha: board.Snapshot,
    initial_beta: board.Snapshot,
    initial_sequence: Int,
  )
}

type ReplicaState {
  ReplicaState(
    client_id: String,
    document: watershed.Document(document_schema.BoardDocument),
    notes: watershed.OrMap,
    votes: watershed.OrMap,
  )
}

pub type RaceMutation {
  RaceMutation(
    alpha: board.Snapshot,
    beta: board.Snapshot,
    pending: List(PendingMarker),
    flows: List(FlowMarker),
  )
}

pub type DeliveryState {
  DeliveryState(
    alpha: board.Snapshot,
    beta: board.Snapshot,
    log: List(LogEntry),
    sequence_number: Int,
    has_more: Bool,
  )
}

pub type DemoError {
  CannotCreateNotes(String)
  CannotCreateVotes(String)
  MissingHandle(replica: Replica, field: String)
  CannotResolveHandle(replica: Replica, field: String, reason: String)
  MissingClientId(replica: Replica)
  CannotProject(replica: Replica, reason: String)
  UnexpectedDelivery(event: String)
}

pub const starter_id = "note-survey-900-1"

pub fn static_model() -> Model {
  let snapshot =
    board.snapshot(
      "",
      [
        #(
          starter_id,
          note.Note("ship week went smoothly", "went_well", "survey", 900),
        ),
      ],
      [],
    )
  Model(
    Static,
    None,
    snapshot,
    snapshot,
    [],
    [],
    [],
    0,
    700,
    False,
    False,
    True,
    None,
    0,
  )
}

pub fn init() -> #(Model, Effect(Msg)) {
  update(static_model(), Start)
}

pub fn update(model: Model, message: Msg) -> #(Model, Effect(Msg)) {
  case message {
    Started(generation, _)
      | ResetDone(generation, _)
      | AddRaceSubmitted(generation, _)
      | VoteRaceSubmitted(generation, _)
      | Delivered(generation, _)
      | Deliver(generation)
      | ClearFlow(generation, _)
      if generation != model.generation
    -> #(model, effect.none())
    Start if model.phase == Static -> begin(model, False)
    Start -> #(model, effect.none())
    Reset ->
      begin(
        Model(
          ..static_model(),
          generation: model.generation + 1,
          latency_ms: model.latency_ms,
        ),
        True,
      )
    Started(_, outcome) | ResetDone(_, outcome) ->
      case outcome {
        Error(reason) -> failed(model, reason)
        Ok(rig) -> #(
          Model(
            ..model,
            phase: Ready,
            rig: Some(rig),
            alpha: rig.initial_alpha,
            beta: rig.initial_beta,
            latest_sequence: rig.initial_sequence,
            error: None,
            converged: rig.initial_alpha == rig.initial_beta,
          ),
          effect.none(),
        )
      }
    RunAddRace | RunVoteRace ->
      case model.phase, model.rig, model.race_locked {
        Ready, Some(rig), False -> {
          let operation = case message {
            RunVoteRace -> fn() { submit_vote_race(rig) }
            _ -> fn() { submit_add_race(rig) }
          }
          let outcome = case message {
            RunVoteRace -> fn(value) {
              VoteRaceSubmitted(model.generation, value)
            }
            _ -> fn(value) { AddRaceSubmitted(model.generation, value) }
          }
          #(
            Model(
              ..model,
              race_locked: True,
              delivery_active: True,
              converged: False,
              phase: Delivering,
            ),
            watershed_lustre.perform(operation:, outcome:),
          )
        }
        _, _, _ -> #(model, effect.none())
      }
    AddRaceSubmitted(_, outcome) | VoteRaceSubmitted(_, outcome) ->
      case outcome {
        Error(reason) -> failed(model, reason)
        Ok(mutation) -> #(
          Model(
            ..model,
            alpha: mutation.alpha,
            beta: mutation.beta,
            pending: mutation.pending,
            flows: mutation.flows,
            phase: Delivering,
            race_locked: True,
            delivery_active: True,
            converged: False,
          ),
          effect.batch([
            watershed_lustre.after(model.latency_ms, Deliver(model.generation)),
            clear_flows(model, mutation.flows),
          ]),
        )
      }
    Deliver(_) if model.phase != Delivering -> #(model, effect.none())
    Deliver(_) ->
      case model.rig, model.pending {
        Some(rig), [_, ..] -> #(
          model,
          watershed_lustre.perform(
            operation: fn() { deliver_group(rig) },
            outcome: fn(value) { Delivered(model.generation, value) },
          ),
        )
        _, _ -> #(model, effect.none())
      }
    Delivered(_, outcome) ->
      case outcome {
        Error(reason) -> failed(model, reason)
        Ok(delivery) -> {
          let pending =
            list.filter(model.pending, fn(marker) {
              marker.sequence_number > delivery.sequence_number
            })
          let flows =
            list.index_map(delivery.log, fn(entry, index) {
              FlowMarker(
                entry.sequence_number * 4 + index,
                "seq",
                entry.target,
                "SN " <> int.to_string(entry.sequence_number),
              )
            })
          let next = case delivery.has_more {
            True ->
              watershed_lustre.after(
                model.latency_ms,
                Deliver(model.generation),
              )
            False -> effect.none()
          }
          #(
            Model(
              ..model,
              alpha: delivery.alpha,
              beta: delivery.beta,
              pending:,
              flows: list.append(model.flows, flows),
              log: list.append(list.reverse(delivery.log), model.log),
              latest_sequence: delivery.sequence_number,
              delivery_active: delivery.has_more,
              converged: !delivery.has_more && delivery.alpha == delivery.beta,
              phase: case delivery.has_more {
                True -> Delivering
                False -> Ready
              },
            ),
            effect.batch([next, clear_flows(model, flows)]),
          )
        }
      }
    ClearFlow(_, id) -> #(
      Model(
        ..model,
        flows: list.filter(model.flows, fn(marker) { marker.id != id }),
      ),
      effect.none(),
    )
    SetLatency(value) -> #(
      Model(..model, latency_ms: int.clamp(value, 100, 2000)),
      effect.none(),
    )
    AnimationFailed(reason) -> failed(model, UnexpectedDelivery(reason))
  }
}

fn begin(model: Model, reset: Bool) -> #(Model, Effect(Msg)) {
  #(
    Model(..model, phase: Starting, converged: False),
    watershed_lustre.perform(operation: start_rig, outcome: fn(value) {
      case reset {
        True -> ResetDone(model.generation, value)
        False -> Started(model.generation, value)
      }
    }),
  )
}

fn failed(model: Model, reason: DemoError) -> #(Model, Effect(Msg)) {
  #(
    Model(
      ..model,
      phase: Failed,
      error: Some(describe_error(reason)),
      delivery_active: False,
      converged: False,
    ),
    effect.none(),
  )
}

fn clear_flows(model: Model, flows: List(FlowMarker)) -> Effect(Msg) {
  flows
  |> list.map(fn(marker) {
    watershed_lustre.after(
      model.latency_ms,
      ClearFlow(model.generation, marker.id),
    )
  })
  |> effect.batch
}

pub fn start_rig() -> Result(Rig, DemoError) {
  let sluice = sluice_js.start(tenant: "default", document: "guide-race-demo")
  let alpha = sluice_js.connect(sluice, "user-a")
  let beta = sluice_js.connect(sluice, "user-b")
  sluice_js.settle(sluice)
  let root = watershed.root_typed(alpha)
  use notes <- result.try(
    watershed.create_or_map(alpha, or_map_kernel.RegisterMode)
    |> result.map_error(CannotCreateNotes),
  )
  watershed.set_or_map_field(root, document_schema.notes(), notes)
  use votes <- result.try(
    watershed.create_or_map(alpha, or_map_kernel.TallyMode)
    |> result.map_error(CannotCreateVotes),
  )
  watershed.set_or_map_field(root, document_schema.votes(), votes)
  sluice_js.settle(sluice)
  use alpha <- result.try(resolve_replica(alpha, Alpha))
  use beta <- result.try(resolve_replica(beta, Beta))
  let _ =
    board.add_note(
      alpha.notes,
      "survey",
      "ship week went smoothly",
      board.WentWell,
      900,
      1,
    )
  sluice_js.settle(sluice)
  use initial_alpha <- result.try(project(alpha, Alpha))
  use initial_beta <- result.try(project(beta, Beta))
  Ok(Rig(
    sluice,
    alpha,
    beta,
    initial_alpha,
    initial_beta,
    sluice_js.sequence_number(sluice),
  ))
}

fn resolve_replica(
  document: watershed.Document(document_schema.BoardDocument),
  replica: Replica,
) -> Result(ReplicaState, DemoError) {
  let root = watershed.root_typed(document)
  use notes <- result.try(
    watershed.resolve_or_map_field(document, root, document_schema.notes())
    |> result.map_error(CannotResolveHandle(replica, "notes", _)),
  )
  use notes <- result.try(option.to_result(
    notes,
    MissingHandle(replica, "notes"),
  ))
  use votes <- result.try(
    watershed.resolve_or_map_field(document, root, document_schema.votes())
    |> result.map_error(CannotResolveHandle(replica, "votes", _)),
  )
  use votes <- result.try(option.to_result(
    votes,
    MissingHandle(replica, "votes"),
  ))
  use client_id <- result.try(
    watershed.client_id(document)
    |> option.to_result(MissingClientId(replica)),
  )
  Ok(ReplicaState(client_id, document, notes, votes))
}

fn project(
  state: ReplicaState,
  replica: Replica,
) -> Result(board.Snapshot, DemoError) {
  board.snapshot_from_channels("", state.notes, state.votes)
  |> result.map_error(CannotProject(replica, _))
}

pub fn submit_add_race(rig: Rig) -> Result(RaceMutation, DemoError) {
  let alpha_key =
    board.add_note(
      rig.alpha.notes,
      "user-a",
      "deploys got faster",
      board.WentWell,
      1000,
      1,
    )
  let alpha_sequence = sluice_js.sequence_number(rig.sluice)
  let beta_key =
    board.add_note(
      rig.beta.notes,
      "user-b",
      "standup stayed short",
      board.WentWell,
      1000,
      1,
    )
  let beta_sequence = sluice_js.sequence_number(rig.sluice)
  mutation(rig, [
    PendingMarker(
      alpha_sequence,
      "alpha",
      ["alpha", "beta"],
      "note:" <> alpha_key,
    ),
    PendingMarker(beta_sequence, "beta", ["alpha", "beta"], "note:" <> beta_key),
  ])
}

pub fn submit_vote_race(rig: Rig) -> Result(RaceMutation, DemoError) {
  board.upvote(rig.alpha.votes, starter_id)
  let first = sluice_js.sequence_number(rig.sluice)
  board.upvote(rig.beta.votes, starter_id)
  let second = sluice_js.sequence_number(rig.sluice)
  board.downvote(rig.beta.votes, starter_id)
  let third = sluice_js.sequence_number(rig.sluice)
  mutation(rig, [
    PendingMarker(first, "alpha", ["alpha", "beta"], "vote:" <> starter_id),
    PendingMarker(second, "beta", ["alpha", "beta"], "vote:" <> starter_id),
    PendingMarker(third, "beta", ["alpha", "beta"], "vote:" <> starter_id),
  ])
}

fn mutation(
  rig: Rig,
  pending: List(PendingMarker),
) -> Result(RaceMutation, DemoError) {
  use _ <- result.try(next_operation(rig))
  use alpha <- result.try(project(rig.alpha, Alpha))
  use beta <- result.try(project(rig.beta, Beta))
  Ok(RaceMutation(
    alpha,
    beta,
    pending,
    list.map(pending, fn(marker) {
      FlowMarker(-marker.sequence_number, marker.author, "seq", marker.key)
    }),
  ))
}

fn next_operation(rig: Rig) -> Result(sluice_js.Delivery, DemoError) {
  use next <- result.try(
    sluice_js.peek_info(rig.sluice)
    |> result.replace_error(UnexpectedDelivery("No operation is queued.")),
  )
  case next.sequence_number > 0 && next.event == "op" {
    True -> Ok(next)
    False -> Error(UnexpectedDelivery(next.event))
  }
}

pub fn deliver_group(rig: Rig) -> Result(DeliveryState, DemoError) {
  use next <- result.try(next_operation(rig))
  use log <- result.try(drain_group(rig, next.sequence_number, []))
  use alpha <- result.try(project(rig.alpha, Alpha))
  use beta <- result.try(project(rig.beta, Beta))
  Ok(DeliveryState(
    alpha,
    beta,
    log,
    next.sequence_number,
    sluice_js.pending(rig.sluice),
  ))
}

fn drain_group(
  rig: Rig,
  sequence: Int,
  log: List(LogEntry),
) -> Result(List(LogEntry), DemoError) {
  case sluice_js.peek_info(rig.sluice) {
    Ok(next) if next.sequence_number == sequence -> {
      use delivered <- result.try(
        sluice_js.step_info(rig.sluice)
        |> result.replace_error(UnexpectedDelivery(
          "Cannot deliver the queued operation.",
        )),
      )
      use target <- result.try(client_name(rig, delivered.to))
      drain_group(rig, sequence, [
        LogEntry(sequence, delivered.author, delivered.event, target),
        ..log
      ])
    }
    Ok(next) if next.sequence_number == 0 ->
      Error(UnexpectedDelivery(next.event))
    Ok(_) | Error(Nil) -> Ok(list.reverse(log))
  }
}

fn client_name(rig: Rig, id: String) -> Result(String, DemoError) {
  case id == rig.alpha.client_id, id == rig.beta.client_id {
    True, _ -> Ok("alpha")
    _, True -> Ok("beta")
    _, _ -> Error(UnexpectedDelivery("Unknown replica: " <> id))
  }
}

pub fn describe_error(error: DemoError) -> String {
  case error {
    CannotCreateNotes(reason) -> "Cannot create notes: " <> reason
    CannotCreateVotes(reason) -> "Cannot create votes: " <> reason
    MissingHandle(replica, field) ->
      replica_label(replica) <> ": Missing handle for " <> field
    CannotResolveHandle(replica, field, reason) ->
      replica_label(replica) <> ": Cannot resolve " <> field <> ": " <> reason
    MissingClientId(replica) -> replica_label(replica) <> ": Missing client ID."
    CannotProject(replica, reason) ->
      replica_label(replica) <> ": Cannot read the board: " <> reason
    UnexpectedDelivery(event) -> "Unexpected delivery: " <> event
  }
}

pub fn replica_label(replica: Replica) -> String {
  case replica {
    Alpha -> "Client A"
    Beta -> "Client B"
  }
}
