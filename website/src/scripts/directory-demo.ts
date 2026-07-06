// Live SharedDirectory convergence demo. Two browser "clients" each own real
// watershed state — a `directory_kernel` (a recursive SharedMap: every folder
// node has its own key/value store plus named child folders), compiled with
// `gleam build --target javascript`. They talk through the same in-page
// sequencer the other demos use: a client edits its tree optimistically, the
// sequencer stamps a global sequence number (SN) and broadcasts in FIFO order,
// and every replica converges — including the tricky case where both clients
// create a folder of the same name at the same instant.
//
// The kernel is driven directly (not through the OTP actor): a local edit
// returns the op plus the kernel `message_id` that is the op's client-sequence
// identity; on delivery the author acks it and every other replica applies it
// remotely with a `SequencedMeta` carrying author, the server SN, the author's
// reference SN, and that message id. That message id is what lets a remote
// replica run the stale-instance filter and sibling ordering — the same data
// the runtime threads on the wire.
import * as directory from "../../../build/dev/javascript/watershed/watershed/directory_kernel.mjs";
import * as json from "../../../build/dev/javascript/gleam_json/gleam/json.mjs";
import { Some } from "../../../build/dev/javascript/gleam_stdlib/gleam/option.mjs";
import { prefersReducedMotion } from "./demo/timing.ts";
import { createFlowLayer } from "./demo/flow-dots.ts";
import { createLatencyControls } from "./demo/controls.ts";
import { createOpLog } from "./demo/op-log.ts";
import { createSequencer } from "./demo/sequencer.ts";

const CLIENT_IDS = ["a", "b", "c"];
const CLIENT_NUM: Record<string, number> = { a: 0, b: 1, c: 2 };
const CLIENT_LABEL: Record<string, string> = {
  a: "Client A",
  b: "Client B",
  c: "Client C",
};

// Survey-flavoured folder + reading vocabulary each client cycles through, so
// independent creates don't collide by accident (the race button forces one).
const FOLDER_NAMES = [
  "surveys",
  "plans",
  "logs",
  "spoil",
  "borrow-pit",
  "wash-fill",
  "intake",
  "weir",
  "kettle-run",
  "mill-race",
];
const READINGS: Array<[string, string]> = [
  ["BM-17", "recorded"],
  ["grade", "2.1%"],
  ["silt", "high"],
  ["stage", "24"],
  ["flow", "61"],
  ["BM-22", "recorded"],
  ["datum", "set"],
];
const RACE_FOLDER = "kettle-run";

type PendingMark = { mid: number; marker: string };

interface Client {
  id: string;
  num: number;
  state: unknown;
  el: Element;
  lastAppliedSn: number;
  pending: PendingMark[];
  folderCursor: number;
  readingCursor: number;
}

// ── path helpers (match the kernel's absolute-path convention) ───────────────
function join(path: string, name: string): string {
  return path === "/" ? "/" + name : path + "/" + name;
}

function parentOf(path: string): string {
  const at = path.lastIndexOf("/");
  return at <= 0 ? "/" : path.slice(0, at);
}

function baseName(path: string): string {
  return path.slice(path.lastIndexOf("/") + 1);
}

// ── kernel reads ─────────────────────────────────────────────────────────────
function subdirs(client: Client, path: string): string[] {
  return directory.subdirectories(client.state, path).toArray();
}

function entries(client: Client, path: string): Array<[string, string]> {
  return directory
    .entries(client.state, path)
    .toArray()
    .map(([key, value]: [string, unknown]) => [key, unquote(json.to_string(value))]);
}

function unquote(raw: string): string {
  return raw.length >= 2 && raw.startsWith('"') && raw.endsWith('"')
    ? raw.slice(1, -1)
    : raw;
}

// ── convergence oracle: a canonical string of a client's optimistic tree ──────
function canonicalTree(client: Client, path: string): unknown {
  const keys = entries(client, path).sort((a, b) => (a[0] < b[0] ? -1 : 1));
  const children = subdirs(client, path)
    .slice()
    .sort();
  return {
    keys,
    subs: children.map((name) => [name, canonicalTree(client, join(path, name))]),
  };
}

export function initDirectoryDemo() {
  const rig = document.querySelector("[data-dir-rig]");
  if (!rig) return;

  const flowLayer = rig.querySelector("[data-flow-layer]");
  const seqNode = rig.querySelector("[data-seq-node]");
  const seqCounter = rig.querySelector("[data-seq-counter]");
  const opLogEl = rig.querySelector("[data-op-log]");
  const statusEl = document.querySelector("[data-dir-status]");
  const latencyInput = document.querySelector("[data-dir-latency]");
  const latencyOut = document.querySelector("[data-dir-latency-out]");
  const paceInput = document.querySelector("[data-dir-pace]");
  const paceOut = document.querySelector("[data-dir-pace-out]");
  const varianceToggle = document.querySelector("[data-dir-latency-variance]");
  const raceBtn = document.querySelector("[data-dir-race]");
  const seedBtn = document.querySelector("[data-dir-seed]");
  const resetBtn = document.querySelector("[data-dir-reset]");

  const section = document.querySelector("#dir-demo");
  for (const el of section.querySelectorAll("button, input")) el.disabled = false;

  const clients: Record<string, Client> = {};
  for (const id of CLIENT_IDS) {
    clients[id] = {
      id,
      num: CLIENT_NUM[id],
      state: directory.new$(),
      el: rig.querySelector(`[data-client="${id}"]`),
      lastAppliedSn: 0,
      pending: [],
      folderCursor: CLIENT_NUM[id], // stagger so A and B pick different names
      readingCursor: CLIENT_NUM[id],
    };
  }

  let epoch = 0;

  const controls = createLatencyControls({
    latencyInput,
    latencyOut,
    paceInput,
    paceOut,
    varianceToggle,
  });
  const flow = createFlowLayer(flowLayer, prefersReducedMotion);
  const opLog = createOpLog(opLogEl, { max: 24 });
  const sequencer = createSequencer({
    clients,
    seqNode,
    flow,
    controls,
    onChange: renderStatus,
  });

  // ── pending bookkeeping ────────────────────────────────────────────────────
  function isPending(client: Client, marker: string): boolean {
    return client.pending.some((p) => p.marker === marker);
  }

  // ── rendering ──────────────────────────────────────────────────────────────
  function render(client: Client) {
    const treeEl = client.el.querySelector("[data-tree]");
    treeEl.replaceChildren(renderNode(client, "/", true));

    const count = client.pending.length;
    const badge = client.el.querySelector("[data-pending-count]");
    badge.textContent = `${count} pending`;
    badge.classList.toggle("is-pending", count > 0);
  }

  function renderNode(client: Client, path: string, isRoot: boolean): Element {
    const node = document.createElement("div");
    node.className = "dir-node";

    const head = document.createElement("div");
    head.className = "dir-head";
    const subPending = !isRoot && isPending(client, "sub:" + path);
    if (subPending) head.classList.add("pending");

    const label = document.createElement("span");
    label.className = "dir-name";
    label.textContent = isRoot ? "/" : baseName(path) + "/";
    head.append(label);

    const actions = document.createElement("span");
    actions.className = "dir-actions";
    actions.append(
      action("+ folder", `Add a folder under ${path} on ${CLIENT_LABEL[client.id]}`, () =>
        localCreate(client.id, path),
      ),
      action("+ reading", `Add a reading in ${path} on ${CLIENT_LABEL[client.id]}`, () =>
        localSet(client.id, path),
      ),
    );
    if (!isRoot) {
      actions.append(
        action("×", `Delete ${path} on ${CLIENT_LABEL[client.id]}`, () =>
          localDelete(client.id, path),
        "dir-del"),
      );
    }
    head.append(actions);
    node.append(head);

    // readings
    const keys = entries(client, path);
    if (keys.length) {
      const dl = document.createElement("ul");
      dl.className = "dir-keys";
      for (const [key, value] of keys) {
        const li = document.createElement("li");
        li.className = "dir-key";
        if (isPending(client, `key:${path}::${key}`)) li.classList.add("pending");
        const k = document.createElement("span");
        k.className = "dk-key";
        k.textContent = key;
        const v = document.createElement("span");
        v.className = "dk-val";
        v.textContent = value;
        li.append(k, v);
        dl.append(li);
      }
      node.append(dl);
    }

    // child folders
    const children = subdirs(client, path);
    if (children.length) {
      const childWrap = document.createElement("div");
      childWrap.className = "dir-children";
      for (const name of children) {
        childWrap.append(renderNode(client, join(path, name), false));
      }
      node.append(childWrap);
    }
    return node;
  }

  function action(
    text: string,
    aria: string,
    onClick: () => void,
    extraClass = "",
  ): HTMLButtonElement {
    const btn = document.createElement("button");
    btn.type = "button";
    btn.className = "node-action" + (extraClass ? " " + extraClass : "");
    btn.textContent = text;
    btn.setAttribute("aria-label", aria);
    btn.addEventListener("click", onClick);
    return btn;
  }

  // ── status ─────────────────────────────────────────────────────────────────
  function converged(): boolean {
    const sigs = CLIENT_IDS.map((id) => JSON.stringify(canonicalTree(clients[id], "/")));
    const identical = sigs.every((s) => s === sigs[0]);
    const anyPending = CLIENT_IDS.some((id) => clients[id].pending.length > 0);
    return identical && !anyPending && sequencer.inFlight === 0;
  }

  function renderStatus() {
    const ok = converged();
    statusEl.innerHTML = ok
      ? '<span class="stamp converged">Converged</span> all trees identical · nothing pending'
      : '<span class="stamp revising">Revising</span> ops in flight';
  }

  function stampSeqCounter(seq: number) {
    seqCounter.textContent = `SN ${seq}`;
    seqCounter.classList.remove("stamped");
    void (seqCounter as HTMLElement).offsetWidth;
    seqCounter.classList.add("stamped");
  }

  function logOp(seq: number, authorId: string, marker: string) {
    const li = document.createElement("li");
    const meta = document.createElement("span");
    meta.className = "op-meta";
    meta.textContent = `SN ${seq} · ${CLIENT_LABEL[authorId].replace("Client ", "")}`;
    const pathEl = document.createElement("span");
    pathEl.className = "op-path";
    pathEl.textContent = markerPath(marker);
    const kindEl = document.createElement("span");
    kindEl.className = "op-kind";
    kindEl.textContent = markerKind(marker);
    li.append(meta, pathEl, kindEl);
    opLog.push(li);
  }

  function markerPath(marker: string): string {
    if (marker.startsWith("sub:")) return marker.slice(4);
    if (marker.startsWith("del:")) return marker.slice(4);
    if (marker.startsWith("key:")) return marker.slice(4).replace("::", " · ");
    return marker;
  }
  function markerKind(marker: string): string {
    if (marker.startsWith("sub:")) return "mkdir";
    if (marker.startsWith("del:")) return "rmdir";
    if (marker.startsWith("key:")) return "set";
    return "";
  }

  // ── protocol: client → sequencer → broadcast ────────────────────────────────
  function sendOp(
    origin: Client,
    op: unknown,
    mid: number,
    author: number,
    refSeq: number,
    marker: string,
  ) {
    sequencer.send({
      originId: origin.id,
      label: markerKind(marker),
      guard: () => {
        const myEpoch = epoch;
        return () => myEpoch !== epoch;
      },
      onSequence: (seq: number) => {
        stampSeqCounter(seq);
        logOp(seq, origin.id, marker);
        return null;
      },
      onDeliver: (target: Client, { seq }: { seq: number }) => {
        deliver(target, op, mid, author, refSeq, seq);
        render(target);
      },
    });
  }

  function deliver(
    target: Client,
    op: unknown,
    mid: number,
    authorNum: number,
    refSeq: number,
    seq: number,
  ) {
    const meta = new directory.SequencedMeta(authorNum, seq, refSeq, mid);
    if (target.num === authorNum) {
      const acked = directory.ack_local(target.state, op, meta);
      if (!acked.isOk()) {
        console.warn("directory ack failed", acked);
        return;
      }
      target.state = acked[0];
      target.pending = target.pending.filter((p) => p.mid !== mid);
    } else {
      const applied = directory.apply_remote(target.state, op, meta, target.num);
      target.state = applied[0];
    }
    target.lastAppliedSn = seq;
  }

  // Run a local edit that yields a single op (set/delete/clear return the op
  // directly; create/delete-subdir wrap it in Option). Optimistically apply,
  // mark it pending, and ship the op if the kernel produced one.
  function localEdit(
    client: Client,
    result: { isOk: () => boolean; 0: unknown[] },
    marker: string,
    optionWrapped: boolean,
  ) {
    if (!result.isOk()) return;
    const [state, , opField, mid] = result[0] as [unknown, unknown, unknown, number];
    client.state = state;
    let op: unknown = opField;
    if (optionWrapped) op = opField instanceof Some ? opField[0] : null;
    if (op == null) {
      render(client);
      renderStatus();
      return;
    }
    client.pending.push({ mid, marker });
    render(client);
    renderStatus();
    sendOp(client, op, mid, client.num, client.lastAppliedSn, marker);
  }

  // ── local operations ────────────────────────────────────────────────────────
  function localCreate(clientId: string, path: string, forcedName?: string) {
    const client = clients[clientId];
    const name = forcedName ?? nextFolder(client, path);
    const childPath = join(path, name);
    localEdit(
      client,
      directory.create_subdirectory(client.state, path, name, client.num),
      "sub:" + childPath,
      true,
    );
  }

  function localSet(clientId: string, path: string, forced?: [string, string]) {
    const client = clients[clientId];
    const [key, value] = forced ?? nextReading(client);
    localEdit(
      client,
      directory.set(client.state, path, key, json.string(value)),
      `key:${path}::${key}`,
      false,
    );
  }

  function localDelete(clientId: string, path: string) {
    const client = clients[clientId];
    localEdit(
      client,
      directory.delete_subdirectory(client.state, parentOf(path), baseName(path)),
      "del:" + path,
      true,
    );
  }

  function nextFolder(client: Client, path: string): string {
    const siblings = new Set(subdirs(client, path));
    // Skip names already present at this path so the free-form button never
    // makes a confusing /a/a; A and B stagger their cursors so independent
    // creates don't collide by accident either.
    for (let i = 0; i < FOLDER_NAMES.length; i++) {
      const name = FOLDER_NAMES[client.folderCursor % FOLDER_NAMES.length];
      client.folderCursor += CLIENT_IDS.length;
      if (!siblings.has(name)) return name;
    }
    return FOLDER_NAMES[client.folderCursor % FOLDER_NAMES.length];
  }

  function nextReading(client: Client): [string, string] {
    const reading = READINGS[client.readingCursor % READINGS.length];
    client.readingCursor += 1;
    return reading;
  }

  // ── set-piece buttons ────────────────────────────────────────────────────────
  // Both clients create a folder of the SAME name against the same base before
  // seeing each other's op. They converge to a single folder whose creator set
  // includes both — the signature SharedDirectory race.
  raceBtn.addEventListener("click", () => {
    for (const id of CLIENT_IDS) localCreate(id, "/", RACE_FOLDER);
  });

  // Populate a small survey tree from Client A; it propagates to B. Gives the
  // free-form buttons something to act on.
  seedBtn.addEventListener("click", () => {
    localCreate("a", "/", "surveys");
    localSet("a", "/surveys", ["BM-17", "recorded"]);
    localCreate("a", "/", "plans");
    localSet("a", "/plans", ["grade", "2.1%"]);
    // Forced-name creates don't advance the auto-name cursor, so step it past
    // the two seeded folder names — otherwise the first free-form "+ folder"
    // reuses "surveys" and makes a confusing /surveys/surveys. (Stepping by a
    // multiple of the pool length would be a no-op under the modulo.)
    clients.a.folderCursor += 2;
    clients.a.readingCursor += 2;
  });

  resetBtn.addEventListener("click", () => {
    epoch += 1;
    sequencer.reset();
    for (const id of CLIENT_IDS) {
      const client = clients[id];
      client.state = directory.new$();
      client.lastAppliedSn = 0;
      client.pending = [];
      client.folderCursor = CLIENT_NUM[id];
      client.readingCursor = CLIENT_NUM[id];
      render(client);
    }
    seqCounter.textContent = "SN 0";
    opLog.clear();
    renderStatus();
  });

  // ── first paint ──────────────────────────────────────────────────────────────
  for (const id of CLIENT_IDS) render(clients[id]);
  renderStatus();
}
