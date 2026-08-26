//// Consensus job-dispatch board — an `OrderedCollection` + `TaskManager` demo.
////
//// The screen reads as a kanban board, but the columns are literally the
//// kernels' states, not a convention layered on top:
////
//// - **Queued** is the `OrderedCollection` FIFO. Only the tab holding the
////   *dispatcher* role generates jobs into it.
//// - **In progress** is the collection's held-jobs table: each entry is a job
////   exactly one client acquired, labelled with its owner.
//// - **Done** is an ordinary `SharedSequence` append log, because the
////   consensus kernels deliberately drop completed jobs.
////
//// Two consensus stories play out here, and both are non-optimistic on
//// purpose:
////
//// 1. **Claiming is a race the server referees.** `ordered_acquire` takes the
////    FIFO head; nothing moves until the op sequences, so the button renders a
////    pending state that resolves via the acquire's consensus outcome —
////    `AcquiredItem` for the winner, `QueueEmpty` for a loser (whose op emits
////    no event at all). Faking an optimistic transition would hide the most
////    interesting thing the queue does.
//// 2. **A dying client cannot take its work with it.** Close a tab holding a
////    job and the server's sequenced `"leave"` re-releases the job to the
////    queue tail in every surviving replica — no code in this app does that.
////    Close the dispatcher tab and the next queued volunteer inherits the
////    role the same way.
////
//// The demo script, printed on the page: open three tabs, volunteer a backup
//// dispatcher, then close the tab marked "dispatcher".

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}

import lustre
import lustre/attribute.{class, disabled, style}
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

import watershed.{
  type Document, type OrderedCollection, type SharedSequence, type TaskManager,
}
import watershed/browser
import watershed/client_id
import watershed/ordered_collection_kernel.{
  type AcquireOutcome, type OrderedEvent,
}
import watershed/presence
import watershed/sequence_kernel
import watershed/task_manager_kernel.{type TaskManagerEvent}
import watershed_lustre

import doc_schema
import job.{type Job, Job}

// ── Dev config for `just server` (levee dev mode) ────────────────────────────

const socket_url = "ws://localhost:4000/socket/websocket?vsn=2.0.0"

const tenant = "dev-tenant"

const tenant_secret = "levee-dev-secret-change-in-production"

/// The single named role: the tab that generates work.
const dispatcher_role = "dispatcher"

/// How long an acquired job "runs" before completing itself. The dwell exists
/// to leave a window in which to kill the worker tab — the kill is the demo.
const dwell_ms = 4000

const generate_ms = 2500

/// Stop generating past this backlog so the board stays readable.
const max_queued = 6

const job_labels = [
  "resize image", "transcode video", "send digest", "index search",
  "compress logs", "render report",
]

pub fn main() {
  let app = lustre.application(init, update, view)
  let document = browser.document_on_navigate("work-queue")
  let assert Ok(_) = lustre.start(app, "#app", document)
  Nil
}

// ── Model ────────────────────────────────────────────────────────────────────

type Status {
  Connecting
  Ready
  Failed(reason: String)
}

type Shared {
  Shared(queue: OrderedCollection, roles: TaskManager, done: SharedSequence)
}

/// The nested channels as they resolve during bootstrap. Each `ensure_*`
/// effect fills one slot; when all three are present they assemble.
type PendingShared {
  PendingShared(
    queue: Option(OrderedCollection),
    roles: Option(TaskManager),
    done: Option(SharedSequence),
  )
}

/// The local claim, driven entirely by consensus signals. `Working` has
/// exactly three exits: the dwell timer completes the job, Release returns it,
/// or the tab dies — in which case there is no tab left to hold the state.
type ClaimState {
  Idle
  /// Acquire submitted, not yet sequenced. The queue is non-optimistic, so
  /// nothing on the board has moved yet.
  PendingClaim
  Working(acquire_id: String, job: Job)
  /// The claim sequenced against a drained queue — a peer got there first (or
  /// the board emptied). Cleared back to `Idle` after a beat.
  Missed
}

type Model {
  Model(
    status: Status,
    doc: Option(Document(doc_schema.Dispatch)),
    shared: Option(Shared),
    pending: PendingShared,
    user_id: String,
    my_int: Option(Int),
    // Snapshots, re-read from the channels on every event.
    queued: List(Job),
    in_progress: List(#(String, Job, Option(Int))),
    done: List(Job),
    role_assignee: Option(Int),
    volunteered: Bool,
    claim: ClaimState,
    generator_running: Bool,
    job_counter: Int,
    last_error: Option(String),
  )
}

type Msg {
  GotHandle(Document(doc_schema.Dispatch))
  Connected(Result(Nil, String))
  EnsuredQueue(Result(OrderedCollection, String))
  EnsuredRoles(Result(TaskManager, String))
  EnsuredDone(Result(SharedSequence, String))
  QueueEvent(OrderedEvent)
  RoleEvent(TaskManagerEvent)
  DoneEvent(sequence_kernel.SequenceEvent)
  BecomeDispatcherClicked
  AbandonDispatcherClicked
  GenerateTick
  ClaimClicked
  ClaimSettled(AcquireOutcome)
  WorkDone(acquire_id: String)
  ReleaseClicked
  ClearMissed
}

fn init(document: String) -> #(Model, Effect(Msg)) {
  // A distinct user per tab so the tabs are separate clients.
  let user_id = "web-" <> int.to_string(1000 + int.random(9000))
  let model =
    Model(
      status: Connecting,
      doc: None,
      shared: None,
      pending: PendingShared(None, None, None),
      user_id: user_id,
      my_int: None,
      queued: [],
      in_progress: [],
      done: [],
      role_assignee: None,
      volunteered: False,
      claim: Idle,
      generator_running: False,
      job_counter: 1,
      last_error: None,
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

// ── Update ───────────────────────────────────────────────────────────────────

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    // The handle arrives before the handshake completes; creating the nested
    // channels must wait for `Connected`.
    GotHandle(doc) -> #(Model(..model, doc: Some(doc)), effect.none())

    Connected(Ok(_)) -> {
      let model = Model(..model, status: Ready)
      case model.doc, model.shared {
        Some(doc), None -> #(model, bootstrap_effect(doc))
        _, _ -> #(snapshot(model), effect.none())
      }
    }
    Connected(Error(reason)) -> #(
      Model(..model, status: Failed(reason), last_error: Some(reason)),
      effect.none(),
    )

    EnsuredQueue(Ok(queue)) ->
      assemble(
        Model(
          ..model,
          pending: PendingShared(..model.pending, queue: Some(queue)),
        ),
      )
    EnsuredQueue(Error(reason)) -> #(
      Model(..model, last_error: Some(reason)),
      effect.none(),
    )
    EnsuredRoles(Ok(roles)) ->
      assemble(
        Model(
          ..model,
          pending: PendingShared(..model.pending, roles: Some(roles)),
        ),
      )
    EnsuredRoles(Error(reason)) -> #(
      Model(..model, last_error: Some(reason)),
      effect.none(),
    )
    EnsuredDone(Ok(done)) ->
      assemble(
        Model(
          ..model,
          pending: PendingShared(..model.pending, done: Some(done)),
        ),
      )
    EnsuredDone(Error(reason)) -> #(
      Model(..model, last_error: Some(reason)),
      effect.none(),
    )

    // Our own `Completed` ack is the one queue event with an action attached:
    // only the completer appends to the Done log, and only on commit, so the
    // job lands there exactly once.
    QueueEvent(ordered_collection_kernel.Completed(value, True)) -> {
      let model = case model.shared {
        Some(shared) -> {
          let _ =
            watershed.sequence_insert(
              shared.done,
              watershed.sequence_length(shared.done),
              value,
            )
          Model(..model, claim: Idle)
        }
        None -> model
      }
      #(snapshot(model), effect.none())
    }
    // Everything else — adds, peer acquires, re-releases after a leave — just
    // refreshes the snapshot. `Added(newly_added: False)` is a job returning
    // to the queue; it falls out of the re-read like any other change.
    QueueEvent(_) -> #(snapshot(model), effect.none())

    // Role changes carry no payload worth keeping: the snapshot re-reads the
    // committed queue, and `maybe_start_generator` notices a promotion —
    // whether it arrived as `Assigned` (own volunteer acked) or as the bare
    // `QueueChanged` a survivor gets when the holder's leave sequences.
    RoleEvent(_) -> maybe_start_generator(snapshot(model))

    DoneEvent(_) -> #(snapshot(model), effect.none())

    BecomeDispatcherClicked ->
      case model.shared {
        None -> #(model, effect.none())
        Some(shared) -> {
          let _outcome =
            watershed.volunteer_for_task(shared.roles, dispatcher_role)
          // Assignment is not optimistic here: the generator starts when the
          // sequenced role state says this tab is the head.
          #(snapshot(model), effect.none())
        }
      }

    AbandonDispatcherClicked ->
      case model.shared {
        None -> #(model, effect.none())
        Some(shared) -> {
          watershed.abandon_task(shared.roles, dispatcher_role)
          #(snapshot(model), effect.none())
        }
      }

    GenerateTick ->
      case model.shared, is_dispatcher(model) {
        Some(shared), True -> {
          let model = case list.length(model.queued) < max_queued {
            True -> {
              watershed.ordered_add(shared.queue, job.to_json(next_job(model)))
              Model(..model, job_counter: model.job_counter + 1)
            }
            False -> model
          }
          #(model, watershed_lustre.after(generate_ms, GenerateTick))
        }
        // Lost the role (abandoned, completed, or this tab was never it):
        // stop, and let a later promotion re-arm via `maybe_start_generator`.
        _, _ -> #(Model(..model, generator_running: False), effect.none())
      }

    ClaimClicked ->
      case model.shared, model.claim {
        Some(shared), Idle | Some(shared), Missed -> #(
          Model(..model, claim: PendingClaim),
          watershed_lustre.ordered_acquire(shared.queue, ClaimSettled),
        )
        _, _ -> #(model, effect.none())
      }

    ClaimSettled(ordered_collection_kernel.AcquiredItem(acquire_id, value)) -> {
      let model =
        Model(..model, claim: Working(acquire_id, job.from_json(value)))
      #(snapshot(model), watershed_lustre.after(dwell_ms, WorkDone(acquire_id)))
    }
    ClaimSettled(ordered_collection_kernel.QueueEmpty) -> #(
      snapshot(Model(..model, claim: Missed)),
      watershed_lustre.after(2000, ClearMissed),
    )
    ClaimSettled(ordered_collection_kernel.Aborted) -> #(
      Model(
        ..model,
        claim: Idle,
        last_error: Some("claim aborted: disconnected"),
      ),
      effect.none(),
    )

    ClearMissed ->
      case model.claim {
        Missed -> #(Model(..model, claim: Idle), effect.none())
        _ -> #(model, effect.none())
      }

    // The dwell timer fired. The id guard makes a stale timer — from a job
    // already released — a no-op. Completion is confirmed by the sequenced
    // `Completed(local: True)` ack, which is where the Done append happens.
    WorkDone(acquire_id) ->
      case model.shared, model.claim {
        Some(shared), Working(current, _) if current == acquire_id -> {
          watershed.ordered_complete(shared.queue, acquire_id)
          #(model, effect.none())
        }
        _, _ -> #(model, effect.none())
      }

    ReleaseClicked ->
      case model.shared, model.claim {
        Some(shared), Working(acquire_id, _) -> {
          watershed.ordered_release(shared.queue, acquire_id)
          #(snapshot(Model(..model, claim: Idle)), effect.none())
        }
        _, _ -> #(model, effect.none())
      }
  }
}

fn bootstrap_effect(doc: Document(doc_schema.Dispatch)) -> Effect(Msg) {
  let root = watershed.root_typed(doc)
  effect.batch([
    watershed_lustre.ensure_ordered_collection(
      doc,
      root,
      doc_schema.queue(),
      EnsuredQueue,
    ),
    watershed_lustre.ensure_task_manager(
      doc,
      root,
      doc_schema.roles(),
      EnsuredRoles,
    ),
    watershed_lustre.ensure_sequence(
      doc,
      root,
      doc_schema.completed(),
      EnsuredDone,
    ),
  ])
}

fn assemble(model: Model) -> #(Model, Effect(Msg)) {
  case model.shared, model.pending {
    None, PendingShared(Some(queue), Some(roles), Some(done)) -> {
      let shared = Shared(queue:, roles:, done:)
      let my_int = case model.doc {
        Some(doc) -> watershed.client_id(doc) |> option.map(client_id.to_int)
        None -> None
      }
      let model = snapshot(Model(..model, shared: Some(shared), my_int: my_int))
      #(
        model,
        effect.batch([
          watershed_lustre.subscribe_ordered_collection(queue, QueueEvent),
          watershed_lustre.subscribe_task_manager(roles, RoleEvent),
          watershed_lustre.subscribe_sequence(done, DoneEvent),
        ]),
      )
    }
    _, _ -> #(model, effect.none())
  }
}

/// Re-read every channel into the model. Events carry payloads, but rendering
/// from a re-read means the board always shows committed state — which is the
/// honest picture for two consensus kernels.
fn snapshot(model: Model) -> Model {
  case model.shared {
    None -> model
    Some(shared) -> {
      let role_assignee =
        watershed.task_queues(shared.roles)
        |> list.find(fn(entry) { entry.0 == dispatcher_role })
        |> fn(found) {
          case found {
            Ok(#(_, [head, ..])) -> Some(head)
            _ -> None
          }
        }
      Model(
        ..model,
        queued: watershed.ordered_queue(shared.queue)
          |> list.map(job.from_json),
        in_progress: watershed.ordered_jobs(shared.queue)
          |> list.map(fn(entry) {
            let #(acquire_id, ordered_collection_kernel.JobEntry(value, owner)) =
              entry
            #(acquire_id, job.from_json(value), owner)
          }),
        done: watershed.sequence_values(shared.done)
          |> list.map(job.from_json),
        role_assignee: role_assignee,
        volunteered: watershed.task_queued(shared.roles, dispatcher_role),
      )
    }
  }
}

fn is_dispatcher(model: Model) -> Bool {
  model.my_int != None && model.role_assignee == model.my_int
}

/// Arm the generation timer when the sequenced role state says this tab holds
/// the dispatcher role and no timer is already running. Both promotion paths —
/// own volunteer acked, or inherited when the holder's leave sequenced — land
/// here through the same snapshot.
fn maybe_start_generator(model: Model) -> #(Model, Effect(Msg)) {
  case is_dispatcher(model) && !model.generator_running {
    True -> #(
      Model(..model, generator_running: True),
      watershed_lustre.after(generate_ms, GenerateTick),
    )
    False -> #(model, effect.none())
  }
}

fn next_job(model: Model) -> Job {
  let count = model.job_counter
  let label = case list.drop(job_labels, count % list.length(job_labels)) {
    [label, ..] -> label
    [] -> "job"
  }
  Job(
    id: model.user_id <> "-" <> int.to_string(count),
    label: label <> " #" <> int.to_string(count),
    created_by: model.user_id,
  )
}

// ── View ─────────────────────────────────────────────────────────────────────

fn view(model: Model) -> Element(Msg) {
  html.main([class("wrap")], [
    html.h1([], [html.text("watershed · consensus work queue")]),
    status_strip(model),
    error_view(model),
    html.div([class("board")], [
      queued_column(model),
      in_progress_column(model),
      done_column(model),
    ]),
    html.p([class("hint")], [
      html.text(
        "Open three tabs. Volunteer one as dispatcher and another as backup, "
        <> "claim jobs from the third — then close the tab marked "
        <> "\"dispatcher\", or a tab mid-job, and watch the survivors recover "
        <> "on their own.",
      ),
    ]),
  ])
}

fn status_strip(model: Model) -> Element(Msg) {
  let connection = case model.status {
    Connecting -> "connecting…"
    Ready -> "connected"
    Failed(reason) -> "failed: " <> reason
  }
  html.div([class("status")], [
    html.span([], [html.text(connection <> " · ")]),
    client_chip(model.user_id, presence.short_name(model.user_id)),
    dispatcher_badge(model),
    dispatcher_button(model),
  ])
}

fn dispatcher_badge(model: Model) -> Element(Msg) {
  case model.role_assignee, model.my_int {
    None, _ -> html.span([class("role")], [html.text(" · no dispatcher")])
    Some(assignee), Some(mine) if assignee == mine ->
      html.span([class("role role-mine")], [
        html.text(" · this tab is the dispatcher"),
      ])
    Some(assignee), _ ->
      html.span([class("role")], [
        html.text(" · dispatcher: "),
        owner_chip(Some(assignee), model),
      ])
  }
}

fn dispatcher_button(model: Model) -> Element(Msg) {
  case is_dispatcher(model), model.volunteered {
    True, _ ->
      html.button([event.on_click(AbandonDispatcherClicked)], [
        html.text("Abandon role"),
      ])
    False, True ->
      html.button([disabled(True)], [html.text("Queued as backup")])
    False, False ->
      html.button(
        [
          event.on_click(BecomeDispatcherClicked),
          disabled(model.shared == None),
        ],
        [html.text("Become dispatcher")],
      )
  }
}

fn error_view(model: Model) -> Element(Msg) {
  html.p([class("error")], [html.text(option.unwrap(model.last_error, ""))])
}

fn queued_column(model: Model) -> Element(Msg) {
  let claim_label = case model.claim {
    Idle -> "Claim next"
    PendingClaim -> "claiming…"
    Working(..) -> "working"
    Missed -> "taken!"
  }
  let claimable = case model.claim {
    Idle | Missed -> model.shared != None && model.queued != []
    _ -> False
  }
  column("Queued (" <> int.to_string(list.length(model.queued)) <> ")", [
    html.button([event.on_click(ClaimClicked), disabled(!claimable)], [
      html.text(claim_label),
    ]),
    ..case model.queued {
      [] -> [empty_note("no jobs waiting")]
      jobs -> list.map(jobs, queued_card)
    }
  ])
}

fn queued_card(entry: Job) -> Element(Msg) {
  html.div([class("card")], [
    html.div([class("card-label")], [html.text(entry.label)]),
    html.div([class("card-meta")], [
      html.text("from "),
      client_chip(entry.created_by, presence.short_name(entry.created_by)),
    ]),
  ])
}

fn in_progress_column(model: Model) -> Element(Msg) {
  column("In progress", case model.in_progress {
    [] -> [empty_note("nothing running")]
    entries -> list.map(entries, fn(entry) { in_progress_card(entry, model) })
  })
}

fn in_progress_card(
  entry: #(String, Job, Option(Int)),
  model: Model,
) -> Element(Msg) {
  let #(acquire_id, entry_job, owner) = entry
  let mine = case model.claim {
    Working(current, _) -> current == acquire_id
    _ -> False
  }
  html.div([class(card_class(mine))], [
    html.div([class("card-label")], [html.text(entry_job.label)]),
    html.div([class("card-meta")], [
      html.text(case mine {
        True -> "working… "
        False -> "held by "
      }),
      owner_chip(owner, model),
    ]),
    ..case mine {
      True -> [
        html.button([event.on_click(ReleaseClicked)], [html.text("Release")]),
      ]
      False -> []
    }
  ])
}

fn card_class(mine: Bool) -> String {
  case mine {
    True -> "card card-mine"
    False -> "card"
  }
}

fn done_column(model: Model) -> Element(Msg) {
  column(
    "Done (" <> int.to_string(list.length(model.done)) <> ")",
    case model.done {
      [] -> [empty_note("nothing finished yet")]
      jobs -> list.reverse(jobs) |> list.map(done_card)
    },
  )
}

fn done_card(entry: Job) -> Element(Msg) {
  html.div([class("card card-done")], [
    html.div([class("card-label")], [html.text(entry.label)]),
  ])
}

fn column(title: String, cards: List(Element(Msg))) -> Element(Msg) {
  html.section([class("column")], [
    html.h2([], [html.text(title)]),
    html.div([class("cards")], cards),
  ])
}

fn empty_note(text: String) -> Element(Msg) {
  html.p([class("empty")], [html.text(text)])
}

/// A colored chip for a user id, deterministic across tabs.
fn client_chip(user: String, label: String) -> Element(Msg) {
  html.span([class("chip"), style("border-color", presence.color_for(user))], [
    html.text(label),
  ])
}

/// The kernels identify clients by hashed int, not user id, so peers render as
/// `client N` — except this tab, which knows its own number.
fn owner_chip(owner: Option(Int), model: Model) -> Element(Msg) {
  case owner {
    None -> html.span([class("chip")], [html.text("unowned")])
    Some(id) -> {
      let label = case model.my_int {
        Some(mine) if mine == id -> "me"
        _ -> "client " <> int.to_string(id)
      }
      html.span(
        [
          class("chip"),
          style("border-color", presence.color_for(int.to_string(id))),
        ],
        [html.text(label)],
      )
    }
  }
}
