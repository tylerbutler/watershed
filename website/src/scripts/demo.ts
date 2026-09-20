// Live convergence demo. The three "clients" here each own real watershed
// state — map/LWW-map/LWW-register/G-counter/PN/OR-map/OR-set/G-set/2P-set/claims/register kernels plus the runtime counter
// channel, compiled with `gleam build --target javascript` — and talk through
// a tiny in-page sequencer that stamps sequence numbers (SNs) and broadcasts
// in order, the same protocol shape as a Fluid-compatible service. All
// structures ride the one op stream, like DDSes sharing a container; the
// picker only changes which replica view is shown.
import { mapKernel } from "./demo/generated-runtime.ts";
import { pnKernel } from "./demo/generated-runtime.ts";
import { gCounterKernel } from "./demo/generated-runtime.ts";
import { lwwRegisterKernel } from "./demo/generated-runtime.ts";
import { lwwMapKernel } from "./demo/generated-runtime.ts";
import { mvKernel } from "./demo/generated-runtime.ts";
import { orMapKernel } from "./demo/generated-runtime.ts";
import { orSetKernel } from "./demo/generated-runtime.ts";
import { gSetKernel } from "./demo/generated-runtime.ts";
import { twoPSetKernel } from "./demo/generated-runtime.ts";
import { claimsKernel } from "./demo/generated-runtime.ts";
import { registerKernel } from "./demo/generated-runtime.ts";
import { orderedKernel } from "./demo/generated-runtime.ts";
import { taskManagerKernel } from "./demo/generated-runtime.ts";
import { pactKernel } from "./demo/generated-runtime.ts";
import { websiteRuntime } from "./demo/generated-runtime.ts";
import { gdict } from "./demo/generated-runtime.ts";
import { gset } from "./demo/generated-runtime.ts";
import { pnLattice } from "./demo/generated-runtime.ts";
import { gCounter } from "./demo/generated-runtime.ts";
import { replicaId } from "./demo/generated-runtime.ts";
import { json } from "./demo/generated-runtime.ts";
import {
  toList,
  type List,
} from "./demo/generated-runtime.ts";
import { createFieldNotes } from "./tutorial.js";
import { createFlowLayer } from "./demo/flow-dots.ts";
import { createLatencyControls } from "./demo/controls.ts";
import { createOpLog } from "./demo/op-log.ts";
import { createSequencer, type SeqClient } from "./demo/sequencer.ts";
import {
  expectOk,
  isOk,
  none,
  optionValue,
  resultError,
  type ResultValue,
  resultValue,
  some,
} from "./demo/generated-runtime.ts";
import { lwwRaceTimestamp } from "./demo/lww-register.js";

type ClientId = "a" | "b" | "c";
type DdsId =
  | "map"
  | "counter"
  | "gcounter"
  | "pn"
  | "ormap"
  | "or-map-mv-register"
  | "lww-map"
  | "lww-register"
  | "mv-register"
  | "orset"
  | "gset"
  | "twopset"
  | "claims"
  | "registers"
  | "ordered"
  | "tasks"
  | "pact";
type OrMapMode = "tally" | "set";
type OrMapScenario = "union" | "member" | "key" | "readd" | "empty";
type JsonData =
  | null
  | boolean
  | number
  | string
  | JsonData[]
  | { [key: string]: JsonData };
type TaskPendingList = List<taskManagerKernel.PendingOperation$>;
type CounterDemoOperation = {
  amount: number;
  write: websiteRuntime.CounterWrite$;
};
type EpochOperation<T> = {
  operation: T;
  messageId: number;
  epoch: number;
};
type OrMapDemoOperation = EpochOperation<orMapKernel.OrMapOperation$> & {
  mode: OrMapMode;
};
type TaskDemoOperation = {
  op: taskManagerKernel.TaskManagerOperation$;
  messageId: number;
};
type OperationByDds = {
  map: mapKernel.MapOperation$;
  counter: CounterDemoOperation;
  gcounter: gCounterKernel.GCounterOperation$;
  pn: pnKernel.PnCounterOperation$;
  ormap: OrMapDemoOperation;
  "or-map-mv-register": EpochOperation<orMapKernel.OrMapOperation$>;
  "lww-map": EpochOperation<lwwMapKernel.LwwMapOperation$>;
  "lww-register": EpochOperation<lwwRegisterKernel.LwwRegisterOperation$>;
  "mv-register": EpochOperation<mvKernel.MvRegisterOperation$>;
  orset: orSetKernel.OrSetOperation$;
  gset: gSetKernel.GSetOperation$;
  twopset: twoPSetKernel.TwoPSetOperation$;
  claims: claimsKernel.ClaimOperation$;
  registers: registerKernel.WriteOperation$;
  ordered: orderedKernel.OrderedOperation$;
  tasks: TaskDemoOperation;
  pact: pactKernel.PactMapOperation$;
};
type OperationEnvelope = {
  [K in DdsId]: { ddsId: K; op: OperationByDds[K] };
}[DdsId];
type ReplayDdsId =
  | "gcounter"
  | "pn"
  | "ormap"
  | "or-map-mv-register"
  | "lww-map"
  | "lww-register"
  | "mv-register"
  | "orset"
  | "gset"
  | "twopset";
type ReplayOperationEnvelope = {
  [K in ReplayDdsId]: { ddsId: K; op: OperationByDds[K] };
}[ReplayDdsId];
type LastOperation<K extends DdsId> = {
  op: OperationByDds[K];
  sn: number;
};

interface DemoClient extends SeqClient {
  id: ClientId;
  map: ReturnType<typeof mapKernel.from_sequenced>;
  gcounter: ReturnType<typeof gCounterStateFromSummary>;
  counterClientId: string;
  counterCore: ReturnType<typeof bootstrapCounterCore>["core"];
  pn: ResultValue<ReturnType<typeof pnKernel.from_summary>>;
  "lww-register": ReturnType<typeof lwwRegisterFromBaseline>;
  "lww-map": ReturnType<typeof lwwMapFromSummary>;
  "mv-register": ReturnType<typeof mvFromBaseline>;
  ormap: ResultValue<ReturnType<typeof orMapKernel.from_summary>>;
  "or-map-mv-register": ReturnType<typeof orMapMvFromBaseline>;
  orset: ResultValue<ReturnType<typeof orSetKernel.from_summary>>;
  gset: ResultValue<ReturnType<typeof gSetKernel.from_summary>>;
  twopset: ResultValue<ReturnType<typeof twoPSetKernel.from_summary>>;
  claims: ReturnType<typeof claimsBaseline>;
  registers: ReturnType<typeof registersBaseline>;
  ordered: ReturnType<typeof orderedBaseline>;
  taskmanager: ReturnType<typeof taskManagerBaseline>;
  pact: ReturnType<typeof pactBaseline>;
  el: HTMLElement;
  lastArrival: number;
  lastSeq: number;
}

const CLIENT_IDS: readonly ClientId[] = ["a", "b", "c"];
const DDS_IDS: readonly DdsId[] = [
  "map",
  "counter",
  "gcounter",
  "pn",
  "ormap",
  "or-map-mv-register",
  "lww-map",
  "lww-register",
  "mv-register",
  "orset",
  "gset",
  "twopset",
  "claims",
  "registers",
  "ordered",
  "tasks",
  "pact",
];
const GAUGES = ["mill-race", "kettle-run", "low-ford"] as const;
const INITIAL: Array<[string, number]> = [
  ["mill-race", 24],
  ["kettle-run", 61],
  ["low-ford", 42],
];
const COUNTER_BASE = 120;
const COUNTER_ADDRESS = "sandbags-counter";
const GCOUNTER_BASE = 18;
const GCOUNTER_BASE_BY_REPLICA: Partial<Record<ClientId, number>> = { a: 9, b: 9 };
// The PN counter baseline: 74 yd³ of fill placed, 30 yd³ cut — net +44.
// Built as a real CRDT summary under a "survey" replica id, then loaded per
// client via `from_summary`, the same path a reconnecting client takes.
const PN_FILL_BASE = 74;
const PN_CUT_BASE = 30;
const PN_BASE = PN_FILL_BASE - PN_CUT_BASE;
const STOCKPILES = ["spoil-north", "borrow-pit-7", "wash-fill"] as const;
const ORMAP_BASELINE: Array<[string, number]> = [
  ["spoil-north", 18],
  ["borrow-pit-7", -6],
  ["wash-fill", 12],
];
const MARKERS = ["north-stake", "sluice-tag", "borrow-flag"] as const;
const ORSET_BASELINE = ["north-stake", "sluice-tag"] as const;
const BENCHMARKS = ["BM-17", "BM-22", "BM-31"] as const;
const GSET_BASELINE = ["BM-17"] as const;
const RETIRED_MARKERS = ["stake-3", "gate-pin", "silt-flag"] as const;
const TWO_P_SET_ACTIVE_BASELINE = ["stake-3"] as const;
const TWO_P_SET_RETIRED_BASELINE = ["silt-flag"] as const;

function required<T extends Element>(
  root: ParentNode,
  selector: string,
): T {
  const element = root.querySelector<T>(selector);
  if (!element) throw new Error(`Structure demo markup is missing ${selector}`);
  return element;
}

function requiredClosest<T extends Element>(
  element: Element,
  selector: string,
): T {
  const match = element.closest<T>(selector);
  if (!match) throw new Error(`Structure demo markup is missing ${selector}`);
  return match;
}

function rowKey(element: Element): string {
  const key = requiredClosest<HTMLTableRowElement>(element, "tr").dataset.key;
  if (key === undefined) {
    throw new Error("Structure demo row is missing data-key");
  }
  return key;
}

function isDdsId(value: string): value is DdsId {
  return DDS_IDS.some((id) => id === value);
}

function isOrMapMode(value: string): value is OrMapMode {
  return value === "tally" || value === "set";
}

function isOrMapScenario(value: string): value is OrMapScenario {
  return value === "union" || value === "member" || value === "key"
    || value === "readd" || value === "empty";
}

function pnBaselineSummary(): string {
  let base = pnLattice.new$(replicaId.new$("survey-baseline"));
  base = expectOk(
    pnLattice.increment(base, PN_FILL_BASE),
    "PN-counter baseline increment failed",
  );
  const decremented = expectOk(
    pnLattice.decrement(base, PN_CUT_BASE),
    "PN-counter baseline decrement failed",
  );
  return json.to_string(pnLattice.to_json(decremented));
}

function mvBaselineSummary(epoch: number): string {
  const [base] = mvKernel.p2p_set(
    mvKernel.new$(replicaId.new$(`survey-mv-${epoch}`)),
    "Survey datum",
  );
  return json.to_string(mvKernel.summary(base));
}

function mvFromBaseline(
  baseline: string,
  id: ClientId,
  epoch: number,
): mvKernel.MvRegisterState$ {
  return expectOk(
    mvKernel.from_summary(
      baseline,
      replicaId.new$(`client-${id}-mv-${epoch}`),
    ),
    "MV-register baseline summary failed to load",
  );
}

function lwwRegisterBaselineSummary(): string {
  const [state] = expectOk(
    lwwRegisterKernel.p2p_set(
      lwwRegisterKernel.new$(replicaId.new$("survey-lww")),
      "Survey datum",
      100,
    ),
    "LWW-register baseline write failed",
  );
  return json.to_string(lwwRegisterKernel.summary(state));
}

function lwwRegisterFromBaseline(
  baseline: string,
  id: ClientId,
  epoch: number,
): lwwRegisterKernel.LwwRegisterState$ {
  return expectOk(
    lwwRegisterKernel.from_summary(
      baseline,
      replicaId.new$(`client-${id}-lww-${epoch}`),
    ),
    "LWW-register baseline summary failed to load",
  );
}

function lwwMapBaselineSummary(): string {
  const [state] = expectOk(
    lwwMapKernel.p2p_set(
      lwwMapKernel.new$(replicaId.new$("survey-lww-map")),
      "gate-mode",
      "surveyed",
      100,
    ),
    "LWWMap baseline write failed",
  );
  return json.to_string(lwwMapKernel.summary(state));
}

function lwwMapFromSummary(
  summary: string,
  id: ClientId,
  epoch: number,
): lwwMapKernel.LwwMapState$ {
  return expectOk(
    lwwMapKernel.from_summary(
      summary,
      replicaId.new$(`client-${id}-lww-map-${epoch}`),
    ),
    "LWWMap summary failed to load",
  );
}

function lwwMapMetadata(state: lwwMapKernel.LwwMapState$) {
  const summary: {
    state: {
      entries: Array<{
        key: string;
        value: string | null;
        timestamp: number;
        provenance: { writer: string };
      }>;
    };
  } = JSON.parse(json.to_string(lwwMapKernel.summary(state)));
  return summary.state.entries
    .map((entry) => ({
      ...entry,
      value: entry.value === null ? null : JSON.parse(entry.value).state.value,
    }))
    .sort((a, b) => a.key < b.key ? -1 : a.key > b.key ? 1 : 0);
}

function gCounterBaselineSummary(): string {
  let base = gCounter.new$(replicaId.new$("survey-baseline"));
  for (const [id, amount] of Object.entries(GCOUNTER_BASE_BY_REPLICA)) {
    const replica = gCounter.new$(replicaId.new$(`client-${id}`));
    base = gCounter.merge(
      base,
      expectOk(
        gCounter.increment(replica, amount),
        "G-counter baseline increment failed",
      ),
    );
  }
  return json.to_string(gCounter.to_json(base));
}

function gCounterStateFromSummary(
  summary: string,
  clientId: ClientId,
): gCounterKernel.GCounterState$ {
  return expectOk(
    gCounterKernel.from_summary(
      summary,
      replicaId.new$(`client-${clientId}`),
    ),
    "G-counter baseline summary failed to load",
  );
}

function orMapBaselineSummary(): string {
  let base = orMapKernel.new$(
    replicaId.new$("survey-baseline"),
    new orMapKernel.TallyMode(),
  );
  for (const [key, amount] of ORMAP_BASELINE) {
    const [next, _events, operation] = expectOk(
      orMapKernel.increment(base, key, amount),
      "or-map baseline increment failed",
    );
    base = expectOk(
      orMapKernel.ack_local(next, operation),
      "or-map baseline ack failed",
    );
  }
  return json.to_string(orMapKernel.summary(base));
}

function orMapMvBaselineSummary(epoch: number): string {
  const [state] = expectOk(
    orMapKernel.p2p_set_mv_register(
      orMapKernel.new$(
        replicaId.new$(`survey-or-map-mv-${epoch}`),
        new orMapKernel.MvRegisterMode(),
      ),
      "gate-mode",
      "surveyed",
    ),
    "OR-map MV-register baseline write failed",
  );
  return json.to_string(orMapKernel.summary(state));
}

function orMapMvFromBaseline(
  baseline: string,
  id: ClientId,
  epoch: number,
): orMapKernel.OrMapState$ {
  return expectOk(
    orMapKernel.from_summary(
      baseline,
      replicaId.new$(`client-${id}-or-map-mv-${epoch}`),
    ),
    "OR-map MV-register baseline failed to load",
  );
}

function orMapMvEntries(
  entries: ReturnType<typeof orMapKernel.entries>,
): Array<[string, string[]]> {
  return entries.toArray().map(([key, value]) => {
    if (!(value instanceof orMapKernel.MvRegister)) {
      throw new Error(`OR-map MV-register entry ${key} has the wrong value mode`);
    }
    return [key, value[0].toArray()];
  });
}

function canonicalMetadata(value: JsonData): JsonData {
  if (Array.isArray(value)) {
    return value
      .map(canonicalMetadata)
      .sort((a, b) => compareCanonical(JSON.stringify(a), JSON.stringify(b)));
  }
  if (value !== null && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value)
        .filter(([key]) => key !== "replica_id" && key !== "counter")
        .sort(([a], [b]) => compareCanonical(a, b))
        .map(([key, nested]) => [key, canonicalMetadata(nested)]),
    );
  }
  return value;
}

function compareCanonical(a: string, b: string): number {
  return a < b ? -1 : a > b ? 1 : 0;
}

function canonicalEncodedJson(source: string): string {
  return JSON.stringify(canonicalMetadata(JSON.parse(source)));
}

function canonicalOrMapMvSummary(state: orMapKernel.OrMapState$): string {
  const summary: {
    state: {
      entries: Array<{
        membership: string;
        value: string;
        [key: string]: JsonData;
      }>;
      [key: string]: JsonData;
    };
    [key: string]: JsonData;
  } = JSON.parse(json.to_string(orMapKernel.summary(state)));
  return JSON.stringify(canonicalMetadata({
    ...summary,
    state: {
      ...summary.state,
      entries: summary.state.entries.map((entry) => ({
        ...entry,
        membership: canonicalEncodedJson(entry.membership),
        value: canonicalEncodedJson(entry.value),
      })),
    },
  }));
}

function orSetBaselineSummary(): string {
  let base = orSetKernel.new$(replicaId.new$("survey-baseline"));
  for (const element of ORSET_BASELINE) {
    const [next, _events, op] = orSetKernel.add(base, element);
    base = expectOk(
      orSetKernel.ack_local(next, op),
      "or-set baseline ack failed",
    );
  }
  return json.to_string(orSetKernel.summary(base));
}

function gSetBaselineSummary(): string {
  let base = gSetKernel.new$();
  for (const element of GSET_BASELINE) {
    const [next, _events, op] = gSetKernel.add(base, element);
    base = expectOk(
      gSetKernel.ack_local(next, op),
      "g-set baseline ack failed",
    );
  }
  return json.to_string(gSetKernel.summary(base));
}

function twoPSetBaselineSummary(): string {
  let base = twoPSetKernel.new$();
  for (const element of TWO_P_SET_ACTIVE_BASELINE) {
    const [next, _events, op] = twoPSetKernel.add(base, element);
    base = expectOk(
      twoPSetKernel.ack_local(next, op),
      "2P-set baseline add ack failed",
    );
  }
  for (const element of TWO_P_SET_RETIRED_BASELINE) {
    let result = twoPSetKernel.add(base, element);
    base = expectOk(
      twoPSetKernel.ack_local(result[0], result[2]),
      "2P-set retired add ack failed",
    );
    result = twoPSetKernel.remove(base, element);
    base = expectOk(
      twoPSetKernel.ack_local(result[0], result[2]),
      "2P-set retired remove ack failed",
    );
  }
  return json.to_string(twoPSetKernel.summary(base));
}

// The claims baseline: three duty stations, one already claimed by the
// survey crew at seq 0, loaded per client via `from_summary` — sequence
// numbers persist so first-writer-wins keeps working after load.
const SLOTS = ["north-levee", "spillway-gate", "pump-house"] as const;
const CLAIMANTS: Record<ClientId, string> = { a: "A", b: "B", c: "C" };
const CLAIMS_BASELINE: Array<[string, string, number]> = [
  ["pump-house", "Survey", 0],
];
const REGISTERS = ["north-bench", "gate-setpoint", "pump-mode"] as const;
const REGISTER_VALUES: Record<ClientId, string> = {
  a: "A revision",
  b: "B revision",
  c: "C revision",
};
const ORDERED_BASELINE = ["grade-stakes", "pump-check"] as const;
const ORDERED_ADDS = ["silt-sample", "crest-photo", "gate-oiling"] as const;
const TASKS = ["sluice-inspection", "pump-watch", "crest-walk"] as const;
const TASK_BASELINE: Array<[string, number[]]> = [
  ["sluice-inspection", [1]],
];
const PACT_KEYS = ["datum-grid", "gate-policy", "inspection-window"] as const;
const PACT_VALUES: Record<ClientId, string> = {
  a: "A proposal",
  b: "B proposal",
  c: "C proposal",
};
const CLIENT_NUMBERS: Record<ClientId, number> = { a: 1, b: 2, c: 3 };
const CLIENT_NAMES: Record<number, string> = { 1: "A", 2: "B", 3: "C" };

function claimsBaseline(): claimsKernel.ClaimsState$ {
  return claimsKernel.from_summary(
    toList(CLAIMS_BASELINE.map(([k, who, seq]) => [k, json.string(who), seq])),
  );
}

function registersBaseline(): registerKernel.RegisterState$ {
  const version = new registerKernel.VersionedValue(json.string("Survey"), 0);
  return registerKernel.from_summary(
    toList([
      ["north-bench", new registerKernel.Register(version, toList([version]))],
    ]),
  );
}

function orderedBaseline(
  items: readonly string[] = ORDERED_BASELINE,
): orderedKernel.OrderedState$ {
  return orderedKernel.from_summary(
    toList(items.map((item) => json.string(item))),
    toList([]),
  );
}

function taskManagerBaseline(): taskManagerKernel.TaskManagerState$ {
  return taskManagerKernel.from_summary(
    toList(TASK_BASELINE.map(([task, queue]) => [task, toList(queue)])),
  );
}

function pactBaseline(): pactKernel.PactMapState$ {
  return pactKernel.from_summary(
    toList([
      [
        "datum-grid",
        new pactKernel.Pact(
          some(
            new pactKernel.Accepted(some(json.string("Survey datum")), 0),
          ),
          none(),
        ),
      ],
    ]),
  );
}

function bootstrapCounterCore(clientId: ClientId) {
  const runtimeClientId = `demo-client-${clientId}`;
  const core = expectOk(
    websiteRuntime.counter_core(
      runtimeClientId,
      COUNTER_ADDRESS,
      COUNTER_BASE,
    ),
    "counter runtime bootstrap failed",
  );
  return {
    clientId: runtimeClientId,
    core,
  };
}

function counterPending(client: DemoClient): { count: number; delta: number } {
  const pending = websiteRuntime.counter_pending(
    client.counterCore,
    COUNTER_ADDRESS,
  );
  return { count: pending.count, delta: pending.delta };
}

function counterValue(client: DemoClient): number {
  const value = websiteRuntime.counter_value(
    client.counterCore,
    COUNTER_ADDRESS,
  );
  return resultValue(value) ?? COUNTER_BASE;
}

const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

function jsonInt(n: number): json.Json$ {
  return json.int(n);
}

function readInt(
  value: ReturnType<typeof mapKernel.get>,
): number | null {
  const contained = resultValue(value);
  return contained === null ? null : Number(json.to_string(contained));
}

function readClaimant(
  value: ReturnType<typeof claimsKernel.get>,
): string | null {
  // Claim values are `json.string`, so the encoder yields quoted JSON;
  // JSON.parse unquotes it back to the claimant name.
  const contained = resultValue(value);
  return contained === null ? null : JSON.parse(json.to_string(contained));
}

function readJsonString(
  value: ReturnType<typeof registerKernel.read>,
): string | null {
  const contained = resultValue(value);
  return contained === null ? null : JSON.parse(json.to_string(contained));
}

function readOptionalJsonString(
  value: Parameters<typeof pactKernel.set>[2],
): string | null {
  const contained = optionValue(value);
  return contained === null ? null : JSON.parse(json.to_string(contained));
}

function pendingMapKeys(state: mapKernel.MapState$): Set<string> {
  const keys = new Set<string>();
  for (const entry of state.pending.toArray()) {
    if (entry instanceof mapKernel.PendingLifetime) keys.add(entry.key);
    else if (entry instanceof mapKernel.PendingDelete) keys.add(entry.key);
    else for (const k of GAUGES) keys.add(k); // PendingClear masks everything
  }
  return keys;
}

function signed(n: number): string {
  return n < 0 ? `−${Math.abs(n)}` : `+${n}`;
}

function describeOp({ ddsId, op }: OperationEnvelope): string {
  if (ddsId === "or-map-mv-register") {
    if (op.operation instanceof orMapKernel.Remove) {
      return `remove ${JSON.stringify(op.operation.key)}`;
    }
    if (op.operation instanceof orMapKernel.SetMvRegister) {
      return `revise ${JSON.stringify(op.operation.key)} = ${JSON.stringify(op.operation.value)}`;
    }
    throw new Error("Unexpected OR-map MV-register operation");
  }
  if (ddsId === "lww-map") {
    const operation = op.operation;
    const edit = operation instanceof lwwMapKernel.Remove
      ? `remove ${JSON.stringify(operation.key)}`
      : `set ${JSON.stringify(operation.key)} = ${JSON.stringify(operation.value)}`;
    return `${edit} (t ${operation.timestamp})`;
  }
  if (ddsId === "lww-register") {
    return `write ${JSON.stringify(op.operation.value)} (t ${op.operation.timestamp})`;
  }
  if (ddsId === "mv-register") return `revise ${JSON.stringify(op.operation.value)}`;
  if (ddsId === "counter") return `inc ${signed(op.amount)}`;
  if (ddsId === "gcounter") return `inspect +${op.amount}`;
  if (ddsId === "pn") {
    return op.amount >= 0
      ? `fill +${op.amount} yd³`
      : `cut −${-op.amount} yd³`;
  }
  if (ddsId === "ormap") {
    const { operation } = op;
    if (operation instanceof orMapKernel.Increment) {
      return operation.amount === 0
        ? `re-open ${operation.key}`
        : `log ${signed(operation.amount)} yd³ → ${operation.key}`;
    }
    if (operation instanceof orMapKernel.AddMember) {
      return `add member ${JSON.stringify(operation.member)} → ${operation.key}`;
    }
    if (operation instanceof orMapKernel.RemoveMember) {
      return `remove member ${JSON.stringify(operation.member)} → ${operation.key}`;
    }
    if (operation instanceof orMapKernel.Remove) {
      return `${op.mode === "set" ? "remove key" : "strike"} ${operation.key}`;
    }
    return `set register ${operation.key}`;
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
    return `claim ${op.key} → ${JSON.parse(json.to_string(op.value))} (ref ${op.reference_sequence_number})`;
  }
  if (ddsId === "registers") {
    return `revise ${op.key} → ${JSON.parse(json.to_string(op.value))} (ref ${op.reference_sequence_number})`;
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
      return `propose ${op.key} → ${value} (ref ${op.reference_sequence_number})`;
    }
    return `accept ${op.key}`;
  }
  if (op instanceof mapKernel.Set) {
    return `set ${op.key} = ${json.to_string(op.value)}`;
  }
  if (op instanceof mapKernel.Delete) return `delete ${op.key}`;
  return "clear";
}

export function initDemo(): void {
  const rig = required<HTMLElement>(document, "[data-demo-rig]");

  // Which structures this instance exposes. The homepage runs a SharedMap-only
  // proof; each /structures/* page scopes the picker to one family. Kernels all
  // boot regardless — `present` only gates rendering to panels that exist.
  const present = new Set<DdsId>(
    (rig.dataset.views || "map")
      .split(",")
      .map((value) => value.trim())
      .filter(isDdsId),
  );

  const flowLayer = required<HTMLElement>(rig, "[data-flow-layer]");
  const seqNode = required<HTMLElement>(rig, "[data-seq-node]");
  const seqCounter = required<HTMLElement>(rig, "[data-seq-counter]");
  const opLogEl = required<HTMLElement>(rig, "[data-op-log]");
  const statusEl = required<HTMLElement>(document, "[data-status]");
  const paceInput = required<HTMLInputElement>(document, "[data-pace]");
  const paceOut = required<HTMLElement>(document, "[data-pace-out]");
  const fieldNotesToggle = document.querySelector<HTMLInputElement>(
    "[data-field-notes]",
  );
  const latencyVarianceToggle = document.querySelector<HTMLInputElement>(
    "[data-latency-variance]",
  );
  const raceBtn = required<HTMLButtonElement>(document, "[data-race]");
  const resetBtn = required<HTMLButtonElement>(document, "[data-reset]");
  const replayBtn = required<HTMLButtonElement>(document, "[data-replay]");
  const cutLinkBtn = document.querySelector<HTMLButtonElement>("[data-cut-link]");
  const linkNote = document.querySelector<HTMLElement>("[data-link-note]");
  const ddsPicks =
    document.querySelectorAll<HTMLInputElement>("[data-dds-pick]");
  const mergeRules =
    document.querySelectorAll<HTMLElement>("[data-merge-rule]");
  const orMapViewSelect =
    document.querySelector<HTMLSelectElement>("[data-ormap-view]");
  const orMapModeSelect =
    document.querySelector<HTMLSelectElement>("[data-ormap-mode]");
  const orMapRaceSelect =
    document.querySelector<HTMLSelectElement>("[data-ormap-set-race]");
  const orMapRaceStatus =
    document.querySelector<HTMLElement>("[data-ormap-race-status]");

  const initial = toList(
    INITIAL.map(([key, value]): [string, json.Json$] => [key, jsonInt(value)]),
  );
  const gCounterBaseline = gCounterBaselineSummary();
  const pnBaseline = pnBaselineSummary();
  const mvBaseline = mvBaselineSummary(0);
  const lwwRegisterBaseline = lwwRegisterBaselineSummary();
  const lwwMapBaseline = lwwMapBaselineSummary();
  const orMapBaseline = orMapBaselineSummary();
  const orMapMvBaseline = orMapMvBaselineSummary(0);
  const orSetBaseline = orSetBaselineSummary();
  const gSetBaseline = gSetBaselineSummary();
  const twoPSetBaseline = twoPSetBaselineSummary();

  function createClient(id: ClientId): DemoClient {
    // The PN kernel is replica-identified: each client loads the shared
    // summary under its own id, exactly like a client joining a session.
    const pn = expectOk(
      pnKernel.from_summary(
        pnBaseline,
        replicaId.new$(`client-${id}`),
      ),
      "pn baseline summary failed to load",
    );
    const ormap = expectOk(
      orMapKernel.from_summary(
        orMapBaseline,
        replicaId.new$(`client-${id}`),
      ),
      "or-map baseline summary failed to load",
    );
    const orset = expectOk(
      orSetKernel.from_summary(
        orSetBaseline,
        replicaId.new$(`client-${id}`),
      ),
      "or-set baseline summary failed to load",
    );
    const gsetState = expectOk(
      gSetKernel.from_summary(gSetBaseline),
      "g-set baseline summary failed to load",
    );
    const twopset = expectOk(
      twoPSetKernel.from_summary(twoPSetBaseline),
      "2P-set baseline summary failed to load",
    );
    const counterChannel = bootstrapCounterCore(id);
    return {
      id,
      map: mapKernel.from_sequenced(initial),
      gcounter: gCounterStateFromSummary(gCounterBaseline, id),
      counterClientId: counterChannel.clientId,
      counterCore: counterChannel.core,
      pn,
      "lww-register": lwwRegisterFromBaseline(lwwRegisterBaseline, id, 0),
      "lww-map": lwwMapFromSummary(lwwMapBaseline, id, 0),
      "mv-register": mvFromBaseline(mvBaseline, id, 0),
      ormap,
      "or-map-mv-register": orMapMvFromBaseline(orMapMvBaseline, id, 0),
      orset,
      gset: gsetState,
      twopset,
      claims: claimsBaseline(),
      registers: registersBaseline(),
      ordered: orderedBaseline(),
      taskmanager: taskManagerBaseline(),
      pact: pactBaseline(),
      el: required<HTMLElement>(rig, `[data-client="${id}"]`),
      lastArrival: 0, // enforces FIFO delivery from the sequencer
      lastSeq: 0, // last delivered container SN — the runtime's job, done here
    };
  }
  const clients: Record<ClientId, DemoClient> = {
    a: createClient("a"),
    b: createClient("b"),
    c: createClient("c"),
  };

  // Controls are authored `disabled` and stay that way until every kernel has
  // booted above — if anything threw, the section stays inert and Demo.astro's
  // catch shows the offline note instead of live-looking dead buttons.
  const demoSection = required<HTMLElement>(document, "#demo");
  for (const el of demoSection.querySelectorAll<
    HTMLButtonElement | HTMLInputElement | HTMLSelectElement
  >("button, input, select")) {
    el.disabled = false;
  }
  // Re-deliver stays dark until a CRDT delta has actually been sequenced.
  replayBtn.disabled = true;

  const initialDds = rig.dataset.dds;
  let activeDds: DdsId =
    initialDds && isDdsId(initialDds) && present.has(initialDds)
      ? initialDds
      : [...present][0] ?? "map";
  // Structures whose field notes flash the values that change (see tutorial.js
  // CHANGE_TARGETS). Kept in sync there; used to route the demo's op-flow hooks.
  const FIELD_FLASH = new Set<DdsId>([
    "lww-map",
    "lww-register",
    "mv-register",
    "map",
    "counter",
    "pn",
    "gcounter",
    "orset",
    "gset",
    "twopset",
    "ormap",
    "or-map-mv-register",
    "claims",
    "registers",
    "ordered",
    "tasks",
    "pact",
  ]);
  // Shared demo infrastructure: pace/jitter controls, the flow-dot layer, the
  // op-log, and the FIFO sequencer transport. Jitter changes the simulation;
  // animation speed only scales how fast you watch it.
  const controls = createLatencyControls({
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
    // The cut-link affordance: while Client B's link is down, sequenced ops
    // headed for B are held at the sequencer and replayed on restore — the
    // same catch-up a reconnecting runtime performs.
    isLinkUp: (client) => linkUp || client.id !== "b",
    onHold: (_client, deliverHop) => {
      heldHops.push(deliverHop);
      renderStatus();
    },
  });
  let counterSn = 0;
  let hasInteracted = false;
  let linkUp = true; // Client B ⇄ sequencer link state
  const heldHops: Array<() => void> = []; // sequenced ops awaiting delivery to B (catch-up)
  const heldSubmits: Array<() => void> = []; // B's local ops parked while offline (resubmit)
  let lastPn: LastOperation<"pn"> | null = null; // the most recently *sequenced* PN op, for re-delivery
  let lastLwwRegister: LastOperation<"lww-register"> | null = null;
  let lwwRegisterEpoch = 0;
  let lastLwwMap: LastOperation<"lww-map"> | null = null;
  let lwwMapEpoch = 0;
  // Keep an early delta so replay after resolution proves it cannot resurrect.
  let lastMv: LastOperation<"mv-register"> | null = null;
  let mvEpoch = 0;
  let lastGCounter: LastOperation<"gcounter"> | null = null; // the most recently *sequenced* G-counter delta
  let lastOrMap: LastOperation<"ormap"> | null = null; // the most recently *sequenced* OR-map op
  let orMapMode: OrMapMode = "tally";
  let orMapEpoch = 0;
  let orMapRaceRunning = false;
  let lastOrMapMv: LastOperation<"or-map-mv-register"> | null = null; // retain the early op to replay after resolution
  let orMapMvEpoch = 0;
  let lastOrSet: LastOperation<"orset"> | null = null; // the most recently *sequenced* OR-set op
  let lastGSet: LastOperation<"gset"> | null = null; // the most recently *sequenced* G-set op
  let lastTwoPSet: LastOperation<"twopset"> | null = null; // the most recently *sequenced* 2P-set op
  let claimsEpoch = 0; // bumped by reset so in-flight claims are dropped
  let twoPSetEpoch = 0; // 2P-set reset reloads because tombstones cannot shrink
  let registersEpoch = 0; // same guard for out-of-band register-sheet reset
  let orderedEpoch = 0; // ordered-collection resets also drop in-flight ops
  let taskEpoch = 0; // task-manager resets drop outstanding queue ops
  let pactEpoch = 0; // pact-map resets drop outstanding proposals/accepts
  let orderedAcquireSerial = 0;
  let orderedAddSerial = 0;
  let taskMessageSerial = 0;
  const claimNotes: Record<ClientId, Record<string, string>> = { a: {}, b: {}, c: {} }; // per-slot margin notes (lost, refused)
  const registerNotes: Record<ClientId, Record<string, string>> = { a: {}, b: {}, c: {} };
  const registerPending: Record<ClientId, Set<string>> = { a: new Set(), b: new Set(), c: new Set() };
  const orderedNotes: Record<ClientId, string> = { a: "", b: "", c: "" };
  const orderedPending: Record<ClientId, Set<string>> = { a: new Set(), b: new Set(), c: new Set() };
  const taskNotes: Record<ClientId, Record<string, string>> = { a: {}, b: {}, c: {} };
  const pactNotes: Record<ClientId, Record<string, string>> = { a: {}, b: {}, c: {} };
  const pactPending: Record<ClientId, Set<string>> = { a: new Set(), b: new Set(), c: new Set() };
  const orMapRetained: Record<ClientId, Map<string, number>> = {
    a: new Map(ORMAP_BASELINE),
    b: new Map(ORMAP_BASELINE),
    c: new Map(ORMAP_BASELINE),
  };

  // ── rendering ─────────────────────────────────────────────────────────────

  function renderMap(client: DemoClient): void {
    const pending = pendingMapKeys(client.map);
    for (const key of GAUGES) {
      const row = required<HTMLTableRowElement>(
        client.el,
        `tr[data-key="${key}"]`,
      );
      const value = readInt(mapKernel.get(client.map, key));
      required<HTMLElement>(row, "[data-value]").textContent =
        value === null ? "—" : String(value);
      row.classList.toggle("pending", pending.has(key));
      const minus =
        row.querySelector<HTMLButtonElement>('button[data-step="-1"]');
      if (minus) minus.disabled = value !== null && value <= 0;
    }
  }

  function renderCounter(client: DemoClient): void {
    const pending = counterPending(client);
    const valueEl = required<HTMLElement>(client.el, "[data-counter-value]");
    valueEl.textContent = String(counterValue(client));
    valueEl.classList.toggle("pending", pending.count > 0);
    const deltaEl = required<HTMLElement>(client.el, "[data-counter-delta]");
    deltaEl.textContent =
      pending.count > 0 ? `Δ ${signed(pending.delta)} unsequenced` : "";
  }

  function gCounterPendingTotal(state: gCounterKernel.GCounterState$): number {
    return state.pending
      .toArray()
      .reduce((sum, item) => sum + item.amount, 0);
  }

  function gCounterCounts(
    state: gCounterKernel.GCounterState$,
  ): Record<
    ClientId,
    ReturnType<typeof gdict.get<replicaId.ReplicaId$, number>>
  > {
    const [counts] = gCounter.to_parts(state.optimistic);
    const perAuthor: Record<
      ClientId,
      ReturnType<typeof gdict.get<replicaId.ReplicaId$, number>>
    > = {
      a: gdict.get(counts, replicaId.new$("client-a")),
      b: gdict.get(counts, replicaId.new$("client-b")),
      c: gdict.get(counts, replicaId.new$("client-c")),
    };
    for (const id of CLIENT_IDS) {
      perAuthor[id] = gdict.get(counts, replicaId.new$(`client-${id}`));
    }
    return perAuthor;
  }

  function readCount(
    result: ReturnType<typeof gdict.get<replicaId.ReplicaId$, number>>,
  ): number {
    return resultValue(result) ?? 0;
  }

  function renderGCounter(client: DemoClient): void {
    const pendingCount = client.gcounter.pending.toArray().length;
    const valueEl = required<HTMLElement>(client.el, "[data-gcounter-value]");
    valueEl.textContent = String(gCounterKernel.value(client.gcounter));
    valueEl.classList.toggle("pending", pendingCount > 0);
    const deltaEl = required<HTMLElement>(client.el, "[data-gcounter-delta]");
    deltaEl.textContent =
      pendingCount > 0
        ? `Δ +${gCounterPendingTotal(client.gcounter)} unsequenced`
        : "";
    const counts = gCounterCounts(client.gcounter);
    for (const [id, count] of Object.entries(counts)) {
      const cell = client.el.querySelector<HTMLElement>(
        `[data-gcounter-author="${id}"]`,
      );
      if (cell) cell.textContent = String(readCount(count));
    }
  }

  function renderLwwRegister(client: DemoClient): void {
    const state = client["lww-register"];
    const optimistic = required<HTMLElement>(
      client.el,
      "[data-lww-register-value]",
    );
    optimistic.textContent = lwwRegisterKernel.value(state);
    optimistic.classList.toggle("k-pending", state.pending.toArray().length > 0);
    required<HTMLElement>(
      client.el,
      "[data-lww-register-confirmed]",
    ).textContent =
      lwwRegisterKernel.sequenced_value(state);
    const winner = JSON.parse(
      json.to_string(lwwRegisterKernel.summary(state)),
    ).state;
    required<HTMLElement>(
      client.el,
      "[data-lww-register-winner]",
    ).textContent =
      `timestamp ${winner.timestamp} · ${winner.replica_id || "bottom"}`;
  }

  function renderLwwMap(client: DemoClient): void {
    const state = client["lww-map"];
    const optimistic = required<HTMLElement>(
      client.el,
      "[data-lww-map-entries]",
    );
    optimistic.textContent = JSON.stringify(lwwMapKernel.entries(state).toArray());
    optimistic.classList.toggle("k-pending", state.pending.toArray().length > 0);
    const confirmed = lwwMapFromSummary(
      json.to_string(lwwMapKernel.summary(state)), client.id, lwwMapEpoch,
    );
    required<HTMLElement>(
      client.el,
      "[data-lww-map-confirmed]",
    ).textContent =
      JSON.stringify(lwwMapKernel.entries(confirmed).toArray());
    required<HTMLElement>(
      client.el,
      "[data-lww-map-metadata]",
    ).textContent =
      JSON.stringify(lwwMapMetadata(confirmed));
  }

  function renderMv(client: DemoClient): void {
    const state = client["mv-register"];
    const optimistic = required<HTMLElement>(
      client.el,
      "[data-mv-register-values]",
    );
    optimistic.textContent = JSON.stringify(mvKernel.values(state).toArray());
    optimistic.classList.toggle("k-pending", state.pending.toArray().length > 0);
    required<HTMLElement>(
      client.el,
      "[data-mv-register-confirmed]",
    ).textContent =
      JSON.stringify(mvKernel.sequenced_values(state).toArray());
    required<HTMLButtonElement>(
      client.el,
      "[data-mv-register-resolve]",
    ).disabled =
      mvKernel.values(state).toArray().length < 2;
  }

  function selectedOrMapMvValues(client: DemoClient): string[] {
    const key = required<HTMLInputElement>(
      client.el,
      "[data-or-map-mv-register-key]",
    ).value;
    const values = orMapEntries(client["or-map-mv-register"]).get(key);
    return Array.isArray(values) ? values : [];
  }

  function renderOrMapMv(client: DemoClient): void {
    const state = client["or-map-mv-register"];
    const optimistic = required<HTMLElement>(
      client.el,
      "[data-or-map-mv-register-entries]",
    );
    optimistic.textContent = JSON.stringify(orMapMvEntries(orMapKernel.entries(state)));
    optimistic.classList.toggle("k-pending", state.pending.toArray().length > 0);
    required<HTMLElement>(
      client.el,
      "[data-or-map-mv-register-confirmed]",
    ).textContent =
      JSON.stringify(orMapMvEntries(orMapKernel.sequenced_entries(state)));
    required<HTMLElement>(
      client.el,
      "[data-or-map-mv-register-canonical-summary]",
    )
      .setAttribute("data-or-map-mv-register-canonical-summary", canonicalOrMapMvSummary(state));
    required<HTMLButtonElement>(
      client.el,
      "[data-or-map-mv-register-resolve]",
    ).disabled =
      selectedOrMapMvValues(client).length < 2;
  }

  function renderPn(client: DemoClient): void {
    const pending = client.pn.pending.toArray();
    const valueEl = required<HTMLElement>(client.el, "[data-pn-value]");
    // An earthwork balance is signed: net fill above baseline zero.
    valueEl.textContent = signed(pnKernel.value(client.pn));
    valueEl.classList.toggle("pending", pending.length > 0);
    const deltaSum = pending.reduce((sum, p) => sum + p.amount, 0);
    const deltaEl = required<HTMLElement>(client.el, "[data-pn-delta]");
    deltaEl.textContent =
      pending.length > 0 ? `Δ ${signed(deltaSum)} unsequenced` : "";
    // The ledger prints the CRDT's real internal state: the two monotone
    // tallies (P = fill, N = cut) whose difference is the value.
    required<HTMLElement>(client.el, "[data-pn-fill]").textContent = String(
      gCounter.value(client.pn.optimistic.positive),
    );
    required<HTMLElement>(client.el, "[data-pn-cut]").textContent = String(
      gCounter.value(client.pn.optimistic.negative),
    );
  }

  function orMapEntries(
    state: orMapKernel.OrMapState$,
  ): Map<string, string[] | number> {
    const entries = new Map<string, string[] | number>();
    for (const [key, value] of orMapKernel.entries(state).toArray()) {
      if (
        value instanceof orMapKernel.SetMembers
        || value instanceof orMapKernel.MvRegister
      ) {
        entries.set(key, value[0].toArray());
      } else if (value instanceof orMapKernel.Tally) {
        entries.set(key, value[0]);
      } else {
        throw new Error("OR-map register value is not used by this demo");
      }
    }
    return entries;
  }

  function pendingOrMapKeys(state: orMapKernel.OrMapState$): Set<string> {
    const keys = new Set<string>();
    for (const pending of state.pending.toArray()) {
      keys.add(pending.operation.key);
    }
    return keys;
  }

  function renderOrMap(client: DemoClient): void {
    const pending = pendingOrMapKeys(client.ormap);
    required<HTMLTableElement>(client.el, "table.dds-ormap").hidden =
      orMapMode !== "tally";
    required<HTMLElement>(client.el, ".ormap-set-panel").hidden =
      orMapMode !== "set";
    if (orMapMode === "set") {
      const optimistic = new Map(orMapKernel.entries(client.ormap).toArray());
      const confirmed = new Map(orMapKernel.sequenced_entries(client.ormap).toArray());
      const memberText = (
        entries: Map<string, orMapKernel.OrMapValue$>,
        key: string,
      ): string => {
        const value = entries.get(key);
        if (value === undefined) return "missing";
        if (!(value instanceof orMapKernel.SetMembers)) {
          throw new Error("OR-map set view received a non-set value");
        }
        const members = value[0].toArray();
        return members.length === 0 ? "empty set" : JSON.stringify(members);
      };
      for (const row of client.el.querySelectorAll<HTMLElement>(
        "[data-ormap-set-row]",
      )) {
        const key = row.dataset.ormapSetRow;
        if (key === undefined) {
          throw new Error("OR-map set row is missing data-ormap-set-row");
        }
        const local = required<HTMLElement>(row, "[data-ormap-members]");
        local.textContent = memberText(optimistic, key);
        local.classList.toggle("k-pending", pending.has(key));
        required<HTMLElement>(row, "[data-ormap-confirmed]").textContent =
          memberText(confirmed, key);
      }
      for (const control of client.el.querySelectorAll<
        HTMLButtonElement | HTMLInputElement | HTMLSelectElement
      >(".ormap-set-panel button, .ormap-set-panel input, .ormap-set-panel select")) {
        control.disabled = orMapRaceRunning;
      }
      return;
    }
    const entries = orMapEntries(client.ormap);
    for (const key of STOCKPILES) {
      const row = required<HTMLTableRowElement>(
        client.el,
        `.dds-ormap tr[data-key="${key}"]`,
      );
      const value = entries.get(key);
      const struck = typeof value !== "number";
      if (!struck) orMapRetained[client.id].set(key, value);
      row.classList.toggle("struck", struck);
      row.classList.toggle("pending", pending.has(key));
      required<HTMLElement>(row, "[data-ormap-value]").textContent = struck
        ? "struck"
        : signed(value);
      required<HTMLElement>(row, "[data-ormap-note]").textContent =
        pending.has(key)
        ? "unsequenced delta"
        : struck
          ? "hidden, not erased"
          : "";
    }
  }

  function orSetValues(state: orSetKernel.OrSetState$): Set<string> {
    return new Set(orSetKernel.values(state).toArray());
  }

  function pendingOrSetElements(
    state: orSetKernel.OrSetState$,
  ): Set<string> {
    const elements = new Set<string>();
    for (const pending of state.pending.toArray()) {
      elements.add(pending.operation.element);
    }
    return elements;
  }

  function renderOrSet(client: DemoClient): void {
    const values = orSetValues(client.orset);
    const pending = pendingOrSetElements(client.orset);
    for (const element of MARKERS) {
      const row = required<HTMLTableRowElement>(
        client.el,
        `.dds-orset tr[data-key="${element}"]`,
      );
      const present = values.has(element);
      row.classList.toggle("absent", !present);
      row.classList.toggle("pending", pending.has(element));
      required<HTMLElement>(row, "[data-orset-value]").textContent = present
        ? "marked"
        : "clear";
      required<HTMLElement>(row, "[data-orset-note]").textContent =
        pending.has(element)
        ? "unsequenced tag"
        : present
          ? "live tag observed"
          : "no live tags";
    }
  }

  function gSetValues(state: gSetKernel.GSetState$): Set<string> {
    return new Set(gSetKernel.values(state).toArray());
  }

  function pendingGSetElements(state: gSetKernel.GSetState$): Set<string> {
    const elements = new Set<string>();
    for (const pending of state.pending.toArray()) {
      elements.add(pending.operation.element);
    }
    return elements;
  }

  function renderGSet(client: DemoClient): void {
    const values = gSetValues(client.gset);
    const pending = pendingGSetElements(client.gset);
    for (const element of BENCHMARKS) {
      const row = required<HTMLTableRowElement>(
        client.el,
        `.dds-gset tr[data-key="${element}"]`,
      );
      const recorded = values.has(element);
      row.classList.toggle("absent", !recorded);
      row.classList.toggle("pending", pending.has(element));
      required<HTMLElement>(row, "[data-gset-value]").textContent = recorded
        ? "recorded"
        : "unrecorded";
      required<HTMLElement>(row, "[data-gset-note]").textContent =
        pending.has(element)
        ? "unsequenced permanent fact"
        : recorded
          ? "in the registry"
          : "not yet observed";
      required<HTMLButtonElement>(row, "[data-gset-add]").disabled =
        recorded || pending.has(element);
    }
  }

  function twoPSetValues(state: twoPSetKernel.TwoPSetState$): Set<string> {
    return new Set(twoPSetKernel.values(state).toArray());
  }

  function twoPSetTombstones(
    state: twoPSetKernel.TwoPSetState$,
  ): Set<string> {
    return new Set(gset.to_list(state.optimistic.removed).toArray());
  }

  function pendingTwoPSetElements(
    state: twoPSetKernel.TwoPSetState$,
  ): Map<string, "retire" | "place"> {
    const pending = new Map<string, "retire" | "place">();
    for (const entry of state.pending.toArray()) {
      pending.set(
        entry.operation.element,
        entry.operation instanceof twoPSetKernel.Remove ? "retire" : "place",
      );
    }
    return pending;
  }

  function renderTwoPSet(client: DemoClient): void {
    const values = twoPSetValues(client.twopset);
    const tombstones = twoPSetTombstones(client.twopset);
    const pending = pendingTwoPSetElements(client.twopset);
    for (const element of RETIRED_MARKERS) {
      const row = required<HTMLTableRowElement>(
        client.el,
        `.dds-twopset tr[data-key="${element}"]`,
      );
      const active = values.has(element);
      const retired = tombstones.has(element);
      const pendingKind = pending.get(element);
      row.classList.toggle("absent", !active && !retired);
      row.classList.toggle("retired", retired);
      row.classList.toggle("pending", pending.has(element));
      required<HTMLElement>(row, "[data-twopset-value]").textContent = retired
        ? "retired"
        : active
          ? "active"
          : "unplaced";
      required<HTMLElement>(row, "[data-twopset-note]").textContent =
        pendingKind
        ? `unsequenced ${pendingKind}`
        : retired
          ? "tombstone wins"
          : active
          ? "active marker"
          : "not placed";
      const add = required<HTMLButtonElement>(row, "[data-twopset-add]");
      add.disabled =
        active || pending.has(element);
      add.textContent = retired
        ? "Try place"
        : "Place";
      add.setAttribute(
        "aria-label",
        `${retired ? "Try to re-place retired marker" : "Place marker"} ${element} on ${client.id.toUpperCase()}`,
      );
      required<HTMLButtonElement>(row, "[data-twopset-remove]").disabled =
        retired || pendingKind === "retire";
    }
  }

  function renderClaims(client: DemoClient): void {
    for (const key of SLOTS) {
      const row = required<HTMLTableRowElement>(
        client.el,
        `.dds-claims tr[data-key="${key}"]`,
      );
      const holder = readClaimant(claimsKernel.get(client.claims, key));
      const filed = gdict.has_key(client.claims.pending, key);
      // Non-optimistic by design: a filed claim never prints as the holder —
      // the row shows "—" in ink until the claim round-trips as won or lost.
      required<HTMLElement>(row, "[data-holder]").textContent = holder ?? "—";
      row.classList.toggle("filed", filed);
      required<HTMLElement>(row, "[data-claim-note]").textContent = filed
        ? "claim filed · outcome unknown"
        : (claimNotes[client.id][key] ??
          (holder === CLAIMANTS[client.id] ? "yours" : ""));
      required<HTMLButtonElement>(row, "[data-claim]").disabled = filed;
    }
  }

  function registerVersions(
    state: registerKernel.RegisterState$,
    key: string,
  ): string[] {
    const versions = resultValue(registerKernel.read_versions(state, key));
    if (versions === null) return [];
    return versions
      .toArray()
      .map((value) => JSON.parse(json.to_string(value)));
  }

  function renderRegisters(client: DemoClient): void {
    for (const key of REGISTERS) {
      const row = required<HTMLTableRowElement>(
        client.el,
        `.dds-registers tr[data-key="${key}"]`,
      );
      const atomic = readJsonString(
        registerKernel.read(client.registers, key, new registerKernel.Atomic()),
      );
      const lww = readJsonString(
        registerKernel.read(client.registers, key, new registerKernel.Lww()),
      );
      const versions = registerVersions(client.registers, key);
      const filed = registerPending[client.id].has(key);
      required<HTMLElement>(row, "[data-register-atomic]").textContent =
        atomic ?? "—";
      required<HTMLElement>(row, "[data-register-lww]").textContent =
        lww ?? "—";
      row.classList.toggle("filed", filed);
      required<HTMLElement>(row, "[data-register-note]").textContent = filed
        ? "revision filed · atomic outcome unknown"
        : (registerNotes[client.id][key] ?? "");
      required<HTMLElement>(row, "[data-register-versions]").textContent =
        versions.length > 1 ? `${versions.length} concurrent versions` : "";
      required<HTMLButtonElement>(row, "[data-register-write]").disabled =
        filed;
    }
  }

  function orderedQueue(state: orderedKernel.OrderedState$): string[] {
    return orderedKernel
      .summary_queue(state)
      .toArray()
      .map((value) => JSON.parse(json.to_string(value)));
  }

  function orderedJobs(state: orderedKernel.OrderedState$) {
    return orderedKernel
      .summary_jobs(state)
      .toArray()
      .map(([id, job]) => ({
        id,
        value: JSON.parse(json.to_string(job.value)),
        owner: optionValue(job.owner),
      }));
  }

  function firstOwnedOrderedJob(client: DemoClient) {
    return orderedJobs(client.ordered).find(
      (job) => job.owner === CLIENT_NUMBERS[client.id],
    );
  }

  function renderOrdered(client: DemoClient): void {
    const queue = orderedQueue(client.ordered);
    const jobs = orderedJobs(client.ordered);
    const localJob = firstOwnedOrderedJob(client);
    const filed = orderedPending[client.id].size > 0;
    const queueRow = required<HTMLTableRowElement>(
      client.el,
      ".dds-ordered tbody tr:first-child",
    );
    const jobsRow = required<HTMLTableRowElement>(
      client.el,
      ".dds-ordered tbody tr:last-child",
    );
    queueRow.classList.toggle("filed", filed);
    jobsRow.classList.toggle("filed", filed);
    required<HTMLElement>(queueRow, "[data-ordered-queue]").textContent =
      queue.length === 0 ? "empty" : queue.join(", ");
    required<HTMLElement>(jobsRow, "[data-ordered-jobs]").textContent =
      jobs.length === 0
        ? "none"
        : jobs
            .map((job) =>
              `${job.value} · ${
                job.owner === null ? "local" : CLIENT_NAMES[job.owner] ?? "local"
              }`
            )
            .join(", ");
    required<HTMLElement>(queueRow, "[data-ordered-note]").textContent = filed
      ? "op filed · waiting for SN"
      : orderedNotes[client.id];
    required<HTMLButtonElement>(queueRow, "[data-ordered-add]").disabled =
      filed;
    required<HTMLButtonElement>(queueRow, "[data-ordered-acquire]").disabled =
      filed;
    required<HTMLButtonElement>(jobsRow, "[data-ordered-complete]").disabled =
      filed || !localJob;
    required<HTMLButtonElement>(jobsRow, "[data-ordered-release]").disabled =
      filed || !localJob;
  }

  function taskQueues(
    state: taskManagerKernel.TaskManagerState$,
  ): Map<string, number[]> {
    const queues = new Map<string, number[]>();
    for (const [task, queue] of taskManagerKernel.summary_queues(state).toArray()) {
      queues.set(task, queue.toArray());
    }
    return queues;
  }

  function taskPendingKeys(
    state: taskManagerKernel.TaskManagerState$,
  ): Set<string> {
    const keys = new Set<string>();
    for (
      const [task, pending] of gdict
        .to_list<string, TaskPendingList>(state.pending)
        .toArray()
    ) {
      if (pending.toArray().length > 0) keys.add(task);
    }
    return keys;
  }

  function renderTaskManager(client: DemoClient): void {
    const queues = taskQueues(client.taskmanager);
    const pending = taskPendingKeys(client.taskmanager);
    for (const task of TASKS) {
      const row = required<HTMLTableRowElement>(
        client.el,
        `.dds-tasks tr[data-key="${task}"]`,
      );
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
      required<HTMLElement>(row, "[data-task-assignee]").textContent =
        assignee === null ? "—" : CLIENT_NAMES[assignee];
      required<HTMLElement>(row, "[data-task-waiters]").textContent =
        waiters.length === 0
          ? "empty"
          : waiters.map((id) => CLIENT_NAMES[id]).join(" → ");
      required<HTMLElement>(row, "[data-task-note]").textContent =
        pending.has(task)
        ? (taskNotes[client.id][task] ?? "op filed · waiting for SN")
        : taskNotes[client.id][task] ??
          (assignedHere ? "yours" : queuedHere ? "waiting" : "");
      required<HTMLButtonElement>(row, "[data-task-volunteer]").disabled =
        pending.has(task) || queuedHere;
      required<HTMLButtonElement>(row, "[data-task-abandon]").disabled =
        pending.has(task) || !queuedHere;
      required<HTMLButtonElement>(row, "[data-task-complete]").disabled =
        pending.has(task) || !assignedHere;
    }
  }

  function pactAccepted(
    state: pactKernel.PactMapState$,
    key: string,
  ): { value: string | null; sequence: number } | null {
    const accepted = resultValue(pactKernel.get_with_details(state, key));
    if (accepted === null) return null;
    return {
      value: readOptionalJsonString(accepted.value),
      sequence: accepted.sequence_number,
    };
  }

  function pactPendingValue(
    state: pactKernel.PactMapState$,
    key: string,
  ): string | null {
    const pending = resultValue(pactKernel.get_pending(state, key));
    if (pending === null) return null;
    return readOptionalJsonString(pending) ?? "delete";
  }

  function pactSignoffs(
    state: pactKernel.PactMapState$,
    key: string,
  ): number[] {
    const entry = pactKernel
      .summary_entries(state)
      .toArray()
      .find(([entryKey]) => entryKey === key);
    if (!entry) return [];
    return optionValue(entry[1].pending)?.expected_signoffs.toArray() ?? [];
  }

  function renderPact(client: DemoClient): void {
    for (const key of PACT_KEYS) {
      const row = required<HTMLTableRowElement>(
        client.el,
        `.dds-pact tr[data-key="${key}"]`,
      );
      const accepted = pactAccepted(client.pact, key);
      const pending = pactPendingValue(client.pact, key);
      const signoffs = pactSignoffs(client.pact, key);
      const filed = pactPending[client.id].has(key);
      row.classList.toggle("filed", filed || pending !== null);
      required<HTMLElement>(row, "[data-pact-accepted]").textContent =
        accepted?.value ?? "—";
      required<HTMLElement>(row, "[data-pact-pending]").textContent =
        pending ?? "—";
      required<HTMLElement>(row, "[data-pact-signoffs]").textContent =
        signoffs.length > 0
          ? `awaiting ${signoffs.map((id) => CLIENT_NAMES[id]).join(" + ")}`
          : "";
      required<HTMLElement>(row, "[data-pact-note]").textContent = filed
        ? (pactNotes[client.id][key] ?? "proposal filed")
        : (pactNotes[client.id][key] ?? "");
      required<HTMLButtonElement>(row, "[data-pact-set]").disabled =
        filed || pending !== null;
      required<HTMLButtonElement>(row, "[data-pact-delete]").disabled =
        filed || pending !== null || accepted === null || accepted.value === null;
    }
  }

  function renderBadge(client: DemoClient): void {
    let count: number;
    switch (activeDds) {
      case "claims":
        count = gdict.size(client.claims.pending);
        break;
      case "counter":
        count = counterPending(client).count;
        break;
      case "registers":
        count = registerPending[client.id].size;
        break;
      case "ordered":
        count = orderedPending[client.id].size;
        break;
      case "tasks":
        count = taskPendingKeys(client.taskmanager).size;
        break;
      case "pact":
        count = pactPending[client.id].size;
        break;
      case "lww-register":
        count = client["lww-register"].pending.toArray().length;
        break;
      case "gcounter":
        count = client.gcounter.pending.toArray().length;
        break;
      case "orset":
        count = client.orset.pending.toArray().length;
        break;
      case "gset":
        count = client.gset.pending.toArray().length;
        break;
      case "twopset":
        count = client.twopset.pending.toArray().length;
        break;
      case "ormap":
        count = client.ormap.pending.toArray().length;
        break;
      case "map":
        count = client.map.pending.toArray().length;
        break;
      case "pn":
        count = client.pn.pending.toArray().length;
        break;
      case "lww-map":
        count = client["lww-map"].pending.toArray().length;
        break;
      case "mv-register":
        count = client["mv-register"].pending.toArray().length;
        break;
      case "or-map-mv-register":
        count = client["or-map-mv-register"].pending.toArray().length;
        break;
    }
    const badge = required<HTMLElement>(client.el, "[data-pending-count]");
    badge.textContent = `${count} pending`;
    if (count === 0) badge.setAttribute("data-zero", "");
    else badge.removeAttribute("data-zero");
  }

  function render(client: DemoClient): void {
    if (present.has("lww-map")) renderLwwMap(client);
    if (present.has("lww-register")) renderLwwRegister(client);
    if (present.has("mv-register")) renderMv(client);
    if (present.has("map")) renderMap(client);
    if (present.has("counter")) renderCounter(client);
    if (present.has("gcounter")) renderGCounter(client);
    if (present.has("pn")) renderPn(client);
    if (present.has("ormap")) renderOrMap(client);
    if (present.has("or-map-mv-register")) renderOrMapMv(client);
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

  function pendingTotal(): number {
    let total = 0;
    for (const client of Object.values(clients)) {
      total += client.map.pending.toArray().length;
      total += counterPending(client).count;
      total += client.gcounter.pending.toArray().length;
      total += client.pn.pending.toArray().length;
      total += client["lww-register"].pending.toArray().length;
      total += client["lww-map"].pending.toArray().length;
      total += client["mv-register"].pending.toArray().length;
      total += client.ormap.pending.toArray().length;
      total += client["or-map-mv-register"].pending.toArray().length;
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

  function replicaSignature(client: DemoClient): string {
    const { entries, vclock } = JSON.parse(
      json.to_string(mvKernel.summary(client["mv-register"])),
    ).state;
    return JSON.stringify([
      entries
        .map(
          ({ tag, value }: {
            tag: { r: string; c: number };
            value: string;
          }) => [tag.r, tag.c, value],
        )
        .sort(),
      Object.entries(vclock).sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0),
      json.to_string(lwwRegisterKernel.summary(client["lww-register"])),
      lwwMapMetadata(client["lww-map"]),
      mapSnapshot(client.map),
      counterValue(client),
      gCounterSnapshot(client.gcounter),
      pnKernel.value(client.pn),
      orMapSnapshot(client.ormap),
      canonicalOrMapMvSummary(client["or-map-mv-register"]),
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

  function renderStatus(): void {
    if (activeDds === "ormap" && orMapMode === "set") {
      raceBtn.disabled = orMapRaceRunning || !linkUp || sequencer.inFlight > 0
        || Object.values(clients).some((client) => client.ormap.pending.toArray().length > 0);
    }
    const pending = pendingTotal();
    const inFlight = sequencer.inFlight;
    if (!linkUp) {
      statusEl.innerHTML = `<span class="stamp revising">Link cut</span> Client B off the wire · ${heldSubmits.length} to resubmit · ${heldHops.length} to catch up`;
      return;
    }
    if (inFlight === 0 && pending === 0) {
      const signatures = Object.values(clients).map(replicaSignature);
      const same = signatures.every((sig) => sig === signatures[0]);
      statusEl.innerHTML = same
        ? `<span class="stamp converged">Converged</span> replicas identical · ${
          activeDds === "mv-register" && mvKernel.values(clients.a["mv-register"]).toArray().length > 1
            ? `${mvKernel.values(clients.a["mv-register"]).toArray().length} alternatives · ready to resolve`
            : "nothing pending"}`
        : `<span class="stamp revising">Diverged</span> this should be impossible — please file a bug`;
    } else {
      statusEl.innerHTML = `<span class="stamp revising">Revising</span> ${inFlight} op${inFlight === 1 ? "" : "s"} in flight · ${pending} pending`;
    }
  }

  function mapSnapshot(state: mapKernel.MapState$) {
    return mapKernel
      .sequenced_entries(state)
      .toArray()
      .map(([k, v]) => [k, json.to_string(v)]);
  }

  function gCounterSnapshot(state: gCounterKernel.GCounterState$) {
    const [counts] = gCounter.to_parts(state.sequenced);
    return [
      readCount(gdict.get(counts, replicaId.new$("client-a"))),
      readCount(gdict.get(counts, replicaId.new$("client-b"))),
    ];
  }

  function claimsSnapshot(state: claimsKernel.ClaimsState$) {
    return claimsKernel
      .summary_entries(state)
      .toArray()
      .map(([k, v, s]) => [k, json.to_string(v), s]);
  }

  function orMapSnapshot(state: orMapKernel.OrMapState$) {
    return orMapKernel
      .sequenced_entries(state)
      .toArray()
      .map(([k, v]) => [k, v instanceof orMapKernel.SetMembers ? v[0].toArray() : v[0]]);
  }

  function orSetSnapshot(state: orSetKernel.OrSetState$) {
    return orSetKernel.sequenced_values(state).toArray();
  }

  function gSetSnapshot(state: gSetKernel.GSetState$) {
    return gSetKernel.sequenced_values(state).toArray();
  }

  function twoPSetSnapshot(state: twoPSetKernel.TwoPSetState$) {
    return [
      twoPSetKernel.sequenced_values(state).toArray(),
      gset.to_list(state.sequenced.removed).toArray(),
    ];
  }

  function registerSnapshot(state: registerKernel.RegisterState$) {
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

  function orderedSnapshot(state: orderedKernel.OrderedState$) {
    return [
      orderedQueue(state),
      orderedJobs(state).map((job) => [job.id, job.value, job.owner]),
    ];
  }

  function taskManagerSnapshot(state: taskManagerKernel.TaskManagerState$) {
    return taskManagerKernel
      .summary_queues(state)
      .toArray()
      .map(([task, queue]) => [task, queue.toArray()]);
  }

  function pactSnapshot(state: pactKernel.PactMapState$) {
    return pactKernel
      .summary_entries(state)
      .toArray()
      .map(([key, pact]) => {
        const accepted = optionValue(pact.accepted);
        const pending = optionValue(pact.pending);
        return [
          key,
          accepted
            ? [
                readOptionalJsonString(accepted.value),
                accepted.sequence_number,
              ]
            : null,
          pending
            ? [
                readOptionalJsonString(pending.value),
                pending.expected_signoffs.toArray(),
              ]
            : null,
        ];
      });
  }

  function logRejected(stampedSn: number, key: string): void {
    const li = document.createElement("li");
    li.className = "rejected";
    li.textContent = `#${String(stampedSn).padStart(2, "0")} rejected — ${key} held · first writer wins`;
    opLog.push(li);
  }

  function logOp(
    stampedSn: number,
    origin: ClientId,
    operation: OperationEnvelope,
  ): void {
    const { ddsId } = operation;
    const li = document.createElement("li");
    li.textContent = `#${String(stampedSn).padStart(2, "0")} ${describeOp(operation)} · from ${origin.toUpperCase()}`;
    opLog.push(li);
    seqCounter.textContent = `SN ${stampedSn}`;
    seqCounter.classList.remove("stamped");
    void seqCounter.offsetWidth;
    seqCounter.classList.add("stamped");
    if (fieldNotes.active && ddsId === activeDds && FIELD_FLASH.has(ddsId)) {
      fieldNotes.flashLog();
    }
  }

  function describeOrderedPending(
    op: orderedKernel.OrderedOperation$,
  ): string {
    if (op instanceof orderedKernel.Add) return `add:${json.to_string(op.value)}`;
    return `${op.constructor.name}:${op.acquire_id}`;
  }

  // ── op flow animation ─────────────────────────────────────────────────────
  // (Flow-dot rendering lives in the shared `flow` layer created above.)

  // ── protocol: client → sequencer → broadcast ──────────────────────────────

  function deliver(
    target: DemoClient,
    originId: ClientId,
    operation: OperationEnvelope,
    seq: number,
    counterSeq = seq,
  ): void {
    const { ddsId, op } = operation;
    // Every op advances the container SN on every replica — all structures
    // ride the one stream. Claims file their `reference_sequence_number` against this.
    target.lastSeq = seq;
    if (ddsId === "map") {
      if (target.id === originId) {
        const result = mapKernel.ack_local(target.map, op);
        const next = resultValue(result);
        if (next !== null) target.map = next;
        else console.error("unexpected ack", resultError(result));
      } else {
        const [next] = mapKernel.apply_remote(target.map, op);
        target.map = next;
      }
    } else if (ddsId === "lww-map") {
      if (target.id === originId) {
        const result = lwwMapKernel.ack_local_with_message_id(
          target["lww-map"], op.operation, op.messageId,
        );
        target["lww-map"] = expectOk(
          result,
          "Unexpected LWWMap acknowledgement",
        );
      } else {
        const result = lwwMapKernel.apply_remote(target["lww-map"], op.operation);
        [target["lww-map"]] = expectOk(result, "Unexpected LWWMap delivery");
      }
    } else if (ddsId === "lww-register") {
      const result = target.id === originId
        ? lwwRegisterKernel.ack_local_with_message_id(
          target["lww-register"],
          op.operation,
          op.messageId,
        )
        : lwwRegisterKernel.apply_remote(
          target["lww-register"],
          op.operation,
        );
      const delivered = expectOk(
        result,
        "Unexpected LWW-register delivery",
      );
      target["lww-register"] = delivered instanceof Array
        ? delivered[0]
        : delivered;
    } else if (ddsId === "mv-register") {
      if (target.id === originId) {
        const result = mvKernel.ack_local_with_message_id(
          target["mv-register"], op.operation, op.messageId,
        );
        target["mv-register"] = expectOk(
          result,
          "Unexpected MV-register acknowledgement",
        );
      } else {
        [target["mv-register"]] = mvKernel.apply_remote(target["mv-register"], op.operation);
      }
    } else if (ddsId === "pn") {
      if (target.id === originId) {
        const result = pnKernel.ack_local(target.pn, op);
        const next = resultValue(result);
        if (next !== null) target.pn = next;
        else console.error("unexpected ack", resultError(result));
      } else {
        const [next] = pnKernel.apply_remote(target.pn, op);
        target.pn = next;
      }
    } else if (ddsId === "gcounter") {
      if (target.id === originId) {
        const result = gCounterKernel.ack_local(target.gcounter, op);
        const next = resultValue(result);
        if (next !== null) target.gcounter = next;
        else console.error("unexpected ack", resultError(result));
      } else {
        const [next] = gCounterKernel.apply_remote(target.gcounter, op);
        target.gcounter = next;
      }
    } else if (ddsId === "or-map-mv-register") {
      if (target.id === originId) {
        const result = orMapKernel.ack_local_with_message_id(
          target[ddsId], op.operation, op.messageId,
        );
        target[ddsId] = expectOk(
          result,
          "Unexpected OR-map MV-register acknowledgement",
        );
      } else {
        const result = orMapKernel.apply_remote(target[ddsId], op.operation);
        [target[ddsId]] = expectOk(
          result,
          "Unexpected OR-map MV-register delivery",
        );
      }
    } else if (ddsId === "ormap") {
      if (target.id === originId) {
        const result = orMapKernel.ack_local_with_message_id(target.ormap, op.operation, op.messageId);
        target.ormap = expectOk(result, "Unexpected OR-map acknowledgement");
      } else {
        const result = orMapKernel.apply_remote(target.ormap, op.operation);
        [target.ormap] = expectOk(
          result,
          "Unexpected remote OR-map operation",
        );
      }
    } else if (ddsId === "orset") {
      if (target.id === originId) {
        const result = orSetKernel.ack_local(target.orset, op);
        const next = resultValue(result);
        if (next !== null) target.orset = next;
        else console.error("unexpected OR-set ack", resultError(result));
      } else {
        const [next] = orSetKernel.apply_remote(target.orset, op);
        target.orset = next;
      }
    } else if (ddsId === "gset") {
      if (target.id === originId) {
        const result = gSetKernel.ack_local(target.gset, op);
        const next = resultValue(result);
        if (next !== null) target.gset = next;
        else console.error("unexpected G-set ack", resultError(result));
      } else {
        const [next] = gSetKernel.apply_remote(target.gset, op);
        target.gset = next;
      }
    } else if (ddsId === "twopset") {
      if (target.id === originId) {
        const result = twoPSetKernel.ack_local(target.twopset, op);
        const next = resultValue(result);
        if (next !== null) target.twopset = next;
        else console.error("unexpected 2P-set ack", resultError(result));
      } else {
        const [next] = twoPSetKernel.apply_remote(target.twopset, op);
        target.twopset = next;
      }
    } else if (ddsId === "claims") {
      if (target.id === originId) {
        // The ack resolves the deferred outcome: only now does the origin
        // learn whether its claim won or lost the race.
        const result = claimsKernel.ack_local(target.claims, op, seq);
        const acknowledged = resultValue(result);
        if (acknowledged !== null) {
          const [next, _events, outcome] = acknowledged;
          target.claims = next;
          if (outcome instanceof claimsKernel.Lost) {
            const holder = readOptionalJsonString(outcome.current_value);
            claimNotes[target.id][op.key] = holder
              ? `lost — ${holder} holds it`
              : "lost";
            logRejected(seq, op.key);
          }
        } else console.error("unexpected ack", resultError(result));
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
        const acquireOutcome = optionValue(outcome);
        if (acquireOutcome !== null) {
          orderedNotes[target.id] =
            acquireOutcome instanceof orderedKernel.AcquiredItem
              ? `acquired ${JSON.parse(json.to_string(acquireOutcome.value))}`
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
        const acknowledged = resultValue(result);
        if (acknowledged !== null) {
          const [next] = acknowledged;
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
        } else {
          console.error("unexpected TaskManager ack", resultError(result));
        }
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
          submit(target.id, { ddsId: "pact", op: reaction.operation });
        }
      } else {
        const result = pactKernel.apply_accept(
          target.pact,
          op.key,
          CLIENT_NUMBERS[originId],
          seq,
        );
        const accepted = resultValue(result);
        if (accepted !== null) {
          const [next] = accepted;
          target.pact = next;
          if (target.id === originId) {
            pactPending[target.id].delete(op.key);
            pactNotes[target.id][op.key] = "signed off";
          }
        } else {
          console.error("unexpected pact accept", resultError(result));
        }
      }
    } else {
      const origin = clients[originId];
      const result = websiteRuntime.deliver_counter(
        target.counterCore,
        origin.counterClientId,
        counterSeq,
        op.write,
      );
      const ingested = resultValue(result);
      if (ingested !== null) target.counterCore = ingested;
      else {
        console.error(
          "unexpected counter channel ingest failure",
          resultError(result),
        );
      }
    }
  }

  function submit(
    originId: ClientId,
    operation: OperationEnvelope,
    onDelivered: (client: DemoClient) => void = () => {},
  ): void {
    const { ddsId, op } = operation;
    // The author captured this epoch before offline work could be parked.
    if (ddsId === "or-map-mv-register" && op.epoch !== orMapMvEpoch) return;
    if (ddsId === "lww-map" && op.epoch !== lwwMapEpoch) return;
    if (ddsId === "lww-register" && op.epoch !== lwwRegisterEpoch) return;
    if (ddsId === "mv-register" && op.epoch !== mvEpoch) return;
    if (ddsId === "ormap" && op.epoch !== orMapEpoch) return;
    // Offline author: the edit already applied optimistically; the send parks
    // until the link is restored, then resubmits — like the runtime's own
    // resubmit queue.
    if (originId === "b" && !linkUp) {
      heldSubmits.push(() => submit(originId, operation, onDelivered));
      renderStatus();
      return;
    }
    // Claims have no compensating op, so reset reloads replicas out of band
    // and bumps the epoch; a claim still in flight is dropped rather than
    // stamped, or it would commit on one replica and fail to ack on the
    // other. Each DDS that resets out of band carries its own epoch.
    const epochFor = () =>
      ddsId === "or-map-mv-register"
        ? orMapMvEpoch
      : ddsId === "lww-map"
        ? lwwMapEpoch
      : ddsId === "lww-register"
        ? lwwRegisterEpoch
      : ddsId === "mv-register"
        ? mvEpoch
      : ddsId === "ormap"
        ? orMapEpoch
      : ddsId === "claims"
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
      label: describeOp(operation),
      guard: () => {
        const snapshot = epochFor();
        return () => snapshot !== epochFor();
      },
      onSequence: (stamped) => {
        const stampedCounter = ddsId === "counter" ? ++counterSn : null;
        logOp(stamped, originId, operation);
        if (ddsId === "or-map-mv-register") {
          lastOrMapMv ??= { op, sn: stamped };
          if (activeDds === "or-map-mv-register") replayBtn.disabled = false;
        } else if (ddsId === "lww-map") {
          lastLwwMap = { op, sn: stamped };
          if (activeDds === "lww-map") replayBtn.disabled = false;
        } else if (ddsId === "lww-register") {
          lastLwwRegister = { op, sn: stamped };
          if (activeDds === "lww-register") replayBtn.disabled = false;
        } else if (ddsId === "mv-register") {
          lastMv ??= { op, sn: stamped };
          if (activeDds === "mv-register") replayBtn.disabled = false;
        } else if (ddsId === "pn") {
          lastPn = { op, sn: stamped };
          replayBtn.disabled = false;
        } else if (ddsId === "gcounter") {
          lastGCounter = { op, sn: stamped };
          replayBtn.disabled = false;
        } else if (ddsId === "ormap") {
          // Set replay keeps the first add, including after removal/re-add.
          if (orMapMode === "tally") lastOrMap = { op, sn: stamped };
          else if (op.operation instanceof orMapKernel.AddMember) lastOrMap ??= { op, sn: stamped };
          if (activeDds === "ormap") replayBtn.disabled = !lastOrMap;
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
        deliver(
          target,
          originId,
          operation,
          seq,
          extra.stampedCounter ?? seq,
        );
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
        onDelivered(target);
      },
    });
  }

  function localSet(clientId: ClientId, key: string, value: number): void {
    const client = clients[clientId];
    const [next, _events, op] = mapKernel.set(client.map, key, jsonInt(value));
    client.map = next;
    fieldNotes.trackChange("map", client.el, true, () => render(client));
    submit(clientId, { ddsId: "map", op });
  }

  function localIncrement(clientId: ClientId, amount: number): void {
    const client = clients[clientId];
    const result = websiteRuntime.counter_increment(
      client.counterCore,
      COUNTER_ADDRESS,
      amount,
    );
    const incremented = resultValue(result);
    if (incremented === null) {
      console.error(
        "unexpected counter channel increment refusal",
        resultError(result),
      );
      return;
    }
    client.counterCore = incremented.core;
    fieldNotes.trackChange("counter", client.el, true, () => render(client));
    submit(clientId, {
      ddsId: "counter",
      op: {
        amount,
        write: incremented.write,
      },
    });
  }

  function localGCounterIncrement(clientId: ClientId, amount: number): void {
    const client = clients[clientId];
    // The kernel refuses a negative amount, which is the whole point of a
    // grow-only counter. The demo never offers one, so a refusal is a bug here.
    const applied = gCounterKernel.increment(client.gcounter, amount);
    const incremented = resultValue(applied);
    if (incremented === null) {
      console.error("g-counter refused an increment", resultError(applied));
      return;
    }
    const [next, _events, operation] = incremented;
    client.gcounter = next;
    fieldNotes.trackChange("gcounter", client.el, true, () => render(client));
    submit(clientId, { ddsId: "gcounter", op: operation });
  }

  function localLwwSet(
    clientId: ClientId,
    value: string,
    wallClock = Date.now(),
  ): void {
    const client = clients[clientId];
    const result = lwwRegisterKernel.set(
      client["lww-register"],
      value,
      wallClock,
    );
    const updated = resultValue(result);
    if (updated === null) {
      console.error("LWW register refused a write", resultError(result));
      return;
    }
    const [next, _events, operation, messageId] = updated;
    client["lww-register"] = next;
    fieldNotes.trackChange("lww-register", client.el, true, () => render(client));
    submit(clientId, {
      ddsId: "lww-register",
      op: {
        operation,
        messageId,
        epoch: lwwRegisterEpoch,
      },
    });
  }

  function localLwwMapEdit(
    clientId: ClientId,
    key: string,
    value: string | null,
    wallClock = Date.now(),
  ): void {
    const client = clients[clientId];
    const result = value === null
      ? lwwMapKernel.remove(client["lww-map"], key, wallClock)
      : lwwMapKernel.set(client["lww-map"], key, value, wallClock);
    const [next, _events, operation, messageId] = expectOk(
      result,
      "LWWMap refused an edit",
    );
    client["lww-map"] = next;
    fieldNotes.trackChange("lww-map", client.el, true, () => render(client));
    submit(clientId, {
      ddsId: "lww-map",
      op: { operation, messageId, epoch: lwwMapEpoch },
    });
  }

  function localMvSet(clientId: ClientId, value: string): void {
    const client = clients[clientId];
    const [next, _events, operation, messageId] = mvKernel.set(client["mv-register"], value);
    client["mv-register"] = next;
    fieldNotes.trackChange("mv-register", client.el, true, () => render(client));
    submit(clientId, {
      ddsId: "mv-register",
      op: { operation, messageId, epoch: mvEpoch },
    });
  }

  function localOrMapMvEdit(
    clientId: ClientId,
    key: string,
    value: string | null,
  ): void {
    const client = clients[clientId];
    const result = value === null
      ? orMapKernel.remove(client["or-map-mv-register"], key)
      : orMapKernel.set_mv_register(client["or-map-mv-register"], key, value);
    const [next, _events, operation, messageId] = expectOk(
      result,
      "OR-map MV register refused an edit",
    );
    client["or-map-mv-register"] = next;
    fieldNotes.trackChange("or-map-mv-register", client.el, true, () => render(client));
    submit(clientId, {
      ddsId: "or-map-mv-register",
      op: { operation, messageId, epoch: orMapMvEpoch },
    });
  }

  function localPnUpdate(clientId: ClientId, amount: number): void {
    const client = clients[clientId];
    // `update` also returns the local message id; the demo's sequencer acks
    // in FIFO order, so only the op needs to travel.
    const [next, _events, op] = pnKernel.update(client.pn, amount);
    client.pn = next;
    fieldNotes.trackChange("pn", client.el, true, () => render(client));
    submit(clientId, { ddsId: "pn", op });
  }

  function localOrMapLog(
    clientId: ClientId,
    key: string,
    amount: number,
  ): Promise<void> {
    return applyLocalOrMapEdit(
      clientId,
      orMapKernel.increment(clients[clientId].ormap, key, amount),
    );
  }

  function localOrMapStrike(
    clientId: ClientId,
    key: string,
  ): Promise<void> {
    return applyLocalOrMapEdit(
      clientId,
      orMapKernel.remove(clients[clientId].ormap, key),
    );
  }

  function localOrMapReopen(clientId: ClientId, key: string): Promise<void> {
    return localOrMapLog(clientId, key, orMapRetained[clientId].get(key) ?? 0);
  }

  function localOrMapAddMember(
    clientId: ClientId,
    key: string,
    member: string,
  ): Promise<void> {
    return applyLocalOrMapEdit(
      clientId,
      orMapKernel.add_member(clients[clientId].ormap, key, member),
    );
  }

  function localOrMapRemoveMember(
    clientId: ClientId,
    key: string,
    member: string,
  ): Promise<void> {
    return applyLocalOrMapEdit(
      clientId,
      orMapKernel.remove_member(clients[clientId].ormap, key, member),
    );
  }

  function applyLocalOrMapEdit(
    clientId: ClientId,
    result: ReturnType<typeof orMapKernel.increment>,
  ): Promise<void> {
    const client = clients[clientId];
    const [next, _events, operation, messageId] = expectOk(
      result,
      "OR-map edit failed",
    );
    client.ormap = next;
    fieldNotes.trackChange("ormap", client.el, true, () => render(client));
    return new Promise<void>((resolve) => {
      let remaining = CLIENT_IDS.length;
      submit(
        clientId,
        {
          ddsId: "ormap",
          op: {
            operation,
            messageId,
            epoch: orMapEpoch,
            mode: orMapMode,
          },
        },
        () => {
          if (--remaining === 0) resolve();
        },
      );
    });
  }

  function localOrSetAdd(clientId: ClientId, element: string): void {
    const client = clients[clientId];
    const [next, _events, op] = orSetKernel.add(client.orset, element);
    client.orset = next;
    fieldNotes.trackChange("orset", client.el, true, () => render(client));
    submit(clientId, { ddsId: "orset", op });
  }

  function localOrSetRemove(clientId: ClientId, element: string): void {
    const client = clients[clientId];
    const [next, _events, op] = orSetKernel.remove(client.orset, element);
    client.orset = next;
    fieldNotes.trackChange("orset", client.el, true, () => render(client));
    submit(clientId, { ddsId: "orset", op });
  }

  function localGSetAdd(clientId: ClientId, element: string): void {
    const client = clients[clientId];
    const [next, _events, op] = gSetKernel.add(client.gset, element);
    client.gset = next;
    fieldNotes.trackChange("gset", client.el, true, () => render(client));
    submit(clientId, { ddsId: "gset", op });
  }

  function localTwoPSetAdd(clientId: ClientId, element: string): void {
    const client = clients[clientId];
    const [next, _events, op] = twoPSetKernel.add(client.twopset, element);
    client.twopset = next;
    fieldNotes.trackChange("twopset", client.el, true, () => render(client));
    submit(clientId, { ddsId: "twopset", op });
  }

  function localTwoPSetRemove(clientId: ClientId, element: string): void {
    const client = clients[clientId];
    const [next, _events, op] = twoPSetKernel.remove(client.twopset, element);
    client.twopset = next;
    fieldNotes.trackChange("twopset", client.el, true, () => render(client));
    submit(clientId, { ddsId: "twopset", op });
  }

  function localClaim(clientId: ClientId, key: string): void {
    const client = clients[clientId];
    const result = claimsKernel.claim_once(
      client.claims,
      key,
      json.string(CLAIMANTS[clientId]),
      client.lastSeq,
    );
    const submitted = resultValue(result);
    if (submitted === null) {
      // AlreadyPendingLocally — unreachable while the button disables itself.
      console.error("unexpected claim refusal", resultError(result));
      return;
    }
    if (submitted instanceof claimsKernel.AlreadyClaimed) {
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
    client.claims = submitted.state;
    // Non-optimistic: the holder does not change here, so this flashes nothing
    // on the origin; the ink flash lands only when the winner is sequenced.
    fieldNotes.trackChange("claims", client.el, true, () => render(client));
    submit(clientId, { ddsId: "claims", op: submitted.operation });
  }

  function localRegisterWrite(clientId: ClientId, key: string): void {
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
    submit(clientId, { ddsId: "registers", op });
  }

  function localOrderedAdd(clientId: ClientId): void {
    const client = clients[clientId];
    const value = ORDERED_ADDS[orderedAddSerial % ORDERED_ADDS.length];
    orderedAddSerial += 1;
    const op = orderedKernel.add(client.ordered, json.string(value));
    orderedPending[clientId].add(describeOrderedPending(op));
    orderedNotes[clientId] = "add filed";
    fieldNotes.trackChange("ordered", client.el, true, () => render(client));
    submit(clientId, { ddsId: "ordered", op });
  }

  function localOrderedAcquire(clientId: ClientId): void {
    const client = clients[clientId];
    orderedAcquireSerial += 1;
    const op = orderedKernel.acquire(`${clientId}${orderedAcquireSerial}`);
    orderedPending[clientId].add(describeOrderedPending(op));
    orderedNotes[clientId] = "acquire filed";
    fieldNotes.trackChange("ordered", client.el, true, () => render(client));
    submit(clientId, { ddsId: "ordered", op });
  }

  function localOrderedComplete(clientId: ClientId): void {
    const client = clients[clientId];
    const job = firstOwnedOrderedJob(client);
    if (!job) return;
    const op = orderedKernel.complete(job.id);
    orderedPending[clientId].add(describeOrderedPending(op));
    orderedNotes[clientId] = "complete filed";
    fieldNotes.trackChange("ordered", client.el, true, () => render(client));
    submit(clientId, { ddsId: "ordered", op });
  }

  function localOrderedRelease(clientId: ClientId): void {
    const client = clients[clientId];
    const job = firstOwnedOrderedJob(client);
    if (!job) return;
    const op = orderedKernel.release(job.id);
    orderedPending[clientId].add(describeOrderedPending(op));
    orderedNotes[clientId] = "release filed";
    fieldNotes.trackChange("ordered", client.el, true, () => render(client));
    submit(clientId, { ddsId: "ordered", op });
  }

  function localTaskVolunteer(clientId: ClientId, taskId: string): void {
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
    const operation = optionValue(maybeOp);
    if (operation !== null) {
      submit(clientId, {
        ddsId: "tasks",
        op: { op: operation, messageId },
      });
    }
  }

  function localTaskAbandon(clientId: ClientId, taskId: string): void {
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
    const operation = optionValue(maybeOp);
    if (operation !== null) {
      submit(clientId, {
        ddsId: "tasks",
        op: { op: operation, messageId },
      });
    }
  }

  function localTaskComplete(clientId: ClientId, taskId: string): void {
    const client = clients[clientId];
    const messageId = ++taskMessageSerial;
    const result = taskManagerKernel.complete(
      client.taskmanager,
      taskId,
      CLIENT_NUMBERS[clientId],
      messageId,
    );
    const completed = resultValue(result);
    if (completed === null) {
      taskNotes[clientId][taskId] = "not assigned here";
      render(client);
      return;
    }
    const [next, op] = completed;
    client.taskmanager = next;
    taskNotes[clientId][taskId] = "complete filed";
    fieldNotes.trackChange("tasks", client.el, true, () => render(client));
    submit(clientId, {
      ddsId: "tasks",
      op: { op, messageId },
    });
  }

  function localPactSet(clientId: ClientId, key: string): void {
    const client = clients[clientId];
    const op = pactKernel.set(
      client.pact,
      key,
      some(json.string(PACT_VALUES[clientId])),
      client.lastSeq,
    );
    const operation = resultValue(op);
    if (operation === null) {
      pactNotes[clientId][key] = "pending pact blocks new proposal";
      render(client);
      return;
    }
    pactPending[clientId].add(key);
    pactNotes[clientId][key] = "proposal filed";
    // Non-optimistic: pending/accepted print only when sequenced (ink).
    fieldNotes.trackChange("pact", client.el, true, () => render(client));
    submit(clientId, { ddsId: "pact", op: operation });
  }

  function localPactDelete(clientId: ClientId, key: string): void {
    const client = clients[clientId];
    const op = pactKernel.delete$(client.pact, key, client.lastSeq);
    const operation = resultValue(op);
    if (operation === null) {
      pactNotes[clientId][key] = "nothing accepted to delete";
      render(client);
      return;
    }
    pactPending[clientId].add(key);
    pactNotes[clientId][key] = "delete filed";
    // Non-optimistic: pending/accepted print only when sequenced (ink).
    fieldNotes.trackChange("pact", client.el, true, () => render(client));
    submit(clientId, { ddsId: "pact", op: operation });
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

  function resetOrdered(items: readonly string[] = ORDERED_BASELINE): void {
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
    const baseline = new Set<string>(ORSET_BASELINE);
    for (const element of MARKERS) {
      const shouldBePresent = baseline.has(element);
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
    const drift = gCounterKernel.value(clients.a.gcounter) - GCOUNTER_BASE;
    if (drift < 0) {
      localGCounterIncrement("a", 0 - drift);
    }
  }

  function resetLwwRegister() {
    lwwRegisterEpoch += 1;
    lastLwwRegister = null;
    const baseline = lwwRegisterBaselineSummary();
    for (const client of Object.values(clients)) {
      client["lww-register"] = lwwRegisterFromBaseline(
        baseline,
        client.id,
        lwwRegisterEpoch,
      );
      render(client);
    }
    replayBtn.disabled = true;
    renderStatus();
  }

  function resetLwwMap() {
    lwwMapEpoch += 1;
    lastLwwMap = null;
    for (const client of Object.values(clients)) {
      client["lww-map"] = lwwMapFromSummary(lwwMapBaseline, client.id, lwwMapEpoch);
      render(client);
    }
    replayBtn.disabled = true;
    renderStatus();
  }

  function resetMv() {
    mvEpoch += 1;
    lastMv = null;
    const baseline = mvBaselineSummary(mvEpoch);
    for (const client of Object.values(clients)) {
      client["mv-register"] = mvFromBaseline(baseline, client.id, mvEpoch);
      render(client);
    }
    replayBtn.disabled = true;
    renderStatus();
  }

  function resetOrMap() {
    orMapEpoch += 1;
    lastOrMap = null;
    orMapRaceRunning = false;
    for (const client of Object.values(clients)) {
      const writer = replicaId.new$(`client-${client.id}-ormap-${orMapEpoch}`);
      if (orMapMode === "set") {
        client.ormap = orMapKernel.new$(writer, new orMapKernel.OrSetMode());
      } else {
        const loaded = orMapKernel.from_summary(orMapBaseline, writer);
        client.ormap = expectOk(
          loaded,
          "OR-map tally baseline failed to load",
        );
      }
      render(client);
    }
    if (orMapRaceStatus) orMapRaceStatus.textContent = "Fresh OR-map replicas. Ready to run.";
    applyActiveView();
  }

  async function runOrMapSetRace(): Promise<void> {
    const raceSelect = orMapRaceSelect;
    const raceStatus = orMapRaceStatus;
    if (raceSelect === null || raceStatus === null) {
      throw new Error("OR-map race controls are missing");
    }
    resetOrMap();
    const epoch = orMapEpoch;
    const scenarioValue = raceSelect.value;
    if (!isOrMapScenario(scenarioValue)) {
      throw new Error(`Unknown OR-map scenario: ${scenarioValue}`);
    }
    const scenario = scenarioValue;
    orMapRaceRunning = true;
    raceStatus.textContent =
      "Running: setup and edits travel through the sequencer.";
    for (const client of Object.values(clients)) render(client);
    renderStatus();
    const key = "inspection-brief";
    const add = (id: ClientId, member: string) =>
      localOrMapAddMember(id, key, member);
    const remove = (id: ClientId, member: string) =>
      localOrMapRemoveMember(id, key, member);
    if (scenario === "union") {
      await Promise.all([add("a", "draft"), add("b", "reviewed")]);
    } else {
      await add("a", "draft");
      if (epoch !== orMapEpoch) return;
      if (scenario === "member") {
        await Promise.all([remove("a", "draft"), add("b", "draft")]);
      } else if (scenario === "key") {
        await Promise.all([localOrMapStrike("a", key), add("b", "reviewed")]);
      } else if (scenario === "readd") {
        await localOrMapStrike("a", key);
        if (epoch !== orMapEpoch) return;
        await add("b", "handoff");
        if (epoch !== orMapEpoch) return;
        await redeliverLastDelta("ormap");
      } else if (scenario === "empty") {
        await remove("a", "draft");
        if (epoch !== orMapEpoch) return;
        await Promise.all([
          remove("a", "absent"),
          localOrMapRemoveMember("b", "pump-watch", "absent"),
        ]);
      }
    }
    if (epoch !== orMapEpoch) return;
    orMapRaceRunning = false;
    raceStatus.textContent =
      "Complete. All three clients received the operations; try another edit.";
    for (const client of Object.values(clients)) render(client);
    renderStatus();
  }

  function resetOrMapMv() {
    orMapMvEpoch += 1;
    lastOrMapMv = null;
    const baseline = orMapMvBaselineSummary(orMapMvEpoch);
    for (const client of Object.values(clients)) {
      client["or-map-mv-register"] = orMapMvFromBaseline(baseline, client.id, orMapMvEpoch);
      render(client);
    }
    replayBtn.disabled = true;
    renderStatus();
  }

  function resetTwoPSet() {
    twoPSetEpoch += 1;
    lastTwoPSet = null;
    const baseline = twoPSetBaselineSummary();
    for (const client of Object.values(clients)) {
      const loaded = twoPSetKernel.from_summary(baseline);
      client.twopset = expectOk(
        loaded,
        "2P-set reset summary failed to load",
      );
      render(client);
    }
    if (activeDds === "twopset") replayBtn.disabled = true;
    renderStatus();
  }

  // The sequencer re-sends an already-sequenced delta to every replica. No
  // new SN is stamped — this is duplicate delivery, the failure mode resends
  // and stash replays produce — and the lattice absorbs it: merge is
  // idempotent, so nothing changes anywhere.
  function redeliverLastDelta(ddsId: DdsId = activeDds): Promise<void> {
    let replay: { operation: ReplayOperationEnvelope; sn: number } | null =
      null;
    if (ddsId === "or-map-mv-register" && lastOrMapMv) {
      replay = {
        operation: { ddsId, op: lastOrMapMv.op },
        sn: lastOrMapMv.sn,
      };
    } else if (ddsId === "lww-map" && lastLwwMap) {
      replay = { operation: { ddsId, op: lastLwwMap.op }, sn: lastLwwMap.sn };
    } else if (ddsId === "lww-register" && lastLwwRegister) {
      replay = {
        operation: { ddsId, op: lastLwwRegister.op },
        sn: lastLwwRegister.sn,
      };
    } else if (ddsId === "mv-register" && lastMv) {
      replay = { operation: { ddsId, op: lastMv.op }, sn: lastMv.sn };
    } else if (ddsId === "ormap" && lastOrMap) {
      replay = { operation: { ddsId, op: lastOrMap.op }, sn: lastOrMap.sn };
    } else if (ddsId === "orset" && lastOrSet) {
      replay = { operation: { ddsId, op: lastOrSet.op }, sn: lastOrSet.sn };
    } else if (ddsId === "gset" && lastGSet) {
      replay = { operation: { ddsId, op: lastGSet.op }, sn: lastGSet.sn };
    } else if (ddsId === "gcounter" && lastGCounter) {
      replay = {
        operation: { ddsId, op: lastGCounter.op },
        sn: lastGCounter.sn,
      };
    } else if (ddsId === "twopset" && lastTwoPSet) {
      replay = {
        operation: { ddsId, op: lastTwoPSet.op },
        sn: lastTwoPSet.sn,
      };
    } else if (ddsId === "pn" && lastPn) {
      replay = { operation: { ddsId, op: lastPn.op }, sn: lastPn.sn };
    }
    if (replay === null) return Promise.resolve();
    const { operation, sn: originalSn } = replay;
    const li = document.createElement("li");
    li.className = "replay";
    li.textContent = `#${String(originalSn).padStart(2, "0")} again ${describeOp(operation)} · absorbed`;
    opLog.push(li);
    if (fieldNotes.active && ddsId === activeDds && FIELD_FLASH.has(ddsId)) {
      fieldNotes.flashLog();
    }

    const delivered = new Promise<void>((resolve) => {
      let remaining = Object.keys(clients).length;
      sequencer.broadcast({
        label: describeOp(operation),
        isStale: () => {
          if (operation.ddsId === "or-map-mv-register") {
            return operation.op.epoch !== orMapMvEpoch;
          }
          if (operation.ddsId === "lww-map") {
            return operation.op.epoch !== lwwMapEpoch;
          }
          if (operation.ddsId === "lww-register") {
            return operation.op.epoch !== lwwRegisterEpoch;
          }
          if (operation.ddsId === "mv-register") {
            return operation.op.epoch !== mvEpoch;
          }
          return operation.ddsId === "ormap"
            && operation.op.epoch !== orMapEpoch;
        },
        onDeliver: (target) => {
          // Every replica takes duplicates through apply_remote, including
          // the origin whose acknowledged delta is already merged.
          if (operation.ddsId === "or-map-mv-register") {
            const result = orMapKernel.apply_remote(
              target[operation.ddsId],
              operation.op.operation,
            );
            [target[operation.ddsId]] = expectOk(
              result,
              "Unexpected duplicate OR-map MV-register op",
            );
          } else if (operation.ddsId === "lww-map") {
            const result = lwwMapKernel.apply_remote(
              target["lww-map"],
              operation.op.operation,
            );
            [target["lww-map"]] = expectOk(
              result,
              "Unexpected duplicate LWWMap op",
            );
          } else if (operation.ddsId === "lww-register") {
            const result = lwwRegisterKernel.apply_remote(
              target["lww-register"],
              operation.op.operation,
            );
            [target["lww-register"]] = expectOk(
              result,
              "Unexpected duplicate LWW-register op",
            );
          } else if (operation.ddsId === "mv-register") {
            [target["mv-register"]] = mvKernel.apply_remote(
              target["mv-register"],
              operation.op.operation,
            );
          } else if (operation.ddsId === "ormap") {
            const result = orMapKernel.apply_remote(
              target.ormap,
              operation.op.operation,
            );
            [target.ormap] = expectOk(
              result,
              "Unexpected duplicate OR-map operation",
            );
          } else if (operation.ddsId === "orset") {
            const [next] = orSetKernel.apply_remote(target.orset, operation.op);
            target.orset = next;
          } else if (operation.ddsId === "gset") {
            const [next] = gSetKernel.apply_remote(target.gset, operation.op);
            target.gset = next;
          } else if (operation.ddsId === "gcounter") {
            const [next] = gCounterKernel.apply_remote(
              target.gcounter,
              operation.op,
            );
            target.gcounter = next;
          } else if (operation.ddsId === "twopset") {
            const [next] = twoPSetKernel.apply_remote(
              target.twopset,
              operation.op,
            );
            target.twopset = next;
          } else {
            const [next] = pnKernel.apply_remote(target.pn, operation.op);
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
          if (--remaining === 0) resolve();
        },
      });
    });
    renderStatus();
    return delivered;
  }

  // ── wiring ────────────────────────────────────────────────────────────────

  for (const client of Object.values(clients)) {
    const memberInput = required<HTMLInputElement>(
      client.el,
      "[data-ormap-set-input]",
    );
    const memberKey = required<HTMLInputElement>(
      client.el,
      "[data-ormap-key]",
    );
    const orMapMvKey = required<HTMLInputElement>(
      client.el,
      "[data-or-map-mv-register-key]",
    );
    const orMapMvInput = required<HTMLInputElement>(
      client.el,
      "[data-or-map-mv-register-input]",
    );
    const lwwMapKey = required<HTMLInputElement>(
      client.el,
      "[data-lww-map-key]",
    );
    const lwwMapInput = required<HTMLInputElement>(
      client.el,
      "[data-lww-map-input]",
    );
    const lwwRegisterInput = required<HTMLInputElement>(
      client.el,
      "[data-lww-register-input]",
    );
    const mvRegisterInput = required<HTMLInputElement>(
      client.el,
      "[data-mv-register-input]",
    );
    memberInput.addEventListener("keydown", (event) => {
      if (event.key === "Enter") {
        event.preventDefault();
        hasInteracted = true;
        void localOrMapAddMember(client.id, memberKey.value, memberInput.value);
      }
    });
    orMapMvKey.addEventListener("input", () => {
      renderOrMapMv(client);
    });
    for (
      const input of client.el.querySelectorAll<HTMLInputElement>(
        "[data-or-map-mv-register-key], [data-or-map-mv-register-input]",
      )
    ) {
      input.addEventListener("keydown", (event) => {
        if (event.key !== "Enter") return;
        event.preventDefault();
        hasInteracted = true;
        localOrMapMvEdit(
          client.id,
          orMapMvKey.value,
          orMapMvInput.value,
        );
      });
    }
    for (
      const input of client.el.querySelectorAll<HTMLInputElement>(
        "[data-lww-map-key], [data-lww-map-input]",
      )
    ) {
      input.addEventListener("keydown", (event) => {
        if (event.key !== "Enter") return;
        event.preventDefault();
        hasInteracted = true;
        localLwwMapEdit(
          client.id,
          lwwMapKey.value,
          lwwMapInput.value,
        );
      });
    }
    lwwRegisterInput.addEventListener("keydown", (event) => {
      if (event.key === "Enter") {
        event.preventDefault();
        hasInteracted = true;
        localLwwSet(client.id, lwwRegisterInput.value);
      }
    });
    mvRegisterInput.addEventListener("keydown", (event) => {
      if (event.key === "Enter") {
        event.preventDefault();
        hasInteracted = true;
        localMvSet(client.id, mvRegisterInput.value);
      }
    });
    client.el.addEventListener("click", (event) => {
      if (!(event.target instanceof Element)) return;
      const target = event.target;
      if (target.closest("[data-or-map-mv-register-write], [data-or-map-mv-register-resolve], [data-or-map-mv-register-remove]")) {
        hasInteracted = true;
        const value = target.closest("[data-or-map-mv-register-remove]")
          ? null
          : target.closest("[data-or-map-mv-register-resolve]")
            ? selectedOrMapMvValues(client).reverse().join(" + ")
            : orMapMvInput.value;
        localOrMapMvEdit(client.id, orMapMvKey.value, value);
        return;
      }
      if (target.closest("[data-lww-map-write], [data-lww-map-remove]")) {
        hasInteracted = true;
        localLwwMapEdit(
          client.id,
          lwwMapKey.value,
          target.closest("[data-lww-map-remove]") ? null : lwwMapInput.value,
        );
        return;
      }
      if (target.closest("[data-lww-register-write]")) {
        hasInteracted = true;
        localLwwSet(client.id, lwwRegisterInput.value);
        return;
      }
      if (target.closest("[data-mv-register-write], [data-mv-register-resolve]")) {
        hasInteracted = true;
        const value = target.closest("[data-mv-register-resolve]")
          ? "raise crest + arm pump"
          : mvRegisterInput.value;
        localMvSet(client.id, value);
        return;
      }
      const stepBtn = target.closest<HTMLButtonElement>("button[data-step]");
      if (stepBtn) {
        hasInteracted = true;
        const key = rowKey(stepBtn);
        const current = readInt(mapKernel.get(client.map, key)) ?? 0;
        // River gauges don't read below zero; renderMap disables "−" at 0.
        const next = Math.max(0, current + Number(stepBtn.dataset.step));
        if (next !== current) localSet(client.id, key, next);
        return;
      }
      const incBtn = target.closest<HTMLButtonElement>("button[data-inc]");
      if (incBtn) {
        hasInteracted = true;
        localIncrement(client.id, Number(incBtn.dataset.inc));
        return;
      }
      const gCounterIncBtn = target.closest<HTMLButtonElement>(
        "button[data-gcounter-inc]",
      );
      if (gCounterIncBtn) {
        hasInteracted = true;
        localGCounterIncrement(
          client.id,
          Number(gCounterIncBtn.dataset.gcounterInc),
        );
        return;
      }
      const pnBtn = target.closest<HTMLButtonElement>("button[data-pn-inc]");
      if (pnBtn) {
        hasInteracted = true;
        localPnUpdate(client.id, Number(pnBtn.dataset.pnInc));
        return;
      }
      const claimBtn = target.closest<HTMLButtonElement>("button[data-claim]");
      if (claimBtn) {
        hasInteracted = true;
        localClaim(client.id, rowKey(claimBtn));
        return;
      }
      const registerBtn = target.closest<HTMLButtonElement>(
        "button[data-register-write]",
      );
      if (registerBtn) {
        hasInteracted = true;
        localRegisterWrite(
          client.id,
          rowKey(registerBtn),
        );
        return;
      }
      const orderedAddBtn = target.closest<HTMLButtonElement>(
        "button[data-ordered-add]",
      );
      if (orderedAddBtn) {
        hasInteracted = true;
        localOrderedAdd(client.id);
        return;
      }
      const orderedAcquireBtn = target.closest<HTMLButtonElement>(
        "button[data-ordered-acquire]",
      );
      if (orderedAcquireBtn) {
        hasInteracted = true;
        localOrderedAcquire(client.id);
        return;
      }
      const orderedCompleteBtn = target.closest<HTMLButtonElement>(
        "button[data-ordered-complete]",
      );
      if (orderedCompleteBtn) {
        hasInteracted = true;
        localOrderedComplete(client.id);
        return;
      }
      const orderedReleaseBtn = target.closest<HTMLButtonElement>(
        "button[data-ordered-release]",
      );
      if (orderedReleaseBtn) {
        hasInteracted = true;
        localOrderedRelease(client.id);
        return;
      }
      const taskVolunteerBtn = target.closest<HTMLButtonElement>(
        "button[data-task-volunteer]",
      );
      if (taskVolunteerBtn) {
        hasInteracted = true;
        localTaskVolunteer(client.id, rowKey(taskVolunteerBtn));
        return;
      }
      const taskAbandonBtn = target.closest<HTMLButtonElement>(
        "button[data-task-abandon]",
      );
      if (taskAbandonBtn) {
        hasInteracted = true;
        localTaskAbandon(client.id, rowKey(taskAbandonBtn));
        return;
      }
      const taskCompleteBtn = target.closest<HTMLButtonElement>(
        "button[data-task-complete]",
      );
      if (taskCompleteBtn) {
        hasInteracted = true;
        localTaskComplete(client.id, rowKey(taskCompleteBtn));
        return;
      }
      const pactSetBtn = target.closest<HTMLButtonElement>(
        "button[data-pact-set]",
      );
      if (pactSetBtn) {
        hasInteracted = true;
        localPactSet(client.id, rowKey(pactSetBtn));
        return;
      }
      const pactDeleteBtn = target.closest<HTMLButtonElement>(
        "button[data-pact-delete]",
      );
      if (pactDeleteBtn) {
        hasInteracted = true;
        localPactDelete(client.id, rowKey(pactDeleteBtn));
        return;
      }
      const orMapLogBtn = target.closest<HTMLButtonElement>(
        "button[data-ormap-log]",
      );
      if (orMapLogBtn) {
        hasInteracted = true;
        localOrMapLog(
          client.id,
          rowKey(orMapLogBtn),
          Number(orMapLogBtn.dataset.ormapLog),
        );
        return;
      }
      const memberButton = target.closest<HTMLElement>(
        "[data-ormap-set-add], [data-ormap-set-remove], [data-ormap-remove-key]",
      );
      if (memberButton) {
        hasInteracted = true;
        if (memberButton.hasAttribute("data-ormap-remove-key")) {
          localOrMapStrike(client.id, memberKey.value);
        } else {
          if (memberButton.hasAttribute("data-ormap-set-add")) {
            void localOrMapAddMember(
              client.id,
              memberKey.value,
              memberInput.value,
            );
          } else {
            void localOrMapRemoveMember(
              client.id,
              memberKey.value,
              memberInput.value,
            );
          }
        }
        return;
      }
      const orMapStrikeBtn = target.closest<HTMLButtonElement>(
        "button[data-ormap-strike]",
      );
      if (orMapStrikeBtn) {
        hasInteracted = true;
        localOrMapStrike(client.id, rowKey(orMapStrikeBtn));
        return;
      }
      const orMapReopenBtn = target.closest<HTMLButtonElement>(
        "button[data-ormap-reopen]",
      );
      if (orMapReopenBtn) {
        hasInteracted = true;
        localOrMapReopen(client.id, rowKey(orMapReopenBtn));
        return;
      }
      const orSetAddBtn = target.closest<HTMLButtonElement>(
        "button[data-orset-add]",
      );
      if (orSetAddBtn) {
        hasInteracted = true;
        localOrSetAdd(client.id, rowKey(orSetAddBtn));
        return;
      }
      const orSetRemoveBtn = target.closest<HTMLButtonElement>(
        "button[data-orset-remove]",
      );
      if (orSetRemoveBtn) {
        hasInteracted = true;
        localOrSetRemove(client.id, rowKey(orSetRemoveBtn));
        return;
      }
      const gSetAddBtn = target.closest<HTMLButtonElement>(
        "button[data-gset-add]",
      );
      if (gSetAddBtn) {
        hasInteracted = true;
        localGSetAdd(client.id, rowKey(gSetAddBtn));
        return;
      }
      const twoPSetAddBtn = target.closest<HTMLButtonElement>(
        "button[data-twopset-add]",
      );
      if (twoPSetAddBtn) {
        hasInteracted = true;
        localTwoPSetAdd(client.id, rowKey(twoPSetAddBtn));
        return;
      }
      const twoPSetRemoveBtn = target.closest<HTMLButtonElement>(
        "button[data-twopset-remove]",
      );
      if (twoPSetRemoveBtn) {
        hasInteracted = true;
        localTwoPSetRemove(client.id, rowKey(twoPSetRemoveBtn));
      }
    });
  }

  const RACE_LABELS = {
    "or-map-mv-register": "Race two gate revisions",
    "lww-map": "Race two gate settings",
    "lww-register": "Race two equal-time notes",
    "mv-register": "Race two revisions",
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
    "or-map-mv-register": "Reload all MV-register OR-maps from the baseline and discard pending edits",
    "lww-map": "Reload all LWW maps from the baseline and discard pending edits",
    "lww-register": "Reload all LWW registers from the surveyed baseline and discard pending notes",
    "mv-register": "Reload all MV registers from a fresh baseline and discard pending revisions",
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
    rig.dataset.ormapValueMode = orMapMode;
    if (orMapViewSelect) {
      required<HTMLElement>(
        document,
        "[data-ormap-view-controls]",
      ).hidden = activeDds !== "ormap" && activeDds !== "or-map-mv-register";
      orMapViewSelect.value = activeDds === "or-map-mv-register" ? activeDds : "ormap";
    }
    for (const pick of ddsPicks) pick.checked = pick.value === activeDds;
    const setMode = orMapMode === "set";
    const orMapControls =
      document.querySelector<HTMLElement>("[data-ormap-controls]");
    if (orMapControls) orMapControls.hidden = activeDds !== "ormap";
    required<HTMLElement>(document, "[data-ormap-tally-note]").hidden = setMode;
    required<HTMLElement>(document, "[data-ormap-set-note]").hidden = !setMode;
    if (orMapRaceSelect) {
      required<HTMLElement>(document, "[data-ormap-scenarios]").hidden =
        !setMode;
    }
    for (const rule of mergeRules) {
      rule.hidden = rule.dataset.mergeRule !== activeDds;
    }
    raceBtn.textContent = RACE_LABELS[activeDds];
    raceBtn.disabled = false;
    resetBtn.setAttribute("aria-label", RESET_LABELS[activeDds]);
    replayBtn.hidden = ![
        "or-map-mv-register",
        "lww-map",
        "lww-register",
        "mv-register",
        "gcounter",
        "pn",
        "ormap",
        "orset",
        "gset",
        "twopset",
      ].includes(activeDds);
    replayBtn.disabled =
        activeDds === "or-map-mv-register"
          ? !lastOrMapMv
        : activeDds === "lww-map"
          ? !lastLwwMap
        : activeDds === "lww-register"
          ? !lastLwwRegister
        : activeDds === "mv-register"
          ? !lastMv
        : activeDds === "gcounter"
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
    const replayOldAdd = activeDds === "ormap" && setMode;
    replayBtn.textContent = replayOldAdd
      ? "Re-deliver first add"
      : "Re-deliver last delta";
    replayBtn.setAttribute("aria-label", replayOldAdd
      ? "Deliver the first sequenced member addition again to every replica"
      : "Deliver the saved sequenced delta again to every replica");
    if (activeDds === "ormap" && setMode) {
      raceBtn.textContent = "Run set scenario";
      resetBtn.setAttribute("aria-label", "Start fresh OR-map set replicas and discard pending set edits");
    }
    renderBadge(clients.a);
    renderBadge(clients.b);
    renderBadge(clients.c);
    fieldNotes.render(activeDds);
    renderStatus();
  }

  const fieldNotes = createFieldNotes({
    rig,
    prefersReducedMotion: () => reducedMotion.matches,
    duration: controls.paced,
  });

  orMapViewSelect?.addEventListener("change", () => {
    hasInteracted = true;
    const value = orMapViewSelect.value;
    if (!isDdsId(value)) throw new Error(`Unknown structure view: ${value}`);
    activeDds = value;
    applyActiveView();
  });

  orMapModeSelect?.addEventListener("change", () => {
    hasInteracted = true;
    const value = orMapModeSelect.value;
    if (!isOrMapMode(value)) throw new Error(`Unknown OR-map mode: ${value}`);
    orMapMode = value;
    resetOrMap();
  });

  for (const pick of ddsPicks) {
    pick.addEventListener("change", () => {
      if (!pick.checked) return;
      hasInteracted = true;
      if (!isDdsId(pick.value)) {
        throw new Error(`Unknown structure view: ${pick.value}`);
      }
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
  let reflowTimer: ReturnType<typeof setTimeout> | null = null;
  window.addEventListener("resize", () => {
    if (!fieldNotes.active) return;
    if (reflowTimer !== null) clearTimeout(reflowTimer);
    reflowTimer = setTimeout(() => fieldNotes.reflow(), 150);
  });

  raceBtn.addEventListener("click", () => {
    hasInteracted = true;
    if (activeDds === "or-map-mv-register") {
      localOrMapMvEdit("a", "gate-mode", "raise crest");
      localOrMapMvEdit("b", "gate-mode", "arm pump");
    } else if (activeDds === "lww-map") {
      // Issued clocks include pending edits and retained tombstones, on every client.
      const timestamp = Math.max(Date.now(), ...Object.values(clients).map((client) => {
        const seen = gdict.get<string, number>(
          client["lww-map"].last_seen,
          "gate-mode",
        );
        return (resultValue(seen) ?? 0) + 1;
      }));
      if (!Number.isSafeInteger(timestamp + 1)) throw new Error("LWWMap race clock exhausted");
      const race = required<HTMLSelectElement>(
        document,
        "[data-lww-map-race]",
      ).value;
      localLwwMapEdit("a", "gate-mode", race === "remove-tie" ? null : "open",
        timestamp + (race === "timestamp" ? 1 : 0));
      localLwwMapEdit("b", "gate-mode", race === "remove-tie" ? "open" : "closed", timestamp);
    } else if (activeDds === "lww-register") {
      const timestamp = lwwRaceTimestamp(Date.now(), [
        clients.a["lww-register"],
        clients.b["lww-register"],
      ]);
      localLwwSet("a", "raise crest", timestamp);
      localLwwSet("b", "arm pump", timestamp);
    } else if (activeDds === "mv-register") {
      localMvSet("a", "raise crest");
      localMvSet("b", "arm pump");
    } else if (activeDds === "map") {
      // Both clients write the same key inside one latency window. The op the
      // server sequences last wins on every replica — that's LWW, and both
      // replicas agree because they apply ops in the same order.
      const key = GAUGES[Math.floor(Math.random() * GAUGES.length)];
      const base = readInt(mapKernel.get(clients.a.map, key)) ?? 0;
      localSet("a", key, base + 10);
      localSet("b", key, Math.max(0, base - 10));
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
      if (orMapMode === "set") {
        void runOrMapSetRace();
        return;
      }
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
      (activeDds === "or-map-mv-register" && lastOrMapMv) ||
      (activeDds === "lww-map" && lastLwwMap) ||
      (activeDds === "lww-register" && lastLwwRegister) ||
      (activeDds === "mv-register" && lastMv) ||
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
    // Timestamped structures reload a fresh survey rather than pruning history.
    if (activeDds === "or-map-mv-register") {
      resetOrMapMv();
    } else if (activeDds === "lww-map") {
      resetLwwMap();
    } else if (activeDds === "lww-register") {
      resetLwwRegister();
    } else if (activeDds === "mv-register") {
      resetMv();
    } else if (activeDds === "map") {
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
      if (orMapMode === "set") {
        resetOrMap();
        return;
      }
      for (const [key, base] of ORMAP_BASELINE) {
        if (!orMapEntries(clients.a.ormap).has(key)) {
          localOrMapReopen("a", key);
        }
        const value = orMapEntries(clients.a.ormap).get(key) ?? 0;
        if (typeof value !== "number") {
          throw new Error("OR-map tally view received a non-tally value");
        }
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
  // waiting to be discovered. Under reduced motion it still runs — dotless
  // and without the reveal delay — so the visitor arrives to SN 1 and a
  // populated op log instead of an inert rig. Skipped once the visitor has
  // already interacted.
  if (
    activeDds === "map" &&
    present.has("map") &&
    "IntersectionObserver" in window
  ) {
    const io = new IntersectionObserver(
      (entries) => {
        if (!entries.some((entry) => entry.isIntersecting)) return;
        io.disconnect();
        setTimeout(
          () => {
            if (hasInteracted) return;
            const current =
              readInt(mapKernel.get(clients.b.map, "kettle-run")) ?? 0;
            localSet("b", "kettle-run", current + 1);
          },
          reducedMotion.matches ? 0 : controls.paced(600),
        );
      },
      { threshold: 0.45 },
    );
    io.observe(rig);
  }

  // Cut-link: sever Client B from the sequencer, keep editing, restore, and
  // watch catch-up + resubmit converge — the reconnect story, witnessed live.
  if (cutLinkBtn) {
    cutLinkBtn.addEventListener("click", () => {
      hasInteracted = true;
      linkUp = !linkUp;
      clients.b.el.classList.toggle("link-cut", !linkUp);
      cutLinkBtn.textContent = linkUp ? "Cut link" : "Restore link";
      cutLinkBtn.setAttribute("aria-pressed", String(!linkUp));
      if (linkNote instanceof HTMLElement) linkNote.hidden = linkUp;
      const li = document.createElement("li");
      li.className = "replay";
      if (!linkUp) {
        li.textContent = "link cut — Client B off the wire";
      } else {
        // Reconnect discipline: deliver the sequenced ops B missed first,
        // then resubmit what B authored offline — the runtime's own order.
        const hops = heldHops.splice(0);
        for (const hop of hops) hop();
        const subs = heldSubmits.splice(0);
        for (const sub of subs) sub();
        li.textContent = `link restored — caught up ${hops.length}, resubmitted ${subs.length}`;
      }
      opLog.push(li);
      renderStatus();
    });
  }

  render(clients.a);
  render(clients.b);
  render(clients.c);
  renderStatus();
}
