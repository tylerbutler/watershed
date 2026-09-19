import type * as $claims_kernel from "../watershed/claims_kernel.d.mts";
import type * as $runtime from "../watershed/runtime.d.mts";

export function observe(
  reply: $runtime.ClaimSubmitReply$,
  resolved: (x0: $claims_kernel.ClaimOutcome$) => undefined
): undefined;
