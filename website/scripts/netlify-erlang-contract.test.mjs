// ──────────────────────────────────────────────────────────────────────────
// Netlify deploy contract — dependency-free, offline checks that the deploy
// configuration can actually run the source-snippet prebuild.
//
// The website prebuild runs `tools/source-snippets`, an Erlang-target Gleam
// CLI, via `pnpm generate:snippets`. Gleam compiles it to Erlang source and
// then shells out to `erlc` and `escript`. Netlify's Ubuntu build image
// installs `esl-erlang`, which supplies both, so nothing needs installing —
// but the chain from netlify.toml to that binary is four files long and every
// link is silent when it breaks.
//
// These tests pin the links that are checkable without a deploy:
//
//   1. netlify.toml points the build at website/ and at our own build script
//   2. the build script exists and is executable
//   3. the prebuild really does invoke the snippet generator
//   4. the generator really is an Erlang-target package (the reason for 5)
//   5. the build script checks escript and erlc before it reaches pnpm build
//   6. netlify.toml declares no build plugin this repository has not installed
//
// (6) is the one with teeth: a `[[plugins]]` entry naming a package that is
// neither vendored in-tree nor a declared dependency fails plugin resolution
// before the build command ever runs, and Netlify's log for that is easy to
// misread as a build failure.
//
// Run: node scripts/netlify-erlang-contract.test.mjs
// ──────────────────────────────────────────────────────────────────────────
import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, existsSync, accessSync, constants } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const websiteRoot = resolve(__dirname, "..");
const repoRoot = resolve(websiteRoot, "..");

const buildScriptPath = resolve(websiteRoot, "scripts", "netlify-build.sh");
const buildScript = readFileSync(buildScriptPath, "utf8");
const netlifyToml = readFileSync(resolve(repoRoot, "netlify.toml"), "utf8");
const websitePackage = JSON.parse(
  readFileSync(resolve(websiteRoot, "package.json"), "utf8"),
);

// ── Minimal TOML reader ────────────────────────────────────────────────────
// Enough of TOML for this file's shape: `[table]` headers, `[[array]]`
// headers, and `key = "string"` pairs. A real parser would be a dependency,
// and netlify.toml is ours to keep simple.
function parseToml(source) {
  const tables = new Map();
  const arrays = new Map();
  let current = {};
  tables.set("", current);

  for (const rawLine of source.split("\n")) {
    const line = rawLine.replace(/(^|\s)#.*$/, "").trim();
    if (!line) continue;

    const arrayHeader = line.match(/^\[\[([^\]]+)\]\]$/);
    if (arrayHeader) {
      const name = arrayHeader[1].trim();
      current = {};
      if (!arrays.has(name)) arrays.set(name, []);
      arrays.get(name).push(current);
      continue;
    }

    const tableHeader = line.match(/^\[([^\]]+)\]$/);
    if (tableHeader) {
      const name = tableHeader[1].trim();
      current = {};
      tables.set(name, current);
      continue;
    }

    const pair = line.match(/^([A-Za-z0-9_.-]+)\s*=\s*"([^"]*)"$/);
    if (pair) current[pair[1]] = pair[2];
  }

  return { tables, arrays };
}

const toml = parseToml(netlifyToml);
const buildTable = toml.tables.get("build") ?? {};
const plugins = toml.arrays.get("plugins") ?? [];

describe("Netlify deploy contract", () => {
  // ── netlify.toml ────────────────────────────────────────────────────────

  it("builds from website/ and publishes website/dist", () => {
    assert.equal(
      buildTable.base,
      "website",
      "netlify.toml [build].base must be website/, the package that owns the site",
    );
    assert.equal(
      buildTable.publish,
      "dist",
      "netlify.toml [build].publish is relative to base and must be dist/, Astro's output",
    );
  });

  it("runs the repository's own build script as the build command", () => {
    assert.equal(
      buildTable.command,
      "./scripts/netlify-build.sh",
      "netlify.toml [build].command must be the checked-in script, resolved against base",
    );
    assert.ok(
      existsSync(buildScriptPath),
      `the build command must exist on disk: ${buildScriptPath}`,
    );
    assert.doesNotThrow(
      () => accessSync(buildScriptPath, constants.X_OK),
      "the build command must be executable; Netlify runs it directly",
    );
  });

  it("declares no build plugin the repository has not installed", () => {
    const declared = new Set([
      ...Object.keys(websitePackage.dependencies ?? {}),
      ...Object.keys(websitePackage.devDependencies ?? {}),
    ]);

    for (const plugin of plugins) {
      const pkg = plugin.package;
      assert.ok(pkg, `every [[plugins]] entry must name a package: ${JSON.stringify(plugin)}`);

      if (pkg.startsWith(".") || pkg.startsWith("/")) {
        assert.ok(
          existsSync(resolve(repoRoot, pkg)),
          `local plugin "${pkg}" does not exist; Netlify resolves plugins before the build command runs`,
        );
        continue;
      }

      assert.ok(
        declared.has(pkg),
        `plugin "${pkg}" is not a dependency of website/package.json. Netlify installs registry ` +
          `plugins during plugin resolution, which happens before the build command; an unresolvable ` +
          `name fails the deploy with no build output at all.`,
      );
    }
  });

  // ── The reason the Erlang toolchain is needed ──────────────────────────

  it("the website prebuild invokes the snippet generator", () => {
    const prebuild = websitePackage.scripts?.prebuild ?? "";
    assert.match(
      prebuild,
      /generate:snippets/,
      "the prebuild hook must generate the snippet manifest; without it the build reads a stale or absent file",
    );

    const generate = websitePackage.scripts?.["generate:snippets"] ?? "";
    assert.match(
      generate,
      /tools\/source-snippets/,
      "generate:snippets must run the tools/source-snippets CLI",
    );
  });

  it("the snippet generator is an Erlang-target Gleam package", () => {
    const gleamToml = readFileSync(
      resolve(repoRoot, "tools/source-snippets/gleam.toml"),
      "utf8",
    );
    assert.match(
      gleamToml,
      /^\s*target\s*=\s*"erlang"\s*$/m,
      "tools/source-snippets must target Erlang — that target is why the deploy needs escript and erlc. " +
        "If it ever moves to JavaScript, the toolchain check in netlify-build.sh becomes dead weight.",
    );
  });

  // ── netlify-build.sh ──────────────────────────────────────────────────

  it("the build script checks escript and erlc before running pnpm build", () => {
    // The header comment mentions `pnpm build` too, so match the invocation:
    // an unindented line that is nothing but the command.
    const invocation = buildScript.match(/^pnpm build\b.*$/m);
    assert.ok(invocation, "netlify-build.sh must run pnpm build");
    const buildIndex = invocation.index;

    const checkIndex = buildScript.indexOf("for cmd in");
    assert.notEqual(
      checkIndex,
      -1,
      "netlify-build.sh must check the Erlang toolchain in a loop before building",
    );
    assert.ok(
      checkIndex < buildIndex,
      "the toolchain check must come before pnpm build, not after it",
    );

    const check = buildScript.slice(checkIndex, buildIndex);
    const loop = check.match(/for cmd in ([^;]+); do/);
    assert.ok(loop, "the toolchain check must be a `for cmd in ...; do` loop over the required binaries");
    const probed = loop[1].trim().split(/\s+/);
    for (const cmd of ["escript", "erlc"]) {
      assert.ok(
        probed.includes(cmd),
        `netlify-build.sh must probe ${cmd} before it reaches pnpm build; it probes ${JSON.stringify(probed)}`,
      );
    }

    assert.match(
      check,
      /command -v "\$cmd"/,
      "the toolchain check must probe PATH with command -v, not assume a fixed install path",
    );
    assert.match(
      check,
      /exit 1/,
      "a missing toolchain must fail the deploy, not warn and continue",
    );
  });

  it("the build script's failure message names the build image, not a plugin", () => {
    const failureBlock = buildScript.slice(
      buildScript.indexOf("ERROR: missing Erlang toolchain"),
      buildScript.indexOf("exit 1"),
    );
    assert.match(
      failureBlock,
      /build image/i,
      "the diagnostic must point at the Netlify build image, which is where Erlang comes from",
    );
    assert.doesNotMatch(
      buildScript,
      /Aptfile|netlify-plugin-apt/,
      "no plugin reads an Aptfile in this configuration; naming one sends the reader down a dead end",
    );
  });

  it("no Aptfile implies an install step that nothing performs", () => {
    assert.ok(
      !existsSync(resolve(websiteRoot, "Aptfile")),
      "website/Aptfile is inert: Netlify's build image reads no Aptfile and no plugin is configured to. " +
        "An Aptfile here would read as a working install step and hide a real missing dependency.",
    );
  });
});
