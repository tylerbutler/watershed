---
name: Markdown Notes Console
description: The visual world of examples/markdown_notes_lustre only — a light console panel where every note is a track with its own state lamp.
colors:
  panel: "oklch(93% 0.004 250)"
  panel-deep: "oklch(88.5% 0.005 250)"
  panel-lip: "oklch(97% 0.003 250)"
  surface: "oklch(98.8% 0.002 250)"
  ink: "oklch(24% 0.012 250)"
  muted: "oklch(45% 0.011 250)"
  rule: "oklch(24% 0.012 250 / 0.16)"
  rule-faint: "oklch(24% 0.012 250 / 0.08)"
  lamp-off: "oklch(24% 0.012 250 / 0.22)"
  lamp-live: "oklch(66% 0.15 68)"
  lamp-safe: "oklch(52% 0.13 155)"
  lamp-armed: "oklch(52% 0.2 27)"
  armed-ink: "oklch(43% 0.18 27)"
typography:
  headline:
    fontFamily: "system-ui, -apple-system, Segoe UI, sans-serif"
    fontSize: "1.5rem"
    fontWeight: 650
    lineHeight: 1.2
    letterSpacing: "-0.02em"
  title:
    fontFamily: "system-ui, -apple-system, Segoe UI, sans-serif"
    fontSize: "1.0625rem"
    fontWeight: 650
    lineHeight: 1.55
    letterSpacing: "-0.01em"
  meter:
    fontFamily: "system-ui, -apple-system, Segoe UI, sans-serif"
    fontSize: "0.9375rem"
    fontWeight: 650
    lineHeight: 1.55
    letterSpacing: "-0.005em"
  body:
    fontFamily: "system-ui, -apple-system, Segoe UI, sans-serif"
    fontSize: "1rem"
    fontWeight: 400
    lineHeight: 1.55
    letterSpacing: "normal"
  readout:
    fontFamily: "system-ui, -apple-system, Segoe UI, sans-serif"
    fontSize: "0.8125rem"
    fontWeight: 400
    lineHeight: 1.55
    letterSpacing: "normal"
  label:
    fontFamily: "system-ui, -apple-system, Segoe UI, sans-serif"
    fontSize: "0.75rem"
    fontWeight: 700
    lineHeight: 1.55
    letterSpacing: "0.14em"
  transport:
    fontFamily: "system-ui, -apple-system, Segoe UI, sans-serif"
    fontSize: "0.75rem"
    fontWeight: 600
    lineHeight: 1.55
    letterSpacing: "0.06em"
  mono:
    fontFamily: "ui-monospace, SF Mono, Cascadia Mono, monospace"
    fontSize: "0.9375rem"
    fontWeight: 400
    lineHeight: 1.7
    letterSpacing: "normal"
  engraved:
    fontFamily: "ui-monospace, SF Mono, Cascadia Mono, monospace"
    fontSize: "0.8125rem"
    fontWeight: 400
    lineHeight: 1.55
    letterSpacing: "normal"
    fontFeature: "tabular-nums"
rounded:
  meter: "1px"
  control: "2px"
  container: "3px"
  lamp: "50%"
spacing:
  hair: "0.25rem"
  tight: "0.5rem"
  snug: "0.75rem"
  base: "1rem"
  rack: "1.25rem"
  room: "1.75rem"
components:
  button-panel:
    backgroundColor: "{colors.panel-lip}"
    textColor: "{colors.ink}"
    typography: "{typography.body}"
    rounded: "{rounded.control}"
    padding: "0.45rem 0.7rem"
  button-panel-disabled:
    backgroundColor: "{colors.panel-deep}"
    textColor: "{colors.muted}"
    rounded: "{rounded.control}"
    padding: "0.45rem 0.7rem"
  button-transport:
    backgroundColor: "{colors.panel-lip}"
    textColor: "{colors.ink}"
    typography: "{typography.transport}"
    rounded: "{rounded.control}"
    padding: "0.4rem 0.6rem"
    height: "2rem"
  button-destructive:
    backgroundColor: "{colors.lamp-armed}"
    textColor: "{colors.surface}"
    rounded: "{rounded.control}"
    padding: "0.45rem 0.7rem"
  button-destructive-hover:
    backgroundColor: "oklch(45% 0.2 27)"
    textColor: "{colors.surface}"
  strip:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    typography: "{typography.meter}"
    rounded: "{rounded.control}"
    padding: "0.5rem 0.6rem"
  strip-open:
    backgroundColor: "{colors.panel-lip}"
    textColor: "{colors.ink}"
    rounded: "{rounded.control}"
    padding: "0.5rem 0.6rem"
  input-panel:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    typography: "{typography.body}"
    rounded: "{rounded.control}"
    padding: "0.45rem 0.6rem"
  chip-tag:
    backgroundColor: "{colors.panel}"
    textColor: "{colors.ink}"
    typography: "{typography.transport}"
    rounded: "{rounded.control}"
    padding: "0.2rem 0.5rem"
  chip-filter-active:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.surface}"
    rounded: "{rounded.control}"
    padding: "0.25rem 0.5rem"
  rack-card:
    backgroundColor: "{colors.panel}"
    rounded: "{rounded.container}"
    padding: "{spacing.snug}"
  lamp-dot:
    backgroundColor: "{colors.lamp-off}"
    rounded: "{rounded.lamp}"
    size: "0.5rem"
  meter-segment:
    backgroundColor: "{colors.lamp-live}"
    rounded: "{rounded.meter}"
    width: "0.25rem"
    height: "0.9rem"
---

# Design System: Markdown Notes Console

**Scope: `examples/markdown_notes_lustre/` only.** This is not the watershed design system. The repository root carries a separate `DESIGN.md` documenting the website's own world, scoped to `website/`; the two share no tokens, no palette, and no type ramp, and neither one governs the other. Nothing here should be lifted into the site, and nothing from the site should be lifted into an example screen. The whole system below lives in the inline `<style>` block of `index.html`; there is no stylesheet, no build step for CSS, and no token package.

## Overview

**Creative North Star: "The Console Panel"**

A note is a track on a mixing console, and every track shows whether it is local, saved, or converged. The screen is a piece of light equipment sitting on a daylit desk: a pale zinc panel, hairline scoring between sections, engraved inset cards for anything you type into or act on, and small discrete indicator lamps that only ever say one of three things. The register is Operate — you are working the panel, not reading a brochure — so labels are terse, uppercase and tracked, and every state is legible without hovering, clicking, or guessing.

The world exists to refuse one specific thing: the two-pane notes app whose only durability signal is a gray "Saved" in a corner. Here, durability is the loudest instrument on the panel. A master meter at the top of the rack answers "is my work safe?" in one sentence, three subordinate readouts break that into network, storage, and local save, and every note strip carries the same lamp again on its own track — because the whole document shares one snapshot, so a note is exactly as saved as every other note, and the panel says so per-track rather than once at the top.

Flat, never metal. There are no gradients, no bevels, no simulated brushed aluminium and no faux screws. Depth is a hairline and a one-pixel lip, nothing more. The system is light-only by decision, not by omission: the use scene is a developer at a daylit desk with two tabs open, a console is a light object, and the product's anti-references rule out both a dark-terminal costume and cream neutrals. There is no dark path to maintain and no `prefers-color-scheme` block anywhere.

**Key Characteristics:**
- Pale cool-zinc panel at three depths, with a near-white writing surface on top
- Engraved inset cards for input, raised lip for containers — the only two depth moves
- Three-colour lamp vocabulary with fixed, strict meaning, always read out in words beside the lamp
- Uppercase tracked labels in a self-hosted variable face, condensed by axis for the strip
- Exactly one authored animation on the entire page
- Single breakpoint at 52rem; a 19.5rem rack collapses to a stacked header

## Colors

A cool zinc panel in four steps, near-neutral ink, and three saturated lamps that are the only chromatic elements in the world.

### Primary

The lamps are the accent system. They are the point of this world and they are used nowhere except signalling.

- **Live Amber** `lamp-live` `oklch(66% 0.15 68)`: local, in flight, not yet on disk. The master meter's default, the connection-opening state, and the "not saved yet" state on every note strip. Also survives as a one-pixel inner line inside the focus ring — the only place amber appears that is not a lamp.
- **Converged Green** `lamp-safe` `oklch(52% 0.13 155)`: on disk / converged. Nothing is green until it has actually been written.
- **Armed Red** `lamp-armed` `oklch(52% 0.2 27)`: at risk or destructive. Lamps, destructive button fills, the recovery panel's border and its 0.1875rem top strip, and the 6%-alpha wash behind an error rack. Never small text.
- **Armed Ink** `armed-ink` `oklch(43% 0.18 27)`: the text-safe twin of Armed Red. Every red *word* on the panel — error lines, the failed save readout, the recovery heading, the error rack's label — uses this and not the lamp. Measured 6.19:1 on the rack and 7.13:1 on the panel.

### Neutral

- **Panel Zinc** `panel` `oklch(93% 0.004 250)`: the page ground and the writing room's background; also the rack card and tag chips, so a card reads as sitting *in* the deeper rack.
- **Rack Zinc** `panel-deep` `oklch(88.5% 0.005 250)`: the sidebar rack, and the fill of a disabled control. One step darker than the panel so the rack reads as the recessed half of the enclosure.
- **Lip** `panel-lip` `oklch(97% 0.003 250)`: one-pixel inset highlight along the top edge of containers and the right edge of the rack, plus the hover and selected fill for strips and buttons. It is a lit edge, not a surface.
- **Writing White** `surface` `oklch(98.8% 0.002 250)`: anything you type into or act on — the editor card, inputs, note strips, the engraved room-id field. Also the knocked-out text colour on a destructive fill.
- **Ink** `ink` `oklch(24% 0.012 250)`: all primary text, the focus ring, the active tag-filter fill, and the background of the inline command block in a banner. 15.84:1 on the writing surface.
- **Muted** `muted` `oklch(45% 0.011 250)`: secondary readouts, placeholders, rack headings, the delete affordance at rest, and the selected strip's border. 6.04:1 on the panel — comfortably past AA, because these lines carry real state, not chrome.
- **Rule** `rule` `oklch(24% 0.012 250 / 0.16)` and **Rule Faint** `rule-faint` `oklch(24% 0.012 250 / 0.08)`: panel scoring. `rule` separates enclosures and outlines controls; `rule-faint` scores *within* an enclosure (under the master meter, under the transport row, above the tag rail, at the foot of the rack).
- **Lamp Off** `lamp-off` `oklch(24% 0.012 250 / 0.22)`: an unlit lamp. Present so a dark lamp reads as a lamp rather than a hole.

### Named Rules

**The Lamp Truth Rule.** Amber means local / in flight / not yet on disk. Green means on disk / converged. Red means at risk or destructive. Those meanings never bend for emphasis, category, branding, or taste. A lamp that is always dark is decoration; if a new surface cannot name which of the three states a lamp reports, it does not get a lamp.

**The Second Channel Rule.** Every lamp is read out in words directly beside it — "local save · saved", "storage · no local snapshot yet", "Safe · 4 notes on disk and on 1 peer". Colour is never the only channel, and the sentence, not the lamp, is what a screen reader gets. New lamps ship with their sentence or they do not ship.

**The Text-Safe Twin Rule.** `lamp-armed` is for lamps and destructive fills only. As small text on the rack it measures 4.33:1 and fails AA. Red words always use `armed-ink`.

**The Selection Is Not A Signal Rule.** Selection, hover and drop targeting are expressed with fill, weight, border colour and a dashed `muted` outline — never with a lamp colour, which has to keep meaning what it means.

## Typography

**Display / Label Font:** **Saira Variable**, self-hosted — `var(--label)` → `"Saira Variable", system-ui, sans-serif`. One latin `woff2` (97KB) carrying `wght` 100–900 and `wdth` 50–125%, installed as `@fontsource-variable/saira` (OFL-1.1) and copied to `fonts/saira-latin-wdth-normal.woff2` by `scripts/copy-fonts.mjs` during `pnpm run build`. `fonts/` is generated and gitignored, like `dist/` and `sw.js`; the package is the single source of truth for the version, so there are no committed bytes that can drift from the manifest. The file is listed in the service worker's `SHELL` — a panel whose lettering only arrives online is not offline-first.

Saira's flat-cut terminals on a squared skeleton are the instrument character the world is built on — this is lettering that belongs silkscreened onto equipment, not a neutral sans standing in for one.

**Body / Readout Font:** the platform workhorse stack — `system-ui, -apple-system, "Segoe UI", sans-serif`. Sentences a person reads are *not* set in the label face.

**Mono Font:** `ui-monospace, "SF Mono", "Cascadia Mono", monospace`.

**Character:** Three voices with a hard division of labour. **Saira** is the equipment's own lettering: panel labels and headings, nothing else. **The system stack** is the reading voice: status sentences, hints, banner prose. **Mono** is for values you might copy or read character by character — the room id, error detail lines, the shell command in a banner, and the editor itself.

### Hierarchy

- **Headline** (Saira, 620, 100% width, 1.625rem, 1.15, -0.015em): the open note's title, at the top of the writing surface. One per screen.
- **Title** (Saira, 620, 100% width, 1.125rem, -0.01em, `armed-ink`): the recovery panel's heading. The only other heading with real size.
- **Meter** (650, 0.9375rem, -0.005em, `ink`): the master safety sentence at the top of the rack. Deliberately the largest thing in the rack.
- **Body** (400, 1rem, 1.55): banner prose, recovery explanation, hints in the writing room.
- **Readout** (400, 0.8125rem, `muted`): the three subordinate status lines, hints, error lines. The default voice of the rack.
- **Label** (Saira, 700, 87.5% width, 0.8125rem, 0.16em, uppercase, `muted`): the rack's own name. The error rack's heading is the same treatment one step smaller (0.75rem, 0.13em, `armed-ink`).
- **Transport** (Saira, 620, 87.5% width, 0.8125rem, 0.08em, uppercase): the markdown toolbar buttons — BOLD, ITALIC, CODE, H1, H2, LIST.
- **Mono** (400, 0.9375rem, 1.7): the editor. Generous leading because this is where prose is actually written.
- **Engraved** (400, 0.8125rem, tabular-nums): the room id field and error detail lines.

### Named Rules

**The Width Rule.** The label face has a width axis, and width carries meaning: **semi-condensed (`--label-width`, 87.5%) for labels**, because a label has to hold a narrow strip, and **normal (100%) for headings**, because a heading runs at reading size and should open back out. Never set a label at 100% or a heading at 87.5%; those two widths are the whole system.

**The Two-Voice Rule.** Saira is for labels and headings. The moment a string becomes a sentence somebody reads — a status readout, a hint, banner prose — it belongs to the system stack. A panel's silkscreen names things; it does not talk. If you are reaching for Saira on a sentence, the sentence is in the wrong place or the face is.

**The Terse Readout Rule.** Status lines are lowercase, dot-separated, and name the subsystem first: `subsystem · state · qualifier`. "storage · local snapshot loaded · durable". The master meter is the one exception and speaks a full capitalised sentence, because it is the line a person reads under pressure.

**The Honest Chord Rule.** A button's tooltip carries its keyboard chord only when the app actually listens for it. Bold, Italic and Code advertise Ctrl/Cmd+B, +I and +E; H1, H2 and List advertise nothing. Inventing a shortcut is worse than silence.

## Layout

Two rooms in a CSS grid: a fixed **19.5rem rack** on the left and the writing room taking the rest. Both are full viewport height and both set `min-width: 0` so long note names and long error strings truncate instead of blowing out the column.

The rack is a vertical flex column with a 1.25rem gap running: rack label → room id + copy → master meter card → error rack (conditional) → compose row → note strips. Its padding is `1.25rem 1rem 1.5rem`.

The writing room is a 1rem-gap flex column padded `1.5rem 1.75rem 1.75rem`. Inside it, the editor card is capped at **82ch** and the transport row and tag rail are capped *with it* — all three live inside the same card — so the writing column reads as one column rather than a narrow editor under a full-width rule. Banners cap at 62ch, the recovery panel at 66ch.

Vertical rhythm inside the card is a strict order: transport row, hairline, editor, hairline, tag rail. The editor grows via a grid-ish stretch on the library-owned wrapper (`flex: 1 1 auto`, `min-height: 12rem`) with `height: 100%` on the textarea, because that wrapper carries an inline `display: block` and can never be a flex container itself.

Spacing scale in use: 0.25rem between strips and between status lines, 0.4–0.5rem inside a control row, 0.75rem for card padding and intra-card gaps, 1rem for the writing room's stack, 1.25rem for the rack's stack.

**Single breakpoint: 52rem.** Below it the grid becomes one column, the rack becomes a stacked header with a bottom rule instead of a right rule, its padding drops to 1rem and its gap to 1rem, the writing room's padding drops to `1.25rem 1rem 1.5rem`, and the tag input's 14rem cap is released.

### Named Rules

**The Bounded Rack Rule.** A rack is bounded. The strip list ends in a `rule-faint` foot 0.5rem below the last strip so the column terminates rather than dissolving into a large field of undifferentiated panel.

**The No-Overflow Rule.** Every flex child in this world declares `min-width: 0`, and every text element that can receive user content declares either `text-overflow: ellipsis` or `overflow-wrap: anywhere`. A missing `min-width: 0` on the tag input is what once pushed the page 167px past a 390px viewport.

## Elevation & Depth

There are no drop shadows in the ambient sense and nothing floats. Depth is entirely tonal plus two one-pixel edges, and it encodes function: **things you act on are pressed in; things that hold are raised by a lip.**

### Shadow Vocabulary

- **Engraved** (`box-shadow: inset 0 1px 2px oklch(24% 0.012 250 / 0.09)`): inputs, note strips, the room id field (at 0.1 alpha). The signature of anything you can type into or click.
- **Lip** (`box-shadow: inset 0 1px 0 var(--panel-lip)`): the top edge of the master meter card and the editor card. A lit edge on a held object.
- **Rack edge** (`box-shadow: inset -1px 0 0 var(--panel-lip)`, wide viewports only): the sidebar's right edge, paired with a `rule` border. Removed at the narrow breakpoint.
- **Seat** (`box-shadow: 0 1px 2px oklch(24% 0.012 250 / 0.06)`): the master meter card only. The one outer shadow in the world, at 6% alpha, and it seats rather than lifts.
- **Pressed** (`box-shadow: inset 0 1px 3px oklch(24% 0.012 250 / 0.18)` plus `translateY(0.5px)`): a button's `:active` state. The panel's only physical feedback.

### Named Rules

**The Flat-Not-Metal Rule.** No gradients, no bevels, no simulated material, no outer glow. If a new surface needs to read as raised, it gets the lip; if it needs to read as recessed, it gets the engrave. There is no third option.

## Shapes

Corners are almost square, and the radius is a hierarchy of three: **2px** on anything you operate (buttons, inputs, strips, chips, the room id), **3px** on anything that holds those things (the meter card, the editor card, banners, the error rack, the recovery panel), and **1px** on the master meter's segment. Lamps are circles.

Borders are the primary form-giver: a 1px `rule` outline defines nearly every object, and `rule-faint` scores the interior of an object without splitting it. The recovery panel adds a `--strip` (0.1875rem) `lamp-armed` top edge — the record-enabled state, and the one place the panel goes red across a whole component.

**The Form-Not-Size Rule.** The master state indicator is a bar segment (0.25rem × 0.9rem, 1px radius) and the subordinate lamps are dots (0.5rem circles); the per-strip lamp is a smaller dot (0.3125rem at 0.75 opacity). The master is differentiated by *form*, not merely size, so it never reads as one more dot in a column of dots.

## Components

### Buttons

- **Shape:** near-square (2px radius), 1px `rule` border, `panel-lip` fill, weight 550, `0.45rem 0.7rem`.
- **Hover:** fill to `panel-lip`. **Active:** the Pressed inset plus a half-pixel nudge. **Disabled:** `muted` text on `panel-deep`, no shadow, `not-allowed`.
- **Transport variant:** uppercase 0.75rem/600 at 0.06em tracking, `0.4rem 0.6rem`, `min-height: 2rem` so a six-button row keeps a consistent hit target.
- **Destructive variant:** `lamp-armed` fill with `surface` text, darkening to `oklch(45% 0.2 27)` on hover. Used only for the two-step delete's commit button and the recovery overwrite.
- **Delete affordance:** a 2rem square with `muted` glyph on `panel` at rest, flooding to `lamp-armed` with knocked-out text on hover. It *arms* the action; a second, named "Delete" button commits it, with "Keep" beside it.

### Inputs

- **Style:** `surface` fill, 1px `rule`, 2px radius, the Engraved inset, `0.45rem 0.6rem`. Placeholders in `muted`.
- **Focus:** a 2px `ink` outline at 1px offset with a 1px `lamp-live` inner line. The editor is the exception: `outline-offset: -2px` and no inner line, so the ring sits inside the card it already fills.

### Note Strips (signature component)

Each strip is an engraved `surface` card carrying its own lamp on the left, the note name (truncating), and the delete affordance outside it in the same row. Selected state is `panel-lip` fill, weight 620 and a `muted` border — no lamp involvement. Dragging drops the row to 0.45 opacity; a drop target takes a 2px dashed `muted` outline at 2px offset, and an empty end-zone row (0.75rem tall) accepts a drop at the tail.

### Master Meter (signature component)

A `panel` card with the Lip and the Seat, containing four lines at a 0.25rem gap. Line one is the meter: the segment indicator plus the safety sentence, scored off from the rest by a `rule-faint` underline. Lines two through four are dots plus lowercase readouts for network, storage and local save. The card's lamp state is driven from a `data-safety` attribute on the app root (`safe` / `saving` / `at-risk` / `pending`); the three readouts drive their own lamp classes independently.

### Tag Chips

- **Chip:** `panel` fill, 1px `rule`, 2px radius, 0.75rem text, with a borderless `muted` remove button that turns `lamp-armed` on hover.
- **Filter chip:** same size, shadowless; the active filter inverts to an `ink` fill with `surface` text — the one high-contrast inversion in the world, and it is a selection, not a signal.

### Banners and the Recovery Panel

A banner is a `panel` card with a `rule` border capped at 62ch; an embedded shell command sits in an `ink` block with `panel-lip` text and horizontal scroll. The recovery panel is the escalated form: `lamp-armed` border, the 0.1875rem armed top strip, a 5%-alpha red wash, an `armed-ink` heading, and — by rule — a reassurance paragraph *first*, saying what is still safe, before any mechanism detail. While it is up, the editor goes readonly with a red-tinted border and mutations are locked.

## Do's and Don'ts

### Do:
- **Do** give every lamp a sentence beside it that states the same fact in words, and drive the lamp from the same model value the sentence comes from.
- **Do** use `armed-ink` (`oklch(43% 0.18 27)`) for red text and reserve `lamp-armed` (`oklch(52% 0.2 27)`) for lamps, destructive fills, and borders.
- **Do** draw focus in `ink` — 2px outline, 1px offset, 1px `lamp-live` inner line. It measures 11.6:1 on the rack and 15.84:1 on the surface; the amber alone measured 2.27:1 on the rack and failed non-text contrast on every control there.
- **Do** engrave what the user operates and lip what holds it, and stop at those two moves.
- **Do** give a new state indicator a distinct *form* when it outranks the indicators around it.
- **Do** state the subsystem first in a readout, lowercase, dot-separated.
- **Do** set `min-width: 0` on every flex child and give user-supplied text an ellipsis or `overflow-wrap: anywhere`.
- **Do** confirm anything that replicates to peers or discards saved bytes with a second, named button — arming and committing are different clicks.

### Don't:
- **Don't** add a second animation. `lamp-pulse` on the master meter segment while saving is the only authored motion on the page: a console's saving lamp pulses, everything else settles on `cubic-bezier(0.16, 1, 0.3, 1)`. Everything is disabled wholesale under `prefers-reduced-motion: reduce`.
- **Don't** add a dark theme, a `prefers-color-scheme` block, or cream neutrals. This world is light-only by decision; `color-scheme: light` is declared, and the product's anti-references rule out both the dark-terminal costume and cream.
- **Don't** self-host a display face, an icon font, or any binary asset. The offline story is under test here and the service worker precaches the built bundle only.
- **Don't** use a lamp colour to mean selection, category, hover, or brand.
- **Don't** introduce a second breakpoint. One at 52rem; between the two layouts, the fluid grid handles it.
- **Don't** simulate metal — no gradient, bevel, texture, or outer glow beyond the single 6%-alpha seat under the master meter.
- **Don't** light a lamp green before the bytes are actually on disk. Amber is the honest state and the panel's credibility depends on it.
