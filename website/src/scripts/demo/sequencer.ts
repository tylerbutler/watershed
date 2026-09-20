// The in-page sequencer transport shared by the interactive demos. A hidden
// watershed document carries one marker write per demo operation through the
// real in-memory sluice. The demo applies its typed kernel operation when each
// corresponding sluice delivery lands.
//
// The transport is domain-agnostic. The demo supplies three hooks:
//   • guard      — snapshots an epoch at send time and reports if it went stale
//                  (a reset happened) so an in-flight op is dropped, not stamped.
//   • onSequence — stamps the SN into the demo's own state / op-log and returns
//                  an `extra` value threaded to every delivery.
//   • onDeliver  — applies the op to one replica and re-renders it.

import type { FlowLayer } from "./flow-dots.ts";
import type { LatencyControls } from "./controls.ts";
import {
  networkPending,
  sequenceNumber,
  writeSequenceMarker,
  type DemoDocument,
  type DemoServer,
} from "./sluice-runtime.ts";
import {
  createDeliveryEngine,
  createSluiceNetwork,
  type DeliveryEngine,
  type DeliveryScheduler,
  type SluiceDelivery,
  type SluiceNetwork,
} from "./sluice-transport.ts";

/** A replica the sequencer can animate to and deliver to. */
export interface SeqClient {
  el: Element;
  /** FIFO watermark: the wall-clock time this replica's last op arrived. */
  lastArrival: number;
  [key: string]: unknown;
}

export interface SequencerConfig<C extends SeqClient> {
  clients: Record<string, C>;
  seqNode: Element;
  flow: FlowLayer;
  controls: LatencyControls;
  /** Minimum spacing between successive arrivals (ms, base). Default 25. */
  fifoGap?: number;
  /** Called after every inFlight change so the demo can re-render status. */
  onChange: () => void;
  /** Per-target link check at fan-out time; a down link holds the hop
   *  (no dot, no delivery) instead of animating it. */
  isLinkUp?: (client: C) => boolean;
  /** Receives each held hop (staleness pre-checked) for replay on restore. */
  onHold?: (client: C, deliver: () => void) => void;
}

export interface SendOptions<C extends SeqClient, E> {
  /** Key into `clients` for the authoring replica. */
  originId: string;
  /** Optional label riding along with the dots to name the op in flight. */
  label?: string;
  /** Snapshot the current epoch; the returned predicate reports staleness. */
  guard?: () => () => boolean;
  /** Stamp the freshly assigned SN; the returned value is passed to onDeliver. */
  onSequence: (seq: number) => E;
  /** Apply the sequenced op to one replica. */
  onDeliver: (target: C, ctx: { seq: number; extra: E }) => void;
}

export interface BroadcastOptions<C extends SeqClient> {
  /** Optional label riding along with the dots to name the op in flight. */
  label?: string;
  /** Optional staleness predicate; a stale hop is dropped before delivery. */
  isStale?: () => boolean;
  /** Deliver the (already-sequenced) op to one replica. */
  onDeliver: (target: C) => void;
}

export interface Sequencer<C extends SeqClient> {
  /** Ops currently travelling on the wire (for the status line). */
  readonly inFlight: number;
  /** The last stamped sequence number. */
  readonly sn: number;
  /** Author an op: client → sequencer → broadcast. */
  send<E>(opts: SendOptions<C, E>): void;
  /** Re-broadcast an already-sequenced op to every replica (no new SN). */
  broadcast(opts: BroadcastOptions<C>): void;
  /** Zero the SN, in-flight count and FIFO watermark (call from demo reset). */
  reset(): void;
}

const browserScheduler: DeliveryScheduler = {
  now: () => performance.now(),
  set: (delayMs, callback) => setTimeout(callback, delayMs),
  clear: (handle) => clearTimeout(handle as ReturnType<typeof setTimeout>),
};

export function createSequencer<C extends SeqClient>(
  config: SequencerConfig<C>,
  scheduler: DeliveryScheduler = browserScheduler,
): Sequencer<C> {
  const { clients, seqNode, flow, controls, onChange } = config;
  const fifoGap = config.fifoGap ?? 25;

  type PendingOperation = {
    isStale: () => boolean;
    label?: string;
    begin: (seq: number) => (target: C) => void;
  };

  let network!: SluiceNetwork;
  let server!: DemoServer;
  let documents!: Record<string, DemoDocument>;
  let sidToId!: Record<string, string>;
  let baseSequence = 0;
  let sn = 0;
  let inFlight = 0;
  let seqLastArrival = 0;
  let generation = 0;
  let engine: DeliveryEngine;
  const pendingBySequence = new Map<number, PendingOperation>();

  function bootTransport() {
    network = createSluiceNetwork({
      tenant: "website",
      document: "structure-atlas",
      clientIds: Object.keys(clients),
    });
    server = network.server;
    documents = network.documents;
    sidToId = network.sidToId;
    baseSequence = sequenceNumber(server);
  }

  function deliverTo(
    target: C,
    isStale: () => boolean,
    deliver: () => void,
    label?: string,
  ): void {
    if (config.isLinkUp && !config.isLinkUp(target)) {
      config.onHold?.(target, () => {
        if (!isStale()) deliver();
      });
      return;
    }
    const hopLatency = controls.sampleLatency();
    flow.animateDot(
      seqNode,
      target.el,
      controls.paced(hopLatency),
      true,
      label,
      hopLatency,
    );
    const now = scheduler.now();
    const arrival = Math.max(
      now + controls.paced(hopLatency),
      target.lastArrival + controls.paced(fifoGap),
    );
    target.lastArrival = arrival;
    inFlight += 1;
    scheduler.set(arrival - now, () => {
      if (!isStale()) deliver();
      inFlight = Math.max(0, inFlight - 1);
      onChange();
    });
  }

  function fanOut(
    isStale: () => boolean,
    deliver: (target: C) => void,
    label?: string,
  ): void {
    for (const target of Object.values(clients)) {
      deliverTo(target, isStale, () => deliver(target), label);
    }
  }

  function deliverWave(deliveries: readonly SluiceDelivery[]) {
    const first = deliveries[0];
    if (first?.event !== "op") {
      if (networkPending(server)) engine.schedule(0);
      return;
    }
    const operation = pendingBySequence.get(first.sequence_number);
    if (!operation) {
      if (networkPending(server)) engine.schedule(0);
      return;
    }

    pendingBySequence.delete(first.sequence_number);
    const logicalSequence = first.sequence_number - baseSequence;
    sn = Math.max(sn, logicalSequence);
    const deliver = operation.isStale()
      ? null
      : operation.begin(logicalSequence);
    for (const landed of deliveries) {
      const targetId = sidToId[landed.to];
      const target = targetId ? clients[targetId] : undefined;
      if (target && deliver !== null) {
        deliverTo(
          target,
          operation.isStale,
          () => deliver(target),
          operation.label,
        );
      }
    }
    inFlight = Math.max(0, inFlight - 1);
    onChange();
    if (networkPending(server)) engine.schedule(0);
  }

  bootTransport();
  engine = createDeliveryEngine({
    network,
    scheduler,
    onWave: deliverWave,
    onIdle: onChange,
  });

  return {
    get inFlight() {
      return inFlight;
    },
    get sn() {
      return sn;
    },

    send<E>(opts: SendOptions<C, E>) {
      const sentGeneration = generation;
      const guarded = opts.guard ? opts.guard() : () => false;
      const isStale = () => sentGeneration !== generation || guarded();
      inFlight += 1;
      onChange();

      const originLatency = controls.sampleLatency();
      flow.animateDot(
        clients[opts.originId].el,
        seqNode,
        controls.paced(originLatency),
        false,
        opts.label,
        originLatency,
      );

      const now = scheduler.now();
      const arrival = Math.max(
        now + controls.paced(originLatency),
        seqLastArrival + controls.paced(fifoGap),
      );
      seqLastArrival = arrival;

      scheduler.set(arrival - now, () => {
        if (isStale()) {
          inFlight = Math.max(0, inFlight - 1);
          onChange();
          return;
        }
        writeSequenceMarker(
          documents[opts.originId],
          sn + pendingBySequence.size + 1,
        );
        const sequence = sequenceNumber(server);
        pendingBySequence.set(sequence, {
          isStale,
          label: opts.label,
          begin: (logicalSequence) => {
            const extra = opts.onSequence(logicalSequence);
            return (target) =>
              opts.onDeliver(target, { seq: logicalSequence, extra });
          },
        });
        engine.schedule(0);
      });
    },

    broadcast(opts: BroadcastOptions<C>) {
      const broadcastGeneration = generation;
      const guarded = opts.isStale ?? (() => false);
      fanOut(
        () => broadcastGeneration !== generation || guarded(),
        opts.onDeliver,
        opts.label,
      );
    },

    reset() {
      generation += 1;
      engine.cancel();
      pendingBySequence.clear();
      sn = 0;
      inFlight = 0;
      seqLastArrival = 0;
      bootTransport();
      engine.reset(network);
    },
  };
}
