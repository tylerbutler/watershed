import assert from "node:assert/strict";
import test from "node:test";

test("replaceDocument preserves configuration parameters", async () => {
  let replaced = null;
  Object.defineProperty(globalThis, "location", {
    configurable: true,
    value: {
      href: "http://localhost:8080/?tenant=t&secret=s&document=old",
    },
  });
  Object.defineProperty(globalThis, "history", {
    configurable: true,
    value: {
      replaceState(_state, _title, url) {
        replaced = String(url);
      },
    },
  });

  const browser = await import("../src/shared_tree_checklist_lustre_ffi.mjs");
  browser.replaceDocument("doc-1");

  const url = new URL(replaced);
  assert.equal(url.searchParams.get("document"), "doc-1");
  assert.equal(url.searchParams.get("tenant"), "t");
  assert.equal(url.searchParams.get("secret"), "s");
  assert.equal(browser.queryParameter("tenant", "fallback"), "t");
  assert.equal(browser.queryParameter("missing", "fallback"), "fallback");
  assert.equal(browser.currentOrigin(), "http://localhost:8080");

  let fetched = null;
  globalThis.fetch = async (input) => {
    fetched = String(input);
    return new Response(null, { status: 204 });
  };
  browser.proxyFloodgateHttp("http://127.0.0.1:4000");
  await fetch("http://127.0.0.1:4000/repos/t/git/commits/c?x=1");
  assert.equal(
    fetched,
    "http://localhost:8080/repos/t/git/commits/c?x=1",
  );
});
