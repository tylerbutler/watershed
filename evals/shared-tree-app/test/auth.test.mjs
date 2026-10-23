import assert from "node:assert/strict";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { copilotWireApi, resolveAuthentication, trialEnvironment } from "../lib/auth.mjs";

test("Copilot authentication takes the SDK token precedence but removes ambient account auth from Vally", async () => {
  const env = {
    COPILOT_GITHUB_TOKEN: "copilot-account-canary", GH_TOKEN: "gh-account-canary",
    GITHUB_TOKEN: "github-account-canary", GITHUB_COPILOT_API_TOKEN: "api-token-canary",
    COPILOT_API_URL: "https://unselected.example", COPILOT_PROVIDER_API_KEY: "byok-canary",
    SHARED_TREE_PROVIDER_API_KEY: "unused-provider-canary", PATH: "/bin",
  };
  const auth = await resolveAuthentication({ auth: "copilot", env });
  assert.equal(auth.upstream, "https://api.githubcopilot.com/");
  assert.equal(auth.apiKey, "copilot-account-canary");
  const effective = trialEnvironment(env, auth, "selected-model");
  for (const name of ["COPILOT_GITHUB_TOKEN", "GH_TOKEN", "GITHUB_TOKEN", "GITHUB_COPILOT_API_TOKEN",
    "COPILOT_API_URL", "COPILOT_PROVIDER_API_KEY"]) assert.equal(effective[name], undefined, name);
  assert.equal(effective.SHARED_TREE_PROVIDER_API_KEY, "copilot-account-canary");
  assert.equal(effective.SHARED_TREE_PROVIDER_MODEL, "selected-model");
  assert.equal(effective.PATH, "/bin");
  assert.equal((await resolveAuthentication({ auth: "copilot", env: { GH_TOKEN: "gh-canary" } })).apiKey, "gh-canary");
});

test("Copilot authentication captures gh credentials without placing the token in command arguments", async () => {
  const root = await mkdtemp(join(tmpdir(), "copilot-auth-"));
  try {
    await writeFile(join(root, "gh"), `#!${process.execPath}
import assert from "node:assert/strict";
assert.deepEqual(process.argv.slice(2), ["auth", "token", "--hostname", "github.com"]);
console.log("gho_fixture_account_canary");
`, { mode: 0o700 });
    const result = await resolveAuthentication({ auth: "copilot", env: { PATH: root } });
    assert.equal(result.apiKey, "gho_fixture_account_canary");
    await writeFile(join(root, "gh"), `#!${process.execPath}
console.error("sensitive-failure-canary");
process.exit(1);
`, { mode: 0o700 });
    await assert.rejects(resolveAuthentication({ auth: "copilot", env: { PATH: root } }), error => {
      assert.match(error.message, /Copilot|gh auth/i);
      assert.equal(error.message.includes("sensitive-failure-canary"), false);
      return true;
    });
  } finally { await rm(root, { recursive: true, force: true }); }
});

test("authentication rejects unsupported modes and malformed tokens without falling back", async () => {
  await assert.rejects(resolveAuthentication({ auth: "automatic", env: {} }), /auth/i);
  for (const token of ["bad\nvalue", "whitespace value", "ghp_classic_pat"]) {
    await assert.rejects(resolveAuthentication({ auth: "copilot", env: { COPILOT_GITHUB_TOKEN: token } }), /token|credential/i);
  }
  const provider = await resolveAuthentication({ env: {
    SHARED_TREE_PROVIDER_URL: "https://provider.example/v1", SHARED_TREE_PROVIDER_API_KEY: "provider-canary",
  } });
  assert.equal(provider.mode, "provider");
  assert.equal(provider.upstream, "https://provider.example/v1");
  await assert.rejects(resolveAuthentication({ env: {
    SHARED_TREE_PROVIDER_URL: "https://provider.example/v1",
  } }), /environment API key/);
});

test("Copilot discovery selects only an entitled text protocol for the exact operator model", async t => {
  let catalog;
  let status = 200;
  t.mock.method(globalThis, "fetch", async (url, options) => {
    assert.equal(url, "https://api.githubcopilot.com/models");
    assert.equal(options.headers.authorization, "Bearer account-canary");
    assert.equal(options.redirect, "manual");
    return new Response(JSON.stringify(catalog), { status });
  });
  const auth = { mode: "copilot", upstream: "https://api.githubcopilot.com/", apiKey: "account-canary" };
  for (const [endpoints, expected] of [
    [["/chat/completions"], "completions"], [["/responses"], "responses"], [["/v1/messages"], "messages"],
  ]) {
    catalog = { data: [{ id: "chosen", supported_endpoints: endpoints, policy: { state: "enabled" } }] };
    assert.equal(await copilotWireApi(auth, "chosen"), expected);
  }
  for (const data of [
    [{ id: "other", supported_endpoints: ["/responses"] }],
    [{ id: "chosen", supported_endpoints: ["/images/generations"] }],
    [{ id: "chosen", supported_endpoints: ["/responses"], policy: { state: "disabled" } }],
    [{ id: "chosen", supported_endpoints: ["/responses"], policy: { state: "unconfigured" } }],
  ]) {
    catalog = { data };
    await assert.rejects(copilotWireApi(auth, "chosen"), /model|protocol/i);
  }
  status = 401;
  catalog = { error: "account-canary" };
  await assert.rejects(copilotWireApi(auth, "chosen"), error => {
    assert.match(error.message, /401/);
    assert.equal(error.message.includes("account-canary"), false);
    return true;
  });
});
