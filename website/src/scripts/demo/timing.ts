// Reduced-motion aware timing helpers shared by every demo. The interactive
// demos gate their flow-dot animations on `prefersReducedMotion`; the scripted
// walkthroughs (counter-bug) use `wait` to pace their choreography and collapse
// every delay to zero when the user prefers reduced motion.

/** True when the user has requested reduced motion. Evaluated live each call. */
export function prefersReducedMotion(): boolean {
  return window.matchMedia("(prefers-reduced-motion: reduce)").matches;
}

/**
 * Resolve after `ms` milliseconds, or immediately when reduced motion is
 * preferred (so scripted demos jump straight to their final state).
 */
export function wait(ms: number): Promise<void> {
  return prefersReducedMotion()
    ? Promise.resolve()
    : new Promise((resolve) => setTimeout(resolve, ms));
}
