import { build } from "esbuild";

await build({
  entryPoints: ["build/dev/javascript/retro_tutorial_lustre/retro_tutorial_lustre.mjs"],
  bundle: true,
  format: "esm",
  outfile: "dist/retro_tutorial_lustre.mjs",
});
