# AGENTS.md

Agent instructions for watershed. Read this before editing.

## Commands

```
just build     # Gleam + JS bundles
just test      # Gleam, JS, and compile-fail suites
just format
just lint
just snippets  # regenerate the website's snippet manifest
```

The website is a separate Astro project under `website/` (`pnpm build`,
`pnpm run og:image` to regenerate the social card).

## Website code snippets

Every code block on the site that quotes real source comes from
`website/src/generated/snippets.json`. That file is generated and ignored, so
do not edit it and do not commit it. The committed inputs are
`website/snippets.json`, which declares one entry per snippet, and the
`// docs:snippet-start <id>` / `// docs:snippet-end <id>` marker pairs in the
sources themselves. `tools/source-snippets` reads both and writes the
manifest; its README documents the schema and marker placement.

`just snippets` regenerates it by hand. `pnpm build`, `pnpm dev`, and
`just test` already do it first, so an edited marker shows up without asking.
Every marker must be quoted by a snippet and every snippet must find its
marker, or generation fails and names the file.

## Prose and copy

The repo carries a vendored instruction from `tylerbutler/apm-base` that reads
"Use ASD-STE100 when possible" at `applyTo: '**'`. Taken literally across the
whole repo, that instruction is wrong, and it has already caused one regression
(`a99e07f`, `760cb87`) that flattened the website's voice before being reverted.

Read it as scoped to **Gleam source**: `**/*.gleam` only. That means module and
function doc comments (`////`, `///`), inline `//` comments, and the strings in
error values. Short sentences, one idea each, active voice, no contractions, no
idioms, one consistent term per concept. A comment is read by someone debugging
at speed, and STE is built for exactly that.

**STE does not apply anywhere else.** Markdown under `docs/`, READMEs, design
notes, changelogs, commit messages, and everything under `website/**` are
written in normal prose with a voice.
`.github/instructions/website-copy.instructions.md` is authoritative for the
site — read it before any copy pass there. The one exception that runs the other
way is assistive text (`aria-label`, `alt`), which stays plain and literal
everywhere.

A copy pass that flattens voiced prose toward STE outside `**/*.gleam` is a
regression even when every individual sentence got clearer.

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
