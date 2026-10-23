import assert from "node:assert/strict";
import { mkdtemp, readFile, realpath, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { parse } from "yaml";
import { offlineSetupCommands, writeRoleCompose } from "../lib/isolation.mjs";

const images = {
  sdk: "watershed",
  task: { id: `sha256:${"1".repeat(64)}` },
  grade: { id: `sha256:${"2".repeat(64)}` },
};

test("Compose keeps credentials and outbound networking in the gateway, and output mounts in grading", async () => {
  const root = await mkdtemp(join(tmpdir(), "role-compose-"));
  try {
    const out = join(root, "compose.yaml");
    await writeRoleCompose({
      sdk: "watershed", images, serviceImage: `sha256:${"3".repeat(64)}`,
      gradingOutput: join(root, "reports"), out, runId: "owned-trial",
    });
    const { services, networks } = parse(await readFile(out, "utf8"));
    assert.equal(networks.default.internal, true);
    for (const service of Object.values(services)) {
      assert.equal(service.labels["com.watershed.shared-tree-eval.run"], "owned-trial");
    }
    for (const network of Object.values(networks)) {
      assert.equal(network.labels["com.watershed.shared-tree-eval.run"], "owned-trial");
    }
    for (const role of ["task", "grade"]) {
      assert.deepEqual(services[role].networks, ["default"]);
      assert.equal(services[role].environment.SHARED_TREE_PROVIDER_API_KEY, undefined);
    }
    assert.equal(services.task.volumes, undefined);
    assert.deepEqual(services.grade.volumes, [
      { type: "bind", source: await realpath(join(root, "reports")), target: "/eval-results" },
    ]);
    assert.deepEqual(services["provider-gateway"].networks, ["default", "provider-outbound"]);
    assert.deepEqual(services["provider-gateway"].profiles, ["vally-task"]);
    assert.deepEqual(services["sdk-service"].profiles, ["vally-task", "vally-grade"]);
  } finally { await rm(root, { recursive: true, force: true }); }
});

test("Compose rejects mutable images and existing grading outputs before replacing evidence", async () => {
  const root = await mkdtemp(join(tmpdir(), "role-compose-invalid-"));
  try {
    const options = { sdk: "watershed", images, serviceImage: "floodgate:latest",
      gradingOutput: join(root, "reports"), out: join(root, "compose.yaml") };
    await assert.rejects(writeRoleCompose(options), /immutable/);
    await writeFile(options.gradingOutput, "previous evidence");
    await assert.rejects(writeRoleCompose({ ...options, serviceImage: `sha256:${"3".repeat(64)}` }),
      { code: "EEXIST" });
    assert.equal(await readFile(options.gradingOutput, "utf8"), "previous evidence");
    assert.throws(() => offlineSetupCommands("other"), /SDK/);
  } finally { await rm(root, { recursive: true, force: true }); }
});

test("Copilot Compose confines the account credential to the outbound gateway", async () => {
  const root = await mkdtemp(join(tmpdir(), "copilot-compose-"));
  try {
    const out = join(root, "compose.yaml");
    await writeRoleCompose({
      sdk: "watershed", images, serviceImage: `sha256:${"3".repeat(64)}`,
      gradingOutput: join(root, "reports"), out, auth: "copilot",
    });
    const { services, networks } = parse(await readFile(out, "utf8"));
    assert.equal(services["provider-gateway"].environment.SHARED_TREE_AUTH_MODE, "copilot");
    assert.match(services["provider-gateway"].environment.SHARED_TREE_PROVIDER_API_KEY, /^\$\{/);
    for (const role of ["task", "grade", "sdk-service"]) {
      assert.equal(services[role].environment.SHARED_TREE_PROVIDER_API_KEY, undefined);
      assert.equal(services[role].environment.COPILOT_GITHUB_TOKEN, undefined);
      assert.deepEqual(services[role].networks, ["default"]);
    }
    assert.equal(services.task.volumes, undefined);
    assert.equal(networks.default.internal, true);
  } finally { await rm(root, { recursive: true, force: true }); }
});
