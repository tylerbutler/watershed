---
name: using-code-map
description: Use when navigating a Git repository with code-map available, locating named functions, methods, types or constants, inspecting file outlines, or interpreting code-map pagination, coverage and cache errors in Gleam, JavaScript, TypeScript or Astro projects.
---

# Using code-map

Find declarations, then read the matched source. Use an LSP for resolved
references, inferred types and renames; use text search for function bodies.

## Invoke

Use the repository's documented wrapper, if present. Otherwise locate the
built tool's `cli.mjs` and invoke it with Node:

```sh
node /absolute/path/to/code-map/cli.mjs --root /absolute/path/to/repository overview
```

The built CLI needs Node and Git, not the target project's dependencies.
Consult the tool's README if its build is missing. A wrapper such as
`just code-map` is repository-specific.

`--root` selects the Git working tree. Query paths are relative to that tree's
root, even when the current directory is a subdirectory. Add `--json` for
structured output; run `--help` for all options.

## Quick reference

Append these arguments to the invocation above, replacing `overview`:

| Arguments | Result |
| --- | --- |
| `overview` | Directory groups, totals and coverage |
| `files --path src` | File inventory, including excluded and unsupported files |
| `find connect --path src --kind function` | Named declarations |
| `file src/client.ts` | One file's declarations in source order |
| `refresh --rebuild` | Rebuild a malformed cache |

`find` matches case-insensitive literal substrings of names and path-qualified
names, with exact names first. For `start` or `stop`, issue separate
`find start` and `find stop` queries; `start|stop` is literal text.

For example, from a repository root with the tool under `tools/code-map`:

```sh
node tools/code-map/cli.mjs --root . find refreshIndex --path tools/code-map --json
node tools/code-map/cli.mjs --root . file tools/code-map/lib/index.mjs --json
```

Read the reported source locations before editing. Signatures omit bodies and
constant initializer values.

## Common mistakes

| Situation | Action |
| --- | --- |
| `hasMore: true` | Repeat the same query with `offset + limit` until false. Defaults are 50 and 0; 127 results need offsets 0, 50 and 100. |
| Source changed | Query again: each query hashes current bytes, regardless of mtime. Restart pagination if files change between pages. |
| Exit 2 / `complete: false` | Inspect diagnostics and affected source. Missing matches cannot establish absence. |
| Exit 1 | Resolve the reported argument, configuration or operational error. For a malformed cache, use `refresh --rebuild`. |

`complete: true` covers the supported parser scope. Excluded files, unsupported
languages and Astro template expressions remain outside declaration coverage;
inspect inventory and use permitted source-reading tools for those gaps.

The generated cache is `.code-map/index.json`. Do not edit or commit it.
