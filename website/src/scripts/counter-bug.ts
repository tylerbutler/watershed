// The counter-in-a-map bug, shown with real Gleam code.
//
// A SharedMap (last-write-wins per key) is the wrong home for a running count.
// The classic footgun is read-modify-write on a shared integer cell: two
// clients read the same value, both write value+1, and the sequencer keeps the
// *last* write outright — one increment silently vanishes (a lost update).
//
// Both rigs below run watershed's real `map_kernel`, compiled with
// `gleam build --target javascript`, over one in-page sequencer that stamps
// sequence numbers (SNs) and broadcasts in FIFO order — the same protocol shape
// a Fluid-compatible service like levee uses. Nothing here is faked:
//
//   • The BUG rig stores the tally in one shared key. Concurrent read-modify-
//     write races drop a boat, because LWW overwrites instead of merging.
//   • The FIX rig stores each gauge house's tally under its own key and sums
//     them (the classic PN-counter construction). The identical race converges
//     on the correct total — the ops no longer contend for one cell.
//   • The COUNTER rig runs the real `counter_kernel` — watershed's
//     SharedCounter engine. Ops are signed deltas (`increment(+1)`,
//     `increment(-1)`); clients never read-modify-write, so there is nothing
//     to overwrite and deltas sum the same in any order.
import { annotate } from "rough-notation";
import * as mapKernel from "../../../build/dev/javascript/watershed/watershed/map_kernel.mjs";
import * as counterKernel from "../../../build/dev/javascript/watershed/watershed/counter_kernel.mjs";
import * as json from "../../../build/dev/javascript/gleam_json/gleam/json.mjs";
import { toList } from "../../../build/dev/javascript/watershed/gleam.mjs";
import { prefersReducedMotion, wait } from "./demo/timing.ts";
import { createOpLog } from "./demo/op-log.ts";

const KEY = "boats-locked";
const BASE = 41; // both houses agree the day started at 41 boats locked through
const BASE_A = 20; // fix rig: A's column …
const BASE_B = 21; // … plus B's column sums to 41

const jsonInt = (n) => json.int(n);

function readInt(optionValue) {
  // `get` returns Option(Json); Some carries its payload at [0]. The gleam
  // encoder stringifies ints, so they round-trip through Number().
  if (optionValue && optionValue[0] !== undefined) {
    return Number(json.to_string(optionValue[0]));
  }
  return null;
}

const cssVar = (name) =>
  getComputedStyle(document.documentElement).getPropertyValue(name).trim();

// ── shared rig chrome ───────────────────────────────────────────────────────
// The UI plumbing every rig shares: value cells, op log, caption, sequencer
// track, playback-speed slider, and rough-notation bookkeeping.
function makeChrome(root) {
  const cells = {
    a: root.querySelector('[data-cell="a"]'),
    b: root.querySelector('[data-cell="b"]'),
  };
  const log = root.querySelector("[data-log]");
  const opLog = createOpLog(log, { mode: "append" });
  const caption = root.querySelector("[data-caption]");
  const seqTrack = root.querySelector("[data-seq]");

  // Animation-speed slider. Lower speed → longer on-screen delays; the outcome
  // is identical at any speed. Defaults to 0.5× (half speed) so the race is
  // easy to follow.
  const paceInput = root.querySelector("[data-cb-pace]");
  const paceOut = root.querySelector("[data-cb-pace-out]");
  let animSpeed = paceInput ? Number(paceInput.value) : 0.5;
  if (paceInput && paceOut) {
    const fmt = (v) => `${v}×`;
    paceOut.textContent = fmt(animSpeed);
    paceInput.addEventListener("input", () => {
      animSpeed = Number(paceInput.value);
      paceOut.textContent = fmt(animSpeed);
    });
  }
  // Scale a base delay to wall-clock ms at the current playback speed.
  const pacedWait = (ms) => wait(ms / animSpeed);

  // A live registry of rough-notation annotations so we can clear them on reset.
  let annotations = [];
  function mark(el, config) {
    if (!el) return null;
    const a = annotate(el, { animate: !prefersReducedMotion(), ...config });
    annotations.push(a);
    a.show();
    return a;
  }
  function clearMarks() {
    for (const a of annotations) a.remove();
    annotations = [];
  }

  function logLine(text, tone = "") {
    const li = document.createElement("li");
    li.textContent = text;
    if (tone) li.dataset.tone = tone;
    opLog.push(li);
    return li;
  }

  function seqTick(label) {
    const chip = document.createElement("span");
    chip.className = "cb-seq-chip";
    chip.textContent = label;
    seqTrack.appendChild(chip);
    return chip;
  }

  function resetChrome() {
    clearMarks();
    opLog.clear();
    seqTrack.replaceChildren();
    const verdict = root.querySelector("[data-verdict]");
    if (verdict) verdict.hidden = true;
    caption.textContent = root.dataset.captionIdle || "";
    root.dataset.state = "idle";
  }

  return {
    cells,
    caption,
    mark,
    clearMarks,
    logLine,
    seqTick,
    resetChrome,
    wait: pacedWait,
  };
}

// ── the map engine ──────────────────────────────────────────────────────────
// One `map_kernel` state per client, plus a FIFO sequencer. `mode` decides
// whether the two houses write the same key (bug) or their own key (fix).
function makeRig(root, mode) {
  const chrome = makeChrome(root);
  const { cells } = chrome;
  const totals = {
    a: root.querySelector('[data-total="a"]'),
    b: root.querySelector('[data-total="b"]'),
  };
  // Fix rig only: the small per-column readout under each house's big number.
  const subcols = {
    a: root.querySelector('[data-subcol="a"]'),
    b: root.querySelector('[data-subcol="b"]'),
  };

  const keyFor = (id) => (mode === "fix" ? `${KEY}/${id}` : KEY);

  const seedEntries = (id) =>
    mode === "fix"
      ? toList([
          [`${KEY}/a`, jsonInt(BASE_A)],
          [`${KEY}/b`, jsonInt(BASE_B)],
        ])
      : toList([[KEY, jsonInt(BASE)]]);

  const clients = {
    a: { id: "a", map: mapKernel.from_sequenced(seedEntries("a")), pending: null },
    b: { id: "b", map: mapKernel.from_sequenced(seedEntries("b")), pending: null },
  };

  function total(client) {
    if (mode === "fix") {
      const a = readInt(mapKernel.get(client.map, `${KEY}/a`)) ?? 0;
      const b = readInt(mapKernel.get(client.map, `${KEY}/b`)) ?? 0;
      return a + b;
    }
    return readInt(mapKernel.get(client.map, KEY)) ?? 0;
  }

  function render() {
    for (const id of ["a", "b"]) {
      const client = clients[id];
      const cell = cells[id];
      const pending = client.pending;
      if (mode === "fix") {
        // The big number is the combined tally the SharedCounter reports; the
        // small label underneath keeps this house's own column visible.
        cell.textContent = String(total(client));
        cell.classList.remove("pending");
        if (subcols[id]) subcols[id].textContent = String(cellValue(client, id));
      } else {
        cell.textContent = pending == null ? String(cellValue(client, id)) : String(pending);
        cell.classList.toggle("pending", pending != null);
      }
      if (totals[id]) totals[id].textContent = String(total(client));
    }
  }

  // The visible cell shows the value this house last read/holds for its own key.
  function cellValue(client, id) {
    return readInt(mapKernel.get(client.map, keyFor(id))) ?? 0;
  }

  // Read-modify-write: read the current value, write value+1 as a local set.
  function readModifyWrite(id) {
    const client = clients[id];
    const key = keyFor(id);
    const read = readInt(mapKernel.get(client.map, key)) ?? 0;
    const next = read + 1;
    const [state, , op] = mapKernel.set(client.map, key, jsonInt(next));
    client.map = state;
    client.pending = mode === "fix" ? null : next; // fix rig shows own column live
    if (mode === "fix") {
      client.map = state; // committed to own key; total recomputes
    }
    return { read, next, op };
  }

  // Deliver a sequenced op to a replica: the author acks, peers apply remotely.
  function deliver(target, originId, op) {
    if (target.id === originId) {
      const result = mapKernel.ack_local(target.map, op);
      if (result.isOk()) target.map = result[0];
    } else {
      const [state] = mapKernel.apply_remote(target.map, op);
      target.map = state;
    }
  }

  function reset() {
    clients.a.map = mapKernel.from_sequenced(seedEntries("a"));
    clients.b.map = mapKernel.from_sequenced(seedEntries("b"));
    clients.a.pending = null;
    clients.b.pending = null;
    chrome.resetChrome();
    render();
  }

  return {
    ...chrome,
    root,
    mode,
    totals,
    clients,
    render,
    reset,
    readModifyWrite,
    deliver,
    total,
  };
}

// ── the counter engine ──────────────────────────────────────────────────────
// One real `counter_kernel` (SharedCounter) state per client. There is no key
// and no read: a local `increment(delta)` applies optimistically and emits the
// delta as the wire op; acks retire pending ops, remote deltas just add.
function makeCounterRig(root) {
  const chrome = makeChrome(root);

  const clients = {
    a: { id: "a", state: counterKernel.from_summary(BASE), pendingOps: 0 },
    b: { id: "b", state: counterKernel.from_summary(BASE), pendingOps: 0 },
  };

  function render() {
    for (const id of ["a", "b"]) {
      const client = clients[id];
      const cell = chrome.cells[id];
      // `state.value` already includes optimistic local increments.
      cell.textContent = String(client.state.value);
      cell.classList.toggle("pending", client.pendingOps > 0);
    }
  }

  // Ship a signed delta. No read of the current tally happens anywhere here.
  function increment(id, delta) {
    const client = clients[id];
    const [state, , op] = counterKernel.increment(client.state, delta);
    client.state = state;
    client.pendingOps += 1;
    return op;
  }

  // Deliver a sequenced op: the author acks (retiring its pending entry, value
  // unchanged — it already applied optimistically), peers add the delta.
  function deliver(target, originId, op) {
    if (target.id === originId) {
      const result = counterKernel.ack_local(target.state, op);
      if (result.isOk()) {
        target.state = result[0];
        target.pendingOps -= 1;
      }
    } else {
      const [state] = counterKernel.apply_remote(target.state, op);
      target.state = state;
    }
  }

  function reset() {
    clients.a.state = counterKernel.from_summary(BASE);
    clients.b.state = counterKernel.from_summary(BASE);
    clients.a.pendingOps = 0;
    clients.b.pendingOps = 0;
    chrome.resetChrome();
    render();
  }

  return { ...chrome, root, clients, render, reset, increment, deliver };
}

// ── choreography: the buggy race ────────────────────────────────────────────
async function playBug(rig) {
  const magenta = cssVar("--overprint");
  const blue = cssVar("--waterline");
  const ink = cssVar("--ink");
  rig.reset();
  rig.root.dataset.state = "running";

  rig.caption.textContent = "Both gauge houses agree: 41 boats locked through today.";
  await rig.wait(700);

  // 1 — both read the shared tally
  rig.mark(rig.cells.a, { type: "box", color: blue, strokeWidth: 2, padding: 5 });
  rig.mark(rig.cells.b, { type: "box", color: blue, strokeWidth: 2, padding: 5 });
  rig.caption.textContent = "A boat locks through each house at the same moment. Both read the tally: 41.";
  rig.logLine("A reads boats-locked → 41");
  rig.logLine("B reads boats-locked → 41");
  await rig.wait(1300);

  // 2 — both write value + 1 locally (pending)
  const a = rig.readModifyWrite("a");
  rig.render();
  rig.mark(rig.cells.a, { type: "underline", color: magenta, strokeWidth: 3, padding: 2 });
  rig.logLine(`A writes boats-locked = 41 + 1 = 42 · sent`, "pending");
  await rig.wait(650);

  const b = rig.readModifyWrite("b");
  rig.render();
  rig.mark(rig.cells.b, { type: "underline", color: magenta, strokeWidth: 3, padding: 2 });
  rig.logLine(`B writes boats-locked = 41 + 1 = 42 · sent`, "pending");
  rig.caption.textContent = "Each house does read-modify-write on the same cell: 41 + 1 = 42. Both send set(42).";
  await rig.wait(1300);

  // 3 — the sequencer orders them: A then B, last write wins
  rig.seqTick("SN 1 · A set 42");
  await rig.wait(500);
  rig.seqTick("SN 2 · B set 42");
  rig.caption.textContent = "The sequencer orders the stream: A then B. Last write wins — B's set(42) lands on top of A's.";
  await rig.wait(900);

  // 4 — deliver both to both replicas; converge on 42
  rig.deliver(rig.clients.a, "a", a.op);
  rig.deliver(rig.clients.b, "a", a.op);
  rig.deliver(rig.clients.a, "b", b.op);
  rig.deliver(rig.clients.b, "b", b.op);
  rig.clients.a.pending = null;
  rig.clients.b.pending = null;
  rig.render();
  await rig.wait(500);

  // 5 — the verdict, drawn in
  const verdict = rig.root.querySelector("[data-verdict]");
  verdict.hidden = false;
  const recorded = rig.root.querySelector("[data-recorded]");
  const expected = rig.root.querySelector("[data-expected]");
  recorded.textContent = String(rig.total(rig.clients.a)); // real converged value
  expected.textContent = String(BASE + 2); // two boats actually locked through
  rig.mark(expected, { type: "crossed-off", color: magenta, strokeWidth: 3, padding: 4 });
  await rig.wait(650);
  rig.mark(recorded, { type: "circle", color: ink, strokeWidth: 3, padding: 8 });
  rig.logLine("converged: boats-locked = 42", "lost");
  rig.caption.textContent =
    "Two boats locked through. The tally moved by one. One boat vanished — LWW overwrote a read-modify-write.";
  rig.root.dataset.state = "done";
}

// ── choreography: the fix, same race, correct total ─────────────────────────
async function playFix(rig) {
  const blue = cssVar("--waterline");
  const ink = cssVar("--ink");
  rig.reset();
  rig.root.dataset.state = "running";

  rig.caption.textContent = "Same start (20 + 21 = 41), but each house tallies its own column.";
  await rig.wait(650);

  rig.logLine("A reads boats-locked/a → 20");
  rig.logLine("B reads boats-locked/b → 21");
  await rig.wait(700);

  const a = rig.readModifyWrite("a");
  rig.render();
  rig.logLine("A writes boats-locked/a = 21 · sent", "pending");
  await rig.wait(550);
  const b = rig.readModifyWrite("b");
  rig.render();
  rig.logLine("B writes boats-locked/b = 22 · sent", "pending");
  rig.caption.textContent = "The two writes touch different keys — they can't overwrite each other.";
  await rig.wait(900);

  rig.seqTick("SN 1 · A set /a=21");
  await rig.wait(450);
  rig.seqTick("SN 2 · B set /b=22");
  await rig.wait(700);

  rig.deliver(rig.clients.a, "a", a.op);
  rig.deliver(rig.clients.b, "a", a.op);
  rig.deliver(rig.clients.a, "b", b.op);
  rig.deliver(rig.clients.b, "b", b.op);
  rig.clients.a.pending = null;
  rig.clients.b.pending = null;
  rig.render();
  await rig.wait(450);

  const verdict = rig.root.querySelector("[data-verdict]");
  verdict.hidden = false;
  const recorded = rig.root.querySelector("[data-recorded]");
  recorded.textContent = String(rig.total(rig.clients.a)); // 21 + 22 = 43
  rig.mark(recorded, { type: "circle", color: blue, strokeWidth: 3, padding: 8 });
  rig.logLine("converged: 21 + 22 = 43", "seq");
  rig.caption.textContent =
    "Both boats counted: 43. Commutative, per-replica tallies converge — the accounting watershed's SharedCounter does for you.";
  rig.root.dataset.state = "done";
}

// ── choreography: the SharedCounter fix — signed deltas through the real
// counter_kernel ────────────────────────────────────────────────────────────
async function playCounter(rig) {
  const blue = cssVar("--waterline");
  const magenta = cssVar("--overprint");
  const ink = cssVar("--ink");
  rig.reset();
  rig.root.dataset.state = "running";

  rig.caption.textContent =
    "Same race, real SharedCounter. Both houses start at 41 — and neither one ever reads the tally.";
  await rig.wait(800);

  // 1 — the same concurrent race, but each house ships a delta, not a value
  const a1 = rig.increment("a", 1);
  rig.render();
  rig.mark(rig.cells.a, { type: "underline", color: blue, strokeWidth: 3, padding: 2 });
  rig.logLine("A sends increment +1 · optimistic 42", "pending");
  await rig.wait(650);

  const b1 = rig.increment("b", 1);
  rig.render();
  rig.mark(rig.cells.b, { type: "underline", color: blue, strokeWidth: 3, padding: 2 });
  rig.logLine("B sends increment +1 · optimistic 42", "pending");
  rig.caption.textContent =
    "No read-modify-write: each op carries +1, not 42. There is no value to overwrite.";
  await rig.wait(1300);

  rig.seqTick("SN 1 · A inc +1");
  await rig.wait(450);
  rig.seqTick("SN 2 · B inc +1");
  await rig.wait(700);

  for (const [origin, op] of [["a", a1], ["b", b1]]) {
    rig.deliver(rig.clients.a, origin, op);
    rig.deliver(rig.clients.b, origin, op);
  }
  rig.render();
  rig.logLine("converged: 41 + 1 + 1 = 43", "seq");
  rig.caption.textContent = "Both deltas land on both replicas: 43. No boat lost.";
  await rig.wait(1100);

  // 2 — deltas are signed: a decrement commutes with an increment the same way
  rig.caption.textContent =
    "Deltas go both ways. Upstream logs another boat (+1) while downstream strikes a double-counted entry (−1) — concurrently.";
  const a2 = rig.increment("a", 1);
  rig.render();
  rig.logLine("A sends increment +1 · optimistic 44", "pending");
  await rig.wait(650);

  const b2 = rig.increment("b", -1);
  rig.render();
  rig.mark(rig.cells.b, { type: "underline", color: magenta, strokeWidth: 3, padding: 2 });
  rig.logLine("B sends increment −1 · optimistic 42", "pending");
  await rig.wait(900);

  rig.caption.textContent =
    "For a moment the replicas read 44 and 42 — then the sequencer orders B's decrement first.";
  rig.seqTick("SN 3 · B inc −1");
  await rig.wait(450);
  rig.seqTick("SN 4 · A inc +1");
  await rig.wait(700);

  for (const [origin, op] of [["b", b2], ["a", a2]]) {
    rig.deliver(rig.clients.a, origin, op);
    rig.deliver(rig.clients.b, origin, op);
  }
  rig.render();
  await rig.wait(500);

  const verdict = rig.root.querySelector("[data-verdict]");
  verdict.hidden = false;
  const recorded = rig.root.querySelector("[data-recorded]");
  recorded.textContent = String(rig.clients.a.state.value); // real converged value
  rig.mark(recorded, { type: "circle", color: ink, strokeWidth: 3, padding: 8 });
  rig.logLine("converged: 43 + 1 − 1 = 43", "seq");
  rig.caption.textContent =
    "Every signed delta counted, in the order the sequencer picked. This is SharedCounter: increments and decrements commute.";
  rig.root.dataset.state = "done";
}

export function initCounterBug() {
  const bugRoot = document.querySelector('[data-counter-bug="bug"]');
  const fixRoot = document.querySelector('[data-counter-bug="fix"]');
  const counterRoot = document.querySelector('[data-counter-bug="counter"]');
  if (!bugRoot) return;

  const bug = makeRig(bugRoot, "bug");
  const fix = fixRoot ? makeRig(fixRoot, "fix") : null;
  const counter = counterRoot ? makeCounterRig(counterRoot) : null;
  const rigs = [bug, fix, counter].filter(Boolean);
  for (const rig of rigs) rig.reset();

  let running = false;
  async function run(fn, rig) {
    if (running) return;
    running = true;
    for (const r of rigs) r.root.querySelectorAll("button").forEach((b) => (b.disabled = true));
    try {
      await fn(rig);
    } catch (error) {
      console.error("watershed counter-bug demo failed", error);
    } finally {
      for (const r of rigs) r.root.querySelectorAll("button").forEach((b) => (b.disabled = false));
      running = false;
    }
  }

  bugRoot.querySelector("[data-play]")?.addEventListener("click", () => run(playBug, bug));
  bugRoot.querySelector("[data-reset]")?.addEventListener("click", () => bug.reset());
  fixRoot?.querySelector("[data-play]")?.addEventListener("click", () => run(playFix, fix));
  fixRoot?.querySelector("[data-reset]")?.addEventListener("click", () => fix.reset());
  counterRoot?.querySelector("[data-play]")?.addEventListener("click", () => run(playCounter, counter));
  counterRoot?.querySelector("[data-reset]")?.addEventListener("click", () => counter.reset());

  // Reposition annotations if the viewport changes mid-view (rough-notation
  // draws to absolute page coordinates). Cheapest safe response: clear them.
  window.addEventListener("resize", () => {
    if (running) return;
    for (const rig of rigs) rig.clearMarks();
  });
}
