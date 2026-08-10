import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}

import lustre
import lustre/attribute.{class, placeholder, value}
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

import watershed/browser
import watershed/g_set_kernel
import watershed/or_set_kernel
import watershed/two_p_set_kernel
import watershed_js.{type Document, type GSet, type OrSet, type TwoPSet}
import watershed_lustre

import doc_schema
import grocery_triptych_lustre/bootstrap_guard.{
  type Feedback, type FeedbackKind, Info, Warning,
}
import pantry_snapshot.{type Row, type Snapshots}

const socket_url = "ws://localhost:4000/socket/websocket?vsn=2.0.0"

const tenant = "dev-tenant"

const tenant_secret = "levee-dev-secret-change-in-production"

pub fn main() {
  let app = lustre.application(init, update, view)
  let document = browser.document_on_navigate("grocery-triptych")
  let assert Ok(_) = lustre.start(app, "#app", document)
  Nil
}

type Model {
  Model(
    document_name: String,
    readiness: Readiness,
    doc: Option(Document),
    ready_callback_seen: Bool,
    bootstrap_requested: Bool,
    pending: PendingPantry,
    shared: Option(SharedPantry),
    draft: String,
    snapshots: Snapshots,
    rows: List(Row),
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
  NoScenario
  PendingScenario(String)
}

type Msg {
  GotHandle(Document)
  Connected(Result(Nil, String))
  EnsuredGrowOnly(Result(GSet, String))
  EnsuredTwoPhase(Result(TwoPSet, String))
  EnsuredObserved(Result(OrSet, String))
  DraftChanged(String)
  GrowOnlyChanged(g_set_kernel.GSetEvent)
  TwoPhaseChanged(two_p_set_kernel.TwoPSetEvent)
  ObservedChanged(or_set_kernel.OrSetEvent)
}

fn init(document: String) -> #(Model, Effect(Msg)) {
  let user_id = "web-" <> int.to_string(1000 + int.random(9000))
  let model =
    Model(
      document_name: document,
      readiness: WaitingForHandleAndReady,
      doc: None,
      ready_callback_seen: False,
      bootstrap_requested: False,
      pending: PendingPantry(None, None, None),
      shared: None,
      draft: "",
      snapshots: pantry_snapshot.empty(),
      rows: [],
      feedback: Some(bootstrap_guard.info(
        "waiting for document handle and ready callback",
      )),
      scenario: NoScenario,
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

fn bootstrap_effect(doc: Document) -> Effect(Msg) {
  let root = watershed_js.root_typed(doc)
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
          #(model, subscribe_shared_effect(shared))
        }
        Some(_), _ -> #(Model(..model, readiness: Ready), effect.none())
        None, _ -> #(Model(..model, readiness: Bootstrapping), effect.none())
      }
  }
}

fn refresh_snapshots(model: Model) -> Model {
  case model.shared {
    Some(shared) -> {
      let snapshots =
        pantry_snapshot.from_values(
          grow_only: watershed_js.g_set_values(shared.grow_only),
          two_phase: watershed_js.two_p_set_values(shared.two_phase),
          observed: watershed_js.or_set_values(shared.observed),
        )
      Model(
        ..model,
        readiness: Ready,
        snapshots: snapshots,
        rows: pantry_snapshot.rows(snapshots),
      )
    }
    None -> model
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

    GrowOnlyChanged(event) -> #(
      refresh_snapshots(
        Model(
          ..model,
          feedback: Some(bootstrap_guard.info(g_set_event_line(event))),
        ),
      ),
      effect.none(),
    )

    TwoPhaseChanged(event) -> #(
      refresh_snapshots(
        Model(
          ..model,
          feedback: Some(bootstrap_guard.info(two_p_set_event_line(event))),
        ),
      ),
      effect.none(),
    )

    ObservedChanged(event) -> #(
      refresh_snapshots(
        Model(
          ..model,
          feedback: Some(bootstrap_guard.info(or_set_event_line(event))),
        ),
      ),
      effect.none(),
    )
  }
}

fn view(model: Model) -> Element(Msg) {
  html.main([class("wrap")], [
    html.h1([], [html.text("watershed · grocery triptych")]),
    html.p([class("status")], [
      html.text(
        "document "
        <> model.document_name
        <> " · "
        <> readiness_text(model.readiness),
      ),
    ]),
    flash_view(model.feedback),
    html.section([class("panel")], [
      html.h2([], [html.text("Bootstrap")]),
      fact("handle", yes_no(option.is_some(model.doc))),
      fact("ready callback", yes_no(model.ready_callback_seen)),
      fact("handles requested", yes_no(model.bootstrap_requested)),
      fact("shared handles", yes_no(option.is_some(model.shared))),
      fact("pending grow_only", pending_status(model.pending.grow_only)),
      fact("pending two_phase", pending_status(model.pending.two_phase)),
      fact("pending observed", pending_status(model.pending.observed)),
      fact("scenario", scenario_text(model.scenario)),
    ]),
    html.section([class("panel")], [
      html.h2([], [html.text("Shared draft")]),
      html.p([class("hint")], [
        html.text(
          "Task 2 wires the draft and synchronized snapshots only; add/remove "
          <> "controls land next.",
        ),
      ]),
      html.input([
        placeholder("milk"),
        value(model.draft),
        event.on_input(DraftChanged),
      ]),
    ]),
    html.section([class("panel")], [
      html.h2([], [html.text("Pantry channels")]),
      html.div([class("pantry")], [
        card("grow_only", "GSet · add-only", model.snapshots.grow_only),
        card(
          "two_phase",
          "TwoPSet · tombstones removals",
          model.snapshots.two_phase,
        ),
        card(
          "observed",
          "OrSet · re-addable observed remove",
          model.snapshots.observed,
        ),
      ]),
    ]),
    html.section([class("panel")], [
      html.h2([], [html.text("Union rows")]),
      html.p([class("hint")], [
        html.text(
          "Rows come from the union of all three snapshots so absence stays "
          <> "renderable.",
        ),
      ]),
      rows_view(model.rows),
    ]),
  ])
}

fn card(name: String, rule: String, items: List(String)) -> Element(msg) {
  html.article([class("card")], [
    html.h2([], [html.text(name)]),
    html.p([], [
      html.text(
        "tagged by Pantry · "
        <> rule
        <> " · "
        <> int.to_string(list.length(items))
        <> " item(s)",
      ),
    ]),
    case items {
      [] -> html.p([class("hint")], [html.text("empty")])
      _ ->
        html.ul(
          [class("values")],
          list.map(items, fn(item) { html.li([], [html.text(item)]) }),
        )
    },
  ])
}

fn rows_view(rows: List(Row)) -> Element(Msg) {
  case rows {
    [] ->
      html.p([class("hint")], [
        html.text("No rows yet — snapshots will populate once the sets change."),
      ])
    _ -> html.ul([class("rows")], list.map(rows, row_view))
  }
}

fn row_view(row: Row) -> Element(Msg) {
  html.li([class("row")], [
    html.span([class("item")], [html.text(row.item)]),
    presence_badge("grow_only", row.grow_only),
    presence_badge("two_phase", row.two_phase),
    presence_badge("observed", row.observed),
  ])
}

fn presence_badge(label: String, present: Bool) -> Element(msg) {
  let marker = case present {
    True -> "present"
    False -> "absent"
  }
  html.span([class("pill " <> marker)], [
    html.text(
      label
      <> ": "
      <> case present {
        True -> "yes"
        False -> "no"
      },
    ),
  ])
}

fn fact(label: String, detail: String) -> Element(msg) {
  html.p([class("hint")], [html.text(label <> ": " <> detail)])
}

fn flash_view(feedback: Option(Feedback)) -> Element(msg) {
  case feedback {
    None -> html.div([], [])
    Some(feedback) ->
      html.p([class(feedback_class(feedback.kind))], [
        html.text(feedback.message),
      ])
  }
}

fn feedback_class(kind: FeedbackKind) -> String {
  case kind {
    Info -> "status"
    Warning -> "status error"
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

fn pending_status(handle: Option(a)) -> String {
  case handle {
    Some(_) -> "resolved"
    None -> "waiting"
  }
}

fn scenario_text(scenario: ScenarioState) -> String {
  case scenario {
    NoScenario -> "presets land in a later task"
    PendingScenario(name) -> "running " <> name
  }
}

/// A G-set can only tell us that something was added; removal is not
/// expressible, which is part of what the demo exists to show.
fn g_set_event_line(event: g_set_kernel.GSetEvent) -> String {
  case event {
    g_set_kernel.ElementAdded(element) -> "grow_only added " <> element
  }
}

fn two_p_set_event_line(event: two_p_set_kernel.TwoPSetEvent) -> String {
  case event {
    two_p_set_kernel.ElementAdded(element) -> "two_phase added " <> element
    two_p_set_kernel.ElementRemoved(element) -> "two_phase removed " <> element
  }
}

fn or_set_event_line(event: or_set_kernel.OrSetEvent) -> String {
  case event {
    or_set_kernel.ElementAdded(element) -> "observed added " <> element
    or_set_kernel.ElementRemoved(element) -> "observed removed " <> element
  }
}
