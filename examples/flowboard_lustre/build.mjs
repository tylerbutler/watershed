import { build } from "esbuild";

await build({
  entryPoints: ["build/dev/javascript/flowboard_lustre/flowboard_lustre.mjs"],
  bundle: true,
  format: "esm",
  outfile: "dist/flowboard_lustre.mjs",
});
