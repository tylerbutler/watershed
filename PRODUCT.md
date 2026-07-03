# Product

## Register

brand

## Users

BEAM and Gleam developers evaluating real-time collaborative data sync for their apps. They know OTP, Phoenix Channels, and distributed-systems tradeoffs; they are skeptical of sync magic and respect visible rigor (property tests, convergence proofs, protocol detail). Context: they land here from GitHub, the Gleam Discord, or a conference talk, deciding in under a minute whether watershed is credible enough to try.

## Product Purpose

watershed is a Gleam (BEAM) DDS client toolkit for levee: collaborative data structures (SharedMap first) with optimistic local edits, server-sequenced convergence, and reconnect safety. The pure core is target-agnostic and compiles to both Erlang and JavaScript. The website's job is to make that credibility legible fast — and to *show* convergence live in the browser rather than claim it. Success: a visiting Gleam dev stars the repo, runs an example, or reads the architecture.

## Brand Personality

Hydrological engineering: calm, precise, systems-confidence. The ecosystem naming (watershed, levee, spillway, aquamarine, roost) is a literal water-infrastructure family — the brand treats that metaphor as load-bearing, not decorative. Voice like a well-written engineering document about river control: measured, exact, quietly authoritative. Three words: **precise, fluid, grounded**.

## Anti-references

- Generic SaaS landing grammar: gradient hero, metric rows, identical feature-card grids, uppercase eyebrow labels on every section.
- Dark-terminal "hacker tool" aesthetic; monospace-everything as a costume for "technical."
- Editorial-magazine lane (display serif italics, drop caps, ruled columns) — this is infrastructure, not a periodical.
- Cream/beige default neutrals; timid restraint that reads as unfinished.

## Design Principles

1. **Show, don't claim.** Convergence is demonstrated live on the page (two in-browser clients over the JS-compiled core), not asserted in copy.
2. **The metaphor is load-bearing.** Water-system visuals (flow, contour, sequencing) illustrate the actual architecture — every decorative element maps to a real concept (ops flowing downstream, the server as sequencer, reconnect as rejoining the flow).
3. **Rigor is content.** Property-test counts, the convergence guarantee, byte-compatibility with Fluid Framework's wire format — specifics over adjectives.
4. **Calm surface, deep water.** Composed, unhurried presentation; density lives in the diagrams and code, not in visual noise.

## Accessibility & Inclusion

WCAG AA contrast throughout (body ≥4.5:1). Ambitious, orchestrated motion is welcome — page-load choreography and flow animation — but every animation has a `prefers-reduced-motion` alternative. Fully keyboard accessible; the live demo must be operable without a pointer.
