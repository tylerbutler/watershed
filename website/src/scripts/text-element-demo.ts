// The shipped editor, live: two `<watershed-textarea>` custom elements — the
// real `watershed_lustre` component, compiled from Gleam — bound to two real
// watershed documents sharing one `SharedText` through the in-memory sluice.
//
// Unlike the mechanics rig above it, this demo contains no editor logic at
// all. The grapheme diff, the one-minimal-op bridge, caret preservation under
// remote edits, the IME composition guard, and the drawn peer cursors are all
// inside the element; this page's whole integration is the custom-element
// contract: assign the live channel to `el.channel`, hand rosters to
// `el.peers`, and listen for `change`/`error`/`cursor` events.
//
// Everything here imports from the `watershed_lustre` build tree — one
// compiled world. Mixing it with the root build the rig demo uses would give
// two copies of every Gleam class, and pattern matches (`instanceof`) across
// copies fail; each demo therefore keeps to its own consistent world.
import { register } from "../../../watershed_lustre/build/dev/javascript/watershed_lustre/watershed_lustre/textarea_element.mjs";
import * as watershed from "../../../watershed_lustre/build/dev/javascript/watershed/watershed.mjs";
import * as runtime from "../../../watershed_lustre/build/dev/javascript/watershed/watershed/runtime.mjs";
import * as sluice from "../../../watershed_lustre/build/dev/javascript/watershed/watershed/sluice_js.mjs";
import { expectOk, type ResultValue } from "./demo/gleam-values.ts";

const SEED =
  "Select a few words here, then look at the other pane. Type in one editor while your caret is in the other — it stays on its text.";
const TEXT_ADDRESS = "prose"; // root-map key holding the text handle
const PUMP_MS = 150; // how long an edit stays "in flight" before the sluice sequences it

interface Pane {
  id: string;
  label: string;
  /** CSS custom property carrying this pane's cursor colour, with fallback. */
  token: string;
  fallback: string;
}

const PANES: Pane[] = [
  { id: "a", label: "Client A", token: "--overprint-deep", fallback: "#c81e78" },
  { id: "b", label: "Client B", token: "--waterline", fallback: "#2563eb" },
];

type SharedText = ResultValue<ReturnType<typeof watershed.create_text>>;

interface Peer {
  id: string;
  label: string;
  colour: string;
  cursor: unknown;
}

interface WatershedTextareaElement extends HTMLElement {
  channel: SharedText;
  peers: Peer[];
}

export function initTextElementDemo(): void {
  const section = document.querySelector("#text-element-demo");
  if (!(section instanceof HTMLElement)) return;

  // Define <watershed-textarea> before touching any instance: a property
  // assigned before the tag upgrades would shadow the class's setter.
  register();

  const styles = getComputedStyle(document.documentElement);
  const colour = (pane: Pane) =>
    styles.getPropertyValue(pane.token).trim() || pane.fallback;

  // One in-memory sluice, two real documents. `connect` handshakes through
  // queued frames, so settle before creating anything.
  const server = sluice.start("demo-tenant", "text-element-demo");
  const docs: Record<string, ReturnType<typeof sluice.connect>> = {};
  for (const pane of PANES) docs[pane.id] = sluice.connect(server, pane.id);
  sluice.settle(server);

  // Client A creates the text, attaches its handle under the root map, and
  // seeds it; client B resolves the same handle — the same bootstrap as the
  // rig demo, all drained before anything is visible.
  const textA = expectOk(
    watershed.create_text(docs["a"]),
    "text element channel creation failed",
  );
  runtime.set(
    watershed.runtime_of(docs["a"]),
    "root",
    TEXT_ADDRESS,
    watershed.text_handle_of(textA),
  );
  watershed.text_insert(textA, 0, SEED);
  sluice.settle(server);
  const stored = expectOk(
    runtime.get(watershed.runtime_of(docs["b"]), "root", TEXT_ADDRESS),
    "text element handle lookup failed",
  );
  const channels: Record<string, SharedText> = {
    a: textA,
    b: expectOk(
      watershed.resolve_text(docs["b"], stored),
      "text element channel resolve failed",
    ),
  };

  // Wire each pane: channel in, events out, the other pane's cursor back in.
  const editors: Record<string, WatershedTextareaElement> = {};
  const cursors: Record<string, unknown> = { a: null, b: null };

  const pushPeers = () => {
    for (const pane of PANES) {
      const other = PANES.find((p) => p.id !== pane.id);
      if (!other) continue;
      const cursor = cursors[other.id];
      editors[pane.id].peers = cursor
        ? [
            {
              id: other.id,
              label: other.label,
              colour: colour(other),
              cursor,
            },
          ]
        : [];
    }
  };

  for (const pane of PANES) {
    const el = section.querySelector<WatershedTextareaElement>(
      `[data-pane="${pane.id}"] watershed-textarea`,
    );
    const count = section.querySelector(`[data-pane="${pane.id}"] [data-count]`);
    const error = section.querySelector(`[data-pane="${pane.id}"] [data-error]`);
    if (!(el instanceof HTMLElement)) return;
    editors[pane.id] = el;

    el.addEventListener("change", (event: Event) => {
      if (!(event instanceof CustomEvent)) return;
      const detail = event.detail;
      if (
        !detail ||
        typeof detail !== "object" ||
        !("length" in detail) ||
        typeof detail.length !== "number"
      ) {
        return;
      }
      if (count instanceof HTMLElement) {
        count.textContent = `${detail.length} graphemes`;
      }
    });
    el.addEventListener("error", (event: Event) => {
      if (!(event instanceof CustomEvent)) return;
      const detail = event.detail;
      if (
        !detail ||
        typeof detail !== "object" ||
        !("message" in detail) ||
        (typeof detail.message !== "string" && detail.message !== null)
      ) {
        return;
      }
      if (error instanceof HTMLElement) error.textContent = detail.message ?? "";
    });
    // The element announces its own selection as content-bound anchors; this
    // page's "presence transport" is a property assignment on the other pane.
    el.addEventListener("cursor", (event) => {
      if (!(event instanceof CustomEvent)) return;
      cursors[pane.id] = event.detail;
      pushPeers();
    });

    el.channel = channels[pane.id];
  }

  // Sequence queued edits on a short heartbeat — long enough that an edit is
  // genuinely optimistic for a beat, short enough to feel live. Re-pushing the
  // rosters after each drain re-resolves any cursor that pointed at content
  // the other replica had not merged yet.
  setInterval(() => {
    if (sluice.pending(server)) {
      sluice.settle(server);
      pushPeers();
    }
  }, PUMP_MS);
}
