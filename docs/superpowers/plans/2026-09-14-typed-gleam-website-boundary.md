# Typed Gleam Website Boundary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every website import of generated Gleam JavaScript subject to a TypeScript check that rejects API drift before the browser runs.

**Architecture:** Enable Gleam's compiler-owned `.d.mts` output for both local Gleam packages and their dependencies. Type-check every website consumer through one small `Result`/`Option` helper module, convert the remaining generated-module consumers from JavaScript to TypeScript, and make the type check a required website and root test gate.

**Tech Stack:** Gleam JavaScript target, generated TypeScript declarations, TypeScript, Astro 7, Node 24, pnpm 11.

**Spec:** `docs/superpowers/specs/2026-09-14-typed-gleam-website-boundary-design.md`

## Global Constraints

- Gleam-generated `.d.mts` files remain under ignored `build/` directories.
- Do not handwrite declarations for Gleam modules or kernel functions.
- Do not add `any`, broad `unknown` casts, or success-shaped fallbacks to silence TypeScript.
- Preserve all website demo behavior.
- Only the shared Gleam value helper may import `Some`, `None`, `Ok`, or Gleam's `Error` constructor.
- Type generation must precede `tsc --noEmit`.
- Use the existing pnpm, Gleam, Node, and website test tools.
- Do not add Co-authored-by trailers to commits.

---

### Task 1: Emit compiler-owned TypeScript declarations

**Files:**
- Modify: `gleam.toml:1-12`
- Modify: `watershed_lustre/gleam.toml:1-13`

**Interfaces:**
- Consumes: Gleam's `[javascript] typescript_declarations` package setting.
- Produces: `.d.mts` files beside every generated `.mjs` module under `build/dev/javascript/` and `watershed_lustre/build/dev/javascript/`.

- [ ] **Step 1: Prove declarations are absent**

Run:

```bash
test -f build/dev/javascript/watershed/watershed/pact_map_kernel.d.mts
```

Expected: exit 1 because the root package does not emit declarations yet.

Run:

```bash
test -f watershed_lustre/build/dev/javascript/watershed_lustre/watershed_lustre.d.mts
```

Expected: exit 1 because the Lustre package does not emit declarations yet.

- [ ] **Step 2: Enable declarations in the root package**

Add this table below `target = "erlang"` in `gleam.toml`:

```toml
[javascript]
typescript_declarations = true
```

- [ ] **Step 3: Enable declarations in the Lustre package**

Add this table below `target = "javascript"` in
`watershed_lustre/gleam.toml`:

```toml
[javascript]
typescript_declarations = true
```

- [ ] **Step 4: Build both JavaScript targets**

Run:

```bash
gleam build --target javascript
cd watershed_lustre && gleam build --target javascript
```

Expected: both commands exit 0.

- [ ] **Step 5: Verify application and dependency declarations**

Run:

```bash
test -f build/dev/javascript/watershed/watershed/pact_map_kernel.d.mts
test -f build/dev/javascript/watershed/gleam.d.mts
test -f build/dev/javascript/gleam_stdlib/gleam/option.d.mts
test -f build/dev/javascript/gleam_json/gleam/json.d.mts
test -f build/dev/javascript/lattice_core/lattice_core/replica_id.d.mts
test -f watershed_lustre/build/dev/javascript/watershed_lustre/watershed_lustre.d.mts
```

Expected: every command exits 0.

- [ ] **Step 6: Inspect the PactMap signatures**

Run:

```bash
grep -n -A4 -E 'function (get_with_details|get_pending|set|delete\\$)' \
  build/dev/javascript/watershed/watershed/pact_map_kernel.d.mts
```

Expected: each function returns a generated `Result<...>` type. None returns
`Option<...>`.

- [ ] **Step 7: Commit**

```bash
git add gleam.toml watershed_lustre/gleam.toml
git commit -m "build: emit Gleam TypeScript declarations"
```

---

### Task 2: Add typed Gleam value helpers and a compile contract

**Files:**
- Create: `website/src/scripts/demo/gleam-values.ts`
- Create: `website/src/scripts/demo/gleam-values.type-test.ts`
- Modify: `website/package.json`
- Modify: `website/pnpm-lock.yaml`

**Interfaces:**
- Consumes:
  - Root `Result<T, E>`, `Ok<T, E>`, and Gleam `Error<T, E>` from `build/dev/javascript/watershed/gleam.mjs`.
  - Root `Option$<T>`, `Some<T>`, and `None` from `build/dev/javascript/gleam_stdlib/gleam/option.mjs`.
  - The matching constructor types from `watershed_lustre/build/dev/javascript/` because that package has a separate runtime prelude.
- Produces:
  - `isOk<T, E>(result: Result<T, E>): result is Ok<T, E>`
  - `resultValue<T, E>(result: Result<T, E>): T | null`
  - `expectOk<T, E>(result: Result<T, E>, detail: string): T`
  - `isSome<T>(option: Option<T>): option is Some<T>`
  - `optionValue<T>(option: Option<T>): T | null`
  - `some<T>(value: T): Option<T>`
  - `none<T>(): Option<T>`
  - `ResultValue<R>`: the `Ok` value type from a generated `Result`

- [ ] **Step 1: Install TypeScript explicitly**

Run:

```bash
cd website && pnpm add --save-dev typescript
```

Expected: `package.json` lists `typescript` under `devDependencies`, and
`pnpm-lock.yaml` records the resolved version.

- [ ] **Step 2: Write the compile-time contract first**

Create `website/src/scripts/demo/gleam-values.type-test.ts`:

```ts
import * as pactMap from "../../../../build/dev/javascript/watershed/watershed/pact_map_kernel.mjs";
import {
  optionValue,
  resultValue,
} from "./gleam-values.ts";

declare const state: pactMap.PactMapState;
declare const setResult: ReturnType<typeof pactMap.set>;
declare const deleteResult: ReturnType<typeof pactMap.delete$>;

const acceptedResult = pactMap.get_with_details(state, "datum-grid");
const pendingResult = pactMap.get_pending(state, "datum-grid");

resultValue(acceptedResult);
resultValue(pendingResult);
resultValue(setResult);
resultValue(deleteResult);

// @ts-expect-error PactMap reads return Result, not Option.
optionValue(acceptedResult);
// @ts-expect-error PactMap proposals return Result, not Option.
optionValue(setResult);
// @ts-expect-error PactMap deletes return Result, not Option.
optionValue(deleteResult);
```

- [ ] **Step 3: Run the contract to verify it fails**

Run:

```bash
cd website && pnpm exec tsc \
  --ignoreConfig \
  --noEmit \
  --strict \
  --target ESNext \
  --module ESNext \
  --moduleResolution Bundler \
  --allowImportingTsExtensions \
  --skipLibCheck \
  src/scripts/demo/gleam-values.type-test.ts
```

Expected: FAIL because `./gleam-values.ts` does not exist.

- [ ] **Step 4: Implement the typed helper**

Create `website/src/scripts/demo/gleam-values.ts`:

```ts
import {
  Error as RootError,
  Ok as RootOk,
  type Result as RootResult,
} from "../../../../build/dev/javascript/watershed/gleam.mjs";
import {
  None as RootNone,
  Some as RootSome,
  type Option$ as RootOption,
} from "../../../../build/dev/javascript/gleam_stdlib/gleam/option.mjs";
import {
  Error as LustreError,
  Ok as LustreOk,
  type Result as LustreResult,
} from "../../../../watershed_lustre/build/dev/javascript/watershed/gleam.mjs";
import {
  None as LustreNone,
  Some as LustreSome,
  type Option$ as LustreOption,
} from "../../../../watershed_lustre/build/dev/javascript/gleam_stdlib/gleam/option.mjs";

type Result<T, E> = RootResult<T, E> | LustreResult<T, E>;
type Ok<T, E> = RootOk<T, E> | LustreOk<T, E>;
type Option<T> = RootOption<T> | LustreOption<T>;
type Some<T> = RootSome<T> | LustreSome<T>;

export type ResultValue<R> =
  R extends RootResult<infer T, infer _E> ? T
    : R extends LustreResult<infer T, infer _E> ? T
    : never;

export function isOk<T, E>(result: Result<T, E>): result is Ok<T, E> {
  return result instanceof RootOk || result instanceof LustreOk;
}

export function resultValue<T, E>(result: Result<T, E>): T | null {
  return isOk(result) ? result[0] : null;
}

export function expectOk<T, E>(result: Result<T, E>, detail: string): T {
  if (isOk(result)) return result[0];
  const error =
    result instanceof RootError || result instanceof LustreError
      ? result[0]
      : result;
  throw new Error(`${detail}: ${String(error)}`);
}

export function isSome<T>(option: Option<T>): option is Some<T> {
  return option instanceof RootSome || option instanceof LustreSome;
}

export function optionValue<T>(option: Option<T>): T | null {
  return isSome(option) ? option[0] : null;
}

export function some<T>(value: T): RootOption<T> {
  return new RootSome(value);
}

export function none<T>(): RootOption<T> {
  return new RootNone();
}
```

- [ ] **Step 5: Run the contract to verify it passes**

Run the command from Step 3 again.

Expected: PASS. TypeScript consumes all three `@ts-expect-error` directives,
which proves that `Result` cannot enter the option helper.

- [ ] **Step 6: Commit**

```bash
git add website/package.json website/pnpm-lock.yaml \
  website/src/scripts/demo/gleam-values.ts \
  website/src/scripts/demo/gleam-values.type-test.ts
git commit -m "feat(site): add typed Gleam value helpers"
```

---

### Task 3: Type-check the existing TypeScript demo consumers

**Files:**
- Modify: `website/tsconfig.json`
- Modify: `website/package.json`
- Modify: `website/src/scripts/demo/sluice-rig.ts`
- Modify: `website/src/scripts/json-ot-demo.ts`
- Modify: `website/src/scripts/text-element-demo.ts`
- Modify: `website/src/scripts/text-demo.ts`
- Modify: `website/src/scripts/directory-demo.ts`
- Modify: `website/src/scripts/rich-text-demo.ts`
- Modify: `website/src/scripts/sequence-demo.ts`
- Modify: `website/src/scripts/guide-race-demo.ts`
- Modify: `website/src/scripts/counter-bug.ts`
- Modify: `website/src/scripts/sudoku-demo.ts`

**Interfaces:**
- Consumes: the helper exports from Task 2 and generated declarations from Task 1.
- Produces: a strict `pnpm check:types` command that passes for every existing `.ts` consumer of generated Gleam modules.

- [ ] **Step 1: Add the strict type-check command**

Change `website/tsconfig.json` to:

```json
{
  "extends": "astro/tsconfigs/base",
  "compilerOptions": {
    "strict": true
  },
  "include": [".astro/types.d.ts", "src/**/*"],
  "exclude": ["dist"]
}
```

Add this package script:

```json
"check:types": "tsc --noEmit",
```

- [ ] **Step 2: Run the broad check to establish the failing baseline**

Run:

```bash
cd website && pnpm check:types
```

Expected: FAIL on the current `unknown` result and option helpers, unsafe DOM
queries, or generated API mismatches. Save the diagnostics for the next steps.

- [ ] **Step 3: Make `sluice-rig.ts` use the typed option helper**

Replace its local structural `some` implementation with:

```ts
import { optionValue } from "./gleam-values.ts";

export const some = optionValue;
```

Keep the exported name `some` in this task so existing dedicated demos do not
need an unrelated rename. Its parameter is now `Option<T>`, so passing a
`Result` becomes a compile error.

- [ ] **Step 4: Replace local result helpers**

Use imports from `./demo/gleam-values.ts` in top-level demo scripts and from
`./gleam-values.ts` inside `src/scripts/demo/`.

Apply these replacements:

```ts
// Before
function okValue<T>(result: unknown): T {
  return (result as { 0: T })[0];
}

// After
import { expectOk, resultValue } from "./demo/gleam-values.ts";
```

Use `expectOk(result, "specific operation failed")` where failure is
unexpected and should stop the demo. Use `resultValue(result)` where the code
already has an explicit error branch.

Remove the local helpers at:

- `json-ot-demo.ts`: `okValue`
- `text-element-demo.ts`: `isOk`, `okValue`, and `some`
- `text-demo.ts`: `isOk` and `okValue`
- `directory-demo.ts`: `okValue`
- `rich-text-demo.ts`: `resultOk` and `okValue`
- `sequence-demo.ts`: `okValue`
- `guide-race-demo.ts`: `expectOk`

Do not replace domain-specific `unknown` handle storage in `RigClient`; those
handles cross several DDS types by design. Narrow each handle at the first
generated function call that requires a concrete type.

- [ ] **Step 5: Use generated result narrowing in rich text**

Replace structural result casts with typed branches:

```ts
const parsed = resultValue(richText.parse_delta(JSON.stringify(ops)));
if (parsed !== null) return parsed;

console.error(
  `watershed rich-text demo: could not decode ${context} as a rich_text delta`,
);
return null;
```

For operations whose error value must be logged, use `isOk` and read the
generated Gleam error variant only inside the error branch:

```ts
const transformed = richText.transform_selection(
  gleamDelta,
  selection,
  isOwnOperation,
);
if (!isOk(transformed)) {
  console.error(
    "watershed rich-text demo: transform_selection failed",
    transformed[0],
  );
  return fallback;
}
const value = transformed[0];
```

- [ ] **Step 6: Fix generated signature and DOM diagnostics**

Resolve the diagnostics in the listed files with these rules:

- pass the exact generated argument type;
- narrow nullable DOM queries with an explicit guard;
- use `instanceof` only for domain constructors such as kernel operations;
- use `expectOk`, `resultValue`, or `optionValue` for Gleam containers;
- remove casts that only existed because generated imports were untyped.

Use this local DOM helper where a file repeatedly queries required markup:

```ts
function required<T extends Element>(
  root: ParentNode,
  selector: string,
): T {
  const element = root.querySelector<T>(selector);
  if (!element) throw new Error(`Missing demo element: ${selector}`);
  return element;
}
```

- [ ] **Step 7: Run the type check**

Run:

```bash
cd website && pnpm check:types
```

Expected: PASS. `demo.js` and `demo/boot.test.mjs` remain outside TypeScript
checking until Tasks 4 and 5.

- [ ] **Step 8: Run the affected non-browser tests**

Run:

```bash
cd website && \
  pnpm test:rich-text-adapter && \
  node --strip-types --test src/data/drift-gates.test.ts
```

Expected: all tests pass.

- [ ] **Step 9: Commit**

```bash
git add website/tsconfig.json website/package.json \
  website/src/scripts/demo/sluice-rig.ts \
  website/src/scripts/json-ot-demo.ts \
  website/src/scripts/text-element-demo.ts \
  website/src/scripts/text-demo.ts \
  website/src/scripts/directory-demo.ts \
  website/src/scripts/rich-text-demo.ts \
  website/src/scripts/sequence-demo.ts \
  website/src/scripts/guide-race-demo.ts \
  website/src/scripts/counter-bug.ts \
  website/src/scripts/sudoku-demo.ts
git commit -m "refactor(site): type Gleam demo consumers"
```

---

### Task 4: Type the generated-module boot test

**Files:**
- Move: `website/src/scripts/demo/boot.test.mjs` to `website/src/scripts/demo/boot.test.ts`
- Modify: `website/package.json`

**Interfaces:**
- Consumes: `expectOk` from Task 2 and generated kernel declarations.
- Produces: a TypeScript boot test that still runs through Node's built-in type stripping.

- [ ] **Step 1: Rename the test**

Run:

```bash
git mv website/src/scripts/demo/boot.test.mjs \
  website/src/scripts/demo/boot.test.ts
```

- [ ] **Step 2: Run the type check to verify the renamed test fails**

Run:

```bash
cd website && pnpm check:types
```

Expected: FAIL on the test's structural `ok` helper or generated values that
were previously untyped.

- [ ] **Step 3: Replace the structural result helper**

Import the shared helper:

```ts
import { expectOk, some } from "./gleam-values.ts";
```

Replace:

```ts
const ok = (result) => {
  assert.ok(result.isOk(), `Kernel returned ${result[0]?.constructor.name}`);
  return result[0];
};
```

with direct calls such as:

```ts
const loaded = expectOk(
  orMap.from_summary(summary, replica.new$("client-a")),
  "ORMap summary load failed",
);
```

Remove the direct `Some` import. Replace both `new Some(...)` calls with
`some(...)`.

Use generated state and operation types instead of adding a generic test-only
cast.

- [ ] **Step 4: Update the test command**

Change:

```json
"test:demo-boot": "node --test src/scripts/demo/boot.test.mjs",
```

to:

```json
"test:demo-boot": "node --strip-types --test src/scripts/demo/boot.test.ts",
```

- [ ] **Step 5: Verify the test and type check**

Run:

```bash
cd website && pnpm check:types && pnpm test:demo-boot
```

Expected: the type check passes and all boot tests pass.

- [ ] **Step 6: Commit**

```bash
git add website/package.json \
  website/src/scripts/demo/boot.test.mjs \
  website/src/scripts/demo/boot.test.ts
git commit -m "test(site): type Gleam demo boot checks"
```

---

### Task 5: Convert the shared structure demo to TypeScript

**Files:**
- Move: `website/src/scripts/demo.js` to `website/src/scripts/demo.ts`
- Modify: `website/src/components/Demo.astro:1188`
- Test: `website/scripts/structure-demos.test.mjs`
- Test: `website/scripts/ormap-demo.test.mjs`
- Test: `website/scripts/lww-map-demo.test.mjs`
- Test: `website/scripts/or-map-mv-register-demo.test.mjs`
- Test: `website/scripts/mv-register-demo.test.mjs`

**Interfaces:**
- Consumes: generated declarations, `isOk`, `resultValue`, `optionValue`, `some`, `none`, and `expectOk`.
- Produces: `initDemo(): void` from a strict TypeScript module.

- [ ] **Step 1: Record the passing behavior baseline**

Start the website:

```bash
cd website && pnpm dev --host 127.0.0.1
```

In another shell, run:

```bash
cd website && pnpm test:structure-demos
```

Expected: all structure demo tests pass before the source rename.

- [ ] **Step 2: Rename the module and update its dynamic import**

Run:

```bash
git mv website/src/scripts/demo.js website/src/scripts/demo.ts
```

Change `website/src/components/Demo.astro` to:

```ts
const { initDemo } = await import("../scripts/demo.ts");
```

- [ ] **Step 3: Run the type check to establish the failing conversion**

Run:

```bash
cd website && pnpm check:types
```

Expected: FAIL with strict diagnostics in `demo.ts`. This is the red phase for
the conversion.

- [ ] **Step 4: Import the typed Gleam value helpers**

Replace the direct `Some` and `None` import with:

```ts
import {
  expectOk,
  isOk,
  none,
  optionValue,
  type ResultValue,
  resultValue,
  some,
} from "./demo/gleam-values.ts";
```

Replace constructor calls:

```ts
// Before
new Some(value)
new None()

// After
some(value)
none()
```

- [ ] **Step 5: Make PactMap use the generated return types**

Use the typed helpers at every PactMap boundary:

```ts
function pactAccepted(
  state: pactKernel.PactMapState,
  key: string,
): { value: string | null; sequence: number } | null {
  const accepted = resultValue(pactKernel.get_with_details(state, key));
  if (accepted === null) return null;
  return {
    value: optionValue(accepted.value),
    sequence: accepted.sequence_number,
  };
}

function pactPendingValue(
  state: pactKernel.PactMapState,
  key: string,
): string | null {
  const pending = resultValue(pactKernel.get_pending(state, key));
  if (pending === null) return null;
  return optionValue(pending) ?? "delete";
}
```

Build local proposals with `resultValue`:

```ts
const operation = resultValue(
  pactKernel.set(
    client.pact,
    key,
    some(json.string(PACT_VALUES[clientId])),
    client.lastSeq,
  ),
);
if (operation === null) {
  pactNotes[clientId][key] = "pending pact blocks new proposal";
  render(client);
  return;
}
submit(clientId, "pact", operation);
```

Apply the same pattern to `pactKernel.delete$`. Do not use
`instanceof Some` for any PactMap result.

- [ ] **Step 6: Add explicit shared-demo types**

Define stable identifiers:

```ts
type ClientId = "a" | "b" | "c";
type DdsId =
  | "map"
  | "counter"
  | "gcounter"
  | "pn"
  | "ormap"
  | "or-map-mv-register"
  | "lww-map"
  | "lww-register"
  | "mv-register"
  | "orset"
  | "gset"
  | "twopset"
  | "claims"
  | "registers"
  | "ordered"
  | "tasks"
  | "pact";
```

Type the client record with generated state types. Include every current state
field and the DOM element:

```ts
interface DemoClient {
  id: ClientId;
  map: ReturnType<typeof mapKernel.from_sequenced>;
  gcounter: ReturnType<typeof gCounterStateFromSummary>;
  counterClientId: string;
  counterCore: ReturnType<typeof bootstrapCounterCore>["core"];
  pn: ResultValue<ReturnType<typeof pnKernel.from_summary>>;
  "lww-register": ReturnType<typeof lwwRegisterFromBaseline>;
  "lww-map": ReturnType<typeof lwwMapFromSummary>;
  "mv-register": ReturnType<typeof mvFromBaseline>;
  ormap: ResultValue<ReturnType<typeof orMapKernel.from_summary>>;
  "or-map-mv-register": ReturnType<typeof orMapMvFromBaseline>;
  orset: ResultValue<ReturnType<typeof orSetKernel.from_summary>>;
  gset: ResultValue<ReturnType<typeof gSetKernel.from_summary>>;
  twopset: ResultValue<ReturnType<typeof twoPSetKernel.from_summary>>;
  claims: ReturnType<typeof claimsBaseline>;
  registers: ReturnType<typeof registersBaseline>;
  ordered: ReturnType<typeof orderedBaseline>;
  taskmanager: ReturnType<typeof taskManagerBaseline>;
  pact: ReturnType<typeof pactBaseline>;
  el: HTMLElement;
  lastArrival: number;
  lastSeq: number;
}
```

Use `Record<ClientId, DemoClient>` for `clients`. Do not replace the record
with `Record<string, unknown>`.

- [ ] **Step 7: Narrow required markup once**

Add:

```ts
function required<T extends Element>(
  root: ParentNode,
  selector: string,
): T {
  const element = root.querySelector<T>(selector);
  if (!element) throw new Error(`Structure demo markup is missing ${selector}`);
  return element;
}
```

Use it for elements whose absence already makes the demo unusable, including
the rig, pace controls, status, client panes, row controls, and output fields.
Use ordinary nullable checks for optional controls.

- [ ] **Step 8: Resolve remaining generated API diagnostics**

For each compiler error:

- use generated state and operation types;
- narrow `Result` and `Option` through the shared helpers;
- preserve kernel domain `instanceof` checks;
- type callback payloads at the sequencer boundary;
- type DOM event targets with `instanceof Element` before `closest`;
- use exhaustive `DdsId` branches rather than a default cast.

Do not change transport timing, operation ordering, reset behavior, labels, or
rendered values.

- [ ] **Step 9: Run the type check**

Run:

```bash
cd website && pnpm check:types
```

Expected: PASS with `demo.ts` included.

- [ ] **Step 10: Run every shared-demo browser suite**

With the development server still running:

```bash
cd website && \
  pnpm test:mv-register-demo && \
  pnpm test:ormap-demo && \
  pnpm test:lww-map-demo && \
  pnpm test:or-map-mv-register-demo && \
  pnpm test:structure-demos
```

Expected: all tests pass, including PactMap load, proposal, and delete.

- [ ] **Step 11: Commit**

```bash
git add website/src/scripts/demo.js website/src/scripts/demo.ts \
  website/src/components/Demo.astro
git commit -m "refactor(site): type the shared demo"
```

---

### Task 6: Enforce the boundary in source and build gates

**Files:**
- Modify: `website/src/data/drift-gates.test.ts`
- Modify: `website/package.json`
- Modify: `justfile:84-94`

**Interfaces:**
- Consumes: `pnpm check:types` and the helper-only constructor import rule.
- Produces:
  - `build:gleam`: fresh JavaScript and declaration generation for both local Gleam packages.
  - `check:types`: `build:gleam`, snippet generation, then `tsc --noEmit`.
  - a drift gate that rejects raw Gleam container constructor imports outside `gleam-values.ts`.

- [ ] **Step 1: Write the drift-gate tests first**

Add tests to `website/src/data/drift-gates.test.ts`:

```ts
describe("Gate: Gleam Result and Option constructors stay behind the typed helper", () => {
  it("detects direct container constructor imports", () => {
    const fake = `
      import { Some } from "../../../build/dev/javascript/gleam_stdlib/gleam/option.mjs";
      import { Ok } from "../../../build/dev/javascript/watershed/gleam.mjs";
    `;
    assert.deepEqual(gleamContainerImports(fake), ["Ok", "Some"]);
  });

  it("allows generated domain constructors", () => {
    const fake = `
      import { Set } from "../../../build/dev/javascript/watershed/watershed/pact_map_kernel.mjs";
    `;
    assert.deepEqual(gleamContainerImports(fake), []);
  });
});
```

- [ ] **Step 2: Run the drift test to verify it fails**

Run:

```bash
cd website && node --strip-types --test src/data/drift-gates.test.ts
```

Expected: FAIL because `gleamContainerImports` does not exist.

- [ ] **Step 3: Implement constructor import detection**

Add:

```ts
const GLEAM_VALUE_HELPER = "src/scripts/demo/gleam-values.ts";
const GLEAM_CONTAINER_CONSTRUCTORS = new Set([
  "Error",
  "None",
  "Ok",
  "Some",
]);

function gleamContainerImports(source: string): string[] {
  const found = new Set<string>();
  const tokens =
    /"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|`(?:\\.|[^`\\])*`|\/\/[^\n]*|\/\*[\s\S]*?\*\/|\bimport\s+(type\s+)?(?:\{([\s\S]*?)\}|\*\s+as\s+([A-Za-z_$][\w$]*))\s+from\s+["']([^"']+)["']/g;
  let match;
  while ((match = tokens.exec(source)) !== null) {
    const [, typeOnly, namedBindings, namespaceBinding, modulePath] = match;
    if (
      (!namedBindings && !namespaceBinding) ||
      typeOnly ||
      !/(?:\/gleam(?:\/option)?|\/prelude)\.mjs$/.test(modulePath)
    ) {
      continue;
    }
    if (namespaceBinding) {
      found.add(`* as ${namespaceBinding}`);
      continue;
    }
    for (const binding of namedBindings.split(",")) {
      const trimmed = binding.trim();
      if (!trimmed || trimmed.startsWith("type ")) continue;
      const imported = trimmed.split(/\s+as\s+/)[0]?.trim();
      if (imported && GLEAM_CONTAINER_CONSTRUCTORS.has(imported)) {
        found.add(imported);
      }
    }
  }
  return [...found].sort();
}
```

Extend the authored-module gate. Skip only
`src/scripts/demo/gleam-values.ts`; every other authored website module must
return an empty list from `gleamContainerImports`.

- [ ] **Step 4: Run the drift test**

Run:

```bash
cd website && node --strip-types --test src/data/drift-gates.test.ts
```

Expected: PASS.

- [ ] **Step 5: Make type generation reusable**

Add:

```json
"build:gleam": "cd .. && gleam build --target javascript && cd watershed_lustre && gleam build --target javascript",
"check:types": "pnpm build:gleam && pnpm generate:snippets && tsc --noEmit",
```

Replace the duplicated Gleam build commands in `predev` and `prebuild`:

```json
"predev": "pnpm check:types",
"prebuild": "pnpm check:types && node --strip-types --test src/data/drift-gates.test.ts && node --strip-types --test src/data/copy-gates.test.ts",
```

The standalone `check:types` command must build fresh declarations and generate
the ignored snippet manifest before TypeScript resolves its JSON import. Do not
allow it to consume an old `build/` directory or require a pre-existing
`src/generated/snippets.json`.

- [ ] **Step 6: Add the root test gate**

Change the website test recipe in `justfile` to include `pnpm check:types`:

```just
_test-website-snippets: snippets
    cd website && pnpm check:types && pnpm test:snippet && pnpm test:snippet-manifest && pnpm test:practice-snippets && pnpm test:standalone-snippets && pnpm test:drift-gates && pnpm test:copy-gates && pnpm test:global-styles && pnpm test:netlify-contract && pnpm test:snippet-config
```

- [ ] **Step 7: Verify the source and build gates**

Run:

```bash
cd website && pnpm check:types
cd website && pnpm test:drift-gates
```

Expected: both commands pass.

- [ ] **Step 8: Prove the PactMap category error stops compilation**

Temporarily change one typed PactMap read in `demo.ts` from:

```ts
const accepted = resultValue(pactKernel.get_with_details(state, key));
```

to:

```ts
const accepted = optionValue(pactKernel.get_with_details(state, key));
```

Run:

```bash
cd website && pnpm check:types
```

Expected: FAIL because `Result<Accepted, undefined>` is not assignable to
`Option<Accepted>`.

Restore the correct `resultValue` call and run `pnpm check:types` again.

Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add website/src/data/drift-gates.test.ts website/package.json justfile
git commit -m "build(site): require Gleam type checks"
```

---

### Task 7: Run the complete verification gate

**Files:**
- Verify only.

**Interfaces:**
- Consumes: all tasks.
- Produces: evidence that declarations, type checks, runtime demos, and the production website build agree.

- [ ] **Step 1: Check formatting and patch integrity**

Run:

```bash
git diff --check
just format
git diff --check
```

Expected: all commands exit 0.

- [ ] **Step 2: Run the type and website data gates**

Run:

```bash
cd website && \
  pnpm check:types && \
  pnpm test:demo-boot && \
  pnpm test:rich-text-adapter && \
  pnpm test:drift-gates && \
  pnpm test:copy-gates
```

Expected: all commands pass.

- [ ] **Step 3: Run all browser demo suites**

Start the website in one shell:

```bash
cd website && pnpm dev --host 127.0.0.1
```

Run in another shell:

```bash
cd website && \
  pnpm test:mv-register-demo && \
  pnpm test:ormap-demo && \
  pnpm test:lww-map-demo && \
  pnpm test:or-map-mv-register-demo && \
  pnpm test:structure-demos
```

Expected: all demo tests pass with no page errors.

- [ ] **Step 4: Build the production website**

Stop the development server, then run:

```bash
cd website && pnpm build
```

Expected: declaration generation, `tsc --noEmit`, drift gates, copy gates, and
Astro build all pass.

- [ ] **Step 5: Run the repository test gate**

Run:

```bash
just test
```

Expected: all suites pass, except the documented unchanged
`smoke/runtime_bootstrap.mjs` baseline may still fail with
`Missing HTTP request /trees/`.

- [ ] **Step 6: Review the final diff**

Run:

```bash
git status --short
git diff --stat
git diff -- \
  gleam.toml \
  watershed_lustre/gleam.toml \
  website \
  justfile
```

Expected: only the typed Gleam boundary, required migrations, tests, package
metadata, and lockfile changes appear.

- [ ] **Step 7: Commit final formatting changes if needed**

If `just format` changed files after the task commits:

```bash
git add gleam.toml watershed_lustre/gleam.toml website justfile
git commit -m "style: format typed Gleam boundary"
```

Skip this commit when formatting made no changes.
