// ──────────────────────────────────────────────────────────────────────────
// watershed — build guide catalog
// Single source of truth for the /guide procedure index and the per-step
// stepper. `n` is the survey-ledger revision number; `slug` is the route under
// /guide. Keep this list in build order — the stepper derives prev/next from it.
// ──────────────────────────────────────────────────────────────────────────

export interface GuideStep {
  /** Ledger revision number, e.g. "01". */
  n: string;
  /** Route slug under /guide. */
  slug: string;
  /** Step title. */
  title: string;
  /** One-line goal, shown under the step title and in the index ledger. */
  goal: string;
  /** The API surface this step introduces, as a mono annotation. */
  surface: string;
}

export const steps = [
  {
    n: "01",
    slug: "connect",
    title: "Connect a document",
    goal: "Join a named, server-sequenced document and read its root map.",
    surface: "watershed.connect · root · set · subscribe",
  },
  {
    n: "02",
    slug: "schema",
    title: "Define a schema",
    goal: "Declare the document's shape once and read and write through it.",
    surface: "schema.field · channel_field · ensure_* · typed",
  },
  {
    n: "03",
    slug: "structures",
    title: "Choose data structures",
    goal: "Select a merge model for each slot based on its possible conflicts.",
    surface: "SharedMap · OR-map · SharedCounter",
  },
  {
    n: "04",
    slug: "ripples",
    title: "Send temporary signals",
    goal: "Broadcast presence and reactions without changing document state.",
    surface: "submit_ripple · subscribe_ripples",
  },
  {
    n: "05",
    slug: "ui",
    title: "Connect the user interface",
    goal: "Use Lustre effects to synchronize data without manual callbacks.",
    surface: "watershed_lustre · connect · ensure_* · presence",
  },
  {
    n: "06",
    slug: "testing",
    title: "Test convergence",
    goal: "Prove that two clients converge without a running server.",
    surface: "sluice · connect · settle · step",
  },
] as const satisfies readonly GuideStep[];

/** Slug of a build-guide step, e.g. `"schema"`. */
export type StepSlug = (typeof steps)[number]["slug"];

/** name → step, for cross-links. */
export const stepBySlug: Record<StepSlug, GuideStep> = Object.fromEntries(
  steps.map((s) => [s.slug, s]),
);

/** The step before/after `slug` in build order, or null at the ends. */
export function neighbours(slug: StepSlug): {
  prev: GuideStep | null;
  next: GuideStep | null;
} {
  const i = steps.findIndex((s) => s.slug === slug);
  return {
    prev: i > 0 ? steps[i - 1] : null,
    next: i >= 0 && i < steps.length - 1 ? steps[i + 1] : null,
  };
}
