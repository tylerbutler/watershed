import { sluice } from "./generated-runtime.ts";
import type { DemoDocument } from "./sluice-runtime.ts";

type GeneratedDocument = ReturnType<typeof sluice.connect>;

export function withLegacyGeneratedDocument<
  Arguments extends unknown[],
  Value,
>(
  document: DemoDocument,
  operation: (
    document: GeneratedDocument,
    ...arguments_: Arguments
  ) => Value,
  ...arguments_: Arguments
): Value {
  return operation(
    document as unknown as GeneratedDocument,
    ...arguments_,
  );
}
