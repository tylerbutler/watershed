import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}

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
import watershed_js.{type Document, type GSet, type OrSet, type TwoPSet}
import watershed_lustre

import doc_schema
import grocery_triptych_lustre/bootstrap_guard.{
  type Feedback, type FeedbackKind, Info, Warning,
}
import pantry_snapshot.{type DiffCounts, type Row, type Snapshots}
import triptych_actions

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
    diffs: DiffCounts,
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

type Panel {
  GrowOnlyPanel
  TwoPhasePanel
  ObservedPanel
}

type Msg {
  GotHandle(Document)
  Connected(Result(Nil, String))
  EnsuredGrowOnly(Result(GSet, String))
  EnsuredTwoPhase(Result(TwoPSet, String))
  EnsuredObserved(Result(OrSet, String))
  DraftChanged(String)
  AddSubmitted
  RemoveRequested(String)
  ScenarioRequested(String)
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
      diffs: pantry_snapshot.empty_diff_counts(),
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
      let rows = pantry_snapshot.rows(snapshots)

      Model(
        ..model,
        readiness: Ready,
        snapshots: snapshots,
        rows: rows,
        diffs: pantry_snapshot.diff_counts(rows),
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

fn controls_ready(model: Model) -> Bool {
  option.is_some(model.shared) && !bootstrap_guard.failure_latched(model.error)
}

fn with_feedback(model: Model, feedback: Feedback) -> Model {
  case bootstrap_guard.failure_latched(model.error) {
    True -> model
    False -> Model(..model, feedback: Some(feedback))
  }
}

fn apply_shared_add(model: Model, raw_item: String) -> Model {
  let model = Model(..model, scenario: NoScenario)

  case triptych_actions.normalize_item_input(raw_item) {
    Error(message) -> with_feedback(model, bootstrap_guard.warning(message))

    Ok(item) ->
      case model.shared {
        None ->
          with_feedback(model, triptych_actions.not_ready_feedback("adding"))

        Some(shared) -> {
          let two_phase_was_present =
            watershed_js.two_p_set_contains(shared.two_phase, item)

          watershed_js.g_set_add(shared.grow_only, item)
          watershed_js.two_p_set_add(shared.two_phase, item)
          watershed_js.or_set_add(shared.observed, item)

          let two_phase_is_present =
            watershed_js.two_p_set_contains(shared.two_phase, item)

          Model(..model, draft: "")
          |> refresh_snapshots
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
  let model = Model(..model, scenario: NoScenario)

  case model.shared {
    None ->
      with_feedback(model, triptych_actions.not_ready_feedback("removing"))

    Some(shared) -> {
      watershed_js.two_p_set_remove(shared.two_phase, item)
      watershed_js.or_set_remove(shared.observed, item)

      model
      |> refresh_snapshots
      |> with_feedback(triptych_actions.remove_feedback(item))
    }
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

    DraftChanged(text) -> #(
      Model(..model, draft: text, scenario: NoScenario),
      effect.none(),
    )

    AddSubmitted -> #(apply_shared_add(model, model.draft), effect.none())

    RemoveRequested(item) -> #(apply_shared_remove(model, item), effect.none())

    ScenarioRequested(name) -> #(
      Model(..model, scenario: PendingScenario(name))
        |> with_feedback(triptych_actions.scenario_placeholder_feedback(name)),
      effect.none(),
    )

    GrowOnlyChanged(_) -> #(refresh_snapshots(model), effect.none())

    TwoPhaseChanged(_) -> #(refresh_snapshots(model), effect.none())

    ObservedChanged(_) -> #(refresh_snapshots(model), effect.none())
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
  let ready = controls_ready(model)
  let add_help_id = "add-item-help"

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
            attribute.disabled(!ready),
            event.on_input(DraftChanged),
          ]),
        ]),
        html.button(
          [
            attribute.class("primary"),
            attribute.type_("submit"),
            attribute.disabled(!ready),
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
        html.text(case ready {
          True ->
            "Press Enter or Add to submit. Empty items are rejected with a warning."
          False ->
            "Add is disabled until the document handle and pantry bootstrap finish."
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
            event.on_click(ScenarioRequested("Tombstone")),
            attribute.aria_label("Explain the upcoming tombstone preset"),
          ],
          [html.text("Tombstone")],
        ),
        html.button(
          [
            attribute.type_("button"),
            event.on_click(ScenarioRequested("Concurrent add/remove")),
            attribute.aria_label(
              "Explain the upcoming concurrent add remove preset",
            ),
          ],
          [html.text("Concurrent add/remove")],
        ),
      ]),
    ]),
    html.p([attribute.class("hint")], [
      html.text(
        "Scenario buttons are placeholders in this task; they explain the "
        <> "next flow but do not automate it yet.",
      ),
    ]),
  ])
}

fn shared_remove_view(model: Model) -> Element(Msg) {
  let ready = controls_ready(model)

  html.section([attribute.class("panel")], [
    html.h2([], [html.text("Shared remove actions")]),
    html.p([attribute.class("hint")], [
      html.text(
        "Each remove issues paired TwoPSet and OrSet removals. GSet keeps the "
        <> "item because grow-only removal is not expressible.",
      ),
    ]),
    case model.rows {
      [] ->
        html.p([attribute.class("hint")], [
          html.text("Add an item to start the comparison."),
        ])

      rows ->
        html.ul(
          [attribute.class("shared-actions")],
          list.map(rows, shared_row_view(_, ready)),
        )
    },
  ])
}

fn shared_row_view(row: Row, ready: Bool) -> Element(Msg) {
  html.li([attribute.class("shared-row")], [
    html.div([attribute.class("row-main")], [
      html.span([attribute.class("item")], [html.text(row.item)]),
      divergence_marker(row.diverges),
    ]),
    html.button(
      [
        attribute.class("danger"),
        attribute.type_("button"),
        attribute.disabled(!ready),
        event.on_click(RemoveRequested(row.item)),
        attribute.aria_label("Remove " <> row.item <> " from TwoPSet and OrSet"),
      ],
      [html.text("Remove from TwoPSet + OrSet")],
    ),
  ])
}

fn comparison_view(model: Model) -> Element(Msg) {
  html.section([attribute.class("panel")], [
    html.h2([], [html.text("Triptych comparison")]),
    html.p([attribute.class("hint")], [
      html.text(
        "Every panel renders the same union rows in the same order; only the "
        <> "removal rule changes what stays present.",
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
          <> diff_count_text(panel_diff_count(panel, model.diffs)),
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
    GrowOnlyPanel -> pantry_snapshot.grow_only_differs(row)
    TwoPhasePanel -> pantry_snapshot.two_phase_differs(row)
    ObservedPanel -> pantry_snapshot.observed_differs(row)
  }
}

fn panel_count_text(count: Int) -> String {
  int.to_string(count)
  <> case count == 1 {
    True -> " item present"
    False -> " items present"
  }
}

fn diff_count_text(count: Int) -> String {
  int.to_string(count)
  <> case count == 1 {
    True -> " diff"
    False -> " diffs"
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
    Warning -> "alert"
  }
}

fn feedback_live(kind: FeedbackKind) -> String {
  case kind {
    Info -> "polite"
    Warning -> "assertive"
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
  case scenario {
    NoScenario -> "placeholder controls only"
    PendingScenario(name) -> name <> " placeholder selected"
  }
}
