# Typed Gleam Website Boundary Design

## Goal

Make every website import of generated Gleam JavaScript subject to a
TypeScript check. A change to a Gleam function name, argument list, return
type, constructor, or record field must stop the website build before browser
code runs.

The PactMap failure defines the required result. TypeScript must reject code
that handles `Result(Accepted, Nil)` as `Option(Accepted)`.

## Current State

The website imports compiled `.mjs` modules from the root `build/` directory
and from `watershed_lustre/build/`. Most demo scripts use TypeScript, but the
shared structure demo remains `website/src/scripts/demo.js`.

Gleam emits JavaScript without declarations unless the package enables:

```toml
[javascript]
typescript_declarations = true
```

Astro and Vite bundle the current JavaScript successfully because they check
syntax and module resolution. They do not know the Gleam function signatures.
The website also has no required `tsc` command.

## Design

### Compiler-owned declarations

Enable `javascript.typescript_declarations` in the root package and in
`watershed_lustre`. Each JavaScript build will then emit `.d.mts` files beside
the generated `.mjs` files. Gleam applies the root setting to dependencies, so
direct imports from `gleam_stdlib`, `gleam_json`, and the lattice packages get
declarations during the same build.

The generated files remain under ignored build directories. The repository
will not commit or edit them.

### TypeScript website scripts

Rename `website/src/scripts/demo.js` to `demo.ts` and update its importer. All
website scripts that import generated Gleam modules will then use TypeScript.

Add `typescript` as an explicit website development dependency. Do not depend
on Astro's transitive TypeScript installation.

Keep the existing Astro base configuration and add the minimum compiler
options needed for a no-output check. The check includes `website/src/**` and
resolves imported `.mjs` modules through Gleam's adjacent `.d.mts` files.

### Gleam value helpers

Add one small TypeScript module for the common Gleam runtime values used by
the demos:

- extract the value from an `Ok`;
- extract a value from `Some`;
- construct `Some` and `None` values.

The helpers accept generated `Result` and `Option` types. Passing a `Result`
to the option helper, or an `Option` to the result helper, is a TypeScript
error. Demo code will stop using local `unknown` casts for these operations.

Only this module may import the generated `Some`, `None`, `Ok`, and `Error`
constructors. A website drift gate will reject direct imports elsewhere. This
rule prevents code from bypassing the typed helpers with an invalid runtime
constructor check.

The module will not define kernel types or copy Gleam function signatures.
Gleam remains the source of those declarations.

### Required build order

The website type check needs generated declarations, so commands must run in
this order:

1. Build the root package for JavaScript.
2. Build `watershed_lustre` for JavaScript.
3. Generate website snippets.
4. Run `tsc --noEmit`.
5. Run the Astro build.

Add a `check:types` package script and call it from `prebuild`. Development
startup will perform the same check after the Gleam builds. The root test
command will run the website type gate through the existing website test
family, so CI cannot omit it.

## Migration

Convert the shared demo without changing its behavior:

- add DOM types and null checks where the current JavaScript relies on runtime
  assumptions;
- replace raw `Result` and `Option` handling with the shared helpers;
- retain generated Gleam constructors for domain values through typed imports;
- keep transport, timing, rendering, and interaction logic unchanged.

Update the other TypeScript demo scripts to use the same helpers where they
currently cast `unknown` results. Fix type errors at the call site. Do not add
`any`, broad type assertions, or handwritten kernel declarations to silence
the compiler.

## Failure Handling

Generated declaration failures stop the Gleam build. Type errors stop
`check:types`. Neither command may substitute a stale declaration or continue
with an untyped module.

The existing prebuild sequence already compiles Gleam before the website. The
new gate uses those fresh outputs and does not need a declaration cache or a
fallback path.

## Verification

Add a compile-time contract fixture that imports PactMap and proves:

- `get_with_details` returns a `Result`;
- `set` and `delete` return `Result` values;
- the option extraction helper rejects those results;
- the result extraction helper accepts them.

Use `@ts-expect-error` only for the deliberately invalid assignments. The
TypeScript command must fail if Gleam declarations weaken enough to permit
the wrong assignment.

Keep the browser regression for PactMap accepted state, proposal settlement,
and deletion. The type test prevents the API category error; the browser test
checks the visible behavior.

Run the complete website demo suites and `pnpm build` after migration.

## Non-goals

- Publishing TypeScript declarations as a public Watershed package.
- Generating declarations with a third-party tool.
- Handwriting declarations for Gleam modules.
- Converting browser tests or Node scripts that do not import generated Gleam
  modules.
- Refactoring the shared demo beyond changes required for strict typing.
