import assert from "node:assert/strict";

// Let all reactions to released responses finish, without a clock or server.
const settle = () => new Promise(setImmediate);

export async function run(makeFixture, summary, encodeOperation) {
  const previousFetch = globalThis.fetch;
  const fixtures = [];
  let pending = [];
  const unexpected = [];
  const operation = (sequence, value = "live") =>
    JSON.parse(encodeOperation(sequence, value));
  const receive = (fixture, ...messages) =>
    fixture.receive(JSON.stringify(messages));
  const blob = { content: Buffer.from(summary).toString("base64") };
  globalThis.fetch = (request) => {
    const url = new URL(typeof request === "string" ? request : request.url);
    const allowed = url.origin === "https://bootstrap.invalid" &&
      (/\/trees\/tree-1$/.test(url.pathname) ||
       /\/blobs\/blob-1$/.test(url.pathname) ||
       url.pathname === "/deltas/test/bootstrap");
    if (!allowed) {
      unexpected.push(url.href);
      return Promise.reject(new Error(`Unexpected request: ${url}`));
    }
    return new Promise((resolve) => pending.push({
      url,
      release: (body, status = 200) =>
        resolve(new Response(JSON.stringify(body), { status })),
    }));
  };
  const take = (part) => {
    const index = pending.findIndex(({ url }) => url.href.includes(part));
    assert.notEqual(index, -1, `Missing HTTP request ${part}`);
    return pending.splice(index, 1)[0];
  };
  const start = async (initial = 0, checkpoint = 1) => {
    const fixture = makeFixture();
    fixtures.push(fixture);
    fixture.connect(true, checkpoint, initial);
    await settle();
    take("/trees/").release({ tree: [{ path: "header", sha: "blob-1" }] });
    await settle();
    return [fixture, take("/blobs/")];
  };
  try {
    {
      const [fixture, response] = await start();
      receive(fixture, operation(2));
      response.release(blob);
      await settle();
      assert.equal(fixture.ready(), 1);
      assert.equal(fixture.sequence(), 2, "live operation must survive summary loading");
      assert.equal(fixture.value(), "live");
      assert.equal(fixture.changes(), 1);
      fixture.close();
    }
    {
      const [fixture, response] = await start();
      receive(fixture, operation(3, "third"));
      response.release(blob);
      await settle();
      assert.equal(fixture.ready(), 0, "readiness must wait for a contiguous buffer");
      assert.equal(fixture.requests(), 1, "buffered gap must request missing history");
      receive(fixture, operation(2, "second"));
      await settle();
      assert.equal(fixture.ready(), 1);
      assert.equal(fixture.sequence(), 3);
      assert.equal(fixture.value(), "third");
      fixture.close();
    }
    {
      const [fixture, response] = await start(2, 2);
      receive(fixture, operation(2, "initial"));
      response.release(blob);
      await settle();
      assert.equal(fixture.ready(), 1);
      assert.equal(fixture.value(), "initial");
      assert.equal(fixture.changes(), 0, "history duplicate must not notify again");
      fixture.close();
    }
    {
      const [fixture, response] = await start(6, 6);
      response.release(blob);
      await settle();
      take("?from=1&to=5").release({ value: [operation(2), operation(3)] });
      await settle();
      const page = take("?from=3&to=5");
      receive(fixture, operation(7, "after-pages"));
      assert.equal(fixture.ready(), 0);
      page.release({ value: [operation(4), operation(5)] });
      await settle();
      assert.equal(fixture.ready(), 1);
      assert.equal(fixture.sequence(), 7);
      assert.equal(fixture.value(), "after-pages");
      fixture.close();
    }
    {
      const [fixture, oldResponse] = await start();
      receive(fixture, operation(2, "obsolete"));
      fixture.disconnect();
      fixture.connect(false, 1, 1);
      assert.equal(fixture.ready(), 1);
      oldResponse.release(blob);
      await settle();
      assert.equal(fixture.ready(), 1);
      assert.equal(fixture.sequence(), 1);
      assert.equal(fixture.value(), "initial", "old HTTP completion must not replace the new session");
      fixture.close();
    }
    {
      const [fixture, response] = await start();
      fixture.close();
      response.release(blob);
      await settle();
      assert.equal(fixture.ready(), 0);
      assert.equal(fixture.sequence(), -1);
    }
    for (const kind of ["http", "count", "bytes", "bytes-boundary"]) {
      const [fixture, response] = await start();
      if (kind === "http") response.release({ error: "unavailable" }, 503);
      if (kind === "count") {
        receive(fixture, ...Array.from({ length: 10000 }, (_, i) => operation(i + 2)));
        assert.equal(fixture.failure(), "");
        receive(fixture, operation(10002));
        response.release(blob);
      }
      if (kind === "bytes") {
        // Non-ASCII payload proves that the limit counts UTF-8 bytes, not code units.
        fixture.receive("[" + "\u00e9".repeat(8 * 1024 * 1024) + "]");
        response.release(blob);
      }
      if (kind === "bytes-boundary") {
        fixture.receive("[]" + " ".repeat(16 * 1024 * 1024 - 2));
        assert.equal(fixture.failure(), "", "exact byte limit is allowed");
        fixture.receive("[]");
        response.release(blob);
      }
      await settle();
      assert.equal(fixture.ready(), 0);
      assert.match(fixture.failure(), kind === "http" ? /summary load failed/ : /bootstrap.*limit/);
      assert.equal(fixture.sequence(), -1);
      assert.equal(fixture.failures(), 1);
      fixture.close();
    }
    {
      const fixture = makeFixture();
      fixtures.push(fixture);
      fixture.connect(false, 1, 1);
      assert.equal(fixture.ready(), 1, "summary-free bootstrap remains synchronous");
      assert.equal(fixture.value(), "initial");
      fixture.close();
    }
    assert.deepEqual(unexpected, []);
    assert.equal(pending.length, 0);
    console.log("PASS runtime bootstrap: retention, gaps, duplicates, pages, generations, limits");
  } finally {
    for (const fixture of fixtures) fixture.close();
    for (const request of pending) request.release({ error: "fixture closed" }, 503);
    pending = [];
    await settle();
    globalThis.fetch = previousFetch;
  }
}
