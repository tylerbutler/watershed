import type * as $json from "../../gleam_json/gleam/json.d.mts";
import type * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.d.mts";
import type * as _ from "../gleam.d.mts";

export class LocalInput extends _.CustomType {}
export function InputClass$LocalInput(): InputClass$;
export function InputClass$isLocalInput(value: any): value is InputClass$;

export class CollaborativeInput extends _.CustomType {
  /** @deprecated */
  constructor(capabilities: _.List<string>);
  /** @deprecated */
  capabilities: _.List<string>;
}
export function InputClass$CollaborativeInput(
  capabilities: _.List<string>,
): InputClass$;
export function InputClass$isCollaborativeInput(
  value: any,
): value is InputClass$;
export function InputClass$CollaborativeInput$0(value: InputClass$): _.List<
  string
>;
export function InputClass$CollaborativeInput$capabilities(value: InputClass$): _.List<
  string
>;

export type InputClass$ = LocalInput | CollaborativeInput;

export class OutputPort extends _.CustomType {}
export function Direction$OutputPort(): Direction$;
export function Direction$isOutputPort(value: any): value is Direction$;

export class InputPort extends _.CustomType {
  /** @deprecated */
  constructor(class$: InputClass$);
  /** @deprecated */
  class: InputClass$;
}
export function Direction$InputPort(class$: InputClass$): Direction$;
export function Direction$isInputPort(value: any): value is Direction$;
export function Direction$InputPort$0(value: Direction$): InputClass$;
export function Direction$InputPort$class(value: Direction$): InputClass$;

export type Direction$ = OutputPort | InputPort;

export class OutputDirection extends _.CustomType {}
export function DirectionKind$OutputDirection(): DirectionKind$;
export function DirectionKind$isOutputDirection(
  value: any,
): value is DirectionKind$;

export class InputDirection extends _.CustomType {}
export function DirectionKind$InputDirection(): DirectionKind$;
export function DirectionKind$isInputDirection(
  value: any,
): value is DirectionKind$;

export type DirectionKind$ = OutputDirection | InputDirection;

export class Descriptor extends _.CustomType {
  /** @deprecated */
  constructor(id: string, direction: Direction$, schema_id: string);
  /** @deprecated */
  id: string;
  /** @deprecated */
  direction: Direction$;
  /** @deprecated */
  schema_id: string;
}
export function Descriptor$Descriptor(
  id: string,
  direction: Direction$,
  schema_id: string,
): Descriptor$;
export function Descriptor$isDescriptor(value: any): value is Descriptor$;
export function Descriptor$Descriptor$0(value: Descriptor$): string;
export function Descriptor$Descriptor$id(value: Descriptor$): string;
export function Descriptor$Descriptor$1(value: Descriptor$): Direction$;
export function Descriptor$Descriptor$direction(value: Descriptor$): Direction$;
export function Descriptor$Descriptor$2(value: Descriptor$): string;
export function Descriptor$Descriptor$schema_id(value: Descriptor$): string;

export type Descriptor$ = Descriptor;

declare class Output<BKGL> extends _.CustomType {
  /** @deprecated */
  constructor(id: string, schema_id: string, encode: (x0: BKGL) => $json.Json$);
  /** @deprecated */
  id: string;
  /** @deprecated */
  schema_id: string;
  /** @deprecated */
  encode: (x0: BKGL) => $json.Json$;
}

export type Output$<BKGL> = Output<BKGL>;

declare class Input<BKGM> extends _.CustomType {
  /** @deprecated */
  constructor(
    id: string,
    schema_id: string,
    decode: $decode.Decoder$<BKGM>,
    input_class: InputClass$
  );
  /** @deprecated */
  id: string;
  /** @deprecated */
  schema_id: string;
  /** @deprecated */
  decode: $decode.Decoder$<BKGM>;
  /** @deprecated */
  input_class: InputClass$;
}

export type Input$<BKGM> = Input<BKGM>;

export class ConnectionTemplate extends _.CustomType {
  /** @deprecated */
  constructor(source_port: string, target_port: string, schema_id: string);
  /** @deprecated */
  source_port: string;
  /** @deprecated */
  target_port: string;
  /** @deprecated */
  schema_id: string;
}
export function ConnectionTemplate$ConnectionTemplate(
  source_port: string,
  target_port: string,
  schema_id: string,
): ConnectionTemplate$;
export function ConnectionTemplate$isConnectionTemplate(
  value: any,
): value is ConnectionTemplate$;
export function ConnectionTemplate$ConnectionTemplate$0(value: ConnectionTemplate$): string;
export function ConnectionTemplate$ConnectionTemplate$source_port(
  value: ConnectionTemplate$,
): string;
export function ConnectionTemplate$ConnectionTemplate$1(value: ConnectionTemplate$): string;
export function ConnectionTemplate$ConnectionTemplate$target_port(
  value: ConnectionTemplate$,
): string;
export function ConnectionTemplate$ConnectionTemplate$2(value: ConnectionTemplate$): string;
export function ConnectionTemplate$ConnectionTemplate$schema_id(
  value: ConnectionTemplate$,
): string;

export type ConnectionTemplate$ = ConnectionTemplate;

export class InvalidPayload extends _.CustomType {
  /** @deprecated */
  constructor(reason: $json.DecodeError$);
  /** @deprecated */
  reason: $json.DecodeError$;
}
export function PortError$InvalidPayload(
  reason: $json.DecodeError$,
): PortError$;
export function PortError$isInvalidPayload(value: any): value is PortError$;
export function PortError$InvalidPayload$0(value: PortError$): $json.DecodeError$;
export function PortError$InvalidPayload$reason(
  value: PortError$,
): $json.DecodeError$;

export class SchemaMismatch extends _.CustomType {
  /** @deprecated */
  constructor(source: string, target: string);
  /** @deprecated */
  source: string;
  /** @deprecated */
  target: string;
}
export function PortError$SchemaMismatch(
  source: string,
  target: string,
): PortError$;
export function PortError$isSchemaMismatch(value: any): value is PortError$;
export function PortError$SchemaMismatch$0(value: PortError$): string;
export function PortError$SchemaMismatch$source(value: PortError$): string;
export function PortError$SchemaMismatch$1(value: PortError$): string;
export function PortError$SchemaMismatch$target(value: PortError$): string;

export type PortError$ = InvalidPayload | SchemaMismatch;

export function output<BKGN>(
  id: string,
  schema_id: string,
  encode: (x0: BKGN) => $json.Json$
): Output$<BKGN>;

export function local_input<BKGP>(
  id: string,
  schema_id: string,
  decoder: $decode.Decoder$<BKGP>
): Input$<BKGP>;

export function collaborative_input<BKGS>(
  id: string,
  schema_id: string,
  decoder: $decode.Decoder$<BKGS>,
  capabilities: _.List<string>
): Input$<BKGS>;

export function direction_kind(direction: Direction$): DirectionKind$;

export function output_descriptor(output: Output$<any>): Descriptor$;

export function input_descriptor(input: Input$<any>): Descriptor$;

export function encode<BKHA>(output: Output$<BKHA>, payload: BKHA): $json.Json$;

export function decode<BKHC>(input: Input$<BKHC>, payload: $json.Json$): _.Result<
  BKHC,
  PortError$
>;

export function connect<BKHG>(output: Output$<BKHG>, input: Input$<BKHG>): _.Result<
  ConnectionTemplate$,
  PortError$
>;
