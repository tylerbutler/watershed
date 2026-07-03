// Live convergence demo. The two "clients" here each own real watershed
// kernel states — `map_kernel`, `counter_kernel`, and `pn_counter_kernel`,
// the same pure Gleam modules the BEAM runtime uses, compiled with
// `gleam build --target javascript` — and talk through a tiny in-page
// sequencer that stamps sequence numbers (SNs) and broadcasts in order, the
// same protocol shape as a live levee server. All structures ride the one op
// stream, like DDSes sharing a container; the picker only changes which
// replica view is shown.
import * as mapKernel from "../../../build/dev/javascript/watershed/watershed/map_kernel.mjs";
import * as counterKernel from "../../../build/dev/javascript/watershed/watershed/counter_kernel.mjs";
import * as pnKernel from "../../../build/dev/javascript/watershed/watershed/pn_counter_kernel.mjs";
import * as pnLattice from "../../../build/dev/javascript/lattice_counters/lattice_counters/pn_counter.mjs";
import * as gCounter from "../../../build/dev/javascript/lattice_counters/lattice_counters/g_counter.mjs";
import * as replicaId from "../../../build/dev/javascript/lattice_core/lattice_core/replica_id.mjs";
import * as json from "../../../build/dev/javascript/gleam_json/gleam/json.mjs";
import { toList } from "../../../build/dev/javascript/watershed/gleam.mjs";

const GAUGES = ["mill-race", "kettle-run", "low-ford"];
const INITIAL = [
  ["mill-race", 24],
  ["kettle-run", 61],
  ["low-ford", 42],
];
const COUNTER_BASE = 120;
// The PN counter baseline: 74 yd³ of fill placed, 30 yd³ cut — net +44.
// Built as a real CRDT summary under a "survey" replica id, then loaded per
// client via `from_summary`, the same path a reconnecting client takes.
const PN_FILL_BASE = 74;
const PN_CUT_BASE = 30;
const PN_BASE = PN_FILL_BASE - PN_CUT_BASE;

function pnBaselineSummary() {
  let base = pnLattice.new$(replicaId.new$("survey-baseline"));
  base = pnLattice.increment(base, PN_FILL_BASE);
  base = pnLattice.decrement(base, PN_CUT_BASE);
  return json.to_string(pnLattice.to_json(base));
}

const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

function jsonInt(n) {
  return json.int(n);
}

function readInt(optionValue) {
  // `get` returns Option(Json); Some stores its payload at [0]. Json values
  // stringify via the gleam encoder, so ints round-trip through Number().
  if (optionValue && optionValue[0] !== undefined) {
    return Number(json.to_string(optionValue[0]));
  }
  return null;
}

function pendingMapKeys(state) {
  const keys = new Set();
  for (const entry of state.pending.toArray()) {
    if (entry instanceof mapKernel.PendingLifetime) keys.add(entry.key);
    else if (entry instanceof mapKernel.PendingDelete) keys.add(entry.key);
    else for (const k of GAUGES) keys.add(k); // PendingClear masks everything
  }
  return keys;
}

function signed(n) {
  return n < 0 ? `−${Math.abs(n)}` : `+${n}`;
}

function describeOp(ddsId, op) {
  if (ddsId === "counter") return `inc ${signed(op.increment_amount)}`;
  if (ddsId === "pn") {
    return op.amount >= 0
      ? `fill +${op.amount} yd³`
      : `cut −${-op.amount} yd³`;
  }
  if (op instanceof mapKernel.Set) {
    return `set ${op.key} = ${json.to_string(op.value)}`;
  }
  if (op instanceof mapKernel.Delete) return `delete ${op.key}`;
  return "clear";
}

export function initDemo() {
  const rig = document.querySelector("[data-demo-rig]");
  if (!rig) return;

  const flowLayer = rig.querySelector("[data-flow-layer]");
  const seqNode = rig.querySelector("[data-seq-node]");
  const seqCounter = rig.querySelector("[data-seq-counter]");
  const opLog = rig.querySelector("[data-op-log]");
  const statusEl = document.querySelector("[data-status]");
  const latencyInput = document.querySelector("[data-latency]");
  const latencyOut = document.querySelector("[data-latency-out]");
  const raceBtn = document.querySelector("[data-race]");
  const resetBtn = document.querySelector("[data-reset]");
  const replayBtn = document.querySelector("[data-replay]");
  const ddsPicks = document.querySelectorAll("[data-dds-pick]");
  const mergeRules = document.querySelectorAll("[data-merge-rule]");

  // Controls are authored `disabled` so they are never interactive before the
  // kernels are loaded (or at all, if this module fails to boot).
  const demoSection = document.querySelector("#demo");
  for (const el of demoSection.querySelectorAll("button, input")) {
    el.disabled = false;
  }
  // Re-deliver stays dark until a PN delta has actually been sequenced.
  replayBtn.disabled = true;

  const initial = toList(INITIAL.map(([k, v]) => [k, jsonInt(v)]));
  const pnBaseline = pnBaselineSummary();

  const clients = {};
  for (const id of ["a", "b"]) {
    // The PN kernel is replica-identified: each client loads the shared
    // summary under its own id, exactly like a client joining a session.
    const pnLoaded = pnKernel.from_summary(
      pnBaseline,
      replicaId.new$(`client-${id}`),
    );
    if (!pnLoaded.isOk()) throw new Error("pn baseline summary failed to load");
    clients[id] = {
      id,
      map: mapKernel.from_sequenced(initial),
      counter: counterKernel.from_summary(COUNTER_BASE),
      pn: pnLoaded[0],
      el: rig.querySelector(`[data-client="${id}"]`),
      lastArrival: 0, // enforces FIFO delivery from the sequencer
    };
  }

  let activeDds = "map";
  let latency = Number(latencyInput.value);
  let sn = 0;
  let inFlight = 0;
  let seqLastArrival = 0; // FIFO into the sequencer too
  let hasInteracted = false;
  let lastPn = null; // the most recently *sequenced* PN op, for re-delivery

  // ── rendering ─────────────────────────────────────────────────────────────

  function renderMap(client) {
    const pending = pendingMapKeys(client.map);
    for (const key of GAUGES) {
      const row = client.el.querySelector(`tr[data-key="${key}"]`);
      const value = readInt(mapKernel.get(client.map, key));
      row.querySelector("[data-value]").textContent =
        value === null ? "—" : String(value);
      row.classList.toggle("pending", pending.has(key));
    }
  }

  function renderCounter(client) {
    const pending = client.counter.pending.toArray();
    const valueEl = client.el.querySelector("[data-counter-value]");
    valueEl.textContent = String(client.counter.value);
    valueEl.classList.toggle("pending", pending.length > 0);
    const deltaSum = pending.reduce((sum, p) => sum + p.increment_amount, 0);
    const deltaEl = client.el.querySelector("[data-counter-delta]");
    deltaEl.textContent =
      pending.length > 0 ? `Δ ${signed(deltaSum)} unsequenced` : "";
  }

  function renderPn(client) {
    const pending = client.pn.pending.toArray();
    const valueEl = client.el.querySelector("[data-pn-value]");
    // An earthwork balance is signed: net fill above baseline zero.
    valueEl.textContent = signed(pnKernel.value(client.pn));
    valueEl.classList.toggle("pending", pending.length > 0);
    const deltaSum = pending.reduce((sum, p) => sum + p.amount, 0);
    const deltaEl = client.el.querySelector("[data-pn-delta]");
    deltaEl.textContent =
      pending.length > 0 ? `Δ ${signed(deltaSum)} unsequenced` : "";
    // The ledger prints the CRDT's real internal state: the two monotone
    // tallies (P = fill, N = cut) whose difference is the value.
    client.el.querySelector("[data-pn-fill]").textContent = String(
      gCounter.value(client.pn.optimistic.positive),
    );
    client.el.querySelector("[data-pn-cut]").textContent = String(
      gCounter.value(client.pn.optimistic.negative),
    );
  }

  function renderBadge(client) {
    const count = client[activeDds].pending.toArray().length;
    const badge = client.el.querySelector("[data-pending-count]");
    badge.textContent = `${count} pending`;
    if (count === 0) badge.setAttribute("data-zero", "");
    else badge.removeAttribute("data-zero");
  }

  function render(client) {
    renderMap(client);
    renderCounter(client);
    renderPn(client);
    renderBadge(client);
  }

  function pendingTotal() {
    let total = 0;
    for (const client of Object.values(clients)) {
      total += client.map.pending.toArray().length;
      total += client.counter.pending.toArray().length;
      total += client.pn.pending.toArray().length;
    }
    return total;
  }

  function renderStatus() {
    const pending = pendingTotal();
    if (inFlight === 0 && pending === 0) {
      const same =
        JSON.stringify(mapSnapshot(clients.a.map)) ===
          JSON.stringify(mapSnapshot(clients.b.map)) &&
        clients.a.counter.value === clients.b.counter.value &&
        pnKernel.value(clients.a.pn) === pnKernel.value(clients.b.pn);
      statusEl.innerHTML = same
        ? `<span class="stamp converged">Converged</span> replicas identical · nothing pending`
        : `<span class="stamp revising">Diverged</span> this should be impossible — please file a bug`;
    } else {
      statusEl.innerHTML = `<span class="stamp revising">Revising</span> ${inFlight} op${inFlight === 1 ? "" : "s"} in flight · ${pending} pending`;
    }
  }

  function mapSnapshot(state) {
    return mapKernel
      .sequenced_entries(state)
      .toArray()
      .map(([k, v]) => [k, json.to_string(v)]);
  }

  function logOp(stampedSn, origin, ddsId, op) {
    const li = document.createElement("li");
    li.textContent = `#${String(stampedSn).padStart(2, "0")} ${describeOp(ddsId, op)} · from ${origin.toUpperCase()}`;
    opLog.prepend(li);
    while (opLog.children.length > 14) opLog.lastChild.remove();
    seqCounter.textContent = `SN ${stampedSn}`;
    seqCounter.classList.remove("stamped");
    void seqCounter.offsetWidth;
    seqCounter.classList.add("stamped");
  }

  // ── op flow animation ─────────────────────────────────────────────────────

  function anchor(el) {
    const layerBox = flowLayer.getBoundingClientRect();
    const box = el.getBoundingClientRect();
    return [
      box.left + box.width / 2 - layerBox.left,
      box.top + box.height / 2 - layerBox.top,
    ];
  }

  function animateDot(fromEl, toEl, duration, sequenced) {
    if (reducedMotion.matches) return;
    const dot = document.createElement("span");
    dot.className = sequenced ? "flow-dot sequenced" : "flow-dot";
    flowLayer.append(dot);
    const [x0, y0] = anchor(fromEl);
    const [x1, y1] = anchor(toEl);
    const anim = dot.animate(
      [
        { transform: `translate(${x0 - 5}px, ${y0 - 5}px)`, opacity: 0.3 },
        { transform: `translate(${x1 - 5}px, ${y1 - 5}px)`, opacity: 1 },
      ],
      { duration: Math.max(180, duration), easing: "ease-in-out" },
    );
    anim.onfinish = () => dot.remove();
  }

  // ── protocol: client → sequencer → broadcast ──────────────────────────────

  function deliver(target, originId, ddsId, op) {
    if (ddsId === "map") {
      if (target.id === originId) {
        const result = mapKernel.ack_local(target.map, op);
        if (result.isOk()) target.map = result[0];
        else console.error("unexpected ack", result[0]);
      } else {
        const [next] = mapKernel.apply_remote(target.map, op);
        target.map = next;
      }
    } else if (ddsId === "pn") {
      if (target.id === originId) {
        const result = pnKernel.ack_local(target.pn, op);
        if (result.isOk()) target.pn = result[0];
        else console.error("unexpected ack", result[0]);
      } else {
        const [next] = pnKernel.apply_remote(target.pn, op);
        target.pn = next;
      }
    } else {
      if (target.id === originId) {
        const result = counterKernel.ack_local(target.counter, op);
        if (result.isOk()) target.counter = result[0];
        else console.error("unexpected ack", result[0]);
      } else {
        const [next] = counterKernel.apply_remote(target.counter, op);
        target.counter = next;
      }
    }
  }

  function submit(originId, ddsId, op) {
    const origin = clients[originId];
    inFlight += 1;
    renderStatus();
    animateDot(origin.el, seqNode, latency, false);

    // FIFO into the sequencer: an op may not overtake an earlier one even if
    // the latency slider moved while it was in flight.
    const now = performance.now();
    const arrival = Math.max(now + latency, seqLastArrival + 25);
    seqLastArrival = arrival;

    setTimeout(() => {
      sn += 1;
      const stamped = sn;
      logOp(stamped, originId, ddsId, op);
      if (ddsId === "pn") {
        lastPn = { op, sn: stamped };
        replayBtn.disabled = false;
      }

      for (const target of Object.values(clients)) {
        animateDot(seqNode, target.el, latency, true);
        const tNow = performance.now();
        const tArrival = Math.max(tNow + latency, target.lastArrival + 25);
        target.lastArrival = tArrival;
        inFlight += 1;
        setTimeout(() => {
          deliver(target, originId, ddsId, op);
          inFlight -= 1;
          render(target);
          renderStatus();
        }, tArrival - tNow);
      }

      inFlight -= 1;
      renderStatus();
    }, arrival - now);
  }

  function localSet(clientId, key, value) {
    const client = clients[clientId];
    const [next, _events, op] = mapKernel.set(client.map, key, jsonInt(value));
    client.map = next;
    render(client);
    submit(clientId, "map", op);
  }

  function localIncrement(clientId, amount) {
    const client = clients[clientId];
    const [next, _events, op] = counterKernel.increment(client.counter, amount);
    client.counter = next;
    render(client);
    submit(clientId, "counter", op);
  }

  function localPnUpdate(clientId, amount) {
    const client = clients[clientId];
    // `update` also returns the local message id; the demo's sequencer acks
    // in FIFO order, so only the op needs to travel.
    const [next, _events, op] = pnKernel.update(client.pn, amount);
    client.pn = next;
    render(client);
    submit(clientId, "pn", op);
  }

  // The sequencer re-sends an already-sequenced delta to every replica. No
  // new SN is stamped — this is duplicate delivery, the failure mode resends
  // and stash replays produce — and the lattice absorbs it: merge is
  // idempotent, so nothing changes anywhere.
  function redeliverLastPn() {
    const { op, sn: originalSn } = lastPn;
    const li = document.createElement("li");
    li.className = "replay";
    li.textContent = `#${String(originalSn).padStart(2, "0")} again ${describeOp("pn", op)} · absorbed`;
    opLog.prepend(li);
    while (opLog.children.length > 14) opLog.lastChild.remove();

    for (const target of Object.values(clients)) {
      animateDot(seqNode, target.el, latency, true);
      const tNow = performance.now();
      const tArrival = Math.max(tNow + latency, target.lastArrival + 25);
      target.lastArrival = tArrival;
      inFlight += 1;
      setTimeout(() => {
        // Both replicas take the duplicate through `apply_remote` — even the
        // origin, whose acked delta is already merged. Idempotence makes
        // both a no-op.
        const [next] = pnKernel.apply_remote(target.pn, op);
        target.pn = next;
        inFlight -= 1;
        render(target);
        renderStatus();
      }, tArrival - tNow);
    }
    renderStatus();
  }

  // ── wiring ────────────────────────────────────────────────────────────────

  for (const client of Object.values(clients)) {
    client.el.addEventListener("click", (event) => {
      const stepBtn = event.target.closest("button[data-step]");
      if (stepBtn) {
        hasInteracted = true;
        const key = stepBtn.closest("tr").dataset.key;
        const current = readInt(mapKernel.get(client.map, key)) ?? 0;
        localSet(client.id, key, current + Number(stepBtn.dataset.step));
        return;
      }
      const incBtn = event.target.closest("button[data-inc]");
      if (incBtn) {
        hasInteracted = true;
        localIncrement(client.id, Number(incBtn.dataset.inc));
        return;
      }
      const pnBtn = event.target.closest("button[data-pn-inc]");
      if (pnBtn) {
        hasInteracted = true;
        localPnUpdate(client.id, Number(pnBtn.dataset.pnInc));
      }
    });
  }

  const RACE_LABELS = {
    map: "Race a concurrent write",
    counter: "Race concurrent increments",
    pn: "Race fill against cut",
  };
  const RESET_LABELS = {
    map: "Reset all gauges to their surveyed baseline values",
    counter: "Reset the counter to its surveyed baseline value",
    pn: "Reset the earthwork balance to its surveyed baseline",
  };

  for (const pick of ddsPicks) {
    pick.addEventListener("change", () => {
      if (!pick.checked) return;
      activeDds = pick.value;
      rig.dataset.dds = activeDds;
      for (const rule of mergeRules) {
        rule.hidden = rule.dataset.mergeRule !== activeDds;
      }
      raceBtn.textContent = RACE_LABELS[activeDds];
      resetBtn.setAttribute("aria-label", RESET_LABELS[activeDds]);
      replayBtn.hidden = activeDds !== "pn";
      renderBadge(clients.a);
      renderBadge(clients.b);
    });
  }

  latencyInput.addEventListener("input", () => {
    latency = Number(latencyInput.value);
    latencyOut.textContent = `${latency} ms`;
  });

  raceBtn.addEventListener("click", () => {
    hasInteracted = true;
    if (activeDds === "map") {
      // Both clients write the same key inside one latency window. The op the
      // server sequences last wins on every replica — that's LWW, and both
      // replicas agree because they apply ops in the same order.
      const key = GAUGES[Math.floor(Math.random() * GAUGES.length)];
      const base = readInt(mapKernel.get(clients.a.map, key)) ?? 0;
      localSet("a", key, base + 10);
      localSet("b", key, base - 10);
    } else if (activeDds === "pn") {
      // A fills while B cuts, inside one latency window. Both deltas merge —
      // fill and cut are separate monotone tallies — and every replica lands
      // on the same net balance (+3).
      localPnUpdate("a", 8);
      localPnUpdate("b", -5);
    } else {
      // Both clients increment inside one latency window. Neither op wins:
      // increments commute, so every replica lands on the sum (+13).
      localIncrement("a", 8);
      localIncrement("b", 5);
    }
  });

  replayBtn.addEventListener("click", () => {
    hasInteracted = true;
    if (lastPn) redeliverLastPn();
  });

  resetBtn.addEventListener("click", () => {
    hasInteracted = true;
    // Reset goes through the sequencer like any other edit.
    if (activeDds === "map") {
      // One set op per gauge that has drifted from its surveyed baseline.
      for (const [key, base] of INITIAL) {
        if (readInt(mapKernel.get(clients.a.map, key)) !== base) {
          localSet("a", key, base);
        }
      }
    } else if (activeDds === "pn") {
      // The lattice only grows, so the reset is a compensating update: cut
      // (or fill) whatever the balance has drifted from baseline.
      const drift = pnKernel.value(clients.a.pn) - PN_BASE;
      if (drift !== 0) localPnUpdate("a", -drift);
    } else {
      // A counter has no "set" — the reset is itself an increment that
      // compensates for the drift.
      const drift = clients.a.counter.value - COUNTER_BASE;
      if (drift !== 0) localIncrement("a", -drift);
    }
  });

  // One scripted op on first reveal, so convergence is witnessed rather than
  // waiting to be discovered. Skipped for reduced motion (the flow dots ARE
  // the explanation) and once the visitor has already interacted.
  if (!reducedMotion.matches && "IntersectionObserver" in window) {
    const io = new IntersectionObserver(
      (entries) => {
        if (!entries.some((entry) => entry.isIntersecting)) return;
        io.disconnect();
        setTimeout(() => {
          if (hasInteracted) return;
          const current =
            readInt(mapKernel.get(clients.b.map, "kettle-run")) ?? 0;
          localSet("b", "kettle-run", current + 1);
        }, 600);
      },
      { threshold: 0.45 },
    );
    io.observe(rig);
  }

  render(clients.a);
  render(clients.b);
  renderStatus();
}
