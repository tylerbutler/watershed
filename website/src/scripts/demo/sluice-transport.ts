import {
  clientId,
  connectClient,
  peekDelivery as peekRuntimeDelivery,
  settleNetwork,
  startNetwork,
  stepDelivery as stepRuntimeDelivery,
  type DemoDelivery,
  type DemoDocument,
  type DemoServer,
} from "./sluice-runtime.ts";

export type SluiceDocument = DemoDocument;
export type SluiceServer = DemoServer;
export type SluiceDelivery = DemoDelivery;

export interface SluiceNetwork {
  server: SluiceServer;
  documents: Record<string, SluiceDocument>;
  sidToId: Record<string, string>;
}

export interface CreateSluiceNetworkOptions {
  tenant: string;
  document: string;
  clientIds: readonly string[];
  connectId?: (id: string) => string;
}

export interface DeliveryScheduler {
  now(): number;
  set(delayMs: number, callback: () => void): unknown;
  clear(handle: unknown): void;
}

export interface DeliveryEngine {
  readonly pending: boolean;
  schedule(delayMs: number): void;
  step(): SluiceDelivery[];
  settle(): SluiceDelivery[];
  reset(network: SluiceNetwork): void;
  cancel(): void;
}

export function createSluiceNetwork(
  options: CreateSluiceNetworkOptions,
): SluiceNetwork {
  const server = startNetwork(options.tenant, options.document);
  const documents: Record<string, SluiceDocument> = {};
  for (const id of options.clientIds) {
    documents[id] = connectClient(server, options.connectId?.(id) ?? id);
  }
  settleNetwork(server);

  const sidToId: Record<string, string> = {};
  for (const id of options.clientIds) {
    const sid = clientId(server, documents[id]);
    if (sid !== null) sidToId[sid] = id;
  }
  return { server, documents, sidToId };
}

export function peekDelivery(network: SluiceNetwork): SluiceDelivery | null {
  return peekRuntimeDelivery(network.server);
}

export function stepDelivery(network: SluiceNetwork): SluiceDelivery | null {
  return stepRuntimeDelivery(network.server);
}

export function stepDeliveryWave(
  network: SluiceNetwork,
  beforeDelivery?: (delivery: SluiceDelivery) => void,
): SluiceDelivery[] {
  const first = peekDelivery(network);
  if (first === null) return [];
  const deliveries: SluiceDelivery[] = [];
  const sequence = first.sequence_number;
  let next: SluiceDelivery | null = first;
  do {
    beforeDelivery?.(next);
    const delivery = stepDelivery(network);
    if (delivery === null) break;
    deliveries.push(delivery);
    next = peekDelivery(network);
  } while (
    first.event === "op" &&
    next !== null &&
    next.event === "op" &&
    next.sequence_number === sequence
  );
  return deliveries;
}

export function drainDeliveries(
  network: SluiceNetwork,
  beforeDelivery?: (delivery: SluiceDelivery) => void,
  onWave?: (deliveries: readonly SluiceDelivery[]) => void,
): SluiceDelivery[] {
  const deliveries: SluiceDelivery[] = [];
  let guard = 0;
  while (peekDelivery(network) !== null && guard < 20_000) {
    const wave = stepDeliveryWave(network, beforeDelivery);
    deliveries.push(...wave);
    onWave?.(wave);
    guard += 1;
  }
  if (peekDelivery(network) !== null) {
    throw new Error("Sluice delivery drain exceeded 20000 waves");
  }
  return deliveries;
}

export function createDeliveryEngine(options: {
  network: SluiceNetwork;
  scheduler: DeliveryScheduler;
  onBeforeDelivery?: (delivery: SluiceDelivery) => void;
  onWave: (deliveries: readonly SluiceDelivery[]) => void;
  onIdle?: () => void;
}): DeliveryEngine {
  let network = options.network;
  let timer: unknown | null = null;
  let settling = false;

  function cancel(): void {
    if (timer === null) return;
    options.scheduler.clear(timer);
    timer = null;
  }

  function deliverWave(): SluiceDelivery[] {
    const deliveries = stepDeliveryWave(network, options.onBeforeDelivery);
    if (deliveries.length > 0) options.onWave(deliveries);
    if (peekDelivery(network) === null) options.onIdle?.();
    return deliveries;
  }

  function schedule(delayMs: number): void {
    if (settling || timer !== null) return;
    if (peekDelivery(network) === null) {
      options.onIdle?.();
      return;
    }
    timer = options.scheduler.set(delayMs, () => {
      timer = null;
      deliverWave();
    });
  }

  return {
    get pending() {
      return timer !== null;
    },
    schedule,
    step() {
      cancel();
      return deliverWave();
    },
    settle() {
      cancel();
      settling = true;
      try {
        const deliveries = drainDeliveries(
          network,
          options.onBeforeDelivery,
          options.onWave,
        );
        options.onIdle?.();
        return deliveries;
      } finally {
        cancel();
        settling = false;
      }
    },
    reset(replacement) {
      cancel();
      network = replacement;
    },
    cancel,
  };
}
