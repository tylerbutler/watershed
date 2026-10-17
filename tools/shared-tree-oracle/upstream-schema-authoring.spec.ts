/*!
 * Copyright (c) Microsoft Corporation and contributors. All rights reserved.
 * Licensed under the MIT License.
 */

import { strict as assert } from "node:assert";
import { mkdirSync, writeFileSync } from "node:fs";
import { isAbsolute, join } from "node:path";

import { FluidClientVersion } from "../codec/index.js";
import {
	extractPersistedSchema,
	SchemaFactory,
	type ImplicitFieldSchema,
} from "../simple-tree/index.js";

const formatVersion = 1;
const packageName = "@fluidframework/tree";
const packageVersion = "3.1.0";
const expectedCommit = "c3c5bf0ecd313362e83fe8a02b7d39e7e0736960";

describe("Watershed schema authoring oracle", () => {
	it("captures the pinned schema authoring subset", () => {
		const output = process.env.WATERSHED_ORACLE_OUTPUT;
		assert(output !== undefined && isAbsolute(output), "An absolute output directory is required");
		assert.equal(process.env.WATERSHED_ORACLE_COMMIT, expectedCommit);
		const sf = new SchemaFactory("com.example.authoring");
		const other = new SchemaFactory("com.example.other");
		class Words extends sf.array("Words", sf.string) {}
		class Numbers extends sf.map("Numbers", sf.number) {}
		class Card extends sf.object("Card", {
			title: sf.string,
			owner: sf.optional(sf.string),
		}) {}
		class Empty extends sf.object("Empty", {}) {}
		class Cards extends sf.array("Cards", Card) {}
		class Groups extends sf.map("Groups", Cards) {}
		class Nested extends sf.object("Nested", { groups: Groups, words: Words }) {}
		class Repeated extends sf.object("Repeated", { left: Card, right: Card }) {}
		class Foreign extends other.object("Foreign", { label: other.string }) {}
		class CrossFactory extends sf.object("CrossFactory", { foreign: Foreign }) {}
		const declarations: [string, ImplicitFieldSchema][] = [
			["string-root", sf.string],
			["number-root", sf.number],
			["boolean-root", sf.boolean],
			["null-root", sf.null],
			["handle-root", sf.handle],
			["optional-string-root", sf.optional(sf.string)],
			["string-array", Words],
			["number-map", Numbers],
			["card", Card],
			["empty-object", Empty],
			["nested", Nested],
			["repeated-child", Repeated],
			["cross-factory", CrossFactory],
		];
		mkdirSync(output, { recursive: true });
		writeFileSync(join(output, "schema-authoring.json"), `${JSON.stringify({
			formatVersion,
			reference: { package: packageName, version: packageVersion, commit: expectedCommit },
			observations: declarations.map(([id, declaration]) => ({
				id,
				schema: extractPersistedSchema(declaration, FluidClientVersion.v2_117, () => false),
			})),
		}, undefined, 2)}\n`, "utf8");
	});
});
