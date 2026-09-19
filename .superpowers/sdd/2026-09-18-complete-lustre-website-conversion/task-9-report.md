# Task 9 report

## Result

Reduced generated JavaScript and CSS from 2,672,023 bytes raw and 651,309
bytes gzip to 1,471,111 bytes raw and 373,239 bytes gzip. The site remains
below the 2.2 MB raw and 520 KB gzip budgets.

## Changes

- Added a generated-client asset budget test that measures every JavaScript and
  CSS file and reports per-file raw and gzip sizes when either limit is
  exceeded.
- Replaced four independent Lustre builds with one official multi-entry build,
  allowing Bun to emit shared chunks once.
- Kept the established public entry URLs with small import shims because the
  official eleven-entry build writes entry modules below its generated
  `.lustre/build` directory.
- Moved the extracted rich-text stylesheet back to its established public path.
- Removed the obsolete single-entry HTML configuration.
- Confirmed static documents load only their site and route styles, while demo
  documents load only their required client entry and route styles.

## Validation

- `just website-lustre` — PASS
- `cd website_lustre && gleam test --target javascript -- assets` — PASS
  (190 tests)

## Concerns

The build still prints pre-existing dependency and repository warnings. The
entry shims preserve stable asset URLs around the official CLI's nested
multi-entry output layout.

## Round 1 fix

The stable public entry shims imported their generated modules from
`/.lustre/`. The pinned GitHub artifact upload and Netlify deployment paths
exclude dot-prefixed directories, so deployed interactive routes could not
load those modules.

- Added a deployment-filter contract that follows every relative import from
  all eleven stable entry shims and rejects dependencies in hidden paths.
- Confirmed the test failed on
  `.lustre/build/watershed_site/client/counter_bug.js` before the fix.
- Moved the generated entry tree to `/lustre/` at the same depth and updated
  the shims. Shared chunks and stable public entry URLs are unchanged.

### Round 1 validation

- `just website-lustre` — PASS
- `node --test website_lustre/test/deployment-filter-contract.test.mjs` — PASS
- `cd website_lustre && gleam test --target javascript -- assets` — PASS
  (190 tests)
- `node --test website_lustre/test/*.test.mjs` — PASS (5 tests)
- `cd website_lustre && CI=true pnpm run smoke` — PASS (24 browser programs)

### Round 1 concerns

The browser suite requires its existing CI launch mode on this host because
Chromium cannot use the local sandbox. The build still prints the pre-existing
dependency and repository warnings noted above.
