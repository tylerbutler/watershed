// ──────────────────────────────────────────────────────────────────────────
// watershed — runtime concept catalog
// Single source of truth for the /runtime section: the hub index, the per-doc
// prev/next pager, and the "adjoining sheets" footer group. These are narrative
// concept sheets (how the runtime behaves), distinct from /guide (how to build)
// and /structures (what each structure is). Keep this list in reading order —
// the pager derives prev/next from it.
// ──────────────────────────────────────────────────────────────────────────

export interface RuntimeDoc {
  /** Route slug under /runtime. */
  slug: string;
  /** Sheet title. */
  title: string;
  /** One-line gloss, shown in the hub index, the pager, and the footer. */
  gloss: string;
  /** The protocol surface / lifecycle this sheet traces, as a mono annotation. */
  concept: string;
}

export const runtimeDocs: RuntimeDoc[] = [
  {
    slug: "optimistic",
    title: "Optimistic edits",
    gloss:
      "Show a local edit at once, confirm it after sequencing, and reverse it if the server rejects it.",
    concept: "apply · pending → ack_local → sequenced",
  },
  {
    slug: "reconnect",
    title: "Reconnect and resynchronize",
    gloss:
      "Restore a dropped connection. A returning client loads state from the same summary path as a new client.",
    concept: "from_summary · replay · catch-up",
  },
  {
    slug: "redelivery",
    title: "Repeated delivery",
    gloss:
      "A sequence-number check drops a repeated delta, or an idempotent merge leaves the state unchanged.",
    concept: "deliver again · sequence check · idempotent merge",
  },
  {
    slug: "presence",
    title: "Presence and ripples",
    gloss:
      "Use temporary broadcasts and a live roster. The server tracks connections when possible; otherwise, clients use heartbeats and a TTL.",
    concept: "submit_ripple · sessions · server or heartbeat",
  },
  {
    slug: "p2p",
    title: "Peer-to-peer WebRTC",
    gloss:
      "Run a document on a WebRTC mesh without a sequencer. Eligible structures merge changes, and an optional relay adds durable storage.",
    concept: "CrdtDocument · Auto / SequencedOnly / P2pOnly · crdt_relay_v1",
  },
];

/** slug → doc, for cross-links. */
export const runtimeBySlug: Record<string, RuntimeDoc> = Object.fromEntries(
  runtimeDocs.map((d) => [d.slug, d]),
);

/** The doc before/after `slug` in reading order, or null at the ends. */
export function runtimeNeighbours(slug: string): {
  prev: RuntimeDoc | null;
  next: RuntimeDoc | null;
} {
  const i = runtimeDocs.findIndex((d) => d.slug === slug);
  return {
    prev: i > 0 ? runtimeDocs[i - 1] : null,
    next: i >= 0 && i < runtimeDocs.length - 1 ? runtimeDocs[i + 1] : null,
  };
}
