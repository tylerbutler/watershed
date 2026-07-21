// Live convergence demo. The two "clients" here each own real watershed
// state — map/G-counter/PN/OR-map/OR-set/G-set/2P-set/claims/register kernels plus the runtime counter
// channel, compiled with `gleam build --target javascript` — and talk through
// a tiny in-page sequencer that stamps sequence numbers (SNs) and broadcasts
// in order, the same protocol shape as a Fluid-compatible service. All
// structures ride the one op stream, like DDSes sharing a container; the
// picker only changes which replica view is shown.
import * as mapKernel from "../../../build/dev/javascript/watershed/watershed/map_kernel.mjs";
import * as pnKernel from "../../../build/dev/javascript/watershed/watershed/pn_counter_kernel.mjs";
import * as orMapKernel from "../../../build/dev/javascript/watershed/watershed/or_map_kernel.mjs";
import * as orSetKernel from "../../../build/dev/javascript/watershed/watershed/or_set_kernel.mjs";
import * as gSetKernel from "../../../build/dev/javascript/watershed/watershed/g_set_kernel.mjs";
import * as twoPSetKernel from "../../../build/dev/javascript/watershed/watershed/two_p_set_kernel.mjs";
import * as claimsKernel from "../../../build/dev/javascript/watershed/watershed/claims_kernel.mjs";
import * as registerKernel from "../../../build/dev/javascript/watershed/watershed/register_collection_kernel.mjs";
import * as orderedKernel from "../../../build/dev/javascript/watershed/watershed/ordered_collection_kernel.mjs";
import * as taskManagerKernel from "../../../build/dev/javascript/watershed/watershed/task_manager_kernel.mjs";
import * as pactKernel from "../../../build/dev/javascript/watershed/watershed/pact_map_kernel.mjs";
import * as channel from "../../../build/dev/javascript/watershed/watershed/channel.mjs";
import * as runtimeCore from "../../../build/dev/javascript/watershed/watershed/runtime_core.mjs";
import * as gdict from "../../../build/dev/javascript/gleam_stdlib/gleam/dict.mjs";
import * as gset from "../../../build/dev/javascript/gleam_stdlib/gleam/set.mjs";
import * as decode from "../../../build/dev/javascript/gleam_stdlib/gleam/dynamic/decode.mjs";
import * as pnLattice from "../../../build/dev/javascript/lattice_counters/lattice_counters/pn_counter.mjs";
import * as gCounter from "../../../build/dev/javascript/lattice_counters/lattice_counters/g_counter.mjs";
import * as replicaId from "../../../build/dev/javascript/lattice_core/lattice_core/replica_id.mjs";
import * as json from "../../../build/dev/javascript/gleam_json/gleam/json.mjs";
import { None, Some } from "../../../build/dev/javascript/gleam_stdlib/gleam/option.mjs";
import { toList } from "../../../build/dev/javascript/watershed/gleam.mjs";
import { createFieldNotes } from "./tutorial.js";
import { createFlowLayer } from "./demo/flow-dots.ts";
import { createLatencyControls } from "./demo/controls.ts";
import { createOpLog } from "./demo/op-log.ts";
import { createSequencer } from "./demo/sequencer.ts";

const GAUGES = ["mill-race", "kettle-run", "low-ford"];
const INITIAL = [
  ["mill-race", 24],
  ["kettle-run", 61],
  ["low-ford", 42],
];
const COUNTER_BASE = 120;
const COUNTER_ADDRESS = "sandbags-counter";
const GCOUNTER_BASE = 18;
const GCOUNTER_BASE_BY_REPLICA = { a: 9, b: 9 };
// The PN counter baseline: 74 yd³ of fill placed, 30 yd³ cut — net +44.
// Built as a real CRDT summary under a "survey" replica id, then loaded per
// client via `from_summary`, the same path a reconnecting client takes.
const PN_FILL_BASE = 74;
const PN_CUT_BASE = 30;
const PN_BASE = PN_FILL_BASE - PN_CUT_BASE;
const STOCKPILES = ["spoil-north", "borrow-pit-7", "wash-fill"];
const ORMAP_BASELINE = [
  ["spoil-north", 18],
  ["borrow-pit-7", -6],
  ["wash-fill", 12],
];
const MARKERS = ["north-stake", "sluice-tag", "borrow-flag"];
const ORSET_BASELINE = ["north-stake", "sluice-tag"];
const BENCHMARKS = ["BM-17", "BM-22", "BM-31"];
const GSET_BASELINE = ["BM-17"];
const RETIRED_MARKERS = ["stake-3", "gate-pin", "silt-flag"];
const TWO_P_SET_ACTIVE_BASELINE = ["stake-3"];
const TWO_P_SET_RETIRED_BASELINE = ["silt-flag"];

function pnBaselineSummary() {
  let base = pnLattice.new$(replicaId.new$("survey-baseline"));
  base = pnLattice.increment(base, PN_FILL_BASE);
  base = pnLattice.decrement(base, PN_CUT_BASE);
  return json.to_string(pnLattice.to_json(base));
}

function gCounterBaselineSummary() {
  let base = gCounter.new$(replicaId.new$("survey-baseline"));
  for (const [id, amount] of Object.entries(GCOUNTER_BASE_BY_REPLICA)) {
    const replica = gCounter.new$(replicaId.new$(`client-${id}`));
    const delta = gCounter.increment(replica, amount);
    base = gCounter.merge(base, delta);
  }
  return json.to_string(gCounter.to_json(base));
}

function gCounterStateFromSummary(summary, clientId) {
  const parsed = gCounter.from_json(summary);
  if (!parsed.isOk()) throw new Error("G-counter baseline summary failed to load");
  const sequenced = gCounter.merge(gCounter.new$(replicaId.new$(`client-${clientId}`)), parsed[0]);
  return { sequenced, optimistic: sequenced, pending: [], nextMessageId: 0 };
}

function gCounterReplayPending(sequenced, pending) {
  return pending.reduce((acc, item) => gCounter.merge(acc, item.delta), sequenced);
}

function orMapBaselineSummary() {
  let base = orMapKernel.new$(
    replicaId.new$("survey-baseline"),
    new orMapKernel.TallyMode(),
  );
  for (const [key, amount] of ORMAP_BASELINE) {
    const result = orMapKernel.increment(base, key, amount);
    if (!result.isOk()) throw new Error("or-map baseline increment failed");
    const [next, _events, op] = result[0];
    const acked = orMapKernel.ack_local(next, op);
    if (!acked.isOk()) throw new Error("or-map baseline ack failed");
    base = acked[0];
  }
  return json.to_string(orMapKernel.summary(base));
}

function orSetBaselineSummary() {
  let base = orSetKernel.new$(replicaId.new$("survey-baseline"));
  for (const element of ORSET_BASELINE) {
    const [next, _events, op] = orSetKernel.add(base, element);
    const acked = orSetKernel.ack_local(next, op);
    if (!acked.isOk()) throw new Error("or-set baseline ack failed");
    base = acked[0];
  }
  return json.to_string(orSetKernel.summary(base));
}

function gSetBaselineSummary() {
  let base = gSetKernel.new$();
  for (const element of GSET_BASELINE) {
    const [next, _events, op] = gSetKernel.add(base, element);
    const acked = gSetKernel.ack_local(next, op);
    if (!acked.isOk()) throw new Error("g-set baseline ack failed");
    base = acked[0];
  }
  return json.to_string(gSetKernel.summary(base));
}

function twoPSetBaselineSummary() {
  let base = twoPSetKernel.new$();
  for (const element of TWO_P_SET_ACTIVE_BASELINE) {
    const [next, _events, op] = twoPSetKernel.add(base, element);
    const acked = twoPSetKernel.ack_local(next, op);
    if (!acked.isOk()) throw new Error("2P-set baseline add ack failed");
    base = acked[0];
  }
  for (const element of TWO_P_SET_RETIRED_BASELINE) {
    let result = twoPSetKernel.add(base, element);
    let acked = twoPSetKernel.ack_local(result[0], result[2]);
    if (!acked.isOk()) throw new Error("2P-set retired add ack failed");
    base = acked[0];
    result = twoPSetKernel.remove(base, element);
    acked = twoPSetKernel.ack_local(result[0], result[2]);
    if (!acked.isOk()) throw new Error("2P-set retired remove ack failed");
    base = acked[0];
  }
  return json.to_string(twoPSetKernel.summary(base));
}

// The claims baseline: three duty stations, one already claimed by the
// survey crew at seq 0, loaded per client via `from_summary` — sequence
// numbers persist so first-writer-wins keeps working after load.
const SLOTS = ["north-levee", "spillway-gate", "pump-house"];
const CLAIMANTS = { a: "A", b: "B", c: "C" };
const CLAIMS_BASELINE = [["pump-house", "Survey", 0]];
const REGISTERS = ["north-bench", "gate-setpoint", "pump-mode"];
const REGISTER_VALUES = { a: "A revision", b: "B revision", c: "C revision" };
const ORDERED_BASELINE = ["grade-stakes", "pump-check"];
const ORDERED_ADDS = ["silt-sample", "crest-photo", "gate-oiling"];
const TASKS = ["sluice-inspection", "pump-watch", "crest-walk"];
const TASK_BASELINE = [["sluice-inspection", [1]]];
const PACT_KEYS = ["datum-grid", "gate-policy", "inspection-window"];
const PACT_VALUES = { a: "A proposal", b: "B proposal", c: "C proposal" };
const CLIENT_NUMBERS = { a: 1, b: 2, c: 3 };
const CLIENT_NAMES = { 1: "A", 2: "B", 3: "C" };

function claimsBaseline() {
  return claimsKernel.from_summary(
    toList(CLAIMS_BASELINE.map(([k, who, seq]) => [k, json.string(who), seq])),
  );
}

function registersBaseline() {
  const version = new registerKernel.VersionedValue(json.string("Survey"), 0);
  return registerKernel.from_summary(
    toList([
      ["north-bench", new registerKernel.Register(version, toList([version]))],
    ]),
  );
}

function orderedBaseline(items = ORDERED_BASELINE) {
  return orderedKernel.from_summary(
    toList(items.map((item) => json.string(item))),
    toList([]),
  );
}

function taskManagerBaseline() {
  return taskManagerKernel.from_summary(
    toList(TASK_BASELINE.map(([task, queue]) => [task, toList(queue)])),
  );
}

function pactBaseline() {
  return pactKernel.from_summary(
    toList([
      [
        "datum-grid",
        new pactKernel.Pact(
          new Some(
            new pactKernel.Accepted(new Some(json.string("Survey datum")), 0),
          ),
          new None(),
        ),
      ],
    ]),
  );
}

function toDynamic(value) {
  const parsed = json.parse(json.to_string(value), decode.dynamic);
  if (!parsed.isOk()) throw new Error("failed to convert JSON to Dynamic");
  return parsed[0];
}

function bootstrapCounterCore(clientId) {
  const summary = new runtimeCore.Summary(
    0,
    toList([[COUNTER_ADDRESS, new channel.CounterSnapshot(COUNTER_BASE)]]),
  );
  const connected = {
    client_id: `demo-client-${clientId}`,
    initial_messages: toList([]),
    checkpoint_sequence_number: new Some(0),
  };
  const bootstrapped = runtimeCore.bootstrap(connected, new Some(summary));
  if (!bootstrapped.isOk()) throw new Error("counter runtime bootstrap failed");
  const outcome = bootstrapped[0];
  if (!(outcome instanceof runtimeCore.Complete)) {
    throw new Error("counter runtime bootstrap requested catch-up unexpectedly");
  }
  return {
    clientId: connected.client_id,
    core: outcome.core,
  };
}

function counterPending(client) {
  let count = 0;
  let delta = 0;
  for (const entry of client.counterCore.in_flight.toArray()) {
    if (entry.address !== COUNTER_ADDRESS) continue;
    if (!(entry.op instanceof channel.CounterOp)) continue;
    count += 1;
    delta += entry.op[0].increment_amount;
  }
  return { count, delta };
}

function counterValue(client) {
  const value = runtimeCore.counter_value(client.counterCore, COUNTER_ADDRESS);
  return value instanceof Some ? value[0] : COUNTER_BASE;
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

function readClaimant(optionValue) {
  // Claim values are `json.string`, so the encoder yields quoted JSON;
  // JSON.parse unquotes it back to the claimant name.
  if (optionValue && optionValue[0] !== undefined) {
    return JSON.parse(json.to_string(optionValue[0]));
  }
  return null;
}

function readJsonString(optionValue) {
  if (optionValue && optionValue[0] !== undefined) {
    return JSON.parse(json.to_string(optionValue[0]));
  }
  return null;
}

function readOptionalJsonString(optionValue) {
  if (optionValue instanceof Some) return JSON.parse(json.to_string(optionValue[0]));
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
  if (ddsId === "gcounter") return `inspect +${op.amount}`;
  if (ddsId === "pn") {
    return op.amount >= 0
      ? `fill +${op.amount} yd³`
      : `cut −${-op.amount} yd³`;
  }
  if (ddsId === "ormap") {
    if (op instanceof orMapKernel.Increment) {
      return op.amount === 0
        ? `re-open ${op.key}`
        : `log ${signed(op.amount)} yd³ → ${op.key}`;
    }
    if (op instanceof orMapKernel.Remove) return `strike ${op.key}`;
    return `set register ${op.key}`;
  }
  if (ddsId === "orset") {
    if (op instanceof orSetKernel.Add) return `mark ${op.element}`;
    return `clear ${op.element}`;
  }
  if (ddsId === "gset") return `record ${op.element}`;
  if (ddsId === "twopset") {
    if (op instanceof twoPSetKernel.Add) return `place ${op.element}`;
    return `retire ${op.element}`;
  }
  if (ddsId === "claims") {
    // The op carries the ref SN it was filed against — printing it shows
    // why the sequencer accepts or rejects the claim.
    return `claim ${op.key} → ${JSON.parse(json.to_string(op.value))} (ref ${op.ref_seq})`;
  }
  if (ddsId === "registers") {
    return `revise ${op.key} → ${JSON.parse(json.to_string(op.value))} (ref ${op.ref_seq})`;
  }
  if (ddsId === "ordered") {
    if (op instanceof orderedKernel.Add) {
      return `queue ${JSON.parse(json.to_string(op.value))}`;
    }
    if (op instanceof orderedKernel.Acquire) return `acquire ${op.acquire_id}`;
    if (op instanceof orderedKernel.Complete) return `complete ${op.acquire_id}`;
    return `release ${op.acquire_id}`;
  }
  if (ddsId === "tasks") {
    const taskId = op.op.task_id;
    if (op.op instanceof taskManagerKernel.Volunteer) return `volunteer → ${taskId}`;
    if (op.op instanceof taskManagerKernel.Abandon) return `abandon ${taskId}`;
    return `complete ${taskId}`;
  }
  if (ddsId === "pact") {
    if (op instanceof pactKernel.Set) {
      const value = readOptionalJsonString(op.value) ?? "deleted";
      return `propose ${op.key} → ${value} (ref ${op.ref_seq})`;
    }
    return `accept ${op.key}`;
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

  // Which structures this instance exposes. The homepage runs a SharedMap-only
  // proof; each /structures/* page scopes the picker to one family. Kernels all
  // boot regardless — `present` only gates rendering to panels that exist.
  const present = new Set(
    (rig.dataset.views || "map").split(",").map((v) => v.trim()).filter(Boolean),
  );

  const flowLayer = rig.querySelector("[data-flow-layer]");
  const seqNode = rig.querySelector("[data-seq-node]");
  const seqCounter = rig.querySelector("[data-seq-counter]");
  const opLogEl = rig.querySelector("[data-op-log]");
  const statusEl = document.querySelector("[data-status]");
  const latencyInput = document.querySelector("[data-latency]");
  const latencyOut = document.querySelector("[data-latency-out]");
  const paceInput = document.querySelector("[data-pace]");
  const paceOut = document.querySelector("[data-pace-out]");
  const fieldNotesToggle = document.querySelector("[data-field-notes]");
  const latencyVarianceToggle = document.querySelector(
    "[data-latency-variance]",
  );
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
  // Re-deliver stays dark until a CRDT delta has actually been sequenced.
  replayBtn.disabled = true;

  const initial = toList(INITIAL.map(([k, v]) => [k, jsonInt(v)]));
  const gCounterBaseline = gCounterBaselineSummary();
  const pnBaseline = pnBaselineSummary();
  const orMapBaseline = orMapBaselineSummary();
  const orSetBaseline = orSetBaselineSummary();
  const gSetBaseline = gSetBaselineSummary();
  const twoPSetBaseline = twoPSetBaselineSummary();

  const clients = {};
  for (const id of ["a", "b", "c"]) {
    // The PN kernel is replica-identified: each client loads the shared
    // summary under its own id, exactly like a client joining a session.
    const pnLoaded = pnKernel.from_summary(
      pnBaseline,
      replicaId.new$(`client-${id}`),
    );
    if (!pnLoaded.isOk()) throw new Error("pn baseline summary failed to load");
    const orMapLoaded = orMapKernel.from_summary(
      orMapBaseline,
      replicaId.new$(`client-${id}`),
    );
    if (!orMapLoaded.isOk()) {
      throw new Error("or-map baseline summary failed to load");
    }
    const orSetLoaded = orSetKernel.from_summary(
      orSetBaseline,
      replicaId.new$(`client-${id}`),
    );
    if (!orSetLoaded.isOk()) {
      throw new Error("or-set baseline summary failed to load");
    }
    const gSetLoaded = gSetKernel.from_summary(gSetBaseline);
    if (!gSetLoaded.isOk()) {
      throw new Error("g-set baseline summary failed to load");
    }
    const twoPSetLoaded = twoPSetKernel.from_summary(twoPSetBaseline);
    if (!twoPSetLoaded.isOk()) {
      throw new Error("2P-set baseline summary failed to load");
    }
    const counterChannel = bootstrapCounterCore(id);
    clients[id] = {
      id,
      map: mapKernel.from_sequenced(initial),
      gcounter: gCounterStateFromSummary(gCounterBaseline, id),
      counterClientId: counterChannel.clientId,
      counterCore: counterChannel.core,
      pn: pnLoaded[0],
      ormap: orMapLoaded[0],
      orset: orSetLoaded[0],
      gset: gSetLoaded[0],
      twopset: twoPSetLoaded[0],
      claims: claimsBaseline(),
      registers: registersBaseline(),
      ordered: orderedBaseline(),
      taskmanager: taskManagerBaseline(),
      pact: pactBaseline(),
      el: rig.querySelector(`[data-client="${id}"]`),
      lastArrival: 0, // enforces FIFO delivery from the sequencer
      lastSeq: 0, // last delivered container SN — the runtime's job, done here
    };
  }

  let activeDds = present.has(rig.dataset.dds) ? rig.dataset.dds : [...present][0];
  // Structures whose field notes flash the values that change (see tutorial.js
  // CHANGE_TARGETS). Kept in sync there; used to route the demo's op-flow hooks.
  const FIELD_FLASH = new Set([
    "map",
    "counter",
    "pn",
    "gcounter",
    "orset",
    "gset",
    "twopset",
    "ormap",
    "claims",
    "registers",
    "ordered",
    "tasks",
    "pact",
  ]);
  // Shared demo infrastructure: latency/pace/jitter controls, the flow-dot
  // layer, the op-log, and the FIFO sequencer transport. Latency and jitter
  // change the simulation; animation speed only scales how fast you watch it.
  const controls = createLatencyControls({
    latencyInput,
    latencyOut,
    paceInput,
    paceOut,
    varianceToggle: latencyVarianceToggle,
  });
  const flow = createFlowLayer(flowLayer, () => reducedMotion.matches);
  const opLog = createOpLog(opLogEl, { max: 14 });
  const sequencer = createSequencer({
    clients,
    seqNode,
    flow,
    controls,
    onChange: renderStatus,
  });
  let counterSn = 0;
  let hasInteracted = false;
  let lastPn = null; // the most recently *sequenced* PN op, for re-delivery
  let lastGCounter = null; // the most recently *sequenced* G-counter delta
  let lastOrMap = null; // the most recently *sequenced* OR-map op
  let lastOrSet = null; // the most recently *sequenced* OR-set op
  let lastGSet = null; // the most recently *sequenced* G-set op
  let lastTwoPSet = null; // the most recently *sequenced* 2P-set op
  let claimsEpoch = 0; // bumped by reset so in-flight claims are dropped
  let twoPSetEpoch = 0; // 2P-set reset reloads because tombstones cannot shrink
  let registersEpoch = 0; // same guard for out-of-band register-sheet reset
  let orderedEpoch = 0; // ordered-collection resets also drop in-flight ops
  let taskEpoch = 0; // task-manager resets drop outstanding queue ops
  let pactEpoch = 0; // pact-map resets drop outstanding proposals/accepts
  let orderedAcquireSerial = 0;
  let orderedAddSerial = 0;
  let taskMessageSerial = 0;
  const claimNotes = { a: {}, b: {}, c: {} }; // per-slot margin notes (lost, refused)
  const registerNotes = { a: {}, b: {}, c: {} };
  const registerPending = { a: new Set(), b: new Set(), c: new Set() };
  const orderedNotes = { a: "", b: "", c: "" };
  const orderedPending = { a: new Set(), b: new Set(), c: new Set() };
  const taskNotes = { a: {}, b: {}, c: {} };
  const pactNotes = { a: {}, b: {}, c: {} };
  const pactPending = { a: new Set(), b: new Set(), c: new Set() };

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
    const pending = counterPending(client);
    const valueEl = client.el.querySelector("[data-counter-value]");
    valueEl.textContent = String(counterValue(client));
    valueEl.classList.toggle("pending", pending.count > 0);
    const deltaEl = client.el.querySelector("[data-counter-delta]");
    deltaEl.textContent =
      pending.count > 0 ? `Δ ${signed(pending.delta)} unsequenced` : "";
  }

  function gCounterPendingTotal(state) {
    return state.pending.reduce((sum, item) => sum + item.amount, 0);
  }

  function gCounterCounts(state) {
    const [counts] = gCounter.to_parts(state.optimistic);
    const perAuthor = {};
    for (const id of Object.keys(clients)) {
      perAuthor[id] = gdict.get(counts, replicaId.new$(`client-${id}`));
    }
    return perAuthor;
  }

  function readCount(result) {
    return result.isOk() ? result[0] : 0;
  }

  function renderGCounter(client) {
    const pending = client.gcounter.pending;
    const valueEl = client.el.querySelector("[data-gcounter-value]");
    valueEl.textContent = String(gCounter.value(client.gcounter.optimistic));
    valueEl.classList.toggle("pending", pending.length > 0);
    const deltaEl = client.el.querySelector("[data-gcounter-delta]");
    deltaEl.textContent =
      pending.length > 0
        ? `Δ +${gCounterPendingTotal(client.gcounter)} unsequenced`
        : "";
    const counts = gCounterCounts(client.gcounter);
    for (const [id, count] of Object.entries(counts)) {
      const cell = client.el.querySelector(`[data-gcounter-author="${id}"]`);
      if (cell) cell.textContent = String(readCount(count));
    }
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

  function orMapEntries(state) {
    const entries = new Map();
    for (const [key, value] of orMapKernel.entries(state).toArray()) {
      entries.set(key, value[0]);
    }
    return entries;
  }

  function pendingOrMapKeys(state) {
    const keys = new Set();
    for (const pending of state.pending.toArray()) {
      keys.add(pending.op.key);
    }
    return keys;
  }

  function renderOrMap(client) {
    const entries = orMapEntries(client.ormap);
    const pending = pendingOrMapKeys(client.ormap);
    for (const key of STOCKPILES) {
      const row = client.el.querySelector(`.dds-ormap tr[data-key="${key}"]`);
      const value = entries.get(key);
      const struck = value === undefined;
      row.classList.toggle("struck", struck);
      row.classList.toggle("pending", pending.has(key));
      row.querySelector("[data-ormap-value]").textContent = struck
        ? "struck"
        : signed(value);
      row.querySelector("[data-ormap-note]").textContent = pending.has(key)
        ? "unsequenced delta"
        : struck
          ? "hidden, not erased"
          : "";
    }
  }

  function orSetValues(state) {
    return new Set(orSetKernel.values(state).toArray());
  }

  function pendingOrSetElements(state) {
    const elements = new Set();
    for (const pending of state.pending.toArray()) {
      elements.add(pending.op.element);
    }
    return elements;
  }

  function renderOrSet(client) {
    const values = orSetValues(client.orset);
    const pending = pendingOrSetElements(client.orset);
    for (const element of MARKERS) {
      const row = client.el.querySelector(`.dds-orset tr[data-key="${element}"]`);
      const present = values.has(element);
      row.classList.toggle("absent", !present);
      row.classList.toggle("pending", pending.has(element));
      row.querySelector("[data-orset-value]").textContent = present
        ? "marked"
        : "clear";
      row.querySelector("[data-orset-note]").textContent = pending.has(element)
        ? "unsequenced tag"
        : present
          ? "live tag observed"
          : "no live tags";
    }
  }

  function gSetValues(state) {
    return new Set(gSetKernel.values(state).toArray());
  }

  function pendingGSetElements(state) {
    const elements = new Set();
    for (const pending of state.pending.toArray()) {
      elements.add(pending.op.element);
    }
    return elements;
  }

  function renderGSet(client) {
    const values = gSetValues(client.gset);
    const pending = pendingGSetElements(client.gset);
    for (const element of BENCHMARKS) {
      const row = client.el.querySelector(`.dds-gset tr[data-key="${element}"]`);
      const recorded = values.has(element);
      row.classList.toggle("absent", !recorded);
      row.classList.toggle("pending", pending.has(element));
      row.querySelector("[data-gset-value]").textContent = recorded
        ? "recorded"
        : "unrecorded";
      row.querySelector("[data-gset-note]").textContent = pending.has(element)
        ? "unsequenced permanent fact"
        : recorded
          ? "in the registry"
          : "not yet observed";
      row.querySelector("[data-gset-add]").disabled =
        recorded || pending.has(element);
    }
  }

  function twoPSetValues(state) {
    return new Set(twoPSetKernel.values(state).toArray());
  }

  function twoPSetTombstones(state) {
    return new Set(gset.to_list(state.optimistic.removed).toArray());
  }

  function pendingTwoPSetElements(state) {
    const pending = new Map();
    for (const entry of state.pending.toArray()) {
      pending.set(
        entry.op.element,
        entry.op instanceof twoPSetKernel.Remove ? "retire" : "place",
      );
    }
    return pending;
  }

  function renderTwoPSet(client) {
    const values = twoPSetValues(client.twopset);
    const tombstones = twoPSetTombstones(client.twopset);
    const pending = pendingTwoPSetElements(client.twopset);
    for (const element of RETIRED_MARKERS) {
      const row = client.el.querySelector(
        `.dds-twopset tr[data-key="${element}"]`,
      );
      const active = values.has(element);
      const retired = tombstones.has(element);
      const pendingKind = pending.get(element);
      row.classList.toggle("absent", !active && !retired);
      row.classList.toggle("retired", retired);
      row.classList.toggle("pending", pending.has(element));
      row.querySelector("[data-twopset-value]").textContent = retired
        ? "retired"
        : active
          ? "active"
          : "unplaced";
      row.querySelector("[data-twopset-note]").textContent = pendingKind
        ? `unsequenced ${pendingKind}`
        : retired
          ? "tombstone wins"
          : active
          ? "active marker"
          : "not placed";
      row.querySelector("[data-twopset-add]").disabled =
        active || pending.has(element);
      row.querySelector("[data-twopset-add]").textContent = retired
        ? "Try place"
        : "Place";
      row.querySelector("[data-twopset-add]").setAttribute(
        "aria-label",
        `${retired ? "Try to re-place retired marker" : "Place marker"} ${element} on ${client.id.toUpperCase()}`,
      );
      row.querySelector("[data-twopset-remove]").disabled =
        retired || pendingKind === "retire";
    }
  }

  function renderClaims(client) {
    for (const key of SLOTS) {
      const row = client.el.querySelector(`.dds-claims tr[data-key="${key}"]`);
      const holder = readClaimant(claimsKernel.get(client.claims, key));
      const filed = gdict.has_key(client.claims.pending, key);
      // Non-optimistic by design: a filed claim never prints as the holder —
      // the row shows "—" in ink until the claim round-trips as won or lost.
      row.querySelector("[data-holder]").textContent = holder ?? "—";
      row.classList.toggle("filed", filed);
      row.querySelector("[data-claim-note]").textContent = filed
        ? "claim filed · outcome unknown"
        : (claimNotes[client.id][key] ??
          (holder === CLAIMANTS[client.id] ? "yours" : ""));
      row.querySelector("[data-claim]").disabled = filed;
    }
  }

  function registerVersions(state, key) {
    const versions = registerKernel.read_versions(state, key);
    if (!versions || versions[0] === undefined) return [];
    return versions[0]
      .toArray()
      .map((value) => JSON.parse(json.to_string(value)));
  }

  function renderRegisters(client) {
    for (const key of REGISTERS) {
      const row = client.el.querySelector(`.dds-registers tr[data-key="${key}"]`);
      const atomic = readJsonString(
        registerKernel.read(client.registers, key, new registerKernel.Atomic()),
      );
      const lww = readJsonString(
        registerKernel.read(client.registers, key, new registerKernel.Lww()),
      );
      const versions = registerVersions(client.registers, key);
      const filed = registerPending[client.id].has(key);
      row.querySelector("[data-register-atomic]").textContent = atomic ?? "—";
      row.querySelector("[data-register-lww]").textContent = lww ?? "—";
      row.classList.toggle("filed", filed);
      row.querySelector("[data-register-note]").textContent = filed
        ? "revision filed · atomic outcome unknown"
        : (registerNotes[client.id][key] ?? "");
      row.querySelector("[data-register-versions]").textContent =
        versions.length > 1 ? `${versions.length} concurrent versions` : "";
      row.querySelector("[data-register-write]").disabled = filed;
    }
  }

  function orderedQueue(state) {
    return orderedKernel
      .summary_queue(state)
      .toArray()
      .map((value) => JSON.parse(json.to_string(value)));
  }

  function orderedJobs(state) {
    return orderedKernel
      .summary_jobs(state)
      .toArray()
      .map(([id, job]) => ({
        id,
        value: JSON.parse(json.to_string(job.value)),
        owner: job.owner instanceof Some ? job.owner[0] : null,
      }));
  }

  function firstOwnedOrderedJob(client) {
    return orderedJobs(client.ordered).find(
      (job) => job.owner === CLIENT_NUMBERS[client.id],
    );
  }

  function renderOrdered(client) {
    const queue = orderedQueue(client.ordered);
    const jobs = orderedJobs(client.ordered);
    const localJob = firstOwnedOrderedJob(client);
    const filed = orderedPending[client.id].size > 0;
    const queueRow = client.el.querySelector(".dds-ordered tbody tr:first-child");
    const jobsRow = client.el.querySelector(".dds-ordered tbody tr:last-child");
    queueRow.classList.toggle("filed", filed);
    jobsRow.classList.toggle("filed", filed);
    queueRow.querySelector("[data-ordered-queue]").textContent =
      queue.length === 0 ? "empty" : queue.join(", ");
    jobsRow.querySelector("[data-ordered-jobs]").textContent =
      jobs.length === 0
        ? "none"
        : jobs
            .map((job) => `${job.value} · ${CLIENT_NAMES[job.owner] ?? "local"}`)
            .join(", ");
    queueRow.querySelector("[data-ordered-note]").textContent = filed
      ? "op filed · waiting for SN"
      : orderedNotes[client.id];
    queueRow.querySelector("[data-ordered-add]").disabled = filed;
    queueRow.querySelector("[data-ordered-acquire]").disabled = filed;
    jobsRow.querySelector("[data-ordered-complete]").disabled = filed || !localJob;
    jobsRow.querySelector("[data-ordered-release]").disabled = filed || !localJob;
  }

  function taskQueues(state) {
    const queues = new Map();
    for (const [task, queue] of taskManagerKernel.summary_queues(state).toArray()) {
      queues.set(task, queue.toArray());
    }
    return queues;
  }

  function taskPendingKeys(state) {
    return new Set(
      gdict
        .to_list(state.pending)
        .toArray()
        .filter(([_task, pending]) => pending.toArray().length > 0)
        .map(([task]) => task),
    );
  }

  function renderTaskManager(client) {
    const queues = taskQueues(client.taskmanager);
    const pending = taskPendingKeys(client.taskmanager);
    for (const task of TASKS) {
      const row = client.el.querySelector(`.dds-tasks tr[data-key="${task}"]`);
      const queue = queues.get(task) ?? [];
      const assignee = queue[0] ?? null;
      const waiters = queue.slice(1);
      const assignedHere = taskManagerKernel.assigned(
        client.taskmanager,
        task,
        CLIENT_NUMBERS[client.id],
        true,
      );
      const queuedHere = taskManagerKernel.queued_optimistically(
        client.taskmanager,
        task,
        CLIENT_NUMBERS[client.id],
      );
      row.classList.toggle("filed", pending.has(task));
      row.querySelector("[data-task-assignee]").textContent =
        assignee === null ? "—" : CLIENT_NAMES[assignee];
      row.querySelector("[data-task-waiters]").textContent =
        waiters.length === 0
          ? "empty"
          : waiters.map((id) => CLIENT_NAMES[id]).join(" → ");
      row.querySelector("[data-task-note]").textContent = pending.has(task)
        ? (taskNotes[client.id][task] ?? "op filed · waiting for SN")
        : taskNotes[client.id][task] ??
          (assignedHere ? "yours" : queuedHere ? "waiting" : "");
      row.querySelector("[data-task-volunteer]").disabled =
        pending.has(task) || queuedHere;
      row.querySelector("[data-task-abandon]").disabled =
        pending.has(task) || !queuedHere;
      row.querySelector("[data-task-complete]").disabled =
        pending.has(task) || !assignedHere;
    }
  }

  function pactAccepted(state, key) {
    const accepted = pactKernel.get_with_details(state, key);
    if (!(accepted instanceof Some)) return null;
    return {
      value: readOptionalJsonString(accepted[0].value),
      sequence: accepted[0].sequence_number,
    };
  }

  function pactPendingValue(state, key) {
    const pending = pactKernel.get_pending(state, key);
    if (!(pending instanceof Some)) return null;
    return readOptionalJsonString(pending[0]) ?? "delete";
  }

  function pactSignoffs(state, key) {
    const entry = pactKernel
      .summary_entries(state)
      .toArray()
      .find(([entryKey]) => entryKey === key);
    if (!entry || !(entry[1].pending instanceof Some)) return [];
    return entry[1].pending[0].expected_signoffs.toArray();
  }

  function renderPact(client) {
    for (const key of PACT_KEYS) {
      const row = client.el.querySelector(`.dds-pact tr[data-key="${key}"]`);
      const accepted = pactAccepted(client.pact, key);
      const pending = pactPendingValue(client.pact, key);
      const signoffs = pactSignoffs(client.pact, key);
      const filed = pactPending[client.id].has(key);
      row.classList.toggle("filed", filed || pending !== null);
      row.querySelector("[data-pact-accepted]").textContent =
        accepted?.value ?? "—";
      row.querySelector("[data-pact-pending]").textContent = pending ?? "—";
      row.querySelector("[data-pact-signoffs]").textContent =
        signoffs.length > 0
          ? `awaiting ${signoffs.map((id) => CLIENT_NAMES[id]).join(" + ")}`
          : "";
      row.querySelector("[data-pact-note]").textContent = filed
        ? (pactNotes[client.id][key] ?? "proposal filed")
        : (pactNotes[client.id][key] ?? "");
      row.querySelector("[data-pact-set]").disabled =
        filed || pending !== null;
      row.querySelector("[data-pact-delete]").disabled =
        filed || pending !== null || accepted === null || accepted.value === null;
    }
  }

  function renderBadge(client) {
    const count =
      activeDds === "claims"
        ? gdict.size(client.claims.pending)
        : activeDds === "counter"
          ? counterPending(client).count
        : activeDds === "registers"
          ? registerPending[client.id].size
        : activeDds === "ordered"
          ? orderedPending[client.id].size
        : activeDds === "tasks"
          ? taskPendingKeys(client.taskmanager).size
        : activeDds === "pact"
          ? pactPending[client.id].size
        : activeDds === "gcounter"
          ? client.gcounter.pending.length
        : activeDds === "orset"
          ? client.orset.pending.toArray().length
        : activeDds === "gset"
          ? client.gset.pending.toArray().length
        : activeDds === "twopset"
          ? client.twopset.pending.toArray().length
        : activeDds === "ormap"
          ? client.ormap.pending.toArray().length
        : client[activeDds].pending.toArray().length;
    const badge = client.el.querySelector("[data-pending-count]");
    badge.textContent = `${count} pending`;
    if (count === 0) badge.setAttribute("data-zero", "");
    else badge.removeAttribute("data-zero");
  }

  function render(client) {
    if (present.has("map")) renderMap(client);
    if (present.has("counter")) renderCounter(client);
    if (present.has("gcounter")) renderGCounter(client);
    if (present.has("pn")) renderPn(client);
    if (present.has("ormap")) renderOrMap(client);
    if (present.has("orset")) renderOrSet(client);
    if (present.has("gset")) renderGSet(client);
    if (present.has("twopset")) renderTwoPSet(client);
    if (present.has("claims")) renderClaims(client);
    if (present.has("registers")) renderRegisters(client);
    if (present.has("ordered")) renderOrdered(client);
    if (present.has("tasks")) renderTaskManager(client);
    if (present.has("pact")) renderPact(client);
    renderBadge(client);
  }

  function pendingTotal() {
    let total = 0;
    for (const client of Object.values(clients)) {
      total += client.map.pending.toArray().length;
      total += counterPending(client).count;
      total += client.gcounter.pending.length;
      total += client.pn.pending.toArray().length;
      total += client.ormap.pending.toArray().length;
      total += client.orset.pending.toArray().length;
      total += client.gset.pending.toArray().length;
      total += client.twopset.pending.toArray().length;
      total += gdict.size(client.claims.pending);
      total += registerPending[client.id].size;
      total += orderedPending[client.id].size;
      total += taskPendingKeys(client.taskmanager).size;
      total += pactPending[client.id].size;
    }
    return total;
  }

  function replicaSignature(client) {
    return JSON.stringify([
      mapSnapshot(client.map),
      counterValue(client),
      gCounterSnapshot(client.gcounter),
      pnKernel.value(client.pn),
      orMapSnapshot(client.ormap),
      orSetSnapshot(client.orset),
      gSetSnapshot(client.gset),
      twoPSetSnapshot(client.twopset),
      claimsSnapshot(client.claims),
      registerSnapshot(client.registers),
      orderedSnapshot(client.ordered),
      taskManagerSnapshot(client.taskmanager),
      pactSnapshot(client.pact),
    ]);
  }

  function renderStatus() {
    const pending = pendingTotal();
    const inFlight = sequencer.inFlight;
    if (inFlight === 0 && pending === 0) {
      const signatures = Object.values(clients).map(replicaSignature);
      const same = signatures.every((sig) => sig === signatures[0]);
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

  function gCounterSnapshot(state) {
    const [counts] = gCounter.to_parts(state.sequenced);
    return [
      readCount(gdict.get(counts, replicaId.new$("client-a"))),
      readCount(gdict.get(counts, replicaId.new$("client-b"))),
    ];
  }

  function claimsSnapshot(state) {
    return claimsKernel
      .summary_entries(state)
      .toArray()
      .map(([k, v, s]) => [k, json.to_string(v), s]);
  }

  function orMapSnapshot(state) {
    return orMapKernel
      .sequenced_entries(state)
      .toArray()
      .map(([k, v]) => [k, v[0]]);
  }

  function orSetSnapshot(state) {
    return orSetKernel.sequenced_values(state).toArray();
  }

  function gSetSnapshot(state) {
    return gSetKernel.sequenced_values(state).toArray();
  }

  function twoPSetSnapshot(state) {
    return [
      twoPSetKernel.sequenced_values(state).toArray(),
      gset.to_list(state.sequenced.removed).toArray(),
    ];
  }

  function registerSnapshot(state) {
    return registerKernel
      .summary_registers(state)
      .toArray()
      .map(([key, register]) => [
        key,
        json.to_string(register.atomic.value),
        register.atomic.sequence_number,
        register.versions
          .toArray()
          .map((version) => [
            json.to_string(version.value),
            version.sequence_number,
          ]),
      ]);
  }

  function orderedSnapshot(state) {
    return [
      orderedQueue(state),
      orderedJobs(state).map((job) => [job.id, job.value, job.owner]),
    ];
  }

  function taskManagerSnapshot(state) {
    return taskManagerKernel
      .summary_queues(state)
      .toArray()
      .map(([task, queue]) => [task, queue.toArray()]);
  }

  function pactSnapshot(state) {
    return pactKernel
      .summary_entries(state)
      .toArray()
      .map(([key, pact]) => [
        key,
        pact.accepted instanceof Some
          ? [
              readOptionalJsonString(pact.accepted[0].value),
              pact.accepted[0].sequence_number,
            ]
          : null,
        pact.pending instanceof Some
          ? [
              readOptionalJsonString(pact.pending[0].value),
              pact.pending[0].expected_signoffs.toArray(),
            ]
          : null,
      ]);
  }

  function logRejected(stampedSn, key) {
    const li = document.createElement("li");
    li.className = "rejected";
    li.textContent = `#${String(stampedSn).padStart(2, "0")} rejected — ${key} held · first writer wins`;
    opLog.push(li);
  }

  function logOp(stampedSn, origin, ddsId, op) {
    const li = document.createElement("li");
    li.textContent = `#${String(stampedSn).padStart(2, "0")} ${describeOp(ddsId, op)} · from ${origin.toUpperCase()}`;
    opLog.push(li);
    seqCounter.textContent = `SN ${stampedSn}`;
    seqCounter.classList.remove("stamped");
    void seqCounter.offsetWidth;
    seqCounter.classList.add("stamped");
    if (fieldNotes.active && ddsId === activeDds && FIELD_FLASH.has(ddsId)) {
      fieldNotes.flashLog();
    }
  }

  function describeOrderedPending(op) {
    if (op instanceof orderedKernel.Add) return `add:${json.to_string(op.value)}`;
    return `${op.constructor.name}:${op.acquire_id}`;
  }

  // ── op flow animation ─────────────────────────────────────────────────────
  // (Flow-dot rendering lives in the shared `flow` layer created above.)

  // ── protocol: client → sequencer → broadcast ──────────────────────────────

  function deliver(target, originId, ddsId, op, seq, counterSeq = seq) {
    // Every op advances the container SN on every replica — all structures
    // ride the one stream. Claims file their `ref_seq` against this.
    target.lastSeq = seq;
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
    } else if (ddsId === "gcounter") {
      const sequenced = gCounter.merge(target.gcounter.sequenced, op.delta);
      const pending =
        target.id === originId
          ? target.gcounter.pending.filter((item) => item.messageId !== op.messageId)
          : target.gcounter.pending;
      target.gcounter = {
        ...target.gcounter,
        sequenced,
        optimistic: gCounterReplayPending(sequenced, pending),
        pending,
      };
    } else if (ddsId === "ormap") {
      if (target.id === originId) {
        const result = orMapKernel.ack_local(target.ormap, op);
        if (result.isOk()) target.ormap = result[0];
        else console.error("unexpected ack", result[0]);
      } else {
        const result = orMapKernel.apply_remote(target.ormap, op);
        if (result.isOk()) target.ormap = result[0][0];
        else console.error("unexpected remote OR-map op", result[0]);
      }
    } else if (ddsId === "orset") {
      if (target.id === originId) {
        const result = orSetKernel.ack_local(target.orset, op);
        if (result.isOk()) target.orset = result[0];
        else console.error("unexpected OR-set ack", result[0]);
      } else {
        const [next] = orSetKernel.apply_remote(target.orset, op);
        target.orset = next;
      }
    } else if (ddsId === "gset") {
      if (target.id === originId) {
        const result = gSetKernel.ack_local(target.gset, op);
        if (result.isOk()) target.gset = result[0];
        else console.error("unexpected G-set ack", result[0]);
      } else {
        const [next] = gSetKernel.apply_remote(target.gset, op);
        target.gset = next;
      }
    } else if (ddsId === "twopset") {
      if (target.id === originId) {
        const result = twoPSetKernel.ack_local(target.twopset, op);
        if (result.isOk()) target.twopset = result[0];
        else console.error("unexpected 2P-set ack", result[0]);
      } else {
        const [next] = twoPSetKernel.apply_remote(target.twopset, op);
        target.twopset = next;
      }
    } else if (ddsId === "claims") {
      if (target.id === originId) {
        // The ack resolves the deferred outcome: only now does the origin
        // learn whether its claim won or lost the race.
        const result = claimsKernel.ack_local(target.claims, op, seq);
        if (result.isOk()) {
          const [next, _events, outcome] = result[0];
          target.claims = next;
          if (outcome instanceof claimsKernel.Lost) {
            const holder = readClaimant(outcome.current_value);
            claimNotes[target.id][op.key] = holder
              ? `lost — ${holder} holds it`
              : "lost";
            logRejected(seq, op.key);
          }
        } else console.error("unexpected ack", result[0]);
      } else {
        const [next] = claimsKernel.apply_remote(target.claims, op, seq);
        target.claims = next;
      }
    } else if (ddsId === "registers") {
      if (target.id === originId) {
        const [next, _events, isWinner] = registerKernel.ack_local(
          target.registers,
          op,
          seq,
        );
        target.registers = next;
        registerPending[target.id].delete(op.key);
        registerNotes[target.id][op.key] = isWinner
          ? "atomic winner"
          : "atomic lost · version retained";
      } else {
        const [next] = registerKernel.apply_remote(target.registers, op, seq);
        target.registers = next;
      }
    } else if (ddsId === "ordered") {
      if (target.id === originId) {
        const [next, _events, outcome] = orderedKernel.ack_local(
          target.ordered,
          op,
          CLIENT_NUMBERS[target.id],
        );
        target.ordered = next;
        orderedPending[target.id].delete(describeOrderedPending(op));
        if (outcome instanceof Some) {
          orderedNotes[target.id] =
            outcome[0] instanceof orderedKernel.AcquiredItem
              ? `acquired ${JSON.parse(json.to_string(outcome[0].value))}`
              : "queue empty";
        } else if (op instanceof orderedKernel.Complete) {
          orderedNotes[target.id] = "completed";
        } else if (op instanceof orderedKernel.Release) {
          orderedNotes[target.id] = "released to back";
        } else {
          orderedNotes[target.id] = "queued";
        }
      } else {
        const [next] = orderedKernel.apply_remote(
          target.ordered,
          op,
          CLIENT_NUMBERS[originId],
        );
        target.ordered = next;
      }
    } else if (ddsId === "tasks") {
      const quorum = toList([1, 2, 3]);
      if (target.id === originId) {
        const result = taskManagerKernel.ack_local(
          target.taskmanager,
          op.op,
          CLIENT_NUMBERS[target.id],
          op.messageId,
          quorum,
        );
        if (result.isOk()) {
          const [next] = result[0];
          target.taskmanager = next;
          if (op.op instanceof taskManagerKernel.Volunteer) {
            taskNotes[target.id][op.op.task_id] = taskManagerKernel.assigned(
              target.taskmanager,
              op.op.task_id,
              CLIENT_NUMBERS[target.id],
              true,
            )
              ? "assigned"
              : "waiting";
          } else if (op.op instanceof taskManagerKernel.Abandon) {
            taskNotes[target.id][op.op.task_id] = "abandoned";
          } else {
            taskNotes[target.id][op.op.task_id] = "completed";
          }
        } else console.error("unexpected TaskManager ack", result[0]);
      } else {
        const [next] = taskManagerKernel.apply_remote(
          target.taskmanager,
          op.op,
          CLIENT_NUMBERS[originId],
          quorum,
        );
        target.taskmanager = next;
      }
    } else if (ddsId === "pact") {
      if (op instanceof pactKernel.Set) {
        const [next, _events, reaction] = pactKernel.apply_set(
          target.pact,
          op,
          seq,
          toList([1, 2, 3]),
          CLIENT_NUMBERS[target.id],
        );
        target.pact = next;
        if (target.id === originId) {
          pactPending[target.id].delete(op.key);
          pactNotes[target.id][op.key] =
            pactPendingValue(target.pact, op.key) ===
            readOptionalJsonString(op.value)
              ? "pending quorum"
              : "proposal dropped";
        }
        if (reaction instanceof pactKernel.OweAccept) {
          pactPending[target.id].add(op.key);
          pactNotes[target.id][op.key] = "signoff owed";
          submit(target.id, "pact", reaction.op);
        }
      } else {
        const result = pactKernel.apply_accept(
          target.pact,
          op.key,
          CLIENT_NUMBERS[originId],
          seq,
        );
        if (result.isOk()) {
          const [next] = result[0];
          target.pact = next;
          if (target.id === originId) {
            pactPending[target.id].delete(op.key);
            pactNotes[target.id][op.key] = "signed off";
          }
        } else {
          console.error("unexpected pact accept", result[0]);
        }
      }
    } else {
      const origin = clients[originId];
      const { outbound, contents } = op;
      const result = runtimeCore.handle_sequenced(target.counterCore, {
        client_id: new Some(origin.counterClientId),
        sequence_number: counterSeq,
        minimum_sequence_number: 0,
        client_sequence_number: outbound.client_sequence_number,
        reference_sequence_number: outbound.reference_sequence_number,
        message_type: outbound.op_type,
        contents,
        metadata: outbound.metadata,
        server_metadata: new None(),
        origin: new None(),
        traces: new None(),
        timestamp: 0,
        data: new None(),
      });
      if (result.isOk()) target.counterCore = result[0][0];
      else console.error("unexpected counter channel ingest failure", result[0]);
    }
  }

  function submit(originId, ddsId, op) {
    // Claims have no compensating op, so reset reloads replicas out of band
    // and bumps the epoch; a claim still in flight is dropped rather than
    // stamped, or it would commit on one replica and fail to ack on the
    // other. Each DDS that resets out of band carries its own epoch.
    const epochFor = () =>
      ddsId === "claims"
        ? claimsEpoch
        : ddsId === "twopset"
          ? twoPSetEpoch
        : ddsId === "registers"
          ? registersEpoch
        : ddsId === "ordered"
          ? orderedEpoch
        : ddsId === "tasks"
          ? taskEpoch
        : ddsId === "pact"
          ? pactEpoch
          : 0;

    sequencer.send({
      originId,
      label: describeOp(ddsId, op),
      guard: () => {
        const snapshot = epochFor();
        return () => snapshot !== epochFor();
      },
      onSequence: (stamped) => {
        const stampedCounter = ddsId === "counter" ? ++counterSn : null;
        logOp(
          stamped,
          originId,
          ddsId,
          ddsId === "counter" ? { increment_amount: op.amount } : op,
        );
        if (ddsId === "pn") {
          lastPn = { op, sn: stamped };
          replayBtn.disabled = false;
        } else if (ddsId === "gcounter") {
          lastGCounter = { op, sn: stamped };
          replayBtn.disabled = false;
        } else if (ddsId === "ormap") {
          lastOrMap = { op, sn: stamped };
          replayBtn.disabled = false;
        } else if (ddsId === "orset") {
          lastOrSet = { op, sn: stamped };
          replayBtn.disabled = false;
        } else if (ddsId === "gset") {
          lastGSet = { op, sn: stamped };
          replayBtn.disabled = false;
        } else if (ddsId === "twopset") {
          lastTwoPSet = { op, sn: stamped };
          replayBtn.disabled = false;
        }
        return { stampedCounter };
      },
      onDeliver: (target, { seq, extra }) => {
        deliver(target, originId, ddsId, op, seq, extra.stampedCounter ?? seq);
        if (FIELD_FLASH.has(ddsId)) {
          fieldNotes.trackChange(ddsId, target.el, false, () => render(target));
        } else {
          render(target);
        }
        if (
          fieldNotes.active &&
          ddsId === activeDds &&
          !FIELD_FLASH.has(ddsId) &&
          target.id === "a"
        ) {
          fieldNotes.pulse();
        }
      },
    });
  }

  function localSet(clientId, key, value) {
    const client = clients[clientId];
    const [next, _events, op] = mapKernel.set(client.map, key, jsonInt(value));
    client.map = next;
    fieldNotes.trackChange("map", client.el, true, () => render(client));
    submit(clientId, "map", op);
  }

  function localIncrement(clientId, amount) {
    const client = clients[clientId];
    const result = runtimeCore.increment(client.counterCore, COUNTER_ADDRESS, amount);
    if (!result.isOk()) {
      console.error("unexpected counter channel increment refusal", result[0]);
      return;
    }
    const [next, _events, outbound] = result[0];
    const [outboundOp] = outbound.toArray();
    if (outboundOp === undefined) {
      console.error("counter channel increment produced no outbound op");
      return;
    }
    client.counterCore = next;
    fieldNotes.trackChange("counter", client.el, true, () => render(client));
    submit(clientId, "counter", {
      amount,
      outbound: outboundOp,
      contents: toDynamic(outboundOp.contents),
    });
  }

  function localGCounterIncrement(clientId, amount) {
    const client = clients[clientId];
    const [optimistic, delta] = gCounter.increment_with_delta(
      client.gcounter.optimistic,
      amount,
    );
    const messageId = client.gcounter.nextMessageId;
    client.gcounter = {
      ...client.gcounter,
      optimistic,
      pending: [...client.gcounter.pending, { delta, amount, messageId }],
      nextMessageId: messageId + 1,
    };
    fieldNotes.trackChange("gcounter", client.el, true, () => render(client));
    submit(clientId, "gcounter", { delta, amount, messageId });
  }

  function localPnUpdate(clientId, amount) {
    const client = clients[clientId];
    // `update` also returns the local message id; the demo's sequencer acks
    // in FIFO order, so only the op needs to travel.
    const [next, _events, op] = pnKernel.update(client.pn, amount);
    client.pn = next;
    fieldNotes.trackChange("pn", client.el, true, () => render(client));
    submit(clientId, "pn", op);
  }

  function localOrMapLog(clientId, key, amount) {
    const client = clients[clientId];
    const result = orMapKernel.increment(client.ormap, key, amount);
    if (!result.isOk()) {
      console.error("unexpected OR-map increment refusal", result[0]);
      return;
    }
    const [next, _events, op] = result[0];
    client.ormap = next;
    fieldNotes.trackChange("ormap", client.el, true, () => render(client));
    submit(clientId, "ormap", op);
  }

  function localOrMapStrike(clientId, key) {
    const client = clients[clientId];
    const [next, _events, op] = orMapKernel.remove(client.ormap, key);
    client.ormap = next;
    fieldNotes.trackChange("ormap", client.el, true, () => render(client));
    submit(clientId, "ormap", op);
  }

  function localOrSetAdd(clientId, element) {
    const client = clients[clientId];
    const [next, _events, op] = orSetKernel.add(client.orset, element);
    client.orset = next;
    fieldNotes.trackChange("orset", client.el, true, () => render(client));
    submit(clientId, "orset", op);
  }

  function localOrSetRemove(clientId, element) {
    const client = clients[clientId];
    const [next, _events, op] = orSetKernel.remove(client.orset, element);
    client.orset = next;
    fieldNotes.trackChange("orset", client.el, true, () => render(client));
    submit(clientId, "orset", op);
  }

  function localGSetAdd(clientId, element) {
    const client = clients[clientId];
    const [next, _events, op] = gSetKernel.add(client.gset, element);
    client.gset = next;
    fieldNotes.trackChange("gset", client.el, true, () => render(client));
    submit(clientId, "gset", op);
  }

  function localTwoPSetAdd(clientId, element) {
    const client = clients[clientId];
    const [next, _events, op] = twoPSetKernel.add(client.twopset, element);
    client.twopset = next;
    fieldNotes.trackChange("twopset", client.el, true, () => render(client));
    submit(clientId, "twopset", op);
  }

  function localTwoPSetRemove(clientId, element) {
    const client = clients[clientId];
    const [next, _events, op] = twoPSetKernel.remove(client.twopset, element);
    client.twopset = next;
    fieldNotes.trackChange("twopset", client.el, true, () => render(client));
    submit(clientId, "twopset", op);
  }

  function localClaim(clientId, key) {
    const client = clients[clientId];
    const result = claimsKernel.try_set_claim(
      client.claims,
      key,
      json.string(CLAIMANTS[clientId]),
      client.lastSeq,
    );
    if (!result.isOk()) {
      // AlreadyPendingLocally — unreachable while the button disables itself.
      console.error("unexpected claim refusal", result[0]);
      return;
    }
    if (result[0] instanceof claimsKernel.AlreadyClaimed) {
      // Write-once: the kernel refuses a claim on a committed slot locally
      // and synchronously — no op travels, no SN is spent.
      claimNotes[clientId][key] = "already claimed — nothing sent";
      render(client);
      setTimeout(() => {
        if (claimNotes[clientId][key] === "already claimed — nothing sent") {
          delete claimNotes[clientId][key];
          render(client);
        }
      }, controls.paced(2200));
      return;
    }
    client.claims = result[0].state;
    // Non-optimistic: the holder does not change here, so this flashes nothing
    // on the origin; the ink flash lands only when the winner is sequenced.
    fieldNotes.trackChange("claims", client.el, true, () => render(client));
    submit(clientId, "claims", result[0].op);
  }

  function localRegisterWrite(clientId, key) {
    const client = clients[clientId];
    const op = registerKernel.write(
      client.registers,
      key,
      json.string(REGISTER_VALUES[clientId]),
      client.lastSeq,
    );
    registerPending[clientId].add(key);
    registerNotes[clientId][key] = "revision filed";
    // Non-optimistic: the atomic/LWW values move only when sequenced (ink).
    fieldNotes.trackChange("registers", client.el, true, () => render(client));
    submit(clientId, "registers", op);
  }

  function localOrderedAdd(clientId) {
    const client = clients[clientId];
    const value = ORDERED_ADDS[orderedAddSerial % ORDERED_ADDS.length];
    orderedAddSerial += 1;
    const op = orderedKernel.add(client.ordered, json.string(value));
    orderedPending[clientId].add(describeOrderedPending(op));
    orderedNotes[clientId] = "add filed";
    fieldNotes.trackChange("ordered", client.el, true, () => render(client));
    submit(clientId, "ordered", op);
  }

  function localOrderedAcquire(clientId) {
    const client = clients[clientId];
    orderedAcquireSerial += 1;
    const op = orderedKernel.acquire(`${clientId}${orderedAcquireSerial}`);
    orderedPending[clientId].add(describeOrderedPending(op));
    orderedNotes[clientId] = "acquire filed";
    fieldNotes.trackChange("ordered", client.el, true, () => render(client));
    submit(clientId, "ordered", op);
  }

  function localOrderedComplete(clientId) {
    const client = clients[clientId];
    const job = firstOwnedOrderedJob(client);
    if (!job) return;
    const op = orderedKernel.complete(job.id);
    orderedPending[clientId].add(describeOrderedPending(op));
    orderedNotes[clientId] = "complete filed";
    fieldNotes.trackChange("ordered", client.el, true, () => render(client));
    submit(clientId, "ordered", op);
  }

  function localOrderedRelease(clientId) {
    const client = clients[clientId];
    const job = firstOwnedOrderedJob(client);
    if (!job) return;
    const op = orderedKernel.release(job.id);
    orderedPending[clientId].add(describeOrderedPending(op));
    orderedNotes[clientId] = "release filed";
    fieldNotes.trackChange("ordered", client.el, true, () => render(client));
    submit(clientId, "ordered", op);
  }

  function localTaskVolunteer(clientId, taskId) {
    const client = clients[clientId];
    const messageId = ++taskMessageSerial;
    const [next, maybeOp, outcome] = taskManagerKernel.volunteer(
      client.taskmanager,
      taskId,
      CLIENT_NUMBERS[clientId],
      messageId,
    );
    client.taskmanager = next;
    taskNotes[clientId][taskId] =
      outcome instanceof taskManagerKernel.AssignedNow
        ? "assigned locally · filing"
        : "volunteer filed";
    fieldNotes.trackChange("tasks", client.el, true, () => render(client));
    if (maybeOp instanceof Some) {
      submit(clientId, "tasks", { op: maybeOp[0], messageId });
    }
  }

  function localTaskAbandon(clientId, taskId) {
    const client = clients[clientId];
    const messageId = ++taskMessageSerial;
    const [next, maybeOp] = taskManagerKernel.abandon(
      client.taskmanager,
      taskId,
      CLIENT_NUMBERS[clientId],
      messageId,
    );
    client.taskmanager = next;
    taskNotes[clientId][taskId] = "abandon filed";
    fieldNotes.trackChange("tasks", client.el, true, () => render(client));
    if (maybeOp instanceof Some) {
      submit(clientId, "tasks", { op: maybeOp[0], messageId });
    }
  }

  function localTaskComplete(clientId, taskId) {
    const client = clients[clientId];
    const messageId = ++taskMessageSerial;
    const result = taskManagerKernel.complete(
      client.taskmanager,
      taskId,
      CLIENT_NUMBERS[clientId],
      messageId,
    );
    if (!result.isOk()) {
      taskNotes[clientId][taskId] = "not assigned here";
      render(client);
      return;
    }
    const [next, op] = result[0];
    client.taskmanager = next;
    taskNotes[clientId][taskId] = "complete filed";
    fieldNotes.trackChange("tasks", client.el, true, () => render(client));
    submit(clientId, "tasks", { op, messageId });
  }

  function localPactSet(clientId, key) {
    const client = clients[clientId];
    const op = pactKernel.set(
      client.pact,
      key,
      new Some(json.string(PACT_VALUES[clientId])),
      client.lastSeq,
    );
    if (!(op instanceof Some)) {
      pactNotes[clientId][key] = "pending pact blocks new proposal";
      render(client);
      return;
    }
    pactPending[clientId].add(key);
    pactNotes[clientId][key] = "proposal filed";
    // Non-optimistic: pending/accepted print only when sequenced (ink).
    fieldNotes.trackChange("pact", client.el, true, () => render(client));
    submit(clientId, "pact", op[0]);
  }

  function localPactDelete(clientId, key) {
    const client = clients[clientId];
    const op = pactKernel.delete$(client.pact, key, client.lastSeq);
    if (!(op instanceof Some)) {
      pactNotes[clientId][key] = "nothing accepted to delete";
      render(client);
      return;
    }
    pactPending[clientId].add(key);
    pactNotes[clientId][key] = "delete filed";
    // Non-optimistic: pending/accepted print only when sequenced (ink).
    fieldNotes.trackChange("pact", client.el, true, () => render(client));
    submit(clientId, "pact", op[0]);
  }

  // Claims are write-once — there is no unclaim op — so reset tears off a
  // fresh sheet: both replicas reload the baseline summary locally, and the
  // epoch bump makes the sequencer drop anything still in flight.
  function resetClaims() {
    claimsEpoch += 1;
    for (const client of Object.values(clients)) {
      client.claims = claimsBaseline();
      claimNotes[client.id] = {};
      render(client);
    }
    renderStatus();
  }

  function resetRegisters() {
    registersEpoch += 1;
    for (const client of Object.values(clients)) {
      client.registers = registersBaseline();
      registerNotes[client.id] = {};
      registerPending[client.id].clear();
      render(client);
    }
    renderStatus();
  }

  function resetOrdered(items = ORDERED_BASELINE) {
    orderedEpoch += 1;
    for (const client of Object.values(clients)) {
      client.ordered = orderedBaseline(items);
      orderedNotes[client.id] = "";
      orderedPending[client.id].clear();
      render(client);
    }
    renderStatus();
  }

  function resetTaskManager() {
    taskEpoch += 1;
    for (const client of Object.values(clients)) {
      client.taskmanager = taskManagerBaseline();
      taskNotes[client.id] = {};
      render(client);
    }
    renderStatus();
  }

  function resetPact() {
    pactEpoch += 1;
    for (const client of Object.values(clients)) {
      client.pact = pactBaseline();
      pactNotes[client.id] = {};
      pactPending[client.id].clear();
      render(client);
    }
    renderStatus();
  }

  function resetOrSet() {
    const current = orSetValues(clients.a.orset);
    for (const element of MARKERS) {
      const shouldBePresent = ORSET_BASELINE.includes(element);
      const isPresent = current.has(element);
      if (shouldBePresent && !isPresent) localOrSetAdd("a", element);
      if (!shouldBePresent && isPresent) localOrSetRemove("a", element);
    }
  }

  function resetGSet() {
    const current = gSetValues(clients.a.gset);
    for (const element of GSET_BASELINE) {
      if (!current.has(element)) localGSetAdd("a", element);
    }
  }

  function resetGCounter() {
    const drift = gCounter.value(clients.a.gcounter.optimistic) - GCOUNTER_BASE;
    if (drift < 0) {
      localGCounterIncrement("a", 0 - drift);
    }
  }

  function resetTwoPSet() {
    twoPSetEpoch += 1;
    lastTwoPSet = null;
    const baseline = twoPSetBaselineSummary();
    for (const client of Object.values(clients)) {
      const loaded = twoPSetKernel.from_summary(baseline);
      if (!loaded.isOk()) throw new Error("2P-set reset summary failed to load");
      client.twopset = loaded[0];
      render(client);
    }
    if (activeDds === "twopset") replayBtn.disabled = true;
    renderStatus();
  }

  // The sequencer re-sends an already-sequenced delta to every replica. No
  // new SN is stamped — this is duplicate delivery, the failure mode resends
  // and stash replays produce — and the lattice absorbs it: merge is
  // idempotent, so nothing changes anywhere.
  function redeliverLastDelta() {
    const ddsId = activeDds;
    const last =
      ddsId === "ormap"
        ? lastOrMap
        : ddsId === "orset"
          ? lastOrSet
        : ddsId === "gset"
          ? lastGSet
        : ddsId === "gcounter"
          ? lastGCounter
        : ddsId === "twopset"
          ? lastTwoPSet
          : lastPn;
    const { op, sn: originalSn } = last;
    const li = document.createElement("li");
    li.className = "replay";
    li.textContent = `#${String(originalSn).padStart(2, "0")} again ${describeOp(ddsId, op)} · absorbed`;
    opLog.push(li);
    if (fieldNotes.active && ddsId === activeDds && FIELD_FLASH.has(ddsId)) {
      fieldNotes.flashLog();
    }

    sequencer.broadcast({
      label: describeOp(ddsId, op),
      onDeliver: (target) => {
        // Both replicas take the duplicate through `apply_remote` — even the
        // origin, whose acked delta is already merged. Idempotence makes
        // both a no-op.
        if (ddsId === "ormap") {
          const result = orMapKernel.apply_remote(target.ormap, op);
          if (result.isOk()) target.ormap = result[0][0];
          else console.error("unexpected duplicate OR-map op", result[0]);
        } else if (ddsId === "orset") {
          const [next] = orSetKernel.apply_remote(target.orset, op);
          target.orset = next;
        } else if (ddsId === "gset") {
          const [next] = gSetKernel.apply_remote(target.gset, op);
          target.gset = next;
        } else if (ddsId === "gcounter") {
          const sequenced = gCounter.merge(target.gcounter.sequenced, op.delta);
          target.gcounter = {
            ...target.gcounter,
            sequenced,
            optimistic: gCounterReplayPending(sequenced, target.gcounter.pending),
          };
        } else if (ddsId === "twopset") {
          const [next] = twoPSetKernel.apply_remote(target.twopset, op);
          target.twopset = next;
        } else {
          const [next] = pnKernel.apply_remote(target.pn, op);
          target.pn = next;
        }
        render(target);
        if (
          fieldNotes.active &&
          ddsId === activeDds &&
          !FIELD_FLASH.has(ddsId) &&
          target.id === "a"
        ) {
          fieldNotes.pulse();
        }
      },
    });
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
      const gCounterIncBtn = event.target.closest("button[data-gcounter-inc]");
      if (gCounterIncBtn) {
        hasInteracted = true;
        localGCounterIncrement(
          client.id,
          Number(gCounterIncBtn.dataset.gcounterInc),
        );
        return;
      }
      const pnBtn = event.target.closest("button[data-pn-inc]");
      if (pnBtn) {
        hasInteracted = true;
        localPnUpdate(client.id, Number(pnBtn.dataset.pnInc));
        return;
      }
      const claimBtn = event.target.closest("button[data-claim]");
      if (claimBtn) {
        hasInteracted = true;
        localClaim(client.id, claimBtn.closest("tr").dataset.key);
        return;
      }
      const registerBtn = event.target.closest("button[data-register-write]");
      if (registerBtn) {
        hasInteracted = true;
        localRegisterWrite(
          client.id,
          registerBtn.closest("tr").dataset.key,
        );
        return;
      }
      const orderedAddBtn = event.target.closest("button[data-ordered-add]");
      if (orderedAddBtn) {
        hasInteracted = true;
        localOrderedAdd(client.id);
        return;
      }
      const orderedAcquireBtn = event.target.closest("button[data-ordered-acquire]");
      if (orderedAcquireBtn) {
        hasInteracted = true;
        localOrderedAcquire(client.id);
        return;
      }
      const orderedCompleteBtn = event.target.closest("button[data-ordered-complete]");
      if (orderedCompleteBtn) {
        hasInteracted = true;
        localOrderedComplete(client.id);
        return;
      }
      const orderedReleaseBtn = event.target.closest("button[data-ordered-release]");
      if (orderedReleaseBtn) {
        hasInteracted = true;
        localOrderedRelease(client.id);
        return;
      }
      const taskVolunteerBtn = event.target.closest("button[data-task-volunteer]");
      if (taskVolunteerBtn) {
        hasInteracted = true;
        localTaskVolunteer(client.id, taskVolunteerBtn.closest("tr").dataset.key);
        return;
      }
      const taskAbandonBtn = event.target.closest("button[data-task-abandon]");
      if (taskAbandonBtn) {
        hasInteracted = true;
        localTaskAbandon(client.id, taskAbandonBtn.closest("tr").dataset.key);
        return;
      }
      const taskCompleteBtn = event.target.closest("button[data-task-complete]");
      if (taskCompleteBtn) {
        hasInteracted = true;
        localTaskComplete(client.id, taskCompleteBtn.closest("tr").dataset.key);
        return;
      }
      const pactSetBtn = event.target.closest("button[data-pact-set]");
      if (pactSetBtn) {
        hasInteracted = true;
        localPactSet(client.id, pactSetBtn.closest("tr").dataset.key);
        return;
      }
      const pactDeleteBtn = event.target.closest("button[data-pact-delete]");
      if (pactDeleteBtn) {
        hasInteracted = true;
        localPactDelete(client.id, pactDeleteBtn.closest("tr").dataset.key);
        return;
      }
      const orMapLogBtn = event.target.closest("button[data-ormap-log]");
      if (orMapLogBtn) {
        hasInteracted = true;
        localOrMapLog(
          client.id,
          orMapLogBtn.closest("tr").dataset.key,
          Number(orMapLogBtn.dataset.ormapLog),
        );
        return;
      }
      const orMapStrikeBtn = event.target.closest("button[data-ormap-strike]");
      if (orMapStrikeBtn) {
        hasInteracted = true;
        localOrMapStrike(client.id, orMapStrikeBtn.closest("tr").dataset.key);
        return;
      }
      const orMapReopenBtn = event.target.closest("button[data-ormap-reopen]");
      if (orMapReopenBtn) {
        hasInteracted = true;
        localOrMapLog(client.id, orMapReopenBtn.closest("tr").dataset.key, 0);
        return;
      }
      const orSetAddBtn = event.target.closest("button[data-orset-add]");
      if (orSetAddBtn) {
        hasInteracted = true;
        localOrSetAdd(client.id, orSetAddBtn.closest("tr").dataset.key);
        return;
      }
      const orSetRemoveBtn = event.target.closest("button[data-orset-remove]");
      if (orSetRemoveBtn) {
        hasInteracted = true;
        localOrSetRemove(client.id, orSetRemoveBtn.closest("tr").dataset.key);
        return;
      }
      const gSetAddBtn = event.target.closest("button[data-gset-add]");
      if (gSetAddBtn) {
        hasInteracted = true;
        localGSetAdd(client.id, gSetAddBtn.closest("tr").dataset.key);
        return;
      }
      const twoPSetAddBtn = event.target.closest("button[data-twopset-add]");
      if (twoPSetAddBtn) {
        hasInteracted = true;
        localTwoPSetAdd(client.id, twoPSetAddBtn.closest("tr").dataset.key);
        return;
      }
      const twoPSetRemoveBtn = event.target.closest("button[data-twopset-remove]");
      if (twoPSetRemoveBtn) {
        hasInteracted = true;
        localTwoPSetRemove(client.id, twoPSetRemoveBtn.closest("tr").dataset.key);
      }
    });
  }

  const RACE_LABELS = {
    map: "Race a concurrent write",
    counter: "Race concurrent increments",
    gcounter: "Race grow-only inspections",
    pn: "Race fill against cut",
    ormap: "Race a strike against a delivery",
    orset: "Race clear against re-mark",
    gset: "Race two permanent marks",
    twopset: "Race retire against re-place",
    claims: "Race two claims for one slot",
    registers: "Race two revisions for one register",
    ordered: "Race two acquires for one queued task",
    tasks: "Race two volunteers for one task",
    pact: "Race two pact proposals",
  };
  const RESET_LABELS = {
    map: "Reset all gauges to their surveyed baseline values",
    counter: "Reset the counter to its surveyed baseline value",
    gcounter: "Ensure the inspection counter is at least its surveyed baseline",
    pn: "Reset the earthwork balance to its surveyed baseline",
    ormap: "Reset the stockpile ledger to its surveyed baseline",
    orset: "Reset the marker roster to its surveyed baseline",
    gset: "Ensure the permanent benchmark registry includes its surveyed baseline",
    twopset: "Reload the retired marker ledger from the surveyed tombstone baseline",
    claims: "Tear off a fresh claim sheet, reloading all replicas from the baseline summary",
    registers: "Reload all register collections from the surveyed baseline summary",
    ordered: "Reload all ordered collections from the queued-task baseline summary",
    tasks: "Reload all task managers from the crew baseline summary",
    pact: "Reload all pact maps from the accepted datum baseline summary",
  };

  function applyActiveView() {
    rig.dataset.dds = activeDds;
    for (const rule of mergeRules) {
      rule.hidden = rule.dataset.mergeRule !== activeDds;
    }
    if (raceBtn) raceBtn.textContent = RACE_LABELS[activeDds];
    if (resetBtn) resetBtn.setAttribute("aria-label", RESET_LABELS[activeDds]);
    if (replayBtn) {
      replayBtn.hidden = ![
        "gcounter",
        "pn",
        "ormap",
        "orset",
        "gset",
        "twopset",
      ].includes(activeDds);
      replayBtn.disabled =
        activeDds === "gcounter"
          ? !lastGCounter
        : activeDds === "ormap"
          ? !lastOrMap
          : activeDds === "orset"
            ? !lastOrSet
          : activeDds === "gset"
            ? !lastGSet
          : activeDds === "twopset"
            ? !lastTwoPSet
            : !lastPn;
    }
    renderBadge(clients.a);
    renderBadge(clients.b);
    renderBadge(clients.c);
    fieldNotes.render(activeDds);
  }

  const fieldNotes = createFieldNotes({
    rig,
    prefersReducedMotion: () => reducedMotion.matches,
    duration: controls.paced,
  });

  for (const pick of ddsPicks) {
    pick.addEventListener("change", () => {
      if (!pick.checked) return;
      activeDds = pick.value;
      applyActiveView();
    });
  }

  // Initialise labels / merge-rule visibility / replay state for the starting
  // view (which may not be "map" on a scoped /structures/* page).
  applyActiveView();

  if (fieldNotesToggle) {
    fieldNotesToggle.addEventListener("change", () => {
      fieldNotes.setActive(fieldNotesToggle.checked);
    });
  }

  // Rough-notation marks are absolutely positioned, so redraw them when the
  // layout shifts under a resize.
  let reflowTimer = null;
  window.addEventListener("resize", () => {
    if (!fieldNotes.active) return;
    clearTimeout(reflowTimer);
    reflowTimer = setTimeout(() => fieldNotes.reflow(), 150);
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
    } else if (activeDds === "gcounter") {
      // Each client owns one monotone inspection tally. The join keeps the
      // maximum observed count for A and B, so both increments survive and
      // duplicate delivery is harmless.
      localGCounterIncrement("a", 7);
      localGCounterIncrement("b", 3);
    } else if (activeDds === "ormap") {
      // A strikes what it has observed while B logs a delivery concurrently.
      // The strike cannot remove B's unseen dot, so the stockpile survives and
      // the retained tally includes every logged yard.
      let key = STOCKPILES.find(
        (k) =>
          orMapEntries(clients.a.ormap).has(k) &&
          orMapEntries(clients.b.ormap).has(k),
      );
      if (key === undefined) {
        key = STOCKPILES[0];
        localOrMapLog("a", key, 0);
        localOrMapLog("b", key, 0);
      }
      localOrMapStrike("a", key);
      localOrMapLog("b", key, 6);
    } else if (activeDds === "orset") {
      // A clears the tags it has observed while B concurrently adds a fresh
      // tag for the same marker. The remove cannot see B's tag, so the marker
      // remains present after both deltas converge.
      let key = MARKERS.find(
        (marker) =>
          orSetValues(clients.a.orset).has(marker) &&
          orSetValues(clients.b.orset).has(marker),
      );
      if (key === undefined) {
        key = MARKERS[0];
        localOrSetAdd("a", key);
        localOrSetAdd("b", key);
      }
      localOrSetRemove("a", key);
      localOrSetAdd("b", key);
    } else if (activeDds === "gset") {
      // G-set has no remove and no winner: A and B permanently record different
      // benchmark IDs, and both IDs remain after the deltas join.
      localGSetAdd("a", "BM-22");
      localGSetAdd("b", "BM-31");
    } else if (activeDds === "twopset") {
      // A retires an active marker while B concurrently re-places it. The add
      // is recorded, but the remove tombstone wins forever.
      resetTwoPSet();
      localTwoPSetRemove("a", "stake-3");
      localTwoPSetAdd("b", "stake-3");
    } else if (activeDds === "claims") {
      // Both clients file for the same free slot inside one latency window.
      // FIFO stamping sequences A's claim first, so A wins on every replica;
      // B's op still gets an SN, is rejected identically everywhere, and B's
      // own ack resolves Lost.
      let key = SLOTS.find(
        (k) =>
          readClaimant(claimsKernel.get(clients.a.claims, k)) === null &&
          readClaimant(claimsKernel.get(clients.b.claims, k)) === null &&
          !gdict.has_key(clients.a.claims.pending, k) &&
          !gdict.has_key(clients.b.claims.pending, k),
      );
      if (key === undefined) {
        resetClaims();
        key = SLOTS[0];
      }
      localClaim("a", key);
      localClaim("b", key);
    } else if (activeDds === "registers") {
      localRegisterWrite("a", "gate-setpoint");
      localRegisterWrite("b", "gate-setpoint");
    } else if (activeDds === "ordered") {
      // One queued task, two acquires. FIFO sequencing gives the first SN the
      // job and the second acquire resolves QueueEmpty on both replicas.
      resetOrdered(["flood-watch"]);
      localOrderedAcquire("a");
      localOrderedAcquire("b");
    } else if (activeDds === "tasks") {
      // Both clients volunteer for the same unassigned task. The first SN gets
      // the assignment and the second becomes the waiter; abandoning promotes.
      resetTaskManager();
      localTaskVolunteer("a", "pump-watch");
      localTaskVolunteer("b", "pump-watch");
    } else if (activeDds === "pact") {
      // The first set that sequences freezes the quorum signoff list. The
      // concurrent set is dropped while that pact is pending.
      resetPact();
      localPactSet("a", "gate-policy");
      localPactSet("b", "gate-policy");
    } else {
      // Both clients increment inside one latency window. Neither op wins:
      // increments commute, so every replica lands on the sum (+13).
      localIncrement("a", 8);
      localIncrement("b", 5);
    }
  });

  replayBtn.addEventListener("click", () => {
    hasInteracted = true;
    if (
      (activeDds === "ormap" && lastOrMap) ||
      (activeDds === "orset" && lastOrSet) ||
      (activeDds === "gset" && lastGSet) ||
      (activeDds === "gcounter" && lastGCounter) ||
      (activeDds === "twopset" && lastTwoPSet) ||
      (activeDds === "pn" && lastPn)
    ) {
      redeliverLastDelta();
    }
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
    } else if (activeDds === "gcounter") {
      resetGCounter();
    } else if (activeDds === "ormap") {
      for (const [key, base] of ORMAP_BASELINE) {
        if (!orMapEntries(clients.a.ormap).has(key)) {
          localOrMapLog("a", key, 0);
        }
        const value = orMapEntries(clients.a.ormap).get(key) ?? 0;
        const drift = value - base;
        if (drift !== 0) localOrMapLog("a", key, -drift);
      }
    } else if (activeDds === "claims") {
      resetClaims();
    } else if (activeDds === "twopset") {
      resetTwoPSet();
    } else if (activeDds === "registers") {
      resetRegisters();
    } else if (activeDds === "ordered") {
      resetOrdered();
    } else if (activeDds === "tasks") {
      resetTaskManager();
    } else if (activeDds === "pact") {
      resetPact();
    } else if (activeDds === "orset") {
      resetOrSet();
    } else if (activeDds === "gset") {
      resetGSet();
    } else {
      // A counter has no "set" — the reset is itself an increment that
      // compensates for the drift.
      const drift = counterValue(clients.a) - COUNTER_BASE;
      if (drift !== 0) localIncrement("a", -drift);
    }
  });

  // One scripted op on first reveal, so convergence is witnessed rather than
  // waiting to be discovered. Skipped for reduced motion (the flow dots ARE
  // the explanation) and once the visitor has already interacted.
  if (
    activeDds === "map" &&
    present.has("map") &&
    !reducedMotion.matches &&
    "IntersectionObserver" in window
  ) {
    const io = new IntersectionObserver(
      (entries) => {
        if (!entries.some((entry) => entry.isIntersecting)) return;
        io.disconnect();
        setTimeout(() => {
          if (hasInteracted) return;
          const current =
            readInt(mapKernel.get(clients.b.map, "kettle-run")) ?? 0;
          localSet("b", "kettle-run", current + 1);
        }, controls.paced(600));
      },
      { threshold: 0.45 },
    );
    io.observe(rig);
  }

  render(clients.a);
  render(clients.b);
  render(clients.c);
  renderStatus();
}
