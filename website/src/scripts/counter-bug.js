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
//     them. The identical race converges on the correct total — the ops no
//     longer contend for one cell. This is exactly the accounting watershed's
//     SharedCounter does for you.
import { annotate } from "rough-notation";
import * as mapKernel from "../../../build/dev/javascript/watershed/watershed/map_kernel.mjs";
import * as json from "../../../build/dev/javascript/gleam_json/gleam/json.mjs";
import { toList } from "../../../build/dev/javascript/watershed/gleam.mjs";

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

const prefersReducedMotion = () =>
  window.matchMedia("(prefers-reduced-motion: reduce)").matches;

const wait = (ms) =>
  prefersReducedMotion()
    ? Promise.resolve()
    : new Promise((resolve) => setTimeout(resolve, ms));

// ── the shared engine ───────────────────────────────────────────────────────
// One `map_kernel` state per client, plus a FIFO sequencer. `mode` decides
// whether the two houses write the same key (bug) or their own key (fix).
function makeRig(root, mode) {
  const cells = {
    a: root.querySelector('[data-cell="a"]'),
    b: root.querySelector('[data-cell="b"]'),
  };
  const totals = {
    a: root.querySelector('[data-total="a"]'),
    b: root.querySelector('[data-total="b"]'),
  };
  const log = root.querySelector("[data-log]");
  const caption = root.querySelector("[data-caption]");
  const seqTrack = root.querySelector("[data-seq]");

  const keyFor = (id) => (mode === "fix" ? `${KEY}/${id}` : KEY);

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
      cell.textContent = pending == null ? String(cellValue(client, id)) : String(pending);
      cell.classList.toggle("pending", pending != null);
      if (totals[id]) totals[id].textContent = String(total(client));
    }
  }

  // The visible cell shows the value this house last read/holds for its own key.
  function cellValue(client, id) {
    return readInt(mapKernel.get(client.map, keyFor(id))) ?? 0;
  }

  function logLine(text, tone = "") {
    const li = document.createElement("li");
    li.textContent = text;
    if (tone) li.dataset.tone = tone;
    log.appendChild(li);
    log.scrollTop = log.scrollHeight;
    return li;
  }

  function seqTick(label) {
    const chip = document.createElement("span");
    chip.className = "cb-seq-chip";
    chip.textContent = label;
    seqTrack.appendChild(chip);
    return chip;
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
    clearMarks();
    clients.a.map = mapKernel.from_sequenced(seedEntries("a"));
    clients.b.map = mapKernel.from_sequenced(seedEntries("b"));
    clients.a.pending = null;
    clients.b.pending = null;
    log.replaceChildren();
    seqTrack.replaceChildren();
    const verdict = root.querySelector("[data-verdict]");
    if (verdict) verdict.hidden = true;
    caption.textContent = root.dataset.captionIdle || "";
    root.dataset.state = "idle";
    render();
  }

  return {
    root,
    mode,
    cells,
    totals,
    caption,
    clients,
    render,
    reset,
    mark,
    clearMarks,
    logLine,
    seqTick,
    readModifyWrite,
    deliver,
    total,
  };
}

// ── choreography: the buggy race ────────────────────────────────────────────
async function playBug(rig) {
  const magenta = cssVar("--overprint");
  const blue = cssVar("--waterline");
  const ink = cssVar("--ink");
  rig.reset();
  rig.root.dataset.state = "running";

  rig.caption.textContent = "Both gauge houses agree: 41 boats locked through today.";
  await wait(700);

  // 1 — both read the shared tally
  rig.mark(rig.cells.a, { type: "box", color: blue, strokeWidth: 2, padding: 5 });
  rig.mark(rig.cells.b, { type: "box", color: blue, strokeWidth: 2, padding: 5 });
  rig.caption.textContent = "A boat locks through each house at the same moment. Both read the tally: 41.";
  rig.logLine("A reads boats-locked → 41");
  rig.logLine("B reads boats-locked → 41");
  await wait(1300);

  // 2 — both write value + 1 locally (pending)
  const a = rig.readModifyWrite("a");
  rig.render();
  rig.mark(rig.cells.a, { type: "underline", color: magenta, strokeWidth: 3, padding: 2 });
  rig.logLine(`A writes boats-locked = 41 + 1 = 42 · sent`, "pending");
  await wait(650);

  const b = rig.readModifyWrite("b");
  rig.render();
  rig.mark(rig.cells.b, { type: "underline", color: magenta, strokeWidth: 3, padding: 2 });
  rig.logLine(`B writes boats-locked = 41 + 1 = 42 · sent`, "pending");
  rig.caption.textContent = "Each house does read-modify-write on the same cell: 41 + 1 = 42. Both send set(42).";
  await wait(1300);

  // 3 — the sequencer orders them: A then B, last write wins
  rig.seqTick("SN 1 · A set 42");
  await wait(500);
  rig.seqTick("SN 2 · B set 42");
  rig.caption.textContent = "The sequencer orders the stream: A then B. Last write wins — B's set(42) lands on top of A's.";
  await wait(900);

  // 4 — deliver both to both replicas; converge on 42
  rig.deliver(rig.clients.a, "a", a.op);
  rig.deliver(rig.clients.b, "a", a.op);
  rig.deliver(rig.clients.a, "b", b.op);
  rig.deliver(rig.clients.b, "b", b.op);
  rig.clients.a.pending = null;
  rig.clients.b.pending = null;
  rig.render();
  await wait(500);

  // 5 — the verdict, drawn in
  const verdict = rig.root.querySelector("[data-verdict]");
  verdict.hidden = false;
  const recorded = rig.root.querySelector("[data-recorded]");
  const expected = rig.root.querySelector("[data-expected]");
  recorded.textContent = String(rig.total(rig.clients.a)); // real converged value
  expected.textContent = String(BASE + 2); // two boats actually locked through
  rig.mark(expected, { type: "crossed-off", color: magenta, strokeWidth: 3, padding: 4 });
  await wait(650);
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
  await wait(650);

  rig.logLine("A reads boats-locked/a → 20");
  rig.logLine("B reads boats-locked/b → 21");
  await wait(700);

  const a = rig.readModifyWrite("a");
  rig.render();
  rig.logLine("A writes boats-locked/a = 21 · sent", "pending");
  await wait(550);
  const b = rig.readModifyWrite("b");
  rig.render();
  rig.logLine("B writes boats-locked/b = 22 · sent", "pending");
  rig.caption.textContent = "The two writes touch different keys — they can't overwrite each other.";
  await wait(900);

  rig.seqTick("SN 1 · A set /a=21");
  await wait(450);
  rig.seqTick("SN 2 · B set /b=22");
  await wait(700);

  rig.deliver(rig.clients.a, "a", a.op);
  rig.deliver(rig.clients.b, "a", a.op);
  rig.deliver(rig.clients.a, "b", b.op);
  rig.deliver(rig.clients.b, "b", b.op);
  rig.clients.a.pending = null;
  rig.clients.b.pending = null;
  rig.render();
  await wait(450);

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

export function initCounterBug() {
  const bugRoot = document.querySelector('[data-counter-bug="bug"]');
  const fixRoot = document.querySelector('[data-counter-bug="fix"]');
  if (!bugRoot) return;

  const bug = makeRig(bugRoot, "bug");
  const fix = fixRoot ? makeRig(fixRoot, "fix") : null;
  bug.reset();
  if (fix) fix.reset();

  let running = false;
  async function run(fn, rig) {
    if (running) return;
    running = true;
    bugRoot.querySelectorAll("button").forEach((b) => (b.disabled = true));
    fixRoot?.querySelectorAll("button").forEach((b) => (b.disabled = true));
    try {
      await fn(rig);
    } catch (error) {
      console.error("watershed counter-bug demo failed", error);
    } finally {
      bugRoot.querySelectorAll("button").forEach((b) => (b.disabled = false));
      fixRoot?.querySelectorAll("button").forEach((b) => (b.disabled = false));
      running = false;
    }
  }

  bugRoot.querySelector("[data-play]")?.addEventListener("click", () => run(playBug, bug));
  bugRoot.querySelector("[data-reset]")?.addEventListener("click", () => bug.reset());
  fixRoot?.querySelector("[data-play]")?.addEventListener("click", () => run(playFix, fix));
  fixRoot?.querySelector("[data-reset]")?.addEventListener("click", () => fix.reset());

  // Reposition annotations if the viewport changes mid-view (rough-notation
  // draws to absolute page coordinates). Cheapest safe response: clear them.
  window.addEventListener("resize", () => {
    if (running) return;
    bug.clearMarks();
    fix?.clearMarks();
  });
}
