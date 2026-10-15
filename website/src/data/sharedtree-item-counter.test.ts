import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import test from "node:test";
import { isSourceBacked } from "../lib/snippet.ts";
import { itemCounterRows, upstreamCommit } from "./sharedtree-item-counter.ts";

const snapshotRoot = new URL(
  "../../../examples/shared_tree_item_counter_lustre/upstream/",
  import.meta.url,
);
const originalDigests = {
  "src/schema.ts": "b94b5ed4619bd5c758d9341a994a725d5cdf043964a3da20c14f0be095a8bc33",
  "src/index.tsx": "2438b3e105ea461dfe35efeff68c17ae109940da7fe45ff59d74ad0e0b27ba31",
  "src/react_app.tsx": "2bbc732ff8b10664967f50c778cfbebd460de484032d24957cfaefad4935f254",
  "src/infra/fluid.ts": "d18f69efad2d5f26eb0d793e66f2db88230753b250686e262954de6f904e27ae",
};

test("reference sources reproduce the pinned upstream bytes without extraction markers", () => {
  for (const [path, expected] of Object.entries(originalDigests)) {
    const source = readFileSync(new URL(path, snapshotRoot), "utf8");
    const original = source.replace(
      /^[\t ]*\/\/ docs:snippet-(?:start|end) [\w-]+\r?\n/gm,
      "",
    );
    assert.equal(createHash("sha256").update(original).digest("hex"), expected, path);
    assert.match(source, /Copyright \(c\) Microsoft Corporation/);
  }
  assert.match(readFileSync(new URL("LICENSE", snapshotRoot), "utf8"), /MIT License/);
  assert.match(readFileSync(new URL("README.md", snapshotRoot), "utf8"), new RegExp(upstreamCommit));
});

test("each comparison task quotes real, attributed source in both languages", () => {
  assert.deepEqual(itemCounterRows.map(row => row.id), [
    "schema", "lifecycle", "observe", "edits",
  ]);
  for (const row of itemCounterRows) {
    assert.ok(row.title && row.explanation);
    for (const column of ["fluid", "watershed"] as const) {
      assert.ok(row[column].length > 0);
      for (const snippet of row[column]) {
        assert.ok(isSourceBacked(snippet));
        assert.ok(snippet.code.trim());
        assert.ok(!snippet.code.includes("docs:snippet-"));
        assert.match(snippet.sourcePath, /^examples\/shared_tree_item_counter_lustre\//);
        assert.equal(snippet.language, column === "fluid" ? "typescript" : "gleam");
        assert.ok(snippet.sourceUrl);
        if (column === "fluid") {
          const originalPath = snippet.sourcePath.split("/upstream/")[1];
          assert.equal(snippet.sourceUrl,
            `https://github.com/microsoft/FluidExamples/blob/${upstreamCommit}/item-counter/${originalPath}`);
        }
      }
    }
  }
});

test("the generated schema snippet quotes the typed array declaration", () => {
  const row = itemCounterRows.find(row => row.id === "schema");
  assert.ok(row);
  const snippet = row.watershed[0];
  assert.match(snippet.code, /builder\.array\(/);
  assert.match(snippet.code, /"shared_tree_item_counter"/);
  assert.match(snippet.code, /"StringArray"/);
  assert.deepEqual(snippet.origin, {
    kind: "source",
    markers: ["item-counter-watershed-definition", "item-counter-watershed-schema"],
  });
});
