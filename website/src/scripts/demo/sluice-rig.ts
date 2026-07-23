// Shared harness for the "real runtime against an in-browser server" demos.
//
// Every convergence demo (sudoku, directory, json-ot) has the same spine: spin
// up an in-memory `sluice`, connect a few real `watershed` documents, let a
// user edit optimistically, and pump sequenced ops out one paced hop at a time
// until every replica converges — animating each hop and logging each op. That
// spine lives here, parameterised by three DDS-specific hooks:
//
//   • setup(clients, server) — establish the shared instance and hang a
//     per-client `handle` off each client (for a root map that's just
//     `watershed.root(doc)`; for a directory/json-ot it creates the channel on
//     one client, shares the handle, and resolves it on the others).
//   • render(client) — draw one replica; edit affordances call `rig.submit`.
//   • canonical(client) — a comparable signature of a replica, for convergence.
//
// The sluice is DDS-agnostic (it sequences opaque wire frames), so this harness
// is too: it never mentions maps, folders, or text.
import * as sluice from "../../../../build/dev/javascript/watershed/watershed/sluice_js.mjs";
import { prefersReducedMotion } from "./timing.ts";
import { createFlowLayer, type FlowLayer } from "./flow-dots.ts";
import { createLatencyControls, type LatencyControls } from "./controls.ts";
import { createOpLog, type OpLog } from "./op-log.ts";

const FIFO_GAP_MS = 25;

export interface RigClient {
  id: string;
  doc: unknown;
  el: Element;
  /** DDS-specific handle set by `setup` (a SharedMap, an address, …). */
  handle: unknown;
  /** Optimistic-write markers, cleared when the client is fully acked. */
  pending: string[];
  cursor: number;
  /** Scratch space for the demo. */
  data: Record<string, unknown>;
}

export interface RigConfig {
  /** Rig container selector, e.g. `[data-sudoku-rig]`. */
  rig: string;
  /** Status line selector, e.g. `[data-sudoku-status]`. */
  status: string;
  /** Section wrapper selector (used to enable its controls), e.g. `#sudoku-demo`. */
  section: string;
  /** Control attribute prefix, e.g. `sudoku` → `[data-sudoku-latency]` etc. */
  control: string;
  /** Logical document name for the sluice. */
  document: string;
  clientIds: string[];
  clientLabel: Record<string, string>;
  setup: (clients: Record<string, RigClient>, server: unknown) => void;
  render: (client: RigClient) => void;
  canonical: (client: RigClient) => string;
  /**
   * Optional hook fired just before each queued frame is actually delivered
   * (i.e. before the `sluice.step_info` call whose synchronous side effect
   * hands the frame to the recipient runtime, which may in turn fan out a
   * subscribed `ChannelEvent` before this hook returns). Lets a caller that
   * needs to know *who authored* the op about to land — the rig already
   * resolves sluice's sid to a `RigClient` for its own bookkeeping — thread
   * that identity into a runtime `subscribe` handler without the rig needing
   * to know anything about the kernel it's carrying. `author` is `null` for
   * non-`"op"` events (handshake, signal) or when the author isn't a tracked
   * client.
   */
  onBeforeDeliver?: (
    delivery: Delivery,
    author: RigClient | null,
    to: RigClient,
  ) => void;
}

export interface Rig {
  clients: Record<string, RigClient>;
  serverPending: () => boolean;
  /** Perform one optimistic write and start pumping its delivery. */
  submit: (
    client: RigClient,
    marker: string | null,
    write: () => void,
    label: string,
  ) => void;
  reset: () => void;
  renderAll: () => void;
  renderStatus: () => void;
  /**
   * Deliver exactly the next queued wave (one op's broadcast, or one
   * handshake/signal frame) immediately, bypassing the paced network-latency
   * timer. A no-op when nothing is queued.
   */
  step: () => void;
  /**
   * Drain every queued frame immediately (no animation, no paced delay) and
   * clear all pending markers — "fast forward to convergence".
   */
  settleNow: () => void;
}

// Gleam `Some(x)` carries the value at index 0; `None` has no such field.
export function some<T>(option: unknown): T | null {
  if (option && typeof option === "object" && 0 in option) {
    return (option as { 0: T })[0];
  }
  return null;
}

export interface Delivery {
  to: string;
  event: string;
  sequence_number: number;
  author: string;
}

export function createSluiceRig(config: RigConfig): Rig | null {
  const rig = document.querySelector(config.rig);
  if (!rig) return null;

  const flowLayer = rig.querySelector("[data-flow-layer]");
  const seqNode = rig.querySelector("[data-seq-node]");
  const seqCounter = rig.querySelector("[data-seq-counter]");
  const opLogEl = rig.querySelector("[data-op-log]");
  const statusEl = document.querySelector(config.status);
  const latencyInput = document.querySelector(`[data-${config.control}-latency]`);
  const latencyOut = document.querySelector(`[data-${config.control}-latency-out]`);
  const paceInput = document.querySelector(`[data-${config.control}-pace]`);
  const paceOut = document.querySelector(`[data-${config.control}-pace-out]`);
  const varianceToggle = document.querySelector(
    `[data-${config.control}-latency-variance]`,
  );
  const section = document.querySelector(config.section);

  if (
    !(flowLayer instanceof HTMLElement) ||
    !(seqNode instanceof HTMLElement) ||
    !(seqCounter instanceof HTMLElement) ||
    !(opLogEl instanceof HTMLOListElement) ||
    !(statusEl instanceof HTMLElement) ||
    !(latencyInput instanceof HTMLInputElement) ||
    !(latencyOut instanceof HTMLElement) ||
    !(section instanceof HTMLElement)
  ) {
    return null;
  }

  for (const el of section.querySelectorAll("button, input")) {
    if (el instanceof HTMLButtonElement || el instanceof HTMLInputElement) el.disabled = false;
  }

  const controls: LatencyControls = createLatencyControls({
    latencyInput,
    latencyOut,
    paceInput: paceInput instanceof HTMLInputElement ? paceInput : null,
    paceOut: paceOut instanceof HTMLElement ? paceOut : null,
    varianceToggle: varianceToggle instanceof HTMLInputElement ? varianceToggle : null,
  });
  const flow: FlowLayer = createFlowLayer(flowLayer, prefersReducedMotion);
  const opLog: OpLog = createOpLog(opLogEl, { max: 24 });

  const clients: Record<string, RigClient> = {};
  for (const id of config.clientIds) {
    const el = rig.querySelector(`[data-client="${id}"]`);
    if (!el) return null;
    clients[id] = {
      id,
      doc: null,
      el,
      handle: null,
      pending: [],
      cursor: config.clientIds.indexOf(id),
      data: {},
    };
  }

  let server: unknown = null;
  const sidToId: Record<string, string> = {};
  const labelBySn = new Map<number, string>();
  const outboundBySn = new Map<
    number,
    { client: RigClient; label: string; arrivalAt: number }
  >();
  const pendingBySn = new Map<number, { client: RigClient; marker: string }>();
  const deliveryTimers = new Set<ReturnType<typeof setTimeout>>();
  let pumpTimer: ReturnType<typeof setTimeout> | null = null;
  let lastOutboundArrival = 0;
  let inFlight = 0;

  function boot() {
    server = sluice.start(config.document, config.document);
    for (const id of config.clientIds) {
      const doc = sluice.connect(server, `user-${id}`);
      clients[id].doc = doc;
      clients[id].pending = [];
      clients[id].cursor = config.clientIds.indexOf(id);
      clients[id].data = {};
      clients[id].handle = null;
    }
    // Complete every handshake before the DDS-specific shared-instance setup.
    sluice.settle(server);
    for (const key of Object.keys(sidToId)) delete sidToId[key];
    for (const id of config.clientIds) {
      const result = sluice.client_id(server, clients[id].doc);
      if (result.isOk()) sidToId[result[0] as string] = id;
    }
    config.setup(clients, server);
    // The setup may have pushed handshake/attach ops; drain them silently so
    // the visible timeline starts clean.
    sluice.settle(server);
    labelBySn.clear();
  }

  function converged(): boolean {
    const sigs = config.clientIds.map((id) => config.canonical(clients[id]));
    const identical = sigs.every((s) => s === sigs[0]);
    const anyPending = config.clientIds.some((id) => clients[id].pending.length > 0);
    return identical && !anyPending && !sluice.pending(server) && inFlight === 0;
  }

  function renderStatus() {
    statusEl.innerHTML = converged()
      ? '<span class="stamp converged">Converged</span> all replicas identical · nothing pending'
      : '<span class="stamp revising">Revising</span> ops in flight';
  }

  function stampSeqCounter(seq: number) {
    seqCounter.textContent = `SN ${seq}`;
    seqCounter.classList.remove("stamped");
    void seqCounter.offsetWidth;
    seqCounter.classList.add("stamped");
  }

  function logOp(seq: number, authorId: string, label: string) {
    const li = document.createElement("li");
    const meta = document.createElement("span");
    meta.className = "op-meta";
    const who = (config.clientLabel[authorId] ?? authorId).replace("Client ", "");
    meta.textContent = `SN ${seq} · ${who}`;
    const pathEl = document.createElement("span");
    pathEl.className = "op-path";
    pathEl.textContent = label;
    const kindEl = document.createElement("span");
    kindEl.className = "op-kind";
    kindEl.textContent = "op";
    li.append(meta, pathEl, kindEl);
    opLog.push(li);
  }

  function pump() {
    if (pumpTimer != null) return;
    const next = some<Delivery>(sluice.peek_info(server));
    if (next == null) {
      renderStatus();
      return;
    }
    const outbound =
      next.event === "op" ? outboundBySn.get(next.sequence_number) : null;
    const delay = outbound
      ? Math.max(0, outbound.arrivalAt - performance.now())
      : controls.paced(controls.sampleLatency());
    pumpTimer = setTimeout(pumpTick, delay);
  }

  /** Stamp the sequencer counter and append an op-log line, but only once —
   * on the delivery back to the op's own author (the "ack" leg). */
  function ackIfAuthor(delivery: Delivery) {
    if (delivery.to !== delivery.author) return;
    const authorId = sidToId[delivery.author] ?? delivery.to;
    stampSeqCounter(delivery.sequence_number);
    logOp(
      delivery.sequence_number,
      authorId,
      labelBySn.get(delivery.sequence_number) ?? `SN ${delivery.sequence_number}`,
    );
  }

  /** Clear the delivered op's pending marker (if this was its author's ack)
   * and re-render the recipient. Shared by the animated and instant paths so
   * a manual `settleNow` drain lands identically to the paced one. */
  function landDelivery(toId: string, delivery: Delivery) {
    if (delivery.to === delivery.author) {
      const pending = pendingBySn.get(delivery.sequence_number);
      if (pending?.client === clients[toId]) {
        pendingBySn.delete(delivery.sequence_number);
        const markerStillPending = [...pendingBySn.values()].some(
          (entry) =>
            entry.client === pending.client && entry.marker === pending.marker,
        );
        if (!markerStillPending) {
          pending.client.pending = pending.client.pending.filter(
            (marker) => marker !== pending.marker,
          );
        }
      }
    }
    config.render(clients[toId]);
  }

  function deliver(delivery: Delivery) {
    const toId = sidToId[delivery.to];
    if (delivery.event !== "op" || !toId) return;
    const duration = controls.paced(controls.sampleLatency());
    flow.animateDot(
      seqNode,
      clients[toId].el,
      duration,
      true,
      `SN ${delivery.sequence_number}`,
    );
    ackIfAuthor(delivery);
    inFlight += 1;
    const timer = setTimeout(() => {
      deliveryTimers.delete(timer);
      landDelivery(toId, delivery);
      inFlight = Math.max(0, inFlight - 1);
      renderStatus();
    }, duration);
    deliveryTimers.add(timer);
  }

  function fireBeforeDeliver(delivery: Delivery) {
    if (!config.onBeforeDeliver) return;
    const authorId = sidToId[delivery.author];
    const toId = sidToId[delivery.to];
    if (!toId) return;
    config.onBeforeDeliver(
      delivery,
      authorId ? clients[authorId] : null,
      clients[toId],
    );
  }

  function pumpTick() {
    pumpTimer = null;
    const first = some<Delivery>(sluice.peek_info(server));
    if (first == null) {
      renderStatus();
      return;
    }

    // A real server fans one op out to every client at once, so drain the whole
    // broadcast wave — every queued frame sharing this op's sequence number — in
    // a single tick. Each recipient's dot still carries its own sampled latency,
    // so they land staggered by per-link jitter, not by the pump. The next
    // client→sequencer op keeps travelling independently while these return legs
    // are in flight.
    if (first.event === "op") {
      const waveSn = first.sequence_number;
      if (outboundBySn.delete(waveSn)) inFlight = Math.max(0, inFlight - 1);
      let next: Delivery | null = first;
      while (next != null && next.event === "op" && next.sequence_number === waveSn) {
        // step_info's delivery to the runtime is synchronous — fire the hook
        // (e.g. to stamp the upcoming subscribe callback with its author)
        // just before that side effect, using the still-undelivered peek.
        fireBeforeDeliver(next);
        const delivery = some<Delivery>(sluice.step_info(server));
        if (delivery == null) break;
        deliver(delivery);
        next = some<Delivery>(sluice.peek_info(server));
      }
    } else {
      fireBeforeDeliver(first);
      const delivery = some<Delivery>(sluice.step_info(server));
      if (delivery != null) deliver(delivery);
    }

    renderStatus();
    if (sluice.pending(server)) pump();
  }

  /** Deliver exactly the next queued wave immediately, no paced delay. */
  function step() {
    if (pumpTimer != null) {
      clearTimeout(pumpTimer);
      pumpTimer = null;
    }
    pumpTick();
  }

  /**
   * Drain every queued frame immediately (no animation, no paced delay) —
   * "fast forward to convergence". Unlike calling `sluice.settle` directly,
   * this still routes each delivery through `deliver`'s ack/pending-clear
   * bookkeeping and `config.onBeforeDeliver` (one delivery at a time, via
   * `peek_info`/`step_info`, exactly like `pumpTick`'s wave loop), so the op
   * log, sequence counter, and any author-routing a caller hooked in stay
   * correct after a bulk settle, not just after the paced path.
   */
  function settleNow() {
    if (pumpTimer != null) {
      clearTimeout(pumpTimer);
      pumpTimer = null;
    }
    for (const timer of deliveryTimers) clearTimeout(timer);
    deliveryTimers.clear();
    inFlight = 0;
    let guard = 0;
    const GUARD_LIMIT = 20000; // pathological-loop backstop, never expected
    while (guard < GUARD_LIMIT) {
      const next = some<Delivery>(sluice.peek_info(server));
      if (next == null) break;
      if (next.event === "op") outboundBySn.delete(next.sequence_number);
      fireBeforeDeliver(next);
      const delivery = some<Delivery>(sluice.step_info(server));
      if (delivery == null) break;
      const toId = sidToId[delivery.to];
      if (delivery.event === "op" && toId) {
        ackIfAuthor(delivery);
        landDelivery(toId, delivery);
      }
      guard += 1;
    }
    outboundBySn.clear();
    pendingBySn.clear();
    lastOutboundArrival = 0;
    for (const id of config.clientIds) clients[id].pending = [];
    renderAll();
    renderStatus();
  }

  function submit(
    client: RigClient,
    marker: string | null,
    write: () => void,
    label: string,
  ) {
    write();
    const sn = sluice.sequence_number(server);
    labelBySn.set(sn, label);
    const now = performance.now();
    const arrivalAt = Math.max(
      now + controls.paced(controls.sampleLatency()),
      lastOutboundArrival + controls.paced(FIFO_GAP_MS),
    );
    lastOutboundArrival = arrivalAt;
    outboundBySn.set(sn, {
      client,
      label,
      arrivalAt,
    });
    inFlight += 1;
    if (marker) {
      pendingBySn.set(sn, { client, marker });
      if (!client.pending.includes(marker)) client.pending.push(marker);
    }
    config.render(client);
    renderStatus();
    flow.animateDot(client.el, seqNode, arrivalAt - now, false, label);
    pump();
  }

  function renderAll() {
    for (const id of config.clientIds) config.render(clients[id]);
  }

  function reset() {
    if (pumpTimer != null) {
      clearTimeout(pumpTimer);
      pumpTimer = null;
    }
    for (const timer of deliveryTimers) clearTimeout(timer);
    deliveryTimers.clear();
    outboundBySn.clear();
    pendingBySn.clear();
    lastOutboundArrival = 0;
    inFlight = 0;
    flowLayer.replaceChildren();
    boot();
    seqCounter.textContent = "SN 0";
    opLog.clear();
    renderAll();
    renderStatus();
  }

  boot();
  renderAll();
  renderStatus();

  return {
    clients,
    serverPending: () => sluice.pending(server),
    submit,
    reset,
    renderAll,
    renderStatus,
    step,
    settleNow,
  };
}
