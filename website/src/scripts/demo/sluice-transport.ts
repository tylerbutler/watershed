import {
  resultValue,
  sluice,
  type ResultValue,
} from "./generated-runtime.ts";

export type SluiceDocument = ReturnType<typeof sluice.connect>;
export type SluiceServer = ReturnType<typeof sluice.start>;
export type SluiceDelivery =
  ResultValue<ReturnType<typeof sluice.peek_info>>;

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

export function createSluiceNetwork(
  options: CreateSluiceNetworkOptions,
): SluiceNetwork {
  const server = sluice.start(options.tenant, options.document);
  const documents: Record<string, SluiceDocument> = {};
  for (const id of options.clientIds) {
    documents[id] = sluice.connect(server, options.connectId?.(id) ?? id);
  }
  sluice.settle(server);

  const sidToId: Record<string, string> = {};
  for (const id of options.clientIds) {
    const sid = resultValue(sluice.client_id(server, documents[id]));
    if (sid !== null) sidToId[sid] = id;
  }
  return { server, documents, sidToId };
}

export function peekDelivery(network: SluiceNetwork): SluiceDelivery | null {
  return resultValue(sluice.peek_info(network.server));
}

export function stepDelivery(network: SluiceNetwork): SluiceDelivery | null {
  return resultValue(sluice.step_info(network.server));
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
): SluiceDelivery[] {
  const deliveries: SluiceDelivery[] = [];
  let guard = 0;
  while (peekDelivery(network) !== null && guard < 20_000) {
    deliveries.push(...stepDeliveryWave(network, beforeDelivery));
    guard += 1;
  }
  if (peekDelivery(network) !== null) {
    throw new Error("Sluice delivery drain exceeded 20000 waves");
  }
  return deliveries;
}
