import { fileURLToPath } from "node:url";
import { defineConfig } from "astro/config";

export default defineConfig({
  site: "https://watershed.tylerbutler.com",
  // Preserve spaces around inline elements when prose wraps across source lines.
  compressHTML: true,
  // The six-step survey procedure replaced four older sheets. Their URLs are
  // linked from outside the site, so they keep resolving to whichever current
  // step inherited their work.
  redirects: {
    "/guide/schema": "/guide/notes",
    "/guide/structures": "/guide/notes",
    "/guide/ripples": "/guide/presence",
    "/guide/ui": "/guide/connect",
  },
  devToolbar: { enabled: false },
  vite: {
    resolve: {
      alias: {
        // The demos drive the real watershed runtime through the in-memory
        // `sluice`, which never uses the phoenix transport. `transport_ffi`
        // still references `phoenix` behind a guarded dynamic import, so alias
        // it to a stub to keep it out of the bundle. See phoenix-stub.mjs.
        phoenix: fileURLToPath(
          new URL("./src/scripts/phoenix-stub.mjs", import.meta.url),
        ),
      },
    },
    server: {
      fs: {
        // The live demo imports the gleam-compiled kernel from ../build.
        allow: [fileURLToPath(new URL("..", import.meta.url))],
      },
    },
  },
});
