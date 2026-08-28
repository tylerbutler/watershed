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
    slug: "race",
    title: "Run the race",
    goal: "Watch two replicas disagree, then agree, before you write a line of it.",
    surface: "sluice · or_map_set · or_map_increment",
  },
  {
    n: "02",
    slug: "connect",
    title: "Connect the board",
    goal: "Join a live document, seed its two channels, and render an empty board.",
    surface: "connect_dev · root_typed · ensure_or_map · subscribe",
  },
  {
    n: "03",
    slug: "notes",
    title: "Notes that survive a tie",
    goal: "Write whole notes into a register OR-map so two simultaneous adds both live.",
    surface: "RegisterMode · or_map_set_json · or_map_entries",
  },
  {
    n: "04",
    slug: "votes",
    title: "Votes that add up",
    goal: "Send signed deltas to a tally OR-map so concurrent votes sum instead of clobbering.",
    surface: "TallyMode · or_map_increment · Tally",
  },
  {
    n: "05",
    slug: "presence",
    title: "Who is reading what",
    goal: "Publish the focused note as presence, where it expires instead of accumulating.",
    surface: "presence.config · watershed_lustre.presence · update_presence",
  },
  {
    n: "06",
    slug: "testing",
    title: "Pin the races",
    goal: "Replay both step-01 races under gleam test, deterministically, with no server.",
    surface: "sluice_js · start · settle · step",
  },
] as const satisfies readonly GuideStep[];

/** Slug of any /guide sheet, e.g. `"notes"`. */
export type StepSlug = (typeof steps)[number]["slug"];

/** name → step, for cross-links. */
export const stepBySlug: Record<StepSlug, GuideStep> = Object.fromEntries(
  steps.map((s) => [s.slug, s]),
) as Record<StepSlug, GuideStep>;

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
