import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { randomUUID } from "node:crypto";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";
import test from "node:test";
import { buildImages } from "../../lib/images.mjs";
import { prepare } from "../../prepare.mjs";

const exec = promisify(execFile);
const benchmark = fileURLToPath(new URL("../../", import.meta.url));

test("task image hides host and grader inputs and blocks downloads while native service and offline builds work", async () => {
  await exec("podman", ["info"], { timeout: 30_000 });
  await mkdir(join(benchmark, ".work/build"), { recursive: true });
  const root = await mkdtemp(join(benchmark, ".work/build/isolation-"));
  const network = `shared-tree-isolation-${randomUUID().slice(0, 8)}`;
  const service = `${network}-service`;
  let networkCreated = false;
  let serviceCreated = false;
  try {
    const source = fileURLToPath(new URL("../../../../", import.meta.url));
    const revision = (await exec("git", ["rev-parse", "HEAD"], { cwd: source })).stdout.trim();
    const prepared = await prepare({ sdk: "watershed", source, revision, out: join(root, "prepared") });
    const images = await buildImages({ prepared, out: join(root, "images") });
    for (const role of ["task", "grade"]) {
      assert.match(images[role].id, /^sha256:[a-f0-9]{64}$/);
      assert.equal(images[role].coreVersion, "0.19.0");
    }
    const canary = join(root, "host-only-canary.txt");
    await writeFile(canary, randomUUID());
    await exec("podman", ["network", "create", "--internal", network]);
    networkCreated = true;
    await exec("podman", ["run", "-d", "--name", service, "--network", network,
      "--network-alias", "sdk-service", "-e", "FLOODGATE_BIND=0.0.0.0",
      "-e", "FLOODGATE_STORAGE_BACKEND=memory", "-e", "FLOODGATE_PUBLIC_URL=http://127.0.0.1:4173/api",
      "-e", "FLOODGATE_TENANT_ID=dev-tenant", "-e", "FLOODGATE_JWT_SECRET=levee-dev-secret-change-in-production",
      "floodgate:shared-tree-eval-21faeaa48671"]);
    serviceCreated = true;
    const script = `
import assert from "node:assert/strict";
import { access, cp, mkdir } from "node:fs/promises";
import { execFileSync } from "node:child_process";
import { createServer } from "node:http";
import { once } from "node:events";
assert.equal(process.getuid(), 1000);
for (const path of ${JSON.stringify([canary, "/opt/shared-tree/grading", "/workspace/fluid",
      "/opt/shared-tree/validation", "/var/run/docker.sock", "/run/podman/podman.sock"])}) {
  await assert.rejects(access(path), { code: "ENOENT" });
}
let ready = false;
for (let attempt = 0; attempt < 30; attempt++) {
  try { ready = (await fetch("http://sdk-service:3000/health")).ok; }
  catch (error) { if (attempt === 29) throw error; }
  if (ready) break;
  await new Promise(resolve => setTimeout(resolve, 1000));
}
assert.equal(ready, true);
assert.throws(() => execFileSync("curl", ["--fail", "--connect-timeout", "3",
  "--max-time", "5", "https://github.com"], { stdio: "pipe" }));
await mkdir("/tmp/submission");
await cp("/opt/shared-tree/baseline", "/tmp/submission",
  { recursive: true, verbatimSymlinks: true });
execFileSync("pnpm", ["check"], { cwd: "/tmp/submission", stdio: "pipe" });
execFileSync("pnpm", ["build"], { cwd: "/tmp/submission", stdio: "pipe" });
const { launchBrowser } = await import("/opt/shared-tree/lib/cdp.mjs");
const browser = await launchBrowser();
try {
  const context = await browser.context();
  const page = await context.page();
  await page.goto("http://sdk-service:3000/health");
  assert.deepEqual(page.errors(), []);
} finally { await browser.close(); }
const { startGateway } = await import("/opt/shared-tree/docker/gateway.mjs");
const { CopilotSdkExecutor } = await import("@microsoft/vally/executor");
let submissions = 0;
const provider = createServer(async (request, response) => {
  let body = "";
  for await (const chunk of request) body += chunk;
  const value = JSON.parse(body);
  submissions++;
  assert.equal(request.url, "/v1/chat/completions");
  assert.equal(request.headers.authorization, "Bearer harmless-upstream-fixture");
  const result = {
    id: "chatcmpl-fixture", object: "chat.completion", created: 1, model: "fixture-model",
    choices: [{ index: 0, message: { role: "assistant", content: "gateway-ready" }, finish_reason: "stop" }],
    usage: { prompt_tokens: 1, completion_tokens: 1, total_tokens: 2 },
  };
  if (value.stream) {
    response.writeHead(200, { "content-type": "text/event-stream" });
    response.write("data: " + JSON.stringify({ ...result, object: "chat.completion.chunk",
      choices: [{ index: 0, delta: { role: "assistant", content: "gateway-ready" }, finish_reason: null }] }) + "\\n\\n");
    response.end("data: " + JSON.stringify({ ...result, object: "chat.completion.chunk",
      choices: [{ index: 0, delta: {}, finish_reason: "stop" }] }) + "\\n\\ndata: [DONE]\\n\\n");
  } else response.writeHead(200, { "content-type": "application/json" }).end(JSON.stringify(result));
});
provider.listen(0, "127.0.0.1");
await once(provider, "listening");
const gateway = await startGateway({
  upstream: "http://127.0.0.1:" + provider.address().port + "/v1",
  apiKey: "harmless-upstream-fixture", model: "fixture-model", port: 0, host: "127.0.0.1",
});
const executor = new CopilotSdkExecutor();
process.env.SHARED_TREE_FIXTURE_CLIENT_KEY = "harmless-client-placeholder";
try {
  const trajectory = await executor.execute({ name: "gateway-fixture", prompt: "Reply gateway-ready" }, {
    workDir: "/tmp/submission", model: "fixture-model", timeout: 30_000, maxAgentDurationMs: 20_000,
    executorConfig: { provider: {
      type: "openai", baseUrl: gateway.origin + "/v1", wireApi: "completions", transport: "http",
      apiKeyEnv: "SHARED_TREE_FIXTURE_CLIENT_KEY", modelId: "fixture-model", wireModel: "fixture-model",
      maxPromptTokens: 131072, maxOutputTokens: 256,
    } },
  });
  assert.match(trajectory.output, /gateway-ready/);
  assert.ok(submissions > 0);
} finally {
  await executor.shutdown();
  await gateway.close();
  provider.closeAllConnections();
  await new Promise(resolve => provider.close(resolve));
}
console.log("ISOLATION_VERIFIED");
`;
    const result = await exec("podman", ["run", "--rm", "--network", network, "--cap-drop=ALL",
      "--security-opt=no-new-privileges", images.task.id, "node", "--input-type=module", "-e", script],
    { timeout: 180_000 });
    assert.match(result.stdout, /ISOLATION_VERIFIED/);
    assert.equal(JSON.parse(await readFile(join(root, "images/images.json"), "utf8")).task.id, images.task.id);
  } finally {
    try { if (serviceCreated) await exec("podman", ["rm", "-f", service]); }
    finally {
      try { if (networkCreated) await exec("podman", ["network", "rm", network]); }
      finally { await rm(root, { recursive: true, force: true }); }
    }
  }
});
