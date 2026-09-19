import type * as $error from "../../gluegun/gluegun/error.d.mts";
import type * as $websocket from "../../gluegun/gluegun/websocket.d.mts";
import type * as $error from "../aquamarine/error.d.mts";
import type * as _ from "../gleam.d.mts";

export class Text extends _.CustomType {
  /** @deprecated */
  constructor(text: string);
  /** @deprecated */
  text: string;
}
export function Frame$Text(text: string): Frame$;
export function Frame$isText(value: any): value is Frame$;
export function Frame$Text$0(value: Frame$): string;
export function Frame$Text$text(value: Frame$): string;

export class Binary extends _.CustomType {
  /** @deprecated */
  constructor(data: _.BitArray);
  /** @deprecated */
  data: _.BitArray;
}
export function Frame$Binary(data: _.BitArray): Frame$;
export function Frame$isBinary(value: any): value is Frame$;
export function Frame$Binary$0(value: Frame$): _.BitArray;
export function Frame$Binary$data(value: Frame$): _.BitArray;

export class Closed extends _.CustomType {}
export function Frame$Closed(): Frame$;
export function Frame$isClosed(value: any): value is Frame$;

export type Frame$ = Text | Binary | Closed;

export class Transport extends _.CustomType {
  /** @deprecated */
  constructor(
    send_text: (x0: string) => _.Result<undefined, $error.AquamarineError$>,
    receive: () => _.Result<Frame$, $error.AquamarineError$>,
    close: () => _.Result<undefined, $error.AquamarineError$>
  );
  /** @deprecated */
  send_text: (x0: string) => _.Result<undefined, $error.AquamarineError$>;
  /** @deprecated */
  receive: () => _.Result<Frame$, $error.AquamarineError$>;
  /** @deprecated */
  close: () => _.Result<undefined, $error.AquamarineError$>;
}
export function Transport$Transport(
  send_text: (x0: string) => _.Result<undefined, $error.AquamarineError$>,
  receive: () => _.Result<Frame$, $error.AquamarineError$>,
  close: () => _.Result<undefined, $error.AquamarineError$>,
): Transport$;
export function Transport$isTransport(value: any): value is Transport$;
export function Transport$Transport$0(value: Transport$): (x0: string) => _.Result<
  undefined,
  $error.AquamarineError$
>;
export function Transport$Transport$send_text(value: Transport$): (x0: string) => _.Result<
  undefined,
  $error.AquamarineError$
>;
export function Transport$Transport$1(value: Transport$): () => _.Result<
  Frame$,
  $error.AquamarineError$
>;
export function Transport$Transport$receive(value: Transport$): () => _.Result<
  Frame$,
  $error.AquamarineError$
>;
export function Transport$Transport$2(value: Transport$): () => _.Result<
  undefined,
  $error.AquamarineError$
>;
export function Transport$Transport$close(value: Transport$): () => _.Result<
  undefined,
  $error.AquamarineError$
>;

export type Transport$ = Transport;

export type Connector = () => _.Result<Transport$, $error.AquamarineError$>;

export function from_gluegun(err: $gluegun_error.GluegunError$): $error.AquamarineError$;

export function gluegun_connector(host: string, port: number, path: string): () => _.Result<
  Transport$,
  $error.AquamarineError$
>;
