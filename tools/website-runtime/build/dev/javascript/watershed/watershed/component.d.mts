import type * as $json from "../../gleam_json/gleam/json.d.mts";
import type * as $dict from "../../gleam_stdlib/gleam/dict.d.mts";
import type * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.d.mts";
import type * as $option from "../../gleam_stdlib/gleam/option.d.mts";
import type * as _ from "../gleam.d.mts";
import type * as $port from "../watershed/port.d.mts";

export class InvalidConfig extends _.CustomType {
  /** @deprecated */
  constructor(kind: string, version: number, reason: $json.DecodeError$);
  /** @deprecated */
  kind: string;
  /** @deprecated */
  version: number;
  /** @deprecated */
  reason: $json.DecodeError$;
}
export function ComponentError$InvalidConfig(
  kind: string,
  version: number,
  reason: $json.DecodeError$,
): ComponentError$;
export function ComponentError$isInvalidConfig(
  value: any,
): value is ComponentError$;
export function ComponentError$InvalidConfig$0(value: ComponentError$): string;
export function ComponentError$InvalidConfig$kind(value: ComponentError$): string;
export function ComponentError$InvalidConfig$1(
  value: ComponentError$,
): number;
export function ComponentError$InvalidConfig$version(value: ComponentError$): number;
export function ComponentError$InvalidConfig$2(
  value: ComponentError$,
): $json.DecodeError$;
export function ComponentError$InvalidConfig$reason(value: ComponentError$): $json.DecodeError$;

export class StartFailed extends _.CustomType {
  /** @deprecated */
  constructor(kind: string, version: number, reason: string);
  /** @deprecated */
  kind: string;
  /** @deprecated */
  version: number;
  /** @deprecated */
  reason: string;
}
export function ComponentError$StartFailed(
  kind: string,
  version: number,
  reason: string,
): ComponentError$;
export function ComponentError$isStartFailed(
  value: any,
): value is ComponentError$;
export function ComponentError$StartFailed$0(value: ComponentError$): string;
export function ComponentError$StartFailed$kind(value: ComponentError$): string;
export function ComponentError$StartFailed$1(value: ComponentError$): number;
export function ComponentError$StartFailed$version(value: ComponentError$): number;
export function ComponentError$StartFailed$2(
  value: ComponentError$,
): string;
export function ComponentError$StartFailed$reason(value: ComponentError$): string;

export class InputUnavailable extends _.CustomType {
  /** @deprecated */
  constructor(kind: string, version: number, input_id: string);
  /** @deprecated */
  kind: string;
  /** @deprecated */
  version: number;
  /** @deprecated */
  input_id: string;
}
export function ComponentError$InputUnavailable(
  kind: string,
  version: number,
  input_id: string,
): ComponentError$;
export function ComponentError$isInputUnavailable(
  value: any,
): value is ComponentError$;
export function ComponentError$InputUnavailable$0(value: ComponentError$): string;
export function ComponentError$InputUnavailable$kind(
  value: ComponentError$,
): string;
export function ComponentError$InputUnavailable$1(value: ComponentError$): number;
export function ComponentError$InputUnavailable$version(
  value: ComponentError$,
): number;
export function ComponentError$InputUnavailable$2(value: ComponentError$): string;
export function ComponentError$InputUnavailable$input_id(
  value: ComponentError$,
): string;

export class InvalidInputPayload extends _.CustomType {
  /** @deprecated */
  constructor(
    kind: string,
    version: number,
    input_id: string,
    reason: $port.PortError$
  );
  /** @deprecated */
  kind: string;
  /** @deprecated */
  version: number;
  /** @deprecated */
  input_id: string;
  /** @deprecated */
  reason: $port.PortError$;
}
export function ComponentError$InvalidInputPayload(
  kind: string,
  version: number,
  input_id: string,
  reason: $port.PortError$,
): ComponentError$;
export function ComponentError$isInvalidInputPayload(
  value: any,
): value is ComponentError$;
export function ComponentError$InvalidInputPayload$0(value: ComponentError$): string;
export function ComponentError$InvalidInputPayload$kind(
  value: ComponentError$,
): string;
export function ComponentError$InvalidInputPayload$1(value: ComponentError$): number;
export function ComponentError$InvalidInputPayload$version(
  value: ComponentError$,
): number;
export function ComponentError$InvalidInputPayload$2(value: ComponentError$): string;
export function ComponentError$InvalidInputPayload$input_id(
  value: ComponentError$,
): string;
export function ComponentError$InvalidInputPayload$3(value: ComponentError$): $port.PortError$;
export function ComponentError$InvalidInputPayload$reason(
  value: ComponentError$,
): $port.PortError$;

export class InputFailed extends _.CustomType {
  /** @deprecated */
  constructor(kind: string, version: number, input_id: string, reason: string);
  /** @deprecated */
  kind: string;
  /** @deprecated */
  version: number;
  /** @deprecated */
  input_id: string;
  /** @deprecated */
  reason: string;
}
export function ComponentError$InputFailed(
  kind: string,
  version: number,
  input_id: string,
  reason: string,
): ComponentError$;
export function ComponentError$isInputFailed(
  value: any,
): value is ComponentError$;
export function ComponentError$InputFailed$0(value: ComponentError$): string;
export function ComponentError$InputFailed$kind(value: ComponentError$): string;
export function ComponentError$InputFailed$1(value: ComponentError$): number;
export function ComponentError$InputFailed$version(value: ComponentError$): number;
export function ComponentError$InputFailed$2(
  value: ComponentError$,
): string;
export function ComponentError$InputFailed$input_id(value: ComponentError$): string;
export function ComponentError$InputFailed$3(
  value: ComponentError$,
): string;
export function ComponentError$InputFailed$reason(value: ComponentError$): string;

export class OutputUnavailable extends _.CustomType {
  /** @deprecated */
  constructor(kind: string, version: number, output_id: string);
  /** @deprecated */
  kind: string;
  /** @deprecated */
  version: number;
  /** @deprecated */
  output_id: string;
}
export function ComponentError$OutputUnavailable(
  kind: string,
  version: number,
  output_id: string,
): ComponentError$;
export function ComponentError$isOutputUnavailable(
  value: any,
): value is ComponentError$;
export function ComponentError$OutputUnavailable$0(value: ComponentError$): string;
export function ComponentError$OutputUnavailable$kind(
  value: ComponentError$,
): string;
export function ComponentError$OutputUnavailable$1(value: ComponentError$): number;
export function ComponentError$OutputUnavailable$version(
  value: ComponentError$,
): number;
export function ComponentError$OutputUnavailable$2(value: ComponentError$): string;
export function ComponentError$OutputUnavailable$output_id(
  value: ComponentError$,
): string;

export class StopFailed extends _.CustomType {
  /** @deprecated */
  constructor(kind: string, version: number, reason: string);
  /** @deprecated */
  kind: string;
  /** @deprecated */
  version: number;
  /** @deprecated */
  reason: string;
}
export function ComponentError$StopFailed(
  kind: string,
  version: number,
  reason: string,
): ComponentError$;
export function ComponentError$isStopFailed(
  value: any,
): value is ComponentError$;
export function ComponentError$StopFailed$0(value: ComponentError$): string;
export function ComponentError$StopFailed$kind(value: ComponentError$): string;
export function ComponentError$StopFailed$1(value: ComponentError$): number;
export function ComponentError$StopFailed$version(value: ComponentError$): number;
export function ComponentError$StopFailed$2(
  value: ComponentError$,
): string;
export function ComponentError$StopFailed$reason(value: ComponentError$): string;

export type ComponentError$ = InvalidConfig | StartFailed | InputUnavailable | InvalidInputPayload | InputFailed | OutputUnavailable | StopFailed;

export function ComponentError$kind(value: ComponentError$): string;
export function ComponentError$version(value: ComponentError$): number;

export class DuplicateRegistration extends _.CustomType {
  /** @deprecated */
  constructor(kind: string, version: number);
  /** @deprecated */
  kind: string;
  /** @deprecated */
  version: number;
}
export function RegistrationError$DuplicateRegistration(
  kind: string,
  version: number,
): RegistrationError$;
export function RegistrationError$isDuplicateRegistration(
  value: any,
): value is RegistrationError$;
export function RegistrationError$DuplicateRegistration$0(value: RegistrationError$): string;
export function RegistrationError$DuplicateRegistration$kind(
  value: RegistrationError$,
): string;
export function RegistrationError$DuplicateRegistration$1(value: RegistrationError$): number;
export function RegistrationError$DuplicateRegistration$version(
  value: RegistrationError$,
): number;

export type RegistrationError$ = DuplicateRegistration;

export class NotRegistered extends _.CustomType {
  /** @deprecated */
  constructor(kind: string);
  /** @deprecated */
  kind: string;
}
export function LookupError$NotRegistered(kind: string): LookupError$;
export function LookupError$isNotRegistered(value: any): value is LookupError$;
export function LookupError$NotRegistered$0(value: LookupError$): string;
export function LookupError$NotRegistered$kind(value: LookupError$): string;

export class UnsupportedVersion extends _.CustomType {
  /** @deprecated */
  constructor(kind: string, requested: number, available: _.List<number>);
  /** @deprecated */
  kind: string;
  /** @deprecated */
  requested: number;
  /** @deprecated */
  available: _.List<number>;
}
export function LookupError$UnsupportedVersion(
  kind: string,
  requested: number,
  available: _.List<number>,
): LookupError$;
export function LookupError$isUnsupportedVersion(
  value: any,
): value is LookupError$;
export function LookupError$UnsupportedVersion$0(value: LookupError$): string;
export function LookupError$UnsupportedVersion$kind(value: LookupError$): string;
export function LookupError$UnsupportedVersion$1(
  value: LookupError$,
): number;
export function LookupError$UnsupportedVersion$requested(value: LookupError$): number;
export function LookupError$UnsupportedVersion$2(
  value: LookupError$,
): _.List<number>;
export function LookupError$UnsupportedVersion$available(value: LookupError$): _.List<
  number
>;

export type LookupError$ = NotRegistered | UnsupportedVersion;

export function LookupError$kind(value: LookupError$): string;

declare class OutputEvent extends _.CustomType {
  /** @deprecated */
  constructor(id: string, schema_id: string, payload: $json.Json$);
  /** @deprecated */
  id: string;
  /** @deprecated */
  schema_id: string;
  /** @deprecated */
  payload: $json.Json$;
}

export type OutputEvent$ = OutputEvent;

declare class OutputEmitter extends _.CustomType {
  /** @deprecated */
  constructor(publish: (x0: _.List<OutputEvent$>) => undefined);
  /** @deprecated */
  publish: (x0: _.List<OutputEvent$>) => undefined;
}

export type OutputEmitter$ = OutputEmitter;

declare class InputHandler<BKIV> extends _.CustomType {
  /** @deprecated */
  constructor(
    descriptor: $port.Descriptor$,
    deliver: (x0: BKIV, x1: $json.Json$) => _.Result<
      [BKIV, _.List<OutputEvent$>],
      InputHandlerError$
    >
  );
  /** @deprecated */
  descriptor: $port.Descriptor$;
  /** @deprecated */
  deliver: (x0: BKIV, x1: $json.Json$) => _.Result<
    [BKIV, _.List<OutputEvent$>],
    InputHandlerError$
  >;
}

export type InputHandler$<BKIV> = InputHandler<BKIV>;

declare class HandlerInvalidPayload extends _.CustomType {
  /** @deprecated */
  constructor(reason: $port.PortError$);
  /** @deprecated */
  reason: $port.PortError$;
}

declare class HandlerFailed extends _.CustomType {
  /** @deprecated */
  constructor(reason: string);
  /** @deprecated */
  reason: string;
}

type InputHandlerError$ = HandlerInvalidPayload | HandlerFailed;

declare class Descriptor<BKIW, BKIX> extends _.CustomType {
  /** @deprecated */
  constructor(
    kind: string,
    version: number,
    ports: _.List<$port.Descriptor$>,
    validate_config: (x0: $json.Json$) => _.Result<undefined, ComponentError$>,
    start: (
      x0: BKIW,
      x1: $json.Json$,
      x2: (x0: _.Result<BKIX, ComponentError$>) => undefined
    ) => undefined,
    inputs: _.List<InputHandler$<BKIX>>,
    stop: (x0: BKIX) => _.Result<undefined, ComponentError$>
  );
  /** @deprecated */
  kind: string;
  /** @deprecated */
  version: number;
  /** @deprecated */
  ports: _.List<$port.Descriptor$>;
  /** @deprecated */
  validate_config: (x0: $json.Json$) => _.Result<undefined, ComponentError$>;
  /** @deprecated */
  start: (
    x0: BKIW,
    x1: $json.Json$,
    x2: (x0: _.Result<BKIX, ComponentError$>) => undefined
  ) => undefined;
  /** @deprecated */
  inputs: _.List<InputHandler$<BKIX>>;
  /** @deprecated */
  stop: (x0: BKIX) => _.Result<undefined, ComponentError$>;
}

export type Descriptor$<BKIW, BKIX> = Descriptor<BKIW, BKIX>;

declare class Catalog<BKIY, BKIZ> extends _.CustomType {
  /** @deprecated */
  constructor(entries: $dict.Dict$<[string, number], Descriptor$<BKIY, BKIZ>>);
  /** @deprecated */
  entries: $dict.Dict$<[string, number], Descriptor$<BKIY, BKIZ>>;
}

export type Catalog$<BKIY, BKIZ> = Catalog<BKIY, BKIZ>;

export function executable_descriptor<BKJJ, BKJL, BKJM>(
  kind: string,
  version: number,
  config_decoder: $decode.Decoder$<BKJJ>,
  start_component: (
    x0: BKJL,
    x1: BKJJ,
    x2: (x0: _.Result<BKJM, string>) => undefined
  ) => undefined,
  inputs: _.List<InputHandler$<BKJM>>,
  stop_component: (x0: BKJM) => _.Result<undefined, string>,
  ports: _.List<$port.Descriptor$>
): Descriptor$<BKJL, BKJM>;

export function descriptor<BKJA, BKJC, BKJD>(
  kind: string,
  version: number,
  config_decoder: $decode.Decoder$<BKJA>,
  start_component: (x0: BKJC, x1: BKJA) => _.Result<BKJD, string>,
  ports: _.List<$port.Descriptor$>
): Descriptor$<BKJC, BKJD>;

export function input_handler<BKJW, BKJY>(
  input: $port.Input$<BKJW>,
  handle: (x0: BKJY, x1: BKJW) => _.Result<[BKJY, _.List<OutputEvent$>], string>
): InputHandler$<BKJY>;

export function emit<BKKD>(output: $port.Output$<BKKD>, payload: BKKD): OutputEvent$;

export function output_emitter(publish: (x0: _.List<OutputEvent$>) => undefined): OutputEmitter$;

export function publish(emitter: OutputEmitter$, events: _.List<OutputEvent$>): undefined;

export function output_id(event: OutputEvent$): string;

export function output_payload(event: OutputEvent$): $json.Json$;

export function kind(descriptor: Descriptor$<any, any>): string;

export function version(descriptor: Descriptor$<any, any>): number;

export function ports(descriptor: Descriptor$<any, any>): _.List<
  $port.Descriptor$
>;

export function validate_config(
  descriptor: Descriptor$<any, any>,
  config: $json.Json$
): _.Result<undefined, ComponentError$>;

export function start<BKLA, BKLB>(
  descriptor: Descriptor$<BKLA, BKLB>,
  context: BKLA,
  config: $json.Json$,
  done: (x0: _.Result<BKLB, ComponentError$>) => undefined
): undefined;

export function deliver<BKLH>(
  descriptor: Descriptor$<any, BKLH>,
  running: BKLH,
  input_id: string,
  payload: $json.Json$
): _.Result<[BKLH, _.List<OutputEvent$>], ComponentError$>;

export function validate_output(
  descriptor: Descriptor$<any, any>,
  event: OutputEvent$
): _.Result<undefined, ComponentError$>;

export function stop<BKLU>(descriptor: Descriptor$<any, BKLU>, running: BKLU): _.Result<
  undefined,
  ComponentError$
>;

export function new_catalog(): Catalog$<any, any>;

export function register<BKMD, BKME>(
  catalog: Catalog$<BKMD, BKME>,
  descriptor: Descriptor$<BKMD, BKME>
): _.Result<Catalog$<BKMD, BKME>, RegistrationError$>;

export function find<BKMN, BKMO>(
  catalog: Catalog$<BKMN, BKMO>,
  kind: string,
  version: number
): _.Result<Descriptor$<BKMN, BKMO>, LookupError$>;
