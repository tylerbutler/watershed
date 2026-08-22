---
description: Two-register copy style for the watershed website — where ASD-STE100 applies and where it must not
applyTo: 'website/**'
---

# House style for website copy

> **Overrides `use-ste.instructions.md` for these paths.** That instruction is
> vendored from `tylerbutler/apm-base` and applies STE at `applyTo: '**'` with
> no scoping. It is wrong for the copy listed under Register B below, and this
> file wins there. Do not edit the vendored file — `apm install` reverts it.


The site's job is to make a reader care enough to read the technical parts. Two
registers, and the register is chosen by *where the text sits*, not by how
technical it is.

## Register A — plain and procedural (ASD-STE100)

Apply STE here. Short sentences, one idea each, active voice, no contractions,
no idioms, consistent term per concept, spelled-out abbreviations on first use.

- API and structure reference prose
- The `detail:` / `rule:` / `body:` strings in `website/src/data/*.ts`
- Comparison tables and definition lists
- `aria-label`, `alt`, and other assistive text — these must be literal
- Setup and installation steps

## Register B — voiced (STE does not apply)

These exist to create interest, name stakes, and invite an action. Flattening
them costs more than the ambiguity it removes.

- `<h1>` and `<h2>` headings
- Hero ledes and page `description=` meta
- Demo captions, `data-caption-idle`, button labels, slider `title` tooltips
- CTA and inline link text
- The teaser/outro asides that sell the next page

### What Register B is allowed to do

- **Name stakes.** "It's the classic distributed-systems bug" beats "Use a
  counter structure to prevent this error."
- **Set up a wrong idea and knock it down.** "Nothing is wrong with the map: a
  counter just is not a single mutable cell." Preempting a misreading is worth
  more than asserting the fact.
- **Address the reader.** "Try cutting Client B's link mid-edit," not
  "Disconnect Client B."
- **Use em-dashes, contractions, sentence fragments, and rhetorical questions.**
- **Make a heading name an idea, not a fact.** "Every edit is a bet on the
  order" over "Local edits predict server order." A heading that is only a fact
  is not shorter, just emptier.

### What Register B still may not do

Hype, superlatives, or claims the page does not back up. Voice is not looseness:
"deliberately nasty orderings" is a real claim about test design and the tests
back it.

## Protected naming

The site's identity is survey sheets and hydrology. These names are branding,
not prose — do not "clarify" them into generic nouns:

`field atlas` (the /structures hub) · `adjoining sheets` (the site nav) ·
`the survey procedure` (the guide steps) · `field index` · `sluice` · `ripple` ·
`gauge` · `floodgate` · `watershed`

If one of these ever does get renamed, rename the component file with it. A
half-applied rename is worse than either state.

## When a copy pass is requested

Say which register each file falls in before editing, and report anything you
moved between registers. A pass that flattens Register B into Register A is a
regression even when every individual sentence got clearer.
