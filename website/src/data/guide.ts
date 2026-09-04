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
    title: "Connect the board",
    goal: "Open the same empty board in two browser tabs.",
    surface: "connect_dev · root_typed · ensure_or_map · subscribe",
  },
  {
    n: "02",
    slug: "notes",
    title: "Add notes",
    goal: "Create a note and watch it show up in both tabs.",
    surface: "RegisterMode · or_map_set_json · or_map_entries",
  },
  {
    n: "03",
    slug: "race",
    title: "Try two edits at once",
    goal: "Add notes from both tabs at the same instant and confirm both appear.",
    surface: "sluice · or_map_set_json · or_map_entries",
  },
  {
    n: "04",
    slug: "votes",
    title: "Add votes",
    goal: "Build a vote count that stays correct even when clicks overlap.",
    surface: "TallyMode · or_map_increment · Tally",
  },
  {
    n: "05",
    slug: "presence",
    title: "Add presence",
    goal: "Show who is looking at each note, and clear it when they leave.",
    surface: "presence.config · watershed_lustre.presence · update_presence",
  },
  {
    n: "06",
    slug: "testing",
    title: "Write repeatable tests",
    goal: "Turn the two-tab checks you've been running by hand into tests you can run anytime.",
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
