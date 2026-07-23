// Live SharedText convergence demo: three real watershed documents share one
// collaboratively-typed string, driven through the in-memory sluice (see
// ./demo/sluice-rig.ts for the shared orchestration). Client A creates the text
// via the JS facade and attaches its handle under the root map; the others
// resolve it. From there, edits are ordinary facade calls the sluice sequences
// — the runtime owns optimistic apply, pending, and resubmit — so the demo just
// diffs each keystroke into ONE minimal grapheme edit and issues
// insert/delete_range/replace_range, always against CRDT grapheme indexes,
// never raw UTF-16 offsets.
import * as watershed from "../../../build/dev/javascript/watershed/watershed_js.mjs";
import * as runtime from "../../../build/dev/javascript/watershed/watershed/runtime_js.mjs";
import * as sluice from "../../../build/dev/javascript/watershed/watershed/sluice_js.mjs";
// The anchor bias enum lives in the sequence lattice SharedText is built on.
import * as bias from "../../../build/dev/javascript/lattice_sequence/lattice_sequence/sequence.mjs";
import { createSluiceRig, some, type RigClient } from "./demo/sluice-rig.ts";
import {
  minimalGraphemeEdit,
  graphemeLength,
  utf16ToGrapheme,
  graphemeToUtf16,
  findGraphemeIndex,
} from "./demo/grapheme.ts";

const CLIENT_IDS = ["a", "b", "c"];
const CLIENT_LABEL: Record<string, string> = {
  a: "Client A",
  b: "Client B",
  c: "Client C",
};
const TEXT_ADDRESS = "prose"; // root-map key holding the text handle

// A grapheme-rich seed. `ri\u0301o` is a base letter + a combining acute — one
// grapheme, one index. `👨‍👩‍👧` is a ZWJ sequence of several code points — still
// one grapheme, one index. `🏞️` carries a variation selector. None of these can
// be split by a CRDT index, because the index counts graphemes, not code units.
const SEED = "ri\u0301o \uD83D\uDEF6 caf\u00E9 \u2615 \uD83D\uDC68\u200D\uD83D\uDC69\u200D\uD83D\uDC67 weir \uD83C\uDFDE\uFE0F";

interface PaneData {
  textarea: HTMLTextAreaElement | null;
  /** A locally-pinned anchor (SharedText anchors are per-replica). */
  anchor: unknown | null;
  /** The grapheme index the anchor was pinned at, for the readout. */
  anchorPinnedAt: number | null;
  /** True between compositionstart and compositionend (IME/dead keys). */
  composing: boolean;
  /**
   * The textarea's value captured at compositionstart. The composed edit is
   * diffed against this snapshot — in *base* grapheme coordinates — so a
   * delivery landing mid-composition is not reverted.
   */
  compBase: string | null;
  /**
   * CRDT anchors for every base grapheme gap, captured at compositionstart
   * while the CRDT still equals `compBase`. `compStartAnchors[g]` marks the
   * start endpoint of gap `g` (Before bias), `compEndAnchors[g]` the end
   * endpoint (After bias). Resolving them on compositionend translates the
   * base-coordinate diff into *current* CRDT indexes, so a remote insert that
   * advanced the text mid-composition can't push the composed run off target.
   */
  compStartAnchors: unknown[] | null;
  compEndAnchors: unknown[] | null;
}

function pane(client: RigClient): PaneData {
  return client.data as unknown as PaneData;
}
function okValue<T>(result: unknown): T {
  return (result as { 0: T })[0];
}
function isOk(result: unknown): boolean {
  return (
    !!result &&
    typeof result === "object" &&
    "isOk" in result &&
    (result as { isOk(): boolean }).isOk()
  );
}
function value(client: RigClient): string {
  return watershed.text_value(client.handle) as string;
}

export function initTextDemo() {
  let rig: ReturnType<typeof createSluiceRig> = null;
  // Monotonic per-op marker so each in-flight edit contributes to the pending
  // count and clears when acked.
  let opSeq = 0;

  function submitEdit(
    client: RigClient,
    write: () => void,
    label: string,
  ) {
    if (!rig) return;
    const marker = `${client.id}:${opSeq++}`;
    rig.submit(client, marker, write, label);
  }

  // ── local edits (all indexes are grapheme indexes) ─────────────────────────

  type EditKind = "insert" | "delete" | "replace";
  function editKind(edit: { start: number; end: number; insert: string }): EditKind {
    if (edit.start === edit.end) return "insert";
    return edit.insert === "" ? "delete" : "replace";
  }

  // Issue one grapheme edit at already-resolved CRDT indexes. Shared by
  // ordinary typing (indexes come straight from the diff) and IME finalize
  // (indexes come from resolving base-gap anchors against the current CRDT), so
  // both paths ship exactly one insert/delete/replace — never a duplicate.
  function dispatchEdit(
    client: RigClient,
    kind: EditKind,
    start: number,
    end: number,
    insert: string,
  ) {
    if (kind === "insert") {
      submitEdit(
        client,
        () => watershed.text_insert(client.handle, start, insert),
        `insert "${clip(insert)}" @${start}`,
      );
    } else if (kind === "delete") {
      submitEdit(
        client,
        () => watershed.text_delete_range(client.handle, start, end),
        `delete ${start}..${end}`,
      );
    } else {
      submitEdit(
        client,
        () => watershed.text_replace_range(client.handle, start, end, insert),
        `replace ${start}..${end} "${clip(insert)}"`,
      );
    }
  }

  // Ordinary (non-composing) keystroke: diff against the current optimistic
  // string, which `renderPane` keeps the textarea equal to between edits, so
  // the diff indexes are already current CRDT indexes.
  function syncFromTextarea(client: RigClient) {
    const ta = pane(client).textarea;
    if (!ta) return;
    const edit = minimalGraphemeEdit(value(client), ta.value);
    if (!edit) return;
    dispatchEdit(client, editKind(edit), edit.start, edit.end, edit.insert);
  }

  // A CRDT anchor for base grapheme gap `g`. Biases are chosen so the eventual
  // range covers exactly the base content the diff named, excluding concurrent
  // boundary inserts:
  //   • start endpoint (Before): binds to the grapheme AT `g`, so a concurrent
  //     insert exactly at that gap is pushed outside (before) the range.
  //   • end endpoint (After): binds to the grapheme at `g - 1`, so a concurrent
  //     insert exactly at that gap is pushed outside (after) the range.
  // Extremes bind to the whole-text endpoints: gap 0 → start anchor; a tail
  // *insert* (start endpoint at gap === len) → end anchor, which tracks growth
  // so the composed run lands after text a remote replica inserted earlier
  // during the composition (the bug this fixes) rather than several graphemes
  // early. A tail *range* end (end endpoint at gap === len) still binds to the
  // last base grapheme via After, so remote-appended text is preserved.
  function gapAnchor(
    client: RigClient,
    g: number,
    len: number,
    role: "start" | "end",
  ): unknown {
    if (g <= 0) return watershed.text_start_anchor();
    if (role === "start" && g >= len) return watershed.text_end_anchor();
    const b = role === "start" ? new bias.Before() : new bias.After();
    const result = watershed.text_anchor_at(client.handle, g, b);
    if (isOk(result)) return okValue(result);
    return role === "start"
      ? watershed.text_start_anchor()
      : watershed.text_end_anchor();
  }

  function resolveGap(client: RigClient, anchor: unknown): number {
    const result = watershed.text_resolve_anchor(client.handle, anchor);
    return isOk(result)
      ? okValue<number>(result)
      : (watershed.text_length(client.handle) as number);
  }

  // IME composition finished: diff the composed run against the compositionstart
  // snapshot (base coordinates), translate its endpoints through the base-gap
  // anchors into current CRDT indexes, then ship one edit — so a remote insert
  // that advanced the text mid-composition can't misplace it. Finally reconcile
  // any reflow deferred while composing (renderPane no longer skips the write
  // once `composing` is false), and clear all composition state.
  function finalizeComposition(client: RigClient) {
    const data = pane(client);
    const ta = data.textarea;
    const base = data.compBase;
    const starts = data.compStartAnchors;
    const ends = data.compEndAnchors;
    data.composing = false;
    data.compBase = null;
    data.compStartAnchors = null;
    data.compEndAnchors = null;
    if (ta && base != null && starts && ends) {
      const edit = minimalGraphemeEdit(base, ta.value);
      if (edit) {
        const kind = editKind(edit);
        const start = resolveGap(client, starts[edit.start]);
        const end =
          kind === "insert" ? start : resolveGap(client, ends[edit.end]);
        dispatchEdit(client, kind, start, end, edit.insert);
      }
    }
    renderPane(client);
  }

  function clip(s: string): string {
    return s.length > 12 ? s.slice(0, 12) + "…" : s;
  }

  function localAppend(clientId: string) {
    if (!rig) return;
    const client = rig.clients[clientId];
    const add = " \u21e3"; // a downstream arrow, unmistakable at the tail
    submitEdit(
      client,
      () => watershed.text_append(client.handle, add),
      `append "${clip(add)}"`,
    );
  }

  function pinAnchor(clientId: string) {
    if (!rig) return;
    const client = rig.clients[clientId];
    const data = pane(client);
    const ta = data.textarea;
    if (!ta) return;
    const gi = utf16ToGrapheme(value(client), ta.selectionStart);
    // `After` bias glues the anchor to the grapheme before the gap, so text
    // inserted at the caret lands after the anchor and it stays put.
    const result = watershed.text_anchor_at(client.handle, gi, new bias.After());
    if (!isOk(result)) return;
    data.anchor = okValue(result);
    data.anchorPinnedAt = gi;
    renderPane(client);
  }

  function clearAnchor(clientId: string) {
    if (!rig) return;
    const client = rig.clients[clientId];
    const data = pane(client);
    data.anchor = null;
    data.anchorPinnedAt = null;
    renderPane(client);
  }

  // ── rendering ──────────────────────────────────────────────────────────────
  function renderPane(client: RigClient) {
    const data = pane(client);
    const ta = data.textarea;
    if (!ta) return;
    const optimistic = value(client);

    // Only touch the textarea when its text actually differs, so local typing
    // keeps its native caret. When a remote op reflows the text under a focused
    // caret, remap the caret by grapheme index so it never lands mid-cluster.
    // While an IME composition is active, defer this reconciliation entirely —
    // overwriting value/caret mid-composition would cancel the IME; the pending
    // reflow is re-applied from finalizeComposition on compositionend.
    if (!data.composing && ta.value !== optimistic) {
      const focused = document.activeElement === ta;
      const caretG = focused
        ? utf16ToGrapheme(ta.value, ta.selectionStart)
        : 0;
      ta.value = optimistic;
      if (focused) {
        const clamped = Math.min(caretG, graphemeLength(optimistic));
        const offset = graphemeToUtf16(optimistic, clamped);
        ta.setSelectionRange(offset, offset);
      }
    }

    const pending = client.pending.length > 0;
    client.el.classList.toggle("pending", pending);

    const badge = client.el.querySelector("[data-pending-count]");
    if (badge instanceof HTMLElement) {
      badge.textContent = `${client.pending.length} pending`;
      badge.classList.toggle("is-pending", pending);
    }
    const count = client.el.querySelector("[data-grapheme-count]");
    if (count instanceof HTMLElement) {
      count.textContent = `${graphemeLength(optimistic)} graphemes`;
    }

    // Anchor readout: a pinned anchor is a local, unsequenced annotation, so it
    // prints in magenta. Resolve it every render to show it tracking edits.
    const readout = client.el.querySelector("[data-anchor-readout]");
    if (readout instanceof HTMLElement) {
      if (data.anchor == null || data.anchorPinnedAt == null) {
        readout.textContent = "no anchor pinned";
        readout.classList.remove("is-pinned");
      } else {
        const resolved = watershed.text_resolve_anchor(
          client.handle,
          data.anchor,
        );
        readout.classList.add("is-pinned");
        readout.textContent = isOk(resolved)
          ? `anchor pinned @${data.anchorPinnedAt} → now grapheme ${okValue<number>(resolved)}`
          : `anchor pinned @${data.anchorPinnedAt} → re-anchor needed`;
      }
    }
    const clearBtn = client.el.querySelector("[data-anchor-clear]");
    if (clearBtn instanceof HTMLButtonElement) {
      clearBtn.disabled = data.anchor == null;
    }
  }

  rig = createSluiceRig({
    rig: "[data-text-rig]",
    status: "[data-text-status]",
    section: "#text-demo",
    control: "text",
    document: "text-demo",
    clientIds: CLIENT_IDS,
    clientLabel: CLIENT_LABEL,
    setup: (clients, server) => {
      // One client creates the text, attaches it under the root map, and seeds
      // it; the others resolve the shared handle. All of this drains inside
      // setup's settle, so the visible timeline starts clean.
      const a = clients["a"];
      const text = okValue<unknown>(watershed.create_text(a.doc));
      a.handle = text;
      const runtimeA = watershed.runtime_of(a.doc);
      runtime.set(runtimeA, "root", TEXT_ADDRESS, watershed.text_handle_of(text));
      watershed.text_insert(text, 0, SEED);
      sluice.settle(server);
      for (const id of CLIENT_IDS) {
        const client = clients[id];
        if (id !== "a") {
          const rt = watershed.runtime_of(client.doc);
          const stored = some<unknown>(runtime.get(rt, "root", TEXT_ADDRESS));
          client.handle = okValue<unknown>(
            watershed.resolve_text(client.doc, stored),
          );
        }
        const ta = client.el.querySelector("[data-text-editor]");
        client.data = {
          textarea: ta instanceof HTMLTextAreaElement ? ta : null,
          anchor: null,
          anchorPinnedAt: null,
          composing: false,
          compBase: null,
          compStartAnchors: null,
          compEndAnchors: null,
        } as unknown as Record<string, unknown>;
      }
    },
    render: renderPane,
    canonical: (client) => value(client),
  });
  if (!rig) return;

  // ── per-pane editor + actions ──────────────────────────────────────────────
  for (const id of CLIENT_IDS) {
    const client = rig.clients[id];
    const ta = client.el.querySelector("[data-text-editor]");
    if (ta instanceof HTMLTextAreaElement) {
      // The rig's enable pass only re-enables <button>/<input>; textareas start
      // disabled (so the pre-JS/failed-JS page never offers a dead editor) and
      // become editable only once the real runtime is wired up here.
      ta.disabled = false;
      ta.addEventListener("input", (event) => {
        // During composition the browser emits `input` with isComposing=true;
        // skip it so we ship whole graphemes on compositionend, not partial
        // code points — and never a duplicate of the finalize edit.
        if ((event as InputEvent).isComposing || pane(client).composing) return;
        syncFromTextarea(client);
      });
      ta.addEventListener("compositionstart", () => {
        const data = pane(client);
        data.composing = true;
        // Snapshot the pre-composition text and anchor every base grapheme gap
        // NOW, while the CRDT still equals this snapshot, so the composed edit
        // can be translated into current coordinates on compositionend.
        const base = ta.value;
        data.compBase = base;
        const len = graphemeLength(base);
        const starts = new Array<unknown>(len + 1);
        const ends = new Array<unknown>(len + 1);
        for (let g = 0; g <= len; g++) {
          starts[g] = gapAnchor(client, g, len, "start");
          ends[g] = gapAnchor(client, g, len, "end");
        }
        data.compStartAnchors = starts;
        data.compEndAnchors = ends;
      });
      ta.addEventListener("compositionend", () => finalizeComposition(client));
    }
    client.el
      .querySelector("[data-anchor-pin]")
      ?.addEventListener("click", () => pinAnchor(id));
    client.el
      .querySelector("[data-anchor-clear]")
      ?.addEventListener("click", () => clearAnchor(id));
    client.el
      .querySelector("[data-text-append]")
      ?.addEventListener("click", () => localAppend(id));
  }

  // Crowd an insert: B and C insert different words at the same grapheme
  // position (just before "weir"), concurrently. Both survive and converge.
  document
    .querySelector("[data-text-race-insert]")
    ?.addEventListener("click", () => {
      if (!rig) return;
      const b = rig.clients["b"];
      const c = rig.clients["c"];
      const at = findGraphemeIndex(value(b), "weir");
      if (at == null) return;
      submitEdit(
        b,
        () => watershed.text_insert(b.handle, at, "still "),
        `insert "still " @${at}`,
      );
      const atC = findGraphemeIndex(value(c), "weir");
      if (atC == null) return;
      submitEdit(
        c,
        () => watershed.text_insert(c.handle, atC, "calm "),
        `insert "calm " @${atC}`,
      );
    });

  // Overlapping edit: B replaces "weir" with "levee" while C deletes an
  // overlapping span across it — concurrent edits to one region, deterministic
  // convergence.
  document
    .querySelector("[data-text-race-overlap]")
    ?.addEventListener("click", () => {
      if (!rig) return;
      const b = rig.clients["b"];
      const c = rig.clients["c"];
      const at = findGraphemeIndex(value(b), "weir");
      if (at == null) return;
      submitEdit(
        b,
        () => watershed.text_replace_range(b.handle, at, at + 4, "levee"),
        `replace ${at}..${at + 4} "levee"`,
      );
      const atC = findGraphemeIndex(value(c), "weir");
      if (atC == null) return;
      submitEdit(
        c,
        () => watershed.text_delete_range(c.handle, atC + 1, atC + 3),
        `delete ${atC + 1}..${atC + 3}`,
      );
    });

  document
    .querySelector("[data-text-reset]")
    ?.addEventListener("click", () => {
      opSeq = 0;
      rig?.reset();
    });
}
