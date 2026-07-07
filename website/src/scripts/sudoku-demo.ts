// Live SharedMap Sudoku convergence demo. Three browser "clients" each own a
// real watershed `map_kernel`, compiled with `gleam build --target javascript`.
// They talk through the shared in-page sequencer: local cell edits render
// optimistically, the sequencer stamps FIFO server order, and every replica
// converges on the last sequenced value for each cell.
import * as mapKernel from "../../../build/dev/javascript/watershed/watershed/map_kernel.mjs";
import * as json from "../../../build/dev/javascript/gleam_json/gleam/json.mjs";
import { prefersReducedMotion } from "./demo/timing.ts";
import { createFlowLayer } from "./demo/flow-dots.ts";
import { createLatencyControls } from "./demo/controls.ts";
import { createOpLog } from "./demo/op-log.ts";
import { createSequencer } from "./demo/sequencer.ts";

const CLIENT_IDS = ["a", "b", "c"];
const CLIENT_LABEL: Record<string, string> = {
  a: "Client A",
  b: "Client B",
  c: "Client C",
};
const BOARD_SIZE = 4;
const DIGITS = [1, 2, 3, 4];
const RACE_CELL = { row: 1, col: 1 };

interface PendingMark {
  id: number;
  key: string;
}

interface Client {
  id: string;
  state: unknown;
  el: Element;
  lastAppliedSn: number;
  pending: PendingMark[];
  cursor: number;
  lastArrival: number;
}

function cellKey(row: number, col: number): string {
  return `r${row}c${col}`;
}

function cellLabel(row: number, col: number): string {
  return `r${row + 1}c${col + 1}`;
}

function readInt(optionValue: unknown): number | null {
  if (optionValue && typeof optionValue === "object" && 0 in optionValue) {
    const value = (optionValue as { 0: unknown })[0];
    const n = Number(json.to_string(value));
    return Number.isFinite(n) ? n : null;
  }
  return null;
}

function cellValue(client: Client, row: number, col: number): number | null {
  return readInt(mapKernel.get(client.state, cellKey(row, col)));
}

function canonicalBoard(client: Client): string {
  const cells: Array<number | null> = [];
  for (let row = 0; row < BOARD_SIZE; row += 1) {
    for (let col = 0; col < BOARD_SIZE; col += 1) {
      cells.push(cellValue(client, row, col));
    }
  }
  return JSON.stringify(cells);
}

function pendingFor(client: Client, key: string): PendingMark | undefined {
  return client.pending.findLast((p) => p.key === key);
}

export function initSudokuDemo() {
  const rig = document.querySelector("[data-sudoku-rig]");
  if (!rig) return;

  const flowLayer = rig.querySelector("[data-flow-layer]");
  const seqNode = rig.querySelector("[data-seq-node]");
  const seqCounter = rig.querySelector("[data-seq-counter]");
  const opLogEl = rig.querySelector("[data-op-log]");
  const statusEl = document.querySelector("[data-sudoku-status]");
  const latencyInput = document.querySelector("[data-sudoku-latency]");
  const latencyOut = document.querySelector("[data-sudoku-latency-out]");
  const paceInput = document.querySelector("[data-sudoku-pace]");
  const paceOut = document.querySelector("[data-sudoku-pace-out]");
  const varianceToggle = document.querySelector("[data-sudoku-latency-variance]");
  const raceBtn = document.querySelector("[data-sudoku-race]");
  const seedBtn = document.querySelector("[data-sudoku-seed]");
  const resetBtn = document.querySelector("[data-sudoku-reset]");

  const section = document.querySelector("#sudoku-demo");
  if (
    !(flowLayer instanceof HTMLElement) ||
    !(seqNode instanceof HTMLElement) ||
    !(seqCounter instanceof HTMLElement) ||
    !(opLogEl instanceof HTMLOListElement) ||
    !(statusEl instanceof HTMLElement) ||
    !(latencyInput instanceof HTMLInputElement) ||
    !(latencyOut instanceof HTMLElement) ||
    !(paceInput instanceof HTMLInputElement) ||
    !(paceOut instanceof HTMLElement) ||
    !(varianceToggle instanceof HTMLInputElement) ||
    !(raceBtn instanceof HTMLButtonElement) ||
    !(seedBtn instanceof HTMLButtonElement) ||
    !(resetBtn instanceof HTMLButtonElement) ||
    !(section instanceof HTMLElement)
  ) {
    return;
  }

  for (const el of section.querySelectorAll("button, input")) {
    if (el instanceof HTMLButtonElement || el instanceof HTMLInputElement) el.disabled = false;
  }

  const clients: Record<string, Client> = {};
  for (const id of CLIENT_IDS) {
    const el = rig.querySelector(`[data-client="${id}"]`);
    if (!el) return;
    clients[id] = {
      id,
      state: mapKernel.new$(),
      el,
      lastAppliedSn: 0,
      pending: [],
      cursor: CLIENT_IDS.indexOf(id),
      lastArrival: 0,
    };
  }

  let epoch = 0;
  let nextPendingId = 1;

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

  function render(client: Client) {
    const boardEl = client.el.querySelector("[data-board]");
    if (!boardEl) return;
    boardEl.replaceChildren();

    for (let row = 0; row < BOARD_SIZE; row += 1) {
      for (let col = 0; col < BOARD_SIZE; col += 1) {
        const key = cellKey(row, col);
        const value = cellValue(client, row, col);
        const pending = pendingFor(client, key);
        const button = document.createElement("button");
        button.type = "button";
        button.className = "sudoku-cell";
        button.dataset.row = String(row);
        button.dataset.col = String(col);
        button.textContent = value == null ? "·" : String(value);
        button.classList.toggle("is-empty", value == null);
        button.classList.toggle("k-pending", pending != null);
        button.classList.toggle("k-seq", pending == null && value != null);
        button.setAttribute(
          "aria-label",
          `${CLIENT_LABEL[client.id]} ${cellLabel(row, col)} ${
            value == null ? "empty" : `digit ${value}`
          }. Press to write the next digit; Shift plus Enter or Space clears.`,
        );
        button.addEventListener("click", (event) => {
          if (event.shiftKey) localClear(client.id, row, col);
          else localCycle(client.id, row, col);
        });
        button.addEventListener("keydown", (event) => {
          if ((event.key === "Enter" || event.key === " ") && event.shiftKey) {
            event.preventDefault();
            localClear(client.id, row, col);
          }
        });
        boardEl.append(button);
      }
    }

    const count = client.pending.length;
    const badge = client.el.querySelector("[data-pending-count]");
    if (badge instanceof HTMLElement) {
      badge.textContent = `${count} pending`;
      badge.classList.toggle("is-pending", count > 0);
    }
  }

  function converged(): boolean {
    const sigs = CLIENT_IDS.map((id) => canonicalBoard(clients[id]));
    const identical = sigs.every((s) => s === sigs[0]);
    const anyPending = CLIENT_IDS.some((id) => clients[id].pending.length > 0);
    return identical && !anyPending && sequencer.inFlight === 0;
  }

  function renderStatus() {
    if (!statusEl) return;
    statusEl.innerHTML = converged()
      ? '<span class="stamp converged">Converged</span> all boards identical · nothing pending'
      : '<span class="stamp revising">Revising</span> ops in flight';
  }

  function stampSeqCounter(seq: number) {
    seqCounter.textContent = `SN ${seq}`;
    seqCounter.classList.remove("stamped");
    void seqCounter.offsetWidth;
    seqCounter.classList.add("stamped");
  }

  function logOp(seq: number, authorId: string, label: string, refSeq: number) {
    const li = document.createElement("li");
    const meta = document.createElement("span");
    meta.className = "op-meta";
    meta.textContent = `SN ${seq} · ${CLIENT_LABEL[authorId].replace("Client ", "")}`;
    const pathEl = document.createElement("span");
    pathEl.className = "op-path";
    pathEl.textContent = label;
    const kindEl = document.createElement("span");
    kindEl.className = "op-kind";
    kindEl.textContent = `ref ${refSeq}`;
    li.append(meta, pathEl, kindEl);
    opLog.push(li);
  }

  function sendOp(origin: Client, op: unknown, pendingId: number, key: string, label: string) {
    const refSeq = origin.lastAppliedSn;
    sequencer.send({
      originId: origin.id,
      label,
      guard: () => {
        const myEpoch = epoch;
        return () => myEpoch !== epoch;
      },
      onSequence: (seq: number) => {
        stampSeqCounter(seq);
        logOp(seq, origin.id, label, refSeq);
        return { pendingId, key, refSeq };
      },
      onDeliver: (target: Client, { seq }: { seq: number }) => {
        deliver(target, op, origin.id, pendingId, seq);
        render(target);
      },
    });
  }

  function deliver(target: Client, op: unknown, authorId: string, pendingId: number, seq: number) {
    if (target.id === authorId) {
      const acked = mapKernel.ack_local(target.state, op);
      if (acked.isOk()) {
        target.state = acked[0];
        target.pending = target.pending.filter((p) => p.id !== pendingId);
      }
    } else {
      const [state] = mapKernel.apply_remote(target.state, op);
      target.state = state;
    }
    target.lastAppliedSn = seq;
  }

  function localEdit(client: Client, result: unknown[], key: string, label: string) {
    const [state, , op] = result;
    client.state = state;
    const id = nextPendingId;
    nextPendingId += 1;
    client.pending.push({ id, key });
    render(client);
    renderStatus();
    sendOp(client, op, id, key, label);
  }

  function localSet(clientId: string, row: number, col: number, digit: number) {
    const client = clients[clientId];
    const key = cellKey(row, col);
    localEdit(
      client,
      mapKernel.set(client.state, key, json.int(digit)),
      key,
      `${cellLabel(row, col)} → ${digit}`,
    );
  }

  function localClear(clientId: string, row: number, col: number) {
    const client = clients[clientId];
    const key = cellKey(row, col);
    localEdit(client, mapKernel.delete$(client.state, key), key, `${cellLabel(row, col)} clear`);
  }

  function localCycle(clientId: string, row: number, col: number) {
    const client = clients[clientId];
    const value = cellValue(client, row, col);
    const digit = value == null ? DIGITS[client.cursor % DIGITS.length] : (value % BOARD_SIZE) + 1;
    client.cursor += 1;
    localSet(clientId, row, col, digit);
  }

  raceBtn.addEventListener("click", () => {
    const { row, col } = RACE_CELL;
    localSet("a", row, col, 1);
    localSet("b", row, col, 3);
    localSet("c", row, col, 4);
  });

  seedBtn.addEventListener("click", () => {
    localSet("a", 0, 0, 1);
    localSet("a", 0, 3, 4);
    localSet("b", 3, 0, 2);
    localSet("c", 3, 3, 3);
  });

  resetBtn.addEventListener("click", () => {
    epoch += 1;
    sequencer.reset();
    for (const id of CLIENT_IDS) {
      const client = clients[id];
      client.state = mapKernel.new$();
      client.lastAppliedSn = 0;
      client.pending = [];
      client.cursor = CLIENT_IDS.indexOf(id);
      client.lastArrival = 0;
      render(client);
    }
    seqCounter.textContent = "SN 0";
    opLog.clear();
    renderStatus();
  });

  for (const id of CLIENT_IDS) render(clients[id]);
  renderStatus();
}
