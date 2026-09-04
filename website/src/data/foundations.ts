// ──────────────────────────────────────────────────────────────────────────
// watershed — foundations and component-model concept catalogs
// Single source of truth for both hub indexes, the per-doc prev/next pager,
// and the "adjoining sheets" footer columns.
// Keep each list in reading order — the pager derives prev/next from it.
// ──────────────────────────────────────────────────────────────────────────

export interface FoundationDoc {
  /** Route slug under its section. */
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

export const componentModelDocs: FoundationDoc[] = [
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

export const conceptDocs = [...foundationsDocs, ...componentModelDocs];

/** slug → doc, for cross-links. */
export const conceptsBySlug: Record<string, FoundationDoc> = Object.fromEntries(
  conceptDocs.map((d) => [d.slug, d]),
);

/** The doc before/after `slug` within its section, or null at the ends. */
export function conceptNeighbours(slug: string): {
  prev: FoundationDoc | null;
  next: FoundationDoc | null;
} {
  const docs = componentModelDocs.some((d) => d.slug === slug)
    ? componentModelDocs
    : foundationsDocs;
  const i = docs.findIndex((d) => d.slug === slug);
  return {
    prev: i > 0 ? docs[i - 1] : null,
    next: i >= 0 && i < docs.length - 1 ? docs[i + 1] : null,
  };
}
