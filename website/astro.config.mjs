import { fileURLToPath } from "node:url";
import { defineConfig } from "astro/config";

export default defineConfig({
  site: "https://watershed.tylerbutler.com",
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
