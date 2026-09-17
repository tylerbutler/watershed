import gleam/list
import gleam/option.{type Option, None, Some}
import watershed_site/guide

pub type Theme {
  Architecture
  Conflicts
  Coordination
  Testing
}

pub type Practice {
  Practice(
    id: String,
    title: String,
    step: guide.Slug,
    theme: Theme,
    related: List(String),
    example_id: String,
    example_name: String,
    example_href: Option(String),
    rule: String,
    body: List(String),
    snippet_id: String,
    test_note: Option(String),
  )
}

pub fn all() -> List(Practice) {
  [
    Practice(
      "relay-decorator",
      "Treat the server as an optional decorator",
      guide.Connect,
      Architecture,
      ["/runtime/p2p", "/structures/counters"],
      "clap_counter_lustre",
      "Clap counter",
      Some("/examples#clap_counter_lustre"),
      "A peer-to-peer app may use a relay for durability, but it should not need one to start.",
      [
        "The clap counter has no sequencer, tenant, or token. If the URL names a relay, one function adds it to the peer-to-peer config.",
        "The app still becomes ready when that relay is down. It reports the outage instead of turning an optional service into a hidden requirement.",
      ],
      "practice-relay-decorator",
      None,
    ),
    Practice(
      "shared-core-two-runtimes",
      "One shared core, two runtimes",
      guide.Connect,
      Architecture,
      [],
      "dice_cli",
      "Dice CLI",
      None,
      "Keep the shared core portable by connecting to the same document from the BEAM and the browser.",
      [
        "dice_cli and dice_lustre edit the same floodgate document. They share the kernel, wire format, and runtime core; only the outer program changes. The browser uses an MVU update function, while the BEAM client uses a receive loop.",
        "The CLI connects to 127.0.0.1 instead of localhost. Erlang's resolver stalls about eight seconds on the AAAA lookup, long enough for the server to drop the connection.",
      ],
      "practice-shared-core-two-runtimes",
      None,
    ),
    Practice(
      "diagnostics-first",
      "Sample diagnostics on every event",
      guide.Connect,
      Testing,
      ["/runtime/optimistic", "/runtime/reconnect"],
      "dice_lustre",
      "Collaborative dice",
      Some("/examples#dice_lustre"),
      "Put the runtime's diagnostics on screen before you debug synchronization.",
      [
        "The smallest browser example updates one diagnostics line after every event. It shows the connection phase, client id, sequence numbers, queued operations, and resubmit checkpoint.",
        "Those values tell you where to look. A stuck in_flight count, a growing buffer, and a connection that never reaches synced point to different problems that application state cannot show.",
      ],
      "practice-diagnostics-first",
      None,
    ),
    Practice(
      "quorum-pending-roster",
      "Propose on release, render the pending signoff",
      guide.Votes,
      Conflicts,
      ["/structures/coordination", "/runtime/optimistic"],
      "drum_machine_lustre",
      "Drum machine",
      Some("/examples#drum_machine_lustre"),
      "Send one consensus proposal per gesture, then show whose approval is still missing.",
      [
        "A PactMap stores the tempo and accepts a change after every connected client approves it. The slider sends its proposal on release. Sending one on every pointer move would overwhelm a protocol that allows only one pending proposal.",
        "While the group decides, the UI disables the slider and names the clients that have not approved. A short poll catches changes that the kernel does not report as events.",
      ],
      "practice-quorum-pending-roster",
      None,
    ),
    Practice(
      "realtime-out-of-band",
      "Keep latency-critical loops out of the update path",
      guide.Presence,
      Architecture,
      [],
      "drum_machine_lustre",
      "Drum machine",
      Some("/examples#drum_machine_lustre"),
      "Let a real-time loop read a plain snapshot. Do not make it wait on the application.",
      [
        "The audio engine runs in an FFI module. Every 25 ms, it schedules the steps due in the next 100 ms against the audio clock. Gleam pushes pattern updates into a plain array, so document delays cannot become audio jitter.",
        "Background tabs create another trap: browsers slow timers while the audio clock keeps moving. When the tab returns, the scheduler resets its timing instead of playing every missed step at once.",
      ],
      "practice-realtime-out-of-band",
      None,
    ),
    Practice(
      "presence-idiom",
      "The minimal presence idiom",
      guide.Presence,
      Coordination,
      ["/runtime/presence"],
      "retro_tutorial_lustre",
      "Retro board (tutorial)",
      Some("/examples#retro_tutorial_lustre"),
      "Declare one presence effect, use one typed payload, and remove the local session before the roster enters your model.",
      [
        "The tutorial retro board shows the smallest complete presence setup. One effect starts the driver with an encoder and decoder. A helper removes the local session from the roster before the app stores it.",
        "watershed includes the local session on purpose; each app decides whether to show it. The richer cursors and avatar lists in other examples use the same setup with more data.",
      ],
      "practice-presence-idiom",
      None,
    ),
    Practice(
      "protocol-on-ripples",
      "Ride an application protocol on ripples",
      guide.Presence,
      Coordination,
      ["/runtime/presence"],
      "grocery_triptych_lustre",
      "Grocery triptych",
      Some("/examples#grocery_triptych_lustre"),
      "Send short-lived coordination over ripples, not through a document channel.",
      [
        "The triptych's guided scenarios ask two tabs to choose a driver and exchange invitations, acknowledgements, and status updates. Ripples deliver those messages with a run id, and the document stores none of them.",
        "Plain functions match runs, ignore the sender's own messages, choose acknowledgements, and reject unknown message types. That keeps the protocol testable without a server.",
      ],
      "practice-protocol-on-ripples",
      None,
    ),
    Practice(
      "pure-modules",
      "Extract pure modules; test without a server",
      guide.Testing,
      Testing,
      [],
      "grocery_triptych_lustre",
      "Grocery triptych",
      Some("/examples#grocery_triptych_lustre"),
      "Move decisions into pure modules so most tests need no document, sluice, or server.",
      [
        "The triptych separates decisions from effects. Its protocol, scenario state, and guards run as ordinary unit tests. The small refresh guard below uses a generation counter to discard an old refresh after a newer one arrives.",
        "Convergence and browser tests still cover behavior that needs a runtime. They stay small because pure tests cover the decision branches.",
      ],
      "practice-pure-modules",
      Some(
        "Six test files (protocol, scenario state, guards, actions) run pure, alongside one sluice convergence file and the smoke tier.",
      ),
    ),
    Practice(
      "ffi-surface",
      "Hand a rendering surface to FFI, and bootstrap on Connected",
      guide.Connect,
      Architecture,
      ["/foundations/lifecycle"],
      "pixel_canvas_lustre",
      "Pixel canvas",
      Some("/examples#pixel_canvas_lustre"),
      "Let an FFI module own the canvas pixels, and create shared channels only after the connection opens.",
      [
        "Lustre renders an empty canvas; an FFI module owns its byte buffer and 2D context. The view keeps the canvas size fixed because changing it erases the pixels. The FFI module looks up the context when it needs it, so mount order does not need another effect.",
        "The app creates its shared channel after Connected, not after GotHandle. A handle can resolve before the connection is ready, which would leave the app painting a canvas that no peer can see.",
      ],
      "practice-ffi-surface",
      None,
    ),
    Practice(
      "fallible-edits",
      "Fallible edits render; never assert on a mutation",
      guide.Notes,
      Conflicts,
      ["/structures/sequences", "/runtime/optimistic"],
      "playlist_lustre",
      "Collaborative playlist",
      Some("/examples#playlist_lustre"),
      "Handle every index-based edit as fallible. A peer may change the list between render and click.",
      [
        "A remote insert or delete can make a rendered index stale before the user clicks. The playlist sends every sequence edit through one helper and shows the runtime error in a banner instead of asserting success.",
        "The runtime refuses an index outside the list. It does not clamp the index, because that could move or delete the wrong track.",
      ],
      "practice-fallible-edits",
      None,
    ),
    Practice(
      "authoritative-channel",
      "When a move is not atomic, crown one channel authoritative",
      guide.Notes,
      Conflicts,
      ["/structures/sequences", "/structures/coordination"],
      "retro_board_lustre",
      "Retro board (full)",
      Some("/examples#retro_board_lustre"),
      "A move across channels is not atomic. Choose one source of truth and reconcile the rest while rendering.",
      [
        "Dragging a sticky note takes three operations across two channel types. The note's column field decides where it belongs. The view skips an id in the wrong column, puts missing ids at the end, and sends unknown columns to an unfiled strip.",
        "The view does not write repairs. If every client tried to clean up while rendering, they could fight over more operations. The next user move removes the stale id from the other columns.",
      ],
      "practice-authoritative-channel",
      None,
    ),
    Practice(
      "stamp-schema",
      "Stamp the schema; refuse bad reads",
      guide.Notes,
      Architecture,
      ["/structures/maps", "/foundations/schema"],
      "scoreboard_cli",
      "Scoreboard CLI",
      None,
      "Fill and stamp a typed map before attaching it, so an incompatible reader gets an error.",
      [
        "The scoreboard has a root map, a roster, and one typed child map for each player. It fills a new player map in one write, stamps the schema version, then attaches the map to the roster.",
        "That stamp protects future readers from decoding the map with the wrong schema. Child lookup also retries because a remote handle may arrive before the operation that attaches its map.",
      ],
      "practice-stamp-schema",
      None,
    ),
    Practice(
      "typedmap-panels",
      "Panels take a TypedMap, never a root",
      guide.Connect,
      Architecture,
      ["/structures/maps", "/foundations/topology"],
      "showcase_lustre",
      "Nested app showcase",
      Some("/examples#showcase_lustre"),
      "Give a reusable component a typed map, whether that map is a root or a child. Keep document-wide effects in the shell.",
      [
        "The showcase mounts four examples as panels in one document. Each panel accepts a TypedMap and cannot tell whether it received the root or a child map. The shell creates one child field for each panel.",
        "The shell also owns presence, offline mode, and summary policy because they affect the whole document. If panels started their own copies, presence messages could mix and the panels could compete over one shared setting.",
      ],
      "practice-typedmap-panels",
      None,
    ),
    Practice(
      "claims-seeding",
      "Seed idempotently with Claims",
      guide.Connect,
      Conflicts,
      ["/structures/coordination", "/foundations/lifecycle"],
      "sudoku_lustre",
      "Collaborative Sudoku",
      Some("/examples#sudoku_lustre"),
      "Let every client seed the same initial values through first-writer-wins claims.",
      [
        "Every Sudoku client runs the same loop over the given cells. claim_once keeps the first value for each cell and ignores later attempts, so the clients settle on one puzzle without electing an initializer.",
        "Use this for initial values that must be written once. The shared structure settles duplicate work, so the app needs no separate setup protocol.",
      ],
      "practice-claims-seeding",
      None,
    ),
    Practice(
      "anchors-not-offsets",
      "Anchors, not offsets",
      guide.Notes,
      Conflicts,
      ["/structures/sequences"],
      "text_lustre",
      "Shared text editor",
      Some("/examples#text_lustre"),
      "Store an anchor instead of a text offset, then resolve its current position after each edit.",
      [
        "The editor turns each input into a small insert, delete, or replace. Remote edits would make saved integer positions stale, so bookmarks, carets, and shared cursors all use anchors that resolve to the current grapheme index.",
        "Anchor bias decides which nearby text a caret or selection follows as edits arrive. If an anchor no longer resolves, the app removes the marker instead of guessing.",
      ],
      "practice-anchors-not-offsets",
      None,
    ),
    Practice(
      "unsettled-writes",
      "Show writes that have not settled",
      guide.Votes,
      Conflicts,
      ["/structures/coordination", "/runtime/optimistic"],
      "tournament_bracket_lustre",
      "Tournament bracket",
      Some("/examples#tournament_bracket_lustre"),
      "When writes are not optimistic, show them as pending until the confirming event arrives.",
      [
        "A RegisterCollection stores each match result under the Atomic policy, which chooses one compare-and-swap winner. Local writes stay hidden until the server orders them, so the bracket shows a submitted result as awaiting confirmation.",
        "VersionChanged reports every ordered submission, including the ones that lose. AtomicChanged reports only the winner and updates the official bracket. The log keeps the competing reports visible.",
      ],
      "practice-unsettled-writes",
      None,
    ),
    Practice(
      "deterministic-death",
      "Test client death deterministically",
      guide.Testing,
      Testing,
      ["/structures/coordination", "/runtime/reconnect"],
      "work_queue_lustre",
      "Work queue",
      Some("/examples#work_queue_lustre"),
      "Test a client dying mid-job with an in-process disconnect that produces the same leave event as the server.",
      [
        "The work queue promises to recover when a client disappears. If a worker dies, the job returns to the queue. If the dispatcher dies, the next client takes over. An automated test needs to prove both transitions.",
        "sluice_js.disconnect produces the same leave event that the server would, so the test runs in process and on demand. A live smoke test covers the remaining boundary: whether floodgate notices a vanished socket and sends that event.",
      ],
      "practice-deterministic-death",
      Some(
        "The same harness asserts a dispatcher promotion arrives as a queue event, not an assignment, pinning the event shape of recovery rather than just its outcome.",
      ),
    ),
  ]
}

pub fn themes() -> List(Theme) {
  [Architecture, Conflicts, Coordination, Testing]
}

pub fn theme_title(theme: Theme) -> String {
  case theme {
    Architecture -> "Architecture & composition"
    Conflicts -> "Conflicts & consistency"
    Coordination -> "Presence & coordination"
    Testing -> "Testing & diagnostics"
  }
}

pub fn theme_blurb(theme: Theme) -> String {
  case theme {
    Architecture ->
      "Decide what the shell owns, what a component may touch, and which work must stay outside the app."
    Conflicts ->
      "Two clients change the same state at once. Keep the UI honest while the shared structure settles the result."
    Coordination ->
      "Some facts belong to the session, not the document: who's here, who drives, and what they need to tell each other."
    Testing ->
      "Reproduce the failures that matter, and read the runtime's own diagnostics before you guess at a sync bug."
  }
}

pub fn by_theme(theme: Theme) -> List(Practice) {
  all()
  |> list.filter(fn(item) { item.theme == theme })
}

pub fn by_example(id: String) -> List(Practice) {
  all()
  |> list.filter(fn(item) { item.example_id == id })
}

pub fn related_to(path: String) -> List(Practice) {
  all()
  |> list.filter(fn(item) { list.contains(item.related, path) })
}

pub fn get(id: String) -> Result(Practice, Nil) {
  all()
  |> list.find(fn(item) { item.id == id })
}

pub fn by_step(step: guide.Slug) -> List(Practice) {
  all()
  |> list.filter(fn(item) { item.step == step })
}

pub fn href(item: Practice) -> String {
  guide.path(item.step) <> "#" <> item.id
}
