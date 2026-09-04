// ──────────────────────────────────────────────────────────────────────────
// watershed — foundations concept catalog
// Single source of truth for the /foundations section: the hub index, the
// per-doc prev/next pager, and the "adjoining sheets" footer column. These are
// the core document model plus the component-composition foundation: what a
// schema declares, how a document is laid out and started, and how a host
// describes components and routes events between them.
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
  {
    slug: "components",
    title: "Components and catalogs",
    gloss:
      "Let users, not the author, decide what is on the page: package each part of the app behind a versioned descriptor so it can be rebuilt from a saved document, and keep unlike parts in one catalog.",
    concept: "Descriptor · Catalog · register · find · start",
  },
  {
    slug: "ports",
    title: "Ports and dispatch",
    gloss:
      "Let a user connect two parts that were written apart: a port is a named connection point a component publishes, typed while you write it, erased once it is stored, and checked again before every event it carries.",
    concept: "Output · Input · EffectiveGraph · LocalIntent · Delivery",
  },
  {
    slug: "workspaces",
    title: "Workspaces and instances",
    gloss:
      "Save the finished board — which parts exist, where they sit, how they are wired — and reopen it safely next year, without deleting the parts this build cannot understand.",
    concept: "ManifestEntry · Snapshot · Prepared · delete_instance",
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
