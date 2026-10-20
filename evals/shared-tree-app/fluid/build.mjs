import { build } from "esbuild";
import { copyFile, mkdir } from "node:fs/promises";

await mkdir("dist", { recursive: true });
await build({
  entryPoints: ["src/index.tsx"],
  bundle: true,
  format: "esm",
  outfile: "dist/app.js",
  define: { "process.env.NODE_ENV": '"production"' },
});
await copyFile("index.html", "dist/index.html");
