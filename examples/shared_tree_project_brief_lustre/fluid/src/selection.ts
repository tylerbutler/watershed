import type { ISignaler, SignalListener } from "@fluid-experimental/data-objects";
import { ConnectionState, type IFluidContainer } from "fluid-framework";

export type FixedField =
  | "title" | "owner.name" | "owner.email"
  | "schedule.start" | "schedule.target"
  | "review.reviewer" | "review.approved";
export type Field =
  | { kind: "fixed"; field: FixedField }
  | { kind: "milestone"; id: string; field: "title" | "completed" };
export interface SelectionMetadata {
  name: string;
  color: "blue" | "green" | "amber" | "violet";
  token: number;
  selected: Field | null;
}
export interface Peer {
  sessionId: string;
  metadata: SelectionMetadata;
}
export interface PresenceSession {
  update(metadata: SelectionMetadata): void;
  stop(): void;
}
export interface SeenPeer {
  metadata: SelectionMetadata;
  seenAt: number;
}
export interface BriefShape {
  readonly review?: unknown;
  readonly schedule: { readonly milestones: Iterable<{ readonly id: string }> };
}

const fixedFields = new Set([
  "title", "owner.name", "owner.email", "schedule.start", "schedule.target",
  "review.reviewer", "review.approved",
]);

function object(value: unknown): Record<string, unknown> {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("Invalid selection object");
  }
  return value as Record<string, unknown>;
}

/** Names are plain text, capped at 80 Unicode code points. IDs cannot contain "/". */
export function decode(value: unknown): SelectionMetadata {
  const data = object(value);
  if (typeof data.name !== "string" ||
      !["blue", "green", "amber", "violet"].includes(String(data.color)) ||
      typeof data.color !== "string" ||
      typeof data.token !== "number" || !Number.isSafeInteger(data.token) || data.token < 0) {
    throw new Error("Invalid selection metadata");
  }
  let selected: Field | null = null;
  if (data.selected !== null) {
    const target = object(data.selected);
    if (target.kind === "fixed" && typeof target.field === "string" && fixedFields.has(target.field)) {
      selected = { kind: "fixed", field: target.field as FixedField };
    } else if (target.kind === "milestone" && typeof target.id === "string" &&
        target.id.length > 0 && !target.id.includes("/") &&
        (target.field === "title" || target.field === "completed")) {
      selected = { kind: "milestone", id: target.id, field: target.field };
    } else {
      throw new Error("Invalid selection target");
    }
  }
  return {
    name: Array.from(data.name).slice(0, 80).join(""),
    color: data.color as SelectionMetadata["color"], token: data.token, selected,
  };
}

export function encode(metadata: SelectionMetadata): SelectionMetadata {
  return decode(metadata);
}

export function fieldKey(field: Field): string {
  return field.kind === "fixed" ? field.field : `milestone/${field.id}/${field.field}`;
}

export function available(field: Field, brief: BriefShape): boolean {
  return field.kind === "milestone"
    ? Array.from(brief.schedule.milestones).some((item) => item.id === field.id)
    : !field.field.startsWith("review.") || brief.review != null;
}

export function focus(metadata: SelectionMetadata, selected: Field | null): SelectionMetadata {
  if ((metadata.selected === null && selected === null) ||
      (metadata.selected !== null && selected !== null && fieldKey(metadata.selected) === fieldKey(selected))) {
    return metadata;
  }
  return decode({ ...metadata, selected, token: metadata.token + 1 });
}

export function reconcileLocal(metadata: SelectionMetadata, brief: BriefShape): SelectionMetadata {
  return metadata.selected && !available(metadata.selected, brief) ? focus(metadata, null) : metadata;
}

export function receive(
  peers: Map<string, SeenPeer>, sessionId: string, metadata: SelectionMetadata, now: number,
): Map<string, SeenPeer> {
  const previous = peers.get(sessionId);
  return new Map(peers).set(sessionId, {
    metadata: previous && previous.metadata.token >= metadata.token ? previous.metadata : metadata,
    seenAt: previous ? Math.max(previous.seenAt, now) : now,
  });
}

export function expire(peers: Map<string, SeenPeer>, now: number): Map<string, SeenPeer> {
  return new Map(Array.from(peers).filter(([, peer]) => now - peer.seenAt < 6_500));
}

export interface SelectionPolicy {
  peers: Peer[];
  latest: Map<string, SelectionMetadata>;
  invalid: Map<string, number>;
}

export function initialPolicy(): SelectionPolicy {
  return { peers: [], latest: new Map(), invalid: new Map() };
}

/** Retain token watermarks until the view closes, even if a peer expires. */
export function reconcile(state: SelectionPolicy, peers: Peer[], brief: BriefShape): SelectionPolicy {
  const latest = new Map(state.latest);
  const invalid = new Map(state.invalid);
  const visible = peers.map((peer) => {
    const previous = latest.get(peer.sessionId);
    const metadata = previous && previous.token >= peer.metadata.token ? previous : peer.metadata;
    latest.set(peer.sessionId, metadata);
    if (metadata.selected && !available(metadata.selected, brief)) {
      invalid.set(peer.sessionId, metadata.token);
    }
    return {
      sessionId: peer.sessionId,
      metadata: metadata.token <= (invalid.get(peer.sessionId) ?? -1)
        ? { ...metadata, selected: null } : metadata,
    };
  });
  // Invalidate cached selections even when the driver has just removed a peer.
  for (const [id, metadata] of latest) {
    if (metadata.selected && !available(metadata.selected, brief)) invalid.set(id, metadata.token);
  }
  return { peers: visible, latest, invalid };
}

const signalName = "project-brief-selection";

// docs:snippet-start project-brief-fluid-presence
/** Experimental Fluid Signaler; no document/tree writes belong in this adapter. */
export function startPresence(
  signaler: ISignaler,
  container: IFluidContainer,
  initial: SelectionMetadata,
  onPeers: (peers: Peer[]) => void,
  onError: (error: unknown) => void,
): PresenceSession {
  let metadata = decode(initial);
  let peers = new Map<string, SeenPeer>();
  let stopped = false;
  const connected = () => container.connectionState === ConnectionState.Connected;
  const publish = () => {
    if (!stopped) onPeers(Array.from(peers, ([sessionId, peer]) => ({ sessionId, metadata: peer.metadata })));
  };
  const send = () => {
    if (stopped || !connected()) return;
    try { signaler.submitSignal(signalName, encode(metadata)); }
    catch (error) { onError(error); }
  };
  const listener: SignalListener<unknown> = (clientId, local, payload) => {
    if (stopped || !connected() || local) return;
    try {
      if (typeof clientId !== "string" || clientId.length === 0) throw new Error("Missing signal sender");
      peers = receive(peers, clientId, decode(payload), performance.now());
    } catch (error) { onError(error); return; }
    publish();
  };
  const disconnected = () => {
    if (stopped) return;
    peers = new Map();
    publish();
  };
  signaler.onSignal(signalName, listener);
  container.on("connected", send);
  container.on("disconnected", disconnected);
  const timer = setInterval(() => {
    if (stopped || !connected()) return;
    peers = expire(peers, performance.now());
    publish();
    send();
  }, 2_000);
  send();
  return {
    update(next) {
      if (stopped) return;
      try {
        const value = decode(next);
        if (value.token < metadata.token) throw new Error("Selection token regressed");
        if (value.token === metadata.token &&
            JSON.stringify(value.selected) !== JSON.stringify(metadata.selected)) {
          throw new Error("Selection changed without a new token");
        }
        metadata = value;
      } catch (error) { onError(error); return; }
      send();
    },
    stop() {
      if (stopped) return;
      stopped = true;
      clearInterval(timer);
      signaler.offSignal(signalName, listener);
      container.off("connected", send);
      container.off("disconnected", disconnected);
      peers.clear();
    },
  };
}
// docs:snippet-end project-brief-fluid-presence
