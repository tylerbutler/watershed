// ──────────────────────────────────────────────────────────────────────────
// Netlify deploy contract — dependency-free, offline checks that the deploy
// configuration can actually run the source-snippet prebuild.
//
// The deploy needs exactly two runtimes: Node, which Netlify's build image
// guarantees, and the Gleam compiler, which it does not ship and which
// netlify-build.sh installs. Nothing here needs the BEAM. That is the whole
// point of the JavaScript target: Netlify's image documents Erlang/OTP 22.2,
// gleam_json 3.1 needs OTP 27, and installing a second runtime to generate a
// JSON file for an Astro build would be the tail wagging the dog.
//
// The chain from netlify.toml to the generated manifest is four files long
// and every link is silent when it breaks. These tests pin the links that are
// checkable without a deploy:
//
//   1. netlify.toml points the build at website/ and at our own build script
//   2. the build script exists, is executable, and installs Gleam when absent
//   3. the generator defaults to the JavaScript target and compiles there
//   4. every canonical generator command runs on that default
//   5. the prebuild generates the manifest before Astro reads it
//   6. nothing in the deploy path asks for Erlang
//   7. netlify.toml declares no build plugin this repository has not installed
//
// (7) is the one with teeth: a `[[plugins]]` entry naming a package that is
// neither vendored in-tree nor a declared dependency fails plugin resolution
// before the build command ever runs, and Netlify's log for that is easy to
// misread as a build failure.
//
// Run: node scripts/netlify-deploy-contract.test.mjs
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
const justfile = readFileSync(resolve(repoRoot, "justfile"), "utf8");
const websitePackage = JSON.parse(
  readFileSync(resolve(websiteRoot, "package.json"), "utf8"),
);
const generatorToml = readFileSync(
  resolve(repoRoot, "tools/source-snippets/gleam.toml"),
  "utf8",
);
const generatorReadme = readFileSync(
  resolve(repoRoot, "tools/source-snippets/README.md"),
  "utf8",
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

// ── The canonical ways to run the generator ────────────────────────────────
// Three files spell out the same command, and a target flag added to one of
// them and not the others is a difference nobody sees until a deploy fails.
function justRecipe(name) {
  const match = justfile.match(
    new RegExp(`^${name}:.*\\n((?:[ \\t]+\\S.*\\n|\\n(?=[ \\t]+\\S))*)`, "m"),
  );
  assert.ok(match, `justfile must define a \`${name}\` recipe`);
  return match[1];
}

function readmeJustBlock() {
  const blocks = generatorReadme.match(/```just\n([\s\S]*?)```/g) ?? [];
  const block = blocks.find((b) => b.includes("source_snippets/cli"));
  assert.ok(
    block,
    "tools/source-snippets/README.md must show a build-integration recipe that runs the CLI",
  );
  return block;
}

const canonicalCommands = [
  {
    where: "website/package.json scripts.generate:snippets",
    command: websitePackage.scripts?.["generate:snippets"] ?? "",
  },
  { where: "the justfile `snippets` recipe", command: justRecipe("snippets") },
  {
    where: "tools/source-snippets/README.md build integration",
    command: readmeJustBlock(),
  },
  {
    where: "tools/source-snippets/README.md command section",
    command: generatorReadme.match(/```\n(gleam run -m source_snippets\/cli[^`]*)```/)?.[1] ?? "",
  },
];

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

  // ── The generator's target ─────────────────────────────────────────────

  it("the snippet generator defaults to the JavaScript target", () => {
    assert.match(
      generatorToml,
      /^\s*target\s*=\s*"javascript"\s*$/m,
      "tools/source-snippets/gleam.toml must set target = \"javascript\". Netlify guarantees Node and " +
        "documents Erlang/OTP 22.2; gleam_json 3.1 needs OTP 27, so the BEAM is not an option here.",
    );
  });

  it("the generator's process exit works on the JavaScript target", () => {
    const system = readFileSync(
      resolve(repoRoot, "tools/source-snippets/src/source_snippets/system.gleam"),
      "utf8",
    );
    assert.match(
      system,
      /@external\(javascript,/,
      "source_snippets/system.gleam must provide a JavaScript external for halt/1. Without it the " +
        "package does not compile on its own default target and the deploy fails inside the prebuild.",
    );
  });

  it("every canonical generator command runs on the default target", () => {
    for (const { where, command } of canonicalCommands) {
      assert.match(
        command,
        /gleam run (?:--target javascript )?-m source_snippets\/cli/,
        `${where} must run the generator with \`gleam run -m source_snippets/cli\``,
      );
      assert.doesNotMatch(
        command,
        /--target[= ]erlang/,
        `${where} must not select the Erlang target; the deploy image has no usable BEAM`,
      );
    }
  });

  // ── The prebuild ───────────────────────────────────────────────────────

  it("the prebuild generates the manifest before Astro reads it", () => {
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

    assert.equal(
      websitePackage.scripts?.build,
      "astro build",
      "build must be plain `astro build`, so npm's prebuild hook is what orders generation before it",
    );

    const kernel = prebuild.indexOf("gleam build --target javascript");
    const snippets = prebuild.indexOf("generate:snippets");
    assert.notEqual(kernel, -1, "the prebuild must compile the Gleam kernel to JavaScript for the live demo");
    assert.ok(
      kernel < snippets,
      "compile the kernel before generating snippets; the generator scans sources, not build output, " +
        "but a failed compile should stop the deploy at the compiler, not at a manifest error",
    );
  });

  // ── No BEAM anywhere in the deploy path ────────────────────────────────

  it("the build script installs Gleam and checks nothing else", () => {
    assert.match(
      buildScript,
      /command -v gleam/,
      "netlify-build.sh must probe PATH for gleam rather than assume a fixed install path",
    );
    assert.match(
      buildScript,
      /releases\/download\/v\$\{GLEAM_VERSION\}/,
      "netlify-build.sh must install the pinned Gleam release when the image does not carry one",
    );

    const invocation = buildScript.match(/^pnpm build\b.*$/m);
    assert.ok(invocation, "netlify-build.sh must run pnpm build");
    assert.ok(
      buildScript.indexOf("command -v gleam") < invocation.index,
      "the Gleam install must come before pnpm build, not after it",
    );
  });

  it("nothing in the deploy path asks for Erlang", () => {
    const beam = /escript|erlc|esl-erlang|rebar3|\bOTP\b|\bBEAM\b/;
    for (const [name, source] of [
      ["website/scripts/netlify-build.sh", buildScript],
      ["netlify.toml", netlifyToml],
    ]) {
      assert.doesNotMatch(
        source,
        beam,
        `${name} must not reference the Erlang toolchain. The generator compiles to JavaScript and ` +
          `runs on the Node the build image already has; a leftover check or comment about the BEAM ` +
          `is a false trail for whoever debugs the next failed deploy.`,
      );
    }
  });

  it("no Aptfile implies an install step that nothing performs", () => {
    assert.ok(
      !existsSync(resolve(websiteRoot, "Aptfile")),
      "website/Aptfile is inert: Netlify's build image reads no Aptfile and no plugin is configured to. " +
        "An Aptfile here would read as a working install step and hide a real missing dependency.",
    );
  });
});
