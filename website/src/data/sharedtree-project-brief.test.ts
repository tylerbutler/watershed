import assert from "node:assert/strict";
import test from "node:test";
import { isSourceBacked } from "../lib/snippet.ts";
import { projectBriefRows } from "./sharedtree-project-brief.ts";

test("six project-brief tasks pair locally authored source in both languages", () => {
  assert.deepEqual(projectBriefRows.map(row => row.id), [
    "schema", "lifecycle", "observe", "edits", "milestones", "presence",
  ]);
  for (const row of projectBriefRows) {
    assert.ok(row.title && row.explanation);
    for (const side of ["fluid", "watershed"] as const) {
      assert.ok(row[side].length > 0);
      for (const snippet of row[side]) {
        assert.ok(isSourceBacked(snippet));
        assert.ok(snippet.code.trim());
        assert.doesNotMatch(snippet.code, /docs:snippet-/);
        assert.match(snippet.sourcePath, /^examples\/shared_tree_project_brief_lustre\//);
        assert.equal(snippet.language, side === "fluid" ? "typescript" : "gleam");
        assert.equal(snippet.sourceUrl,
          `https://github.com/tylerbutler/watershed/blob/main/${snippet.sourcePath}`);
        assert.equal(snippet.origin.kind, "source");
        if (snippet.origin.kind === "source") {
          assert.ok(snippet.origin.markers.every(marker =>
            marker.startsWith(`project-brief-${side}-${row.id}`)));
        }
      }
    }
  }
});

test("milestones quote UUID insertion, captured node edits, and keyed rendering", () => {
  const row = projectBriefRows.find(row => row.id === "milestones")!;
  const fluid = row.fluid.map(snippet => snippet.code).join("\n");
  const gleam = row.watershed.map(snippet => snippet.code).join("\n");
  assert.match(fluid, /crypto\.randomUUID\(\)/);
  assert.match(fluid, /key=\{node\.id\}/);
  assert.match(fluid, /assign\(root, node, "title"/);
  assert.match(fluid, /removeMilestone\(root, node\)/);
  assert.match(gleam, /id\.uuid_v4\(\)/);
  assert.match(gleam, /keyed\.div\(/);
  assert.match(gleam, /shared_tree\.set\(node, schema\.milestone_title\(\)/);
  assert.match(gleam, /tree\.array_remove_node\(array, item\)/);
});

test("presence quotes ephemeral transports and actual update wiring", () => {
  const row = projectBriefRows.find(row => row.id === "presence")!;
  const fluid = row.fluid.map(snippet => snippet.code).join("\n");
  const gleam = row.watershed.map(snippet => snippet.code).join("\n");
  assert.match(fluid, /signaler\.submitSignal/);
  assert.match(fluid, /signaler\.onSignal/);
  assert.match(fluid, /signaler\.offSignal/);
  assert.match(fluid, /update\(next\)/);
  assert.match(gleam, /presence\.with_mode\(presence\.Ripple\)/);
  assert.match(gleam, /watershed_lustre\.presence\(/);
  assert.match(gleam, /watershed_lustre\.update_presence/);
});
