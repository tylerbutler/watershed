# watershed website

Astro builds this site into `dist/`. Cloudflare Workers serves those static
assets; there is no server-rendered app or Cloudflare adapter.

## Build locally

Use Node 24, pnpm 11.13.1, and Gleam 1.18.1:

```sh
pnpm install --frozen-lockfile
pnpm build:cloudflare
pnpm preview:worker
```

Run these commands from `website/`. `build:cloudflare` installs Gleam if it
isn't on `PATH`, then runs `pnpm build`. The prebuild compiles the Gleam
runtime and samples, generates source snippets, checks TypeScript, and runs
the Node tests. The Gleam packages target JavaScript, so you don't need Erlang.
Set `GLEAM_VERSION` to override the compiler release used by the installer.

`preview:worker` serves the built site with Wrangler, including Workers'
redirect and HTML routing rules. Rebuild after changing source files.
`pnpm preview` still provides Astro's preview server.

## Cloudflare Workers Builds

Create a **Worker**, not a Pages project, and connect this Git repository.
Use these settings:

| Setting | Value |
| --- | --- |
| Worker name | `watershed-website` |
| Production branch | `main` |
| Root directory | `website` |
| Build command | `pnpm build:cloudflare` |
| Deploy command | `pnpm deploy` |
| Preview command | `pnpm deploy:preview` |
| Enable Preview Builds | Enabled |
| Build variable `PNPM_VERSION` | `11.13.1` |
| Build variable `GLEAM_VERSION` | `1.18.1` |

The checked-in `.node-version` selects Node 24. Leave automatic dependency
installation enabled; Cloudflare installs the website's dependencies before
running the build command. The website's `pnpm-workspace.yaml` permits the
native build steps for esbuild, sharp, and Wrangler's workerd runtime.

Keep the full repository checkout. The website imports Gleam code from the
root package, `watershed_lustre/`, `examples/`, and `tools/`. Leave build watch
paths unrestricted so changes outside `website/` also trigger a build.

Wrangler reads `wrangler.json` and uploads `dist/`. The empty `previews` block
enables Worker Previews; `pnpm deploy:preview` uploads the current branch's
assets without changing the production deployment. Cloudflare manages
deployment authentication for its Git-connected builds; don't add credentials
to the repository.

For a manual production deploy:

```sh
pnpm exec wrangler login
pnpm build:cloudflare
pnpm deploy
```

## Move the live domain from Netlify

The initial configuration deploys to `workers.dev` and does not change DNS.
Keep Netlify serving the live domain until you have checked the Worker.

1. Confirm that `tylerbutler.com` is an active zone in the Cloudflare account.
2. Check the new `workers.dev` site: the home page, guide, live demos, assets,
   and a missing URL. Check that the four retired guide URLs redirect.
3. Record the existing DNS record for `watershed.tylerbutler.com`. Remove its
   Netlify CNAME, then open the Worker's **Settings > Domains & Routes > Add >
   Custom Domain** and add `watershed.tylerbutler.com`. Cloudflare creates the
   DNS record and certificate; an existing CNAME prevents this step.
4. Before the next production deploy, add this top-level field to
   `wrangler.json` and commit it so later deployments retain the domain:

   ```json
   "routes": [
     { "pattern": "watershed.tylerbutler.com", "custom_domain": true }
   ]
   ```

5. Check HTTPS and the live demos on the custom domain, then disable Netlify's
   automatic builds. Keep the Netlify site during the rollback window.

To roll back, remove the Worker's custom domain and restore the recorded
Netlify DNS record. Remove the Wrangler `routes` entry before another Workers
deploy and re-enable Netlify builds if needed.

`public/_redirects` provides permanent HTTP redirects for the four retired
guide URLs. Keep it aligned with Astro's `redirects`, which also preserves
those links during Astro preview. Workers serves directory index pages
without trailing slashes and returns 404 for missing paths, rather than
falling back to the home page.

See Cloudflare's [build settings], [build image], and [custom domains] docs.

[build settings]: https://developers.cloudflare.com/workers/ci-cd/builds/configuration/
[build image]: https://developers.cloudflare.com/workers/ci-cd/builds/build-image/
[custom domains]: https://developers.cloudflare.com/workers/configuration/routing/custom-domains/
