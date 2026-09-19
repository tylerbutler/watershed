import {
  Error,
  Ok,
  type Result,
} from "../../../../tools/website-runtime/build/dev/javascript/watershed/gleam.mjs";
import {
  None,
  Some,
  type Option$ as Option,
} from "../../../../tools/website-runtime/build/dev/javascript/gleam_stdlib/gleam/option.mjs";

export type ResultValue<R> =
  R extends Result<infer T, infer _E> ? T : never;

export function isOk<T, E>(result: Result<T, E>): result is Ok<T, E> {
  return result instanceof Ok;
}

export function resultValue<T, E>(result: Result<T, E>): T | null {
  return isOk(result) ? result[0] : null;
}

export function resultError<T, E>(result: Result<T, E>): E | null {
  return result instanceof Error ? result[0] : null;
}

export function expectOk<T, E>(result: Result<T, E>, detail: string): T {
  if (isOk(result)) return result[0];
  const error = result instanceof Error ? result[0] : result;
  throw new Error(`${detail}: ${String(error)}`);
}

export function isSome<T>(option: Option<T>): option is Some<T> {
  return option instanceof Some;
}

export function optionValue<T>(option: Option<T>): T | null {
  return isSome(option) ? option[0] : null;
}

export function some<T>(value: T): Option<T> {
  return new Some(value);
}

export function none<T>(): Option<T> {
  return new None();
}
