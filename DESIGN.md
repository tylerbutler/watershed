# Design

Visual system for the watershed website (`website/`). Register: brand.

## Theme: "Photorevised survey quadrangle"

The site is styled as a USGS-style survey sheet. The metaphor is load-bearing:
on photorevised quadrangles, magenta overprint marks revisions not yet
field-checked — on this site, magenta marks *pending, unsequenced* state, and
ink marks state the server has sequenced. Every decorative element maps to a
real protocol concept (contours labeled with server sequence numbers, the architecture drawn as a
geological cross-section, milestones as a revision ledger).

## Color (OKLCH, light theme only)

| Token | Value | Role |
| --- | --- | --- |
| `--bg` | `oklch(100% 0 0)` | pure white sheet |
| `--surface` | `oklch(96.2% 0.005 340)` | alternate section band |
| `--ink` | `oklch(25% 0.02 260)` | body text, borders, sequenced state (16:1 on bg) |
| `--muted` | `oklch(44% 0.015 260)` | secondary text (7.8:1) |
| `--overprint` | `oklch(55% 0.21 340)` | magenta brand / pending fills, large text (5.5:1) |
| `--overprint-deep` | `oklch(44% 0.185 340)` | magenta at body sizes (8.6:1) |
| `--waterline` | `oklch(37% 0.095 240)` | blue ink: links, water linework, "converged" (10.2:1) |
| `--hairline` / `--hairline-faint` | ink at 22% / 11% | rules, strata boundaries |

Strategy: **Committed** — magenta carries the brand; white text on magenta
fills; no other hues. Semantics are strict: magenta = pending/unverified,
ink = sequenced/confirmed, waterline = linework and links.

## Typography

- **Archivo Variable** (`@fontsource-variable/archivo/wdth.css`): the width
  axis is the voice. Display/headings at `font-stretch` 115–122%,
  weight 620–650; body at normal width.
- **Fragment Mono**: code, data, and the `.annot` map-margin annotation style
  (uppercase, 0.07em tracking, 0.8125rem).
- Display: `clamp(2.7rem, 5vw + 1.35rem, 5.4rem)`, line-height 0.99,
  letter-spacing −0.025em. H2: `clamp(1.85rem, 2.2vw + 1.1rem, 2.9rem)`.
  Body 1.0625rem / 1.65, measure ≤62ch.

## Sheet grammar

The page is wrapped in a neatline border with registration crosses at the
corners and mono margin annotations above/below the frame (`Sheet.astro`).
This frame-level grammar is the *only* place kicker-style labels live;
sections themselves get plain headings — no per-section eyebrows.

## Motion

- Tokens: `--ease-out-quart`, `--ease-out-expo`; 130ms feedback / 240ms state
  / 700ms entrance.
- Hero contours draw in via `stroke-dashoffset` keyframes; headline rises.
- Scroll reveals (`src/scripts/motion.js`) animate *visible-by-default*
  content with WAAPI at trigger time — nothing is hidden if JS fails.
  Variants: `rise` (up) and `settle` (strata settle downward).
- Demo ops travel as dots (magenta toward the sequencer, ink outward). On
  first reveal the demo submits one scripted op so convergence is witnessed
  without interaction (skipped under reduced motion or after user input).
- Global `prefers-reduced-motion` rule collapses all CSS animation to end
  state; scripts return early.

## Components / conventions

- Panels and tables: 1px `--ink` borders, no border-radius, no shadows —
  everything sits flat on the sheet like printed linework.
- "Stamps" (`.stamp`, `.pure-stamp`): mono uppercase in a 1.5px
  `currentColor` box, rotated ~2deg, like a hand inspection stamp.
- Bedrock hatching: `repeating-linear-gradient(-45deg, …)` hairline diagonal.
- Astro scoped styles don't reach JS-created elements — use `:global()` for
  anything rendered from `demo.js`.
- The demo imports the real compiled kernel from
  `../../../build/dev/javascript/watershed/watershed/map_kernel.mjs`
  (`gleam build --target javascript` runs via `predev`/`prebuild`).
