---
description: House style for the watershed website — voiced copy, ASD-STE100 does not apply here
applyTo: 'website/**'
---

# House style for website copy

> **Overrides `use-ste.instructions.md` for these paths.** That instruction is
> vendored from `tylerbutler/apm-base` and applies STE at `applyTo: '**'` with
> no scoping. STE belongs to the docs — reference prose, API docs, doc
> comments, error messages — not to the site. This file wins under `website/**`.
> Do not edit the vendored file — `apm install` reverts it.

The site's job is to make a reader care enough to read the technical parts.
Write it in full voice: em-dashes, contractions, sentence fragments, rhetorical
questions, second person. Two copy passes have already flattened this site into
STE (`a99e07f`, `760cb87`); both were reverted. Do not do it a third time.

## What the voice is allowed to do

- **Name stakes.** "It's the classic distributed-systems bug" beats "Use a
  counter structure to prevent this error."
- **Set up a wrong idea and knock it down.** "Nothing is wrong with the map: a
  counter just is not a single mutable cell." Preempting a misreading is worth
  more than asserting the fact.
- **Address the reader.** "Try cutting Client B's link mid-edit," not
  "Disconnect Client B."
- **Make a heading name an idea, not a fact.** "Every edit is a bet on the
  order" over "Local edits predict server order." A heading that is only a fact
  is not shorter, just emptier.

This covers headings, hero ledes, page `description=` meta, demo captions,
button labels, tooltips, CTA and link text, teaser asides, and the `rule:` /
`body:` / `detail:` strings in `website/src/data/*.ts`.

## What it still may not do

Hype, superlatives, or claims the page does not back up. Voice is not looseness:
"deliberately nasty orderings" is a real claim about test design and the tests
back it.

## The one literal exception

`aria-label`, `alt`, and other assistive text must be plain and literal. Screen
reader output is not a place for voice.

## Protected naming

The site's identity is survey sheets and hydrology. These names are branding,
not prose — do not "clarify" them into generic nouns:

`field atlas` (the /structures hub) · `adjoining sheets` (the site nav) ·
`the survey procedure` (the guide steps) · `field index` · `sluice` · `ripple` ·
`gauge` · `floodgate` · `watershed`

If one of these ever does get renamed, rename the component file with it. A
half-applied rename is worse than either state.

## When a copy pass is requested

A pass that flattens voiced copy toward STE is a regression even when every
individual sentence got clearer. If a string reads flat, the fix is more voice,
not less.
