import { build } from "esbuild";

await build({
  entryPoints: ["build/dev/javascript/bench_book_lustre/bench_book_lustre.mjs"],
  bundle: true,
  format: "esm",
  outfile: "dist/bench_book_lustre.mjs",
});
