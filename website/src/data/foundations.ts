// ──────────────────────────────────────────────────────────────────────────
// watershed — foundations concept catalog
// Single source of truth for the /foundations section: the hub index, the
// per-doc prev/next pager, and the "adjoining sheets" footer column. These are
// the core mental model a programmer needs before the /guide steps make
// sense: what a schema declares, how a document is actually laid out, and
// what happens between opening a document and having something to build on.
// Keep this list in reading order — the pager derives prev/next from it.
// ──────────────────────────────────────────────────────────────────────────

export interface FoundationDoc {
  /** Route slug under /foundations. */
  slug: string;
  /** Sheet title. */
  title: string;
  /** One-line gloss, shown in the hub index, the pager, and the footer. */
  gloss: string;
  /** The API surface this sheet traces, as a mono annotation. */
  concept: string;
}

export const foundationsDocs: FoundationDoc[] = [
  {
    slug: "schema",
    title: "Schemas and fields",
    gloss:
      "Declare the shape of a map once, at compile time, with a phantom tag the runtime never sees: a plain field, a handle to a nested map, or a handle to another channel entirely.",
    concept: "Field · ChildField · ChannelField · FieldError",
  },
  {
    slug: "topology",
    title: "Documents and handles",
    gloss:
      "A watershed document is not one tree — it's a root map plus whatever channels its values point to, each one independently addressed, attached, and resolved.",
    concept: "root_typed · handle_of · create_map · resolve",
  },
  {
    slug: "lifecycle",
    title: "Starting a document",
    gloss:
      "Every client runs the same bootstrap: get a handle, wait for the catch-up, ensure the channels it needs exist, and only render once they've all reported in.",
    concept: "got_document · connected · ensure_* · subscribe",
  },
];

/** slug → doc, for cross-links. */
export const foundationsBySlug: Record<string, FoundationDoc> = Object.fromEntries(
  foundationsDocs.map((d) => [d.slug, d]),
);

/** The doc before/after `slug` in reading order, or null at the ends. */
export function foundationsNeighbours(slug: string): {
  prev: FoundationDoc | null;
  next: FoundationDoc | null;
} {
  const i = foundationsDocs.findIndex((d) => d.slug === slug);
  return {
    prev: i > 0 ? foundationsDocs[i - 1] : null,
    next: i >= 0 && i < foundationsDocs.length - 1 ? foundationsDocs[i + 1] : null,
  };
}
