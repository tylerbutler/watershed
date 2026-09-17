import assert from "node:assert/strict";
import { test } from "node:test";

import {
  contextualNavigation,
  footerNavigationSections,
  topNavigationGroups,
} from "./navigation.ts";

test("top navigation follows the learning path and pairs the model sections", () => {
  assert.deepEqual(
    topNavigationGroups.flatMap((group) => group.links.map((link) => link.label)),
    [
      "Foundations",
      "Components",
      "Guide",
      "Atlas",
      "Runtime",
      "Models",
      "Examples",
      "Source",
    ],
  );
  assert.deepEqual(
    topNavigationGroups[0]?.links.map((link) => link.label),
    ["Foundations", "Components"],
  );
});

test("footer sections preserve the top navigation learning path", () => {
  assert.deepEqual(
    footerNavigationSections.map((section) => section.label),
    ["Foundations", "Components", "Guide", "Atlas", "Runtime"],
  );
});

test("nested sections expose their own ordered sheet index", () => {
  const navigation = contextualNavigation("/component-model/ports");

  assert.equal(navigation?.label, "Component model");
  assert.deepEqual(
    navigation?.links.map((link) => link.label),
    ["Overview", "01 Components", "02 Ports", "03 Workspaces"],
  );
  assert.equal(navigation?.links[2]?.current, true);
});

test("singleton destinations do not add an empty contextual row", () => {
  assert.equal(contextualNavigation("/models"), null);
  assert.equal(contextualNavigation("/examples"), null);
});
