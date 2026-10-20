import { execFileSync } from "node:child_process";
import { copyFile, mkdir } from "node:fs/promises";
import { build } from "esbuild";

execFileSync("gleam", ["build", "--target", "javascript"], { stdio: "inherit" });
await mkdir("dist", { recursive: true });
await build({
  entryPoints: ["build/dev/javascript/incident_eval/incident_eval/shell.mjs"],
  bundle: true,
  format: "esm",
  outfile: "dist/app.js",
});
await copyFile("index.html", "dist/index.html");
