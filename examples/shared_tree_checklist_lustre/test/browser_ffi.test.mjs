import assert from "node:assert/strict";
import test from "node:test";

test("replaceDocument preserves configuration parameters", async () => {
  let replaced = null;
  Object.defineProperty(globalThis, "location", {
    configurable: true,
    value: {
      href: "http://localhost:8080/?host=example.test&port=4100&tenant=t&secret=s&document=old",
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
  assert.equal(url.searchParams.get("host"), "example.test");
  assert.equal(url.searchParams.get("port"), "4100");
  assert.equal(url.searchParams.get("tenant"), "t");
  assert.equal(url.searchParams.get("secret"), "s");
  assert.equal(browser.queryParameter("host", "fallback"), "example.test");
  assert.equal(browser.queryParameter("missing", "fallback"), "fallback");
});
