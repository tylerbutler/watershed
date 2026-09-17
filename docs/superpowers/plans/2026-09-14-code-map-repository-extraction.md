# Code-map Repository Extraction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a history-preserving standalone code-map repository at `../code-map` and remove Watershed's embedded code-map package and workspace integration.

**Architecture:** Build the sibling repository from a fresh clone, then use `git filter-repo` to retain only `tools/code-map` history and move that directory to the new root. Validate the standalone package before changing Watershed. Watershed keeps target-owned `code-map.json` and `.code-map/` ignore policy, but loses the tool source, tests, recipes, dependency installation, and Trellis membership.

**Tech Stack:** Git, git-filter-repo, Gleam 1.18+, Node.js 22+, pnpm, Just, Trellis

**Spec:** `docs/superpowers/specs/2026-09-14-code-map-repository-extraction-design.md`

## Global Constraints

- Create a local sibling repository at `../code-map`; do not create or push a GitHub repository.
- Preserve commits that changed `tools/code-map`.
- Abort if `../code-map` exists.
- Keep the code-map CLI, API, cache format, parser behavior, and runtime versions unchanged.
- Keep `code-map.json` and `/.code-map/` in Watershed.
- Do not add a sibling wrapper, submodule, or package dependency to Watershed.
- Do not modify or revert unrelated uncommitted Watershed changes.
- Do not add Co-authored-by trailers to commits.

---

### Task 1: Create and Validate the Standalone Repository

**Files:**
- Create repository: `../code-map/`
- Preserve from history: `tools/code-map/**` as `../code-map/**`
- Do not modify: Watershed working-tree files

**Interfaces:**
- Consumes: committed Watershed Git history through the current `HEAD`
- Produces: a local Git repository at `../code-map` with `cli.mjs`, `lib/`, `src/`, `test/`, and package manifests at its root

- [ ] **Step 1: Read the approved design and inspect both working locations**

Run:

```bash
rtk git status --short
test ! -e ../code-map
rtk git filter-repo --help >/dev/null
```

Expected:

- Watershed may show unrelated website or APM changes.
- `test ! -e ../code-map` exits `0`.
- `git filter-repo` is available.

- [ ] **Step 2: Clone committed Watershed history into the sibling path**

Run from the Watershed root:

```bash
rtk git clone --no-local . ../code-map
```

Expected: Git creates `../code-map/.git` without copying uncommitted Watershed changes.

- [ ] **Step 3: Filter history and move the tool to the repository root**

Run:

```bash
cd ../code-map
rtk git filter-repo \
  --path tools/code-map/ \
  --path-rename tools/code-map/: \
  --force
```

Expected:

- `cli.mjs`, `gleam.toml`, `package.json`, `src/`, `lib/`, and `test/` exist at the repository root.
- No tracked path starts with `tools/code-map/`.
- Commits that never changed `tools/code-map` are absent.

- [ ] **Step 4: Verify the rewritten repository boundary**

Run:

```bash
cd ../code-map
test -f cli.mjs
test -f src/code_map.gleam
test -f test/portable.test.mjs
test -z "$(rtk git ls-files tools/code-map)"
test -z "$(rtk git remote)"
rtk git log --reverse --format='%h %ad %s' --date=short -- .
```

Expected:

- Every `test` command exits `0`.
- `git remote` prints nothing.
- History starts with the rewritten code-map introduction and includes the later typed-core migration commits.

- [ ] **Step 5: Install standalone dependencies**

Run:

```bash
cd ../code-map
rtk pnpm install --frozen-lockfile
```

Expected: pnpm installs the Node dependencies without changing `pnpm-lock.yaml`.

- [ ] **Step 6: Run the standalone test suite**

Run:

```bash
cd ../code-map
rtk pnpm test
```

Expected:

- Gleam tests pass.
- Node tests pass.
- `test/portable.test.mjs` proves that the runtime works after relocation.

- [ ] **Step 7: Prove that the standalone CLI indexes Watershed**

Run:

```bash
cd ../code-map
rtk node cli.mjs \
  --root ../watershed \
  overview \
  --json
```

Expected: the command exits `0` and reports `"complete": true`. This reads Watershed's root `code-map.json`.

- [ ] **Step 8: Confirm that Task 1 did not change Watershed**

Run:

```bash
cd ../watershed
rtk git status --short
```

Expected: the output contains only the design/plan state and the unrelated changes that existed before the clone. No code-map source or integration file has changed yet.

### Task 2: Remove the Embedded Watershed Integration

**Files:**
- Delete: `tools/code-map/**`
- Delete: `tools/code-map-watershed.test.mjs`
- Modify: `justfile:33`
- Modify: `justfile:105-118`
- Modify: `justfile:309-321`
- Modify: `gleam.toml:58`
- Modify: `gleam.toml:83-94`
- Modify: `AGENTS.md:18-39`
- Modify: `README.md:566-576`
- Keep unchanged: `code-map.json`
- Keep unchanged: `.gitignore:18`

**Interfaces:**
- Consumes: the validated standalone CLI at `../code-map/cli.mjs`
- Produces: a Watershed repository with no embedded code-map package, build step, test step, dependency install, or Trellis member

- [ ] **Step 1: Remove the embedded source and Watershed corpus test**

Run:

```bash
rtk git rm -r tools/code-map tools/code-map-watershed.test.mjs
```

Expected: Git stages only the embedded package and consumer-specific corpus test for deletion.

- [ ] **Step 2: Remove code-map from the root test and recipe graph**

Modify `justfile` so the root test target becomes:

```just
# Run tests
test: _test-gleam _test-js _test-compile-fail _test-website-snippets
```

Delete this complete block:

```just
# Syntax-backed discovery; the tool owns all indexing and configuration.
[positional-arguments]
code-map *args:
    @cd tools/code-map && gleam build >&2
    @node tools/code-map/cli.mjs "$@"

# Node contracts include the consumer-owned corpus gate; Trellis runs Gleam tests.
_test-code-map:
    cd tools/code-map && gleam build
    node --test tools/code-map/test/*.test.mjs tools/code-map-watershed.test.mjs

# Focused parser, cache, CLI, extraction, and repository-coverage suites.
code-map-test: _test-code-map
    cd tools/code-map && gleam test
```

Expected: `just --list` no longer contains `code-map` or `code-map-test`.

- [ ] **Step 3: Remove the code-map dependency install**

Change the dependency target in `justfile` to:

```just
deps: _deps-gleam _deps-live-js _deps-bundles
```

Delete:

```just
_deps-code-map:
    pnpm --dir tools/code-map install
```

Expected: `just deps` no longer enters `tools/code-map`.

- [ ] **Step 4: Remove code-map from Trellis configuration**

In `gleam.toml`, remove `"tools/code-map"` from:

- `[tools.trellis.exclude]."@release"`;
- `[tools.trellis.exclude].build-erlang`;
- `[tools.trellis.exclude].bundle`.

The resulting values must be:

```toml
"@release" = ["examples/*", "tools/compile-fail/*", "tools/website-samples", "tools/source-snippets"]
```

```toml
build-erlang = ["watershed_lustre", "examples/*_lustre", "tools/compile-fail/*", "tools/website-samples", "tools/source-snippets"]
```

```toml
bundle = [
    ".",
    "watershed_lustre",
    "examples/dice_cli",
    "examples/scoreboard_cli",
    "tools/compile-fail/*",
    "tools/website-samples",
    "tools/source-snippets",
]
```

Expected: Trellis no longer discovers or excludes an embedded code-map package.

- [ ] **Step 5: Update contributor instructions for the external tool**

Replace the `AGENTS.md` code discovery section with:

````markdown
## Code discovery

Use the standalone code-map sibling for repository outlines and declaration
search:

```sh
node ../code-map/cli.mjs --root . overview
node ../code-map/cli.mjs --root . find <name>
node ../code-map/cli.mjs --root . file <path>
```

Add `--json` for structured output. Results default to 50 entries; when
`hasMore` is true, repeat with the next `--offset`.

The tool refreshes from on-disk source before queries. Exit 2 and
`complete: false` mean some files could not be read or parsed; do not treat
their missing declarations as evidence that the code does not exist. Read
referenced source before edits and use an LSP for resolved references or
renames. Do not edit or commit `.code-map/`.

Watershed owns the exclusions in root `code-map.json`. Code-map source,
tests, dependencies, and policy belong to the standalone sibling repository.
````

Expected: contributor instructions no longer claim that Watershed builds or tests code-map.

- [ ] **Step 6: Update the root README**

Replace the embedded-tool paragraphs in `README.md` with:

````markdown
For source navigation with a sibling code-map checkout:

```sh
node ../code-map/cli.mjs --root . overview
node ../code-map/cli.mjs --root . find connect --path src
node ../code-map/cli.mjs --root . file src/watershed/p2p.gleam
```

Add `--json` for agent-readable results. Queries refresh an ignored cache from
current source; they do not require an application or website build.
Watershed supplies repository-specific exclusions through
[`code-map.json`](code-map.json).
````

Expected: the README does not link to deleted tool source or test files and does not list removed Just recipes.

- [ ] **Step 7: Check for stale embedded-path references**

Run:

```bash
rtk rg -n "tools/code-map|code-map-watershed|just code-map|code-map-test|_deps-code-map|_test-code-map" \
  AGENTS.md README.md justfile gleam.toml docs .github
```

Expected: no stale reference remains outside the approved design and implementation plan, which document the migration.

- [ ] **Step 8: Validate Just and Trellis configuration**

Run:

```bash
rtk just --list
rtk trellis doctor
rtk just build
```

Expected:

- Just parses the edited file and does not list removed code-map recipes.
- Trellis reports a valid workspace without `tools/code-map`.
- The existing Watershed build completes.

- [ ] **Step 9: Run the Watershed test graph**

Run:

```bash
rtk just test
```

Expected: Watershed's existing Gleam, JavaScript, compile-fail, and website snippet suites run without a code-map step. If an unrelated pre-existing failure appears, reproduce it from unchanged `HEAD` before classifying it as a baseline failure.

- [ ] **Step 10: Re-run the standalone CLI against cleaned Watershed**

Run:

```bash
rtk node ../code-map/cli.mjs \
  --root . \
  overview \
  --json
```

Expected: the command exits `0`, reports `"complete": true`, and applies the unchanged Watershed `code-map.json`.

- [ ] **Step 11: Review the final cross-repository state**

Run:

```bash
rtk git status --short
rtk git diff --check
rtk git diff --stat
cd ../code-map
rtk git status --short
rtk git remote -v
```

Expected:

- Watershed shows the planned deletions and configuration/documentation edits plus untouched unrelated user changes.
- The standalone repository is clean.
- The standalone repository has no remote.

- [ ] **Step 12: Commit only the Watershed extraction changes**

Stage these paths:

```bash
cd ../watershed
rtk git add \
  AGENTS.md \
  README.md \
  justfile \
  gleam.toml \
  tools/code-map \
  tools/code-map-watershed.test.mjs
rtk git diff --cached --check
rtk git diff --cached --stat
rtk git commit -m "refactor: extract code-map repository"
```

Expected: the commit excludes unrelated website and APM changes and has no Co-authored-by trailer.

- [ ] **Step 13: Verify both persistent results**

Run:

```bash
cd ../watershed
rtk git show --check --stat --oneline HEAD
test ! -e tools/code-map
test ! -e tools/code-map-watershed.test.mjs
test -f code-map.json

cd ../code-map
test -d .git
test -f cli.mjs
test -z "$(rtk git remote)"
rtk pnpm test
rtk node cli.mjs --root ../watershed overview --json
```

Expected:

- The Watershed extraction commit contains only the planned paths.
- The embedded package and corpus test are absent.
- The target-owned configuration remains.
- The standalone suite passes and the standalone CLI indexes Watershed with complete coverage.
