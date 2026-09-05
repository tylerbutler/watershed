# Lustre Website Vertical Slice Implementation Plan

> **For agentic workers:** Execute this plan task-by-task, test-first. Do not use subagents. Follow the approved design in `docs/superpowers/specs/2026-09-04-lustre-website-vertical-slice-design.md`. Commit after each task. Stop and report if a required public package API differs from this plan instead of hiding the mismatch behind JavaScript.

**Goal:** Build `/guide/race` as a complete Lustre SSG page and page-scoped Lustre application while preserving the current route, copy, metadata, design, accessibility, static fallback, and race-demo behavior.

**Architecture:** Add a JavaScript-target Gleam package beside `website/`. The package loads Djot with TOML frontmatter, validates its Jot AST, renders complete documents through `lustre_ssg`, and copies only the client bundle needed by each route. The guide race demo shares one Lustre view between its static SSG state and its browser application. Its effects call the existing typed `watershed/sluice_js` driver and the existing retro-board schema and projection modules.

**Tech Stack:** Gleam, Lustre 5, `lustre_ssg` 0.12, Jot 8, `tom`, Smalto 3, `watershed`, `watershed_lustre`, official `lustre_dev_tools`, gleeunit, Lustre simulation, Puppeteer, GitHub Actions, and Netlify deploy previews.

## Global constraints

### Implementation adjustments

The following observed API details supersede the corresponding examples below:

- SSG 0.12 is not on Hex. Pin upstream commit
  `2992bf78179d1be2876f834f0d923003f7f43f44` and use its compatible `tom` 1.x.
- The snippet ID is `foundations-schema-title-field`; `retro-schema-title`
  names its source marker, not its manifest entry.
- Approved during implementation: mount Lustre inside a neutral
  `#guide-race-mount` wrapper. The shared view keeps `#guide-race-demo`.
  Lustre renders the selected host's children; it does not replace the host.
- Approved during implementation: export the official Lustre CLI from a
  separate Erlang package at `tools/website-lustre-build`. Run that executable
  from `website_lustre`; do not compile the JavaScript-only watershed bindings
  for Erlang merely to start the bundler.
- Trellis selects this package by its Gleam name, `watershed_site`.
- The official bundler emits `guide_race.js`; the route names that file
  explicitly. The build process uses `node:process.exit`, as the snippet
  generator does, rather than the nonexistent built-in `Never` type.

### Original constraints

- Keep `website/` and the current `netlify.toml` unchanged during the pilot.
- Keep `/guide/race/` as the public route. Use index routes so the generated file is `dist/guide/race/index.html`.
- Preserve the current page copy byte-for-byte except for markup syntax needed by Djot.
- Preserve the current document title, description, `og:*` tags, Tinylytics script, navigation labels, breadcrumb, guide metadata, previous/next links, ecosystem links, favicon, social image, and no-script behavior.
- Do not add a canonical link. The Astro page does not emit one.
- Do not import `.gleam` or `.mjs` source text at runtime.
- Do not edit `website/src/generated/snippets.json`. Run `just snippets`.
- Treat `website/src/generated/snippets.json` as the only snippet manifest.
- Reject raw HTML in Djot before rendering.
- Reject unknown embedded component names and unknown snippet IDs before rendering.
- Do not use `element.unsafe_raw_html`.
- Map Smalto tokens to Lustre elements in `watershed_site/code.gleam`. Do not add `smalto_lustre`; version 3.0 is Erlang-target only.
- Keep site markup and collaboration state in Gleam. JavaScript is allowed only for the browser smoke test and narrow browser APIs that Lustre does not expose.
- Run every mutable `sluice_js` or watershed operation from a Lustre effect, not from `update`.
- Show effect and projection failures in the demo. Do not turn errors into empty boards or successful status.
- Use stable `data-testid` attributes for browser assertions. Do not select by visual CSS classes in tests.
- Keep all new Gleam comments and error strings in Simplified Technical English.
- Keep website copy in the existing site voice. Read `.github/instructions/website-copy.instructions.md` before editing content.
- Do not change the protected names `field atlas`, `adjoining sheets`, `the survey procedure`, `field index`, `sluice`, `ripple`, `gauge`, `floodgate`, or `watershed`.
- Do not add Co-authored-by trailers to commits.

## File map

### Create

- `website_lustre/gleam.toml`
- `website_lustre/manifest.toml`
- `website_lustre/.gitignore`
- `website_lustre/README.md`
- `website_lustre/package.json`
- `website_lustre/pnpm-lock.yaml`
- `website_lustre/content/guide/race.djot`
- `website_lustre/assets/favicon.svg`
- `website_lustre/assets/og.png`
- `website_lustre/assets/styles/site.css`
- `website_lustre/assets/styles/guide-race.css`
- `website_lustre/assets/fonts/archivo/wdth.css`
- `website_lustre/assets/fonts/archivo/files/*.woff2`
- `website_lustre/assets/fonts/archivo/LICENSE`
- `website_lustre/assets/fonts/jetbrains-mono/400.css`
- `website_lustre/assets/fonts/jetbrains-mono/400-italic.css`
- `website_lustre/assets/fonts/jetbrains-mono/700.css`
- `website_lustre/assets/fonts/jetbrains-mono/files/*.woff2`
- `website_lustre/assets/fonts/jetbrains-mono/LICENSE`
- `website_lustre/src/watershed_site.gleam`
- `website_lustre/src/watershed_site/error.gleam`
- `website_lustre/src/watershed_site/route.gleam`
- `website_lustre/src/watershed_site/guide.gleam`
- `website_lustre/src/watershed_site/content.gleam`
- `website_lustre/src/watershed_site/snippet.gleam`
- `website_lustre/src/watershed_site/code.gleam`
- `website_lustre/src/watershed_site/page.gleam`
- `website_lustre/src/watershed_site/view/document.gleam`
- `website_lustre/src/watershed_site/view/sheet.gleam`
- `website_lustre/src/watershed_site/view/guide.gleam`
- `website_lustre/src/watershed_site/view/adjoining_sheets.gleam`
- `website_lustre/src/watershed_site/view/ecosystem.gleam`
- `website_lustre/src/watershed_site/guide_race/runtime.gleam`
- `website_lustre/src/watershed_site/guide_race/view.gleam`
- `website_lustre/src/watershed_site/client/guide_race.gleam`
- `website_lustre/dev/watershed_site/build.gleam`
- `website_lustre/dev/watershed_site/system.gleam`
- `website_lustre/dev/watershed_site/system_ffi.mjs`
- `website_lustre/test/route_test.gleam`
- `website_lustre/test/content_test.gleam`
- `website_lustre/test/snippet_test.gleam`
- `website_lustre/test/document_test.gleam`
- `website_lustre/test/guide_race_runtime_test.gleam`
- `website_lustre/test/guide_race_view_test.gleam`
- `website_lustre/test/generated_site_test.gleam`
- `website_lustre/test/assets_test.gleam`
- `website_lustre/test/fixtures/valid-page.djot`
- `website_lustre/test/fixtures/raw-html.djot`
- `website_lustre/test/fixtures/unknown-component.djot`
- `website_lustre/test/fixtures/snippet.djot`
- `website_lustre/test/browser/guide-race.mjs`
- `.github/workflows/website-lustre.yml`

### Modify

- `gleam.toml`
- `justfile`
- `watershed_lustre/src/watershed_lustre.gleam`
- `watershed_lustre/test/watershed_lustre_test.gleam`

### Read as migration sources

- `.github/instructions/website-copy.instructions.md`
- `website/src/layouts/Sheet.astro`
- `website/src/components/GuideLayout.astro`
- `website/src/components/GuideRaceDemo.astro`
- `website/src/components/AdjoiningSheets.astro`
- `website/src/components/Ecosystem.astro`
- `website/src/pages/guide/race.astro`
- `website/src/scripts/guide-race-demo.ts`
- `website/src/scripts/demo/sluice-rig.ts`
- `website/src/styles/global.css`
- `website/snippets.json`
- `website/src/generated/snippets.json`
- `examples/retro_tutorial_lustre/src/retro_tutorial_lustre/board.gleam`
- `examples/retro_tutorial_lustre/src/retro_tutorial_lustre/note.gleam`
- `examples/retro_tutorial_lustre/src/retro_tutorial_lustre/document_schema.gleam`

---

## Task 1: Create the JavaScript-target site package and route registry

**Files:**
- Create: `website_lustre/gleam.toml`
- Create: `website_lustre/manifest.toml`
- Create: `website_lustre/.gitignore`
- Create: `website_lustre/src/watershed_site.gleam`
- Create: `website_lustre/src/watershed_site/error.gleam`
- Create: `website_lustre/src/watershed_site/route.gleam`
- Create: `website_lustre/test/route_test.gleam`
- Modify: `gleam.toml`

### Step 1: Scaffold the package

Run:

```sh
gleam new website_lustre --name watershed_site --template lib
cd website_lustre
gleam add lustre@5
gleam add lustre_ssg@0.12
gleam add jot@8
gleam add tom
gleam add smalto@3
gleam add simplifile@2
gleam add gleam_crypto@1
gleam add gleeunit --dev
gleam add lustre_dev_tools@2 --dev
gleam add html_parser@1 --dev
gleam add argv envoy --dev
```

Then add these path dependencies to `website_lustre/gleam.toml`:

```toml
target = "javascript"

[dependencies]
watershed = { path = ".." }
watershed_lustre = { path = "../watershed_lustre" }
retro_tutorial_lustre = { path = "../examples/retro_tutorial_lustre" }

[tools.lustre.build]
minify = true
no_html = true
no_tailwind = true
outdir = "./build/static"

[tools.lustre.html]
body = '<div id="guide-race-demo"></div>'
```

Keep the versions written by `gleam add`. Remove the scaffolded example module
and test before adding the files below. Set `.gitignore` to exclude `/build/`,
`/dist/`, `/.lustre/`, `/node_modules/`, and `/.cache/`.

### Step 2: Write the failing route tests

Define the public route API in the test first:

```gleam
import gleeunit
import gleeunit/should
import watershed_site/route

pub fn main() {
  gleeunit.main()
}

pub fn pilot_route_is_registered_test() {
  route.all()
  |> should.equal([
    route.Route(
      path: "/guide/race",
      layout: route.Guide,
      content_path: "content/guide/race.djot",
      client_script: Some("/watershed_site_client_guide_race.mjs"),
      analytics: route.Tinylytics,
    ),
  ])
}

pub fn duplicate_paths_are_rejected_test() {
  let race = route.guide_race()
  route.validate([race, race])
  |> should.be_error()
}
```

Run:

```sh
cd website_lustre
gleam test --target javascript -- route
```

Expected: FAIL because `watershed_site/route` does not exist.

### Step 3: Implement the route registry and shared build error

Use these public types and functions:

```gleam
pub type Route {
  Route(
    path: String,
    layout: Layout,
    content_path: String,
    client_script: Option(String),
    analytics: Analytics,
  )
}

pub type Layout {
  Guide
}

pub type Analytics {
  NoAnalytics
  Tinylytics
}

pub fn guide_race() -> Route
pub fn all() -> List(Route)
pub fn validate(routes: List(Route)) -> Result(List(Route), BuildError)
```

Define contextual build errors in `watershed_site/error.gleam`:

```gleam
pub type BuildError {
  DuplicateRoute(
    path: String,
    first_content_path: String,
    second_content_path: String,
  )
  CannotRead(path: String, reason: String)
  InvalidFrontmatter(path: String, reason: String)
  InvalidContent(path: String, reason: String)
  InvalidSnippetManifest(path: String, reason: String)
  MissingSnippet(path: String, id: String)
  UnknownComponent(path: String, name: String)
  RawHtml(path: String)
  SiteGenerationFailed(reason: String)
}

pub fn describe(error: BuildError) -> String
```

`route.validate` must report the duplicated path and both content descriptors.
It must not silently keep the first or last item.

### Step 4: Register the package with Trellis

Trellis auto-discovers the package. Edit the root `gleam.toml` exclusions:

- Add `website_lustre` to `@release`.
- Add `website_lustre` to `build-erlang`.
- Add `website_lustre` to `bundle`.
- Do not add it to `build-javascript`.
- Add `website_lustre` to `test` because Task 10 gives the site a dedicated test
  recipe that prepares generated assets before running its suite.

### Step 5: Run the focused tests and workspace doctor

Run:

```sh
cd website_lustre
gleam format --check src test
gleam test --target javascript -- route
cd ..
trellis doctor
trellis run build-javascript website_lustre
```

Expected: all commands pass.

### Step 6: Commit

```sh
git add gleam.toml website_lustre
git commit -m "feat(website): add Lustre site package"
```

---

## Task 2: Load typed Djot content and reject invalid AST nodes

**Files:**
- Create: `website_lustre/src/watershed_site/guide.gleam`
- Create: `website_lustre/src/watershed_site/content.gleam`
- Create: `website_lustre/test/content_test.gleam`
- Create: `website_lustre/test/fixtures/valid-page.djot`
- Create: `website_lustre/test/fixtures/raw-html.djot`
- Create: `website_lustre/test/fixtures/unknown-component.djot`

### Step 1: Write valid and invalid Djot fixtures

The valid fixture must include the author-owned TOML fields, a heading, prose,
and a known embedded component:

```djot
---
description = "A test page."
layout = "guide"
guide_step = "race"
---

# The race

Both replicas write before either receives the other operation.

{data-component="guide-race"}
:::
:::
```

The raw HTML fixture must contain a Jot `RawBlock`. The unknown-component
fixture must set `data-component="not-registered"`.

### Step 2: Write failing loader and validator tests

Test these cases:

- valid TOML decodes into the exact typed values;
- missing `description` is `InvalidFrontmatter`;
- malformed TOML is `InvalidFrontmatter`;
- unknown `layout` and `guide_step` values are `InvalidFrontmatter`;
- raw HTML is `RawHtml(path)`;
- `guide-race` is accepted;
- any other `data-component` value is `UnknownComponent(path, name)`.

Use these public interfaces in the tests:

```gleam
pub type Metadata {
  Metadata(
    description: String,
    layout: route.Layout,
    guide_step: guide.Slug,
    og_title: Option(String),
    og_description: Option(String),
  )
}

pub type Source {
  Source(
    path: String,
    metadata: Metadata,
    body: String,
    document: jot.Document,
  )
}

pub fn load(route: route.Route) -> Result(Source, BuildError)

pub fn parse(
  source: String,
  path: String,
  route: route.Route,
) -> Result(Source, BuildError)
```

Run:

```sh
cd website_lustre
gleam test --target javascript -- content
```

Expected: FAIL because the content module does not exist.

### Step 3: Decode frontmatter into `Metadata`

Use `lustre/ssg/djot.metadata` for TOML parsing and `lustre/ssg/djot.content`
before `jot.parse`.

Keep the decoder strict:

- `description`, `layout`, and `guide_step` are required.
- `og_title` and `og_description` are optional string overrides.
- `layout` must be `guide` and match the route descriptor.
- `guide_step` must resolve through the typed guide catalog.
- The catalog path for the step must equal the route descriptor path.
- Reject any frontmatter key outside these five names.
- Report the source path and field name in each error.

Do not use defaults for missing metadata.

Define the guide catalog in `watershed_site/guide.gleam`:

```gleam
pub type Slug {
  Connect
  Notes
  Race
  Votes
  Presence
  Testing
}

pub type Step {
  Step(
    number: String,
    slug: Slug,
    title: String,
    goal: String,
    surface: String,
  )
}

pub fn all() -> List(Step)
pub fn from_string(value: String) -> Result(Slug, Nil)
pub fn path(slug: Slug) -> String
pub fn get(slug: Slug) -> Step
pub fn neighbours(slug: Slug) -> #(Option(Step), Option(Step))
```

Copy all six entries from `website/src/data/guide.ts`. Add a contract test that
reads that file and checks each Gleam entry's number, slug, title, goal, and
surface. The test must also compare the TypeScript `slug:` entry count with
`list.length(guide.all())`. Page titles, goals, API surfaces, and neighbors come
from this catalog, not from Djot frontmatter.

Test metadata once with both Open Graph overrides absent and once with both
present. The race page omits both, so its Open Graph title and description fall
back to the derived document title and page description.

### Step 4: Validate the Jot AST before rendering

Walk every `jot.Container` and nested `jot.Inline` value. Apply these rules:

- Reject every `jot.RawBlock`.
- A `jot.Div` without `data-component` is ordinary content.
- A `jot.Div` with `data-component="guide-race"` is valid.
- Reject any other `data-component` value.
- Recurse through divs, block quotes, lists, headings, paragraphs, links,
  emphasis, strong text, images, and spans.

The renderer callback API cannot return `Result`, so validation must finish
before `lustre/ssg/djot.render` runs.

### Step 5: Run focused tests

Run:

```sh
cd website_lustre
gleam format --check src test
gleam test --target javascript -- content
```

Expected: PASS.

### Step 6: Commit

```sh
git add website_lustre/src/watershed_site/guide.gleam \
  website_lustre/src/watershed_site/content.gleam \
  website_lustre/test/content_test.gleam \
  website_lustre/test/fixtures
git commit -m "feat(website): validate Djot content"
```

---

## Task 3: Decode source snippets and render highlighted Lustre elements

**Files:**
- Create: `website_lustre/src/watershed_site/snippet.gleam`
- Create: `website_lustre/src/watershed_site/code.gleam`
- Create: `website_lustre/test/snippet_test.gleam`
- Create: `website_lustre/test/fixtures/snippet.djot`

### Step 1: Generate the real manifest

Run:

```sh
just snippets
```

Confirm that `website/src/generated/snippets.json` exists and remains ignored.

### Step 2: Write failing manifest tests

Mirror the version-1 schema from
`tools/source-snippets/src/source_snippets/manifest.gleam`:

```gleam
pub type Manifest {
  Manifest(version: Int, snippets: Dict(String, Snippet))
}

pub type Snippet {
  Snippet(
    code: String,
    language: String,
    source_path: String,
    origin: Origin,
  )
}

pub type Origin {
  Source(markers: List(String))
  File
}

pub fn load(path: String) -> Result(Manifest, BuildError)
pub fn decode(source: String, path: String) -> Result(Manifest, BuildError)
pub fn get(manifest: Manifest, path: String, id: String)
  -> Result(Snippet, BuildError)
```

Test:

- the real manifest decodes as version 1;
- version 2 is rejected;
- a missing `snippets` object is rejected;
- source and file origins both decode;
- `get` returns `MissingSnippet(path, id)` for an unknown ID.

Add a Djot fixture whose code block uses a real manifest ID:

````djot
```gleam
{data-snippet="retro-schema-title"}
ignored fixture text
```
````

The rendered result must use manifest code, not `ignored fixture text`.

Run:

```sh
cd website_lustre
gleam test --target javascript -- snippet
```

Expected: FAIL because the snippet and code modules do not exist.

### Step 3: Decode the manifest

Use `gleam/json` and `gleam/dynamic/decode`. Keep the outer version check
separate so the error states the unsupported version. Do not accept partial
entries.

Convert source paths to public GitHub links with one function:

```gleam
pub fn source_url(snippet: Snippet, revision: String) -> String
```

Use the repository URL and the pinned site revision supplied to the build. Pass
that revision through the page renderer and `code.block`. Do not point source
chips at a local file path.

### Step 4: Render Smalto tokens without `smalto_lustre`

Expose:

```gleam
pub fn block(snippet: Snippet, revision: String) -> Element(msg)
pub fn highlighted(language: String, source: String) -> List(Element(msg))
```

For `gleam`, call `smalto.to_tokens(source, gleam.grammar())`. For `js`, call
the JavaScript grammar. Map tokens as follows:

```gleam
fn token_view(item: token.Token) -> Element(msg) {
  case item {
    token.Whitespace(value) | token.Other(value) -> element.text(value)
    other -> html.span(
      [attribute.class("smalto-" <> token.name(other))],
      [element.text(token.value(other))],
    )
  }
}
```

Use explicit imports or aliases so the variable does not shadow the module.
For any other language, return one escaped `element.text(source)` node and keep
the language in `data-language`.

`block` must render:

- a language label;
- `<pre><code>` with token elements;
- a source-path link with a visible keyboard focus style;
- the source path as link text.

### Step 5: Validate snippet references before rendering

Extend the Task 2 AST validator. A code block with `data-snippet` must resolve
in the loaded manifest. A code block without that attribute remains literal
Djot code. The validator returns `MissingSnippet` before the renderer runs.

### Step 6: Run focused tests

Run:

```sh
cd website_lustre
gleam format --check src test
gleam test --target javascript -- snippet
```

Expected: PASS. The test output string contains `smalto-keyword` for Gleam,
contains the source link, does not contain the ignored fixture text, and
escapes `<script>` in an unknown-language block.

### Step 7: Commit

```sh
git add website_lustre/src/watershed_site/snippet.gleam \
  website_lustre/src/watershed_site/code.gleam \
  website_lustre/src/watershed_site/content.gleam \
  website_lustre/test/snippet_test.gleam \
  website_lustre/test/fixtures/snippet.djot
git commit -m "feat(website): render source snippets"
```

---

## Task 4: Build the shared document, sheet, and guide views

**Files:**
- Create: `website_lustre/src/watershed_site/page.gleam`
- Create: `website_lustre/src/watershed_site/view/document.gleam`
- Create: `website_lustre/src/watershed_site/view/sheet.gleam`
- Create: `website_lustre/src/watershed_site/view/guide.gleam`
- Create: `website_lustre/src/watershed_site/view/adjoining_sheets.gleam`
- Create: `website_lustre/src/watershed_site/view/ecosystem.gleam`
- Create: `website_lustre/test/document_test.gleam`

### Step 1: Write failing document tests from the Astro output contract

Render a small guide page to `element.to_document_string` and assert:

- `<!doctype html>` and `<html lang="en">`;
- the exact title and description;
- `og:title`, `og:description`, `og:type`, `og:image`, `og:image:width`,
  `og:image:height`, `og:image:alt`, and `og:url`;
- the current Twitter card metadata;
- no canonical link;
- `/favicon.svg`;
- `/styles/site.css` and `/styles/guide-race.css`;
- the Tinylytics script attributes used by `Sheet.astro`;
- the page-scoped module script and no unrelated client bundle;
- skip link, site header, primary navigation, `field atlas`, and
  `adjoining sheets`;
- guide breadcrumb, step number, previous link, and next link;
- no Astro or Vite markers.

Use exact strings from the current Astro components. Do not paraphrase.

Run:

```sh
cd website_lustre
gleam test --target javascript -- document
```

Expected: FAIL because the view modules do not exist.

### Step 2: Define the page input

Use one typed value at the layout boundary:

```gleam
pub type GuidePage(msg) {
  GuidePage(
    route: route.Route,
    metadata: content.Metadata,
    step: guide.Step,
    body: List(Element(msg)),
    demo: Element(msg),
  )
}

pub fn view(page: GuidePage(msg)) -> Element(msg)
```

Do not pass a dictionary through view code.

### Step 3: Port the complete document shell

`view/document.gleam` owns `<html>`, `<head>`, and `<body>`. It receives:

```gleam
pub type Document {
  Document(
    title: String,
    description: String,
    url: String,
    stylesheets: List(String),
    scripts: List(Script),
    body: Element(Nil),
  )
}

pub type Script {
  Module(src: String)
  Deferred(src: String, attributes: List(#(String, String)))
}

pub fn view(document: Document) -> Element(Nil)
```

Build `https://watershed.tylerbutler.com` URLs in one constant. Preserve the
current ordering of metadata and scripts where browser behavior depends on it.
Map the page tree to `Nil` only at this complete-document boundary. Add
Tinylytics only when the route's analytics policy is `Tinylytics`, and add only
the client script named by that route.

### Step 4: Port the shared site views

Port semantic structure and text from:

- `Sheet.astro` to `view/sheet.gleam`;
- `GuideLayout.astro` to `view/guide.gleam`;
- `AdjoiningSheets.astro` to `view/adjoining_sheets.gleam`;
- `Ecosystem.astro` to `view/ecosystem.gleam`.

Keep links, `aria-*` text, heading levels, landmarks, and source order. The
pilot can render only the links visible on `/guide/race`; do not add stubs for
the other 42 routes.

### Step 5: Run focused tests

Run:

```sh
cd website_lustre
gleam format --check src test
gleam test --target javascript -- document
```

Expected: PASS.

### Step 6: Commit

```sh
git add website_lustre/src/watershed_site/page.gleam \
  website_lustre/src/watershed_site/view \
  website_lustre/test/document_test.gleam
git commit -m "feat(website): render guide document"
```

---

## Task 5: Migrate the race page copy and static assets

**Files:**
- Create: `website_lustre/content/guide/race.djot`
- Create: `website_lustre/assets/**`
- Create: `website_lustre/test/assets_test.gleam`
- Modify: `website_lustre/src/watershed_site/page.gleam`

### Step 1: Write failing asset and content parity tests

The asset test must check that each referenced stylesheet, image, font file,
and license exists under `website_lustre/assets`. Compare the favicon and
social image bytes with the committed Astro sources. Record and test SHA-256
hashes for each copied WOFF2 file so CI does not need `website/node_modules`.

The content test must load `content/guide/race.djot` and assert:

- layout `Guide` and guide slug `Race`;
- the current description;
- the catalog derives route `/guide/race`, step `03`, title, goal, and API
  surface;
- the catalog derives `notes` as previous and `votes` as next;
- every heading and prose paragraph from `website/src/pages/guide/race.astro`;
- exactly one `guide-race` component marker.

Run:

```sh
cd website_lustre
gleam test --target javascript -- assets
gleam test --target javascript -- content
```

Expected: FAIL because the content and assets do not exist.

### Step 2: Migrate the route to Djot

Read `.github/instructions/website-copy.instructions.md` again, then transcribe
the public copy from `website/src/pages/guide/race.astro`. Put route and guide
selection metadata in TOML frontmatter. Keep the step title, goal, surface, and
neighbors in `watershed_site/guide.gleam`. Replace only the Astro component
invocation with:

```djot
{data-component="guide-race"}
:::
:::
```

Wrap each of the two prose groups in an ordinary Djot fenced div with class
`g-block`. The renderer must preserve that class. This replaces the two
`<div class="g-block">` wrappers without raw HTML.

Do not add a snippet block to the public page. The snippet renderer remains
covered by `test/fixtures/snippet.djot`.

### Step 3: Copy images and font assets

Copy:

- `website/public/favicon.svg` to `website_lustre/assets/favicon.svg`;
- `website/public/og.png` to `website_lustre/assets/og.png`;
- Archivo Variable `wdth.css`, its referenced WOFF2 files, and its license;
- JetBrains Mono `400.css`, `400-italic.css`, `700.css`, their referenced WOFF2
  files, and the package license.

Preserve each Fontsource stylesheet's relative `./files/...` URLs.

If `website/node_modules` is absent, run:

```sh
cd website
pnpm install --frozen-lockfile
```

Do not add the Fontsource packages to `website_lustre`; the copied files are
committed static assets.

### Step 4: Port CSS without redesigning the page

Build `assets/styles/site.css` from the global and shared layout rules used by
the route. Build `assets/styles/guide-race.css` from
`GuideRaceDemo.astro`'s scoped CSS.

When translating Astro's scoped selectors:

- root them under `[data-guide-race]`;
- preserve media queries and reduced-motion behavior;
- preserve focus-visible styles;
- preserve disabled and in-flight states;
- remove only Astro-generated scope selectors;
- do not rename visible design tokens or change measurements.

### Step 5: Render Djot through a custom renderer

Create a renderer based on `lustre/ssg/djot.default_renderer()`. Override:

- `codeblock` for source-backed snippets and highlighted literal blocks;
- `div` for `data-component="guide-race"`;
- `raw_html` with an unreachable plain-text error element.

The validated component div calls the static guide race view from Task 8. Until
Task 8 exists, use a private empty shell with the final root ID and a test that
Task 8 replaces. Do not expose temporary copy in the generated page.

### Step 6: Run focused tests

Run:

```sh
cd website_lustre
gleam format --check src test
gleam test --target javascript -- assets
gleam test --target javascript -- content
```

Expected: PASS.

### Step 7: Commit

```sh
git add website_lustre/content website_lustre/assets \
  website_lustre/src/watershed_site/page.gleam \
  website_lustre/test/assets_test.gleam \
  website_lustre/test/content_test.gleam
git commit -m "feat(website): migrate race page assets"
```

---

## Task 6: Add a generic deferred Lustre effect

**Files:**
- Modify: `watershed_lustre/src/watershed_lustre.gleam`
- Modify: `watershed_lustre/test/watershed_lustre_test.gleam`

### Step 1: Write the failing public API test

The CRDT submodule already has the required implementation:

```gleam
pub fn perform(
  operation operation: fn() -> a,
  outcome outcome: fn(a) -> msg,
) -> Effect(msg)
```

Add a top-level test that imports `watershed_lustre` and verifies:

- the operation does not run while `update` builds the effect;
- the operation runs when Lustre performs the effect;
- the outcome is dispatched on a microtask;
- a `Result` value reaches the message unchanged.

Follow the existing effect tests and JavaScript promise helpers in this package.

Run:

```sh
cd watershed_lustre
gleam test --target javascript
```

Expected: FAIL because `watershed_lustre.perform` is not public.

### Step 2: Re-export the existing implementation

Import `watershed_lustre/crdt` with a non-conflicting alias and add:

```gleam
/// Run an operation when Lustre performs the effect.
///
/// The effect sends the outcome on a microtask.
pub fn perform(
  operation operation: fn() -> a,
  outcome outcome: fn(a) -> msg,
) -> Effect(msg) {
  crdt_effect.perform(operation:, outcome:)
}
```

Do not duplicate `effect.from` or `queue_microtask`.

### Step 3: Run the package tests

Run:

```sh
cd watershed_lustre
gleam format --check src test
gleam test --target javascript
```

Expected: PASS.

### Step 4: Commit

```sh
git add watershed_lustre/src/watershed_lustre.gleam \
  watershed_lustre/test/watershed_lustre_test.gleam
git commit -m "feat(lustre): expose deferred effect"
```

---

## Task 7: Build the guide race runtime and pure transitions

**Files:**
- Create: `website_lustre/src/watershed_site/guide_race/runtime.gleam`
- Create: `website_lustre/test/guide_race_runtime_test.gleam`

### Step 1: Write failing model and transition tests

Use these public types:

```gleam
pub type Replica {
  Alpha
  Beta
}

pub type Phase {
  Static
  Starting
  Ready
  Delivering
  Failed
}

pub type PendingMarker {
  PendingMarker(
    sequence_number: Int,
    author: String,
    targets: List(String),
  )
}

pub type FlowMarker {
  FlowMarker(
    id: Int,
    from: String,
    to: String,
    label: String,
  )
}

pub type LogEntry {
  LogEntry(
    sequence_number: Int,
    author: String,
    event: String,
    target: String,
  )
}

pub type Model {
  Model(
    phase: Phase,
    rig: Option(Rig),
    alpha: board.Snapshot,
    beta: board.Snapshot,
    pending: List(PendingMarker),
    flows: List(FlowMarker),
    log: List(LogEntry),
    generation: Int,
    latency_ms: Int,
    race_locked: Bool,
    delivery_active: Bool,
    converged: Bool,
    error: Option(String),
  )
}

pub type Msg {
  Start
  Started(generation: Int, Result(Rig, DemoError))
  RunAddRace
  AddRaceSubmitted(generation: Int, Result(RaceMutation, DemoError))
  RunVoteRace
  VoteRaceSubmitted(generation: Int, Result(RaceMutation, DemoError))
  Deliver(generation: Int)
  Delivered(generation: Int, Result(DeliveryState, DemoError))
  ClearFlow(generation: Int, marker_id: Int)
  SetLatency(Int)
  Reset
  ResetDone(generation: Int, Result(Rig, DemoError))
}

pub fn static_model() -> Model
pub fn init() -> #(Model, Effect(Msg))
pub fn update(Model, Msg) -> #(Model, Effect(Msg))
```

Test pure message transitions:

- `static_model` has the current initial notes, no error, and no live rig;
- `init` enters `Starting` and returns one effect;
- `Started(_, Ok(rig))` enters `Ready`;
- `Started(_, Error(error))` enters `Failed` with visible text;
- `RunAddRace` while ready locks the race buttons and returns one effect that submits
  both client writes before any frame is delivered;
- `RunAddRace` while locked changes nothing and returns no effect;
- `AddRaceSubmitted` stores both locally divergent snapshots, both sequence
  numbers, pending markers, client-to-sequencer flow markers, and a delayed
  delivery effect;
- `RunVoteRace` submits `+1` from alpha, then `+1` and `-1` from beta before
  delivery;
- `Deliver` returns an effect only when a frame is pending;
- final delivery ends the active delivery and sets `converged = True`;
- race buttons stay locked after a completed race until reset;
- `ClearFlow` removes only its named transient marker;
- latency clamps to the current UI range;
- reset increments `generation`, enters `Starting`, clears transient state, and
  returns an effect;
- completion, delivery, and clear-flow messages from an older generation do
  nothing;
- every failed mutation, projection, delivery, and reset enters `Failed`.

Run:

```sh
cd website_lustre
gleam test --target javascript -- guide_race_runtime
```

Expected: FAIL because the runtime module does not exist.

### Step 2: Define the live rig

The live value holds one sluice and two typed replicas:

```gleam
pub opaque type Rig {
  Rig(
    sluice: sluice_js.Sluice,
    alpha: ReplicaState,
    beta: ReplicaState,
  )
}

type ReplicaState {
  ReplicaState(
    client_id: String,
    document: watershed.Document(document_schema.BoardDocument),
    notes: watershed.OrMap,
    votes: watershed.OrMap,
  )
}
```

`start_rig` must:

1. Start one sluice with fixed tenant and document IDs.
2. Connect `alpha` and `beta`.
3. Settle both handshakes.
4. Create the notes `RegisterMode` OR-map and votes `TallyMode` OR-map on alpha.
5. Store both handles on alpha's root under the schema field keys.
6. Settle handle operations.
7. Resolve both maps on both replicas.
8. Resolve both client IDs.
9. Seed the exact current initial notes through `board.add_note`.
10. Settle seed operations and project both snapshots.

Return `Result(Rig, DemoError)` at every fallible step. Replace each `assert`
from the example test fixture with `result.try`.

### Step 3: Put mutations in effects

The `update` branches create effects with `watershed_lustre.perform`:

```gleam
watershed_lustre.perform(
  operation: fn() { submit_add_race(rig) },
  outcome: fn(result) { AddRaceSubmitted(model.generation, result) },
)
```

The add-race operation:

- calls `board.add_note` once on alpha and once on beta with the exact current
  demo note data;
- reads `sluice_js.sequence_number` after each write;
- projects alpha and beta without settling;
- uses `peek_info` to identify the first pending broadcast group;
- returns typed mutation data.

The vote-race operation calls `board.upvote` on alpha, then `board.upvote` and
`board.downvote` on beta. It also returns all three sequence numbers before any
delivery.

Do not call `sluice_js.settle` after a user mutation. The visible race requires
queued frames.

`AddRaceSubmitted` batches the first `Deliver(model.generation)` timer with
timers that clear the client-to-sequencer markers. The latency slider and reset
control stay available; only the race buttons remain locked after a race
starts. Every timer carries the current generation so reset makes all old
timers harmless.

### Step 4: Deliver one broadcast group per timer

Use `sluice_js.peek_info` and `sluice_js.step_info` to deliver all frames with
the next nonzero sequence number as one visual step. Record one `LogEntry` per
delivered frame. After each group:

- project alpha and beta;
- add sequencer-to-client `FlowMarker` values for the delivered targets;
- schedule `ClearFlow` for transient markers;
- if pending frames remain, return
  `watershed_lustre.after(latency_ms, Deliver(model.generation))`;
- otherwise end `delivery_active` and calculate convergence from the two
  snapshots. Keep `race_locked = True` until reset.

Non-operation handshake frames can be drained during startup. During the demo,
report an unexpected zero-sequence frame as `DemoError`.

### Step 5: Keep failures descriptive

Define:

```gleam
pub type DemoError {
  CannotCreateNotes(String)
  CannotCreateVotes(String)
  MissingHandle(replica: Replica, field: String)
  CannotResolveHandle(replica: Replica, field: String, reason: String)
  MissingClientId(replica: Replica)
  CannotProject(replica: Replica, reason: String)
  UnexpectedDelivery(event: String)
}

pub fn describe_error(error: DemoError) -> String
```

Messages must identify the replica and operation. Do not expose a JavaScript
stack trace in page copy.

### Step 6: Add one real sluice convergence test

In addition to pure transition tests, perform effects through Lustre's test
runtime or call the private operation through a test-only public scenario
function:

1. Start the rig.
2. Submit the add race and leave all frames queued.
3. Verify alpha has only its new local note and beta has only its new local
   note.
4. Verify the snapshots differ while frames wait.
5. Deliver all groups.
6. Verify both snapshots are equal and contain both notes.
7. Verify the operation log includes both sequence numbers and both client IDs.

Do not replace this with hand-built snapshots. This test proves the route uses
the real watershed runtime.

### Step 7: Run focused tests

Run:

```sh
cd website_lustre
gleam format --check src test
gleam test --target javascript -- guide_race_runtime
```

Expected: PASS.

### Step 8: Commit

```sh
git add website_lustre/src/watershed_site/guide_race/runtime.gleam \
  website_lustre/test/guide_race_runtime_test.gleam
git commit -m "feat(website): model the guide race"
```

---

## Task 8: Render one shared static and interactive race view

**Files:**
- Create: `website_lustre/src/watershed_site/guide_race/view.gleam`
- Create: `website_lustre/src/watershed_site/client/guide_race.gleam`
- Create: `website_lustre/test/guide_race_view_test.gleam`
- Modify: `website_lustre/src/watershed_site/page.gleam`

### Step 1: Write failing view tests with Lustre simulation

Use `lustre/dev/simulate` and `lustre/dev/query` where events are involved.
Test:

- one root with `id="guide-race-demo"` and `data-guide-race`;
- two replica panels with stable labels and test IDs;
- the `Went well` board column shown by the current route;
- initial note cards from `runtime.static_model`;
- latency input with its accessible label and value;
- add-note controls;
- vote controls present but hidden when `notes_only = True`;
- operation log and sequence display;
- convergence status;
- in-flight markers;
- client-to-sequencer and sequencer-to-client flow markers;
- race buttons disabled while `race_locked`;
- latency and reset controls available after startup;
- an `aria-live` error region;
- a `<noscript>` explanation in static output;
- add, vote, latency, reset, and delivery events produce the expected messages.

Run a complete simulated state sequence as well: start from a ready fixture,
click the add-race button, inject the typed two-write outcome, inject each
delivery outcome, query the divergent intermediate boards and status text, and
finish at equal boards with the race button locked. Then dispatch reset and
verify the initial board and assistive status return.

Run:

```sh
cd website_lustre
gleam test --target javascript -- guide_race_view
```

Expected: FAIL because the view module does not exist.

### Step 2: Define one view used by SSG and browser runtime

Expose:

```gleam
pub type Options {
  Options(notes_only: Bool, include_noscript: Bool)
}

pub fn view(model: runtime.Model, options: Options) -> Element(runtime.Msg)

pub fn static() -> Element(Nil) {
  view(
    runtime.static_model(),
    Options(notes_only: True, include_noscript: True),
  )
  |> element.map(fn(_) { Nil })
}
```

Keep the message erasure explicit. Static serialization does not write event
handlers into the document.

Keep card rendering based on `board.cards_for`. Do not duplicate the board
projection.

### Step 3: Port the accessibility contract

Carry across:

- explicit panel labels;
- button names that include replica and column context;
- latency label and output;
- disabled semantics during delivery;
- `aria-live` status for delivery, convergence, and errors;
- keyboard focus styles;
- reduced-motion behavior from CSS;
- meaningful no-script copy.

The hidden vote controls retain their accessible implementation for a later
route, but `hidden` removes them from the `/guide/race` accessibility tree.

### Step 4: Start the browser application

The page-scoped entry is:

```gleam
import lustre
import watershed_site/guide_race/runtime
import watershed_site/guide_race/view

pub fn main() {
  let app =
    lustre.application(
      init: fn(_) { runtime.init() },
      update: runtime.update,
      view: fn(model) {
        view.view(
          model,
          view.Options(notes_only: True, include_noscript: False),
        )
      },
    )

  let assert Ok(_) = lustre.start(app, "#guide-race-demo", Nil)
}
```

Check the installed Lustre 5 signature and adjust the final flags argument if
the compiler requires it. The selector and replacement behavior are fixed.

Run the client-only development server with:

```sh
cd website_lustre
gleam run -m lustre/dev start watershed_site/client/guide_race
```

The configured development body supplies `#guide-race-demo`. Full page checks
still use `just website-lustre-serve`.

### Step 5: Replace the temporary static component

Update the Djot renderer in `page.gleam` so the validated `guide-race` div calls
`guide_race/view.static()`. Remove the Task 5 empty shell and its temporary
test.

### Step 6: Run focused tests

Run:

```sh
cd website_lustre
gleam format --check src test
gleam test --target javascript -- guide_race
```

Expected: PASS.

### Step 7: Commit

```sh
git add website_lustre/src/watershed_site/guide_race/view.gleam \
  website_lustre/src/watershed_site/client/guide_race.gleam \
  website_lustre/src/watershed_site/page.gleam \
  website_lustre/test/guide_race_view_test.gleam
git commit -m "feat(website): render the race application"
```

---

## Task 9: Bundle the page application and generate the static site

**Files:**
- Create: `website_lustre/dev/watershed_site/build.gleam`
- Create: `website_lustre/dev/watershed_site/system.gleam`
- Create: `website_lustre/dev/watershed_site/system_ffi.mjs`
- Create: `website_lustre/test/generated_site_test.gleam`
- Modify: `website_lustre/src/watershed_site.gleam`
- Modify: `justfile`

### Step 1: Write the failing generated-site test

Expose an injectable build function:

```gleam
pub fn build(
  out_dir: String,
  static_dir: String,
  snippet_manifest: String,
  revision: String,
) -> Result(Nil, BuildError)
```

The test builds into a test-only temporary directory and reads
`guide/race/index.html`. Parse it with `html_parser.as_tree`; do not use regular
expressions as an HTML parser. Assert:

- the route exists at the index path;
- the page contains all Task 4 metadata;
- the static race root and initial notes exist;
- the page includes `/watershed_site_client_guide_race.mjs`;
- the referenced script exists in the output;
- CSS, fonts, favicon, and social image exist;
- no Astro island, `/_astro/`, or Vite client marker exists;
- the output contains no unexpanded `data-component` marker;
- the fixture build fails before replacing an existing output when content
  validation fails.

Run:

```sh
cd website_lustre
gleam test --target javascript -- generated_site
```

Expected: FAIL because the build function does not exist.

### Step 2: Build all route elements before calling `lustre_ssg`

`watershed_site.build` must:

1. Validate `route.all()`.
2. Load the snippet manifest.
3. Load and validate every route's content.
4. Render every route to a complete `Element(Nil)`.
5. Only after all four steps succeed, create the SSG config.
6. Call `ssg.new(out_dir)`.
7. Call `ssg.add_static_dir(static_dir)`.
8. Call `ssg.use_index_routes`.
9. Add each static route.
10. Call `ssg.build`.
11. Map `ssg.BuildError` to `SiteGenerationFailed`.

This ordering keeps invalid content from replacing a previous valid output.
`lustre_ssg` writes through a temporary directory for its own file operations.

### Step 3: Add the build entry

`dev/watershed_site/build.gleam` reads:

- output directory from argument 1, default `./dist`;
- static staging directory from argument 2, default `./build/static`;
- snippet manifest from argument 3, default
  `../website/src/generated/snippets.json`;
- revision from `GITHUB_SHA`, default `main`.

Print one contextual error to stderr and exit nonzero. Use `argv`, `envoy`, and
the source-snippet tool's process-exit pattern. Add:

```gleam
@external(javascript, "./system_ffi.mjs", "halt")
pub fn halt(code: Int) -> Never
```

The FFI calls `process.exit(code)`. It contains no build or rendering logic.

### Step 4: Build with official Lustre development tools

Run:

```sh
just snippets
cd website_lustre
rm -rf build/static
gleam run -m lustre/dev build watershed_site/client/guide_race
gleam run -m watershed_site/build
```

Expected outputs:

- `build/static/watershed_site_client_guide_race.mjs`;
- copied files from `assets/` under `build/static/`;
- `dist/guide/race/index.html`;
- the same bundle and assets under `dist/`.

If the installed dev tools use a different deterministic entry filename, update
the route registry and tests to that observed name. Do not glob for an arbitrary
script at page-render time.

### Step 5: Add root build recipes

Add:

```make
_build-website-lustre: snippets
    rm -rf website_lustre/build/static
    cd website_lustre && gleam run -m lustre/dev build watershed_site/client/guide_race
    cd website_lustre && gleam run -m watershed_site/build

website-lustre: _build-website-lustre

website-lustre-serve: _build-website-lustre
    pnpm dlx netlify-cli@27.4.1 dev --offline --port 4321 --dir website_lustre/dist
```

Append `_build-website-lustre` to the root `build` dependency list. Keep the
existing Astro bundle and Netlify build unchanged.

The removal targets only the generated static staging directory. The SSG
replaces `dist` through its own temporary-directory build.

### Step 6: Run the generated-site checks

Run:

```sh
just website-lustre
cd website_lustre
gleam test --target javascript -- generated_site
```

Expected: PASS.

### Step 7: Commit

```sh
git add justfile website_lustre/dev \
  website_lustre/src/watershed_site.gleam \
  website_lustre/test/generated_site_test.gleam
git commit -m "feat(website): generate the Lustre pilot"
```

---

## Task 10: Add browser parity tests and the dedicated root test gate

**Files:**
- Create: `website_lustre/package.json`
- Create: `website_lustre/pnpm-lock.yaml`
- Create: `website_lustre/test/browser/guide-race.mjs`
- Modify: `justfile`

### Step 1: Add the browser-test package

Create a private package with no application build:

```json
{
  "name": "watershed-site-browser-tests",
  "private": true,
  "type": "module",
  "packageManager": "pnpm@11.13.1",
  "scripts": {
    "smoke": "node test/browser/guide-race.mjs"
  },
  "devDependencies": {
    "puppeteer": "^25.3.0"
  }
}
```

Run:

```sh
cd website_lustre
pnpm install
```

Commit the resulting lockfile.

### Step 2: Write the failing browser smoke test

Adapt the launch and Chromium discovery code from the existing website smoke
harness. The test must start its own static server on an available loopback
port, close both browser and server in `finally`, and fail on page errors or
console errors.

With JavaScript disabled, assert:

- `/guide/race/` returns 200;
- title and metadata match;
- headings and prose are visible;
- both static replica panels and initial notes are visible;
- no-script copy is visible;
- navigation and previous/next links work;
- no Astro or Vite runtime appears.

With JavaScript enabled, assert:

- the static root is replaced once, not duplicated;
- critical computed styles match fixed values recorded from the Astro route for
  body fonts, section borders, replica grid placement, note borders, button
  sizing, focus outlines, and the narrow-screen layout;
- both replicas begin with equal snapshots;
- clicking `Add two notes at once` writes one note on alpha and one different
  note on beta before delivery;
- race buttons lock while frames wait;
- alpha and beta show their different optimistic notes before delivery;
- flow markers move each local operation to the sequencer, then each sequenced
  operation to the target replica;
- delivery follows the selected latency;
- both replicas receive both notes;
- the operation log shows sequence number, author, event, and target;
- status returns to converged, the add button stays locked, and reset remains
  available;
- reset restores the initial state and clears transient log entries.

Use `data-testid` values only.

Run before starting a server:

```sh
cd website_lustre
pnpm run smoke
```

Expected: FAIL with a clear connection error.

### Step 3: Run against the generated site

Run:

```sh
just website-lustre
cd website_lustre
pnpm run smoke
```

Expected: PASS. If Chromium is unavailable, follow the repository's existing
smoke-test convention: print the reason and skip locally. CI installs Chromium,
so CI must not skip.

### Step 4: Add the dedicated root test recipe

Add:

```make
_test-website-lustre: _build-website-lustre
    cd website_lustre && gleam test --target javascript
    cd website_lustre && pnpm run smoke
```

Append `_test-website-lustre` to the root `test` dependency list. The generic
Trellis `test` task continues to exclude `website_lustre`, as set in Task 1.

### Step 5: Run the pilot gate

Run:

```sh
just _test-website-lustre
```

Expected: all Gleam tests and the browser smoke pass.

### Step 6: Commit

```sh
git add justfile website_lustre/package.json website_lustre/pnpm-lock.yaml \
  website_lustre/test/browser/guide-race.mjs
git commit -m "test(website): cover the Lustre pilot"
```

---

## Task 11: Add GitHub Actions build, Netlify preview, and package documentation

**Files:**
- Create: `.github/workflows/website-lustre.yml`
- Create: `website_lustre/README.md`

### Step 1: Write the package README

Document:

- the pilot scope and coexistence with `website/`;
- required Gleam, Erlang, Node, pnpm, and Bun behavior;
- `just website-lustre`;
- `just website-lustre-serve`;
- `just _test-website-lustre`;
- the content, route, renderer, asset, and page-scoped entry locations;
- why `smalto_lustre` is not a dependency;
- how to add the next route and client entry;
- that the root `netlify.toml` still publishes Astro;
- that production cutover is a later milestone.

Do not describe unfinished migration work as available.

### Step 2: Add CI build and test jobs

Create a workflow for pull requests, pushes to `main`, and manual dispatch.
Pin third-party actions to full commit SHAs.

The build job must:

1. Check out the repository.
2. Install OTP 28 and Gleam 1.16.0 with `erlef/setup-beam`.
3. Install Node 24, pnpm 11.13.1, and `just` with pinned setup actions.
4. Set `PUPPETEER_CACHE_DIR` to a workspace-local cache path.
5. Cache Gleam packages, `website_lustre/.lustre`, pnpm, and Puppeteer's browser.
6. Run `gleam deps download` in `tools/source-snippets`.
7. Run `just snippets`.
8. Run `gleam deps download` in `website_lustre`.
9. Run `pnpm install --frozen-lockfile` in `website_lustre`.
10. Run `gleam format --check src test dev` in `website_lustre`.
11. Remove only `website_lustre/build/static`.
12. Run `gleam run -m lustre/dev build watershed_site/client/guide_race`.
13. Run `GITHUB_SHA=$GITHUB_SHA gleam run -m watershed_site/build`.
14. Run `gleam test --target javascript`.
15. Run `pnpm run smoke` with `CI=true`, which must treat a missing browser as
    a failure.
16. Upload `website_lustre/dist` as the `website-lustre` artifact.

Do not run the Astro Netlify build in this workflow.

### Step 3: Add the Netlify preview job

Run the deploy job for manual dispatches and pull requests whose head repository
equals the base repository. Skip it for fork pull requests, which must not
receive secrets. The job downloads the tested artifact and runs a pinned
Netlify CLI version:

```sh
pnpm dlx netlify-cli@27.4.1 deploy \
  --dir website_lustre/dist \
  --auth "$NETLIFY_AUTH_TOKEN" \
  --site "$NETLIFY_SITE_ID" \
  --message "Lustre pilot ${GITHUB_SHA}"
```

Use repository secrets. Do not print them. Do not pass `--prod`; this milestone
creates a deploy preview only. Give same-repository pull requests the stable
`lustre-pr-${{ github.event.pull_request.number }}` alias. Manual dispatches can
use Netlify's generated preview URL.

### Step 4: Validate the workflow and documentation

Run:

```sh
just _test-website-lustre
git diff --check
```

Inspect the workflow paths and action pins. Confirm that `netlify.toml` is
unchanged.

### Step 5: Commit

```sh
git add .github/workflows/website-lustre.yml website_lustre/README.md
git commit -m "ci(website): deploy Lustre previews"
```

---

## Task 12: Run the full repository gates and inspect the migration boundary

**Files:**
- Modify only files required by failures caused by Tasks 1 through 11.

### Step 1: Run formatting

Run:

```sh
just format
git diff --check
```

Review formatter changes before staging. Do not stage unrelated worktree files.

### Step 2: Run the focused site gate

Run:

```sh
just _test-website-lustre
```

Expected: PASS.

### Step 3: Run workspace builds and tests

Run:

```sh
just build
just test
just lint
```

The repository has intentional compile-fail fixtures. Judge them by the
justfile's expected checks, not by an isolated successful compile.

### Step 4: Inspect generated output

Serve `website_lustre/dist` and inspect `/guide/race/` at:

- desktop width;
- narrow mobile width;
- `prefers-reduced-motion: reduce`;
- keyboard-only navigation;
- JavaScript disabled.

Compare it beside the Astro route. Fix regressions in route copy, source order,
focus behavior, metadata, styles, and demo timing. Do not change the Astro page
to make the new page look correct.

### Step 5: Review the final diff boundary

Run:

```sh
git status --short
git diff --stat
git diff --name-only
```

The committed change set may contain:

- `website_lustre/**`;
- the root `gleam.toml`;
- the root `justfile`;
- the two `watershed_lustre` files from Task 6;
- `.github/workflows/website-lustre.yml`;
- this specification and plan history.

It must not contain:

- generated `website/src/generated/snippets.json`;
- generated `website_lustre/build/**`;
- generated `website_lustre/dist/**`;
- changes to the Astro site;
- changes to `netlify.toml`;
- unrelated `apm` or vendored instruction changes.

### Step 6: Commit any gate fixes

If the gates required code changes, commit only those files:

```sh
git commit -m "fix(website): pass Lustre pilot gates"
```

Stage each changed path from this plan explicitly before the commit. If no fixes
were needed, do not create an empty commit.

## Completion criteria

The vertical slice is complete when all of these statements are true:

- `just website-lustre` writes a static `/guide/race/` page.
- The output contains no Astro or Vite runtime.
- The static page retains useful content and the initial demo when JavaScript is
  unavailable.
- The browser loads only the guide race client entry.
- The live demo uses `sluice_js`, typed watershed documents, and the existing
  retro-board model.
- Two concurrent replica writes visibly diverge, travel, and converge.
- Failures appear near the controls.
- The route's copy, metadata, navigation, design, and accessibility match the
  current Astro route.
- Source snippet decoding and highlighting are tested without adding a snippet
  to the public race page.
- GitHub Actions produces a tested static artifact.
- Manual workflow dispatch can publish that artifact as a Netlify preview.
- The current Astro production deployment remains unchanged.
