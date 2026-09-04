# Lustre website vertical slice design

**Date:** 2026-09-04

## Goal

Replatform the watershed website on Lustre so the site demonstrates the same
Gleam web stack that watershed supports. Preserve the current URLs, content,
visual design, metadata, accessibility, and demo behavior.

The first implementation covers the site foundation and `/guide/race`. It must
prove static generation, Djot content, shared layouts, the source-snippet
pipeline, client-side Lustre, and deployment before later work migrates the
other routes.

## Decisions

- Generate complete static documents with `lustre_ssg`.
- Write prose-heavy content in Djot with TOML frontmatter.
- Render Djot through `lustre/ssg/djot` and a site-specific renderer.
- Use page-scoped Lustre applications for core collaboration demos.
- Keep decorative scripts and third-party adapters when a Gleam rewrite adds
  no value.
- Bundle client applications with the official Lustre development tools.
- Build in GitHub Actions with modern Erlang/OTP, Gleam, and the Bun binary
  managed by Lustre.
- Deploy the completed static artifact to Netlify.
- Develop the replacement beside the Astro site and switch production only
  after full parity checks pass.

## Current site

Astro generates 43 static routes from 27 shared components. It provides the
document shell, route metadata, redirects, component composition, scoped CSS,
and syntax highlighting. TypeScript and JavaScript modules start the browser
demos against watershed code compiled to JavaScript.

The build also generates `website/src/generated/snippets.json` from
`website/snippets.json` and marker ranges in real source files. Drift checks
require every source quotation to use that manifest. Netlify installs Gleam,
runs the Astro prebuild, and publishes `website/dist`.

The replacement must preserve these useful contracts. It must not copy source
examples into Djot or weaken the checks that keep quotations current.

## Scope

The first implementation adds:

- a new JavaScript-target Gleam site package beside `website`;
- a Lustre SSG build entry;
- typed route, metadata, navigation, and guide-step models;
- Djot loading with required TOML metadata;
- a custom Djot-to-Lustre renderer;
- decoding and lookup for the generated snippet manifest;
- shared sheet and guide layouts;
- static assets and styles needed by `/guide/race`;
- a Lustre MVU version of the guide race demo;
- multiple-entry client bundling through `lustre_dev_tools`;
- GitHub Actions build and Netlify preview deployment;
- unit, generated-document, simulation, and browser tests.

The first implementation does not:

- migrate routes other than `/guide/race`;
- change the public production deployment;
- add a client router;
- hydrate whole pages;
- redesign the guide, its copy, or its visual system;
- rewrite decorative motion or analytics in Gleam;
- replace the source-snippet generator;
- remove Astro or current TypeScript modules.

## Package structure

The replacement starts in `website_lustre/` while Astro remains the production
site.

```text
website_lustre/
  assets/
    fonts/
    images/
    scripts/
    styles/
  content/
    guide/
      race.djot
  src/
    watershed_site.gleam
    watershed_site/
      build.gleam
      content.gleam
      document.gleam
      guide.gleam
      metadata.gleam
      route.gleam
      snippet.gleam
      view/
        guide.gleam
        sheet.gleam
      demo/
        guide_race.gleam
        sluice_rig.gleam
  test/
  gleam.toml
```

Names can change during planning if Gleam module rules require it. The
responsibilities and boundaries must remain.

`watershed_site/build` prepares routes and calls `lustre_ssg`. The main
`watershed_site` module is not a browser entry. Each interactive demo exposes
its own `main`, which lets Lustre dev tools produce one route-specific bundle
and shared chunks when the package has several demos.

## Route model

The build creates each route from a typed descriptor:

```text
Route(
  path,
  metadata,
  layout,
  content,
  client_entry,
)
```

`path` is the public URL. `metadata` includes the title, description, page URL,
social card fields, and analytics policy. `layout` selects a known site layout.
`content` points to validated Djot content. `client_entry` identifies an
optional page-scoped application bundle.

The route registry rejects duplicate paths before it calls `lustre_ssg`.
`ssg.use_index_routes` writes `/guide/race/index.html`, matching the current
clean URL. Netlify continues to own legacy redirects because `lustre_ssg`
generates files and does not define redirect responses.

The document renderer emits the complete HTML document. It includes the
language, viewport, favicon, description, Open Graph fields including
`og:url`, Twitter card, stylesheet links, Tinylytics script, and the optional
client entry for the route. The pilot does not add a canonical link that the
current route does not emit.

## Djot content

`content/guide/race.djot` contains the current page prose and TOML frontmatter.
The frontmatter names fields that authors should review with the content:

```toml
description = "Step three of the watershed build guide: ..."
layout = "guide"
guide_step = "race"
```

The loader reads the file with `simplifile`, parses frontmatter through
`lustre/ssg/djot`, and decodes required fields into the metadata model. It
reports the file, field, and parse reason when decoding fails.

The guide layout derives the page title from the typed guide step, matching the
current Astro layout. Authors do not repeat the step title in frontmatter.

The custom renderer maps ordinary Djot constructs to the classes and semantic
elements used by the current site. It also recognizes a small set of explicit
extensions:

- a fenced div that selects a registered site component;
- a code block attribute that names a generated snippet;
- attributes required for established guide callouts and annotations.

The component registry uses a Gleam custom type. An unknown component name is a
build error. The renderer must not accept an arbitrary module name or execute
content-provided code.

Before rendering, the content loader traverses the Jot AST to validate component
markers and snippet IDs and to reject raw HTML blocks. The renderer callbacks
therefore receive validated content. This validation pass can return contextual
errors, while the `lustre/ssg/djot.Renderer` callbacks cannot.

Raw HTML remains disabled for migrated content unless a later route proves a
specific need. This keeps page markup in typed Lustre functions.

## Source-backed snippets

The existing Gleam generator remains authoritative. It reads
`website/snippets.json` and source markers, then writes a generated JSON
manifest for the replacement build.

A Gleam decoder enforces the current manifest version and entry model:

- code;
- language;
- source path;
- optional source URL added by site policy;
- source-marker or whole-file origin.

Djot names a generated snippet by ID instead of containing its source text.
The renderer looks up the ID and emits the source label, link, code block, and
optional caption. A missing ID stops the build.

The first slice keeps the existing snippet configuration and generator command.
Later work can move the configuration only if both builds no longer need it.

The current `/guide/race` route displays no source snippet. The pilot must not
add one only to create coverage. Renderer tests use a generated manifest entry
to exercise the complete snippet path without changing the route's content.

Syntax highlighting happens during the static build. `smalto` tokenizes each
supported language, and a small site-owned function maps its token variants to
Lustre elements with site-owned classes. The renderer does not use
`smalto_lustre` because version 3.0 declares the Erlang target and cannot join
the JavaScript-target site package. The renderer preserves escaped source text,
language classes, keyboard focus on source links, and the current visual
theme. An unknown language produces an unhighlighted escaped code block and
retains its language label.

## Shared layouts

`view/sheet` reproduces the current document frame, sheet index, registration
marks, bottom annotations, and protected watershed names. It computes active
navigation from the route path.

`view/guide` composes the sheet with:

- guide breadcrumbs;
- step number, title, goal, and API surface;
- normal and wide content regions;
- field notes;
- previous and next navigation;
- adjoining sheets.

`guide.gleam` becomes the typed source for guide steps and neighbor lookup.
During the parallel phase, a parity test compares it with the current guide
catalog so edits cannot leave one site with different navigation.

The pilot copies the required CSS and public assets into the replacement
package. Astro remains authoritative until cutover. Contract tests compare
critical computed styles and asset hashes where an unnoticed difference would
change the page. At cutover, the replacement package becomes authoritative and
the temporary comparison ends.

## Guide race application

`demo/guide_race` owns one Lustre application with a model for:

- two client replicas;
- the shared notes and vote channels;
- visible cards and vote totals;
- pending operation markers;
- latency;
- the sequencer log and latest sequence number;
- run status;
- controls and client-visible errors.

Messages cover add, vote, reset, latency changes, timer delivery, kernel events,
and effect failures. The update function returns a new model and effects. The
view renders the complete demo subtree, including assistive text and the
no-script or failed-start explanation.

The module exports one view function for both build and browser use. The SSG
renders the initial model and maps its messages to `Nil`. The client bundle
starts the application on the same root and replaces that static subtree. This
is deliberate replacement because `lustre_ssg` supplies no hydration protocol.
Calling one view function on both paths prevents separate markup
implementations.

`demo/sluice_rig` wraps the in-memory sluice and watershed operations needed by
browser demonstrations. It provides typed commands and events to the Lustre
application. It does not expose DOM nodes. The first slice implements only the
operations required by the guide race, then later demos can extend it when they
migrate.

The app uses Gleam and `watershed_lustre` for collaboration state, updates, and
effects. A small JavaScript FFI may measure positions for flow animation or
call browser APIs that Lustre does not expose. The FFI must not construct page
markup or own collaboration state.

If the module script does not load, the static initial view and prose remain.
If an effect fails after startup, the application dispatches a typed failure
message and renders the reason near the controls. It does not hide the demo or
report success.

## Retained scripts

The migration keeps Tinylytics as an external script. It can also keep the
existing motion and contour scripts while the static DOM contract they use
remains stable. Quill and other third-party adapters may keep narrow JavaScript
modules on routes that still need them.

These scripts are exceptions for platform APIs or third-party libraries. New
core collaboration behavior belongs in Lustre.

## Build and local development

The production build performs these steps in order:

1. Compile the root watershed package and `watershed_lustre` for JavaScript.
2. Generate the source-snippet manifest.
3. Run `gleam run -m lustre/dev build` with each demo entry module.
4. Configure Lustre dev tools with `no_html = true`, minification, and an asset
   staging output directory.
5. Run the site build module, which copies staged assets and bundles, validates
   every route, and calls `lustre_ssg.build`.
6. Run generated-document and browser checks against the completed `dist/`.

Multiple entry modules let Lustre dev tools produce page bundles and a shared
chunk without generating an HTML entry file. The SSG remains the only document
generator.

For client application work, developers run the Lustre development server with
the guide race entry. For full-route checks, a repository command rebuilds the
SSG output and serves `dist/` with Netlify's local server. The first slice does
not add a custom watcher or static server.

## Continuous deployment

The official Lustre development tools target Erlang and use Bun for bundling.
Their CLI downloads a matching Bun binary into `.lustre` unless configuration
selects a system binary. The GitHub Actions workflow therefore installs
supported OTP and Gleam versions and caches Gleam packages plus `.lustre`.

The workflow builds from a clean checkout and uploads `dist/` as an artifact.
During the pilot it deploys that artifact to a Netlify preview. It does not
change the production site.

At cutover, the production job deploys the same tested artifact to Netlify.
Netlify does not rebuild it. This removes differences between the tested files
and the published files.

The workflow stores Netlify credentials in GitHub Actions secrets and grants
the deploy job only the permissions it needs. Pull requests from untrusted
forks build and test without receiving deployment credentials.

## Error handling

The build reports errors at the boundary that can explain them:

- content errors name the Djot file and metadata field;
- component errors name the route and component marker;
- snippet errors name the route and snippet ID;
- route errors name both descriptors that claim one path;
- asset and bundle errors name the source and destination;
- SSG errors retain the `lustre_ssg.BuildError` reason.

The build exits with a nonzero status after any error. GitHub Actions does not
deploy an artifact from a failed job. `lustre_ssg` writes through a temporary
directory, so an interrupted build does not replace a previous complete
output.

Client effects return typed results. The update function records failures in
the model and the view shows them. Tests cover each failure transition that the
pilot can trigger.

## Testing

### Gleam unit tests

Tests cover:

- required and optional TOML metadata;
- invalid metadata with file and field context;
- route uniqueness and index-route output;
- active sheet navigation;
- guide neighbor lookup;
- Djot elements and site extensions;
- rejection of unknown components and raw HTML;
- snippet manifest decoding and missing IDs;
- guide race update transitions;
- sluice-rig command and event mapping;
- failed effects entering the visible failure state.

### Lustre simulation tests

Lustre development simulations cover:

- the static initial model;
- adding two notes while latency keeps both pending;
- delivery of both notes to both replicas;
- convergence after the stream drains;
- control locking during a run;
- reset restoring the initial board;
- assistive status text after each state change.

### Generated-document tests

Build tests parse `/guide/race/index.html` and verify:

- title, description, Open Graph URL and data, and Twitter card;
- favicon, stylesheet, analytics, and route-specific module script;
- sheet and guide navigation;
- active-page attributes;
- guide step metadata and previous or next links;
- one demo root, static initial markup, and no-script text;
- no Astro runtime, Vite client, or client router.

A separate renderer fixture verifies source-backed snippet text, highlighting,
and its source link against a generated manifest entry.

### Browser test

The existing Puppeteer style can remain test infrastructure. The browser test
loads the built route, waits for the Lustre app, increases latency, starts the
two-note race, observes pending styles, waits for convergence, confirms both
replicas match, and resets the demo.

The test also disables JavaScript and confirms that the page content,
navigation, metadata, initial demo view, and no-script explanation remain
readable.

### Pilot acceptance

The pilot is complete when:

- a clean GitHub Actions run builds and tests the replacement;
- the Netlify preview serves `/guide/race/` with no broken assets;
- the generated document meets the route contract;
- the browser race converges and resets;
- copy, layout, assistive text, and critical styles match the current route;
- page code contains no Astro component or TypeScript collaboration logic;
- the current production deployment remains unchanged.

## Migration after the pilot

The later migration uses the tested foundation in this order:

1. Move the other guide routes and shared guide components.
2. Move prose-heavy foundations, runtime, component-model, and structure
   routes to Djot.
3. Move data-driven index routes and shared site components.
4. Rewrite the remaining core collaboration demos as page-scoped Lustre
   applications.
5. Compare the full route inventory, redirects, metadata, links, assistive
   text, no-JavaScript output, demo behavior, and asset loading.
6. Switch the production deployment to the prebuilt Lustre artifact.
7. Keep the previous Astro deploy available for immediate Netlify rollback.
8. Remove Astro and obsolete TypeScript after the Lustre deployment remains
   stable.

Each migration group gets its own bounded plan. A group needs another design
only when it changes the approved renderer, application, build, or deployment
architecture.

## Cutover criteria

Production can switch after the replacement:

- generates every current public route or an approved redirect;
- preserves current metadata, public URLs, and Open Graph URLs;
- passes link and asset checks;
- passes no-JavaScript content checks;
- passes browser checks for each core demo;
- preserves the protected site names and website voice;
- deploys the exact artifact that CI tested;
- has a tested rollback to the last Astro deploy.

## References

- [lustre_ssg](https://github.com/lustre-labs/ssg)
- [`lustre/ssg/djot`](https://github.com/lustre-labs/ssg/blob/main/src/lustre/ssg/djot.gleam)
- [Lustre development tools](https://github.com/lustre-labs/dev-tools)
- [Lustre development tools TOML reference](https://hexdocs.pm/lustre_dev_tools/toml-reference.html)
