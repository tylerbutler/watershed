//// Collaborative release checklist — a small "go/no-go" room for shipping a
//// release.
////
//// Three channels, three different consistency rules, on purpose:
////
//// - `checks` is an OR-set of completed gate ids. Add-wins is correct here:
////   two people ticking the same gate concurrently is not a conflict, and
////   ticking a gate that someone else just reopened has to win — which is
////   exactly the case a remove-wins set (`TwoPSet`) would get backwards. The
////   fixed list of gates — their ids and labels — never goes on the wire;
////   only the ids of the ones that are done do (see `gates`).
////
//// - `captain` is a `Claims` channel holding one key, `"captain"`. Claims give
////   the room first-writer-wins election plus compare-and-set take-over, so
////   exactly one client ends up holding the seat even when several claim it
////   in the same instant. This is a *UI convenience*, not a security
////   boundary: nothing stops another client from calling `pact_map_set` on
////   the release target directly, and the app says so rather than implying
////   otherwise. Reads are not optimistic — the local claim UI stays in a
////   pending state until the claim's outcome sequences.
////
//// - `release` is a `PactMap` holding one key, `"target"`, the version or tag
////   being shipped. Like the drum machine's `"bpm"`, this is state where
////   uncoordinated last-write-wins is genuinely bad, so publishing a target
////   requires the room to sign off first. Only the committed captain may
////   draft one, and only once every fixed gate is complete.

import gleam/dynamic/decode
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

import release_checklist_lustre/doc_schema
import release_checklist_lustre/release_readiness
import watershed.{type Claims, type Document, type OrSet, type PactMap}
import watershed/browser
import watershed/claims_kernel
import watershed/client_id
import watershed/pact_map_kernel
import watershed_lustre

// ── Dev config for the floodgate dev server (`just integration-up`) ──────────

const socket_url = "ws://localhost:4000/socket/websocket?vsn=2.0.0"

const tenant = "dev-tenant"

const tenant_secret = "levee-dev-secret-change-in-production"

/// The single key on the captain claims channel.
const captain_key = "captain"

/// The single key in the quorum-gated release pact.
const target_key = "target"

/// How often to re-read a pending release proposal's signoff list. The kernel
/// emits an event when a pact goes pending and when it is accepted, but
/// nothing in between, so watching the list drain means asking.
const signoff_poll_ms = 250

pub fn main() -> Nil {
  let app = lustre.application(init, update, view)
  let document = browser.document_on_navigate("release-checklist")
  let assert Ok(_) = lustre.start(app, "#app", document)
  Nil
}

// ── Gates ────────────────────────────────────────────────────────────────────

/// A fixed release gate: an id shared over the wire, and a label that never
/// leaves this module. Recognizable, generic release checks — nothing
/// specific to this repo — so the demo reads the same regardless of what it
/// is actually shipping.
type Gate {
  Gate(id: String, label: String)
}

/// The checklist. Fixed and small on purpose (RC3): a real release has more
/// gates, but four is enough to show convergence without turning the demo
/// into a form.
fn gates() -> List(Gate) {
  [
    Gate("tests_passing", "Tests passing"),
    Gate("changelog_updated", "Changelog updated"),
    Gate("security_review", "Security review"),
    Gate("docs_updated", "Docs updated"),
  ]
}

fn gate_ids() -> List(String) {
  list.map(gates(), fn(gate) { gate.id })
}

// ── Model ────────────────────────────────────────────────────────────────────

type Status {
  Connecting
  Ready
  Failed(reason: String)
}

type SharedState {
  SharedState(checks: OrSet, captain: Claims, release: PactMap)
}

/// The nested channels as they resolve during bootstrap. Each `ensure_*`
/// effect fills one slot; when all three are present they assemble into
/// `SharedState`.
type PendingShared {
  PendingShared(
    checks: Option(OrSet),
    captain: Option(Claims),
    release: Option(PactMap),
  )
}

/// A release-target change the room has not finished agreeing to.
///
/// `PactMap` freezes a signoff list from the connected roster the moment a
/// proposal is sequenced, and the value is not accepted until every client on
/// that list has acknowledged it — or has left the room. `waiting` is what is
/// left of that list; `quorum` is how long it was when the proposal landed,
/// so the UI can say "1 of 3" instead of a bare count with no denominator.
///
/// Nothing here is a vote or an approval. `pact_map_kernel` emits `OweAccept`
/// and the runtime auto-submits it: signing off means "this client has seen
/// the proposal", not "this client agrees". The UI must never render an
/// agree/reject affordance, because there is nothing behind it.
type Proposal {
  Proposal(target: String, waiting: List(Int), quorum: Int)
}

type Model {
  Model(
    status: Status,
    doc: Option(Document(doc_schema.Checklist)),
    shared: Option(SharedState),
    pending: PendingShared,
    user_id: String,
    /// Completed gate ids, read from the OR-set.
    completed: List(String),
    /// The committed captain's user id, `None` until someone claims the seat.
    captain: Option(String),
    /// True between calling `claim_once`/`compare_and_set_claim` and
    /// learning the outcome. Claims reads are not optimistic — nothing about
    /// `captain` changes until the op sequences — so this is the only signal
    /// that a claim is in flight.
    captain_claim_pending: Bool,
    /// The accepted release target, or `None` until the room has agreed one.
    target: Option(String),
    /// Where the captain's draft box currently sits. Diverges from `target`
    /// while a proposal is in flight.
    target_draft: String,
    /// The release-target proposal the room is currently signing off on, if
    /// any.
    proposal: Option(Proposal),
    /// True between calling `pact_map_set` and learning what the room made of
    /// it — the same submit-to-pending gap the drum machine's tempo has.
    proposing: Bool,
    error: Option(String),
  )
}

type Msg {
  GotHandle(Document(doc_schema.Checklist))
  Connected(Result(Nil, String))
  EnsuredChecks(Result(OrSet, String))
  EnsuredCaptain(Result(Claims, String))
  EnsuredRelease(Result(PactMap, String))
  ChecksChanged
  CaptainEvent(claims_kernel.ClaimEvent)
  ReleaseChanged(pact_map_kernel.PactMapEvent)
  PollSignoffs
  CheckToggled(String)
  ClaimCaptainClicked
  TakeoverClicked
  CaptainClaimResolved(claims_kernel.ClaimOutcome)
  TargetDrafted(String)
  TargetCommitted
  ReconnectClicked
}

fn init(document: String) -> #(Model, Effect(Msg)) {
  // A distinct user per tab so the two clients are separate connections.
  let user_id = "web-" <> int.to_string(1000 + int.random(9000))
  let model =
    Model(
      status: Connecting,
      doc: None,
      shared: None,
      pending: PendingShared(None, None, None),
      user_id: user_id,
      completed: [],
      captain: None,
      captain_claim_pending: False,
      target: None,
      target_draft: "",
      proposal: None,
      proposing: False,
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

/// Bootstrap the document declaratively: seed the title, adopt-or-seed each
/// nested channel, and watch the root — all as one batch of effects. Each
/// `ensure_*` dispatches its channel back as an `Ensured*` message; they
/// assemble into `SharedState` once all three have arrived. `ensure_*` is
/// idempotent — safe to run again on every `GotHandle`/`Connected` that finds
/// `shared` still unset, which is how this bootstrap survives a reconnect
/// without double-seeding anything.
fn bootstrap_effect(doc: Document(doc_schema.Checklist)) -> Effect(Msg) {
  let root = watershed.root_typed(doc)
  effect.batch([
    watershed_lustre.ensure_field(root, doc_schema.title(), "Release checklist"),
    watershed_lustre.ensure_or_set(
      doc,
      root,
      doc_schema.checks(),
      EnsuredChecks,
    ),
    watershed_lustre.ensure_claims(
      doc,
      root,
      doc_schema.captain(),
      EnsuredCaptain,
    ),
    watershed_lustre.ensure_pact_map(
      doc,
      root,
      doc_schema.release(),
      EnsuredRelease,
    ),
    watershed_lustre.subscribe(watershed.root(doc), fn(_event) { ChecksChanged }),
  ])
}

/// Assemble `SharedState` once all three nested channels have resolved, and
/// start the per-channel subscriptions. A no-op until the last channel
/// arrives or once already assembled.
fn assemble(model: Model) -> #(Model, Effect(Msg)) {
  case model.shared, model.pending {
    None, PendingShared(Some(checks), Some(captain), Some(release)) -> {
      let shared = SharedState(checks:, captain:, release:)
      let model = Model(..model, shared: Some(shared), error: None)
      // Adopt whatever the room already agreed before we arrived, and pick up
      // a proposal or a captain that were already settled when we joined.
      let model = read_checks(model, shared)
      let model = read_captain(model, shared)
      let #(model, poll) = read_release(model, shared)
      #(model, effect.batch([subscribe_shared_effect(shared), poll]))
    }
    _, _ -> #(model, effect.none())
  }
}

/// The narrowed per-kind subscriptions as one batch.
///
/// The `PactMap` subscription is the one that is not optional: `WentPending`
/// and `WentAccepted` *are* the consensus protocol, and without them a client
/// can propose and read but never learn that a peer's proposal landed.
fn subscribe_shared_effect(shared: SharedState) -> Effect(Msg) {
  effect.batch([
    watershed_lustre.subscribe_or_set(shared.checks, fn(_event) {
      ChecksChanged
    }),
    watershed_lustre.subscribe_claims(shared.captain, CaptainEvent),
    watershed_lustre.subscribe_pact_map(shared.release, ReleaseChanged),
  ])
}

// ── Update ───────────────────────────────────────────────────────────────────

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    GotHandle(doc) -> {
      let model = Model(..model, doc: Some(doc))
      case model.status, model.shared {
        Ready, None -> #(model, bootstrap_effect(doc))
        _, _ -> #(model, effect.none())
      }
    }

    Connected(Ok(_)) -> {
      let model = Model(..model, status: Ready)
      case model.doc, model.shared {
        Some(doc), None -> #(model, bootstrap_effect(doc))
        _, _ -> #(model, effect.none())
      }
    }

    Connected(Error(reason)) -> #(
      Model(..model, status: Failed(reason), error: Some(reason)),
      effect.none(),
    )

    EnsuredChecks(Ok(checks)) ->
      assemble(
        Model(
          ..model,
          pending: PendingShared(..model.pending, checks: Some(checks)),
        ),
      )
    EnsuredChecks(Error(reason)) -> #(
      ensure_failed(model, reason),
      effect.none(),
    )

    EnsuredCaptain(Ok(captain)) ->
      assemble(
        Model(
          ..model,
          pending: PendingShared(..model.pending, captain: Some(captain)),
        ),
      )
    EnsuredCaptain(Error(reason)) -> #(
      ensure_failed(model, reason),
      effect.none(),
    )

    EnsuredRelease(Ok(release)) ->
      assemble(
        Model(
          ..model,
          pending: PendingShared(..model.pending, release: Some(release)),
        ),
      )
    EnsuredRelease(Error(reason)) -> #(
      ensure_failed(model, reason),
      effect.none(),
    )

    ChecksChanged ->
      case model.shared {
        Some(shared) -> #(read_checks(model, shared), effect.none())
        None -> #(model, effect.none())
      }

    CaptainEvent(_event) ->
      case model.shared {
        Some(shared) -> #(read_captain(model, shared), effect.none())
        None -> #(model, effect.none())
      }

    // `WentPending` and `WentAccepted` are the only two transitions the
    // kernel reports, and both mean the same thing here: re-read the pact.
    ReleaseChanged(_event) ->
      case model.shared {
        Some(shared) -> read_release(model, shared)
        None -> #(model, effect.none())
      }

    PollSignoffs ->
      case model.shared {
        Some(shared) -> read_release(model, shared)
        None -> #(model, effect.none())
      }

    CheckToggled(id) -> {
      case model.shared {
        Some(shared) -> toggle_check(shared, id)
        None -> Nil
      }
      #(model, effect.none())
    }

    ClaimCaptainClicked ->
      case
        model.status,
        model.shared,
        model.captain,
        model.captain_claim_pending
      {
        Ready, Some(shared), None, False -> #(
          Model(..model, captain_claim_pending: True),
          watershed_lustre.claim_once(
            shared.captain,
            captain_key,
            json.string(model.user_id),
            CaptainClaimResolved,
          ),
        )
        _, _, _, _ -> #(model, effect.none())
      }

    TakeoverClicked ->
      case
        model.status,
        model.shared,
        model.captain,
        model.captain_claim_pending
      {
        Ready, Some(shared), Some(current), False if current != model.user_id -> #(
          Model(..model, captain_claim_pending: True),
          watershed_lustre.compare_and_set_claim(
            shared.captain,
            captain_key,
            json.string(model.user_id),
            CaptainClaimResolved,
          ),
        )
        _, _, _, _ -> #(model, effect.none())
      }

    CaptainClaimResolved(outcome) -> {
      let model = Model(..model, captain_claim_pending: False)
      case outcome {
        // A real outcome — this client's committed value won, or a
        // concurrent attempt beat it to the same key. Either way the room's
        // captain may have changed, so re-read it; no error, this is the
        // ordinary result of an election.
        claims_kernel.Accepted(_) | claims_kernel.Lost(_) ->
          case model.shared {
            Some(shared) -> #(read_captain(model, shared), effect.none())
            None -> #(model, effect.none())
          }
        // The attempt never reached the wire at all (still connecting, or
        // the connection has failed) — surface that visibly rather than
        // quietly re-reading state that never changed.
        claims_kernel.Aborted -> #(
          Model(..model, error: Some("Captain claim aborted: not connected.")),
          effect.none(),
        )
      }
    }

    TargetDrafted(raw) -> #(Model(..model, target_draft: raw), effect.none())

    // Propose on submit, never per keystroke. A `pact_map_set` per keystroke
    // would flood the protocol with proposals that invalidate each other —
    // `apply_set` rejects a proposal made while one is pending.
    TargetCommitted ->
      case
        model.shared,
        release_readiness.can_propose(
          release_readiness.is_captain(model.captain, model.user_id),
          release_readiness.all_checks_complete(model.completed, gate_ids()),
          model.target_draft,
          option.is_some(model.proposal),
          model.proposing,
        )
      {
        Some(shared), True -> {
          watershed.pact_map_set(
            shared.release,
            target_key,
            json.string(string.trim(model.target_draft)),
          )
          // Poll rather than wait for an event: a proposal the kernel
          // *rejects* — one made while a peer's is already pending — emits
          // nothing at all. Without this tick the control would stay
          // disabled forever on a rejection.
          #(
            Model(..model, proposing: True),
            watershed_lustre.after(signoff_poll_ms, PollSignoffs),
          )
        }
        _, _ -> #(model, effect.none())
      }

    ReconnectClicked ->
      case model.doc {
        Some(doc) -> #(model, watershed_lustre.force_reconnect(doc))
        None -> #(model, effect.none())
      }
  }
}

/// Re-read the OR-set of completed gate ids into the model.
fn read_checks(model: Model, shared: SharedState) -> Model {
  Model(..model, completed: watershed.or_set_values(shared.checks))
}

/// Re-read the committed captain from the claims channel. Claims reads are
/// not optimistic, so this always reflects the last sequenced claim, never a
/// local guess.
fn read_captain(model: Model, shared: SharedState) -> Model {
  let captain =
    watershed.get_claim(shared.captain, captain_key)
    |> result.try(decode_string)
    |> option.from_result
  Model(..model, captain: captain)
}

/// Re-read the `"target"` pact: the accepted release target, and the
/// proposal still being signed off, if any.
///
/// Returns a poll timer alongside the model because the kernel reports only
/// the two ends of the protocol. A signoff list draining from three names to
/// two emits nothing — `apply_accept` only produces an event when the list
/// empties — so a UI that says *who* it is waiting on has to look. The poll
/// is armed only while something is pending and stops as soon as it is not.
fn read_release(model: Model, shared: SharedState) -> #(Model, Effect(Msg)) {
  let accepted =
    watershed.pact_map_get(shared.release, target_key)
    |> result.try(decode_string)
    |> option.from_result

  let proposal =
    watershed.pact_map_pending(shared.release, target_key)
    |> option.from_result
    |> option.then(fn(pending: pact_map_kernel.Pending) {
      case pending.value |> option.to_result(Nil) |> result.try(decode_string) {
        Ok(target) ->
          Some(Proposal(
            target: target,
            waiting: pending.expected_signoffs,
            // The quorum is the list at its longest. Once it starts draining
            // the original size is unrecoverable, so hold on to the widest
            // reading we have seen for this proposal.
            quorum: quorum_of(model.proposal, target, pending.expected_signoffs),
          ))
        Error(Nil) -> None
      }
    })

  let model =
    Model(
      ..model,
      target: accepted,
      proposal: proposal,
      // Whatever the pact says now is the answer to any proposal of ours
      // that was in flight — including "the kernel rejected it", which
      // arrives as silence and leaves nothing pending.
      proposing: False,
      target_draft: case proposal {
        // While a proposal is in flight the draft box shows it, so the ghost
        // value and the box agree; otherwise it tracks the accepted target.
        Some(p) -> p.target
        None -> option.unwrap(accepted, model.target_draft)
      },
    )

  #(model, case proposal {
    Some(_) -> watershed_lustre.after(signoff_poll_ms, PollSignoffs)
    None -> effect.none()
  })
}

fn quorum_of(
  previous: Option(Proposal),
  target: String,
  waiting: List(Int),
) -> Int {
  let seen = list.length(waiting)
  case previous {
    Some(p) if p.target == target -> int.max(p.quorum, seen)
    Some(_) | None -> seen
  }
}

fn decode_string(value: Json) -> Result(String, Nil) {
  case json.parse(json.to_string(value), decode.string) {
    Ok(text) -> Ok(text)
    Error(_) -> Error(Nil)
  }
}

/// Toggle one gate. `or_set_contains` reads the optimistic local state, so
/// the toggle is decided against what the user can currently see — and
/// concurrent completion beats a concurrent reopen by the same rule every
/// OR-set add/remove race resolves by: the add's tombstone-clearing wins
/// regardless of which op the kernel happens to apply first.
fn toggle_check(shared: SharedState, id: String) -> Nil {
  case watershed.or_set_contains(shared.checks, id) {
    True -> watershed.or_set_remove(shared.checks, id)
    False -> watershed.or_set_add(shared.checks, id)
  }
}

fn ensure_failed(model: Model, reason: String) -> Model {
  Model(..model, error: Some(reason))
}

/// A signoff list holds the integer ids the kernels tie-break on, derived
/// from the server's client id strings — for floodgate ids that is a stable
/// hash, so it is a long opaque number rather than anything a reader
/// recognises.
///
/// The one entry a reader *can* place is their own, and it is the one that
/// changes what they do: "the room is waiting on you" is actionable, "the
/// room is waiting on client 274880073" is trivia.
fn client_label(model: Model, id: Int) -> String {
  case own_client_id(model) == Some(id) {
    True -> "you"
    False -> "client " <> int.to_string(id)
  }
}

fn own_client_id(model: Model) -> Option(Int) {
  model.doc
  |> option.then(watershed.client_id)
  |> option.map(client_id.to_int)
}

// ── View ─────────────────────────────────────────────────────────────────────

fn view(model: Model) -> Element(Msg) {
  html.div([attribute.class("checklist")], [
    html.h1([], [html.text("Release checklist")]),
    status_view(model),
    gates_view(model),
    captain_view(model),
    release_view(model),
    toolbar(model),
    error_view(model.error),
  ])
}

fn status_view(model: Model) -> Element(Msg) {
  html.p([attribute.class("status")], [
    html.text(case model.status {
      Connecting -> "Connecting…"
      Ready -> "Connected as " <> model.user_id
      Failed(reason) -> "Disconnected: " <> reason
    }),
  ])
}

fn gates_view(model: Model) -> Element(Msg) {
  html.div(
    [
      attribute.class("gates"),
      attribute.role("group"),
      attribute.aria_label("Release gates"),
    ],
    [
      html.ul(
        [attribute.class("gate-list")],
        list.map(gates(), fn(gate) { gate_view(model, gate) }),
      ),
    ],
  )
}

fn gate_view(model: Model, gate: Gate) -> Element(Msg) {
  let done = list.contains(model.completed, gate.id)
  html.li([attribute.class("gate")], [
    html.button(
      [
        attribute.classes([#("gate-toggle", True), #("done", done)]),
        attribute.aria_pressed(bool_to_string(done)),
        event.on_click(CheckToggled(gate.id)),
      ],
      [
        html.span([attribute.class("gate-mark")], [
          html.text(case done {
            True -> "✓"
            False -> "○"
          }),
        ]),
        html.span([attribute.class("gate-label")], [html.text(gate.label)]),
      ],
    ),
  ])
}

/// The captain seat. Its copy is deliberately explicit that this is
/// collaborative coordination, not an access-control decision: anyone reading
/// the code or the network traffic can see nothing in watershed prevents a
/// non-captain client from writing the release target directly.
fn captain_view(model: Model) -> Element(Msg) {
  html.div([attribute.class("captain")], [
    html.p([attribute.class("captain-status")], [
      html.text(case model.captain, model.captain_claim_pending {
        _, True -> "Claiming captain…"
        Some(captain), False if captain == model.user_id ->
          "You are the release captain."
        Some(captain), False -> captain <> " is the release captain."
        None, False -> "No release captain yet."
      }),
    ]),
    captain_action(model),
    html.p([attribute.class("hint")], [
      html.text(
        "The captain seat is a first-writer-wins claim: whoever claims it "
        <> "first holds it until someone takes it over. This coordinates who "
        <> "drafts the release in this UI — it is not an authorization check, "
        <> "and any client could still write the release target directly.",
      ),
    ]),
  ])
}

fn captain_action(model: Model) -> Element(Msg) {
  case model.captain, model.captain_claim_pending {
    _, True -> html.text("")
    None, False ->
      html.button([event.on_click(ClaimCaptainClicked)], [
        html.text("Claim captain"),
      ])
    Some(captain), False if captain == model.user_id -> html.text("")
    Some(_other), False ->
      html.button([event.on_click(TakeoverClicked)], [
        html.text("Take over as captain"),
      ])
  }
}

fn release_view(model: Model) -> Element(Msg) {
  let is_captain = release_readiness.is_captain(model.captain, model.user_id)
  html.div([attribute.class("release")], [
    html.p([attribute.class("release-status")], [
      html.text(case model.target {
        Some(target) -> "Accepted release target: " <> target
        None -> "No release target agreed yet."
      }),
    ]),
    proposal_view(model),
    case is_captain {
      True -> release_form(model)
      False -> html.text("")
    },
  ])
}

fn release_form(model: Model) -> Element(Msg) {
  let ready = release_readiness.all_checks_complete(model.completed, gate_ids())
  let can_propose =
    release_readiness.can_propose(
      True,
      ready,
      model.target_draft,
      option.is_some(model.proposal),
      model.proposing,
    )
  html.div([attribute.class("release-form")], [
    html.label([attribute.class("target-input")], [
      html.span([], [html.text("Release target")]),
      html.input([
        attribute.type_("text"),
        attribute.value(model.target_draft),
        attribute.placeholder("v1.2.3"),
        attribute.aria_label("Release target"),
        attribute.disabled(
          !ready || model.proposing || option.is_some(model.proposal),
        ),
        event.on_input(TargetDrafted),
      ]),
    ]),
    html.button(
      [event.on_click(TargetCommitted), attribute.disabled(!can_propose)],
      [
        html.text("Publish release target"),
      ],
    ),
    case ready {
      True -> html.text("")
      False ->
        html.span([attribute.class("hint")], [
          html.text(
            "Every gate must be checked before a target can be published.",
          ),
        ])
    },
  ])
}

fn proposal_view(model: Model) -> Element(Msg) {
  case model.proposal {
    None -> html.text("")
    Some(proposal) -> {
      let remaining = list.length(proposal.waiting)
      html.p([attribute.class("proposal"), attribute.role("status")], [
        html.text(
          "\""
          <> proposal.target
          <> "\" pending — waiting on "
          <> int.to_string(remaining)
          <> " of "
          <> int.to_string(proposal.quorum)
          <> case proposal.quorum {
            1 -> " client"
            _ -> " clients"
          },
        ),
        html.span([attribute.class("signoffs")], [
          html.text(
            " · "
            <> case proposal.waiting {
              [] -> "settling"
              ids ->
                "not yet acknowledged: "
                <> string.join(
                  list.map(ids, fn(id) { client_label(model, id) }),
                  ", ",
                )
            },
          ),
        ]),
        // Said out loud because the obvious reading of a pending bar is a
        // vote, and it is not one. Nobody is deciding; the runtime
        // auto-submits each client's acknowledgement the moment it sees the
        // proposal.
        html.span([attribute.class("hint")], [
          html.text(
            " Signing off means a client has seen the change, not that it "
            <> "agreed to it — there is nothing to agree to and no way to "
            <> "refuse.",
          ),
        ]),
      ])
    }
  }
}

fn toolbar(model: Model) -> Element(Msg) {
  html.div([attribute.class("toolbar")], [
    html.button([event.on_click(ReconnectClicked)], [
      html.text("Force reconnect"),
    ]),
    html.text(case model.shared {
      Some(_) -> ""
      None -> " · loading checklist…"
    }),
  ])
}

fn error_view(error: Option(String)) -> Element(Msg) {
  case error {
    Some(reason) -> html.p([attribute.class("error")], [html.text(reason)])
    None -> html.text("")
  }
}

fn bool_to_string(value: Bool) -> String {
  case value {
    True -> "true"
    False -> "false"
  }
}
