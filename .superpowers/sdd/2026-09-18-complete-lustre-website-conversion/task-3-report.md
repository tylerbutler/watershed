# Task 3 Report: Native Lustre Homepage

## Files

- `website_lustre/src/watershed_site/client/home.gleam`
  - Replaced the separate structure-demo mount plus `enhance()` call with one
    Lustre application.
  - Composes the structure-demo model with a homepage gauge-strip projection.
  - Maps the structure-demo messages and effects through the homepage model.
- `website_lustre/src/watershed_site/client/home_ffi.mjs`
  - Removed the Astro `hero-drift.js` import and all gauge-strip DOM syncing.
  - Keeps only contour geometry, reduced-motion handling,
    `IntersectionObserver`, and `requestAnimationFrame`.
  - Exports only `startHeroDrift` and `stopHeroDrift`.
- `website_lustre/src/watershed_site/view/home.gleam`
  - Replaced `#home-structure-demo-mount` with one `#home-demo-mount`.
  - Derives strip values and per-key pending classes from the structure-demo
    model.
  - Dispatches the strip race button through the structure-demo runtime.
  - Restored the accessible `Convergence models compared` navigation label.
- `website_lustre/test/home_view_test.gleam`
  - Added mount, fallback, navigation-label, and homepage-FFI ownership tests.
- `website_lustre/test/browser/home.mjs`
  - Added a live-DOM assertion that the mounted application leaves exactly one
    `#home-demo-mount`.

## Decisions

- The homepage stores a `GaugeStrip` projection beside the structure-demo
  model and rebuilds that projection after every structure-demo update. The
  strip therefore follows the same optimistic and sequenced state as the main
  gauge tables without observing or querying their DOM.
- The static page and client application share the same demo renderer. The
  server owns the mount element; the client renders a fragment inside it. This
  avoids duplicate mount IDs after Lustre starts.
- Per-key pending styling reads the public `map_kernel.MapState.pending`
  entries. A pending clear marks every strip value pending; set/delete entries
  mark only their key.
- The contour generator was copied into the homepage FFI so the native site has
  no runtime import from `website/src`. Browser-specific animation and
  reduced-motion APIs remain in JavaScript.
- No subagent was used, as requested.

## Commands and Results

1. RED ownership tests:

   ```text
   cd website_lustre && gleam test --target javascript -- home
   ```

   Result: expected failure, `145 passed, 2 failures`.
   `home_has_one_lustre_owned_demo_mount_test` could not find
   `#home-demo-mount`; `home_ffi_only_owns_contour_animation_test` found
   `MutationObserver`.

2. First GREEN pass:

   ```text
   cd website_lustre && gleam test --target javascript -- home
   ```

   Result: `147 passed, no failures`.

3. Formatting:

   ```text
   just format
   ```

   Result: all Trellis members formatted successfully.

4. Requested validation:

   ```text
   cd website_lustre && gleam test --target javascript -- home
   ```

   Result: `147 passed, no failures`.

   ```text
   just website-lustre
   ```

   Result: successful JavaScript bundles, assets, and static-site generation.
   The command printed existing dependency and repository warnings; it reported
   no warning in the Task 3 files.

   ```text
   node website_lustre/test/browser/home.mjs
   ```

   Result: Chromium did not launch because this host's AppArmor policy blocks
   unprivileged browser sandboxes.

   ```text
   CI=1 node website_lustre/test/browser/home.mjs
   ```

   Result: `PASS: Homepage SharedMap demo converges without Astro runtime.`
   `site.mjs` already uses `--no-sandbox` under `CI=1`.

5. Self-review regression test:

   ```text
   CI=1 node website_lustre/test/browser/home.mjs
   ```

   Result before the fix: expected failure, `2 !== 1`, proving the client had
   rendered a second `#home-demo-mount` inside the server mount.

6. Final validation after flattening the client view:

   ```text
   just format
   ```

   Result: all Trellis members formatted successfully.

   ```text
   cd website_lustre && gleam test --target javascript -- home
   ```

   Result: `147 passed, no failures`.

   ```text
   just website-lustre
   ```

   Result: successful JavaScript bundles, assets, and static-site generation,
   with the same pre-existing warnings noted above.

   ```text
   CI=1 node website_lustre/test/browser/home.mjs
   ```

   Result: `PASS: Homepage SharedMap demo converges without Astro runtime.`

7. Final ownership and diff checks:

   ```text
   git diff --check
   grep -o 'id="home-demo-mount"' website_lustre/dist/index.html | wc -l
   grep -R -n -E 'website/src|_astro|MutationObserver|home-structure-demo-mount' \
     website_lustre/build/static/home.js \
     website_lustre/src/watershed_site/client/home.gleam \
     website_lustre/src/watershed_site/client/home_ffi.mjs \
     website_lustre/src/watershed_site/view/home.gleam
   ```

   Result: clean diff, one generated mount, and no forbidden ownership matches.

## Commit

`feat(website): make homepage demo native Lustre` (this commit)

## Self-review

- Confirmed every structure-demo effect is mapped back into the parent message
  type; deferred delivery and race behavior remain owned by Task 2's runtime.
- Confirmed the strip race button dispatches the runtime message directly and
  is enabled without a DOM proxy.
- Confirmed pending strip styling follows the specific map key rather than a
  replica-wide pending count.
- Confirmed static fallback markup remains inside the single mount and the
  blocked-script browser scenario still passes.
- Confirmed the generated homepage and bundle contain no Astro runtime path,
  `website/src` import, legacy mount ID, or homepage `MutationObserver`.
- Found and fixed the duplicate live mount during review; the browser test now
  guards that ownership boundary.
- Remaining concern: the unprefixed browser command cannot launch Chromium on
  this machine because of host AppArmor policy. The repository's existing
  `CI=1` launch path runs the same test successfully.

## Fix round 1

- Changed `startHeroDrift` to accept the contour SVG and reduced-motion Boolean
  chosen by Gleam. The animation now queries paths only inside that supplied
  SVG and does not call `document.querySelector` or `matchMedia`.
- Added `test/home_ffi_contract.test.mjs`. It passes detached contour fields
  directly to the FFI and proves that the supplied Boolean selects reset or
  animation behavior without ambient DOM or media lookup.
- Moved the live `#home-demo-mount` assertion after the baseline-recording
  branch, so Astro baseline recording remains available while the assertion
  still protects the Lustre build.
- Updated `_test-website-lustre` to run every top-level Node contract test.

### Fix evidence

1. FFI contract test before the fix:

   ```text
   node --test website_lustre/test/home_ffi_contract.test.mjs
   ```

   Result: expected failure, `document is not defined`, because
   `startHeroDrift` ignored the supplied SVG and queried the document.

2. Baseline recording before the fix:

   ```text
   CI=1 node website_lustre/test/browser/home.mjs --record-baseline
   ```

   Result: expected failure, `0 !== 1`, because the Lustre-only mount assertion
   ran against the Astro baseline.

3. Contract and homepage tests after the fix:

   ```text
   node --test website_lustre/test/*.test.mjs
   ```

   Result: `4 passed, no failures`.

   ```text
   cd website_lustre && gleam test --target javascript -- home
   ```

   Result: `147 passed, no failures`.

4. Baseline recording after the fix:

   ```text
   CI=1 node website_lustre/test/browser/home.mjs --record-baseline
   ```

   Result: `Recorded Astro homepage parity baseline.` The fixture was
   unchanged.

5. Build and live browser test:

   ```text
   just website-lustre
   ```

   Result: successful bundles, assets, and static-site generation with the
   same pre-existing dependency and repository warnings.

   ```text
   CI=1 node website_lustre/test/browser/home.mjs
   ```

   Result: `PASS: Homepage SharedMap demo converges without Astro runtime.`

## Fix round 2

- Added a homepage-client `ReducedMotionChanged` message and model field.
- Replaced the startup-only preference read with one media-query subscription
  that dispatches the initial value and every live change into Lustre.
- Kept animation control explicit: the Lustre update effect supplies the
  contour SVG and current reduced-motion Boolean to `startHeroDrift`.
- Extended the homepage browser regression to prove contour drift is active,
  stops after switching to reduced motion, and resumes after switching back.

### Fix evidence

1. Browser regression before the fix:

   ```text
   CI=1 node website_lustre/test/browser/home.mjs
   ```

   Result: expected failure. The contour path changed during the
   reduced-motion window, proving that the startup snapshot did not handle a
   live preference change.

2. Focused tests after the fix:

   ```text
   cd website_lustre && gleam test --target javascript -- home
   node --test test/*.test.mjs
   ```

   Result: `147 passed, no failures`; `4 passed, no failures`.

3. Build and live browser test after the fix:

   ```text
   just website-lustre
   CI=1 node website_lustre/test/browser/home.mjs
   ```

   Result: successful static-site generation and
   `PASS: Homepage SharedMap demo converges without Astro runtime.` The build
   printed the same pre-existing dependency and repository warnings.
