// Offline deployment checks. Gleam compiles the runtime, samples, and snippet
// generator to JavaScript before Astro builds the assets served by Workers.
import { describe, it } from "node:test";
import assert from "node:assert/strict";
import {
  readFileSync,
  existsSync,
  accessSync,
  constants,
  mkdtempSync,
  mkdirSync,
  writeFileSync,
  rmSync,
} from "node:fs";
import { spawnSync } from "node:child_process";
import { tmpdir } from "node:os";
import { resolve, dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const websiteRoot = resolve(__dirname, "..");
const repoRoot = resolve(websiteRoot, "..");

const buildScriptPath = resolve(websiteRoot, "scripts", "cloudflare-build.sh");
const justfile = readFileSync(resolve(repoRoot, "justfile"), "utf8");
const testFiles = readFileSync(
  resolve(websiteRoot, "scripts", "test-files.mjs"),
  "utf8",
);
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

function readWebsiteFile(path) {
  const absolute = resolve(websiteRoot, path);
  assert.ok(existsSync(absolute), `deployment file is missing: ${path}`);
  return readFileSync(absolute, "utf8");
}

function runBuild(
  t,
  { installed = true, downloadFails = false, buildFails = false } = {},
) {
  assert.ok(existsSync(buildScriptPath), "Cloudflare build script is missing");
  const root = mkdtempSync(join(tmpdir(), "watershed-cloudflare-build-"));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const bin = join(root, "bin");
  mkdirSync(bin);
  const log = join(root, "commands.log");
  const command = (name, source) => {
    writeFileSync(join(bin, name), `#!/bin/bash\nset -eu\n${source}\n`, {
      mode: 0o755,
    });
  };
  const gleam = 'printf "gleam %s\\n" "$*" >> "$COMMAND_LOG"';
  command(
    "pnpm",
    `printf "pnpm %s\\n" "$*" >> "$COMMAND_LOG"\nexit ${buildFails ? 7 : 0}`,
  );
  if (installed) command("gleam", gleam);
  command("mkdir", '/bin/mkdir "$@"');
  command(
    "curl",
    `printf "curl %s\\n" "$*" >> "$COMMAND_LOG"\nexit ${downloadFails ? 22 : 0}`,
  );
  command(
    "tar",
    `while [ "$1" != "-C" ]; do shift; done\nshift\nprintf '%s\\n' '#!/bin/bash' '${gleam}' > "$1/gleam"\n/bin/chmod +x "$1/gleam"`,
  );

  const result = spawnSync("/bin/bash", [buildScriptPath], {
    cwd: websiteRoot,
    encoding: "utf8",
    env: {
      HOME: root,
      PATH: bin,
      COMMAND_LOG: log,
      GLEAM_VERSION: "1.18.1",
    },
  });
  assert.ifError(result.error);
  return { ...result, commands: readFileSync(log, "utf8") };
}

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

describe("Cloudflare deploy contract", () => {
  it("defines the website integration gates", () => {
    assert.equal(
      websitePackage.scripts?.["test:unit"],
      "node scripts/run-node-tests.mjs",
    );
    assert.equal(
      websitePackage.scripts?.["test:integration:node"],
      "pnpm test:unit",
    );
    assert.equal(
      websitePackage.scripts?.["test:integration:browser"],
      "node scripts/run-browser-tests.mjs",
    );
    assert.match(
      testFiles,
      /runtime-demos\.test\.mjs/,
    );
    assert.match(testFiles, /src\/data\/structures\.test\.ts/);
    assert.match(justfile, /pnpm test:unit/);
    assert.match(justfile, /pnpm test:integration:browser/);
  });

  it("serves Astro output as static assets without an SSR entry point", () => {
    const config = JSON.parse(readWebsiteFile("wrangler.json"));
    assert.equal(config.name, "watershed-website");
    assert.equal(config.workers_dev, true);
    assert.equal(config.main, undefined);
    assert.deepEqual(config.previews, {});
    assert.deepEqual(config.assets, {
      directory: "./dist",
      html_handling: "drop-trailing-slash",
      not_found_handling: "404-page",
    });
    assert.match(config.compatibility_date, /^\d{4}-\d{2}-\d{2}$/);
  });

  it("exposes build, deploy, preview deployment, and local Workers commands", () => {
    assert.equal(
      websitePackage.scripts["build:cloudflare"],
      "./scripts/cloudflare-build.sh",
    );
    assert.equal(websitePackage.scripts.deploy, "wrangler deploy");
    assert.equal(websitePackage.scripts["deploy:preview"], "wrangler preview");
    assert.equal(websitePackage.scripts["preview:worker"], "wrangler dev");
    assert.ok(websitePackage.devDependencies.wrangler);
    assert.equal(readWebsiteFile(".node-version").trim(), "24");
    assert.doesNotThrow(
      () => accessSync(buildScriptPath, constants.X_OK),
      "Cloudflare must be able to execute the build command",
    );
  });

  it("redirects the four retired guide URLs at the asset boundary", () => {
    const redirects = readWebsiteFile("public/_redirects")
      .trim()
      .split("\n")
      .map((line) => line.trim().split(/\s+/));
    assert.deepEqual(redirects, [
      ["/guide/schema", "/guide/notes", "301"],
      ["/guide/structures", "/guide/notes", "301"],
      ["/guide/ripples", "/guide/presence", "301"],
      ["/guide/ui", "/guide/connect", "301"],
    ]);
  });

  // ── The generator's target ─────────────────────────────────────────────

  it("the snippet generator defaults to the JavaScript target", () => {
    assert.match(
      generatorToml,
      /^\s*target\s*=\s*"javascript"\s*$/m,
      "tools/source-snippets/gleam.toml must set target = \"javascript\"; deployment needs only Node and Gleam.",
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
    const checkTypes = websitePackage.scripts?.["check:types"] ?? "";
    const buildSamples = websitePackage.scripts?.["build:samples"] ?? "";
    const buildGleam = websitePackage.scripts?.["build:gleam"] ?? "";
    const generate = websitePackage.scripts?.["generate:snippets"] ?? "";

    assert.match(
      prebuild,
      /check:types/,
      "the prebuild hook must run check:types before Astro reads generated modules",
    );
    assert.doesNotMatch(
      prebuild,
      /\btest(?::|\s|$)/,
      "the prebuild hook must leave tests to CI",
    );

    assert.match(
      checkTypes,
      /build:samples/,
      "check:types must compile the source-backed Gleam samples",
    );
    assert.match(
      checkTypes,
      /build:gleam/,
      "check:types must compile the Gleam modules and declarations",
    );
    assert.match(
      checkTypes,
      /generate:snippets/,
      "check:types must generate the snippet manifest before TypeScript reads it",
    );
    assert.match(
      checkTypes,
      /astro sync/,
      "check:types must generate Astro's TypeScript declarations",
    );
    assert.match(
      checkTypes,
      /tsc --noEmit/,
      "check:types must run the TypeScript compiler",
    );
    assert.match(
      buildSamples,
      /cd \.\.\/tools\/website-samples && gleam build --target javascript/,
      "build:samples must compile the source-backed Gleam samples for JavaScript",
    );
    assert.match(
      buildGleam,
      /cd \.\.\/tools\/website-runtime && gleam build --target javascript/,
      "build:gleam must compile the internal website runtime package",
    );
    assert.equal(
      buildGleam.match(/gleam build --target javascript/g)?.length,
      1,
      "build:gleam must create one generated Gleam module tree",
    );
    assert.doesNotMatch(
      buildGleam,
      /cd \.\. &&|cd watershed_lustre/,
      "build:gleam must not create separate root and Lustre runtime worlds",
    );
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

    const samples = checkTypes.indexOf("build:samples");
    const kernel = checkTypes.indexOf("build:gleam");
    const snippets = checkTypes.indexOf("generate:snippets");
    const astroTypes = checkTypes.indexOf("astro sync");
    const typescript = checkTypes.indexOf("tsc --noEmit");
    assert.ok(
      samples < snippets,
      "compile source-backed samples before generating their snippets",
    );
    assert.ok(
      kernel < snippets,
      "compile the kernel before generating snippets; the generator scans sources, not build output, " +
        "but a failed compile should stop the deploy at the compiler, not at a manifest error",
    );
    assert.ok(
      snippets < astroTypes && astroTypes < typescript,
      "generate snippets and Astro declarations before TypeScript resolves them",
    );
  });

  // ── No BEAM anywhere in the deploy path ────────────────────────────────

  it("uses an installed Gleam compiler before the normal website build", (t) => {
    const result = runBuild(t);
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.commands, "gleam --version\npnpm build\n");
  });

  it("installs Gleam when the build image does not provide it", (t) => {
    const result = runBuild(t, { installed: false });
    assert.equal(result.status, 0, result.stderr);
    assert.match(
      result.commands,
      /releases\/download\/v1\.18\.1\/gleam-v1\.18\.1-x86_64-unknown-linux-musl\.tar\.gz/,
    );
    assert.match(result.commands, /gleam --version\npnpm build\n$/);
  });

  it("stops before Astro when the compiler download fails", (t) => {
    const result = runBuild(t, { installed: false, downloadFails: true });
    assert.notEqual(result.status, 0);
    assert.doesNotMatch(result.commands, /pnpm build/);
  });

  it("propagates a failed website build", (t) => {
    const result = runBuild(t, { buildFails: true });
    assert.equal(result.status, 7);
  });

  it("nothing in the deploy path asks for Erlang", () => {
    const beam = /escript|erlc|esl-erlang|rebar3|\bOTP\b|\bBEAM\b/;
    for (const [name, source] of [
      [
        "website/scripts/cloudflare-build.sh",
        readWebsiteFile("scripts/cloudflare-build.sh"),
      ],
      ["website/wrangler.json", readWebsiteFile("wrangler.json")],
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
      "website/Aptfile is not consumed by the build; compiler installation belongs in cloudflare-build.sh.",
    );
  });
});
