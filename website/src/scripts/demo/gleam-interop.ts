import {
  Error as GleamError,
  None,
  Ok,
  Some,
  type Option,
  type Result,
} from "./generated-runtime.ts";

export type ResultValue<R> =
  R extends Result<infer Value, infer _Error> ? Value : never;

export function isOk<Value, Failure>(
  result: Result<Value, Failure>,
): result is Ok<Value, Failure> {
  return result instanceof Ok;
}

export function expectOk<Value, Failure>(
  result: Result<Value, Failure>,
  detail: string,
): Value {
  if (isOk(result)) return result[0];
  const error = result instanceof GleamError ? result[0] : result;
  throw new Error(`${detail}: ${String(error)}`);
}

export function resultValue<Value, Failure>(
  result: Result<Value, Failure>,
): Value | null {
  return isOk(result) ? result[0] : null;
}

export function resultError<Value, Failure>(
  result: Result<Value, Failure>,
): Failure | null {
  return result instanceof GleamError ? result[0] : null;
}

export function isSome<Value>(
  option: Option<Value>,
): option is Some<Value> {
  return option instanceof Some;
}

export function optionValue<Value>(option: Option<Value>): Value | null {
  return isSome(option) ? option[0] : null;
}

export function some<Value>(value: Value): Option<Value> {
  return new Some(value);
}

export function none<Value>(): Option<Value> {
  return new None();
}
