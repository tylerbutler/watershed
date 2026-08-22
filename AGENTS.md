# AGENTS.md

Agent instructions for watershed. Read this before editing.

## Commands

```
just build     # Gleam + JS bundles
just test      # Gleam, JS, and compile-fail suites
just format
just lint
```

The website is a separate Astro project under `website/` (`pnpm build`,
`pnpm run og:image` to regenerate the social card).

## Prose and copy

The repo carries a vendored instruction from `tylerbutler/apm-base` that reads
"Use ASD-STE100 when possible" at `applyTo: '**'`. Taken literally across the
whole repo, that instruction is wrong, and it has already caused one regression
(`a99e07f`, `760cb87`) that flattened the website's voice before being reverted.

Read it as scoped to **technical prose**: reference docs, API docs, doc
comments, README bodies, error messages, and assistive text (`aria-label`,
`alt`). STE is a procedure spec — it removes ambiguity, and it also removes
stakes, contrast, and second person. That trade is right for a maintenance
manual and wrong for copy whose job is to make someone care.

**STE does not apply to:** headings, hero ledes, page meta descriptions, demo
captions, button labels, tooltips, CTA and inline link text, teaser copy, or
established product naming.

Under `website/**`, `.github/instructions/website-copy.instructions.md` is
authoritative and splits every string into one of the two registers. Read it
before any copy pass there.

A copy pass that flattens voiced copy into STE is a regression even when every
individual sentence got clearer. If you cannot tell which register a string is
in, leave it alone and say so.

### Protected naming

Branding, not prose. Do not "clarify" these into generic nouns:

`field atlas` (the /structures hub) · `adjoining sheets` (the site nav) ·
`the survey procedure` (the guide steps) · `field index` · `sluice` · `ripple` ·
`gauge` · `floodgate` · `watershed`

If one is ever renamed, rename its component file in the same change. A
half-applied rename is worse than either state.

## apm-managed files

`apm.yml` / `apm.lock.yaml` vendor instructions and skills into
`.github/instructions/`, `.claude/`, and `.agents/`. Files listed in the lock's
`deployed_files` are overwritten by `apm install` — do not edit them. Put local
overrides in this file or in a non-vendored instruction file.
