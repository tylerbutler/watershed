import assert from "node:assert/strict";

const settle = () => new Promise(setImmediate);

export async function run(makeFixture) {
  const previousFetch = globalThis.fetch;
  const fixture = makeFixture();
  let release;
  globalThis.fetch = (request) => {
    const url = new URL(typeof request === "string" ? request : request.url);
    assert.equal(url.origin, "https://seed.invalid");
    assert.equal(url.pathname, "/deltas/default/tree");
    assert.equal(url.search, "?from=0&to=2");
    return new Promise((resolve) => {
      release = () => resolve(new Response(
        JSON.stringify({ value: JSON.parse(fixture.prefix) }),
        { status: 200 },
      ));
    });
  };
  try {
    fixture.connect();
    await settle();
    assert.equal(typeof release, "function", "prefix HTTP request must be pending");
    fixture.receive();
    release();
    await settle();
    assert.equal(fixture.edit_rejected(), true);
    assert.equal(fixture.pending_before_close(), 0);
    assert.equal(fixture.phase(), "connecting");
    assert.equal(fixture.ready(), 0);
  } finally {
    fixture.close();
    globalThis.fetch = previousFetch;
  }
}
