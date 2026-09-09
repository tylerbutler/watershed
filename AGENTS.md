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

## Code discovery

Use `just code-map overview` for a repository outline, `just code-map find
<name>` to locate declarations, and `just code-map file <path>` for a file's
functions and types. Add `--json` for structured output. Results default to
50 entries; when `hasMore` is true, repeat with the next `--offset`.

The tool refreshes from on-disk source before queries. Exit 2 and
`complete: false` mean some files could not be read or parsed; do not treat
their missing declarations as evidence that the code does not exist. Read
referenced source before edits and use an LSP for resolved references or
renames. Do not edit or commit `.code-map/`.

`tools/code-map/` is a self-contained, extractable tool. Keep repository-specific
exclusions in root `code-map.json` and corpus assertions in
`tools/code-map-watershed.test.mjs`, outside the tool. Run its focused suites
with `just code-map-test`; `just deps` installs its isolated Node dependencies.

Code-map policy belongs in its typed Gleam core (`tools/code-map/src/code_map/`).
Keep JavaScript focused on Node I/O, compiler AST adapters, and native source
offset operations. Preserve the plain-object JS API and versioned wire formats.

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

Website pages and components must not import `.gleam` or `.mjs` files with
Vite's `?raw` query or extract source text at runtime. They request generated
snippets with `sourceSnippet(id)` instead. Only
`website/src/components/SnippetBlock.astro` may import or render Astro's
`Code` component; callers render source-backed snippets through
`SnippetBlock`, and use `snippetFromLiteral` only for illustrative text that
does not quote source.

The generator is a Gleam package that targets JavaScript and runs on Node —
`gleam run -m source_snippets/cli` with no `--target` flag, because its own
`gleam.toml` names the target. Trellis builds and tests it with the
JavaScript family and leaves it out of the Erlang build entirely. That is
what lets Netlify deploy the site with nothing but Node and the Gleam
compiler; the build image's Erlang is too old for `gleam_json` and we do not
want it in the loop.

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
