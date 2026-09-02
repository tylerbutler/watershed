// ──────────────────────────────────────────────────────────────────────────
// Practice snippet registry — the single source of truth for which generated
// snippet each field note shows. One line per practice: a practice id on the
// left, the generated id on the right.
//
// The code itself is not selected here. `website/snippets.json` declares the
// marker ranges, `tools/source-snippets` extracts them, and the loader fails
// the build on an id nothing generates. Practice metadata and the source
// links stay local, in `practices.ts`.
// ──────────────────────────────────────────────────────────────────────────
import { sourceSnippet, type Snippet } from "../lib/snippet.ts";

/** Every practice snippet, keyed by practice id. */
export const practiceSnippets: Record<string, Snippet> = {
  "relay-decorator": sourceSnippet("practice-relay-decorator"),
  "shared-core-two-runtimes": sourceSnippet("practice-shared-core-two-runtimes"),
  "diagnostics-first": sourceSnippet("practice-diagnostics-first"),
  "quorum-pending-roster": sourceSnippet("practice-quorum-pending-roster"),
  "realtime-out-of-band": sourceSnippet("practice-realtime-out-of-band"),
  "presence-idiom": sourceSnippet("practice-presence-idiom"),
  "protocol-on-ripples": sourceSnippet("practice-protocol-on-ripples"),
  "pure-modules": sourceSnippet("practice-pure-modules"),
  "ffi-surface": sourceSnippet("practice-ffi-surface"),
  "fallible-edits": sourceSnippet("practice-fallible-edits"),
  "authoritative-channel": sourceSnippet("practice-authoritative-channel"),
  "stamp-schema": sourceSnippet("practice-stamp-schema"),
  "typedmap-panels": sourceSnippet("practice-typedmap-panels"),
  "claims-seeding": sourceSnippet("practice-claims-seeding"),
  "anchors-not-offsets": sourceSnippet("practice-anchors-not-offsets"),
  "unsettled-writes": sourceSnippet("practice-unsettled-writes"),
  "deterministic-death": sourceSnippet("practice-deterministic-death"),
};
