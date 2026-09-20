import { resultValue } from "./gleam-interop.ts";
import { json, sluice, watershed } from "./generated-runtime.ts";

type GeneratedDocument = ReturnType<typeof sluice.connect>;
type GeneratedServer = ReturnType<typeof sluice.start>;

declare const demoDocumentBrand: unique symbol;
declare const demoServerBrand: unique symbol;

export type DemoDocument = {
  readonly [demoDocumentBrand]: never;
};
export type DemoServer = {
  readonly [demoServerBrand]: never;
};
export interface DemoDelivery {
  author: string;
  event: string;
  sequence_number: number;
  to: string;
}

export function startNetwork(tenant: string, document: string): DemoServer {
  return demoServer(sluice.start(tenant, document));
}

export function connectClient(
  server: DemoServer,
  id: string,
): DemoDocument {
  return demoDocument(sluice.connect(generatedServer(server), id));
}

export function settleNetwork(server: DemoServer): void {
  sluice.settle(generatedServer(server));
}

export function networkPending(server: DemoServer): boolean {
  return sluice.pending(generatedServer(server));
}

export function sequenceNumber(server: DemoServer): number {
  return sluice.sequence_number(generatedServer(server));
}

export function clientId(
  server: DemoServer,
  document: DemoDocument,
): string | null {
  return resultValue(
    sluice.client_id(generatedServer(server), generatedDocument(document)),
  );
}

export function peekDelivery(server: DemoServer): DemoDelivery | null {
  return deliveryValue(sluice.peek_info(generatedServer(server)));
}

export function stepDelivery(server: DemoServer): DemoDelivery | null {
  return deliveryValue(sluice.step_info(generatedServer(server)));
}

export function writeSequenceMarker(
  document: DemoDocument,
  value: number,
): void {
  watershed.set(
    watershed.root(generatedDocument(document)),
    "__atlas_sequence__",
    json.int(value),
  );
}

function demoDocument(document: GeneratedDocument): DemoDocument {
  return document as unknown as DemoDocument;
}

function demoServer(server: GeneratedServer): DemoServer {
  return server as unknown as DemoServer;
}

function generatedDocument(document: DemoDocument): GeneratedDocument {
  return document as unknown as GeneratedDocument;
}

function generatedServer(server: DemoServer): GeneratedServer {
  return server as unknown as GeneratedServer;
}

function deliveryValue(
  result: ReturnType<typeof sluice.peek_info>,
): DemoDelivery | null {
  const delivery = resultValue(result);
  if (delivery === null) return null;
  return {
    author: delivery.author,
    event: delivery.event,
    sequence_number: delivery.sequence_number,
    to: delivery.to,
  };
}
