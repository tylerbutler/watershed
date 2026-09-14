import {
  Error as RootError,
  Ok as RootOk,
  type Result as RootResult,
} from "../../../../build/dev/javascript/watershed/gleam.mjs";
import {
  None as RootNone,
  Some as RootSome,
  type Option$ as RootOption,
} from "../../../../build/dev/javascript/gleam_stdlib/gleam/option.mjs";
import {
  Error as LustreError,
  Ok as LustreOk,
  type Result as LustreResult,
} from "../../../../watershed_lustre/build/dev/javascript/watershed/gleam.mjs";
import {
  None as LustreNone,
  Some as LustreSome,
  type Option$ as LustreOption,
} from "../../../../watershed_lustre/build/dev/javascript/gleam_stdlib/gleam/option.mjs";

type Result<T, E> = RootResult<T, E> | LustreResult<T, E>;
type Ok<T, E> = RootOk<T, E> | LustreOk<T, E>;
type Option<T> = RootOption<T> | LustreOption<T>;
type Some<T> = RootSome<T> | LustreSome<T>;

export type ResultValue<R> =
  R extends RootResult<infer T, infer _E> ? T
    : R extends LustreResult<infer T, infer _E> ? T
    : never;

export function isOk<T, E>(result: Result<T, E>): result is Ok<T, E> {
  return result instanceof RootOk || result instanceof LustreOk;
}

export function resultValue<T, E>(result: Result<T, E>): T | null {
  return isOk(result) ? result[0] : null;
}

export function expectOk<T, E>(result: Result<T, E>, detail: string): T {
  if (isOk(result)) return result[0];
  const error =
    result instanceof RootError || result instanceof LustreError
      ? result[0]
      : result;
  throw new Error(`${detail}: ${String(error)}`);
}

export function isSome<T>(option: Option<T>): option is Some<T> {
  return option instanceof RootSome || option instanceof LustreSome;
}

export function optionValue<T>(option: Option<T>): T | null {
  return isSome(option) ? option[0] : null;
}

export function some<T>(value: T): RootOption<T> {
  return new RootSome(value);
}

export function none<T>(): RootOption<T> {
  return new RootNone();
}
