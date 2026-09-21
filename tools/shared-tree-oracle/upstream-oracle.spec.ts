import { strict as assert } from "node:assert";
import { mkdir, writeFile } from "node:fs/promises";
import { endianness } from "node:os";
import { isAbsolute, join } from "node:path";

import { createSessionId, deserializeIdCompressor, serializeIdCompressor } from "@fluidframework/id-compressor/internal";
import { FlushMode } from "@fluidframework/runtime-definitions/internal";
import { MockFluidDataStoreRuntime, MockSharedObjectServices } from "@fluidframework/test-runtime-utils/internal";

import { FluidClientVersion, jsonableCodecTree } from "../codec/index.js";
import { ObjectForest } from "../feature-libraries/object-forest/objectForest.js";
import { getCodecTreeForSharedTreeFormat } from "../shared-tree/index.js";
import { EditManager } from "../shared-tree-core/index.js";
import { SchemaFactory, TreeViewConfiguration } from "../simple-tree/index.js";
import { configuredSharedTreeInternal } from "../treeFactory.js";
import { MockContainerRuntimeWithOpBunching } from "./mocksForOpBunching.js";
import { TestTreeProviderLite } from "./utils.js";

describe("Watershed oracle", () => {
	it("captures the pinned source codecs, messages, compressor, and summary", async () => {
		const output = process.env.WATERSHED_ORACLE_OUTPUT;
		assert(output !== undefined && isAbsolute(output), "An absolute output directory is required");
		const commit = process.env.WATERSHED_ORACLE_COMMIT;
		assert.equal(commit, "c3c5bf0ecd313362e83fe8a02b7d39e7e0736960");

		const minVersionForCollab = FluidClientVersion.v2_117;
		const factory = configuredSharedTreeInternal({ minVersionForCollab }).getFactory();
		const provider = new TestTreeProviderLite(2, factory);
		const config = new TreeViewConfiguration({ schema: SchemaFactory.number });
		const first = provider.trees[0].viewWith(config);
		first.initialize(0);

		const messages: unknown[] = [];
		function deliver(): void {
			while (provider.peekNextMessage() !== undefined) {
				messages.push(JSON.parse(JSON.stringify(provider.peekNextMessage())));
				provider.synchronizeMessages({ count: 1 });
			}
		}
		deliver();
		const second = provider.trees[1].viewWith(config);
		first.root = 1;
		second.root = 2;
		const pending = [first.root, second.root];
		deliver();
		assert.equal(first.root, 2);
		assert.equal(second.root, 2);
		assert(messages.length > 0);

		const summary = await provider.trees[0].summarize(true);
		const compressor = serializeIdCompressor(provider.getCompressor(provider.trees[0]), false);
		const compressorBytes = Uint8Array.from(Buffer.from(compressor, "base64"));
		const capture = {
			formatVersion: 1,
			reference: { version: "3.1.0", commit },
			kind: "source-smoke",
			minVersionForCollab,
			codecTree: jsonableCodecTree(getCodecTreeForSharedTreeFormat(minVersionForCollab)),
			messages,
			observations: { pending, settled: [first.root, second.root] },
			compressor,
			compressorFormat: {
				version: new Float64Array(compressorBytes.buffer)[0],
				byteOrder: endianness(),
			},
			summary: summary.summary,
		};
		await mkdir(output, { recursive: true });
		await writeFile(join(output, "source-smoke.json"), `${JSON.stringify(capture, null, 2)}\n`);
	});

	const schema = new SchemaFactory("org.watershed.shared-tree.m1");
	class Point extends schema.object("Point", { x: schema.number, y: schema.number }) {}
	class Root extends schema.object("Root", {
		title: schema.string, enabled: schema.boolean, rating: schema.number,
		marker: schema.null, note: schema.optional(schema.string), point: Point,
	}) {}
	class KeyProbe extends schema.object("KeyProbe", {
		"": schema.string, "\u6c34": schema.string,
	}) {}
	class ExcludedArray extends schema.array("ExcludedArray", schema.number) {}
	class ExcludedMap extends schema.map("ExcludedMap", schema.number) {}
	const configuration = new TreeViewConfiguration({ schema: Root });
	const factory = configuredSharedTreeInternal({
		minVersionForCollab: FluidClientVersion.v2_117,
	}).getFactory();

	function copy<T>(value: T): T {
		return JSON.parse(JSON.stringify(value));
	}

	function visible(root: Root) {
		return {
			title: root.title, enabled: root.enabled,
			rating: root.rating, negativeZero: Object.is(root.rating, -0),
			marker: root.marker,
			note: root.note === undefined ? { present: false } : { present: true, value: root.note },
			point: { x: root.point.x, y: root.point.y },
		};
	}

	type EditValue = string | number | boolean | null | undefined | { x: number; y: number };
	type EditPath = "title" | "enabled" | "rating" | "note" | "point" | "point.x" | "point.y";

	function harness(note?: string, flushMode = FlushMode.Immediate) {
		const provider = new TestTreeProviderLite(2, factory, true, flushMode);
		const messages: unknown[] = [];
		const events: string[][] = [[], []];
		const actions: unknown[] = [];
		const observations: unknown[] = [];
		for (const [index, tree] of provider.trees.entries()) {
			const runtime = tree.containerRuntime;
			assert(runtime instanceof MockContainerRuntimeWithOpBunching);
			const process = runtime.process.bind(runtime);
			runtime.process = (message) => {
				if (index === 0) messages.push(copy(message));
				process(message);
			};
			const processMessages = runtime.processMessages.bind(runtime);
			runtime.processMessages = (batch) => {
				if (index === 0) messages.push(...copy(batch));
				processMessages(batch);
			};
			tree.kernel.checkout.events.on("afterBatch", () => events[index].push("afterBatch"));
		}
		const first = provider.trees[0].viewWith(configuration);
		first.initialize(new Root({
			title: "", enabled: false, rating: 0, marker: null, note,
			point: new Point({ x: 0, y: 0 }),
		}));
		provider.synchronizeMessages();
		const views = [first, provider.trees[1].viewWith(configuration)];

		function checkpoint(label: string) {
			observations.push({
				label, sequenceNumber: provider.sequenceNumber,
				minimumSequenceNumber: provider.minimumSequenceNumber,
				clients: provider.trees.map((tree, index) => {
					// The pinned kernel owns its manager privately. Validate its class before reading it.
					const manager: unknown = Reflect.get(tree.kernel, "editManager");
					assert(manager instanceof EditManager);
					return {
						visible: visible(views[index].root), events: [...events[index]],
						pending: manager.getLocalCommits("main").map(({ revision }) => revision),
						trunk: manager.getTrunkCommits("main").map(({ revision }) => revision),
						longestBranch: manager.getLongestBranchLength(),
						removed: copy(tree.contentSnapshot().removed),
					};
				}),
			});
		}

		function edit(client: number, path: EditPath, value: EditValue) {
			actions.push(value === undefined
				? { op: "clear", client, path }
				: { op: "set", client, path, value, ...(Object.is(value, -0) ? { negativeZero: true } : {}) });
			const root = views[client].root;
			switch (path) {
				case "title": assert(typeof value === "string"); root.title = value; break;
				case "enabled": assert(typeof value === "boolean"); root.enabled = value; break;
				case "rating": assert(typeof value === "number"); root.rating = value; break;
				case "note": assert(value === undefined || typeof value === "string"); root.note = value; break;
				case "point":
					assert(value !== null && typeof value === "object");
					root.point = new Point(value); break;
				case "point.x": assert(typeof value === "number"); root.point.x = value; break;
				case "point.y": assert(typeof value === "number"); root.point.y = value; break;
			}
			checkpoint(`edit-${actions.length}`);
		}

		function flush(client: number) {
			actions.push({ op: "flush", client });
			provider.trees[client].containerRuntime.flush();
		}

		function deliver() {
			actions.push({ op: "deliver" });
			for (let count = 0; provider.peekNextMessage() !== undefined; count++) {
				assert(count < 200, "Unexpected unbounded message stream");
				provider.synchronizeMessages({ count: 1, flush: false });
				checkpoint(`delivery-${messages.length}`);
			}
		}

		async function reload() {
			const summary = await provider.trees[0].summarize(true);
			const compressor = serializeIdCompressor(provider.getCompressor(provider.trees[0]), false);
			const runtime = new MockFluidDataStoreRuntime({
				idCompressor: deserializeIdCompressor(compressor, createSessionId()),
			});
			const tree = await factory.load(runtime, "reloaded",
				MockSharedObjectServices.createFromSummary(summary.summary), factory.attributes);
			const view = tree.viewWith(configuration);
			assert("contentSnapshot" in tree && typeof tree.contentSnapshot === "function");
			const snapshot: unknown = tree.contentSnapshot();
			assert(snapshot !== null && typeof snapshot === "object" && "removed" in snapshot);
			assert(Array.isArray(snapshot.removed));
			const observation = { visible: visible(view.root), removed: copy(snapshot.removed) };
			observations.push({ label: "reloaded", ...observation });
			return { summary: summary.summary, compressor, observation };
		}

		checkpoint("initial");
		return { provider, views, messages, actions, observations, checkpoint, edit, deliver, flush, reload };
	}

	function caseFile(id: string, domain: string, input: object, observations: unknown[], raw: object) {
		assert(observations.length > 0);
		return {
			formatVersion: 1,
			reference: {
				package: "@fluidframework/tree", version: "3.1.0",
				commit: "c3c5bf0ecd313362e83fe8a02b7d39e7e0736960",
			},
			id, domain, input,
			expected: { observations },
			raw,
		};
	}

	async function scenario(
		label: string,
		run: (test: ReturnType<typeof harness>) => void,
		note?: string,
		flushMode = FlushMode.Immediate,
	) {
		const test = harness(note, flushMode);
		const initial = {
			summary: (await test.provider.trees[0].summarize(true)).summary,
			sessions: test.provider.trees.map((tree) => test.provider.getCompressor(tree).localSessionId),
			compressors: test.provider.trees.map((tree) => serializeIdCompressor(test.provider.getCompressor(tree), true)),
			initializationMessages: copy(test.messages),
		};
		run(test);
		test.deliver();
		const loaded = await test.reload();
		assert.deepEqual(visible(test.views[0].root), visible(test.views[1].root));
		assert.deepEqual(loaded.observation.visible, visible(test.views[0].root));
		return {
			input: { label, initial, initialNote: note === undefined ? { present: false } : { present: true, value: note },
				flushMode, actions: test.actions },
			observations: { label, checkpoints: test.observations },
			raw: { messages: test.messages, summary: loaded.summary, compressor: loaded.compressor },
		};
	}

	function combine(id: string, domain: string, runs: Awaited<ReturnType<typeof scenario>>[]) {
		return caseFile(id, domain,
			{ runtime: "upstream-TestTreeProviderLite", schedules: runs.map((run) => run.input) },
			runs.map((run) => run.observations), { schedules: runs.map((run) => run.raw) });
	}

	function failure(run: () => unknown) {
		try {
			run();
		} catch (error: unknown) {
			assert(error instanceof Error);
			return { name: error.name, message: error.message };
		}
		assert.fail("Expected upstream refusal");
	}

	function internalState(test: ReturnType<typeof harness>) {
		const tree = test.provider.trees[0];
		const manager: unknown = Reflect.get(tree.kernel, "editManager");
		assert(manager instanceof EditManager);
		const forest = tree.kernel.checkout.forest;
		assert(forest instanceof ObjectForest);
		// Retain the same backing root before invalidation; guarded cursor APIs then refuse access.
		const roots = forest.roots;
		return () => JSON.parse(JSON.stringify({
			forest: roots,
			schema: {
				nodes: tree.kernel.storedSchema.nodeSchema,
				root: tree.kernel.storedSchema.rootFieldSchema,
			},
			pending: manager.getLocalCommits("main").map(({ revision }) => revision),
			trunk: manager.getTrunkCommits("main").map(({ revision }) => revision),
			compressor: serializeIdCompressor(test.provider.getCompressor(tree), true),
		}, (_key, value: unknown) =>
			value instanceof Map ? [...value] : value instanceof Set ? [...value] : value));
	}

	function removedPointX(removed: unknown): number[] {
		assert(Array.isArray(removed));
		return removed.flatMap((entry: unknown) => {
			assert(Array.isArray(entry));
			const node: unknown = entry[2];
			assert(node !== null && typeof node === "object" && "type" in node);
			if (node.type !== Point.identifier) return [];
			assert("fields" in node && node.fields !== null && typeof node.fields === "object");
			assert("x" in node.fields && Array.isArray(node.fields.x));
			const leaf: unknown = node.fields.x[0];
			assert(leaf !== null && typeof leaf === "object" && "value" in leaf && typeof leaf.value === "number");
			return [leaf.value];
		});
	}

	async function asyncFailure(run: () => Promise<unknown>) {
		try {
			await run();
		} catch (error: unknown) {
			assert(error instanceof Error);
			return { name: error.name, message: error.message };
		}
		assert.fail("Expected upstream refusal");
	}

	if (process.env.WATERSHED_ORACLE_CORPUS === "1") {
		describe("Watershed object-tree corpus", () => {
			it("records actual object edits, reconciliation, history, and reloads", async () => {
				const output = process.env.WATERSHED_ORACLE_OUTPUT;
				assert(output !== undefined && isAbsolute(output));
				const cases: ReturnType<typeof caseFile>[] = [];
				cases.push(combine("independent-fields", "tree", [
					await scenario("concurrent", (t) => {
						t.edit(0, "title", "left"); t.edit(1, "enabled", true);
					}),
				]));
				const sameFieldRuns = [];
				for (const order of [[0, 1], [1, 0]]) {
					sameFieldRuns.push(await scenario(order.join("-then-"), (t) => {
						for (const client of order) t.edit(client, "title", client === 0 ? "left" : "right");
					}));
				}
				cases.push(combine("same-field-both-orders", "tree", sameFieldRuns));
				cases.push(combine("optional-set-clear", "tree", [
					await scenario("set-then-clear", (t) => {
						t.edit(0, "note", "new"); t.edit(1, "note", undefined);
					}, "seed"),
					await scenario("clear-then-set", (t) => {
						t.edit(1, "note", undefined); t.edit(0, "note", "new");
					}, "seed"),
					await scenario("absent-clear-and-readd", (t) => {
						t.edit(0, "note", undefined); t.deliver();
						t.edit(0, "note", "first"); t.deliver();
						t.edit(1, "note", undefined); t.deliver();
						t.edit(0, "note", "again");
					}),
				]));
				const nullRun = await scenario("required-null-and-optional-absence", (t) => {
					const assignments: [string, unknown][] = [["marker", "string"], ["marker", undefined], ["note", null]];
					for (const [path, value] of assignments) {
						const before = visible(t.views[0].root);
						const error = failure(() => Reflect.set(t.views[0].root, path, value));
						assert.deepEqual(visible(t.views[0].root), before);
						t.actions.push(value === undefined
							? { op: "invalid-clear", path }
							: { op: "invalid-assignment", path, value });
						t.observations.push({ label: "atomic-refusal", error, visible: before });
					}
					t.edit(0, "note", "present"); t.deliver(); t.edit(0, "note", undefined);
				});
				cases.push(combine("null-and-absence", "tree", [nullRun]));
				cases.push(combine("nested-independent", "tree", [
					await scenario("concurrent", (t) => { t.edit(0, "point.x", 7); t.edit(1, "point.y", 9); }),
				]));
				const parentRuns = [];
				for (const order of [[0, 1], [1, 0]]) {
					parentRuns.push(await scenario(order.join("-then-"), (t) => {
						for (const client of order) {
							if (client === 0) t.edit(0, "point", { x: 10, y: 20 });
							else t.edit(1, "point.x", 7);
						}
					}));
				}
				cases.push(combine("parent-child-both-orders", "tree", parentRuns));
				const delayedDetached = await scenario("delayed-attached-peer-edit", (t) => {
					const retained = t.views[0].root.point;
					t.edit(0, "point", { x: 10, y: 20 });
					t.edit(1, "point.x", 42);
					t.deliver();
					assert.equal(retained.x, 42);
					assert.equal(t.views[0].root.point.x, 10);
					assert(removedPointX(t.provider.trees[0].contentSnapshot().removed).includes(42));
					t.observations.push({ label: "retained-reference-updated", x: retained.x, y: retained.y });
				});
				const reloadedDetached = delayedDetached.observations.checkpoints.at(-1);
				assert(reloadedDetached !== null && typeof reloadedDetached === "object" && "removed" in reloadedDetached);
				assert(removedPointX(reloadedDetached.removed).includes(42));
				cases.push(combine("detached-child-edit", "tree", [
					await scenario("retained-reference", (t) => {
						const removed = t.views[0].root.point;
						t.edit(0, "point", { x: 10, y: 20 });
						t.deliver();
						t.actions.push({ op: "edit-retained-point", client: 0, path: "x", value: 42 });
						const before = { x: removed.x, y: removed.y };
						const error = failure(() => { removed.x = 42; });
						const after = { x: removed.x, y: removed.y };
						assert.deepEqual(after, before);
						t.observations.push({ label: "detached-edit-refused", error, before, after });
						t.checkpoint("after-detached-edit-refusal");
						assert.equal(t.views[0].root.point.x, 10);
					}),
					delayedDetached,
				]));
				cases.push(combine("multiple-pending", "history", [
					await scenario("remote-between-local-flushes", (t) => {
						t.edit(0, "title", "one"); t.flush(0);
						t.edit(0, "note", "two"); t.edit(0, "rating", 3);
						t.edit(1, "enabled", true); t.flush(1); t.flush(0);
						t.checkpoint("three-local-commits-pending");
					}, undefined, FlushMode.TurnBased),
				]));
				cases.push(combine("history-window", "history", [
					await scenario("stale-peer-and-minimum-advance", (t) => {
						t.edit(0, "point", { x: 8, y: 9 }); t.edit(1, "point.x", 4);
						t.edit(0, "title", "pending"); t.deliver();
						const initial = t.provider.minimumSequenceNumber;
						for (let index = 0; index < 8; index++) {
							t.edit(index % 2, "title", `advance-${index}`); t.deliver();
						}
						assert(t.provider.minimumSequenceNumber > initial);
					}),
				]));
				const unicodeCase = combine("unicode-and-numbers", "values", [
					await scenario("unicode-and-finite-doubles", (t) => {
						t.edit(0, "title", "\u6c34\u{1f30a}\u0000e\u0301"); t.deliver();
						for (const value of [Number.MIN_VALUE, Number.MAX_VALUE, -0, -1.25, 9007199254740991]) {
							t.edit(0, "rating", value); t.deliver();
						}
					}),
				]);
				const keyProvider = new TestTreeProviderLite(1, factory);
				const keyView = keyProvider.trees[0].viewWith(new TreeViewConfiguration({ schema: KeyProbe }));
				keyView.initialize(new KeyProbe({ "": "", "\u6c34": "\u{1f30a}" }));
				keyView.root[""] = "empty-key";
				keyProvider.synchronizeMessages();
				Object.assign(unicodeCase.input, { fieldKeyProbe: { "": "empty-key", "\u6c34": "\u{1f30a}" } });
				unicodeCase.expected.observations.push({
					label: "empty-and-non-ascii-keys",
					visible: { "": keyView.root[""], "\u6c34": keyView.root["\u6c34"] },
				});
				const fieldKeySummary = (await keyProvider.trees[0].summarize(true)).summary;
				Object.assign(unicodeCase.input, { fieldKeySummary });
				Object.assign(unicodeCase.raw, { fieldKeySummary });
				cases.push(unicodeCase);
				const schemaTest = harness();
				const schemaSummary = await schemaTest.reload();
				schemaTest.views[1].dispose();
				const incompatible = schemaTest.provider.trees[1].viewWith(
					new TreeViewConfiguration({ schema: SchemaFactory.string }),
				);
				assert.equal(incompatible.compatibility.canView, false);
				const schemaIndexes = schemaSummary.summary.tree.indexes;
				assert(schemaIndexes.type === 1);
				const schemaIndex = schemaIndexes.tree.Schema;
				assert(schemaIndex.type === 1);
				const schemaBlob = schemaIndex.tree.SchemaString;
				assert(schemaBlob.type === 2 && typeof schemaBlob.content === "string");
				cases.push(caseFile("schema-profile", "schema",
					{ schemaNamespace: "org.watershed.shared-tree.m1", incompatibleSchema: "string",
						summary: schemaSummary.summary, compressor: schemaSummary.compressor },
					[{ visible: schemaSummary.observation.visible, compatibility: incompatible.compatibility,
						storedSchema: JSON.parse(schemaBlob.content) }],
					{ summary: schemaSummary.summary, compressor: schemaSummary.compressor }));
				const invalidInputs: unknown[] = [];
				const invalidObservations: unknown[] = [];
				const invalidRaw: unknown[] = [];
				for (const kind of ["array", "map"]) {
					const provider = new TestTreeProviderLite(1, factory);
					const tree = provider.trees[0];
					if (kind === "array") {
						const view = tree.viewWith(new TreeViewConfiguration({ schema: ExcludedArray }));
						view.initialize(new ExcludedArray([1]));
						view.dispose();
					} else {
						const view = tree.viewWith(new TreeViewConfiguration({ schema: ExcludedMap }));
						view.initialize(new ExcludedMap([["key", 1]]));
						view.dispose();
					}
					provider.synchronizeMessages();
					const view = tree.viewWith(configuration);
					assert.equal(view.compatibility.canView, false);
					const before = copy(tree.contentSnapshot());
					const error = failure(() => view.root);
					assert.deepEqual(copy(tree.contentSnapshot()), before);
					const summary = (await tree.summarize(true)).summary;
					invalidInputs.push({ mutation: "excluded-schema", kind, summary });
					invalidObservations.push({ mutation: "excluded-schema", kind,
						compatibility: view.compatibility, refused: true, statePreserved: true });
					invalidRaw.push({ mutation: "excluded-schema", kind, error, summary });
				}
				for (const mutation of ["message-version", "unknown-required-change"]) {
					const t = harness();
					t.edit(0, "title", "must-not-apply-remotely");
					let next = t.provider.peekNextMessage();
					while (next !== undefined) {
						const contents: unknown = next.contents;
						if (contents !== null && typeof contents === "object" && "version" in contents) break;
						t.provider.synchronizeMessages({ count: 1 });
						next = t.provider.peekNextMessage();
					}
					assert(next !== undefined);
					const contents: unknown = copy(next.contents);
					assert(contents !== null && typeof contents === "object" && "version" in contents);
					if (mutation === "message-version") contents.version = 999;
					else {
						assert("changeset" in contents);
						contents.changeset = [{ requiredUnsupportedChange: {} }];
					}
					const before = t.views.map((view) => visible(view.root));
					const observeState = internalState(t);
					const stateBefore: unknown = observeState();
					const corrupted = { ...copy(next), contents };
					const runtime = t.provider.trees[0].containerRuntime;
					assert(runtime instanceof MockContainerRuntimeWithOpBunching);
					const process = runtime.process.bind(runtime);
					runtime.process = (message) => process({ ...message, contents });
					const error = failure(() => t.provider.synchronizeMessages({ count: 1 }));
					const stateAfter: unknown = observeState();
					assert.deepEqual(stateAfter, stateBefore);
					const subsequentReadError = failure(() => visible(t.views[0].root));
					const unaffectedPeer = visible(t.views[1].root);
					assert.deepEqual(unaffectedPeer, before[1]);
					invalidInputs.push({ mutation, initialState: stateBefore, message: corrupted });
					invalidObservations.push({ mutation, refused: true, clientInvalidated: true,
						statePreserved: true, before, unaffectedPeer });
					invalidRaw.push({ mutation, error, subsequentReadError, stateBefore, stateAfter,
						message: corrupted, delivered: t.messages });
				}
				const missingBlob = copy(schemaSummary.summary);
				const indexes = missingBlob.tree.indexes;
				assert(indexes.type === 1);
				const forest = indexes.tree.Forest;
				assert(forest.type === 1);
				delete forest.tree.contents;
				const missingBlobError = await asyncFailure(() => factory.load(
					new MockFluidDataStoreRuntime({
						idCompressor: deserializeIdCompressor(schemaSummary.compressor, createSessionId()),
					}),
					"missing-blob",
					MockSharedObjectServices.createFromSummary(missingBlob), factory.attributes,
				));
				invalidInputs.push({ mutation: "missing-forest-blob", summary: missingBlob, compressor: schemaSummary.compressor });
				invalidObservations.push({ mutation: "missing-forest-blob", error: missingBlobError });
				invalidRaw.push({ mutation: "missing-forest-blob", summary: missingBlob });
				cases.push(caseFile("invalid-profile", "invalid",
					{ mutations: invalidInputs }, invalidObservations, { mutations: invalidRaw }));
				await writeFile(join(output, "tree-cases.json"), `${JSON.stringify(cases, null, 2)}\n`);
			});
		});
	}
});
