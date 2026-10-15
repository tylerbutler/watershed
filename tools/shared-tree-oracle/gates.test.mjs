import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import {
  existsSync,
  readFileSync,
  unlinkSync,
  writeFileSync,
} from "node:fs";
import { resolve } from "node:path";
import test from "node:test";

const repository = resolve(import.meta.dirname, "../..");
const schemaEvolutionCaseIds = [
  "schema-evolution-compatibility",
  "schema-evolution-algebra",
  "schema-evolution-history",
  "schema-evolution-codecs",
];
const undoRedoCaseIds = [
  "revertible-lifetime",
  "undo-redo-kinds",
  "undo-redo-fields",
  "undo-redo-constraints",
  "undo-redo-reconnect",
];
const branchCaseIds = [
  "local-branch-isolation",
  "local-branch-rebase",
  "local-branch-merge",
  "local-branch-transactions",
  "local-branch-undo",
  "local-branch-allocation",
  "local-branch-retention",
  "local-branch-recovery",
];
const branchSupportedFeatures = [
  "runtime-local-checkouts",
  "local-fork-rebase-merge",
  "checkout-scoped-transactions-and-revertibles",
  "branch-and-revertible-history-retention",
  "local-branch-reconnect",
  "merged-branch-summary-continuation",
];
const branchExcludedFeatures = [
  "shared-branches",
  "persisted-branches",
  "branch-wire-apis",
  "branch-schema-authoring",
  "cross-runtime-or-tree-merge",
  "portable-branch-handles-and-revertibles",
  "historical-checkouts",
];
const lifecycleCaseIds = [
  "handle-leaves",
  "live-channel-attachment",
  "cross-datastore-attachment",
  "handle-transaction-branch",
  "handle-retention",
];
const lifecycleSections = [
  "handleValues",
  "channelAttachment",
  "datastoreAttachment",
  "handleTransactionBranch",
  "handleRetention",
  "handleReconnect",
  "handleReloadMatrix",
];

function recipeCommands(name) {
  const result = spawnSync("just", [
    "--color", "never", "--dry-run", name,
  ], { cwd: repository, encoding: "utf8" });
  assert.ifError(result.error);
  assert.equal(result.status, 0, result.stderr);
  return `${result.stdout}${result.stderr}`.trim().split(/\r?\n/);
}

function markdownSection(markdown, heading) {
  return markdown.split(`${heading}\n`)[1]?.split("\n### ", 1)[0];
}

function compileMarkdownSection(path, heading, fixture) {
  const markdown = readFileSync(resolve(repository, path), "utf8");
  const section = markdownSection(markdown, heading);
  assert(section, `${path} lacks the ${heading.slice(4)} section`);
  const blocks = [...section.matchAll(/```gleam\n([\s\S]*?)```/g)]
    .map((match) => match[1]);
  assert(blocks.length > 0, `${path} ${heading.slice(4)} has no Gleam examples`);

  const packageDirectory = resolve(repository, "tools/website-samples");
  const source = resolve(packageDirectory, "src", fixture);
  writeFileSync(source, blocks.join("\n"));
  try {
    const result = spawnSync("gleam", ["check", "--target", "javascript"], {
      cwd: packageDirectory,
      encoding: "utf8",
    });
    assert.ifError(result.error);
    assert.equal(result.status, 0, `${result.stdout}${result.stderr}`);
  } finally {
    unlinkSync(source);
  }
}

test("native gate selects both complete file suites and HTTP smokes", () => {
  assert.deepEqual(recipeCommands("shared-tree-test"), [
    "gleam test --target erlang -- shared_tree git_storage facade_parity",
    "gleam test --target javascript -- shared_tree git_storage facade_parity",
    "node smoke/shared_tree_storage.mjs",
    "node smoke/shared_tree_bootstrap.mjs",
    "node smoke/shared_tree_creation.mjs",
  ]);
});

test("acceptance delegates to the 300-schedule coordinator", () => {
  assert.deepEqual(recipeCommands("shared-tree-interop"), [
    "node smoke/shared_tree.mjs --profile test/fixtures/shared_tree/profile.json --iterations 300 --seed 42",
  ]);
});

test("lifecycle acceptance runs the complete owned-service profile", () => {
  assert.deepEqual(recipeCommands("shared-tree-lifecycle-interop"), [
    "node tools/shared-tree-oracle/lifecycle-interop.mjs --local-floodgate --iterations 300 --seed 42",
  ]);
});

test("compression acceptance runs both native targets, corpus check, and live gate", () => {
  assert.deepEqual(recipeCommands("shared-tree-compression-interop"), [
    "gleam test --target erlang -- shared_tree_compression shared_tree_runtime shared_tree_document_summary shared_tree_document_recovery",
    "gleam test --target javascript -- shared_tree_compression shared_tree_runtime shared_tree_document_summary shared_tree_document_recovery",
    "node tools/shared-tree-oracle/compression.mjs check",
    "node tools/shared-tree-oracle/compression-interop.mjs interop --local-floodgate",
  ]);
});

test("oracle compression script runs the owned live gate", () => {
  const packageJson = JSON.parse(readFileSync(
    resolve(repository, "tools/shared-tree-oracle/package.json"),
    "utf8",
  ));
  assert.equal(
    packageJson.scripts["compression:interop"],
    "node compression-interop.mjs interop --local-floodgate",
  );
});

test("layout acceptance checks native creation before the owned-service matrix", () => {
  assert.deepEqual(recipeCommands("shared-tree-layout-interop"), [
    "gleam test --target erlang -- shared_tree_creation git_storage facade_parity",
    "gleam test --target javascript -- shared_tree_creation git_storage facade_parity",
    "node smoke/shared_tree_creation.mjs",
    "node tools/shared-tree-oracle/layout-interop.mjs",
  ]);
});

test("committed corpus gates source and both native schema evolution coverage", () => {
  const manifest = JSON.parse(readFileSync(
    resolve(repository, "test/fixtures/shared_tree/manifest.json"),
    "utf8",
  ));
  const sourceCases = new Set(manifest.cases.map(({ id }) => id));
  for (const id of schemaEvolutionCaseIds) {
    assert(sourceCases.has(id), `Source corpus lacks ${id}`);
    for (const target of ["javascript", "erlang"]) {
      assert(manifest.nativeSemanticRunners[target].includes(id),
        `${target} native coverage lacks ${id}`);
    }
  }
});

test("committed corpus gates the complete undo and redo contract", () => {
  const manifest = JSON.parse(readFileSync(
    resolve(repository, "test/fixtures/shared_tree/manifest.json"),
    "utf8",
  ));
  const sourceCases = new Set(manifest.cases.map(({ id }) => id));
  for (const id of undoRedoCaseIds) {
    assert(sourceCases.has(id), `Source corpus lacks ${id}`);
  }
  assert.deepEqual(manifest.inventory.undoRedoContract.supportedFeatures, [
    "application-owned-revertibles",
    "default-undo-redo-commit-kinds",
    "runtime-local-handle-lifetime",
    "reconnect-with-live-handles",
    "object-map-array-move-transaction-undo-redo",
    "sequenced-commit-outcomes",
  ]);
});

test("committed profile and corpus publish the complete local branch contract", () => {
  const profile = JSON.parse(readFileSync(
    resolve(repository, "test/fixtures/shared_tree/profile.json"),
    "utf8",
  ));
  const manifest = JSON.parse(readFileSync(
    resolve(repository, "test/fixtures/shared_tree/manifest.json"),
    "utf8",
  ));
  assert.deepEqual(
    profile.supportedFeatures.filter((feature) =>
      branchSupportedFeatures.includes(feature)),
    branchSupportedFeatures,
  );
  assert.deepEqual(
    profile.excludedFeatures.filter((feature) =>
      branchExcludedFeatures.includes(feature)),
    branchExcludedFeatures,
  );
  assert.deepEqual(manifest.inventory.branchContract, {
    cases: branchCaseIds,
    supportedFeatures: branchSupportedFeatures,
    excludedFeatures: branchExcludedFeatures,
    serviceReport: {
      requiredSections: [
        "localBranchIsolation",
        "localBranchConcurrent",
        "localBranchLifetime",
        "localBranchReconnect",
        "localBranchReloadMatrix",
      ],
      nativeTargets: ["javascript", "erlang"],
      seed: 42,
      iterations: 300,
    },
  });

  const sourceCases = new Set(manifest.cases.map(({ id }) => id));
  for (const id of branchCaseIds) {
    assert(sourceCases.has(id), `Source corpus lacks ${id}`);
    for (const target of ["javascript", "erlang"]) {
      assert(manifest.nativeSemanticRunners[target].includes(id),
        `${target} native coverage lacks ${id}`);
    }
  }
});

test("committed profile and corpus publish the complete lifecycle contract", () => {
  const profile = JSON.parse(readFileSync(
    resolve(repository, "test/fixtures/shared_tree/profile.json"),
    "utf8",
  ));
  const manifest = JSON.parse(readFileSync(
    resolve(repository, "test/fixtures/shared_tree/manifest.json"),
    "utf8",
  ));
  assert.deepEqual(profile.lifecycle, {
    nativeTargets: ["javascript", "erlang"],
    seed: 42,
    iterations: 300,
    reloadCells: 27,
    targetKinds: ["SharedMap", "SharedTree"],
    datastoreType: "org.watershed.shared-tree.m7.graph",
    cases: lifecycleCaseIds,
    requiredSections: lifecycleSections,
  });
  assert.deepEqual(manifest.inventory.lifecycleContract, profile.lifecycle);
  const sourceCases = new Set(manifest.cases.map(({ id }) => id));
  for (const id of lifecycleCaseIds) {
    assert(sourceCases.has(id), `Source corpus lacks ${id}`);
    for (const target of profile.lifecycle.nativeTargets) {
      assert(manifest.nativeSemanticRunners[target].includes(id),
        `${target} native coverage lacks ${id}`);
    }
  }
});

test("deep acceptance uses the same coordinator with 7500 schedules", () => {
  assert.deepEqual(recipeCommands("shared-tree-interop-deep"), [
    "node smoke/shared_tree.mjs --profile test/fixtures/shared_tree/profile.json --iterations 7500 --seed 42",
  ]);
});

test("creation acceptance retains native checks and pinned-service proof", () => {
  assert.deepEqual(recipeCommands("shared-tree-create-interop"), [
    "gleam test --target erlang -- shared_tree_creation git_storage facade_parity",
    "gleam test --target javascript -- shared_tree_creation git_storage facade_parity",
    "node smoke/shared_tree_creation.mjs",
    "node tools/shared-tree-oracle/creation.mjs interop --local-floodgate",
  ]);
});

test("hosted erlang gates install the configured rebar tool", () => {
  const mise = readFileSync(resolve(repository, "mise.toml"), "utf8");
  const nativeWorkflow = readFileSync(
    resolve(repository, ".github/workflows/shared-tree.yml"),
    "utf8",
  );
  const interopWorkflowPath = resolve(
    repository,
    ".github/workflows/shared-tree-interop.yml",
  );

  assert.match(mise, /^rebar = "3\.27\.1"$/m);
  assert.equal(
    [...nativeWorkflow.matchAll(/uses: jdx\/mise-action@v3/g)].length,
    1,
  );
  assert.doesNotMatch(nativeWorkflow, /^\s*install_args:/m);
  assert.doesNotMatch(nativeWorkflow, /run: just shared-tree-interop/);
  assert.doesNotMatch(nativeWorkflow, /run: just shared-tree-create-interop/);
  const nativeBuild = nativeWorkflow.indexOf("run: just shared-tree-test");
  const nativeValidators = nativeWorkflow.indexOf(
    "run: node --test tools/shared-tree-oracle/source.test.mjs tools/shared-tree-oracle/generate.test.mjs tools/shared-tree-oracle/gates.test.mjs",
  );
  assert(nativeBuild > nativeWorkflow.indexOf("run: npm --prefix tools/shared-tree-oracle run source:prepare"));
  assert(nativeValidators > nativeBuild);
  assert.doesNotMatch(nativeWorkflow, /npm --prefix tools\/shared-tree-oracle test/);
  assert.equal(existsSync(interopWorkflowPath), true);

  const interopWorkflow = readFileSync(interopWorkflowPath, "utf8");
  assert.match(interopWorkflow, /^on:\n  workflow_dispatch:\n/m);
  assert.doesNotMatch(interopWorkflow, /^\s{2}(?:pull_request|push):/m);
  assert.match(interopWorkflow, /uses: jdx\/mise-action@v3/);
  assert.doesNotMatch(interopWorkflow, /^\s*install_args:/m);
  assert.match(interopWorkflow, /run: just shared-tree-interop/);
  assert.match(interopWorkflow, /run: just shared-tree-create-interop/);
  assert.match(interopWorkflow, /run: just shared-tree-lifecycle-interop/);
  assert.match(interopWorkflow, /run: just shared-tree-compression-interop/);
  const sourcePrepare = interopWorkflow.indexOf(
    "run: npm --prefix tools/shared-tree-oracle run source:prepare",
  );
  const sourceVerify = interopWorkflow.indexOf(
    "run: npm --prefix tools/shared-tree-oracle run source:verify",
  );
  const nativeAcceptance = interopWorkflow.indexOf("run: just shared-tree-test");
  const sourceCapture = interopWorkflow.indexOf(
    "run: npm --prefix tools/shared-tree-oracle run source:capture",
  );
  const allNode = interopWorkflow.indexOf(
    "run: npm --prefix tools/shared-tree-oracle test",
  );
  assert(sourcePrepare > 0 && sourceVerify > sourcePrepare);
  assert(nativeAcceptance > sourceVerify);
  assert(sourceCapture > nativeAcceptance);
  assert(allNode > sourceCapture);
  assert.match(
    readFileSync(resolve(repository, "tools/shared-tree-oracle/package.json"), "utf8"),
    /"test": "node --test --test-concurrency=1 \*\.test\.mjs"/,
  );
  assert.match(interopWorkflow, /uses: actions\/upload-artifact@v4/);
  assert.match(interopWorkflow, /tools\/shared-tree-oracle\/\.output\/lifecycle\//);
  assert.match(interopWorkflow, /tools\/shared-tree-oracle\/\.output\/compression\//);
});

test("BEAM reconnect command restarts the native transport", () => {
  const client = readFileSync(
    resolve(repository, "test/watershed/tree/client_beam.gleam"),
    "utf8",
  );

  assert.match(
    client,
    /protocol\.Reconnect -> \{\s+watershed\.force_reconnect\(document\)/,
  );
});

test("README local branch examples compile against the public Gleam API", () => {
  compileMarkdownSection(
    "README.md",
    "### SharedTree local branches",
    "readme_local_branch_examples.gleam",
  );
});

test("README typed SharedTree examples compile against the public Gleam API", () => {
  compileMarkdownSection(
    "README.md",
    "### Typed SharedTree application API",
    "readme_typed_shared_tree_examples.gleam",
  );
});

test("README initial layout example compiles against the public Gleam API", () => {
  compileMarkdownSection(
    "README.md",
    "### Declare an initial container layout",
    "readme_initial_layout_example.gleam",
  );
});

test("watershed_lustre SharedTree examples compile against its public API", () => {
  compileMarkdownSection(
    "watershed_lustre/README.md",
    "### SharedTree effects",
    "readme_lustre_shared_tree_examples.gleam",
  );
});

test("application facades expose one typed SharedTree surface", () => {
  for (const path of ["src/watershed.gleam", "src/watershed_beam.gleam"]) {
    const source = readFileSync(resolve(repository, path), "utf8");
    assert.match(source, /pub opaque type SharedTree\(schema, record\)/);
    assert.match(
      source,
      /pub fn tree_get\(\s*node: TreeNode\(s, r\),\s*field: typed\.Field\(s, a, typed\.Required\),/s,
    );
    assert.match(
      source,
      /pub fn tree_set\(\s*node: TreeNode\(s, r\),\s*field: typed\.Field\(s, a, c\),\s*value: a,/s,
    );
    assert.doesNotMatch(source, /pub (?:opaque )?type TypedTree\b/);
    assert.doesNotMatch(source, /pub fn tree_typed_/);
    assert.doesNotMatch(
      source,
      /pub fn tree_(?:get|set|clear)\(\s*tree: SharedTree[^,]*,\s*path: tree_types\.FieldPath/s,
    );
  }
});
