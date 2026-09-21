# SharedTree interoperability oracle

This development-only package runs actual Fluid SharedTree code. It is not a
production dependency, a native tree implementation, or evidence that Watershed
can yet load a SharedTree document.

The public collaboration test uses an in-memory service. The source capture uses
upstream's deterministic DDS test runtimes. Neither substitutes for the M0
real-service preflight or the full conformance corpus.

## Reference

| Item | Pin |
| --- | --- |
| `fluid-framework`, `@fluidframework/tree`, `@fluidframework/local-driver` | `3.1.0` |
| Source tag | `client_v3.1.0` |
| Source commit | `c3c5bf0ecd313362e83fe8a02b7d39e7e0736960` |
| Source package manager | `pnpm@11.15.1`, from the pinned manifest |
| Source Node requirement | `>=22.22.2` |

The release uses Node-only test tooling. Its dependencies and build outputs stay
under the ignored `.reference/` directory. The npm lockfile covers this package's
published dependencies; the pinned upstream lockfile covers its source build.

## Run

From the Watershed repository root:

```sh
npm --prefix tools/shared-tree-oracle ci
npm --prefix tools/shared-tree-oracle test
npm --prefix tools/shared-tree-oracle run source:prepare
npm --prefix tools/shared-tree-oracle run source:verify
npm --prefix tools/shared-tree-oracle run source:capture
```

The capture is written to `.output/source/source-smoke.json`. To choose an output
directory, pass an absolute path:

```sh
npm --prefix tools/shared-tree-oracle run source:capture -- /tmp/watershed-tree-capture
```

`source:prepare` installs only the upstream tree's dependency closure and the
workspace root, with `--frozen-lockfile`. It invokes the exact pnpm version
through `npm exec`; it does not depend on the host's Corepack-selected version.
Browser downloads are disabled because this oracle does not run a browser.

The source runner builds upstream's `compile` task and ESM tests, then runs only
the injected oracle with Mocha. It supplies upstream's
`allow-ff-test-exports` Node condition. It does not run the release's unrelated
lint, API-report, benchmark, or snapshot suites.

### Checkout ownership

Preparation checks the exact source commit and package versions. It refuses
changed tracked files, unrelated untracked files, a symbolic-link checkout, and
an injected test whose contents differ from `upstream-oracle.spec.ts`.

Only `packages/dds/tree/src/test/watershedOracle.spec.ts` is injected. If you
intentionally edit the oracle after preparing a checkout, review the old injected
copy and remove that one file before preparing again. Do not discard other
reference changes to make verification pass.

The checkout excludes upstream's generated
`packages/dds/tree/src/test/snapshots/output/` directory. The release contains
snapshot filenames that differ only by capitalization, which collide on the
default macOS filesystem. No upstream source or algorithm is excluded or
modified.

### Failure behavior

Package mismatches, source changes, build failures, a failed source test, zero
tests, missing output, and incomplete captures all fail the command. A capture
is generated in an owned temporary directory and published only after validation
and another source-integrity check. Failure leaves any earlier capture intact;
an earlier file is not evidence that the failed invocation succeeded.

The Node tests cover these guards, including a producer subprocess that exits
nonzero and a producer that writes no case.

## Source smoke format

The smoke case initializes a number root, queues concurrent replacements from
two clients, records their pending values, and delivers the actual upstream
messages in order. It captures the settled values, full DDS summary, compressor
bytes, compressor format header, and selected codec dependency graph.

At the pinned commit, the explicit `minVersionForCollab` of `2.117.0` produces:

| Codec | Version |
| --- | --- |
| Message and EditManager | 7 |
| SharedTreeChange and ModularChange | 5 |
| Forest, Schema, DetachedFieldIndex, FieldBatch | 2 |
| Value and Optional fields | 2 |
| Sequence fields | 3 |
| Forbidden and Identifier fields | 1 |
| ID compressor serialization | 2 |

These values come from the captured codec graph and compressor header, not from
the npm major version. The raw message list includes ID allocations. The summary
is a DDS summary, not a complete Fluid container summary.

The object schema in `schema.mjs` is the planned M1 schema. Its tree-only
`rootStore` is an oracle health check. The service profile must instead create a
real SharedMap bootstrap channel with a `"tree"` handle. A passing smoke case
does not freeze that profile or satisfy the M0 exit gate.
