import assert from "node:assert/strict";
import { test } from "node:test";

import { categories } from "./structures.ts";

test("registers appear before maps in the field atlas", () => {
  const slugs = categories.map((category) => category.slug);

  assert.ok(slugs.indexOf("registers") < slugs.indexOf("maps"));
});
