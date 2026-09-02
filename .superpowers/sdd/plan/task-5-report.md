# Task 5 report — replace Astro extraction with the generated manifest

## Summary

The website no longer extracts code. `website/src/lib/snippet.ts` is a
manifest consumer: it imports the ignored `src/generated/snippets.json`,
decodes it strictly, and hands out one snippet per id. Every source-backed
page and registry asks for a generated id. The TypeScript definition and
marker extractors, the composite origin, the whole-file helper, the
transitional guide registry, and all 44 `?raw` Gleam and `.mjs` imports
are gone — 1784 lines deleted against 852 added.

The rendered site is byte-identical on 37 of 40 pages. The other three differ
by exactly the eight accepted `@target(javascript)` lines Task 4 predicted,
and by nothing else.

## The loader

`snippet.ts` exports the interface the brief specified, with the whole-file
origin the fix round of Task 4 added:

```ts
export interface Snippet {
  code: string;
  language: string;
  sourcePath: string;
  sourceUrl?: string;
  origin: SnippetOrigin;
}

export type SnippetOrigin =
  | { kind: "source"; markers: string[] }
  | { kind: "file" }
  | { kind: "literal" };

export function decodeManifest(value: unknown): Map<string, Snippet>;
export function sourceSnippet(id: string): Snippet;
export function sourceSnippetIds(): string[];
export function snippetFromLiteral(code, language, sourcePath, sourceUrl?): Snippet;
export function withSourceUrl(snippet: Snippet, sourceUrl: string): Snippet;
export function isSourceBacked(snippet: Snippet): boolean;
```

Decoding takes `unknown` and narrows it. There is no `as any`, no cast of the
imported JSON to a declared shape, and no empty-map fallback: a silently
empty manifest would take every code block off the site without failing the
build. Each rejection names the entry at fault.

| Shape | Rejected because |
| --- | --- |
| not an object, or an array | a manifest is a document |
| `version` absent, `"1"`, or `2` | only version 1 is understood |
| `snippets` absent or an array | entries are keyed by id |
| entry not an object | an entry is a record |
| `code` / `language` / `sourcePath` absent, non-string, or blank | a blank citation is not a citation |
| `origin` absent, or kind `"definition"`, `"marker"`, `"composite"` | the manifest speaks `source` and `file` only |
| `origin.kind` `"literal"` | the manifest holds source-backed code only |
| `source` with no `markers`, `[]`, a string, a non-string element, or a blank id | a range selection names ranges |
| `file` that also names markers | a listing selected no marker |

`sourceSnippet` throws on an unknown id and names it. Entries are frozen, so
no caller can edit the manifest for everyone else; `withSourceUrl` therefore
returns a copy rather than assigning, which is what `FieldNotes.astro` needs.

The manifest is read with an import attribute:

```ts
import generatedManifest from "../generated/snippets.json" with { type: "json" };
```

Both runtimes that matter accept it, verified before the loader was written:
Node 24 with `--strip-types`, and Astro 7 / Vite in a throwaway page that
rendered the entry count and was then removed. An `fs` read was rejected: in
an SSR build `import.meta.url` points at the emitted chunk, not the source
tree, so a relative read would resolve somewhere else.

## What now asks for an id

| Surface | Before | After |
| --- | --- | --- |
| `src/data/practice-snippets.ts` | 17 `?raw` imports, a paths object, 17 extractor calls | 17 `sourceSnippet("practice-…")` lines |
| `src/data/standalone-snippets.ts` | 7 `?raw` imports, a paths object, 10 extractions, 7 TS literals | 10 `sourceSnippet(…)` lines, the same 7 TS literals |
| `src/data/guide-snippets.ts` | 1 whole-file entry | deleted; the sheet calls `sourceSnippet` |
| `pages/guide/{connect,notes,votes,presence,testing}.astro` | 9 `?raw` imports, 30 extractions | 30 `sourceSnippet(…)` lines |
| `pages/foundations/{lifecycle,schema,topology}.astro` | 10 `?raw` imports, 21 extractions | 21 `sourceSnippet(…)` lines |
| `components/FieldNotes.astro` | `{ ...practice.snippet, sourceUrl }` | `withSourceUrl(practice.snippet, …)` |

The one-entry guide registry is folded, as the binding required:
`connect.astro` reads `sourceSnippet("guide-connect-schema")` beside its six
other ids, and there is no fourth way to reach a snippet.

Preserved deliberately: the seven Fluid TypeScript literals and their syntax
checks, the `gleam.toml` TOML listing (a `?raw` import of a manifest file, not
of source), the two shell literals, the three `text` layout diagrams, and the
four allowlisted illustrative Gleam literals on `guide/connect`,
`guide/votes`, `guide/testing`, and `runtime/presence`. Every source path,
link, and caption on every sheet is unchanged.

## Gates

`drift-gates.test.ts` policed a frontend that extracted. Five gates were
rewritten around one that reads ids.

- **Gate 1** was "declared `?raw` paths exist". It is now "every rendered id
  is declared and generated": each `sourceSnippet("…")` call in an authored
  module must name an id `website/snippets.json` declares and the manifest
  holds, whose `sourcePath` exists. It runs the other way too — a configured
  id nothing renders fails. Both directions are currently exact at 78.
- **Gate 5** was "the paths object has no empty values". Paths objects are
  gone, so it is now "only the loader reads the generated manifest": no other
  authored module may import `src/generated/snippets.json`, and the loader
  must decode rather than cast (`decodeManifest` present, `as any` absent).
- **Gate 6** allowed `?raw` Gleam in listed descriptor files. It now forbids
  `?raw` imports of `.gleam` and `.mjs` anywhere, with no allowlist, and a
  negative test pins that a `.toml` listing is not caught by it.
- **Gate 7** checked that paths objects matched `?raw` imports. Deleted with
  both.
- **Gate 4** now also checks each registry names generated ids: 17 for the
  practices, at least 10 for the standalone sheet.
- `SNIPPET_DESCRIPTOR_FILES` is gone. It existed to say which files could
  import raw Gleam; nothing can. Marker references now come from the
  configuration alone, which is the only descriptor left.

Gates 2, 3, 8, 9, and 10 are unchanged in substance. Gate 9's fixtures were
updated to the current origin vocabulary, and its failure message now names
the functions that exist.

## RED → GREEN

RED, with the tests written first and no implementation:

```
$ node --strip-types --test src/lib/snippet.test.ts
SyntaxError: The requested module './snippet.ts' does not provide an export named 'decodeManifest'
ℹ tests 1 ℹ pass 0 ℹ fail 1

$ node --strip-types --test src/lib/snippet-manifest.test.ts
SyntaxError: The requested module './snippet.ts' does not provide an export named 'sourceSnippet'
ℹ tests 1 ℹ pass 0 ℹ fail 1
```

GREEN after the loader: 31 and 172 passing.

The manifest was generated before the Node run, as the binding required —
`gleam run -m source_snippets/cli -- ../../website/snippets.json ../../website/src/generated/snippets.json`,
now wired into `just website-snippets`, `pnpm snippets`, `prebuild`, and
`predev`. Deleting the generated file and running `pnpm build` regenerates it
and completes; running a Node suite without it fails with
`ERR_MODULE_NOT_FOUND` naming the exact path.

## Suites

`src/lib/snippet-markers.test.ts` and `src/data/guide-snippets.test.ts` both
replicated extraction in Node to check what the registry would produce. There
is nothing to replicate now, so their assertions moved into
`src/lib/snippet-manifest.test.ts`, which reads the real manifest: the
configured ids and the generated ids are the same set, each entry keeps its
configured path, language, and selection, the seven marker ranges still hold
the code their sheet discusses, the whole-file listing still opens with the
module documentation and keeps every other line, and composed snippets keep
their order and separator.

The practice and standalone suites now import the registries directly —
possible for the first time, because no module reads source with `?raw`. They
test the snippets the site renders rather than a reconstruction of them. The
Fluid TypeScript literals are parsed as the registry exports them, instead of
being scraped back out of the registry's source text with a regex.

## Parity

40 emitted HTML files, compared against a build of `e888a76` taken before any
edit.

- 37 files md5-identical, including every guide sheet, the homepage, both
  runtime sheets, `/sharedtree`, and every field note.
- 3 files differ: `/foundations/lifecycle`, `/foundations/schema`,
  `/foundations/topology`.
- Stripping tags, those three differ by 8 hunks in total, each one line:
  `@target(javascript)` added above the doc comment of
  `foundations-lifecycle-ensure-channel`, `foundations-schema-get-field`,
  `foundations-schema-stamp`, and the five `foundations-topology-*`
  definitions. Nothing else on those pages moved.

That is exactly the set Task 4 recorded and this task was told to accept: all
eight are `src/watershed.gleam` definitions whose start marker `gleam format`
moves above the attribute, so a faithful range includes it. The old extractor
dropped the line because it walked up over `//` comments only.

Nearby copy was checked and needs no change. Neither foundations sheet claims
anything about compilation targets: `grep` for `target`, `javascript`,
`BEAM`, `Erlang`, and `watershed_beam` across the three pages and
`src/data/foundations.ts` returns one hit, "two browser tabs", which is about
tabs. The prose around each of the eight explains semantics — handles,
attachment, typed reads — and the attribute neither contradicts nor duplicates
it. The cross-runtime comparison lives on `guide/connect`, which is unchanged.

## Builds and tests

| Command | Result |
| --- | --- |
| `just _test-website-snippets` | 31 + 172 + 29 + 39 + 1282 + 667 + 1 = 2221 passed, 0 failed |
| `cd website && pnpm build` | prebuild regenerates, gates pass, 36 pages |
| `cd website && pnpm build` from a deleted manifest | regenerated, 36 pages |
| `cd tools/source-snippets && gleam test` | 109 passed, no failures |
| `just lint` | clean across every package |

The recipe is one suite shorter than at `e888a76` (seven, not eight) and 391
assertions longer, because the gates now iterate ids rather than descriptor
files.

## Self-review

- No generated file is committed. `website/src/generated/.gitignore` ignores
  everything but itself, and `git status --untracked-files=all` shows the
  `.gitignore` alone.
- No authored module imports the manifest, and the gate that says so is not
  self-referential: it reads the loader and asserts the loader does import it.
- The eight-line rendering change is the only difference in the built site,
  and it was measured rather than assumed.
- Nothing in the repository still names `snippetFromDefinition`,
  `snippetFromMarker`, `combineSnippets`, `snippetFromWholeFile`,
  `originParts`, or `guide-snippets`.

## Concerns

1. **A missing manifest fails as `ERR_MODULE_NOT_FOUND`, not as advice.** The
   build and the test recipe both generate first, so this only bites someone
   who runs `node --strip-types --test` by hand in a fresh checkout. The
   message does name the exact path. A friendlier error would need the loader
   to read the file itself, which the SSR chunk path rules out.
2. **The two-way id gate is exact today.** 78 configured, 78 rendered. That
   is a strong gate, and it will fail the moment someone adds a configuration
   entry before the sheet that quotes it. That is the intended order of work,
   but it is worth knowing before a half-finished branch runs the suite.
3. **Task 4's concerns 2 and 4 still stand.** Marker roots are still listed
   per package, and the repository configuration test still lives inside the
   generic `source_snippets` package.
4. **`findAstroPages` in the gates is dead code**, and was already dead at
   `e888a76`. Left alone rather than swept in with this change.

---

## Review fix — Netlify Erlang toolchain

### Finding

The website prebuild now runs the Erlang-target `tools/source-snippets` CLI
(`pnpm snippets`), but Netlify installs only Gleam. The committed
`netlify.toml` uses base `website` and `website/scripts/netlify-build.sh`,
so deploy lacks `escript` and `erlc`.

### Fix

Three files, smallest Netlify-native approach:

| File | Change |
| --- | --- |
| `website/Aptfile` | Lists `erlang-base`, which provides `escript` and `erlc` on the Ubuntu build image. Read by `netlify-plugin-apt` before the build command. |
| `netlify.toml` | Adds `[[plugins]] package = "netlify-plugin-apt"` so the Aptfile is honoured. |
| `website/scripts/netlify-build.sh` | Early loop checks `escript` and `erlc` are on PATH; exits with actionable diagnostics naming the Aptfile and plugin if either is missing. Comments updated to describe source-snippet manifest generation. |

### Test — RED then GREEN

`website/scripts/netlify-erlang-contract.test.mjs` — 5 assertions, no
dependencies beyond `node:test` and `node:fs`:

1. `website/Aptfile` exists.
2. Aptfile lists an `erlang` package.
3. `netlify.toml` references `netlify-plugin-apt`.
4. `netlify-build.sh` mentions `escript`.
5. `netlify-build.sh` mentions `erlc`.

RED (before fix — all 5 fail):
```
$ node scripts/netlify-erlang-contract.test.mjs
✖ website/Aptfile exists
✖ Aptfile lists an Erlang package that provides escript
✖ netlify.toml configures the apt plugin
✖ netlify-build.sh checks for escript before building
✖ netlify-build.sh checks for erlc before building
ℹ pass 0  ℹ fail 5
```

GREEN (after fix — all 5 pass):
```
$ node scripts/netlify-erlang-contract.test.mjs
✔ website/Aptfile exists
✔ Aptfile lists an Erlang package that provides escript
✔ netlify.toml configures the apt plugin
✔ netlify-build.sh checks for escript before building
✔ netlify-build.sh checks for erlc before building
ℹ pass 5  ℹ fail 0
```

Wired into `pnpm test:netlify-contract` in `website/package.json` and
appended to `just _test-website-snippets` so it runs with every website
test invocation.

### Verification

| Command | Result |
| --- | --- |
| `bash -n website/scripts/netlify-build.sh` | Syntax OK |
| `cd website && pnpm build` | prebuild + build, 36 pages |
| `just _test-website-snippets` | all suites pass, 0 failures |

### Concern

`erlang-base` is the correct package name across Ubuntu 20.04–24.04 (the
Netlify build image range). If a future image drops to a minimal base that
splits `erlc` into `erlang-dev`, the contract test will still pass (it checks
the script, not the package contents) but the deploy will fail at the
toolchain check with an actionable message naming the Aptfile.
