# code-map

Find declarations without reading whole source files. Code-map lists files in a
Git working tree and indexes named functions, methods, types, and module-level
constants. Use its locations to open the source; use a language server to resolve
references, inferred types, and rename operations.

The tool directory is self-contained. You can copy it into a separate repository
and use the same build and test commands. Its target repository needs no project
dependencies or compiler installation.

## Setup

Building from source requires Node 22 or newer, pnpm, and Gleam 1.18 or newer.
Run these commands in the tool directory:

```sh
pnpm install --frozen-lockfile
pnpm run build
pnpm test
```

The built CLI requires Node and Git. Keep `cli.mjs`, `lib/`, `src/`, the package
manifests and lockfiles, `node_modules/`, and `build/dev/javascript/` together.
The compiled Gleam dependency tree is part of the tool, not the target project.
Indexing does not install dependencies, run builds, execute indexed source, or
contact a service.

The package is private. Moving it to its own repository does not require changing
its core; publishing and release automation remain separate work.

## Commands

From any working directory:

```sh
node /path/to/code-map/cli.mjs --root /path/to/repository overview
node /path/to/code-map/cli.mjs --root /path/to/repository find connect --json
```

Without `--root`, code-map uses the Git working tree containing the current
directory. `--root` may name a directory inside the target working tree.
Query paths are relative to that tree's root, regardless of your current directory.

| Command | Result |
| --- | --- |
| `overview` (default) | File/symbol totals, directory groups, coverage |
| `files [--path src]` | File inventory, including unsupported and excluded files |
| `file src/example.ts` | Declarations in one file, in source order |
| `find connect [--path src] [--kind function]` | Case-insensitive literal name search |
| `refresh [--rebuild]` | Refresh the cache; rebuild discards cached parses |

Kinds are `function`, `method`, `class`, `type`, and `constant`.
Search matches names and path-qualified names, with exact name matches first,
then prefixes, then other substrings. It does not search source bodies.

`files`, `file`, and `find` accept `--limit` and `--offset` (defaults: 50 and 0).
Responses include `total`, `limit`, `offset`, and `hasMore`. Use the next offset
to retrieve further results. `overview` shows at most 50 directory groups; use
`files --path` to browse a group. Common diagnostics show at most 50 entries
with the total and `diagnosticsHasMore`; file views show that file's diagnostics.

`--json` writes one JSON object to stdout. Text views escape control characters
and quote signatures so source cannot inject terminal escape sequences.
`--help` prints command help.

| Exit status | Meaning |
| --- | --- |
| `0` | Complete within the documented parser scope; an empty search is valid |
| `1` | Invalid arguments, configuration, cache, or an operational failure |
| `2` | Current parse/read errors; useful results remain, marked `complete: false` |

An unsupported language is visible coverage, not a parse error. `complete: true`
does not claim support for all languages or runtime-generated declarations.

## Coverage

- **Gleam:** public/private functions, target variants, bodyless external
  declarations, custom/opaque types, aliases, constants, and named local
  function/capture bindings.
- **JS/TS:** named functions, nested functions, identifier-bound arrows/function
  expressions, classes, constructors, static-name methods and accessors,
  callable fields/object properties, interfaces, aliases, enums, and
  module-level constants. Supports JS, MJS, CJS, JSX, TS, MTS, CTS, and TSX.
- **Astro:** TypeScript frontmatter and executable inline scripts. JSON,
  unsupported script languages, template expressions, styles, event attributes,
  and external script contents are outside the extraction scope. External
  source files still appear when Git includes them.

Unbound anonymous callbacks and computed runtime method names have no symbols.
Gleam constructors appear through their enclosing type, not separate function
records. Exports describe syntax; the tool does not resolve cross-file re-exports
or dynamic CommonJS exports. A named function expression assigned to a named
binding appears once under the binding name.

Syntax errors invalidate that file's declarations rather than returning a
partial outline as authoritative. Other files remain available. Signatures
omit function bodies and constant initializer values; they preserve explicit
annotations and parameter defaults, not inferred types.

## Repository configuration

Optional `code-map.json` belongs at the **target repository root**:

```json
{
  "version": 1,
  "excludeDirs": ["build", "dist", "node_modules"],
  "excludePaths": ["vendor/generated"]
}
```

With no configuration, both arrays are empty. `excludeDirs` matches directory
component names at any depth. `excludePaths` matches a root-relative path and its
descendants, not similarly named siblings. Paths use `/`; no globs, absolute
paths, traversal, or duplicate entries. Unknown fields and malformed
configurations are errors. Configuration is data, not executable code.

Git supplies tracked and non-ignored untracked paths. Deleted paths disappear.
Tracked files remain visible even if Git ignores them later. Unsupported formats
and config-excluded paths retain inventory entries; the tool does not read their
contents. It does not follow symlinks or descend into submodules.

`.code-map/` is the tool's intrinsic artifact exclusion, even without a Git ignore
rule. Add `/.code-map/` to the target repository's `.gitignore` to keep the cache
out of commits. The CLI does not edit your ignore files.

## Freshness and data

Every query rediscovers paths and hashes current source bytes. It reuses a parse
only when source, tool, and configuration hashes match. An unchanged mtime or
commit SHA cannot hide an edit. Failed parses lose their old declarations and
retry on the next query.

The versioned cache is `.code-map/index.json` in the target root. It contains
relative paths, hashes, source signatures, locations, coverage details, and
diagnostics, not complete source files. The tool writes a unique temporary sibling
and renames it into place; fatal failures preserve the previous cache. A malformed
cache requires `refresh --rebuild`. You should not edit or commit cache entries.

Each file has a language, status, reason, source hash, symbols, diagnostics, and
skipped regions. Each symbol has a name, path-qualified name, enclosing named
scopes, kind, visibility, export flag, signature, range, target, and ID.
IDs encode path, scope, name, and range, so overloads and repeated names stay
distinct. IDs may change after source moves.

Ranges are half-open: start included, end excluded. `byte` is a zero-based UTF-8
offset. `line` and `column` are one-based; columns count Unicode scalar values.
Adapters normalize parser-specific positions to this contract. For example,
JavaScript compiler offsets count UTF-16 code units. Astro locations refer to
the original file, with `frontmatter` and `script:N` scopes.

The index describes files on disk. Concurrent edits can change them after a
query, and an entire repository scan is not a transactional snapshot. Read the
referenced source before making an edit.

## Library

Import the library without invoking the CLI:

```javascript
import { refreshIndex, queryIndex } from "./lib/index.mjs";

const index = await refreshIndex("/path/to/repository");
const view = queryIndex(index, {
  command: "find",
  query: "connect",
  path: "src",
  kind: "function",
  limit: 20,
  offset: 0,
});
```

`refreshIndex(root, { rebuild, config })` accepts optional rebuild and validated
configuration overrides. Without `config`, it reads the target's `code-map.json`.
`queryIndex` accepts the same query options as the CLI, using `path` for a `file`
request. Both functions report errors to the caller; neither writes to stdout
or exits the process. Only refresh reads and writes the target.

## Development and extraction

The core is Gleam compiled to JavaScript. Modules under `src/code_map/` own the
typed data model, wire validation, exclusions, symbol identity, queries, text
rendering, and cache-reuse decisions. `src/code_map.gleam` handles Gleam syntax.
Put new policy in this core rather than duplicating it in JavaScript.

JavaScript retains the TypeScript/Astro AST adapters, Node filesystem/process
operations, and the small source-coordinate helpers in `src/code_map_ffi.mjs`.
The bridge exchanges native objects, not JSON strings containing whole indexes.
`queryIndex` stays synchronous and returns plain JavaScript objects; refresh
stays asynchronous. The version-1 cache and command formats are unchanged.

`pnpm test` runs the Gleam suite and Node's built-in test runner. `pnpm run
test:node` builds the helper and runs only the Node suites. Generic tests create
their own Git repositories; they do not depend on a parent checkout.

The relocation test copies the runtime and its dependency tree outside the
checkout, checks dependency symlinks, and indexes unrelated Gleam/JS/TS/Astro
files. Consumer integrations should keep real-repository corpus assertions and
repository-specific configuration outside this directory.

`test/fixtures/contracts.json` captures synthetic pre-migration outputs. The
contract suite compares full indexes, locations, views, and text against that
fixture; do not regenerate it just to make a refactor pass.
