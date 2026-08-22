import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

import watershed/browser
import watershed/g_set_kernel
import watershed/or_set_kernel
import watershed/two_p_set_kernel
import watershed.{
  type Document, type GSet, type OrSet, type Ripple, type TwoPSet,
}
import watershed_lustre

import doc_schema
import grocery_triptych_lustre/bootstrap_guard.{
  type Feedback, type FeedbackKind, Info, Warning,
}
import pantry_snapshot.{type DiffCounts, type Row, type Snapshots}
import refresh_guard
import scenario_protocol
import scenario_state
import triptych_actions

const socket_url = "ws://localhost:4000/socket/websocket?vsn=2.0.0"

const tenant = "dev-tenant"

const tenant_secret = "levee-dev-secret-change-in-production"

/// UI debounce window for grouping independently delivered pantry-channel op
/// frames into one snapshot refresh. This smooths transport timing without
/// implying atomic multi-channel delivery.
const shared_refresh_debounce_ms = 75

const tombstone_start_delay_ms = 250

const tombstone_step_ms = 650

const concurrent_prepare_ms = 350

/// The peer must stay Go-eligible for the initiator's full acknowledgement
/// window plus a delivery margin, or a late ack can be selected after the
/// peer has already returned Idle.
const concurrent_invite_timeout_ms = 1600

const concurrent_ack_delivery_margin_ms = 600

const concurrent_peer_go_timeout_ms = 2200

const concurrent_verify_retry_ms = 125

const concurrent_verify_attempts = 12

pub fn main() {
  let app = lustre.application(init, update, view)
  let document = browser.document_on_navigate("grocery-triptych")
  let assert Ok(_) = lustre.start(app, "#app", document)
  Nil
}

type Model {
  Model(
    document_name: String,
    user_id: String,
    readiness: Readiness,
    doc: Option(Document(doc_schema.Pantry)),
    ready_callback_seen: Bool,
    bootstrap_requested: Bool,
    pending: PendingPantry,
    shared: Option(SharedPantry),
    draft: String,
    snapshots: Snapshots,
    rows: List(Row),
    diffs: DiffCounts,
    shared_refresh: refresh_guard.State,
    feedback: Option(Feedback),
    scenario: ScenarioState,
    error: Option(String),
  )
}

type Readiness {
  WaitingForHandleAndReady
  WaitingForHandle
  WaitingForReady
  Bootstrapping
  Ready
  Failed
}

type SharedPantry {
  SharedPantry(grow_only: GSet, two_phase: TwoPSet, observed: OrSet)
}

type PendingPantry {
  PendingPantry(
    grow_only: Option(GSet),
    two_phase: Option(TwoPSet),
    observed: Option(OrSet),
  )
}

type ScenarioState {
  ScenarioState(
    tombstone: TombstoneState,
    concurrent: ConcurrentState,
    handled_run_ids: List(String),
  )
}

type TombstoneState {
  TombstoneAvailable
  TombstoneRunning(TombstoneStep)
  TombstoneComplete
}

type TombstoneStep {
  TombstoneAddStep
  TombstoneRemoveStep
  TombstoneReAddStep
}

type ConcurrentState {
  ConcurrentIdle(last_status: Option(String))
  ConcurrentLocked(last_status: String, disabled_reason: String)
  ConcurrentComplete(last_status: String, disabled_reason: String)
  ConcurrentInitiator(
    run_id: String,
    phase: InitiatorPhase,
    selected_peer: Option(String),
    peer_applied: Bool,
    attempts_remaining: Int,
  )
  ConcurrentPeer(
    run_id: String,
    initiator: String,
    phase: PeerPhase,
    attempts_remaining: Int,
    note: Option(String),
  )
}

type InitiatorPhase {
  ConcurrentPreparing
  ConcurrentAwaitingAck
  ConcurrentRemoving
  ConcurrentVerifying
}

type PeerPhase {
  PeerAwaitingGo
  PeerVerifying
}

type ScenarioName {
  TombstoneScenario
  ConcurrentAddRemoveScenario
}

type Panel {
  GrowOnlyPanel
  TwoPhasePanel
  ObservedPanel
}

type Msg {
  GotHandle(Document(doc_schema.Pantry))
  Connected(Result(Nil, String))
  EnsuredGrowOnly(Result(GSet, String))
  EnsuredTwoPhase(Result(TwoPSet, String))
  EnsuredObserved(Result(OrSet, String))
  DraftChanged(String)
  AddSubmitted
  RemoveRequested(String)
  ScenarioRequested(ScenarioName)
  ScenarioRippleReceived(Ripple)
  TombstoneStepDue(TombstoneStep)
  ConcurrentInvitePeers(String)
  ConcurrentInviteTimedOut(String)
  ConcurrentPeerGoTimedOut(String)
  ConcurrentInitiatorRemove(String, String)
  VerifyConcurrent(String)
  GrowOnlyChanged(g_set_kernel.GSetEvent)
  TwoPhaseChanged(two_p_set_kernel.TwoPSetEvent)
  ObservedChanged(or_set_kernel.OrSetEvent)
  FlushSharedRefresh(Int)
}

fn init(document: String) -> #(Model, Effect(Msg)) {
  let user_id = "web-" <> int.to_string(1000 + int.random(9000))
  let model =
    Model(
      document_name: document,
      user_id: user_id,
      readiness: WaitingForHandleAndReady,
      doc: None,
      ready_callback_seen: False,
      bootstrap_requested: False,
      pending: PendingPantry(None, None, None),
      shared: None,
      draft: "",
      snapshots: pantry_snapshot.empty(),
      rows: [],
      diffs: pantry_snapshot.empty_diff_counts(),
      shared_refresh: refresh_guard.idle(),
      feedback: Some(bootstrap_guard.info(
        "waiting for document handle and ready callback",
      )),
      scenario: ScenarioState(
        tombstone: TombstoneAvailable,
        concurrent: ConcurrentIdle(None),
        handled_run_ids: [],
      ),
      error: None,
    )
  #(
    model,
    watershed_lustre.connect_dev(
      url: socket_url,
      tenant: tenant,
      secret: tenant_secret,
      document: document,
      user_id: user_id,
      got_document: GotHandle,
      connected: Connected,
    ),
  )
}

fn bootstrap_effect(doc: Document(doc_schema.Pantry)) -> Effect(Msg) {
  let root = watershed.root_typed(doc)
  effect.batch([
    watershed_lustre.ensure_g_set(
      doc,
      root,
      doc_schema.grow_only(),
      EnsuredGrowOnly,
    ),
    watershed_lustre.ensure_two_p_set(
      doc,
      root,
      doc_schema.two_phase(),
      EnsuredTwoPhase,
    ),
    watershed_lustre.ensure_or_set(
      doc,
      root,
      doc_schema.observed(),
      EnsuredObserved,
    ),
  ])
}

fn subscribe_shared_effect(shared: SharedPantry) -> Effect(Msg) {
  effect.batch([
    watershed_lustre.subscribe_g_set(shared.grow_only, GrowOnlyChanged),
    watershed_lustre.subscribe_two_p_set(shared.two_phase, TwoPhaseChanged),
    watershed_lustre.subscribe_or_set(shared.observed, ObservedChanged),
  ])
}

fn ready_effect(model: Model, shared: SharedPantry) -> Effect(Msg) {
  case model.doc {
    Some(doc) ->
      effect.batch([
        subscribe_shared_effect(shared),
        watershed_lustre.subscribe_ripples(doc, ScenarioRippleReceived),
      ])

    None -> subscribe_shared_effect(shared)
  }
}

fn maybe_bootstrap(model: Model) -> #(Model, Effect(Msg)) {
  case model.error {
    Some(_) -> #(Model(..model, readiness: Failed), effect.none())
    None ->
      case model.shared {
        Some(_) -> #(Model(..model, readiness: Ready), effect.none())
        None ->
          case model.doc, model.ready_callback_seen, model.bootstrap_requested {
            Some(doc), True, False -> {
              let model =
                Model(
                  ..model,
                  readiness: Bootstrapping,
                  bootstrap_requested: True,
                  feedback: Some(bootstrap_guard.info(
                    "bootstrapping pantry channels",
                  )),
                )
              #(model, bootstrap_effect(doc))
            }
            Some(_), True, True -> #(
              Model(..model, readiness: Bootstrapping),
              effect.none(),
            )
            Some(_), False, _ -> #(
              Model(..model, readiness: WaitingForReady),
              effect.none(),
            )
            None, True, _ -> #(
              Model(..model, readiness: WaitingForHandle),
              effect.none(),
            )
            None, False, _ -> #(
              Model(..model, readiness: WaitingForHandleAndReady),
              effect.none(),
            )
          }
      }
  }
}

fn assemble(model: Model) -> #(Model, Effect(Msg)) {
  case bootstrap_guard.failure_latched(model.error) {
    True -> #(Model(..model, readiness: Failed), effect.none())
    False ->
      case model.shared, model.pending {
        None, PendingPantry(Some(grow_only), Some(two_phase), Some(observed)) -> {
          let shared = SharedPantry(grow_only:, two_phase:, observed:)
          let model =
            Model(
              ..model,
              shared: Some(shared),
              readiness: Ready,
              feedback: Some(bootstrap_guard.info("pantry handles assembled")),
            )
            |> refresh_snapshots
          #(model, ready_effect(model, shared))
        }
        Some(_), _ -> #(Model(..model, readiness: Ready), effect.none())
        None, _ -> #(Model(..model, readiness: Bootstrapping), effect.none())
      }
  }
}

fn refresh_snapshots(model: Model) -> Model {
  case model.shared {
    Some(shared) ->
      apply_shared_snapshots(model, shared, snapshots_of_shared(shared))
    None -> model
  }
}

fn snapshots_of_shared(shared: SharedPantry) -> Snapshots {
  pantry_snapshot.from_values(
    grow_only: watershed.g_set_values(shared.grow_only),
    two_phase: watershed.two_p_set_values(shared.two_phase),
    observed: watershed.or_set_values(shared.observed),
  )
}

fn apply_shared_snapshots(
  model: Model,
  shared: SharedPantry,
  snapshots: Snapshots,
) -> Model {
  let rows = pantry_snapshot.rows(snapshots)
  let tombstone = derive_tombstone_state(model.scenario.tombstone, snapshots)
  let concurrent = derive_concurrent_state(model.scenario.concurrent, snapshots)

  Model(
    ..model,
    shared: Some(shared),
    readiness: Ready,
    snapshots: snapshots,
    rows: rows,
    diffs: pantry_snapshot.diff_counts(rows),
    scenario: ScenarioState(
      ..model.scenario,
      tombstone: tombstone,
      concurrent: concurrent,
    ),
  )
}

fn derive_tombstone_state(
  current: TombstoneState,
  snapshots: Snapshots,
) -> TombstoneState {
  case current {
    TombstoneRunning(_) -> current
    _ ->
      case scenario_state.tombstone_matches_expected(snapshots) {
        True -> TombstoneComplete
        False -> TombstoneAvailable
      }
  }
}

fn derive_concurrent_state(
  current: ConcurrentState,
  snapshots: Snapshots,
) -> ConcurrentState {
  case current {
    ConcurrentInitiator(_, _, _, _, _) | ConcurrentPeer(_, _, _, _, _) ->
      current

    _ ->
      case scenario_state.concurrent_durable_state(snapshots) {
        scenario_state.DurableRetryable -> current
        scenario_state.DurableComplete(status, disabled_reason) ->
          ConcurrentComplete(status, disabled_reason)
        scenario_state.DurableLocked(status, disabled_reason) ->
          ConcurrentLocked(status, disabled_reason)
      }
  }
}

fn schedule_shared_refresh(model: Model) -> #(Model, Effect(Msg)) {
  case model.shared, bootstrap_guard.failure_latched(model.error) {
    Some(_), False -> {
      let #(shared_refresh, generation) =
        refresh_guard.request(model.shared_refresh)

      #(
        Model(..model, shared_refresh: shared_refresh),
        watershed_lustre.after(
          shared_refresh_debounce_ms,
          FlushSharedRefresh(generation),
        ),
      )
    }
    _, _ -> #(model, effect.none())
  }
}

fn flush_shared_refresh(model: Model, generation: Int) -> Model {
  let #(shared_refresh, accepted) =
    refresh_guard.flush(model.shared_refresh, generation)
  let model = Model(..model, shared_refresh: shared_refresh)

  case accepted, model.shared, bootstrap_guard.failure_latched(model.error) {
    True, Some(_), False -> refresh_snapshots(model)
    _, _, _ -> model
  }
}

fn fail(model: Model, reason: String) -> Model {
  Model(
    ..model,
    readiness: Failed,
    feedback: Some(bootstrap_guard.warning(reason)),
    error: Some(reason),
  )
}

fn controls_ready(model: Model) -> Bool {
  option.is_some(model.shared) && !bootstrap_guard.failure_latched(model.error)
}

fn scenario_busy(model: Model) -> Bool {
  tombstone_running(model.scenario.tombstone)
  || concurrent_active(model.scenario.concurrent)
}

fn tombstone_running(state: TombstoneState) -> Bool {
  case state {
    TombstoneRunning(_) -> True
    _ -> False
  }
}

fn tombstone_completed(state: TombstoneState) -> Bool {
  case state {
    TombstoneComplete -> True
    _ -> False
  }
}

fn concurrent_active(state: ConcurrentState) -> Bool {
  case state {
    ConcurrentIdle(_) | ConcurrentLocked(_, _) | ConcurrentComplete(_, _) ->
      False
    _ -> True
  }
}

fn with_feedback(model: Model, feedback: Feedback) -> Model {
  case bootstrap_guard.failure_latched(model.error) {
    True -> model
    False -> Model(..model, feedback: Some(feedback))
  }
}

fn feedback_of_kind(kind: FeedbackKind, message: String) -> Feedback {
  case kind {
    Info -> bootstrap_guard.info(message)
    Warning -> bootstrap_guard.warning(message)
  }
}

fn own_client_id(model: Model) -> Option(String) {
  model.doc
  |> option.then(watershed.client_id)
}

fn seen_run_ids(model: Model) -> List(String) {
  model.scenario.handled_run_ids
}

fn has_seen_run_id(model: Model, run_id: String) -> Bool {
  scenario_state.has_seen_run_id(seen_run_ids(model), run_id)
}

fn remember_run_id(model: Model, run_id: String) -> Model {
  Model(
    ..model,
    scenario: ScenarioState(
      ..model.scenario,
      handled_run_ids: scenario_state.remember_run_id(
        seen_run_ids(model),
        run_id,
      ),
    ),
  )
}

fn next_run_id(model: Model) -> String {
  option.unwrap(own_client_id(model), model.user_id)
  <> "-"
  <> int.to_string(int.random(1_000_000))
}

fn shared_action_reason(model: Model) -> Option(String) {
  case controls_ready(model) {
    False ->
      Some(
        "Shared edits are disabled until the document handle and pantry bootstrap finish.",
      )

    True ->
      case scenario_busy(model) {
        True ->
          Some(
            "Shared edits are disabled while the current scenario is running.",
          )
        False -> None
      }
  }
}

fn tombstone_button_reason(model: Model) -> Option(String) {
  case model.scenario.tombstone {
    TombstoneRunning(_) -> Some("Tombstone is already running in this room.")
    state ->
      case tombstone_completed(state) {
        True -> Some(scenario_state.tombstone_locked_message())
        False ->
          scenario_state.tombstone_button_reason(
            ready: controls_ready(model),
            busy: concurrent_active(model.scenario.concurrent),
            completed: False,
          )
      }
  }
}

fn concurrent_button_reason(model: Model) -> Option(String) {
  case controls_ready(model) {
    False ->
      Some(
        "Concurrent add/remove is disabled until the document handle and pantry bootstrap finish.",
      )

    True ->
      case model.scenario.concurrent {
        ConcurrentLocked(_, disabled_reason)
        | ConcurrentComplete(_, disabled_reason) -> Some(disabled_reason)
        _ ->
          case model.scenario.tombstone {
            TombstoneRunning(_) ->
              Some(
                "Concurrent add/remove is disabled while Tombstone is running.",
              )

            _ ->
              case model.scenario.concurrent {
                ConcurrentIdle(_) -> None
                _ ->
                  Some("Concurrent add/remove is already running in this tab.")
              }
          }
      }
  }
}

fn submit_scenario_ripple(
  model: Model,
  message: scenario_protocol.Message,
) -> Effect(Msg) {
  case model.doc {
    Some(doc) ->
      watershed_lustre.submit_ripple(
        doc,
        ripple_type: scenario_protocol.ripple_type,
        content: scenario_protocol.encode(message),
      )

    None -> effect.none()
  }
}

fn schedule_concurrent_verification(run_id: String) -> Effect(Msg) {
  watershed_lustre.after(concurrent_verify_retry_ms, VerifyConcurrent(run_id))
}

pub fn concurrent_peer_go_timeout_covers_ack_window() -> Bool {
  concurrent_peer_go_timeout_ms
  >= concurrent_invite_timeout_ms + concurrent_ack_delivery_margin_ms
}

fn set_concurrent_timeout_state(
  model: Model,
  timeout_state: scenario_state.ConcurrentTimeoutState,
  feedback: Feedback,
) -> Model {
  let concurrent = case timeout_state {
    scenario_state.RetryableTimeout(status) -> ConcurrentIdle(Some(status))
    scenario_state.LockedTimeout(status, disabled_reason) ->
      ConcurrentLocked(status, disabled_reason)
  }

  Model(
    ..model,
    scenario: ScenarioState(..model.scenario, concurrent: concurrent),
  )
  |> with_feedback(feedback)
}

fn set_concurrent_durable_state(
  model: Model,
  durable_state: scenario_state.ConcurrentDurableState,
) -> Model {
  case durable_state {
    scenario_state.DurableRetryable -> model
    scenario_state.DurableComplete(status, disabled_reason) ->
      Model(
        ..model,
        scenario: ScenarioState(
          ..model.scenario,
          concurrent: ConcurrentComplete(status, disabled_reason),
        ),
      )
      |> with_feedback(bootstrap_guard.info(status))
    scenario_state.DurableLocked(status, disabled_reason) ->
      Model(
        ..model,
        scenario: ScenarioState(
          ..model.scenario,
          concurrent: ConcurrentLocked(status, disabled_reason),
        ),
      )
      |> with_feedback(bootstrap_guard.warning(status))
  }
}

fn set_tombstone_state(
  model: Model,
  tombstone: TombstoneState,
  feedback: Feedback,
) -> Model {
  Model(
    ..model,
    scenario: ScenarioState(..model.scenario, tombstone: tombstone),
  )
  |> with_feedback(feedback)
}

fn refresh_live_shared(model: Model) -> Result(Model, String) {
  use shared <- result.try(resolve_live_shared(model))
  Ok(apply_shared_snapshots(model, shared, snapshots_of_shared(shared)))
}

fn resolve_live_shared(model: Model) -> Result(SharedPantry, String) {
  case model.doc {
    Some(doc) -> {
      let root = watershed.root_typed(doc)
      use grow_only <- result.try(require_live_channel(
        "grow_only",
        watershed.resolve_g_set_field(doc, root, doc_schema.grow_only()),
      ))
      use two_phase <- result.try(require_live_channel(
        "two_phase",
        watershed.resolve_two_p_set_field(doc, root, doc_schema.two_phase()),
      ))
      use observed <- result.try(require_live_channel(
        "observed",
        watershed.resolve_or_set_field(doc, root, doc_schema.observed()),
      ))
      Ok(SharedPantry(grow_only:, two_phase:, observed:))
    }

    None -> Error("document handle is unavailable")
  }
}

fn require_live_channel(
  label: String,
  channel_result: Result(Option(a), String),
) -> Result(a, String) {
  case channel_result {
    Ok(Some(channel)) -> Ok(channel)
    Ok(None) -> Error(label <> " handle is missing from the live pantry root")
    Error(reason) -> Error(label <> " handle refresh failed: " <> reason)
  }
}

fn shared_add(model: Model, item: String) -> #(Model, #(Bool, Bool)) {
  case model.shared {
    Some(shared) -> {
      let two_phase_was_present =
        watershed.two_p_set_contains(shared.two_phase, item)

      watershed.g_set_add(shared.grow_only, item)
      watershed.two_p_set_add(shared.two_phase, item)
      watershed.or_set_add(shared.observed, item)

      let two_phase_is_present =
        watershed.two_p_set_contains(shared.two_phase, item)

      #(
        refresh_snapshots(model),
        #(two_phase_was_present, two_phase_is_present),
      )
    }

    None -> #(model, #(False, False))
  }
}

fn shared_remove(model: Model, item: String) -> #(Model, #(Bool, Bool)) {
  case model.shared {
    Some(shared) -> {
      let two_phase_present =
        watershed.two_p_set_contains(shared.two_phase, item)
      let observed_present = watershed.or_set_contains(shared.observed, item)

      case two_phase_present {
        True -> watershed.two_p_set_remove(shared.two_phase, item)
        False -> Nil
      }
      case observed_present {
        True -> watershed.or_set_remove(shared.observed, item)
        False -> Nil
      }

      #(refresh_snapshots(model), #(two_phase_present, observed_present))
    }

    None -> #(model, #(False, False))
  }
}

fn apply_shared_add(model: Model, raw_item: String) -> Model {
  case shared_action_reason(model) {
    Some(reason) -> with_feedback(model, bootstrap_guard.info(reason))

    None ->
      case triptych_actions.normalize_item_input(raw_item) {
        Error(message) -> with_feedback(model, bootstrap_guard.warning(message))

        Ok(item) -> {
          let #(model, #(two_phase_was_present, two_phase_is_present)) =
            shared_add(model, item)

          Model(..model, draft: "")
          |> with_feedback(triptych_actions.add_feedback(
            item,
            two_phase_was_present,
            two_phase_is_present,
          ))
        }
      }
  }
}

fn apply_shared_remove(model: Model, item: String) -> Model {
  case shared_action_reason(model) {
    Some(reason) -> with_feedback(model, bootstrap_guard.info(reason))

    None ->
      case model.shared {
        None ->
          with_feedback(model, triptych_actions.not_ready_feedback("removing"))

        Some(shared) -> {
          let two_phase_present =
            watershed.two_p_set_contains(shared.two_phase, item)
          let observed_present =
            watershed.or_set_contains(shared.observed, item)
          let removable =
            triptych_actions.remove_action_available(
              two_phase_present,
              observed_present,
            )

          case removable {
            False ->
              with_feedback(
                model,
                triptych_actions.remove_feedback(
                  item,
                  two_phase_present,
                  observed_present,
                ),
              )

            True -> {
              let #(model, _) = shared_remove(model, item)

              model
              |> with_feedback(triptych_actions.remove_feedback(
                item,
                two_phase_present,
                observed_present,
              ))
            }
          }
        }
      }
  }
}

fn start_tombstone(model: Model) -> #(Model, Effect(Msg)) {
  case tombstone_button_reason(model) {
    Some(reason) -> #(
      with_feedback(model, bootstrap_guard.info(reason)),
      effect.none(),
    )

    None ->
      case refresh_live_shared(model) {
        Ok(model) ->
          case scenario_state.tombstone_preflight_outcome(model.snapshots) {
            scenario_state.TombstonePreflightRetryable ->
              schedule_tombstone_start(model)

            scenario_state.TombstonePreflightComplete(status) -> #(
              with_feedback(model, bootstrap_guard.info(status)),
              effect.none(),
            )
          }

        Error(reason) -> #(
          with_feedback(
            model,
            bootstrap_guard.warning(
              "Tombstone: could not re-read the live pantry state before starting. "
              <> reason,
            ),
          ),
          effect.none(),
        )
      }
  }
}

fn schedule_tombstone_start(model: Model) -> #(Model, Effect(Msg)) {
  let model =
    Model(
      ..model,
      scenario: ScenarioState(
        ..model.scenario,
        tombstone: TombstoneRunning(TombstoneAddStep),
      ),
    )
    |> with_feedback(bootstrap_guard.info(
      "Tombstone started: it will add \"milk\", remove it, then re-add it once.",
    ))

  #(
    model,
    watershed_lustre.after(
      tombstone_start_delay_ms,
      TombstoneStepDue(TombstoneAddStep),
    ),
  )
}

fn advance_tombstone(
  model: Model,
  step: TombstoneStep,
) -> #(Model, Effect(Msg)) {
  case model.scenario.tombstone, step {
    TombstoneRunning(TombstoneAddStep), TombstoneAddStep ->
      case refresh_live_shared(model) {
        Ok(model) ->
          case scenario_state.tombstone_preflight_outcome(model.snapshots) {
            scenario_state.TombstonePreflightComplete(status) -> #(
              set_tombstone_state(
                model,
                TombstoneComplete,
                bootstrap_guard.info(status),
              ),
              effect.none(),
            )

            scenario_state.TombstonePreflightRetryable -> {
              let #(model, #(_two_phase_was_present, two_phase_is_present)) =
                shared_add(model, scenario_state.tombstone_item)

              case
                scenario_state.tombstone_add_step_outcome(two_phase_is_present)
              {
                scenario_state.TombstoneAddStepComplete(status) -> #(
                  set_tombstone_state(
                    model,
                    TombstoneComplete,
                    bootstrap_guard.warning(status),
                  ),
                  effect.none(),
                )

                scenario_state.TombstoneAddStepContinue -> {
                  let model =
                    set_tombstone_state(
                      model,
                      TombstoneRunning(TombstoneRemoveStep),
                      bootstrap_guard.info(
                        "Tombstone 1/3: added \"milk\" to all three sets. Removing it next.",
                      ),
                    )

                  #(
                    model,
                    watershed_lustre.after(
                      tombstone_step_ms,
                      TombstoneStepDue(TombstoneRemoveStep),
                    ),
                  )
                }
              }
            }
          }

        Error(reason) -> #(
          set_tombstone_state(
            model,
            TombstoneAvailable,
            bootstrap_guard.warning(
              "Tombstone: could not re-read the live pantry state before the add step, so this tab stopped without mutating. "
              <> reason,
            ),
          ),
          effect.none(),
        )
      }

    TombstoneRunning(TombstoneRemoveStep), TombstoneRemoveStep -> {
      let #(model, _) = shared_remove(model, scenario_state.tombstone_item)
      let model =
        Model(
          ..model,
          scenario: ScenarioState(
            ..model.scenario,
            tombstone: TombstoneRunning(TombstoneReAddStep),
          ),
        )
        |> with_feedback(bootstrap_guard.info(
          "Tombstone 2/3: removed \"milk\" from TwoPSet and OrSet while GSet retained it. Re-adding next.",
        ))

      #(
        model,
        watershed_lustre.after(
          tombstone_step_ms,
          TombstoneStepDue(TombstoneReAddStep),
        ),
      )
    }

    TombstoneRunning(TombstoneReAddStep), TombstoneReAddStep -> {
      let #(model, #(two_phase_was_present, two_phase_is_present)) =
        shared_add(model, scenario_state.tombstone_item)
      let base =
        triptych_actions.add_feedback(
          scenario_state.tombstone_item,
          two_phase_was_present,
          two_phase_is_present,
        )
      let message =
        "Tombstone 3/3: "
        <> base.message
        <> " "
        <> scenario_state.tombstone_locked_message()
      let model =
        set_tombstone_state(
          model,
          TombstoneComplete,
          feedback_of_kind(base.kind, message),
        )

      #(model, effect.none())
    }

    _, _ -> #(model, effect.none())
  }
}

fn start_concurrent(model: Model) -> #(Model, Effect(Msg)) {
  case concurrent_button_reason(model) {
    Some(reason) -> #(
      with_feedback(model, bootstrap_guard.info(reason)),
      effect.none(),
    )

    None ->
      case refresh_live_shared(model) {
        Ok(model) ->
          case scenario_state.concurrent_preflight_outcome(model.snapshots) {
            scenario_state.PreflightRetryable -> prepare_concurrent_start(model)

            scenario_state.PreflightComplete(status, disabled_reason) -> #(
              set_concurrent_durable_state(
                model,
                scenario_state.DurableComplete(status, disabled_reason),
              ),
              effect.none(),
            )

            scenario_state.PreflightLocked(status, disabled_reason) -> #(
              set_concurrent_durable_state(
                model,
                scenario_state.DurableLocked(status, disabled_reason),
              ),
              effect.none(),
            )
          }

        Error(reason) -> #(
          with_feedback(
            model,
            bootstrap_guard.warning(
              "Concurrent add/remove: could not re-read the live pantry state before starting. "
              <> reason,
            ),
          ),
          effect.none(),
        )
      }
  }
}

fn prepare_concurrent_start(model: Model) -> #(Model, Effect(Msg)) {
  let run_id = next_run_id(model)
  let #(model, #(_two_phase_was_present, two_phase_is_present)) =
    shared_add(model, scenario_state.concurrent_item)

  case two_phase_is_present {
    False ->
      case refresh_live_shared(model) {
        Ok(model) ->
          case scenario_state.concurrent_durable_state(model.snapshots) {
            scenario_state.DurableRetryable -> #(
              with_feedback(
                model,
                bootstrap_guard.warning(
                  "Concurrent add/remove: TwoPSet stayed absent after seeding \"eggs\", so this tab refused to invite peers even though the live room still looked retryable.",
                ),
              ),
              effect.none(),
            )

            durable_state -> #(
              set_concurrent_durable_state(model, durable_state),
              effect.none(),
            )
          }

        Error(reason) -> #(
          with_feedback(
            model,
            bootstrap_guard.warning(
              "Concurrent add/remove: TwoPSet stayed absent after seeding \"eggs\", but this tab could not re-read the live pantry state. "
              <> reason,
            ),
          ),
          effect.none(),
        )
      }

    True -> {
      let model = remember_run_id(model, run_id)
      let model =
        Model(
          ..model,
          scenario: ScenarioState(
            ..model.scenario,
            concurrent: ConcurrentInitiator(
              run_id: run_id,
              phase: ConcurrentPreparing,
              selected_peer: None,
              peer_applied: False,
              attempts_remaining: concurrent_verify_attempts,
            ),
          ),
        )
        |> with_feedback(bootstrap_guard.info(
          "Concurrent add/remove: seeded \"eggs\" into all three sets and is waiting briefly before inviting a peer.",
        ))

      #(
        model,
        watershed_lustre.after(
          concurrent_prepare_ms,
          ConcurrentInvitePeers(run_id),
        ),
      )
    }
  }
}

fn invite_concurrent_peers(
  model: Model,
  run_id: String,
) -> #(Model, Effect(Msg)) {
  case model.scenario.concurrent {
    ConcurrentInitiator(
      current_run,
      ConcurrentPreparing,
      selected_peer,
      peer_applied,
      attempts_remaining,
    )
      if current_run == run_id
    ->
      case refresh_live_shared(model) {
        Ok(model) ->
          case scenario_state.concurrent_preflight_outcome(model.snapshots) {
            scenario_state.PreflightRetryable -> {
              let model =
                Model(
                  ..model,
                  scenario: ScenarioState(
                    ..model.scenario,
                    concurrent: ConcurrentInitiator(
                      run_id: run_id,
                      phase: ConcurrentAwaitingAck,
                      selected_peer: selected_peer,
                      peer_applied: peer_applied,
                      attempts_remaining: attempts_remaining,
                    ),
                  ),
                )
                |> with_feedback(bootstrap_guard.info(
                  "Concurrent add/remove: invited other ready tabs to acknowledge the \"eggs\" race.",
                ))

              #(
                model,
                effect.batch([
                  submit_scenario_ripple(
                    model,
                    scenario_protocol.Invitation(run_id),
                  ),
                  watershed_lustre.after(
                    concurrent_invite_timeout_ms,
                    ConcurrentInviteTimedOut(run_id),
                  ),
                ]),
              )
            }

            scenario_state.PreflightComplete(status, disabled_reason) -> #(
              set_concurrent_durable_state(
                model,
                scenario_state.DurableComplete(status, disabled_reason),
              ),
              effect.none(),
            )

            scenario_state.PreflightLocked(status, disabled_reason) -> #(
              set_concurrent_durable_state(
                model,
                scenario_state.DurableLocked(status, disabled_reason),
              ),
              effect.none(),
            )
          }

        Error(reason) -> {
          let message =
            "Concurrent add/remove: could not re-read the live pantry state before inviting peers, so this tab stopped without sending invitations. "
            <> reason
          let model =
            Model(
              ..model,
              scenario: ScenarioState(
                ..model.scenario,
                concurrent: ConcurrentIdle(Some(message)),
              ),
            )
            |> with_feedback(bootstrap_guard.warning(message))

          #(model, effect.none())
        }
      }

    _ -> #(model, effect.none())
  }
}

fn handle_scenario_ripple(
  model: Model,
  ripple: Ripple,
) -> #(Model, Effect(Msg)) {
  case
    scenario_protocol.decode(
      watershed.ripple_type(ripple),
      watershed.ripple_content(ripple),
      watershed.ripple_client_id(ripple),
    )
  {
    Some(inbound) ->
      case inbound.message {
        scenario_protocol.Invitation(_) -> handle_invitation(model, inbound)
        scenario_protocol.Acknowledgement(_) ->
          handle_acknowledgement(model, inbound)
        scenario_protocol.Go(_, _) -> handle_go(model, inbound)
        scenario_protocol.Status(_, _, _) -> handle_status(model, inbound)
      }

    None -> #(model, effect.none())
  }
}

fn handle_invitation(
  model: Model,
  inbound: scenario_protocol.Inbound,
) -> #(Model, Effect(Msg)) {
  case own_client_id(model) {
    Some(self_id) ->
      case inbound.message {
        scenario_protocol.Invitation(run_id) -> {
          let already_seen = has_seen_run_id(model, run_id)
          let remembered = remember_run_id(model, run_id)

          case
            scenario_protocol.should_acknowledge(
              self_id,
              controls_ready(remembered)
                && case remembered.scenario.concurrent {
                ConcurrentLocked(_, _) | ConcurrentComplete(_, _) -> False
                _ -> True
              },
              scenario_busy(remembered),
              already_seen,
              inbound,
            )
          {
            True -> {
              case refresh_live_shared(remembered) {
                Ok(remembered) ->
                  case
                    scenario_state.concurrent_preflight_outcome(
                      remembered.snapshots,
                    )
                  {
                    scenario_state.PreflightRetryable -> {
                      let message =
                        "Concurrent add/remove: acknowledged run "
                        <> run_id
                        <> " from tab "
                        <> inbound.from_peer
                        <> " and is waiting to see whether this tab is selected."
                      let model =
                        Model(
                          ..remembered,
                          scenario: ScenarioState(
                            ..remembered.scenario,
                            concurrent: ConcurrentPeer(
                              run_id: run_id,
                              initiator: inbound.from_peer,
                              phase: PeerAwaitingGo,
                              attempts_remaining: concurrent_verify_attempts,
                              note: Some(message),
                            ),
                          ),
                        )
                        |> with_feedback(bootstrap_guard.info(message))

                      #(
                        model,
                        effect.batch([
                          submit_scenario_ripple(
                            model,
                            scenario_protocol.Acknowledgement(run_id),
                          ),
                          watershed_lustre.after(
                            concurrent_peer_go_timeout_ms,
                            ConcurrentPeerGoTimedOut(run_id),
                          ),
                        ]),
                      )
                    }

                    scenario_state.PreflightComplete(status, disabled_reason) -> #(
                      set_concurrent_durable_state(
                        remembered,
                        scenario_state.DurableComplete(status, disabled_reason),
                      ),
                      effect.none(),
                    )

                    scenario_state.PreflightLocked(status, disabled_reason) -> #(
                      set_concurrent_durable_state(
                        remembered,
                        scenario_state.DurableLocked(status, disabled_reason),
                      ),
                      effect.none(),
                    )
                  }

                Error(reason) -> #(
                  with_feedback(
                    remembered,
                    bootstrap_guard.warning(
                      "Concurrent add/remove: could not re-read the live pantry state before acknowledging run "
                      <> run_id
                      <> ". "
                      <> reason,
                    ),
                  ),
                  effect.none(),
                )
              }
            }

            False -> #(remembered, effect.none())
          }
        }

        _ -> #(model, effect.none())
      }

    None -> #(model, effect.none())
  }
}

fn handle_acknowledgement(
  model: Model,
  inbound: scenario_protocol.Inbound,
) -> #(Model, Effect(Msg)) {
  case own_client_id(model), model.scenario.concurrent {
    Some(self_id),
      ConcurrentInitiator(
        run_id,
        ConcurrentAwaitingAck,
        selected_peer,
        peer_applied,
        attempts_remaining,
      )
    ->
      case
        scenario_protocol.select_first_ack(
          self_id,
          run_id,
          selected_peer,
          inbound,
        )
      {
        Some(peer) -> {
          let model =
            Model(
              ..model,
              scenario: ScenarioState(
                ..model.scenario,
                concurrent: ConcurrentInitiator(
                  run_id: run_id,
                  phase: ConcurrentRemoving,
                  selected_peer: Some(peer),
                  peer_applied: peer_applied,
                  attempts_remaining: attempts_remaining,
                ),
              ),
            )
            |> with_feedback(bootstrap_guard.info(
              "Concurrent add/remove: selected tab "
              <> peer
              <> " and pushed go before deferring the initiator remove to the next timer tick.",
            ))

          // Push the coordination ripple first, then defer the initiator's
          // remove. The peer's ripple callback runs before the later remove
          // frame is processed, so neither authored operation observes the
          // other even though the transport remains best-effort.
          #(
            model,
            effect.batch([
              submit_scenario_ripple(model, scenario_protocol.Go(run_id, peer)),
              watershed_lustre.after(0, ConcurrentInitiatorRemove(run_id, peer)),
            ]),
          )
        }

        None -> #(model, effect.none())
      }

    _, _ -> #(model, effect.none())
  }
}

fn handle_go(
  model: Model,
  inbound: scenario_protocol.Inbound,
) -> #(Model, Effect(Msg)) {
  case own_client_id(model), model.scenario.concurrent {
    Some(self_id),
      ConcurrentPeer(run_id, initiator, phase, attempts_remaining, _note)
    -> {
      let already_started = case phase {
        PeerVerifying -> True
        _ -> False
      }

      case
        scenario_protocol.classify_go(
          self_id,
          run_id,
          initiator,
          already_started,
          inbound,
        )
      {
        scenario_protocol.ApplyGo -> {
          let #(model, _) = shared_add(model, scenario_state.concurrent_item)
          let model =
            Model(
              ..model,
              scenario: ScenarioState(
                ..model.scenario,
                concurrent: ConcurrentPeer(
                  run_id: run_id,
                  initiator: initiator,
                  phase: PeerVerifying,
                  attempts_remaining: attempts_remaining,
                  note: Some(
                    "This tab handled go while still seeing the pre-remove state, then authored the concurrent add for \"eggs\" immediately.",
                  ),
                ),
              ),
            )
            |> with_feedback(bootstrap_guard.info(
              "Concurrent add/remove: handled go from tab "
              <> initiator
              <> " and immediately re-added \"eggs\" before the later remove frame arrived. Verifying "
              <> scenario_state.expected_concurrent_summary()
              <> ".",
            ))

          #(
            model,
            effect.batch([
              submit_scenario_ripple(
                model,
                scenario_protocol.Status(
                  run_id: run_id,
                  target_peer: initiator,
                  status: scenario_protocol.PeerAppliedAdd,
                ),
              ),
              schedule_concurrent_verification(run_id),
            ]),
          )
        }

        scenario_protocol.Ignore -> #(model, effect.none())
      }
    }

    _, _ -> #(model, effect.none())
  }
}

fn handle_status(
  model: Model,
  inbound: scenario_protocol.Inbound,
) -> #(Model, Effect(Msg)) {
  case own_client_id(model), model.scenario.concurrent {
    Some(self_id),
      ConcurrentInitiator(
        run_id,
        phase,
        selected_peer,
        _peer_applied,
        attempts_remaining,
      )
    -> {
      let accepted_status = case selected_peer {
        Some(peer) ->
          scenario_protocol.should_accept_status(self_id, run_id, peer, inbound)
        None -> None
      }

      case accepted_status {
        Some(scenario_protocol.PeerAppliedAdd) -> {
          let model =
            Model(
              ..model,
              scenario: ScenarioState(
                ..model.scenario,
                concurrent: ConcurrentInitiator(
                  run_id: run_id,
                  phase: phase,
                  selected_peer: selected_peer,
                  peer_applied: True,
                  attempts_remaining: attempts_remaining,
                ),
              ),
            )
            |> with_feedback(bootstrap_guard.info(
              "Concurrent add/remove: selected peer "
              <> inbound.from_peer
              <> " reported that it authored the concurrent add for \"eggs\".",
            ))

          #(model, effect.none())
        }

        Some(_) -> #(model, effect.none())
        None -> #(model, effect.none())
      }
    }

    Some(self_id),
      ConcurrentPeer(run_id, initiator, phase, attempts_remaining, note)
    ->
      case
        scenario_protocol.should_accept_status(
          self_id,
          run_id,
          initiator,
          inbound,
        )
      {
        Some(status) ->
          case
            scenario_state.observe_peer_status(
              participating: case phase {
                PeerVerifying -> True
                PeerAwaitingGo -> False
              },
              status: status,
            )
          {
            scenario_state.IgnoreWhileAwaitingGo -> #(model, effect.none())

            scenario_state.KeepVerifying(message) -> {
              let note = case note {
                Some(extra) -> Some(extra <> " " <> message)
                None -> Some(message)
              }
              let model =
                Model(
                  ..model,
                  scenario: ScenarioState(
                    ..model.scenario,
                    concurrent: ConcurrentPeer(
                      run_id: run_id,
                      initiator: initiator,
                      phase: PeerVerifying,
                      attempts_remaining: attempts_remaining,
                      note: note,
                    ),
                  ),
                )
                |> with_feedback(bootstrap_guard.info(message))

              #(model, effect.none())
            }

            scenario_state.LockRoom(message) -> {
              let feedback = case note {
                Some(extra) -> bootstrap_guard.warning(extra <> " " <> message)
                None -> bootstrap_guard.warning(message)
              }
              let model =
                set_concurrent_timeout_state(
                  model,
                  scenario_state.concurrent_timeout_state(
                    remove_phase_began: True,
                    status: message,
                  ),
                  feedback,
                )

              #(model, effect.none())
            }
          }

        None -> #(model, effect.none())
      }

    _, _ -> #(model, effect.none())
  }
}

fn initiator_remove(
  model: Model,
  run_id: String,
  peer: String,
) -> #(Model, Effect(Msg)) {
  case model.scenario.concurrent {
    ConcurrentInitiator(
      current_run,
      ConcurrentRemoving,
      Some(selected_peer),
      peer_applied,
      attempts_remaining,
    )
      if current_run == run_id && selected_peer == peer
    -> {
      let #(model, _) = shared_remove(model, scenario_state.concurrent_item)
      let model =
        Model(
          ..model,
          scenario: ScenarioState(
            ..model.scenario,
            concurrent: ConcurrentInitiator(
              run_id: run_id,
              phase: ConcurrentVerifying,
              selected_peer: Some(peer),
              peer_applied: peer_applied,
              attempts_remaining: attempts_remaining,
            ),
          ),
        )
        |> with_feedback(bootstrap_guard.info(
          "Concurrent add/remove: the initiator removed \"eggs\" after broadcasting go. Verifying "
          <> scenario_state.expected_concurrent_summary()
          <> ".",
        ))

      #(model, schedule_concurrent_verification(run_id))
    }

    _ -> #(model, effect.none())
  }
}

fn verify_concurrent(model: Model, run_id: String) -> #(Model, Effect(Msg)) {
  case model.scenario.concurrent {
    ConcurrentInitiator(
      current_run,
      ConcurrentVerifying,
      selected_peer,
      peer_applied,
      attempts_remaining,
    )
      if current_run == run_id
    ->
      case
        scenario_state.advance_verification(model.snapshots, attempts_remaining)
      {
        scenario_state.Verified -> {
          let message =
            "Concurrent add/remove verified "
            <> scenario_state.expected_concurrent_summary()
            <> "; saw "
            <> scenario_state.concurrent_summary(model.snapshots)
            <> "."
          let model =
            Model(
              ..model,
              scenario: ScenarioState(
                ..model.scenario,
                concurrent: ConcurrentComplete(
                  message,
                  scenario_state.concurrent_locked_message(),
                ),
              ),
            )
            |> with_feedback(bootstrap_guard.info(message))
          let notify = case selected_peer {
            Some(peer) ->
              submit_scenario_ripple(
                model,
                scenario_protocol.Status(
                  run_id: run_id,
                  target_peer: peer,
                  status: scenario_protocol.VerifiedExpectedOutcome,
                ),
              )
            None -> effect.none()
          }

          #(model, notify)
        }

        scenario_state.Retry(remaining) -> {
          let model =
            Model(
              ..model,
              scenario: ScenarioState(
                ..model.scenario,
                concurrent: ConcurrentInitiator(
                  run_id: run_id,
                  phase: ConcurrentVerifying,
                  selected_peer: selected_peer,
                  peer_applied: peer_applied,
                  attempts_remaining: remaining,
                ),
              ),
            )

          #(model, schedule_concurrent_verification(run_id))
        }

        scenario_state.TimedOut -> {
          let message =
            "Concurrent add/remove timed out while verifying "
            <> scenario_state.expected_concurrent_summary()
            <> "; saw "
            <> scenario_state.concurrent_summary(model.snapshots)
            <> ". "
            <> scenario_state.concurrent_locked_message()
          let model =
            set_concurrent_timeout_state(
              model,
              scenario_state.concurrent_timeout_state(
                remove_phase_began: True,
                status: message,
              ),
              bootstrap_guard.warning(message),
            )
          let notify = case selected_peer {
            Some(peer) ->
              submit_scenario_ripple(
                model,
                scenario_protocol.Status(
                  run_id: run_id,
                  target_peer: peer,
                  status: scenario_protocol.VerificationTimedOut,
                ),
              )
            None -> effect.none()
          }

          #(model, notify)
        }
      }

    ConcurrentPeer(
      current_run,
      initiator,
      PeerVerifying,
      attempts_remaining,
      note,
    )
      if current_run == run_id
    ->
      case
        scenario_state.advance_verification(model.snapshots, attempts_remaining)
      {
        scenario_state.Verified -> {
          let message =
            "Concurrent add/remove reached "
            <> scenario_state.expected_concurrent_summary()
            <> " on this tab; saw "
            <> scenario_state.concurrent_summary(model.snapshots)
            <> "."
          let feedback = case note {
            Some(extra) -> message <> " " <> extra
            None -> message
          }
          let model =
            Model(
              ..model,
              scenario: ScenarioState(
                ..model.scenario,
                concurrent: ConcurrentComplete(
                  message,
                  scenario_state.concurrent_locked_message(),
                ),
              ),
            )
            |> with_feedback(bootstrap_guard.info(feedback))

          #(
            model,
            submit_scenario_ripple(
              model,
              scenario_protocol.Status(
                run_id: run_id,
                target_peer: initiator,
                status: scenario_protocol.VerifiedExpectedOutcome,
              ),
            ),
          )
        }

        scenario_state.Retry(remaining) -> {
          let model =
            Model(
              ..model,
              scenario: ScenarioState(
                ..model.scenario,
                concurrent: ConcurrentPeer(
                  run_id: run_id,
                  initiator: initiator,
                  phase: PeerVerifying,
                  attempts_remaining: remaining,
                  note: note,
                ),
              ),
            )

          #(model, schedule_concurrent_verification(run_id))
        }

        scenario_state.TimedOut -> {
          let message =
            "Concurrent add/remove timed out on this tab while verifying "
            <> scenario_state.expected_concurrent_summary()
            <> "; saw "
            <> scenario_state.concurrent_summary(model.snapshots)
            <> ". "
            <> scenario_state.concurrent_locked_message()
          let feedback = case note {
            Some(extra) -> message <> " " <> extra
            None -> message
          }
          let model =
            set_concurrent_timeout_state(
              model,
              scenario_state.concurrent_timeout_state(
                remove_phase_began: True,
                status: message,
              ),
              bootstrap_guard.warning(feedback),
            )

          #(
            model,
            submit_scenario_ripple(
              model,
              scenario_protocol.Status(
                run_id: run_id,
                target_peer: initiator,
                status: scenario_protocol.VerificationTimedOut,
              ),
            ),
          )
        }
      }

    _ -> #(model, effect.none())
  }
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    GotHandle(doc) -> {
      let model =
        Model(
          ..model,
          doc: Some(doc),
          feedback: Some(bootstrap_guard.info("document handle acquired")),
        )
      maybe_bootstrap(model)
    }

    Connected(Ok(_)) -> {
      let model =
        Model(
          ..model,
          ready_callback_seen: True,
          feedback: Some(bootstrap_guard.info("ready callback completed")),
        )
      maybe_bootstrap(model)
    }

    Connected(Error(reason)) -> #(
      fail(model, "connection failed: " <> reason),
      effect.none(),
    )

    EnsuredGrowOnly(Ok(set)) ->
      assemble(
        Model(
          ..model,
          pending: PendingPantry(..model.pending, grow_only: Some(set)),
          feedback: bootstrap_guard.success_feedback(
            model.error,
            model.feedback,
            "grow_only handle ensured",
          ),
        ),
      )
    EnsuredGrowOnly(Error(reason)) -> #(
      fail(model, "grow_only ensure failed: " <> reason),
      effect.none(),
    )

    EnsuredTwoPhase(Ok(set)) ->
      assemble(
        Model(
          ..model,
          pending: PendingPantry(..model.pending, two_phase: Some(set)),
          feedback: bootstrap_guard.success_feedback(
            model.error,
            model.feedback,
            "two_phase handle ensured",
          ),
        ),
      )
    EnsuredTwoPhase(Error(reason)) -> #(
      fail(model, "two_phase ensure failed: " <> reason),
      effect.none(),
    )

    EnsuredObserved(Ok(set)) ->
      assemble(
        Model(
          ..model,
          pending: PendingPantry(..model.pending, observed: Some(set)),
          feedback: bootstrap_guard.success_feedback(
            model.error,
            model.feedback,
            "observed handle ensured",
          ),
        ),
      )
    EnsuredObserved(Error(reason)) -> #(
      fail(model, "observed ensure failed: " <> reason),
      effect.none(),
    )

    DraftChanged(text) -> #(Model(..model, draft: text), effect.none())

    AddSubmitted -> #(apply_shared_add(model, model.draft), effect.none())

    RemoveRequested(item) -> #(apply_shared_remove(model, item), effect.none())

    ScenarioRequested(TombstoneScenario) -> start_tombstone(model)

    ScenarioRequested(ConcurrentAddRemoveScenario) -> start_concurrent(model)

    ScenarioRippleReceived(ripple) -> handle_scenario_ripple(model, ripple)

    TombstoneStepDue(step) -> advance_tombstone(model, step)

    ConcurrentInvitePeers(run_id) -> invite_concurrent_peers(model, run_id)

    ConcurrentInviteTimedOut(run_id) ->
      case model.scenario.concurrent {
        ConcurrentInitiator(current_run, ConcurrentAwaitingAck, None, _, _)
          if current_run == run_id
        ->
          case refresh_live_shared(model) {
            Ok(model) ->
              case scenario_state.concurrent_durable_state(model.snapshots) {
                scenario_state.DurableRetryable -> {
                  let message = scenario_state.invitation_timeout_message()
                  let model =
                    set_concurrent_timeout_state(
                      model,
                      scenario_state.concurrent_timeout_state(
                        remove_phase_began: False,
                        status: message,
                      ),
                      bootstrap_guard.warning(message),
                    )

                  #(model, effect.none())
                }

                durable_state -> #(
                  set_concurrent_durable_state(model, durable_state),
                  effect.none(),
                )
              }

            Error(reason) -> {
              let message =
                "Concurrent add/remove: could not re-read the live pantry state when run "
                <> run_id
                <> " timed out waiting for acknowledgements, so this tab stopped without claiming the room is retryable. "
                <> reason
              let model =
                Model(
                  ..model,
                  scenario: ScenarioState(
                    ..model.scenario,
                    concurrent: ConcurrentIdle(Some(message)),
                  ),
                )
                |> with_feedback(bootstrap_guard.warning(message))

              #(model, effect.none())
            }
          }

        _ -> #(model, effect.none())
      }

    ConcurrentPeerGoTimedOut(run_id) ->
      case model.scenario.concurrent {
        ConcurrentPeer(current_run, _initiator, PeerAwaitingGo, _, _)
          if current_run == run_id
        ->
          case refresh_live_shared(model) {
            Ok(model) ->
              case
                scenario_state.concurrent_peer_go_timeout_outcome(
                  run_id,
                  model.snapshots,
                )
              {
                scenario_state.PeerGoRetryable(status) -> {
                  let model =
                    set_concurrent_timeout_state(
                      model,
                      scenario_state.concurrent_timeout_state(
                        remove_phase_began: False,
                        status: status,
                      ),
                      bootstrap_guard.warning(status),
                    )

                  #(model, effect.none())
                }

                scenario_state.PeerGoComplete(status, disabled_reason) -> #(
                  set_concurrent_durable_state(
                    model,
                    scenario_state.DurableComplete(status, disabled_reason),
                  ),
                  effect.none(),
                )

                scenario_state.PeerGoLocked(status, disabled_reason) -> #(
                  set_concurrent_durable_state(
                    model,
                    scenario_state.DurableLocked(status, disabled_reason),
                  ),
                  effect.none(),
                )
              }

            Error(reason) -> {
              let message =
                "Concurrent add/remove: could not re-read the live pantry state after go timed out for run "
                <> run_id
                <> ", so this tab left the waiting state without claiming the room is retryable. "
                <> reason
              let model =
                Model(
                  ..model,
                  scenario: ScenarioState(
                    ..model.scenario,
                    concurrent: ConcurrentIdle(Some(message)),
                  ),
                )
                |> with_feedback(bootstrap_guard.warning(message))

              #(model, effect.none())
            }
          }

        _ -> #(model, effect.none())
      }

    ConcurrentInitiatorRemove(run_id, peer) ->
      initiator_remove(model, run_id, peer)

    VerifyConcurrent(run_id) -> verify_concurrent(model, run_id)

    GrowOnlyChanged(_) -> schedule_shared_refresh(model)

    TwoPhaseChanged(_) -> schedule_shared_refresh(model)

    ObservedChanged(_) -> schedule_shared_refresh(model)

    FlushSharedRefresh(generation) -> #(
      flush_shared_refresh(model, generation),
      effect.none(),
    )
  }
}

fn view(model: Model) -> Element(Msg) {
  html.main([attribute.class("wrap")], [
    html.h1([], [html.text("watershed · grocery triptych")]),
    html.p([attribute.class("status")], [
      html.text(
        "document "
        <> model.document_name
        <> " · "
        <> readiness_text(model.readiness),
      ),
    ]),
    flash_view(model.feedback),
    connection_view(model),
    controls_view(model),
    shared_remove_view(model),
    comparison_view(model),
  ])
}

fn connection_view(model: Model) -> Element(Msg) {
  html.section([attribute.class("panel")], [
    html.h2([], [html.text("Connection and bootstrap")]),
    html.p([attribute.class("hint")], [
      html.text(
        "Shared actions stay gated until the document handle, ready callback, "
        <> "and all three pantry channels are available.",
      ),
    ]),
    fact("document handle", yes_no(option.is_some(model.doc))),
    fact("ready callback", yes_no(model.ready_callback_seen)),
    fact("handles requested", yes_no(model.bootstrap_requested)),
    fact("shared handles", yes_no(option.is_some(model.shared))),
    fact("scenario status", scenario_text(model.scenario)),
    case model.error {
      Some(reason) ->
        html.p(
          [
            attribute.class("error"),
            attribute.attribute("role", "alert"),
            attribute.attribute("aria-live", "assertive"),
          ],
          [html.text(reason)],
        )

      None -> html.text("")
    },
  ])
}

fn controls_view(model: Model) -> Element(Msg) {
  let manual_reason = shared_action_reason(model)
  let shared_enabled = case manual_reason {
    None -> True
    Some(_) -> False
  }
  let add_help_id = "add-item-help"
  let tombstone_reason = tombstone_button_reason(model)
  let concurrent_reason = concurrent_button_reason(model)
  let tombstone_enabled = case tombstone_reason {
    None -> True
    Some(_) -> False
  }
  let concurrent_enabled = case concurrent_reason {
    None -> True
    Some(_) -> False
  }

  html.section([attribute.class("panel")], [
    html.h2([], [html.text("Shared controls")]),
    html.p([attribute.class("hint")], [
      html.text(
        "One form drives all three sets so any divergence comes from the set "
        <> "rules rather than from different controls.",
      ),
    ]),
    html.form(
      [attribute.class("compose"), event.on_submit(fn(_) { AddSubmitted })],
      [
        html.label([attribute.class("field")], [
          html.span([attribute.class("field-label")], [html.text("Item")]),
          html.input([
            attribute.name("item"),
            attribute.placeholder("milk"),
            attribute.value(model.draft),
            attribute.aria_label("Grocery item name"),
            attribute.attribute("aria-describedby", add_help_id),
            attribute.disabled(!shared_enabled),
            event.on_input(DraftChanged),
          ]),
        ]),
        html.button(
          [
            attribute.class("primary"),
            attribute.type_("submit"),
            attribute.disabled(!shared_enabled),
            attribute.aria_label("Add grocery item to all three sets"),
            attribute.attribute("aria-describedby", add_help_id),
          ],
          [html.text("Add to all three")],
        ),
      ],
    ),
    html.p(
      [
        attribute.class("hint"),
        attribute.attribute("id", add_help_id),
        attribute.attribute("aria-live", "polite"),
      ],
      [
        html.text(case manual_reason {
          Some(reason) -> reason
          None ->
            "Press Enter or Add to submit. Empty items are rejected with a warning."
        }),
      ],
    ),
    html.div([attribute.class("scenario-row")], [
      html.span([attribute.class("field-label")], [
        html.text("Preset scenarios"),
      ]),
      html.div([attribute.class("scenario-buttons")], [
        html.button(
          [
            attribute.type_("button"),
            attribute.disabled(!tombstone_enabled),
            event.on_click(ScenarioRequested(TombstoneScenario)),
            attribute.aria_label("Run the tombstone preset"),
          ],
          [html.text("Tombstone")],
        ),
        html.button(
          [
            attribute.type_("button"),
            attribute.disabled(!concurrent_enabled),
            event.on_click(ScenarioRequested(ConcurrentAddRemoveScenario)),
            attribute.aria_label("Run the concurrent add remove preset"),
          ],
          [html.text("Concurrent add/remove")],
        ),
      ]),
    ]),
    html.p([attribute.class("hint")], [
      html.text(
        "Tombstone uses fixed item \"milk\" and becomes one-shot for the room. Concurrent add/remove uses fixed item \"eggs\" and ripples only for coordination — completion still comes from the settled snapshots.",
      ),
    ]),
    html.div([attribute.class("scenario-statuses")], [
      scenario_status_view(
        "Tombstone",
        tombstone_status_text(model.scenario.tombstone),
        tombstone_reason,
      ),
      scenario_status_view(
        "Concurrent add/remove",
        concurrent_status_text(model.scenario.concurrent),
        concurrent_reason,
      ),
    ]),
  ])
}

fn shared_remove_view(model: Model) -> Element(Msg) {
  let manual_reason = shared_action_reason(model)
  let shared_enabled = case manual_reason {
    None -> True
    Some(_) -> False
  }

  html.section([attribute.class("panel")], [
    html.h2([], [html.text("Shared remove actions")]),
    html.p([attribute.class("hint")], [
      html.text(case manual_reason {
        Some(reason) -> reason
        None ->
          "Each remove stays enabled only while TwoPSet or OrSet still contains the item. When both copies remain, the shared action removes both; when only one remains, the label names that panel honestly. GSet keeps the item because grow-only removal is not expressible."
      }),
    ]),
    case model.rows {
      [] ->
        html.p([attribute.class("hint")], [
          html.text("Add an item to start the comparison."),
        ])

      rows ->
        html.ul(
          [attribute.class("shared-actions")],
          list.map(rows, shared_row_view(_, shared_enabled, manual_reason)),
        )
    },
  ])
}

fn shared_row_view(
  row: Row,
  shared_enabled: Bool,
  disabled_reason: Option(String),
) -> Element(Msg) {
  let removable = pantry_snapshot.row_has_removable_copy(row)
  let button_disabled = !shared_enabled || !removable
  let hint_text = case disabled_reason {
    Some(reason) -> Some(reason)
    None ->
      case removable {
        True -> None
        False ->
          Some("Already absent from TwoPSet and OrSet. GSet still retains it.")
      }
  }

  html.li([attribute.class("shared-row")], [
    html.div([attribute.class("row-main")], [
      html.span([attribute.class("item")], [html.text(row.item)]),
      divergence_marker(row.diverges),
    ]),
    html.div([attribute.class("remove-action")], [
      html.button(
        [
          attribute.class("danger"),
          attribute.type_("button"),
          attribute.disabled(button_disabled),
          event.on_click(RemoveRequested(row.item)),
          attribute.aria_label(triptych_actions.remove_action_label(
            row.item,
            row.two_phase,
            row.observed,
          )),
        ],
        [
          html.text(triptych_actions.remove_action_text(
            row.two_phase,
            row.observed,
          )),
        ],
      ),
      case hint_text {
        Some(reason) ->
          html.span([attribute.class("hint")], [html.text(reason)])
        None -> html.text("")
      },
    ]),
  ])
}

fn scenario_status_view(
  label: String,
  status: String,
  disabled_reason: Option(String),
) -> Element(msg) {
  html.div([attribute.class("scenario-status")], [
    html.p([attribute.class("hint")], [html.text(label <> ": " <> status)]),
    case disabled_reason {
      Some(reason) ->
        html.p([attribute.class("hint")], [
          html.text("Disabled reason: " <> reason),
        ])
      None -> html.text("")
    },
  ])
}

fn tombstone_status_text(state: TombstoneState) -> String {
  case state {
    TombstoneAvailable -> "ready to run once with fixed item \"milk\"."
    TombstoneRunning(TombstoneAddStep) ->
      "running step 1/3: adding \"milk\" to all three sets."
    TombstoneRunning(TombstoneRemoveStep) ->
      "running step 2/3: removing \"milk\" from TwoPSet and OrSet."
    TombstoneRunning(TombstoneReAddStep) ->
      "running step 3/3: re-adding \"milk\" so TwoPSet stays absent while OrSet restores it."
    TombstoneComplete -> scenario_state.tombstone_locked_message()
  }
}

fn concurrent_status_text(state: ConcurrentState) -> String {
  case state {
    ConcurrentIdle(Some(status)) -> status
    ConcurrentIdle(None) ->
      "idle; it seeds \"eggs\" first, then coordinates a two-tab race over ripples."
    ConcurrentLocked(status, _) -> status
    ConcurrentComplete(status, _) -> status

    ConcurrentInitiator(run_id, ConcurrentPreparing, _, _, _) ->
      "run "
      <> run_id
      <> ": seeded \"eggs\" and is waiting briefly before inviting peers."

    ConcurrentInitiator(run_id, ConcurrentAwaitingAck, _, _, _) ->
      "run " <> run_id <> ": waiting for the first ready peer acknowledgement."

    ConcurrentInitiator(run_id, ConcurrentRemoving, selected_peer, _, _) ->
      "run "
      <> run_id
      <> ": selected "
      <> selected_peer_text(selected_peer)
      <> ", sent go, and queued the initiator remove on a zero-delay timer."

    ConcurrentInitiator(
      run_id,
      ConcurrentVerifying,
      selected_peer,
      peer_applied,
      _,
    ) ->
      "run "
      <> run_id
      <> ": verifying "
      <> scenario_state.expected_concurrent_summary()
      <> " after racing against "
      <> selected_peer_text(selected_peer)
      <> case peer_applied {
        True -> "; the peer already reported its add."
        False -> "; peer status is optional and may still be in flight."
      }

    ConcurrentPeer(run_id, initiator, PeerAwaitingGo, _, note) ->
      case note {
        Some(note) -> note
        None ->
          "run "
          <> run_id
          <> ": acknowledged initiator "
          <> initiator
          <> " and is waiting to learn whether this tab was selected."
      }

    ConcurrentPeer(run_id, initiator, PeerVerifying, _, note) ->
      case note {
        Some(note) -> note
        None ->
          "run "
          <> run_id
          <> ": authored the concurrent add with initiator "
          <> initiator
          <> " and is verifying "
          <> scenario_state.expected_concurrent_summary()
          <> "."
      }
  }
}

fn selected_peer_text(selected_peer: Option(String)) -> String {
  case selected_peer {
    Some(peer) -> "peer " <> peer
    None -> "the selected peer"
  }
}

fn comparison_view(model: Model) -> Element(Msg) {
  html.section([attribute.class("panel")], [
    html.h2([], [html.text("Triptych comparison")]),
    html.p([attribute.class("hint")], [
      html.text(
        "Every panel renders the same union rows in the same order; the "
        <> "warning marker and the panel diff count both track the same "
        <> "divergent rows.",
      ),
    ]),
    html.div([attribute.class("pantry")], [
      panel_view(GrowOnlyPanel, model),
      panel_view(TwoPhasePanel, model),
      panel_view(ObservedPanel, model),
    ]),
  ])
}

fn panel_view(panel: Panel, model: Model) -> Element(Msg) {
  html.article([attribute.class("card")], [
    html.div([attribute.class("card-header")], [
      html.h2([], [html.text(panel_title(panel))]),
      html.p([], [html.text(panel_rule(panel))]),
      html.p([attribute.class("hint")], [
        html.text(
          panel_count_text(panel_present_count(panel, model.snapshots))
          <> " · "
          <> divergence_count_text(panel_diff_count(panel, model.diffs)),
        ),
      ]),
      panel_note(panel),
    ]),
    panel_rows_view(panel, model.rows),
  ])
}

fn panel_rows_view(panel: Panel, rows: List(Row)) -> Element(Msg) {
  case rows {
    [] -> html.p([attribute.class("hint")], [html.text("No rows yet.")])
    _ ->
      html.ul(
        [attribute.class("panel-rows")],
        list.map(rows, panel_row_view(panel, _)),
      )
  }
}

fn panel_row_view(panel: Panel, row: Row) -> Element(Msg) {
  html.li([attribute.class(panel_row_class(panel, row))], [
    html.div([attribute.class("row-main")], [
      html.span([attribute.class("item")], [html.text(row.item)]),
      divergence_marker(row.diverges),
    ]),
    presence_badge(panel_present(panel, row)),
  ])
}

fn panel_note(panel: Panel) -> Element(Msg) {
  case panel {
    GrowOnlyPanel ->
      html.div([attribute.class("disabled-note")], [
        html.button([attribute.type_("button"), attribute.disabled(True)], [
          html.text("Remove unavailable"),
        ]),
        html.span([attribute.class("hint")], [
          html.text("Grow-only set: removal is not expressible."),
        ]),
      ])

    _ -> html.text("")
  }
}

fn divergence_marker(diverges: Bool) -> Element(msg) {
  case diverges {
    True -> html.span([attribute.class("marker")], [html.text("⚠ diverges")])
    False -> html.text("")
  }
}

fn presence_badge(present: Bool) -> Element(msg) {
  let marker = case present {
    True -> "present"
    False -> "absent"
  }

  html.span([attribute.class("pill " <> marker)], [html.text(marker)])
}

fn panel_title(panel: Panel) -> String {
  case panel {
    GrowOnlyPanel -> "GSet"
    TwoPhasePanel -> "TwoPSet"
    ObservedPanel -> "OrSet"
  }
}

fn panel_rule(panel: Panel) -> String {
  case panel {
    GrowOnlyPanel -> "Grow-only: add-only; removal is not expressible."
    TwoPhasePanel ->
      "Two-phase: removes tombstone forever, so a re-add can be ignored."
    ObservedPanel ->
      "Observed-remove: remove what you saw; re-adding the item works."
  }
}

fn panel_present_count(panel: Panel, snapshots: Snapshots) -> Int {
  case panel {
    GrowOnlyPanel -> list.length(snapshots.grow_only)
    TwoPhasePanel -> list.length(snapshots.two_phase)
    ObservedPanel -> list.length(snapshots.observed)
  }
}

fn panel_diff_count(panel: Panel, diffs: DiffCounts) -> Int {
  case panel {
    GrowOnlyPanel -> diffs.grow_only
    TwoPhasePanel -> diffs.two_phase
    ObservedPanel -> diffs.observed
  }
}

fn panel_present(panel: Panel, row: Row) -> Bool {
  case panel {
    GrowOnlyPanel -> row.grow_only
    TwoPhasePanel -> row.two_phase
    ObservedPanel -> row.observed
  }
}

fn panel_row_class(panel: Panel, row: Row) -> String {
  case row.diverges, panel_is_outlier(panel, row) {
    True, True -> "panel-row diverges outlier"
    True, False -> "panel-row diverges"
    False, _ -> "panel-row"
  }
}

fn panel_is_outlier(panel: Panel, row: Row) -> Bool {
  case panel {
    GrowOnlyPanel -> pantry_snapshot.grow_only_is_outlier(row)
    TwoPhasePanel -> pantry_snapshot.two_phase_is_outlier(row)
    ObservedPanel -> pantry_snapshot.observed_is_outlier(row)
  }
}

fn panel_count_text(count: Int) -> String {
  int.to_string(count)
  <> case count == 1 {
    True -> " item present"
    False -> " items present"
  }
}

fn divergence_count_text(count: Int) -> String {
  int.to_string(count)
  <> case count == 1 {
    True -> " divergent row"
    False -> " divergent rows"
  }
}

fn fact(label: String, detail: String) -> Element(msg) {
  html.p([attribute.class("hint")], [html.text(label <> ": " <> detail)])
}

fn flash_view(feedback: Option(Feedback)) -> Element(msg) {
  case feedback {
    None -> html.text("")

    Some(feedback) ->
      html.p(
        [
          attribute.class("flash " <> feedback_class(feedback.kind)),
          attribute.attribute("role", feedback_role(feedback.kind)),
          attribute.attribute("aria-live", feedback_live(feedback.kind)),
        ],
        [html.text(feedback.message)],
      )
  }
}

fn feedback_class(kind: FeedbackKind) -> String {
  case kind {
    Info -> "status"
    Warning -> "status error"
  }
}

fn feedback_role(kind: FeedbackKind) -> String {
  case kind {
    Info -> "status"
    Warning -> "status"
  }
}

fn feedback_live(kind: FeedbackKind) -> String {
  case kind {
    Info -> "polite"
    Warning -> "polite"
  }
}

fn readiness_text(readiness: Readiness) -> String {
  case readiness {
    WaitingForHandleAndReady -> "waiting for handle and ready callback"
    WaitingForHandle -> "waiting for document handle"
    WaitingForReady -> "waiting for ready callback"
    Bootstrapping -> "bootstrapping pantry channels"
    Ready -> "ready"
    Failed -> "failed"
  }
}

fn yes_no(value: Bool) -> String {
  case value {
    True -> "yes"
    False -> "no"
  }
}

fn scenario_text(scenario: ScenarioState) -> String {
  "Tombstone: "
  <> tombstone_status_text(scenario.tombstone)
  <> " · Concurrent add/remove: "
  <> concurrent_status_text(scenario.concurrent)
}
