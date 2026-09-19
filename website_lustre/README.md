# Lustre website

This package renders every production route with Lustre SSG. Static pages ship
plain HTML, CSS, and small page scripts. Interactive routes add page-scoped
client bundles that use the compiled watershed runtimes.

## Run it

Use Gleam 1.18.1, Erlang/OTP 28, Node 24, pnpm 11.13.1, and just 1.58.0
to match CI. Install the root and browser-test dependencies once:

```sh
corepack pnpm@11.13.1 install --frozen-lockfile
corepack pnpm@11.13.1 --dir website_lustre install --frozen-lockfile
gleam deps download
cd watershed_lustre && gleam deps download && cd ..
cd tools/source-snippets && gleam deps download && cd ../..
cd tools/website-lustre-build && gleam deps download && cd ../..
cd website_lustre && gleam deps download && cd ..
just website-lustre
```

Serve the generated artifact through Netlify's local static server:

```sh
just website-lustre-serve
```

Open `http://127.0.0.1:4321/`. The route registry generates 42 pages:
the homepage, foundations, component model, runtime, field atlas, guide,
comparison pages, and dedicated demos. Fonts, styles, images, and client
modules sit alongside the documents in `website_lustre/dist/`. Three
redirects preserve the former foundations URLs for components, ports, and
workspaces. There is no separate frontend dev server; rebuild after editing
source or content.

The first build downloads Gleam dependencies and the Bun executable used
by the official Lustre bundler. You do not need a separate Bun installation.
The serve command uses Netlify CLI 27.4.1 in offline mode.

## Validation

```sh
just _test-website-lustre
```

This command rebuilds snippets and the site, runs the Gleam suite, and runs
the Node contracts and all 24 Puppeteer route gates against temporary loopback
servers. It also runs as part of `just test`; `just build` includes the site
build. No external collaboration service is required.

Puppeteer needs Chrome. If dependency installation did not download it, run
`pnpm --dir website_lustre exec puppeteer browsers install chrome`.
Set `WATERSHED_CHROME` to use another Chromium executable. A missing browser
skips the gate locally and fails in CI. On a host without a usable Chromium
sandbox, use `CI=true just _test-website-lustre`; the existing CI launch path
uses `--no-sandbox` and makes a missing browser an error.

To run the gates separately from the repository root:

```sh
just format
just website-lustre
(cd website_lustre && gleam test --target javascript)
node --test website_lustre/test/*.test.mjs
(cd website_lustre && CI=true pnpm run smoke)
just build
just lint
CI=true just test
```

The Node contracts cover Netlify configuration, deployment-filter preservation
of client imports, and the homepage animation FFI. The Gleam suite checks
content, generated documents, typed demo behavior, and the generated JS/CSS
budget (2.2 MB raw, 520 KB gzip). Run the build first so artifact checks inspect
current output.

The browser contract fixtures under `test/fixtures/` record the native site's copy,
metadata, navigation, code figures, field notes, and computed styles across
the route families. Browser gates cover desktop and mobile layout, keyboard
navigation, no-script content, reduced motion, failed-start explanations, and
live edits, races, and resets. Static-sheet gates check field-note fragments
on initial load and `hashchange`. To update the fixtures listed in
`package.json` after an intentional site change, build this package, then run
`pnpm run record:contracts` from `website_lustre/`. Review the fixture diff
before accepting a new baseline.

The smoke helper stubs Tinylytics so an external analytics outage cannot fail
the route contracts. For a release inspection, also browse the generated
site without interception: check console errors and failed requests on `/`,
`/structures/maps/`, `/directory/`, `/guide/race/`, `/json-ot/`, `/rich-text/`,
`/sequence/`, and `/text/` at desktop and mobile sizes. An unavailable
Tinylytics request is distinct from a broken local asset or client module.

## Build and rendering

The site targets JavaScript. `tools/website-lustre-build` is a separate
Erlang package that exports the official `lustre_dev_tools` CLI as an
escript. The root recipes run that executable from `website_lustre`, so the
bundler reads this package's configuration without trying to compile
JavaScript-only watershed bindings for Erlang.

`tools/build-website-lustre.sh` builds all eleven client entries in one
official CLI invocation so they share chunks. Public entry shims such as
`/home.js` import modules below `/lustre/`; keep those paths free of hidden
directories so both GitHub artifact upload and Netlify retain them. The
rich-text stylesheet keeps its public `/rich_text.css` path.

Lustre SSG 0.12 is not on Hex. We pin upstream commit
`2992bf78179d1be2876f834f0d923003f7f43f44` with its compatible `tom` 1.x
parser. `code.gleam` maps Smalto tokens to Lustre elements because
`smalto_lustre` 3.0 targets Erlang only.

| Location | Purpose |
| --- | --- |
| `content/` | Djot prose and metadata for the full route inventory |
| `content/guide/index.djot` | Guide landing-page prose and section markers |
| `content/guide/*.djot` | Guide prose and TOML frontmatter |
| `content/foundations/index.djot` | Foundations landing-page prose and section markers |
| `content/foundations/*.djot` | Foundations concept-sheet prose and snippet references |
| `content/component-model/index.djot` | Component-model landing-page prose and section markers |
| `content/component-model/*.djot` | Component-model concept-sheet prose and snippet references |
| `content/runtime/index.djot` | Runtime landing-page prose and section markers |
| `content/runtime/*.djot` | Runtime behavior prose and snippet references |
| `src/watershed_site/route.gleam` | Explicit route, source path, and client entry registry |
| `src/watershed_site/runtime.gleam` | Typed runtime behavior catalog |
| `src/watershed_site/content.gleam` | Metadata decoding and Djot AST validation |
| `src/watershed_site/page.gleam` | Djot renderer and embedded demo |
| `src/watershed_site/practice.gleam` | Typed catalog for all 17 field notes |
| `src/watershed_site/view/field_notes.gleam` | Inline references and complete field-note sections |
| `src/watershed_site/view/` | Complete document, sheet, guide, and footer markup |
| `src/watershed_site/view/guide_index.gleam` | Guide landing sections, document diagram, and shared step ledger |
| `src/watershed_site/view/concept_index.gleam` | Foundations landing sections and shared concept ledger |
| `src/watershed_site/view/concept_sheet.gleam` | Foundations hero, related notes, and neighboring-sheet pager |
| `src/watershed_site/view/runtime_sheet.gleam` | Runtime hero, related notes, and neighboring-sheet pager |
| `src/watershed_site/guide_race/` | Shared static/browser view and real sluice runtime |
| `src/watershed_site/structure_demo/` | Shared typed models, kernel operations, family plates, and replica views |
| `src/watershed_site/{directory,json_ot,rich_text,sequence,text}/` | Dedicated demo runtimes and views |
| `src/watershed_site/client/` | Page-scoped Lustre entries and narrow browser adapters |
| `assets/scripts/field-notes.js` | Fragment-target reveal behavior for static sheets |
| `assets/` | Copied CSS, licensed fonts, favicon, and social image |
| `dev/watershed_site/build.gleam` | SSG command and contextual build errors |

The build rejects raw HTML, unknown metadata, unknown components, stale
practice IDs, and missing snippet IDs before rendering. Source-backed code
blocks use `src/generated/snippets.json`, regenerated by `just snippets`.
Declare a snippet in `website_lustre/snippets.json` and mark its source; do not
hand-edit the generated manifest or load source files at runtime. The Connect
sheet's `gleam.toml` is a whole-file manifest entry.

Static guide Djot has three explicit extensions:

````djot
{data-snippet="guide-notes-note-record"}
```gleam
generated
```

{data-source-label="(illustrative — not in the tutorial source)"}
```gleam
let current = read_total(board, id)
```

{data-component="field-note-ref" data-practice="authoritative-channel"}
:::
:::
````

`data-caption` adds a plain-text figure caption to either code-block form.
Generated snippet IDs must resolve through the manifest. Field-note IDs must
resolve through `practice.gleam`; the catalog also decides which complete
notes appear at the end of each sheet.

The guide index loads its own stylesheet and no Lustre client bundle. Its
small reveal script lives at `assets/scripts/motion.js`; static wrapper modules
start the shared implementation. The six step links use the same typed guide
catalog as the race page's navigation. Content stays visible without
JavaScript, and the script respects reduced motion.

Connect, Notes, Votes, Presence, and Testing load only the shared
`/scripts/field-notes.js` module. Race loads only `/guide_race.js` and is the
only route that receives `guide-race.css`.

For headings referenced by `aria-labelledby`, use the `data-heading-id`
Djot attribute. The renderer turns it into an HTML `id`; Jot replaces the
ordinary explicit heading ID with a generated one. Keep adjacent nested
div fences together without a blank line after the closing fence, because
Jot otherwise reads the next marker as paragraph text.

The static page includes both initial boards and the no-script explanation.
Lustre mounts inside `#guide-race-mount`; the shared view owns the single
`#guide-race-demo` section. If the bundle does not load, CSS reveals the
failed-start explanation after three seconds. With scripting disabled, the
no-script explanation appears instead. Mutable operations run through deferred
effects.
Reset advances a generation counter so old delivery timers cannot change
the new board.

## Typed demos and the FFI boundary

Keep collaboration behavior in Gleam. The modules under
`src/watershed_site/structure_demo/` own the shared rig's typed state,
operations, delivery queue, and views. The homepage and structure-family
plates use that same implementation. Dedicated demos own their runtimes and
views under their matching directories; the guide race uses the tutorial
board through the real sluice. These modules call the watershed kernels and
runtimes rather than reimplementing their merge rules in browser scripts.

The entries under `src/watershed_site/client/` mount page-scoped Lustre apps
and connect effects to browser adapters. Models own pending state, sequence
numbers, operation logs, errors, and reset generations. Views render those
models into both static initial markup and live replicas. Mutable runtime
work belongs in effects, with generation checks that reject stale delivery
after reset.

Use JavaScript FFI only where the browser or a third-party widget requires it:
DOM geometry, Web Animations, media-query subscriptions, pointer capture,
Quill editor lifecycle, and the `watershed-textarea` custom-element bridge.
Quill can own its editor DOM; Gleam owns collaboration, sequencing, and
failure state. Keep kernel imports and demo state machines out of the FFI.
The small scripts in `assets/scripts/` handle static-page reveals and
fragment navigation, not document edits.

## Add another route

Add a Djot file and an explicit route entry. Extend the typed metadata and
page renderer only if the route needs another layout or embedded component.
For an interactive page, add a client module, name its deterministic bundle
in the route registry, and add the module to the shared entry list in
`tools/build-website-lustre.sh`. Structure sheets use the shared
`/structure_sheet.js` entry through `page.gleam`; they do not need one bundle
per family. Static pages need no client entry.

Add content validation, generated-document checks, and browser contract
coverage for the new route. Build output, dependency caches, and the shared
snippet manifest stay untracked.

## Deployment

`.github/workflows/website-lustre.yml` builds and tests on pull requests,
pushes to `main`, and manual dispatch. It uploads the generated site as the
`website-lustre` artifact.

With repository secrets `NETLIFY_AUTH_TOKEN` and `NETLIFY_SITE_ID`, the
preview job deploys that tested artifact for same-repository pull requests
and manual dispatches. Pull requests use the stable `lustre-pr-N` alias.
Fork pull requests run the build without receiving deployment secrets;
pushes to `main` only build and upload. The deploy job does not check out
the repository, rebuild the artifact, or use `--prod`.

Netlify's Git integration owns production deployment. The root `netlify.toml`
runs `website_lustre/scripts/netlify-build.sh` from the repository root and
publishes `website_lustre/dist`. That script installs the pinned Gleam and pnpm
versions when needed, installs the root and site JavaScript dependencies,
downloads the Gleam dependencies, and calls `tools/build-website-lustre.sh`.
The root `just website-lustre` recipe calls the same production build script.

### Rollback

For a production rollback, redeploy a known-good historical Netlify artifact.
The last commit containing the Astro source tree is
`8a600a631d090338d6c4a6bf4a9047fed9c69e6e` (the parent of the removal commit
`3a4b75b`). Recover `website/` from that revision in a separate checkout if
you need to rebuild the old site. That revision already has the Lustre
production configuration, so an Astro rebuild also needs its historical
build and deployment settings; the current Netlify command is not an Astro
rollback command. Do not restore a parallel legacy tree in this branch.
