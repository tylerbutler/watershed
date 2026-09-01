// ──────────────────────────────────────────────────────────────────────────
// watershed — practices catalog
// One entry per technique, each anchored to the ONE checked-in example that
// demonstrates it best. This is the inverse of the old /patterns page: not
// conventions that recur across apps, but one implementation practice paired
// with example code that demonstrates it. Snippets are copied (and trimmed)
// from the example source named in `snippetFile` — keep them in sync when an
// example changes.
//
// Each practice is filed under the /guide step whose work it belongs to, and
// renders as field notes at the foot of that step. /patterns indexes them the
// other way — by problem theme — and `related` surfaces each one on the
// atlas and runtime sheets where its problem shows up.
// ──────────────────────────────────────────────────────────────────────────
import { examples, type Example } from "./examples";
import { steps, type StepSlug } from "./guide";

/** The problem themes /patterns groups by: what you're stuck on, not where
 *  the procedure happens to teach it. */
export const themes = [
  {
    slug: "architecture",
    title: "Architecture & composition",
    blurb:
      "Decide what the shell owns, what a component may touch, and which work must stay outside the app.",
  },
  {
    slug: "conflicts",
    title: "Conflicts & consistency",
    blurb:
      "Two clients change the same state at once. Keep the UI honest while the shared structure settles the result.",
  },
  {
    slug: "coordination",
    title: "Presence & coordination",
    blurb:
      "Some facts belong to the session, not the document: who's here, who drives, and what they need to tell each other.",
  },
  {
    slug: "testing",
    title: "Testing & diagnostics",
    blurb:
      "Reproduce the failures that matter, and read the runtime's own diagnostics before you guess at a sync bug.",
  },
] as const;

export type ThemeSlug = (typeof themes)[number]["slug"];

export interface Practice {
  /** Anchor slug, on the guide step this practice is filed under. */
  id: string;
  /** Section title. */
  title: string;
  /** The build-guide step whose work this practice belongs to. */
  step: StepSlug;
  /** The problem theme /patterns files this under. */
  theme: ThemeSlug;
  /** Routes of the atlas / runtime sheets where this practice's problem
   *  shows up, e.g. "/structures/sequences". Renders a field-notes strip
   *  on those pages. */
  related?: string[];
  /** `Example.id` of the app that demonstrates this practice. */
  example: string;
  /** One-sentence imperative rule. */
  rule: string;
  /** Two or three short paragraphs: why it holds, the failure it prevents. */
  body: string[];
  /** Excerpt adapted from the example's source. */
  snippet: string;
  /** Language of the snippet, for syntax highlighting. */
  snippetLang: "gleam" | "js";
  /** Path of the excerpted file, relative to the example directory. */
  snippetFile: string;
  /** Only for Testing-group patterns: the check that pins the claim. */
  testNote?: string;
}

export const practices: Practice[] = [
  {
    id: "relay-decorator",
    title: "Treat the server as an optional decorator",
    step: "connect",
    theme: "architecture",
    related: ["/runtime/p2p", "/structures/counters"],
    example: "clap_counter_lustre",
    rule: "A peer-to-peer app may use a relay for durability, but it should not need one to start.",
    body: [
      "The clap counter has no sequencer, tenant, or token. If the URL names a relay, one function adds it to the peer-to-peer config.",
      "The app still becomes ready when that relay is down. It reports the outage instead of turning an optional service into a hidden requirement.",
    ],
    snippet: `let config =
  crdt_js.config(
    room_id: room,
    replica_label: "tab",
    compatibility_tag: compatibility,
    root: p2p.pn_counter_root(),
    signaling: signaling,
  )
  |> crdt_js.with_ice_servers(ice_servers())
  |> with_relay

/// Attach the optional relay named by \`?relay=\`, and nothing at all
/// without one. The policy stays \`Auto\` either way: readiness never waits
/// for a relay, so a URL pointing at a service that is down costs a
/// status line and no claps.
fn with_relay(
  config: crdt_js.Config(PnCounterChannel),
) -> crdt_js.Config(PnCounterChannel) {
  case query(relay_param, "") {
    "" -> config
    url -> crdt_js.with_sequencer(config, crdt_js.sequencer(url))
  }
}`,
    snippetLang: "gleam",
    snippetFile: "src/clap_counter_lustre.gleam",
  },
  {
    id: "shared-core-two-runtimes",
    title: "One shared core, two runtimes",
    step: "connect",
    theme: "architecture",
    example: "dice_cli",
    rule: "Keep the shared core portable by connecting to the same document from the BEAM and the browser.",
    body: [
      "dice_cli and dice_lustre edit the same floodgate document. They share the kernel, wire format, and runtime core; only the outer program changes. The browser uses an MVU update function, while the BEAM client uses a receive loop.",
      "The CLI connects to 127.0.0.1 instead of localhost. Erlang's resolver stalls about eight seconds on the AAAA lookup, long enough for the server to drop the connection.",
    ],
    snippet: `fn event_loop(
  map: watershed_beam.SharedMap,
  selector: process.Selector(CliMsg),
  roll_due: process.Subject(Nil),
) -> Nil {
  case process.selector_receive_forever(selector) {
    MapChanged(event) -> {
      print_event(event)
      print_snapshot(map)
      event_loop(map, selector, roll_due)
    }
    RollDue -> {
      roll(map)
      schedule_roll(roll_due, roll_interval_milliseconds)
      event_loop(map, selector, roll_due)
    }
  }
}`,
    snippetLang: "gleam",
    snippetFile: "src/dice_cli.gleam",
  },
  {
    id: "diagnostics-first",
    title: "Sample diagnostics on every event",
    step: "connect",
    theme: "testing",
    related: ["/runtime/optimistic", "/runtime/reconnect"],
    example: "dice_lustre",
    rule: "Put the runtime's diagnostics on screen before you debug synchronization.",
    body: [
      "The smallest browser example updates one diagnostics line after every event. It shows the connection phase, client id, sequence numbers, queued operations, and resubmit checkpoint.",
      "Those values tell you where to look. A stuck in_flight count, a growing buffer, and a connection that never reaches synced point to different problems that application state cannot show.",
    ],
    snippet: `fn diagnostic_line(diagnostics: watershed.Diagnostics) -> String {
  "phase="
  <> diagnostics.phase
  <> " client="
  <> option.unwrap(diagnostics.client_id, "none")
  <> " sn="
  <> option_int(diagnostics.last_seen_sequence_number)
  <> " next_csn="
  <> option_int(diagnostics.next_client_sequence_number)
  <> " in_flight="
  <> int.to_string(diagnostics.in_flight_count)
  <> " buffered="
  <> int.to_string(diagnostics.buffered_out_of_order_count)
  <> " resubmit_at="
  <> option_int(diagnostics.resubmit_checkpoint)
  <> " synced="
  <> bool_to_string(diagnostics.synced)
}`,
    snippetLang: "gleam",
    snippetFile: "src/dice_lustre.gleam",
  },
  {
    id: "quorum-pending-roster",
    title: "Propose on release, render the pending signoff",
    step: "votes",
    theme: "conflicts",
    related: ["/structures/coordination", "/runtime/optimistic"],
    example: "drum_machine_lustre",
    rule: "Send one consensus proposal per gesture, then show whose approval is still missing.",
    body: [
      "A PactMap stores the tempo and accepts a change after every connected client approves it. The slider sends its proposal on release. Sending one on every pointer move would overwhelm a protocol that allows only one pending proposal.",
      "While the group decides, the UI disables the slider and names the clients that have not approved. A short poll catches changes that the kernel does not report as events.",
    ],
    snippet: `// Propose on release, never per pointer move. A \`pact_map_set\` per frame
// would flood the protocol with proposals that invalidate each other —
// \`apply_set\` rejects a proposal made while one is pending — so a dragged
// slider would land on whichever frame happened to arrive between pacts.
BpmCommitted ->
  case model.shared, tempo_locked(model), model.bpm_draft == model.bpm {
    Some(shared), False, False -> {
      watershed.pact_map_set(
        shared.settings,
        bpm_key,
        json.int(model.bpm_draft),
      )
      // Poll rather than wait for an event, because a proposal the kernel
      // *rejects* — one made while a peer's is already pending — emits
      // nothing at all. Without this tick the control would stay disabled
      // forever on a rejection.
      #(
        Model(..model, proposing: True),
        watershed_lustre.after(signoff_poll_milliseconds, PollSignoffs),
      )
    }
    _, _, _ -> #(model, effect.none())
  }`,
    snippetLang: "gleam",
    snippetFile: "src/drum_machine_lustre.gleam",
  },
  {
    id: "realtime-out-of-band",
    title: "Keep latency-critical loops out of the update path",
    step: "presence",
    theme: "architecture",
    example: "drum_machine_lustre",
    rule: "Let a real-time loop read a plain snapshot. Do not make it wait on the application.",
    body: [
      "The audio engine runs in an FFI module. Every 25 ms, it schedules the steps due in the next 100 ms against the audio clock. Gleam pushes pattern updates into a plain array, so document delays cannot become audio jitter.",
      "Background tabs create another trap: browsers slow timers while the audio clock keeps moving. When the tab returns, the scheduler resets its timing instead of playing every missed step at once.",
    ],
    snippet: `function tick(engine) {
  const ctx = engine.ctx;
  if (ctx === null || !engine.playing) return;

  // Browsers throttle \`setInterval\` to about once a second in a background
  // tab, while the audio clock keeps running. Without this the next tick would
  // "catch up" by scheduling a second of steps whose times have already
  // passed, and Web Audio plays a past-dated start immediately — so returning
  // to the tab is greeted by a burst of every step it missed. Resync instead,
  // keeping the step index continuous so the pattern resumes in place.
  if (engine.nextStepTime < ctx.currentTime) {
    engine.nextStepTime = ctx.currentTime;
    engine.queue = [];
  }

  const horizon = ctx.currentTime + SCHEDULE_AHEAD_S;
  while (engine.nextStepTime < horizon) {
    scheduleStep(engine, engine.nextStep, engine.nextStepTime);
    engine.queue.push({ step: engine.nextStep, time: engine.nextStepTime });
    // Read the duration per step, so a tempo change mid-bar takes effect on
    // the next step rather than at the end of the loop.
    engine.nextStepTime += stepDuration(engine);
    engine.nextStep = (engine.nextStep + 1) % STEP_COUNT;
  }
}`,
    snippetLang: "js",
    snippetFile: "src/drum_machine_lustre/audio_ffi.mjs",
  },
  {
    id: "presence-idiom",
    title: "The minimal presence idiom",
    step: "presence",
    theme: "coordination",
    related: ["/runtime/presence"],
    example: "retro_tutorial_lustre",
    rule: "Declare one presence effect, use one typed payload, and remove the local session before the roster enters your model.",
    body: [
      "The tutorial retro board shows the smallest complete presence setup. One effect starts the driver with an encoder and decoder. A helper removes the local session from the roster before the app stores it.",
      "watershed includes the local session on purpose; each app decides whether to show it. The richer cursors and avatar lists in other examples use the same setup with more data.",
    ],
    snippet: `fn presence_effect(
  model: Model,
  document: Document(document_schema.BoardDocument),
) -> Effect(Msg) {
  watershed_lustre.presence(
    document: document,
    config: presence.config(encode_presence, presence_decoder()),
    initial: current_presence(model),
    started: PresenceStarted,
    on_event: PresenceEvent,
  )
}

fn remote_peers(
  model: Model,
  entries: List(presence.PresenceEntry(BoardPresence)),
) -> List(presence.PresenceEntry(BoardPresence)) {
  case model.presence {
    Some(handle) ->
      case presence_js.local_session(handle) {
        Some(session) -> presence.remote_entries(entries, session)
        None -> entries
      }
    None -> entries
  }
}`,
    snippetLang: "gleam",
    snippetFile: "src/retro_tutorial_lustre.gleam",
  },
  {
    id: "protocol-on-ripples",
    title: "Ride an application protocol on ripples",
    step: "presence",
    theme: "coordination",
    related: ["/runtime/presence"],
    example: "grocery_triptych_lustre",
    rule: "Send short-lived coordination over ripples, not through a document channel.",
    body: [
      "The triptych's guided scenarios ask two tabs to choose a driver and exchange invitations, acknowledgements, and status updates. Ripples deliver those messages with a run id, and the document stores none of them.",
      "Plain functions match runs, ignore the sender's own messages, choose acknowledgements, and reject unknown message types. That keeps the protocol testable without a server.",
    ],
    snippet: `pub fn matches_run(expected_run_id: String, inbound: Inbound) -> Bool {
  run_id(inbound.message) == expected_run_id
}

pub fn from_self(self_id: String, inbound: Inbound) -> Bool {
  inbound.from_peer == self_id
}

pub fn should_acknowledge(
  self_id: String,
  ready: Bool,
  busy: Bool,
  already_seen: Bool,
  inbound: Inbound,
) -> Bool {
  case inbound.message {
    Invitation(_) ->
      ready && !busy && !already_seen && !from_self(self_id, inbound)
    Acknowledgement(_) -> False
    Go(_, _) -> False
    Status(_, _, _) -> False
  }
}`,
    snippetLang: "gleam",
    snippetFile: "src/grocery_triptych_lustre/scenario_protocol.gleam",
  },
  {
    id: "pure-modules",
    title: "Extract pure modules; test without a server",
    step: "testing",
    theme: "testing",
    example: "grocery_triptych_lustre",
    rule: "Move decisions into pure modules so most tests need no document, sluice, or server.",
    body: [
      "The triptych separates decisions from effects. Its protocol, scenario state, and guards run as ordinary unit tests. The small refresh guard below uses a generation counter to discard an old refresh after a newer one arrives.",
      "Convergence and browser tests still cover behavior that needs a runtime. They stay small because pure tests cover the decision branches.",
    ],
    snippet: `pub type State {
  State(current_generation: Int, pending: Bool)
}

pub fn idle() -> State {
  State(current_generation: 0, pending: False)
}

pub fn request(state: State) -> #(State, Int) {
  let generation = state.current_generation + 1

  #(State(current_generation: generation, pending: True), generation)
}

pub fn flush(state: State, generation: Int) -> #(State, Bool) {
  case state.pending && state.current_generation == generation {
    True -> #(
      State(current_generation: state.current_generation, pending: False),
      True,
    )
    False -> #(state, False)
  }
}`,
    snippetLang: "gleam",
    snippetFile: "src/grocery_triptych_lustre/refresh_guard.gleam",
    testNote:
      "Six test files (protocol, scenario state, guards, actions) run pure, alongside one sluice convergence file and the smoke tier.",
  },
  {
    id: "ffi-surface",
    title: "Hand a rendering surface to FFI, and bootstrap on Connected",
    step: "connect",
    theme: "architecture",
    related: ["/foundations/lifecycle"],
    example: "pixel_canvas_lustre",
    rule: "Let an FFI module own the canvas pixels, and create shared channels only after the connection opens.",
    body: [
      "Lustre renders an empty canvas; an FFI module owns its byte buffer and 2D context. The view keeps the canvas size fixed because changing it erases the pixels. The FFI module looks up the context when it needs it, so mount order does not need another effect.",
      "The app creates its shared channel after Connected, not after GotHandle. A handle can resolve before the connection is ready, which would leave the app painting a canvas that no peer can see.",
    ],
    snippet: `Connected(Ok(_)) ->
  case model.document {
    None -> #(Model(..model, status: Ready), effect.none())
    Some(document) -> {
      let #(canvas, canvas_effect) =
        component.init(document, watershed.root_typed(document))
      #(
        Model(..model, status: Ready, canvas: Some(canvas)),
        effect.map(canvas_effect, Canvas),
      )
    }
  }
Connected(Error(reason)) -> #(
  Model(..model, status: Failed(reason), last_error: Some(reason)),
  effect.none(),
)`,
    snippetLang: "gleam",
    snippetFile: "src/pixel_canvas_lustre.gleam",
  },
  {
    id: "fallible-edits",
    title: "Fallible edits render; never assert on a mutation",
    step: "notes",
    theme: "conflicts",
    related: ["/structures/sequences", "/runtime/optimistic"],
    example: "playlist_lustre",
    rule: "Handle every index-based edit as fallible. A peer may change the list between render and click.",
    body: [
      "A remote insert or delete can make a rendered index stale before the user clicks. The playlist sends every sequence edit through one helper and shows the runtime error in a banner instead of asserting success.",
      "The runtime refuses an index outside the list. It does not clamp the index, because that could move or delete the wrong track.",
    ],
    snippet: `MoveDownClicked(index) -> #(
  mutate(model, "move", fn(sequence) {
    watershed.sequence_move(sequence, index, index + 1)
  }),
  effect.none(),
)

/// Run a sequence edit against the resolved channel, recording any index error.
fn mutate(
  model: Model,
  verb: String,
  edit: fn(SharedSequence) -> Result(Nil, String),
) -> Model {
  case model.tracks_channel {
    None -> model
    Some(sequence) -> record(model, edit(sequence), verb)
  }
}

/// Fold an edit result into the model: clear the banner on success, surface the
/// runtime's own message on failure.
fn record(model: Model, result: Result(Nil, String), verb: String) -> Model {
  case result {
    Ok(Nil) -> Model(..model, last_error: None)
    Error(reason) ->
      Model(..model, last_error: Some(verb <> " failed: " <> reason))
  }
}`,
    snippetLang: "gleam",
    snippetFile: "src/playlist_lustre/component.gleam",
  },
  {
    id: "authoritative-channel",
    title: "When a move is not atomic, crown one channel authoritative",
    step: "notes",
    theme: "conflicts",
    related: ["/structures/sequences", "/structures/coordination"],
    example: "retro_board_lustre",
    rule: "A move across channels is not atomic. Choose one source of truth and reconcile the rest while rendering.",
    body: [
      "Dragging a sticky note takes three operations across two channel types. The note's column field decides where it belongs. The view skips an id in the wrong column, puts missing ids at the end, and sends unknown columns to an unfiled strip.",
      "The view does not write repairs. If every client tried to clean up while rendering, they could fight over more operations. The next user move removes the stale id from the other columns.",
    ],
    snippet: `/// One column: the sequenced head in sequence order, then the unsequenced
/// tail in \`(created, id)\` order.
fn render_column(
  column: Column,
  ids: List(String),
  notes: List(#(String, Note)),
  notes_by_id: Dict(String, Note),
  votes_by_id: Dict(String, Int),
) -> List(NoteCard) {
  let column_id = column.id(column)
  // Sequenced head: keep an id only if its note exists (a deleted note's
  // sequence entry dies here), its register matches this column, and this is
  // its first occurrence in the sequence.
  let #(head, kept) =
    ids
    |> list.index_map(fn(id, index) { #(id, index) })
    |> list.fold(#([], dict.new()), fn(acc, entry) {
      let #(cards, kept) = acc
      let #(id, index) = entry
      case dict.has_key(kept, id), dict.get(notes_by_id, id) {
        False, Ok(n) if n.column == column_id -> #(
          [card(id, n, votes_by_id, Some(index)), ..cards],
          dict.insert(kept, id, Nil),
        )
        _, _ -> acc
      }
    })
  let head = list.reverse(head)
  // Unsequenced tail: notes claiming this column that the head did not keep.
  let tail =
    notes
    |> list.filter(fn(entry) {
      entry.1.column == column_id && !dict.has_key(kept, entry.0)
    })
    |> list.sort(by_created_then_id)
    |> list.map(fn(entry) { card(entry.0, entry.1, votes_by_id, None) })
  list.append(head, tail)
}`,
    snippetLang: "gleam",
    snippetFile: "src/retro_board_lustre/board.gleam",
  },
  {
    id: "stamp-schema",
    title: "Stamp the schema; refuse bad reads",
    step: "notes",
    theme: "architecture",
    related: ["/structures/maps", "/foundations/schema"],
    example: "scoreboard_cli",
    rule: "Fill and stamp a typed map before attaching it, so an incompatible reader gets an error.",
    body: [
      "The scoreboard has a root map, a roster, and one typed child map for each player. It fills a new player map in one write, stamps the schema version, then attaches the map to the roster.",
      "That stamp protects future readers from decoding the map with the wrong schema. Child lookup also retries because a remote handle may arrive before the operation that attaches its map.",
    ],
    snippet: `// Our own player map: populated while detached (local-only), then
// attached — snapshot and all — by storing its handle in the roster.
// A single \`write\` fills every key; \`stamp\` records the schema version.
use me <- result.try(watershed_beam.create_typed_map(document))
use schema <- result.try(
  player_schema() |> result.map_error(fn(_) { "Schema build failed" }),
)
watershed_beam.write(
  me,
  schema,
  PlayerState(name: player_id, last_roll: None, total: 0, rolls: 0),
)
watershed_beam.stamp(me, schema)
watershed_beam.set_child(roster, player_slot(player_id), me)

let roll_due = process.new_subject()
let selector =
  process.new_selector()
  |> process.select_map(watershed_beam.subscribe_typed(roster), RosterChanged)
  |> process.select_map(watershed_beam.subscribe_typed(me), ScoreChanged)
  |> process.select_map(roll_due, fn(_) { RollDue })`,
    snippetLang: "gleam",
    snippetFile: "src/scoreboard_cli.gleam",
  },
  {
    id: "typedmap-panels",
    title: "Panels take a TypedMap, never a root",
    step: "connect",
    theme: "architecture",
    related: ["/structures/maps", "/foundations/topology"],
    example: "showcase_lustre",
    rule: "Give a reusable component a typed map, whether that map is a root or a child. Keep document-wide effects in the shell.",
    body: [
      "The showcase mounts four examples as panels in one document. Each panel accepts a TypedMap and cannot tell whether it received the root or a child map. The shell creates one child field for each panel.",
      "The shell also owns presence, offline mode, and summary policy because they affect the whole document. If panels started their own copies, presence messages could mix and the panels could compete over one shared setting.",
    ],
    snippet: `/// Every tab runs this unconditionally. \`ensure_child\` creates a map only if
/// the key is absent, so two tabs opening a *cold* document can both create one
/// and LWW settles a single handle — the loser is orphaned before anybody has
/// interacted with it, and every tab converges on the same four handles.
fn bootstrap_effect(document: Document(document_schema.Showcase)) -> Effect(Msg) {
  let root = watershed.root_typed(document)
  effect.batch([
    watershed_lustre.auto_summarize(
      document: document,
      policy: summary_policy.policy()
        |> summary_policy.with_threshold(summary_threshold),
    ),
    watershed_lustre.ensure_child(document, root, document_schema.text(), EnsuredText),
    watershed_lustre.ensure_child(
      document,
      root,
      document_schema.playlist(),
      EnsuredPlaylist,
    ),
    watershed_lustre.ensure_child(document, root, document_schema.sudoku(), EnsuredSudoku),
    watershed_lustre.ensure_child(document, root, document_schema.canvas(), EnsuredCanvas),
  ])
}`,
    snippetLang: "gleam",
    snippetFile: "src/showcase_lustre.gleam",
  },
  {
    id: "claims-seeding",
    title: "Seed idempotently with Claims",
    step: "connect",
    theme: "conflicts",
    related: ["/structures/coordination", "/foundations/lifecycle"],
    example: "sudoku_lustre",
    rule: "Let every client seed the same initial values through first-writer-wins claims.",
    body: [
      "Every Sudoku client runs the same loop over the given cells. claim_once keeps the first value for each cell and ignores later attempts, so the clients settle on one puzzle without electing an initializer.",
      "Use this for initial values that must be written once. The shared structure settles duplicate work, so the app needs no separate setup protocol.",
    ],
    snippet: `fn seed_givens(
  claims: Claims,
  active_puzzle: Puzzle,
  row: Int,
  column: Int,
) -> Nil {
  case row >= 9 {
    True -> Nil
    False -> {
      let given = puzzle.given_at(active_puzzle, row, column)
      case given > 0 {
        True -> {
          let _ =
            watershed.claim_once(claims, cell_key(row, column), json.int(given))
          Nil
        }
        False -> Nil
      }
      case column == 8 {
        True -> seed_givens(claims, active_puzzle, row + 1, 0)
        False -> seed_givens(claims, active_puzzle, row, column + 1)
      }
    }
  }
}`,
    snippetLang: "gleam",
    snippetFile: "src/sudoku_lustre/component.gleam",
  },
  {
    id: "anchors-not-offsets",
    title: "Anchors, not offsets",
    step: "notes",
    theme: "conflicts",
    related: ["/structures/sequences"],
    example: "text_lustre",
    rule: "Store an anchor instead of a text offset, then resolve its current position after each edit.",
    body: [
      "The editor turns each input into a small insert, delete, or replace. Remote edits would make saved integer positions stale, so bookmarks, carets, and shared cursors all use anchors that resolve to the current grapheme index.",
      "Anchor bias decides which nearby text a caret or selection follows as edits arrive. If an anchor no longer resolves, the app removes the marker instead of guessing.",
    ],
    snippet: `/// Resolve the pinned anchor to its current grapheme position, or drop it to
/// \`None\` if it has gone stale/unknown.
fn refresh_anchor(model: Model) -> Model {
  case model.editor, model.anchor {
    Some(editor), Some(anchor) ->
      case watershed.text_resolve_anchor(textarea.channel(editor), anchor) {
        Ok(position) -> Model(..model, anchor_pos: Some(position))
        Error(_) -> Model(..model, anchor_pos: None)
      }
    _, _ -> Model(..model, anchor_pos: None)
  }
}`,
    snippetLang: "gleam",
    snippetFile: "src/text_lustre/component.gleam",
  },
  {
    id: "unsettled-writes",
    title: "Show writes that have not settled",
    step: "votes",
    theme: "conflicts",
    related: ["/structures/coordination", "/runtime/optimistic"],
    example: "tournament_bracket_lustre",
    rule: "When writes are not optimistic, show them as pending until the confirming event arrives.",
    body: [
      "A RegisterCollection stores each match result under the Atomic policy, which chooses one compare-and-swap winner. Local writes stay hidden until the server orders them, so the bracket shows a submitted result as awaiting confirmation.",
      "VersionChanged reports every ordered submission, including the ones that lose. AtomicChanged reports only the winner and updates the official bracket. The log keeps the competing reports visible.",
    ],
    snippet: `ReportClicked(match_key, winner) ->
  case model.matches {
    None -> #(model, effect.none())
    Some(matches) -> {
      let score =
        dict.get(model.score_drafts, match_key)
        |> option.from_result
        |> option.unwrap("")
      let value = bracket.to_json(MatchResult(winner:, score:))
      watershed.register_write(matches, match_key, value)
      #(
        Model(..model, pending: set.insert(model.pending, match_key)),
        effect.none(),
      )
    }
  }

// ... and in the register event handler:
AtomicChanged(key, value, _local) -> {
  let result = bracket.from_json(value)
  Model(
    ..model,
    results: dict.insert(model.results, key, result),
    pending: set.delete(model.pending, key),
  )
  |> log_line(key <> " official result: " <> result.winner)
}`,
    snippetLang: "gleam",
    snippetFile: "src/tournament_bracket_lustre.gleam",
  },
  {
    id: "deterministic-death",
    title: "Test client death deterministically",
    step: "testing",
    theme: "testing",
    related: ["/structures/coordination", "/runtime/reconnect"],
    example: "work_queue_lustre",
    rule: "Test a client dying mid-job with an in-process disconnect that produces the same leave event as the server.",
    body: [
      "The work queue promises to recover when a client disappears. If a worker dies, the job returns to the queue. If the dispatcher dies, the next client takes over. An automated test needs to prove both transitions.",
      "sluice_js.disconnect produces the same leave event that the server would, so the test runs in process and on demand. A live smoke test covers the remaining boundary: whether floodgate notices a vanished socket and sends that event.",
    ],
    snippet: `pub fn held_job_returns_to_queue_when_holder_disconnects_test() {
  let #(sluice, document_a, document_b) = room("wq-worker-dies")
  let queue_a = queue_of(document_a)
  let queue_b = queue_of(document_b)
  let payload = job("doomed")

  watershed.ordered_add(queue_a, payload)
  sluice_js.settle(sluice)

  let events_b = queue_events(queue_b)
  let #(outcomes_a, id_a) = outcome_cell(queue_a)
  sluice_js.settle(sluice)
  transport_js.get_cell(outcomes_a)
  |> should.equal([AcquiredItem(id_a, payload)])

  // The tab holding the job goes away without completing or releasing.
  sluice_js.disconnect(sluice, document_a)
  sluice_js.settle(sluice)

  transport_js.get_cell(events_b)
  |> list.contains(ordered_collection_kernel.Added(payload, False, False))
  |> should.be_true()
  watershed.ordered_queue(queue_b) |> should.equal([payload])
  watershed.ordered_jobs(queue_b) |> should.equal([])
}`,
    snippetLang: "gleam",
    snippetFile: "test/queue_semantics_test.gleam",
    testNote:
      "The same harness asserts a dispatcher promotion arrives as a queue event, not an assignment, pinning the event shape of recovery rather than just its outcome.",
  },
];

const exampleById = new Map<string, Example>(examples.map((e) => [e.id, e]));

// The two CLI examples live in the repo but not in the browser-example
// catalog, so they carry their display names here.
const cliExampleNames: Record<string, string> = {
  dice_cli: "Dice CLI",
  scoreboard_cli: "Scoreboard CLI",
};

/** The catalog entry the practice is anchored to, if it is a browser example. */
export function exampleForPractice(practice: Practice): Example | null {
  return exampleById.get(practice.example) ?? null;
}

/** Display name for the anchoring example, catalog or not. */
export function practiceExampleName(practice: Practice): string {
  const name =
    exampleForPractice(practice)?.name ?? cliExampleNames[practice.example];
  if (!name) {
    throw new Error(
      `practice ${practice.id} names unknown example ${practice.example}`,
    );
  }
  return name;
}

/** GitHub link to the excerpted file inside the example. */
export function practiceSourceUrl(practice: Practice): string {
  return `https://github.com/tylerbutler/watershed/tree/main/examples/${practice.example}/${practice.snippetFile}`;
}

/** example id → the practices it demonstrates, for /examples chips. */
export const practicesByExample: Record<string, Practice[]> = {};
for (const practice of practices) {
  (practicesByExample[practice.example] ??= []).push(practice);
}

/** guide step slug → the practices filed under it, in catalog order. */
export const practicesByStep: Record<StepSlug, Practice[]> = Object.fromEntries(
  steps.map((step) => [
    step.slug,
    practices.filter((practice) => practice.step === step.slug),
  ]),
) as Record<StepSlug, Practice[]>;

/** Deep link to a practice, on the guide step that renders it. */
export function practiceHref(practice: Practice): string {
  return `/guide/${practice.step}#${practice.id}`;
}

/** theme slug → the practices filed under it, in catalog order. */
export const practicesByTheme: Record<ThemeSlug, Practice[]> = Object.fromEntries(
  themes.map((theme) => [
    theme.slug,
    practices.filter((practice) => practice.theme === theme.slug),
  ]),
) as Record<ThemeSlug, Practice[]>;

/** The practice with this id, for inline field-note callouts. Throws at build
 *  time on a stale id, so a renamed practice cannot leave a dead callout. */
export function practiceById(id: string): Practice {
  const practice = practices.find((p) => p.id === id);
  if (!practice) {
    throw new Error(`no practice with id ${id}`);
  }
  return practice;
}

/** The practices whose problem shows up on the given sheet route, e.g.
 *  "/structures/sequences" — for the field-notes strip on atlas and runtime
 *  pages. */
export function relatedPractices(page: string): Practice[] {
  return practices.filter((practice) => practice.related?.includes(page));
}
