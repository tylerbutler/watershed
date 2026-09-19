import type * as $json from "../../gleam_json/gleam/json.d.mts";
import type * as $dict from "../../gleam_stdlib/gleam/dict.d.mts";
import type * as _ from "../gleam.d.mts";

export class RegisterState extends _.CustomType {
  /** @deprecated */
  constructor(registers: $dict.Dict$<string, Register$>);
  /** @deprecated */
  registers: $dict.Dict$<string, Register$>;
}
export function RegisterState$RegisterState(
  registers: $dict.Dict$<string, Register$>,
): RegisterState$;
export function RegisterState$isRegisterState(
  value: any,
): value is RegisterState$;
export function RegisterState$RegisterState$0(value: RegisterState$): $dict.Dict$<
  string,
  Register$
>;
export function RegisterState$RegisterState$registers(value: RegisterState$): $dict.Dict$<
  string,
  Register$
>;

export type RegisterState$ = RegisterState;

export class Register extends _.CustomType {
  /** @deprecated */
  constructor(atomic: VersionedValue$, versions: _.List<VersionedValue$>);
  /** @deprecated */
  atomic: VersionedValue$;
  /** @deprecated */
  versions: _.List<VersionedValue$>;
}
export function Register$Register(
  atomic: VersionedValue$,
  versions: _.List<VersionedValue$>,
): Register$;
export function Register$isRegister(value: any): value is Register$;
export function Register$Register$0(value: Register$): VersionedValue$;
export function Register$Register$atomic(value: Register$): VersionedValue$;
export function Register$Register$1(value: Register$): _.List<VersionedValue$>;
export function Register$Register$versions(value: Register$): _.List<
  VersionedValue$
>;

export type Register$ = Register;

export class VersionedValue extends _.CustomType {
  /** @deprecated */
  constructor(value: $json.Json$, sequence_number: number);
  /** @deprecated */
  value: $json.Json$;
  /** @deprecated */
  sequence_number: number;
}
export function VersionedValue$VersionedValue(
  value: $json.Json$,
  sequence_number: number,
): VersionedValue$;
export function VersionedValue$isVersionedValue(
  value: any,
): value is VersionedValue$;
export function VersionedValue$VersionedValue$0(value: VersionedValue$): $json.Json$;
export function VersionedValue$VersionedValue$value(
  value: VersionedValue$,
): $json.Json$;
export function VersionedValue$VersionedValue$1(value: VersionedValue$): number;
export function VersionedValue$VersionedValue$sequence_number(value: VersionedValue$): number;

export type VersionedValue$ = VersionedValue;

export class Write extends _.CustomType {
  /** @deprecated */
  constructor(
    key: string,
    value: $json.Json$,
    reference_sequence_number: number
  );
  /** @deprecated */
  key: string;
  /** @deprecated */
  value: $json.Json$;
  /** @deprecated */
  reference_sequence_number: number;
}
export function WriteOperation$Write(
  key: string,
  value: $json.Json$,
  reference_sequence_number: number,
): WriteOperation$;
export function WriteOperation$isWrite(value: any): value is WriteOperation$;
export function WriteOperation$Write$0(value: WriteOperation$): string;
export function WriteOperation$Write$key(value: WriteOperation$): string;
export function WriteOperation$Write$1(value: WriteOperation$): $json.Json$;
export function WriteOperation$Write$value(value: WriteOperation$): $json.Json$;
export function WriteOperation$Write$2(value: WriteOperation$): number;
export function WriteOperation$Write$reference_sequence_number(value: WriteOperation$): number;

export type WriteOperation$ = Write;

export class AtomicChanged extends _.CustomType {
  /** @deprecated */
  constructor(key: string, value: $json.Json$, local: boolean);
  /** @deprecated */
  key: string;
  /** @deprecated */
  value: $json.Json$;
  /** @deprecated */
  local: boolean;
}
export function RegisterEvent$AtomicChanged(
  key: string,
  value: $json.Json$,
  local: boolean,
): RegisterEvent$;
export function RegisterEvent$isAtomicChanged(
  value: any,
): value is RegisterEvent$;
export function RegisterEvent$AtomicChanged$0(value: RegisterEvent$): string;
export function RegisterEvent$AtomicChanged$key(value: RegisterEvent$): string;
export function RegisterEvent$AtomicChanged$1(value: RegisterEvent$): $json.Json$;
export function RegisterEvent$AtomicChanged$value(
  value: RegisterEvent$,
): $json.Json$;
export function RegisterEvent$AtomicChanged$2(value: RegisterEvent$): boolean;
export function RegisterEvent$AtomicChanged$local(value: RegisterEvent$): boolean;

export class VersionChanged extends _.CustomType {
  /** @deprecated */
  constructor(key: string, value: $json.Json$, local: boolean);
  /** @deprecated */
  key: string;
  /** @deprecated */
  value: $json.Json$;
  /** @deprecated */
  local: boolean;
}
export function RegisterEvent$VersionChanged(
  key: string,
  value: $json.Json$,
  local: boolean,
): RegisterEvent$;
export function RegisterEvent$isVersionChanged(
  value: any,
): value is RegisterEvent$;
export function RegisterEvent$VersionChanged$0(value: RegisterEvent$): string;
export function RegisterEvent$VersionChanged$key(value: RegisterEvent$): string;
export function RegisterEvent$VersionChanged$1(value: RegisterEvent$): $json.Json$;
export function RegisterEvent$VersionChanged$value(
  value: RegisterEvent$,
): $json.Json$;
export function RegisterEvent$VersionChanged$2(value: RegisterEvent$): boolean;
export function RegisterEvent$VersionChanged$local(value: RegisterEvent$): boolean;

export type RegisterEvent$ = AtomicChanged | VersionChanged;

export function RegisterEvent$key(value: RegisterEvent$): string;
export function RegisterEvent$local(value: RegisterEvent$): boolean;
export function RegisterEvent$value(value: RegisterEvent$): $json.Json$;

export class Atomic extends _.CustomType {}
export function ReadPolicy$Atomic(): ReadPolicy$;
export function ReadPolicy$isAtomic(value: any): value is ReadPolicy$;

export class Lww extends _.CustomType {}
export function ReadPolicy$Lww(): ReadPolicy$;
export function ReadPolicy$isLww(value: any): value is ReadPolicy$;

export type ReadPolicy$ = Atomic | Lww;

export function new$(): RegisterState$;

export function from_summary(entries: _.List<[string, Register$]>): RegisterState$;

export function summary_registers(state: RegisterState$): _.List<
  [string, Register$]
>;

export function read(state: RegisterState$, key: string, policy: ReadPolicy$): _.Result<
  $json.Json$,
  undefined
>;

export function read_versions(state: RegisterState$, key: string): _.Result<
  _.List<$json.Json$>,
  undefined
>;

export function keys(state: RegisterState$): _.List<string>;

export function write(
  x0: RegisterState$,
  key: string,
  value: $json.Json$,
  last_seen_sequence_number: number
): WriteOperation$;

export function write_detached(
  state: RegisterState$,
  key: string,
  value: $json.Json$
): [RegisterState$, _.List<RegisterEvent$>];

export function apply_remote(
  state: RegisterState$,
  operation: WriteOperation$,
  sequence_number: number
): [RegisterState$, _.List<RegisterEvent$>];

export function ack_local(
  state: RegisterState$,
  operation: WriteOperation$,
  sequence_number: number
): [RegisterState$, _.List<RegisterEvent$>, boolean];

export function rollback(state: RegisterState$, x1: WriteOperation$): [
  RegisterState$,
  boolean
];

export function apply_stashed_operation(
  state: RegisterState$,
  operation: WriteOperation$
): [RegisterState$, WriteOperation$];
