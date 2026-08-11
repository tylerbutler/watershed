---
name: astro-tinylytics
description: Integrate the astro-tinylytics npm package into an Astro site to add Tinylytics analytics, kudos buttons, webmentions, event tracking, webrings, or no-JS tracking pixels. Use this skill whenever a user asks to add Tinylytics, hit counters, kudos buttons, webmention endpoints, or analytics to an Astro project — including Starlight-based sites — even if they don't mention astro-tinylytics by name. Also trigger when a user mentions tinylytics.app and wants to wire it into Astro.
---

# astro-tinylytics integration

This skill helps integrate [`astro-tinylytics`](https://www.npmjs.com/package/astro-tinylytics) into an Astro site. The package wraps Tinylytics features (analytics, kudos, webmentions, event tracking, webrings, tracking pixel) as Astro components.

The integration steps differ depending on whether the site is **plain Astro** or **Starlight** because they expose different head-injection mechanisms. Identify which kind of site you're working in before you start.

## Step 1: Identify the site type

Look for these signals in the project:

- `package.json` includes `@astrojs/starlight` → **Starlight site** (use Step 4)
- `astro.config.*` calls `starlight(...)` → **Starlight site**
- Otherwise → **plain Astro site** (use Step 3)

If you're unsure, ask the user. Don't guess — the integration approach is genuinely different.

## Step 2: Install the package

Use the project's package manager (check for `pnpm-lock.yaml` / `package-lock.json` / `yarn.lock`):

```sh
pnpm add astro-tinylytics
# or: npm install astro-tinylytics
# or: yarn add astro-tinylytics
```

`astro >= 4.0.0` is a peer dependency. Most modern Astro projects already satisfy this.

## Step 3: Decide where the embed code lives

**The Tinylytics embed code (a.k.a. site ID) is not a secret.** It ships in client HTML on every page load — anyone viewing source can see it. Treat it like a public identifier (similar to a Google Analytics measurement ID), not a credential. Specifically:

- **Don't gitignore** `.env` files just because they hold the embed code, and don't add a `.env.example` solely for this value. Those patterns exist for secrets; applying them here adds noise without protection.
- **Don't refuse to commit** the embed code to source control. Committing it directly is fine.

You have two reasonable options:

1. **Inline the value directly** in the component that renders `<Script>`. This is the simplest choice and is preferable when the embed code is used in only one place. Example: `<Script embedCode="abc123XYZ" ... />`.
2. **Read from an env var** (`PUBLIC_TINYLYTICS` is the convention — `PUBLIC_*` vars are exposed to client code in Astro, which is correct here since the value isn't secret). This makes sense if the value is referenced in multiple components, or if the user explicitly wants to swap it per-environment (staging vs. prod).

If the user pastes an embed code into the conversation, inline it. Don't invent an env var unless they ask for one or there's a real reason (multiple usages, multi-environment setup). When in doubt, prefer the simpler option and let the user request indirection if they want it later.

If you do use an env var, add it to `.env` and read it as `import.meta.env.PUBLIC_TINYLYTICS`. The remaining examples in this skill use the env-var form for illustration — substitute the literal embed code if you're inlining.

## Step 4: Plain Astro integration

In a plain Astro site, the layout file (commonly `src/layouts/Layout.astro` or `src/layouts/BaseLayout.astro`) renders `<head>`. Add the `<Script>` component there.

Find the layout, then edit `<head>`:

```astro
---
import { Script } from "astro-tinylytics";

const embedCode = import.meta.env.PUBLIC_TINYLYTICS;
---
<head>
  <!-- existing tags -->
  <Script embedCode={embedCode} hits kudos="custom" events beacon />
</head>
```

Pick the props that match what the user asked for. See **Step 6: Choosing widgets** below.

If the site has multiple layouts, place the script in whichever one is the universal wrapper. If there isn't one, ask the user where they want it.

## Step 5: Starlight integration

Starlight doesn't expose `<head>` directly — instead it lets you override individual UI slots via the `components` config option. Use the `Head` slot.

Create `src/components/Head.astro`:

```astro
---
import Default from "@astrojs/starlight/components/Head.astro";
import { Script } from "astro-tinylytics";

const embedCode = import.meta.env.PUBLIC_TINYLYTICS;
---
<Default><slot /></Default>
<link rel="webmention" href={`https://tinylytics.app/webmention/${embedCode}`} />
<Script embedCode={embedCode} hits kudos="custom" events beacon />
```

The `<Default>` wrapper preserves Starlight's default `<head>` content — don't drop it. Anything you render after `<Default>` is appended.

The `<link rel="webmention">` is optional — only include it if the user wants webmention support. (See **Webmentions** below.)

Then register the override in `astro.config.*`:

```ts
import { defineConfig } from "astro/config";
import starlight from "@astrojs/starlight";

export default defineConfig({
  integrations: [
    starlight({
      // ...existing config
      components: {
        Head: "./src/components/Head.astro",
      },
    }),
  ],
});
```

If there's already a custom `Head.astro`, edit it — don't replace it. Add the `<Script>` and import alongside what's already there.

If `components` already contains other overrides, add `Head` as a new key — don't replace the whole object.

## Step 6: Choosing widgets

The `<Script>` props are the master switch — a widget tag (like `<Hits />`) only works if the corresponding flag is set on `<Script>`. Match props to what the user asked for:

| User wants                         | `<Script>` prop          | Widget component          |
| ---------------------------------- | ------------------------ | ------------------------- |
| Page-view counter                  | `hits`                   | `<Hits />`                |
| Unique visitors only               | `hits="unique"`          | `<Hits />`                |
| Kudos buttons (default emoji)      | `kudos`                  | `<Kudos />`               |
| Kudos buttons (custom UI)          | `kudos="custom"`         | `<KudosButton />` or custom `<Kudos />` slot |
| Uptime badge (paid plan)           | `uptime`                 | `<Uptime />`              |
| Visitor countries widget           | `countries`              | `<Countries />`           |
| Webring link                       | `webring` or `webring="avatars"` | `<Webring />`     |
| Event tracking (clicks/downloads)  | `events`                 | `<Event />`               |
| Reliable event sends on navigation | `beacon` (with `events`) | —                         |
| SPA / client routing               | `spa`                    | —                         |
| Smaller payload (minified build)   | `min`                    | —                         |

Don't enable flags the user didn't ask for. If the user is vague ("just basic analytics"), `hits kudos="custom" events beacon` is a sensible default — it covers the common case (page views + a kudos button + click tracking that survives navigation).

### `min` — minified build

`min` swaps the embed for Tinylytics' `min.js` build, which ships less JavaScript. It's a pure size win with no behavioral difference, so it's a good default to include — especially on production sites where bundle size matters. Add it alongside the feature flags:

```astro
<Script embedCode={embedCode} min hits kudos="custom" events beacon />
```

If the user is debugging an integration issue, suggest dropping `min` temporarily so the un-minified script is easier to read in devtools.

## Step 7: Place widgets

The `<Script>` only enables features. To actually display a counter, kudos button, etc., the user needs to drop the matching widget component somewhere visible.

Common placements:

- `<Hits />` — footer or about page (`Total visits: <Hits />`)
- `<KudosButton path={Astro.url.pathname} />` — bottom of blog post layout
- `<Countries />` — about page
- `<Webring>` — sidebar or footer

Ask the user where they want each widget if it's not obvious from context. Don't sprinkle them around without asking.

### `<KudosButton>` styling

`<KudosButton>` is the opinionated wrapper with icon + label + threshold suffix. To get its default styles, import the stylesheet once (e.g. in the layout):

```astro
import "astro-tinylytics/styles.css";
```

Customize via CSS variables (see the package README for the full list — `--tlt-kudos-fg`, `--tlt-kudos-bg`, etc.). Skip the stylesheet entirely if the user wants to style from scratch using the documented class hooks.

`<KudosButton>` requires `kudos="custom"` on `<Script>`. If the user wants `<KudosButton>` but the script is set to plain `kudos`, change it.

### Per-post kudos

When using kudos on individual posts, pass an explicit `path` so the count is pinned to a canonical URL (otherwise multiple buttons on the same page collide). In a Starlight or blog post layout:

```astro
<KudosButton path={Astro.url.pathname} />
```

## Webmentions

Webmentions are independent of the analytics script. Add this `<link>` to the head wherever the script lives (plain Astro layout or Starlight `Head.astro`):

```astro
<link rel="webmention" href={`https://tinylytics.app/webmention/${embedCode}`} />
```

There's also a `<Tinylytics>` convenience wrapper imported via subpath that can render either the script or the webmention link (mutually exclusive — call it twice if both are needed). It's optional; the explicit `<link>` + `<Script>` pair is clearer for most cases.

## Event tracking

`<Event>` wraps a clickable element with Tinylytics tracking attributes. Use Tinylytics' `category.action` naming (e.g. `file.download`, `nav.menu.open`).

```astro
<Event name="file.download" value="resume.pdf" as="a" href="/resume.pdf">
  Download resume
</Event>
```

Requires `events` on `<Script>`. If the click navigates away (external link, file download), also set `beacon` on `<Script>` — without it, `sendBeacon` isn't used and the event is sometimes dropped.

`<Event>` auto-renders as `<a>` if `href` is set, otherwise `<button>`. Override with `as`.

## Tracking pixel (no-JS contexts)

For RSS feeds, email newsletters, or other contexts where JavaScript can't run, use `<Pixel>`:

```astro
<Pixel embedCode={embedCode} path="/posts/hello" />
```

This is for niche use cases — only suggest it if the user mentions feeds, email, or "no JavaScript".

## After wiring it up

Confirm the integration by running the dev server and checking that:

1. The Tinylytics `<script>` appears in the rendered `<head>` (view source, not devtools — the script is `defer`).
2. Widget elements (`<Hits>`, `<KudosButton>`) render to the page (they may show empty initially; the script populates them).
3. Type-checking passes — run the project's check task (often `pnpm check` or `astro check`).

If the user has a Tinylytics account, hits should appear in their dashboard within a minute or two of loading the dev or prod site.

## Common pitfalls

- **Forgetting to enable the flag on `<Script>`.** Dropping `<Hits />` without `hits` on `<Script>` results in a silent empty span. The flag is what tells the embed script to scan for and populate the widget.
- **Replacing Starlight's `<Default>` head instead of wrapping with it.** This breaks Starlight's CSS / metadata. Always render `<Default><slot /></Default>` first, then append.
- **Using `kudos` instead of `kudos="custom"` with `<KudosButton>`.** `<KudosButton>` expects only the count to be injected; plain `kudos` injects the full default button HTML and the suffix observer breaks.
- **Missing `path` on multiple kudos buttons on the same page.** Without it, all buttons share the same count. Set `path` to the canonical URL for the post.
- **Adding `beacon` without `events`.** `beacon` only matters for event tracking; on its own it does nothing.
- **Treating the embed code as a secret.** It's a public site identifier that ships in every HTML response. Don't gitignore `.env` for it, don't refuse to commit it, and don't add env-var indirection unless there's a real reason. See Step 3.
