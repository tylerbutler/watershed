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

export const steps: GuideStep[] = [
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
    title: "Model it with a schema",
    goal: "Declare the document's shape once and read and write through it.",
    surface: "schema.field · channel_field · ensure_* · typed",
  },
  {
    n: "03",
    slug: "structures",
    title: "Choose your structures",
    goal: "Pick a merge model per slot: which conflicts you can tolerate, and where.",
    surface: "SharedMap · OR-map · SharedCounter",
  },
  {
    n: "04",
    slug: "ripples",
    title: "Ephemeral signals",
    goal: "Broadcast presence and reactions that never touch the document's state.",
    surface: "submit_ripple · subscribe_ripples",
  },
  {
    n: "05",
    slug: "ui",
    title: "Wire it to your UI",
    goal: "Declare sync as Lustre effects instead of hand-bridging callbacks.",
    surface: "watershed_lustre · connect · ensure_* · presence",
  },
  {
    n: "06",
    slug: "testing",
    title: "Test convergence",
    goal: "Prove two clients converge, deterministically, with no server running.",
    surface: "sluice · connect · settle · step",
  },
];

/** name → step, for cross-links. */
export const stepBySlug: Record<string, GuideStep> = Object.fromEntries(
  steps.map((s) => [s.slug, s]),
);

/** The step before/after `slug` in build order, or null at the ends. */
export function neighbours(slug: string): {
  prev: GuideStep | null;
  next: GuideStep | null;
} {
  const i = steps.findIndex((s) => s.slug === slug);
  return {
    prev: i > 0 ? steps[i - 1] : null,
    next: i >= 0 && i < steps.length - 1 ? steps[i + 1] : null,
  };
}
