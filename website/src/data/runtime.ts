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
      "Show a local edit the instant it happens, reconcile it when the server sequences it — and unwind it cleanly if it loses.",
    concept: "apply · pending → ack_local → sequenced",
  },
  {
    slug: "reconnect",
    title: "Reconnect & resync",
    gloss:
      "Drop the link and rejoin the flow. A returning client rehydrates from a summary — the same path a fresh client boots from.",
    concept: "from_summary · replay · catch-up",
  },
  {
    slug: "redelivery",
    title: "Idempotent re-delivery",
    gloss:
      "Why a re-sent delta lands as a non-event — dropped by the runtime's sequence-number check, or absorbed by an idempotent merge.",
    concept: "re-deliver · dedupe · absorb",
  },
  {
    slug: "presence",
    title: "Presence & ripples",
    gloss:
      "The ephemeral tier beside your state: throwaway broadcasts, and the roster built on them — connection-backed where the server offers it, heartbeat-and-TTL where it does not.",
    concept: "submit_ripple · sessions · server or heartbeat",
  },
  {
    slug: "p2p",
    title: "Peer-to-peer over WebRTC",
    gloss:
      "A document that runs on a WebRTC mesh with no sequencer at all — eligible structures merge instead of ordering, and a relay attaches later for durability without changing the document's state or handles.",
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
