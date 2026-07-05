// The in-page sequencer transport shared by the interactive demos. It models a
// Fluid-style service: a client sends an op to the sequencer, the sequencer
// stamps a global sequence number (SN) and broadcasts it in FIFO order to every
// replica. Timing is driven by the injected latency/pace controls; the flow
// layer visualises each hop.
//
// The transport is domain-agnostic. The demo supplies three hooks:
//   • guard      — snapshots an epoch at send time and reports if it went stale
//                  (a reset happened) so an in-flight op is dropped, not stamped.
//   • onSequence — stamps the SN into the demo's own state / op-log and returns
//                  an `extra` value threaded to every delivery.
//   • onDeliver  — applies the op to one replica and re-renders it.

import type { FlowLayer } from "./flow-dots.ts";
import type { LatencyControls } from "./controls.ts";

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
}

export interface SendOptions<C extends SeqClient, E> {
  /** Key into `clients` for the authoring replica. */
  originId: string;
  /** Snapshot the current epoch; the returned predicate reports staleness. */
  guard?: () => () => boolean;
  /** Stamp the freshly assigned SN; the returned value is passed to onDeliver. */
  onSequence: (seq: number) => E;
  /** Apply the sequenced op to one replica. */
  onDeliver: (target: C, ctx: { seq: number; extra: E }) => void;
}

export interface BroadcastOptions<C extends SeqClient> {
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

export function createSequencer<C extends SeqClient>(
  config: SequencerConfig<C>,
): Sequencer<C> {
  const { clients, seqNode, flow, controls, onChange } = config;
  const fifoGap = config.fifoGap ?? 25;

  let sn = 0;
  let inFlight = 0;
  let seqLastArrival = 0;

  // The sequencer → replicas fan-out, shared by `send` and `broadcast`.
  function fanOut(isStale: () => boolean, deliver: (target: C) => void): void {
    for (const target of Object.values(clients)) {
      const hopLatency = controls.sampleLatency();
      flow.animateDot(seqNode, target.el, controls.paced(hopLatency), true);
      const tNow = performance.now();
      const tArrival = Math.max(
        tNow + controls.paced(hopLatency),
        target.lastArrival + controls.paced(fifoGap),
      );
      target.lastArrival = tArrival;
      inFlight += 1;
      setTimeout(() => {
        if (isStale()) {
          inFlight = Math.max(0, inFlight - 1);
          onChange();
          return;
        }
        deliver(target);
        inFlight = Math.max(0, inFlight - 1);
        onChange();
      }, tArrival - tNow);
    }
  }

  return {
    get inFlight() {
      return inFlight;
    },
    get sn() {
      return sn;
    },

    send<E>(opts: SendOptions<C, E>) {
      const isStale = opts.guard ? opts.guard() : () => false;
      inFlight += 1;
      onChange();

      const originLatency = controls.sampleLatency();
      flow.animateDot(
        clients[opts.originId].el,
        seqNode,
        controls.paced(originLatency),
        false,
      );

      // FIFO into the sequencer: an op may not overtake an earlier one even if
      // the latency slider moved while it was in flight.
      const now = performance.now();
      const arrival = Math.max(
        now + controls.paced(originLatency),
        seqLastArrival + controls.paced(fifoGap),
      );
      seqLastArrival = arrival;

      setTimeout(() => {
        if (isStale()) {
          inFlight = Math.max(0, inFlight - 1);
          onChange();
          return;
        }
        sn += 1;
        const extra = opts.onSequence(sn);
        const seq = sn;
        fanOut(isStale, (target) => opts.onDeliver(target, { seq, extra }));
        inFlight = Math.max(0, inFlight - 1);
        onChange();
      }, arrival - now);
    },

    broadcast(opts: BroadcastOptions<C>) {
      fanOut(opts.isStale ?? (() => false), opts.onDeliver);
    },

    reset() {
      sn = 0;
      inFlight = 0;
      seqLastArrival = 0;
    },
  };
}
