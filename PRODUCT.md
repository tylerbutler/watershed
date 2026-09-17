# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

BEAM and Gleam developers evaluating real-time collaborative data sync for
their applications. They know OTP, Phoenix Channels, and distributed-systems
tradeoffs. They distrust sync magic and value visible rigor such as property
tests, convergence guarantees, and protocol detail.

They often arrive from GitHub, the Gleam Discord, or a conference talk. They
want to decide within a minute whether watershed is credible enough to try.

## Product Purpose

watershed gives Gleam applications collaborative data structures with
optimistic local edits, server-sequenced convergence, and reconnect safety. It
works with Fluid Framework-compatible sequencing services, including
floodgate, levee, and routerlicious.

The pure core compiles to Erlang and JavaScript. Success means that a developer
stars the repository, runs an example, reads the architecture, or starts
integrating watershed into an application.

## Positioning

A Gleam-native collaborative data toolkit whose shared core runs on BEAM and
JavaScript, speaks the Fluid wire protocol, and exposes convergence behavior
directly instead of hiding it behind sync magic.

## Operating Context

Developers evaluate watershed through the website, repository documentation,
live browser demos, and runnable examples. They compare data structures by
their merge rules, optimistic behavior, saved state, and response to concurrent
or offline edits.

Application developers use the Erlang facade in OTP systems and the JavaScript
facade in browser applications. Lustre applications use the
`watershed_lustre` bindings. Documents connect to a compatible sequencing
service or use the peer-to-peer runtime where that model fits.

## Capabilities and Constraints

- The core supports Erlang and JavaScript from one Gleam codebase.
- The toolkit includes server-ordered DDSs, CRDTs, operational transforms,
  presence, reconnect handling, summaries, and typed document schemas.
- All structures in a document share the same sequenced stream.
- The wire protocol is compatible with Fluid Framework sequencing services.
- Browser demos run the compiled Gleam kernels rather than a separate
  simulation of their merge behavior.
- `watershed` and `watershed_lustre` are installed from a pinned Git commit.
  They are not published to Hex.
- The project must preserve the established terms `watershed`, `floodgate`,
  `sluice`, `ripple`, `gauge`, `field atlas`, `adjoining sheets`, and
  `the survey procedure`.

## Brand Commitments

The name and product language belong to a family of water-infrastructure
projects: watershed, floodgate, spillway, aquamarine, and roost. The metaphor
describes real system behavior. It is not decorative naming.

The voice is measured, exact, and quietly authoritative, like a clear
engineering document about river control. The three defining traits are
**precise, fluid, grounded**.

Avoid generic SaaS landing-page patterns, dark-terminal hacker styling,
editorial-magazine styling, and timid cream or beige presentation. Do not use
monospace type as a generic signal for technical credibility.

## Evidence on Hand

- `README.md` documents installation, both target-specific facades, supported
  structures, and executable examples.
- `website/src/pages/` contains the guide, architecture material, model
  comparisons, structure references, and dedicated demonstrations.
- `website/src/components/Demo.astro` runs live multi-client demonstrations
  against the JavaScript-compiled kernels.
- `examples/` contains BEAM, browser, CLI, Lustre, peer-to-peer, persistence,
  and collaborative application examples.
- `test/` and the browser smoke suites exercise convergence, wire behavior,
  reconnects, summaries, transports, and target parity.
- The repository contains no testimonials, production customer logos, press
  coverage, or independent performance benchmarks. Future work must not
  fabricate them.

## Product Principles

1. **Show, do not claim.** Let developers witness convergence in live demos.
2. **Make the mechanism legible.** Show sequencing, pending state, reconnects,
   and merge rules instead of presenting collaboration as magic.
3. **Use rigor as evidence.** Prefer protocol details, tests, and concrete
   behavior over adjectives.
4. **Keep one shared core.** Erlang and JavaScript should expose the same
   underlying semantics.
5. **Match the structure to the conflict rule.** Help developers choose a data
   type by what concurrent edits must mean.

## Accessibility & Inclusion

The website targets WCAG AA contrast, including at least 4.5:1 for body text.
Interactive demonstrations must work with a keyboard. Every animation must
provide an intentional `prefers-reduced-motion` alternative.
