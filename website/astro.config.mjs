import { fileURLToPath } from "node:url";
import { defineConfig } from "astro/config";

export default defineConfig({
  site: "https://watershed.tylerbutler.com",
  devToolbar: { enabled: false },
  vite: {
    server: {
      fs: {
        // The live demo imports the gleam-compiled kernel from ../build.
        allow: [fileURLToPath(new URL("..", import.meta.url))],
      },
    },
  },
});
