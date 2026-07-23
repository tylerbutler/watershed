// Live SharedRichText convergence demo: three real Quill editors share one
// rich_text (Quill-Delta-shaped OT) document, driven through the in-memory
// sluice (see ./demo/sluice-rig.ts for the shared orchestration) exactly like
// ../json-ot-demo.ts. rich_text is the *other* single-op-in-flight OT kernel —
// same client-transform protocol as json_ot, but its algebra is quill-delta's
// retain/insert/delete + attribute patches + embeds, addressed by UTF-16 code
// unit, not a JSON path. This file only bridges the real generated
// `runtime_js`/`rich_text` modules to a real Quill instance through the
// approved ./demo/rich-text-adapter.js; it never reimplements OT or transform.
//
// Each editor:
//   - submits only user-sourced Quill deltas, decoded through the generated
//     `rich_text` codec (`delta_from_json_string`) and routed through
//     `runtime_js.submit_rich_text` via the shared rig's `submit` (so pending
//     markers, op log, and convergence status all come from the same place
//     every other rig demo uses);
//   - applies remote deltas incrementally via `runtime_js.subscribe` — no
//     polling of the full document after an edit, only on setup/reset;
//   - keeps Quill's native History (undo/redo) scoped to user edits only
//     (`history: { userOnly: true }`), so remote "api"-sourced updates never
//     land on the local undo stack but still shift it correctly;
//   - renders peer selections via quill-cursors, reconciled through the same
//     adapter used for real Quill instances everywhere else. Presence has no
//     ripple-capable path through the in-memory sluice (`sluice_js`/`sluice`
//     never route `send_ripple`/`subscribe_ripples`), so peer selections
//     travel over a small isolated in-page roster broadcaster instead — it
//     exercises the identical adapter reconciliation semantics the real
//     ripple transport would. That broadcaster is synchronous (same-page,
//     no simulated latency) and always races ahead of the rig's
//     latency-modelled op delivery, so a remote RichTextChanged's author
//     entry is already post-edit by the time it lands here; `applyChange`
//     is called with `authorSelectionAlreadyApplied: true` so the adapter
//     leaves that one cached entry alone instead of double-shifting it.
import * as watershed from "../../../build/dev/javascript/watershed/watershed_js.mjs";
import * as runtime from "../../../build/dev/javascript/watershed/watershed/runtime_js.mjs";
import * as richText from "../../../build/dev/javascript/watershed/watershed/rich_text.mjs";
import * as channel from "../../../build/dev/javascript/watershed/watershed/channel.mjs";
import * as handle from "../../../build/dev/javascript/watershed/watershed/handle.mjs";
import * as sluice from "../../../build/dev/javascript/watershed/watershed/sluice_js.mjs";
import * as json from "../../../build/dev/javascript/gleam_json/gleam/json.mjs";
import {
  createSluiceRig,
  some,
  type Delivery,
  type RigClient,
} from "./demo/sluice-rig.ts";
import {
  createRichTextAdapter,
  type RichTextAdapter,
  type PeerSelectionEntry,
  type RichTextSelection,
} from "./demo/rich-text-adapter.js";

import Quill from "quill";
import "quill/dist/quill.snow.css";
import QuillCursors from "quill-cursors";

Quill.register("modules/cursors", QuillCursors);

// ── Quill delta <-> generated rich_text codec ───────────────────────────────
// The generated codec's `delta_from_json`/`delta_to_json` (de)serialize a
// *bare* array of ops (`[{...}, ...]`), matching every `test/fixtures/
// shared_rich_text/*.json` fixture's `base`/`deltas.*` shape — not Quill's
// own `{ops: [...]}` wrapper. Quill's own `Delta` constructor happens to
// accept a bare op array directly (`new Delta(opsArray)`), so the bare array
// is exactly what both `updateContents`/`setContents` and this codec want.
type QuillOp = Record<string, unknown>;

function resultOk<T>(result: unknown): result is { 0: T } {
  return (result as { isOk(): boolean }).isOk();
}

/** Decode a Quill Delta's `.ops` (or a bare op array) through the generated
 * codec, or `null` on a decode `Error` (logged, never thrown/swallowed). */
function decodeDelta(ops: QuillOp[], context: string): unknown | null {
  const result = richText.delta_from_json_string(JSON.stringify(ops));
  if (resultOk<unknown>(result)) return (result as { 0: unknown })[0];
  console.error(
    `watershed rich-text demo: could not decode ${context} as a rich_text delta`,
    (result as { 0: unknown })[0],
  );
  return null;
}

function deltaToOps(delta: unknown): QuillOp[] {
  return JSON.parse(json.to_string(richText.delta_to_json(delta))) as QuillOp[];
}

function documentToOps(document: unknown): QuillOp[] {
  return JSON.parse(
    json.to_string(richText.document_to_json(document)),
  ) as QuillOp[];
}

function opsOf(delta: unknown): QuillOp[] {
  if (Array.isArray(delta)) return delta as QuillOp[];
  const withOps = delta as { ops?: QuillOp[] };
  return withOps.ops ?? [];
}

/**
 * The adapter's `TransformSelection` callback: reorders args to
 * `(selection, delta, isOwnOperation)`, calls the generated
 * `rich_text.transform_selection(delta, selection, isOwnOperation)`, and
 * unwraps its `Result(Selection, Error)` — falling back to the
 * untransformed selection and logging on `Error` rather than ever passing
 * the `Result` wrapper through as a selection.
 */
function transformSelection(
  selection: RichTextSelection,
  delta: unknown,
  isOwnOperation: boolean,
): RichTextSelection {
  const gleamDelta = decodeDelta(opsOf(delta), "a peer-selection delta");
  if (gleamDelta == null) return selection;
  const length = Math.max(0, selection.length);
  const selResult = richText.selection(Math.max(0, selection.index), length);
  if (!resultOk<unknown>(selResult)) return selection;
  const transformed = richText.transform_selection(
    gleamDelta,
    (selResult as { 0: unknown })[0],
    isOwnOperation,
  );
  if (!resultOk<unknown>(transformed)) {
    console.error(
      "watershed rich-text demo: transform_selection failed",
      (transformed as { 0: unknown })[0],
    );
    return selection;
  }
  const out = (transformed as { 0: unknown })[0];
  return {
    index: richText.selection_index(out),
    length: richText.selection_length(out),
  };
}

// ── Describing an op for the shared op log / pending marker label ──────────
function describeOps(ops: QuillOp[]): string {
  let cursor = 0;
  for (const op of ops) {
    if (typeof op.retain === "number") {
      const attrs = op.attributes as Record<string, unknown> | undefined;
      if (attrs) return `format ${Object.keys(attrs).join(",")} @${cursor}`;
      cursor += op.retain;
      continue;
    }
    if (typeof op.delete === "number") return `delete ${op.delete} @${cursor}`;
    if (op.insert !== undefined) {
      if (typeof op.insert === "string") {
        const preview =
          op.insert.length > 10 ? `${op.insert.slice(0, 10)}…` : op.insert;
        return `insert “${preview}” @${cursor}`;
      }
      const kind = Object.keys(op.insert as Record<string, unknown>)[0] ?? "embed";
      return `insert ${kind} @${cursor}`;
    }
  }
  return "no-op";
}

// ── Client identity / colors ────────────────────────────────────────────────
const CLIENT_IDS = ["a", "b", "c"];
const CLIENT_LABEL: Record<string, string> = {
  a: "Client A",
  b: "Client B",
  c: "Client C",
};
// A third, locally-scoped accent alongside the site's magenta/waterline pair —
// see the component stylesheet for `--client-a/b/c`.
const PEER_META: Record<string, { name: string; color: string }> = {
  a: { name: "Client A", color: "var(--client-a)" },
  b: { name: "Client B", color: "var(--client-b)" },
  c: { name: "Client C", color: "var(--client-c)" },
};

const DOC_KEY = "doc"; // root-map key holding the shared rich-text handle

const BASELINE_OPS: QuillOp[] = [
  { insert: "Watershed " },
  { insert: "keeps", attributes: { bold: true } },
  { insert: " every replica in the " },
  { insert: "same state", attributes: { color: "#9d174d" } },
  { insert: ".\n" },
];

const IMAGE_DATA_URI =
  "data:image/svg+xml;utf8," +
  encodeURIComponent(
    '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="40">' +
      '<rect width="64" height="40" fill="#e8e3d8" stroke="#25203a"/>' +
      '<text x="32" y="24" font-size="11" text-anchor="middle" fill="#7a2455">stake</text>' +
      "</svg>",
  );

interface Handle {
  runtime: unknown;
  address: string;
}
function h(client: RigClient): Handle {
  return client.handle as Handle;
}
function okValue<T>(result: unknown): T {
  return (result as { 0: T })[0];
}

interface ClientUI {
  quill: InstanceType<typeof Quill>;
  adapter: RichTextAdapter;
  cursors: QuillCursors;
  knownCursors: Set<string>;
}

function optimisticDocument(client: RigClient): unknown | null {
  const hd = h(client);
  return some<unknown>(runtime.rich_text_view(hd.runtime, hd.address));
}

// ── Peer-selection roster: an isolated in-page broadcaster ──────────────────
// The in-memory sluice never routes `send_ripple`/`subscribe_ripples` (its
// `sluice_js`/core have no signal path), so there is no generic ripple
// transport to reuse here. This stand-in exercises the exact same adapter
// (`replacePeerSelections`) every ripple-backed presence integration would
// call — it just delivers synchronously, in-page, instead of over a document
// channel.
function createRoster(clientIds: string[]) {
  const state: Record<string, RichTextSelection | null> = {};
  const adapters: Record<string, RichTextAdapter> = {};
  for (const id of clientIds) state[id] = null;

  function snapshotFor(excludeId: string): PeerSelectionEntry[] {
    return clientIds
      .filter((id) => id !== excludeId && state[id] != null)
      .map((id) => ({
        id,
        selection: state[id],
        name: PEER_META[id].name,
        color: PEER_META[id].color,
      }));
  }

  return {
    register(id: string, adapter: RichTextAdapter) {
      adapters[id] = adapter;
    },
    publish(id: string, selection: RichTextSelection | null) {
      state[id] = selection;
      for (const otherId of clientIds) {
        if (otherId === id) continue;
        adapters[otherId]?.replacePeerSelections(snapshotFor(otherId));
      }
    },
    resetAll() {
      for (const id of clientIds) state[id] = null;
      for (const id of clientIds) adapters[id]?.replacePeerSelections([]);
    },
  };
}

export function initRichTextDemo() {
  const roster = createRoster(CLIENT_IDS);
  let currentRemoteAuthor: RigClient | null = null;
  // Quill instances / adapters must survive `reset()`: the rig wipes each
  // `RigClient.data` back to `{}` on every `boot()` (it's scratch space other
  // demos re-seed fresh each time — see json-ot-demo.ts's `a.data = {...}`).
  // Rich text instead needs the *same* Quill editor and adapter kept across a
  // reset (only their backing runtime/address change), so this demo keeps its
  // own map rather than storing UI state in `client.data`.
  const clientUIs: Record<string, ClientUI> = {};
  let rig: ReturnType<typeof createSluiceRig> = null;

  function ui(client: RigClient): ClientUI {
    return clientUIs[client.id];
  }

  function initClientUI(client: RigClient) {
    const mount = client.el.querySelector("[data-quill-root]");
    if (!(mount instanceof HTMLElement)) {
      throw new Error(`rich-text demo: missing [data-quill-root] for ${client.id}`);
    }
    const quill = new Quill(mount, {
      theme: "snow",
      modules: {
        toolbar: [["bold", "italic", "underline"], ["image"]],
        cursors: { transformOnTextChange: false },
        history: { userOnly: true, delay: 400, maxStack: 100 },
      },
    });
    const cursors = quill.getModule("cursors") as QuillCursors;

    const adapter = createRichTextAdapter({
      editor: quill,
      submitChange: (delta) => {
        const ops = opsOf(delta);
        const gleamDelta = decodeDelta(ops, `${client.id}'s local edit`);
        if (gleamDelta == null) return;
        const hd = h(client);
        rig?.submit(
          client,
          "richtext",
          () => runtime.submit_rich_text(hd.runtime, hd.address, gleamDelta),
          describeOps(ops),
        );
      },
      onLocalSelection: (selection) => roster.publish(client.id, selection),
      onPeerSelections: (peers) => renderPeers(client, peers),
      transformSelection,
      initialPeers: [],
    });
    roster.register(client.id, adapter);

    clientUIs[client.id] = {
      quill,
      adapter,
      cursors,
      knownCursors: new Set<string>(),
    } satisfies ClientUI;
  }

  function renderPeers(client: RigClient, peers: ReadonlyArray<PeerSelectionEntry>) {
    const clientUi = ui(client);
    const seen = new Set<string>();
    for (const peer of peers) {
      const id = String(peer.id);
      seen.add(id);
      if (!clientUi.knownCursors.has(id)) {
        clientUi.cursors.createCursor(
          id,
          String(peer.name ?? id),
          String(peer.color ?? "#7a7a7a"),
        );
        clientUi.knownCursors.add(id);
      }
      if (peer.selection) {
        clientUi.cursors.moveCursor(id, peer.selection);
      } else {
        clientUi.cursors.removeCursor(id);
        clientUi.knownCursors.delete(id);
      }
    }
    for (const id of [...clientUi.knownCursors]) {
      if (!seen.has(id)) {
        clientUi.cursors.removeCursor(id);
        clientUi.knownCursors.delete(id);
      }
    }

    const list = client.el.querySelector("[data-peer-list]");
    if (list) {
      list.replaceChildren();
      for (const peer of peers) {
        const li = document.createElement("li");
        const swatch = document.createElement("span");
        swatch.className = "peer-swatch";
        swatch.style.background = String(peer.color ?? "#7a7a7a");
        const label = document.createElement("span");
        label.textContent = peer.selection
          ? `${peer.name} @${peer.selection.index}${
              peer.selection.length ? `–${peer.selection.index + peer.selection.length}` : ""
            }`
          : `${peer.name} (no selection)`;
        li.append(swatch, label);
        list.append(li);
      }
    }
  }

  function loadBaselineInto(client: RigClient) {
    const clientUi = ui(client);
    const doc = optimisticDocument(client);
    if (doc == null) return;
    clientUi.adapter.loadDocument(documentToOps(doc));
    clientUi.quill.history.clear();
    clientUi.knownCursors.clear();
    clientUi.cursors.clearCursors();
  }

  function seedInto(rt: unknown, address: string) {
    const seed = decodeDelta(BASELINE_OPS, "the baseline seed");
    if (seed == null) return;
    runtime.submit_rich_text(rt, address, seed);
  }

  function render(client: RigClient) {
    const badge = client.el.querySelector("[data-pending-count]");
    if (badge instanceof HTMLElement) {
      const count = client.pending.length;
      badge.textContent = count > 0 ? "in flight / buffered" : "synced";
      badge.classList.toggle("is-pending", count > 0);
    }
    const canonicalEl = client.el.querySelector("[data-canonical]");
    if (canonicalEl) {
      const doc = optimisticDocument(client);
      canonicalEl.textContent = doc == null ? "" : canonicalOf(client, doc);
    }
  }

  function canonicalOf(_client: RigClient, doc: unknown): string {
    const text = documentToOps(doc)
      .map((op) => (typeof op.insert === "string" ? op.insert : op.insert !== undefined ? "▣" : ""))
      .join("")
      .replace(/\n+$/, "");
    return `“${text}”`;
  }

  rig = createSluiceRig({
    rig: "[data-rt-rig]",
    status: "[data-rt-status]",
    section: "#rt-demo",
    control: "rt",
    document: "rich-text-demo",
    clientIds: CLIENT_IDS,
    clientLabel: CLIENT_LABEL,
    onBeforeDeliver: (_delivery: Delivery, author) => {
      currentRemoteAuthor = author;
    },
    setup: (clients, server) => {
      for (const id of CLIENT_IDS) {
        if (!clientUIs[id]) initClientUI(clients[id]);
      }

      const a = clients["a"];
      const rtA = watershed.runtime_of(a.doc);
      const address = okValue<string>(runtime.create_rich_text(rtA));
      seedInto(rtA, address);
      runtime.set(rtA, "root", DOC_KEY, handle.encode_handle(address));
      a.handle = { runtime: rtA, address };
      sluice.settle(server);

      for (const id of CLIENT_IDS) {
        const client = clients[id];
        let rt: unknown;
        let addr: string;
        if (id === "a") {
          rt = rtA;
          addr = address;
        } else {
          rt = watershed.runtime_of(client.doc);
          const stored = some<unknown>(runtime.get(rt, "root", DOC_KEY));
          addr = okValue<string>(handle.parse_handle(stored));
          runtime.resolve_address(rt, addr);
          client.handle = { runtime: rt, address: addr };
        }
        runtime.subscribe(rt, addr, (event: unknown) => {
          if (!(event instanceof channel.RichTextEvent)) return;
          const changed = (event as { 0: { delta: unknown; local: boolean } })[0];
          const ops = deltaToOps(changed.delta);
          ui(client).adapter.applyChange({
            delta: ops,
            local: changed.local,
            author: changed.local ? undefined : (currentRemoteAuthor?.id ?? undefined),
            // This demo's roster (see createRoster above) broadcasts a
            // client's own selection synchronously the instant Quill
            // recomputes it — including right after that client's own
            // local edit — while the corresponding op still travels the
            // rig's simulated network latency. So by the time that op
            // lands here as a remote RichTextChanged, every peer's cache
            // already holds the author's *post-edit* selection, not their
            // pre-edit one. Transforming it again through this same delta
            // (the adapter's default contract) would double-shift it; tell
            // the adapter to leave the author's cached entry untouched
            // while still transforming every other cached peer as usual.
            authorSelectionAlreadyApplied: true,
          });
        });
        loadBaselineInto(client);
      }
      roster.resetAll();
    },
    render,
    canonical: (client) => {
      const doc = optimisticDocument(client);
      return doc == null ? "" : json.to_string(richText.document_to_json(doc));
    },
  });
  if (!rig) return;

  // ── Scenarios ──────────────────────────────────────────────────────────
  function quillOf(id: string) {
    return clientUIs[id].quill;
  }

  function scenarioReset() {
    rig?.reset();
  }

  function scenarioSimultaneousTyping() {
    const a = quillOf("a");
    const b = quillOf("b");
    const at = Math.max(0, Math.floor(Math.min(a.getLength(), b.getLength()) / 2));
    a.insertText(at, "⟨A⟩", "user");
    b.insertText(at, "⟨B⟩", "user");
  }

  function scenarioConcurrentFormat() {
    const a = quillOf("a");
    const c = quillOf("c");
    const len = a.getLength();
    const start = Math.max(0, Math.floor(len / 3));
    const span = Math.max(1, Math.min(6, len - start - 1));
    a.formatText(start, span, "bold", true, "user");
    c.formatText(start, span, "color", "#1d4ed8", "user");
  }

  function scenarioDeletionRace() {
    const a = quillOf("a");
    const b = quillOf("b");
    const len = b.getLength();
    const start = Math.max(0, Math.floor(len / 4));
    const delSpan = Math.max(1, Math.min(4, len - start - 1));
    const fmtSpan = Math.max(1, Math.min(delSpan + 2, len - start - 1));
    b.deleteText(start, delSpan, "user");
    a.formatText(start, fmtSpan, "italic", true, "user");
  }

  function scenarioInsertEmbed() {
    const c = quillOf("c");
    const at = Math.max(0, c.getLength() - 1);
    c.insertEmbed(at, "image", IMAGE_DATA_URI, "user");
  }

  document.querySelector("[data-rt-reset]")?.addEventListener("click", scenarioReset);
  document
    .querySelector("[data-rt-race-type]")
    ?.addEventListener("click", scenarioSimultaneousTyping);
  document
    .querySelector("[data-rt-race-format]")
    ?.addEventListener("click", scenarioConcurrentFormat);
  document
    .querySelector("[data-rt-race-delete]")
    ?.addEventListener("click", scenarioDeletionRace);
  document
    .querySelector("[data-rt-embed]")
    ?.addEventListener("click", scenarioInsertEmbed);
  document.querySelector("[data-rt-step]")?.addEventListener("click", () => rig?.step());
  document
    .querySelector("[data-rt-settle]")
    ?.addEventListener("click", () => rig?.settleNow());
}
