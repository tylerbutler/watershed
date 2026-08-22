// ──────────────────────────────────────────────────────────────────────────
// watershed — practices catalog
// One entry per technique, each anchored to the ONE checked-in example that
// demonstrates it best. This is the inverse of the old /patterns page: not
// conventions that recur across apps, but the specific thing each app was
// built to prove, with the code that proves it. Snippets are copied (and
// trimmed) from the example source named in `snippetFile` — keep them in
// sync when an example changes.
//
// Each practice is filed under the /guide step whose work it belongs to, and
// renders as field notes at the foot of that step. /patterns is the index over
// all of them, not their home.
// ──────────────────────────────────────────────────────────────────────────
import { examples, type Example } from "./examples";
import { steps, type StepSlug } from "./guide";

export interface Practice {
  /** Anchor slug, on the guide step this practice is filed under. */
  id: string;
  /** Section title. */
  title: string;
  /** The build-guide step whose work this practice belongs to. */
  step: StepSlug;
  /** `Example.id` of the app that demonstrates this practice. */
  example: string;
  /** One-sentence imperative rule. */
  rule: string;
  /** Two or three short paragraphs: why it holds, the failure it prevents. */
  body: string[];
  /** Verbatim excerpt from the example's source. */
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
    title: "Keep the relay optional",
    step: "connect",
    example: "clap_counter_lustre",
    rule: "For peer-to-peer applications, add durability through optional configuration. Do not make readiness depend on the relay.",
    body: [
      "The clap counter uses the state-based CRDT stack without a sequencer, tenant, or token. The application adds a relay only when the URL specifies one. One configuration function adds the relay.",
      "The readiness policy remains Auto. If the relay is unavailable, the application reports its status and continues over WebRTC. This behavior verifies that peer-to-peer mode does not require a server.",
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
    example: "dice_cli",
    rule: "Join the same document from an OTP actor and a browser tab to verify core portability.",
    body: [
      "dice_cli is an Erlang-target client for the same floodgate document dice_lustre edits from a browser. The kernel, wire format, and runtime core are the same modules; only the transport shell differs. On the BEAM the app is a recursive receive loop over one selector instead of an MVU update function.",
      "The pair also documents a deployment issue. Connect to 127.0.0.1 instead of localhost. Erlang can resolve IPv6 first and delay the connection until the server drops the idle socket.",
    ],
    snippet: `fn event_loop(
  map: watershed.SharedMap,
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
      schedule_roll(roll_due, roll_interval_ms)
      event_loop(map, selector, roll_due)
    }
  }
}`,
    snippetLang: "gleam",
    snippetFile: "src/dice_cli.gleam",
  },
  {
    id: "diagnostics-first",
    title: "Read diagnostics on every event",
    step: "connect",
    example: "dice_lustre",
    rule: "Display runtime diagnostics before you diagnose a synchronization error.",
    body: [
      "The smallest browser example keeps a diagnostics line on screen and refreshes it on every event: connection phase, client ID, last-seen sequence number, in-flight and buffered operation counts, and the resubmit checkpoint. The README explains how to use each field during diagnosis.",
      "Include these fields in a synchronization error report. A fixed in_flight count, an increasing buffered count, or a phase that does not reach synced identifies a different runtime layer. Application state does not show these conditions.",
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
  <> bool_string(diagnostics.synced)
}`,
    snippetLang: "gleam",
    snippetFile: "src/dice_lustre.gleam",
  },
  {
    id: "quorum-pending-roster",
    title: "Submit on release and show pending signoffs",
    step: "structures",
    example: "drum_machine_lustre",
    rule: "Submit one consensus proposal when the gesture ends. Show which clients have not signed off.",
    body: [
      "A PactMap stores the tempo. Each connected client must sign off before a change is accepted. The slider submits one proposal on release. It does not submit a proposal for each pointer movement because the protocol rejects a second proposal while one is pending.",
      "The interface shows the pending signoff roster and disables the control. A poll detects transitions that the kernel does not report. The interface uses the same client ID derivation as the kernels to identify the local client.",
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
        watershed_lustre.after(signoff_poll_ms, PollSignoffs),
      )
    }
    _, _, _ -> #(model, effect.none())
  }`,
    snippetLang: "gleam",
    snippetFile: "src/drum_machine_lustre.gleam",
  },
  {
    id: "realtime-out-of-band",
    title: "Keep real-time loops outside the update path",
    step: "ripples",
    example: "drum_machine_lustre",
    rule: "Send a plain state snapshot to the real-time loop. Do not make the loop call the application.",
    body: [
      "The audio engine is an FFI module running a lookahead scheduler: a 25 ms interval schedules every step falling inside the next 100 ms against the audio clock. It reads a mutable pattern array that Gleam pushes updates into. If the scheduler had to ask the application for the pattern, document latency would become audio jitter.",
      "Browsers throttle timers in background tabs while the audio clock continues. A scheduler that processes all missed steps would play them together when the tab returns. The tick resynchronizes with the audio clock instead.",
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
    snippetFile: "src/audio_ffi.mjs",
  },
  {
    id: "presence-idiom",
    title: "Declare only required presence data",
    step: "ripples",
    example: "flowboard_lustre",
    rule: "Declare one presence effect with a typed payload. Remove the local session before the roster enters application state.",
    body: [
      "Flowboard is the guide application. One effect declares the presence driver with an encoder and decoder. The roster callback removes the local session before it updates the model.",
      "Presence state includes the local session by design. The application removes that session once at the boundary. Other examples use the same structure with larger cursor or avatar payloads.",
    ],
    snippet: `fn presence_effect(
  model: Model,
  doc: Document(doc_schema.Board),
) -> Effect(Msg) {
  watershed_lustre.presence(
    document: doc,
    config: presence.config(encode_presence, presence_decoder()),
    initial: BoardPresence(card: model.focus),
    started: PresenceStarted,
    on_event: PresenceEvent,
  )
}

/// Everyone but this teammate. Presence state includes the local session by
/// design, so the roster is filtered here rather than in the driver.
fn remote_entries(
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
    snippetFile: "src/flowboard_lustre.gleam",
  },
  {
    id: "protocol-on-ripples",
    title: "Send temporary coordination through ripples",
    step: "ripples",
    example: "grocery_triptych_lustre",
    rule: "Send session-only coordination in a typed ripple envelope. Do not store it in a document channel.",
    body: [
      "The triptych scenarios coordinate two tabs with an invitation, acknowledgment, start signal, and status updates. Ripples carry these messages in a typed envelope with a run ID. The messages do not change durable state and do not remain after the browsing session.",
      "The envelope module uses pure functions for run matching, local-message filtering, acknowledgment selection, and unknown-type rejection. Tests can verify this protocol without a server.",
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
    _ -> False
  }
}`,
    snippetLang: "gleam",
    snippetFile: "src/scenario_protocol.gleam",
  },
  {
    id: "pure-modules",
    title: "Extract pure modules and test without a server",
    step: "testing",
    example: "grocery_triptych_lustre",
    rule: "Move decision logic from update into pure modules. Test most decisions without a document, sluice, or server.",
    body: [
      "The triptych has about one thousand lines of pure protocol, scenario-state, and guard tests. The application separates decision logic from side effects. The 23-line refresh guard below uses a generation counter to drop stale combined refreshes.",
      "Unit tests cover each decision branch. Convergence and browser smoke tests cover only behavior that requires those environments.",
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
    snippetFile: "src/refresh_guard.gleam",
    testNote:
      "Seven test files (protocol, scenario state, guards, actions) run pure, alongside a much smaller sluice and smoke tier.",
  },
  {
    id: "ffi-surface",
    title: "Let FFI control the canvas and initialize after connection",
    step: "ui",
    example: "pixel_canvas_lustre",
    rule: "Let one FFI module control the canvas pixels. Run ensure_* only after the connection handshake.",
    body: [
      "Lustre renders the canvas as an element without children. An FFI module controls the byte buffer and 2D context. Keep the width and height static because rewriting either attribute clears the surface. Resolve the context on each call so that the application does not need a mount-order effect.",
      "Run initialization only in the Connected branch. GotHandle occurs before the connection is ready. Attaching a channel requires a ready connection. Resolving a handle does not. If ensure_* runs early, the application can draw local pixels before it shares them.",
    ],
    snippet: `Connected(Ok(_)) ->
  case model.doc {
    None -> #(Model(..model, status: Ready), effect.none())
    Some(doc) -> {
      let #(canvas, canvas_effect) =
        component.init(doc, watershed.root_typed(doc))
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
    title: "Show edit errors and do not assert on mutations",
    step: "ui",
    example: "playlist_lustre",
    rule: "Handle the Result from each index-based edit. A peer can delete the row before the local click.",
    body: [
      "Sequence insert, move, replace, and delete operations can fail because a displayed index can become stale before a click. The playlist sends each edit through one helper. The helper displays the runtime error in a banner. The application does not unwrap mutations with an assert.",
      "The API rejects an out-of-bounds edit instead of changing the index. Changing the index could reorder the wrong element. The application can display the rejection.",
    ],
    snippet: `MoveDownClicked(index) -> #(
  mutate(model, "move", fn(seq) {
    watershed.sequence_move(seq, index, index + 1)
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
    title: "Use one authoritative channel for non-atomic moves",
    step: "schema",
    example: "retro_board_lustre",
    rule: "A cross-channel move cannot be transactional, so pick the channel that wins and reconcile at render time.",
    body: [
      "Moving a sticky note uses three operations across two channel types without a transaction. The board treats the note's column register as authoritative. The view skips an ID in the wrong column sequence. It places a note that is missing from its sequence at the end by creation time. It sends unknown columns to an unfiled area.",
      "The application leaves stale sequence entries in place. If every render sent correction operations, clients could send conflicting repairs. The next user action removes the ID from sequences where it no longer belongs.",
    ],
    snippet: `/// One column: the sequenced head in sequence order, then the unsequenced
/// tail in \`(created, id)\` order.
fn render_column(
  col: Column,
  ids: List(String),
  notes: List(#(String, Note)),
  notes_by_id: Dict(String, Note),
  votes_by_id: Dict(String, Int),
) -> List(NoteCard) {
  let col_id = column.id(col)
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
        False, Ok(n) if n.column == col_id -> #(
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
      entry.1.column == col_id && !dict.has_key(kept, entry.0)
    })
    |> list.sort(by_created_then_id)
    |> list.map(fn(entry) { card(entry.0, entry.1, votes_by_id, None) })
  list.append(head, tail)
}`,
    snippetLang: "gleam",
    snippetFile: "src/board.gleam",
  },
  {
    id: "stamp-schema",
    title: "Stamp the schema and reject invalid reads",
    step: "schema",
    example: "scoreboard_cli",
    rule: "Initialize a detached typed map in one write. Stamp its schema version before attachment so that reads reject incompatible layouts.",
    body: [
      "The scoreboard uses a root, a roster, and one typed child map for each player. The application writes all keys to a new player map while it is detached. It then stamps the schema version and attaches the map by storing its handle in the roster.",
      "A future build that uses an incompatible schema receives an error instead of partial decoded state. The module also retries child resolution because a remote handle can remain unavailable while its attachment operation is pending.",
    ],
    snippet: `// attached — snapshot and all — by storing its handle in the roster.
// A single \`write\` fills every key; \`stamp\` records the schema version.
let assert Ok(me) = watershed.create_typed_map(doc)
watershed.write(
  me,
  player_schema(),
  PlayerState(name: player_id, last_roll: None, total: 0, rolls: 0),
)
watershed.stamp(me, player_schema())
watershed.set_child(roster, player_slot(player_id), me)

let roll_due = process.new_subject()
let selector =
  process.new_selector()
  |> process.select_map(watershed.subscribe_typed(roster), RosterChanged)
  |> process.select_map(watershed.subscribe_typed(me), ScoreChanged)
  |> process.select_map(roll_due, fn(_) { RollDue })`,
    snippetLang: "gleam",
    snippetFile: "src/scoreboard_cli.gleam",
  },
  {
    id: "typedmap-panels",
    title: "Initialize panels with a TypedMap",
    step: "schema",
    example: "showcase_lustre",
    rule: "Initialize a reusable component with a typed map. Keep document-scoped effects in the application shell.",
    body: [
      "The showcase mounts four examples as panels in one document. Each panel initializes from a TypedMap instead of a document root. The panel therefore works with either a root map or a child map. The shell declares one ChildField for each panel and ensures all four in one batch.",
      "The shell owns document-scoped effects. Two panel-level presence drivers could share a ripple type and decode each other’s data. go_offline applies to the full document. The document also has only one summary policy. Keeping these effects in the shell prevents duplicate or conflicting drivers.",
    ],
    snippet: `/// Every tab runs this unconditionally. \`ensure_child\` creates a map only if
/// the key is absent, so two tabs opening a *cold* document can both create one
/// and LWW settles a single handle — the loser is orphaned before anybody has
/// interacted with it, and every tab converges on the same four handles.
fn bootstrap_effect(doc: Document(doc_schema.Showcase)) -> Effect(Msg) {
  let root = watershed.root_typed(doc)
  effect.batch([
    watershed_lustre.auto_summarize(
      document: doc,
      policy: summary_policy.policy()
        |> summary_policy.with_threshold(summary_threshold),
    ),
    watershed_lustre.ensure_child(doc, root, doc_schema.text(), EnsuredText),
    watershed_lustre.ensure_child(
      doc,
      root,
      doc_schema.playlist(),
      EnsuredPlaylist,
    ),
    watershed_lustre.ensure_child(doc, root, doc_schema.sudoku(), EnsuredSudoku),
    watershed_lustre.ensure_child(doc, root, doc_schema.canvas(), EnsuredCanvas),
  ])
}`,
    snippetLang: "gleam",
    snippetFile: "src/showcase_lustre.gleam",
  },
  {
    id: "claims-seeding",
    title: "Initialize data idempotently with Claims",
    step: "schema",
    example: "sudoku_lustre",
    rule: "When all clients need the same initial data, run the same initialization loop through first-writer-wins claims on each client.",
    body: [
      "Sudoku givens use try_set_claim: the first writer of each cell wins, and every later attempt is a harmless no-op. There is no initializer to elect and no bootstrap protocol. Every client runs the same loop and converges on the same puzzle.",
      "Use this pattern for values that each client must write at most once. Make the write idempotent in the structure instead of coordinating one initializer in the application.",
    ],
    snippet: `fn seed_givens(claims: Claims, puzzle: Puzzle, row: Int, col: Int) -> Nil {
  case row >= 9 {
    True -> Nil
    False -> {
      let given = puzzles.given_at(puzzle, row, col)
      case given > 0 {
        True -> {
          let _ =
            watershed.try_set_claim(
              claims,
              cell_key(row, col),
              json.int(given),
            )
          Nil
        }
        False -> Nil
      }
      case col == 8 {
        True -> seed_givens(claims, puzzle, row + 1, 0)
        False -> seed_givens(claims, puzzle, row, col + 1)
      }
    }
  }
}`,
    snippetLang: "gleam",
    snippetFile: "src/sudoku_lustre/component.gleam",
  },
  {
    id: "anchors-not-offsets",
    title: "Store text positions as anchors",
    step: "structures",
    example: "text_lustre",
    rule: "Store text positions as anchors. Resolve each anchor again after an edit.",
    body: [
      "The text editor converts each input event into one grapheme insert, delete, or replace operation. It does not replace the full document. A stored integer position can become stale after a remote edit. Anchors represent bookmarks, the local caret, and shared cursors. The application resolves each anchor to a grapheme index when needed.",
      "The bias argument uses the ProseMirror and Yjs association conventions. A collapsed caret associates with the previous grapheme. A range associates with its content. If an anchor is stale, resolution returns an error and the application removes the marker.",
    ],
    snippet: `/// Resolve the pinned anchor to its current grapheme position, or drop it to
/// \`None\` if it has gone stale/unknown.
fn refresh_anchor(model: Model) -> Model {
  case model.editor, model.anchor {
    Some(editor), Some(anchor) ->
      case watershed.text_resolve_anchor(textarea.channel(editor), anchor) {
        Ok(pos) -> Model(..model, anchor_pos: Some(pos))
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
    step: "ui",
    example: "tournament_bracket_lustre",
    rule: "When a structure does not show local writes before confirmation, display the write as pending until a sequencing event arrives.",
    body: [
      "A RegisterCollection stores match results and reads them with the Atomic policy. The kernel does not show a local write before sequencing. The bracket displays “submitted, awaiting confirmation…” until the corresponding event arrives.",
      "VersionChanged reports each sequenced write and updates the visible log of other reports. AtomicChanged reports only the CAS winner and updates the official result. Conflicting submissions converge on one winner and retain the other report.",
    ],
    snippet: `ReportClicked(match_key, winner) ->
  case model.matches {
    None -> #(model, effect.none())
    Some(matches) -> {
      let score =
        dict.get(model.score_drafts, match_key)
        |> option.from_result
        |> option.unwrap("")
      let value = match_result.to_json(MatchResult(winner:, score:))
      watershed.register_write(matches, match_key, value)
      #(
        Model(..model, pending: set.insert(model.pending, match_key)),
        effect.none(),
      )
    }
  }

// ... and in the register event handler:
AtomicChanged(key, value, _local) -> {
  let result = match_result.from_json(value)
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
    title: "Test client disconnection deterministically",
    step: "testing",
    example: "work_queue_lustre",
    rule: "Reproduce a client disconnection during a job. Use an in-process disconnect that sequences the same leave event as the server.",
    body: [
      "The work queue must recover after disconnection. If a tab closes while it holds a job, the remaining replicas return the job to the end of the queue. If the dispatcher closes, the queued backup receives the role. Runtime code performs this recovery, so a deterministic test verifies it.",
      "sluice_js.disconnect sequences the same leave event as a real server. The test can therefore reproduce worker disconnection in one process. The test does not verify that floodgate emits a leave event for a closed socket. A live smoke test verifies that server behavior.",
    ],
    snippet: `pub fn held_job_returns_to_queue_when_holder_disconnects_test() {
  let #(sluice, doc_a, doc_b) = room("wq-worker-dies")
  let queue_a = queue_of(doc_a)
  let queue_b = queue_of(doc_b)
  let payload = job("doomed")

  watershed.ordered_add(queue_a, payload)
  sluice_js.settle(sluice)

  let events_b = queue_events(queue_b)
  let #(outcomes_a, id_a) = outcome_cell(queue_a)
  sluice_js.settle(sluice)
  transport_js.get_cell(outcomes_a)
  |> should.equal([AcquiredItem(id_a, payload)])

  // The tab holding the job goes away without completing or releasing.
  sluice_js.disconnect(sluice, doc_a)
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
      "The same harness checks that dispatcher promotion arrives as a queue event instead of an assignment. This check verifies the recovery event shape and outcome.",
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
);

/** Deep link to a practice, on the guide step that renders it. */
export function practiceHref(practice: Practice): string {
  return `/guide/${practice.step}#${practice.id}`;
}
