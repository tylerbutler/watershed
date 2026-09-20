import type {
  DemoDelivery,
  DemoDocument,
  DemoServer,
} from "./sluice-runtime.ts";
import {
  clientId,
  connectClient,
  networkPending,
  peekDelivery,
  sequenceNumber as readSequenceNumber,
  settleNetwork,
  startNetwork,
  stepDelivery,
  writeSequenceMarker,
} from "./sluice-runtime.ts";
import * as sluiceRuntime from "./sluice-runtime.ts";
import type { ResultValue } from "./gleam-interop.ts";
import { sluice } from "./generated-runtime.ts";

type IsAny<Value> = 0 extends (1 & Value) ? true : false;
type IsEqual<Left, Right> =
  (<Value>() => Value extends Left ? 1 : 2) extends
  (<Value>() => Value extends Right ? 1 : 2)
    ? true
    : false;
type AssertFalse<Value extends false> = Value;

type GeneratedServer = ReturnType<typeof sluice.start>;
type GeneratedDocument = ReturnType<typeof sluice.connect>;
type GeneratedDelivery = ResultValue<ReturnType<typeof sluice.peek_info>>;

type ServerIsAuthored = AssertFalse<IsEqual<DemoServer, GeneratedServer>>;
type DocumentIsAuthored = AssertFalse<IsEqual<DemoDocument, GeneratedDocument>>;
type DeliveryIsAuthored = AssertFalse<IsEqual<DemoDelivery, GeneratedDelivery>>;
type DeliveryIsTyped = AssertFalse<IsAny<DemoDelivery>>;

declare const delivery: DemoDelivery;
declare const document: DemoDocument;
declare const server: DemoServer;
const event: string = delivery.event;
const sequenceNumber: number = delivery.sequence_number;
const author: string = delivery.author;
const to: string = delivery.to;

const startedServer: DemoServer = startNetwork("tenant", "document");
const connectedDocument: DemoDocument = connectClient(server, "client");
settleNetwork(server);
const pending: boolean = networkPending(server);
const sequence: number = readSequenceNumber(server);
const connectedClientId: string | null = clientId(server, document);
const peekedDelivery: DemoDelivery | null = peekDelivery(server);
const steppedDelivery: DemoDelivery | null = stepDelivery(server);
writeSequenceMarker(document, 1);

// @ts-expect-error The shared adapter does not expose raw generated documents.
sluiceRuntime.withDocument;
// @ts-expect-error DemoServer does not expose generated cell state.
server.cell;
// @ts-expect-error DemoServer does not expose the generated tenant field.
server.tenant;
// @ts-expect-error DemoServer does not expose the generated document field.
server.document;
// @ts-expect-error DemoDocument does not expose the generated runtime field.
document.runtime;

void event;
void sequenceNumber;
void author;
void to;
void startedServer;
void connectedDocument;
void pending;
void sequence;
void connectedClientId;
void peekedDelivery;
void steppedDelivery;
void (null as unknown as ServerIsAuthored);
void (null as unknown as DocumentIsAuthored);
void (null as unknown as DeliveryIsAuthored);
void (null as unknown as DeliveryIsTyped);
