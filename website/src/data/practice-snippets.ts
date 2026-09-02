// ──────────────────────────────────────────────────────────────────────────
// Practice snippet registry — the single source of truth for every code
// excerpt shown in a field note. Each import is a Vite `?raw` read of a
// real compiled example; the extractor throws at build time when the
// definition or marker it names is missing or stale.
// ──────────────────────────────────────────────────────────────────────────
import {
  snippetFromDefinition,
  snippetFromMarker,
  type Snippet,
} from "../lib/snippet.ts";

// ── Raw source imports ─────────────────────────────────────────────────────
import clapCounterSource from "../../../examples/clap_counter_lustre/src/clap_counter_lustre.gleam?raw";
import diceCLISource from "../../../examples/dice_cli/src/dice_cli.gleam?raw";
import diceLustreSource from "../../../examples/dice_lustre/src/dice_lustre.gleam?raw";
import drumMachineSource from "../../../examples/drum_machine_lustre/src/drum_machine_lustre.gleam?raw";
import audioFFISource from "../../../examples/drum_machine_lustre/src/drum_machine_lustre/audio_ffi.mjs?raw";
import retroTutorialSource from "../../../examples/retro_tutorial_lustre/src/retro_tutorial_lustre.gleam?raw";
import scenarioProtocolSource from "../../../examples/grocery_triptych_lustre/src/grocery_triptych_lustre/scenario_protocol.gleam?raw";
import refreshGuardSource from "../../../examples/grocery_triptych_lustre/src/grocery_triptych_lustre/refresh_guard.gleam?raw";
import pixelCanvasSource from "../../../examples/pixel_canvas_lustre/src/pixel_canvas_lustre.gleam?raw";
import playlistComponentSource from "../../../examples/playlist_lustre/src/playlist_lustre/component.gleam?raw";
import retroBoardSource from "../../../examples/retro_board_lustre/src/retro_board_lustre/board.gleam?raw";
import scoreboardCLISource from "../../../examples/scoreboard_cli/src/scoreboard_cli.gleam?raw";
import showcaseSource from "../../../examples/showcase_lustre/src/showcase_lustre.gleam?raw";
import sudokuComponentSource from "../../../examples/sudoku_lustre/src/sudoku_lustre/component.gleam?raw";
import textComponentSource from "../../../examples/text_lustre/src/text_lustre/component.gleam?raw";
import tournamentSource from "../../../examples/tournament_bracket_lustre/src/tournament_bracket_lustre.gleam?raw";
import queueTestSource from "../../../examples/work_queue_lustre/test/queue_semantics_test.gleam?raw";

// ── Source paths (repo-relative, for citation and links) ───────────────────
const paths = {
  clapCounter: "examples/clap_counter_lustre/src/clap_counter_lustre.gleam",
  diceCLI: "examples/dice_cli/src/dice_cli.gleam",
  diceLustre: "examples/dice_lustre/src/dice_lustre.gleam",
  drumMachine: "examples/drum_machine_lustre/src/drum_machine_lustre.gleam",
  audioFFI: "examples/drum_machine_lustre/src/drum_machine_lustre/audio_ffi.mjs",
  retroTutorial: "examples/retro_tutorial_lustre/src/retro_tutorial_lustre.gleam",
  scenarioProtocol: "examples/grocery_triptych_lustre/src/grocery_triptych_lustre/scenario_protocol.gleam",
  refreshGuard: "examples/grocery_triptych_lustre/src/grocery_triptych_lustre/refresh_guard.gleam",
  pixelCanvas: "examples/pixel_canvas_lustre/src/pixel_canvas_lustre.gleam",
  playlistComponent: "examples/playlist_lustre/src/playlist_lustre/component.gleam",
  retroBoard: "examples/retro_board_lustre/src/retro_board_lustre/board.gleam",
  scoreboardCLI: "examples/scoreboard_cli/src/scoreboard_cli.gleam",
  showcase: "examples/showcase_lustre/src/showcase_lustre.gleam",
  sudokuComponent: "examples/sudoku_lustre/src/sudoku_lustre/component.gleam",
  textComponent: "examples/text_lustre/src/text_lustre/component.gleam",
  tournament: "examples/tournament_bracket_lustre/src/tournament_bracket_lustre.gleam",
  queueTest: "examples/work_queue_lustre/test/queue_semantics_test.gleam",
} as const;

// ── Registry ───────────────────────────────────────────────────────────────

/** Every practice snippet, keyed by practice id. */
export const practiceSnippets: Record<string, Snippet> = {
  // ── relay-decorator: config block (marker) + fn with_relay (definition) ──
  "relay-decorator": combine(
    snippetFromMarker(clapCounterSource, paths.clapCounter, "gleam", "practice-relay-config"),
    snippetFromDefinition(clapCounterSource, paths.clapCounter, "gleam", "fn with_relay("),
    paths.clapCounter,
  ),

  // ── shared-core-two-runtimes: whole definition ───────────────────────────
  "shared-core-two-runtimes": snippetFromDefinition(
    diceCLISource, paths.diceCLI, "gleam", "fn event_loop(",
  ),

  // ── diagnostics-first: whole definition ──────────────────────────────────
  "diagnostics-first": snippetFromDefinition(
    diceLustreSource, paths.diceLustre, "gleam", "fn diagnostic_line(",
  ),

  // ── quorum-pending-roster: BpmCommitted case arm (marker) ────────────────
  "quorum-pending-roster": snippetFromMarker(
    drumMachineSource, paths.drumMachine, "gleam", "practice-quorum-pending",
  ),

  // ── realtime-out-of-band: JS function (definition) ──────────────────────
  "realtime-out-of-band": snippetFromDefinition(
    audioFFISource, paths.audioFFI, "js", "function tick(engine)",
  ),

  // ── presence-idiom: two definitions ──────────────────────────────────────
  "presence-idiom": snippetFromDefinition(
    retroTutorialSource, paths.retroTutorial, "gleam",
    "fn presence_effect(", "fn remote_peers(",
  ),

  // ── protocol-on-ripples: three definitions ───────────────────────────────
  "protocol-on-ripples": snippetFromDefinition(
    scenarioProtocolSource, paths.scenarioProtocol, "gleam",
    "pub fn matches_run(", "pub fn from_self(", "pub fn should_acknowledge(",
  ),

  // ── pure-modules: type + three functions ─────────────────────────────────
  "pure-modules": snippetFromDefinition(
    refreshGuardSource, paths.refreshGuard, "gleam",
    "pub type State {", "pub fn idle(", "pub fn request(", "pub fn flush(",
  ),

  // ── ffi-surface: Connected case arms (marker) ───────────────────────────
  "ffi-surface": snippetFromMarker(
    pixelCanvasSource, paths.pixelCanvas, "gleam", "practice-ffi-connected",
  ),

  // ── fallible-edits: MoveDownClicked arm (marker) + fn mutate + fn record ─
  "fallible-edits": combine(
    snippetFromMarker(playlistComponentSource, paths.playlistComponent, "gleam", "practice-fallible-move"),
    snippetFromDefinition(playlistComponentSource, paths.playlistComponent, "gleam", "fn mutate(", "fn record("),
    paths.playlistComponent,
  ),

  // ── authoritative-channel: whole definition ──────────────────────────────
  "authoritative-channel": snippetFromDefinition(
    retroBoardSource, paths.retroBoard, "gleam", "fn render_column(",
  ),

  // ── stamp-schema: marker for the setup block inside main() ───────────────
  "stamp-schema": snippetFromMarker(
    scoreboardCLISource, paths.scoreboardCLI, "gleam", "practice-stamp-schema",
  ),

  // ── typedmap-panels: whole definition ────────────────────────────────────
  "typedmap-panels": snippetFromDefinition(
    showcaseSource, paths.showcase, "gleam", "fn bootstrap_effect(",
  ),

  // ── claims-seeding: whole definition ─────────────────────────────────────
  "claims-seeding": snippetFromDefinition(
    sudokuComponentSource, paths.sudokuComponent, "gleam", "fn seed_givens(",
  ),

  // ── anchors-not-offsets: whole definition (comment auto-included) ────────
  "anchors-not-offsets": snippetFromDefinition(
    textComponentSource, paths.textComponent, "gleam", "fn refresh_anchor(",
  ),

  // ── unsettled-writes: two markers joined with editorial glue ─────────────
  "unsettled-writes": combine(
    snippetFromMarker(tournamentSource, paths.tournament, "gleam", "practice-unsettled-report"),
    snippetFromMarker(tournamentSource, paths.tournament, "gleam", "practice-unsettled-atomic"),
    paths.tournament,
    "\n\n// ... and in the register event handler:\n",
  ),

  // ── deterministic-death: whole test definition ───────────────────────────
  "deterministic-death": snippetFromDefinition(
    queueTestSource, paths.queueTest, "gleam",
    "pub fn held_job_returns_to_queue_when_holder_disconnects_test(",
  ),
};

// ── Helpers ────────────────────────────────────────────────────────────────

/**
 * Join two snippet extractions into one descriptor. The first snippet's
 * origin is preserved; the second is appended with a separator.
 */
function combine(
  first: Snippet,
  second: Snippet,
  sourcePath: string,
  separator = "\n\n",
): Snippet {
  return {
    code: first.code + separator + second.code,
    language: first.language,
    sourcePath,
    origin: first.origin,
  };
}
