// ──────────────────────────────────────────────────────────────────────────
// watershed — practices catalog
// One entry per technique, each anchored to the ONE checked-in example that
// demonstrates it best. This is the inverse of the old /patterns page: not
// conventions that recur across apps, but the specific thing each app was
// built to prove, with the code that proves it. Snippets are copied (and
// trimmed) from the example source named in `snippetFile` — keep them in
// sync when an example changes.
// ──────────────────────────────────────────────────────────────────────────
import { examples, type Example } from "./examples";

export interface Practice {
  /** Anchor slug on /patterns. */
  id: string;
  /** Section title. */
  title: string;
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
  /** The unique check that pins the claim, if the example has one. */
  testNote?: string;
}

export const practices: Practice[] = [
  {
    id: "relay-decorator",
    title: "Treat the server as an optional decorator",
    example: "clap_counter_lustre",
    rule: "When the app is peer-to-peer, add durability as a config decorator that readiness never waits on.",
    body: [
      "The clap counter is the one example built on the state-based CRDT stack: no sequencer, no tenant, no token. A relay only exists if the URL names one, and it is attached by piping the config through one decorator function.",
      "Because the readiness policy stays Auto, a relay that is down costs a status line, not the application. The failure mode this prevents is quiet dependence: a demo that silently required a server would be lying about what the P2P mode needs.",
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
    testNote:
      "just p2p-clap runs two real headless browsers through the reference signaling service and asserts equal totals, equal canonical digests, and that signaling carried nothing but join/signal/leave frames.",
  },
  {
    id: "shared-core-two-runtimes",
    title: "One shared core, two runtimes",
    example: "dice_cli",
    rule: "Prove the core is portable by joining the same document from an OTP actor and a browser tab.",
    body: [
      "dice_cli is an Erlang-target client for the same floodgate document dice_lustre edits from a browser. The kernel, wire format, and runtime core are the same modules; only the transport shell differs. On the BEAM the app is a recursive receive loop over one selector instead of an MVU update function.",
      "The pair also documents a real deployment gotcha: connect to 127.0.0.1, not localhost — Erlang's IPv6-first resolution can stall long enough for the server to drop the idle socket.",
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
    title: "Sample diagnostics on every event",
    example: "dice_lustre",
    rule: "Render the runtime's own diagnostics before guessing at a sync bug.",
    body: [
      "The smallest browser example keeps a diagnostics line on screen and refreshes it on every event: connection phase, client id, last-seen sequence number, in-flight and buffered op counts, and the resubmit checkpoint. Its README reads each field as a triage recipe.",
      "This is the canonical shape of a sync bug report. A stuck in_flight count, a climbing buffered count, or a phase that never reaches synced each point at a different layer — and none of them are visible from the application state alone.",
    ],
    snippet: `fn diagnostic_line(diagnostics: watershed_js.Diagnostics) -> String {
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
    testNote:
      "The headless smoke forces a mid-session reconnect with edits applied during the drop, then asserts convergence.",
  },
  {
    id: "quorum-pending-roster",
    title: "Propose on release, render the pending signoff",
    example: "drum_machine_lustre",
    rule: "A consensus write is a proposal, not an edit: commit it once per gesture and show who has not signed off.",
    body: [
      "Tempo lives in a PactMap: a change is accepted only when every connected client signs off. The slider therefore proposes on release, never per pointer move — a proposal per frame would flood a protocol in which a second proposal is rejected outright while one is pending.",
      "The pending state is rendered, not hidden: the roster of outstanding signoffs stays on screen and the control stays disabled, with a poll to catch the transitions the kernel does not report. Matching “you” in that roster uses the same client-id derivation the kernels use, so the match is exact.",
    ],
    snippet: `// Propose on release, never per pointer move. A \`pact_map_set\` per frame
// would flood the protocol with proposals that invalidate each other —
// \`apply_set\` rejects a proposal made while one is pending — so a dragged
// slider would land on whichever frame happened to arrive between pacts.
BpmCommitted ->
  case model.shared, tempo_locked(model), model.bpm_draft == model.bpm {
    Some(shared), False, False -> {
      watershed_js.pact_map_set(
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
    testNote:
      "test/quorum_test.gleam runs three clients — a two-client room cannot distinguish a correct signoff roster from [self, author] — and drains a stalled proposal by disconnecting the silent client.",
  },
  {
    id: "realtime-out-of-band",
    title: "Keep latency-critical loops out of the update path",
    example: "drum_machine_lustre",
    rule: "A real-time loop reads a plain snapshot the app pushes to it; it never calls back into the application.",
    body: [
      "The audio engine is an FFI module running a lookahead scheduler: a 25 ms interval schedules every step falling inside the next 100 ms against the audio clock. It reads a mutable pattern array that Gleam pushes updates into — if the scheduler had to ask the application for the pattern, document latency would become audio jitter.",
      "The same file documents the background-tab trap: browsers throttle timers while the audio clock keeps running, so a naive scheduler greets a returning tab with a burst of every step it missed. The tick resyncs instead of catching up.",
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
    title: "The minimal presence idiom",
    example: "flowboard_lustre",
    rule: "One declared presence effect, one typed payload, and a roster filtered of the local session at the edge.",
    body: [
      "Flowboard is the guide's worked example, and its presence wiring is the template the larger apps elaborate: a single effect declares the driver with an encoder/decoder pair, and the roster callback filters out the local session before the model ever sees it.",
      "Presence state includes the local session by design — the filtering is an application decision, made once, at the edge. Every peer cursor and avatar stack in the other examples is this same dozen lines with a richer payload.",
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
    title: "Ride an application protocol on ripples",
    example: "grocery_triptych_lustre",
    rule: "Coordination that should die with the session gets its own message envelope on ripples, never a document channel.",
    body: [
      "The triptych's guided scenarios need two tabs to agree on who drives: an invitation, an acknowledgement, a go signal, status updates. All of it rides ripples inside a typed envelope with a run id, and none of it touches durable state — a browsing session's handshake has no business surviving in the document.",
      "The envelope module is pure: run matching, self-filtering, ack selection, and foreign-type rejection are plain functions over decoded messages, which is what makes the protocol testable without a server.",
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
    testNote:
      "scenario_protocol_test covers every phase transition — including rejecting a foreign run id and this client's own echo — with no document and no transport.",
  },
  {
    id: "pure-modules",
    title: "Extract pure modules; test without a server",
    example: "grocery_triptych_lustre",
    rule: "Pull decision logic out of update into pure modules, and let most of the suite need no doc, no sluice, no server.",
    body: [
      "The triptych carries the repo's largest pure-logic suite — around a thousand lines across protocol, scenario-state, and guard tests — because everything that decides was extracted from everything that performs. The 23-line refresh guard below is the smallest specimen: a generation counter that drops stale coalesced refreshes.",
      "The payoff is proportion: the expensive convergence and browser smoke tests are reserved for claims only they can make, while every branch of the decision logic runs as ordinary unit tests.",
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
      "Seven test files — protocol, scenario state, guards, actions — run pure, alongside a much smaller sluice and smoke tier.",
  },
  {
    id: "ffi-surface",
    title: "Hand a rendering surface to FFI — and bootstrap on Connected",
    example: "pixel_canvas_lustre",
    rule: "Give a canvas to an FFI module that owns its pixels, and run ensure_* only after the connection handshake.",
    body: [
      "The canvas is rendered by Lustre as a childless element and painted by an FFI module that owns the byte buffer and 2D context. Two rules keep that safe: width and height must stay static in view (a diff rewriting them wipes the surface), and the context is resolved lazily per call, so no mount-ordering effect is needed.",
      "Bootstrap lives in the Connected arm, not GotHandle: attaching a channel needs a ready connection, while resolving a handle does not. Fire ensure_* early and the app paints locally while sharing nothing.",
    ],
    snippet: `Connected(Ok(_)) ->
  case model.doc {
    None -> #(Model(..model, status: Ready), effect.none())
    Some(doc) -> {
      let #(canvas, canvas_effect) =
        component.init(doc, watershed_js.root_typed(doc))
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
    testNote:
      "The convergence suite owns the offline-window family — regions painted while offline join on reconnect; a cell contested across the window converges — and deliberately does not assert which colour wins.",
  },
  {
    id: "fallible-edits",
    title: "Fallible edits render; never assert on a mutation",
    example: "playlist_lustre",
    rule: "Every index-addressed edit returns a Result, because a peer can delete the row between render and click.",
    body: [
      "Sequence operations — insert, move, replace, delete — are fallible by design: the index a client renders can be stale by the time it clicks. The playlist funnels every edit through one helper that surfaces the runtime's own error message as a banner, and no mutation is ever unwrapped with an assert.",
      "The boundary behaviour is part of the contract: an out-of-bounds edit is refused, not clamped. Clamping would silently reorder the wrong element; the refusal is honest and renderable.",
    ],
    snippet: `MoveDownClicked(index) -> #(
  mutate(model, "move", fn(seq) {
    watershed_js.sequence_move(seq, index, index + 1)
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
    testNote:
      "The library suite pins the payoff race — a concurrent move against a replace preserves every element — and the smoke asserts an out-of-bounds delete is refused rather than clamped.",
  },
  {
    id: "authoritative-channel",
    title: "When a move is not atomic, crown one channel authoritative",
    example: "retro_board_lustre",
    rule: "A cross-channel move cannot be transactional, so pick the channel that wins and reconcile at render time.",
    body: [
      "Dragging a sticky note is three operations across two channel kinds, with no transaction. The board makes the note's column register authoritative and reconciles in the view: an id sitting in the wrong column's sequence is skipped, a note missing from its sequence renders at the tail ordered by creation time, and unknown columns route to an unfiled strip.",
      "Stale garbage is left in place deliberately. Repair-on-render would have every client issuing corrective ops and fighting; instead, repair rides the next user action, which sweeps the id out of every sequence it no longer belongs in.",
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
    testNote:
      "board_test unit-tests the render rules themselves — duplicate ids, orphan votes, unknown columns — and the convergence suite pins observed behaviour: an edit racing a delete wins, and the card resurrects at the column tail.",
  },
  {
    id: "stamp-schema",
    title: "Stamp the schema; fail loudly on read",
    example: "scoreboard_cli",
    rule: "Seed a detached typed map in one write, stamp its schema version, then attach — so incompatible layouts fail on read, not silently.",
    body: [
      "The scoreboard builds the deepest handle topology in the repo: root, roster, and one typed child map per player. A new player's map is filled while still detached — one write covers every key — then stamped with its schema version and attached by storing the handle in the roster.",
      "The stamp is the part nothing else demonstrates: a future build reading this map through an incompatible schema fails loudly instead of returning half-decoded state. The module also wraps child resolution in a retry, because a remote handle can be transiently unresolvable while its attach op is in flight.",
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
    title: "Panels take a TypedMap, never a root",
    example: "showcase_lustre",
    rule: "A composable component's init takes a typed map — standalone it happens to be the root; nested it is a child — and document-scoped effects stay in the shell.",
    body: [
      "The showcase mounts four other examples as panels of one document. That works because each of those apps exposes a component whose init takes a TypedMap, never a document root: nothing inside a panel can tell whether its map is the whole document or one child of it. The shell declares one ChildField per panel and ensures all four in one batch.",
      "Document-scoped effects belong to the shell, and each has a concrete failure mode if a panel ran its own: two presence drivers share a ripple kind and cross-decode silently; go_offline is per-document and cannot be scoped down; the summary policy is one slot per document, so which panel's policy won would depend on click order.",
    ],
    snippet: `/// Every tab runs this unconditionally. \`ensure_child\` creates a map only if
/// the key is absent, so two tabs opening a *cold* document can both create one
/// and LWW settles a single handle — the loser is orphaned before anybody has
/// interacted with it, and every tab converges on the same four handles.
fn bootstrap_effect(doc: Document(doc_schema.Showcase)) -> Effect(Msg) {
  let root = watershed_js.root_typed(doc)
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
    testNote:
      "composition_test asserts what the types cannot: panel keys do not leak into the root, racing clients agree on one set of children, and one go_offline partitions all four panels.",
  },
  {
    id: "claims-seeding",
    title: "Seed idempotently with Claims",
    example: "sudoku_lustre",
    rule: "When every client must agree on initial data, let every client run the same seeding loop through first-writer-wins claims.",
    body: [
      "Sudoku givens are seeded with try_set_claim: the first writer of each cell wins, and every later attempt is a harmless no-op. That means there is no initializer to elect and no bootstrap protocol — every client runs the identical loop, and all of them converge on the same puzzle.",
      "This is the general answer to “who sets up the document?” for any value that must be written exactly once: make the write idempotent at the structure level instead of coordinating at the application level.",
    ],
    snippet: `fn seed_givens(claims: Claims, puzzle: Puzzle, row: Int, col: Int) -> Nil {
  case row >= 9 {
    True -> Nil
    False -> {
      let given = puzzles.given_at(puzzle, row, col)
      case given > 0 {
        True -> {
          let _ =
            watershed_js.try_set_claim(
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
    title: "Anchors, not offsets",
    example: "text_lustre",
    rule: "Never store a text position as an integer: hold an anchor and re-resolve it after every edit.",
    body: [
      "The text editor never replaces the whole document — each input event is grapheme-diffed into one minimal insert, delete, or replace — which means every stored position would go stale on every remote edit. So positions are anchors: the pinned bookmark, the local caret across remote edits, and shared cursors riding presence are all the same primitive, resolved back to a grapheme index on demand.",
      "The bias argument encodes the ProseMirror/Yjs association conventions: a collapsed caret hangs off the preceding grapheme, a range hugs its content. An anchor that has gone stale resolves to an error, and the app drops the marker instead of guessing.",
    ],
    snippet: `/// Resolve the pinned anchor to its current grapheme position, or drop it to
/// \`None\` if it has gone stale/unknown.
fn refresh_anchor(model: Model) -> Model {
  case model.editor, model.anchor {
    Some(editor), Some(anchor) ->
      case watershed_js.text_resolve_anchor(textarea.channel(editor), anchor) {
        Ok(pos) -> Model(..model, anchor_pos: Some(pos))
        Error(_) -> Model(..model, anchor_pos: None)
      }
    _, _ -> Model(..model, anchor_pos: None)
  }
}`,
    snippetLang: "gleam",
    snippetFile: "src/text_lustre/component.gleam",
    testNote:
      "The smoke races an emoji insert at the head against a combining-mark insert at the tail and asserts grapheme integrity and anchor movement; caret and IME behaviour ship as reasoned manual checklists.",
  },
  {
    id: "unsettled-writes",
    title: "Show writes that have not settled",
    example: "tournament_bracket_lustre",
    rule: "When a structure is not optimistic, say so in the UI: pending until the event that proves the write sequenced.",
    body: [
      "Match results live in a RegisterCollection read with the Atomic policy — the linearizable CAS winner, not last-write-wins. The kernel shows no local write before it sequences, so the bracket is the deliberate inverse of every optimistic example: a submitted result renders as “submitted, awaiting confirmation…” until its event lands.",
      "The two event kinds divide the truth cleanly: VersionChanged fires for every sequenced write and feeds the visible log of losing reports; AtomicChanged fires only for the CAS winner and is the sole source of official results. Conflicting submissions converge on one winner without discarding the loser.",
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
      watershed_js.register_write(matches, match_key, value)
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
    testNote:
      "The convergence suite pins the payoff: concurrent conflicting reports converge on one official winner while the losing report stays visible in the version log.",
  },
  {
    id: "deterministic-death",
    title: "Test client death deterministically",
    example: "work_queue_lustre",
    rule: "The interesting event is a client dying mid-job — reproduce it in-process with a disconnect that sequences the same leave the server would.",
    body: [
      "The work queue's whole claim is recovery: close a tab holding a job and the surviving replicas return it to the queue tail; close the dispatcher and the queued backup inherits the role. No application code participates — which is exactly why it needs a deterministic test, not a demo.",
      "sluice_js.disconnect sequences the same leave a real server would, so worker death becomes an ordinary in-process scenario. The suite is equally explicit about its limit: it cannot vouch that floodgate emits a leave for a vanished socket — that one claim is what the live smoke exists for.",
    ],
    snippet: `pub fn held_job_returns_to_queue_when_holder_disconnects_test() {
  let #(sluice, doc_a, doc_b) = room("wq-worker-dies")
  let queue_a = queue_of(doc_a)
  let queue_b = queue_of(doc_b)
  let payload = job("doomed")

  watershed_js.ordered_add(queue_a, payload)
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
  watershed_js.ordered_queue(queue_b) |> should.equal([payload])
  watershed_js.ordered_jobs(queue_b) |> should.equal([])
}`,
    snippetLang: "gleam",
    snippetFile: "test/queue_semantics_test.gleam",
    testNote:
      "The same harness asserts a dispatcher promotion arrives as a queue event, not an assignment — pinning the event shape of recovery, not just its outcome.",
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
