# Code-map Repository Extraction Design

## Goal

Extract `tools/code-map` into a local sibling repository at `../code-map`.
Preserve the commits that changed the tool, and remove the tool's source,
build, test, and dependency integration from Watershed.

The extracted repository must build and test without Watershed. Code-map must
still index Watershed when invoked with Watershed as its target repository.

## Current State

`tools/code-map` is a self-contained Gleam and Node package. It owns its source,
generic tests, package manifests, lockfiles, CLI, and README. Its relocation
test copies the runtime outside the Watershed checkout and indexes an unrelated
repository.

Watershed supplies the remaining consumer-specific integration:

- `code-map.json` defines exclusions for the Watershed source tree.
- `tools/code-map-watershed.test.mjs` checks Watershed corpus coverage.
- `just code-map` and `just code-map-test` build and run the embedded package.
- `just deps` installs the package's Node dependencies.
- the Trellis workspace includes `tools/code-map`.
- root documentation describes the embedded workflow.

The Watershed working tree contains unrelated uncommitted website and APM
changes. The extraction must preserve those changes.

## Repository Split

Create `../code-map` from a fresh local clone of Watershed. Do not build the new
repository from the current working tree or copy files from it.

Run `git filter-repo` in the clone with:

```sh
git filter-repo \
  --path tools/code-map/ \
  --path-rename tools/code-map/: \
  --force
```

This rewrites the selected commits so the former tool directory becomes the
new repository root. It excludes Watershed files and commits that never changed
the tool. Remove or verify the absence of the Watershed remote after filtering.
The task creates a local repository only and does not create or push a GitHub
repository.

Abort before cloning if `../code-map` exists. Do not overwrite, merge, or delete
an existing sibling directory.

## Standalone Repository Boundary

The new repository owns the current contents of `tools/code-map`, including:

- the Gleam core under `src/`;
- Node adapters, filesystem operations, and the CLI;
- generic Gleam and Node tests;
- parser contract fixtures and the relocation test;
- `gleam.toml`, `manifest.toml`, `package.json`, pnpm files, and lockfiles;
- the code-map README and ignore rules.

Keep the package private. Publishing, release automation, a GitHub remote, and
new packaging formats are separate work.

The extraction does not change the core API, cache format, CLI format, parser
coverage, or supported runtime versions.

## Watershed Boundary

Remove these files and integrations from Watershed:

- `tools/code-map/`;
- `tools/code-map-watershed.test.mjs`;
- the `just code-map`, `_test-code-map`, and `code-map-test` recipes;
- the code-map install command in `just deps`;
- all `tools/code-map` Trellis exclusions and workspace task entries.

Keep `code-map.json` at the Watershed root. Target repositories own their
code-map configuration, so this file remains useful when an external code-map
installation indexes Watershed. Keep the `.code-map/` ignore rule for the same
reason.

Update `AGENTS.md` and the root README. They must describe code-map as an
external tool and show an invocation that selects Watershed with `--root`.
Remove statements that Watershed owns, installs, builds, or tests code-map.

Do not add a sibling-path wrapper to Watershed. Other clones and CI jobs cannot
assume that `../code-map` exists.

## Migration Order

1. Confirm that `../code-map` does not exist.
2. Clone Watershed into `../code-map`.
3. Filter the clone to `tools/code-map` and move that path to the repository
   root through history rewriting.
4. Install the standalone dependencies and run its tests.
5. Run the standalone CLI against the Watershed checkout.
6. Remove the embedded package and its Watershed integrations.
7. Update Watershed documentation.
8. Run the focused Watershed build and test checks.

Validate the new repository before removing the embedded copy. A failed split
must leave Watershed unchanged.

## Failure Handling

Stop if the sibling destination exists, the history rewrite fails, dependency
installation fails, or the standalone tests fail. Keep the failed clone for
inspection unless it contains no useful state and its exact path is safe to
remove.

Do not convert test failures into successful results. Do not fall back to a
snapshot repository if filtered history fails. Report the blocking command and
its error.

The Watershed cleanup must not modify or revert unrelated uncommitted files.
Stage and commit only extraction-related paths if the implementation creates
commits.

## Verification

In `../code-map`:

1. Confirm that tracked paths start at the repository root and no
   `tools/code-map` prefix remains.
2. Confirm that Git history contains the commits that introduced and changed
   code-map.
3. Run `pnpm install --frozen-lockfile`.
4. Run `pnpm test`, including the relocation test.
5. Run the CLI with `--root` against Watershed and require complete coverage.

In Watershed:

1. Confirm that no build, test, dependency, or Trellis reference points to
   `tools/code-map`.
2. Confirm that `code-map.json` remains valid when the standalone CLI indexes
   Watershed.
3. Run the smallest existing build and test commands that cover the changed
   Trellis and `just` configuration.
4. Confirm that unrelated working-tree changes match their pre-extraction
   state.

## Non-goals

- Creating or pushing a GitHub repository.
- Adding code-map to Watershed as a submodule or package dependency.
- Keeping optional `../code-map` wrappers in Watershed.
- Preserving the Watershed-specific corpus test.
- Publishing code-map or adding release automation.
- Changing code-map behavior during extraction.
