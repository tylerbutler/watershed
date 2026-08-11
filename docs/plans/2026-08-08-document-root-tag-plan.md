# Document root-tag plan — make the root map's schema checkable

**Status: shipped 2026-08-10.** DR1–DR6 all landed, DR6 included — the
compile-fail fixture lives at `tools/compile-fail/two_root_tags` and runs as
`just _test-compile-fail`, wired into `just test`. Two deviations from the plan
below, both scope only: the examples had grown from five to twelve (nine
already carried a usable tag in their `doc_schema.gleam`), and the `just build`
gate had to be repaired first — `dice_lustre` pinned a broken pnpm release and
`sudoku_lustre`'s manifest pinned a stale spillway commit, neither related to
this change.

**Date:** 2026-08-08
**Builds on:** `2026-07-06-typed-layer-dx-plan.md` (the phantom-tag design this extends to the one place it never reached).
**Blocks (softly):** `2026-08-08-showcase-composition-plan.md` — the showcase is the first app in this repo with more than one schema tag in play, and so the first place the gap does real damage. Best landed before SC1; the showcase's SC7 root-purity test is the stopgap if it isn't.

**Prerequisite work: none.** This is a type-level change with no runtime component and no kernel involvement.

## The gap

```gleam
pub fn root_typed(document: Document) -> TypedMap(s)   // src/watershed.gleam:420
```

`s` is free and unconstrained by any argument, so the caller picks it. Two different demos can each call `root_typed` on the same document, get `TypedMap(PlaylistDoc)` and `TypedMap(SudokuDoc)` for the same physical map, and share one key namespace with no diagnostic. Every other typed-layer entry point that hands out a tagged handle is pinned by an argument — `resolve_child` and `ensure_child` take the `ChildField(s, c)` that names the child tag, and `create_typed_map`/`typed` are self-correcting because the tag unifies at the store site (`set_child` demands the field's child tag). `root_typed` is the only unpinned handle to a map with a stable identity, which is why it is the only one that bites.

The typed layer's premise is that a map's shape is checked. The root map is the one map in every document, and it is the one map the premise does not cover.

## The fix

A phantom parameter on `Document`:

```gleam
pub opaque type Document(root) {
  Document(runtime: runtime_js.Runtime)   // unchanged — `root` is never stored
}

pub fn root_typed(document: Document(root)) -> TypedMap(root)
```

Nothing in the runtime changes; `root` appears only in signatures.

**Why this pins the tag when nothing else does.** Phantom tags in Gleam are only ever inferred from an annotation at a use site — there is no definition site that fixes one. Any alternative that invents a token to carry the tag (`schema.root()`, a `RootSchema(s)` handed to `connect`) is itself generic in the tag and moves the problem one call up rather than solving it. Threading the tag through `Document` works because an app is *already forced* to write the type concretely: in the `Msg` constructor that carries the handle (`GotHandle(Document(Showcase))`) or in the `Model` field that holds it. Every `root_typed` call on that value then unifies with `Showcase`, and a second tag is a compile error. An app that dodges the annotation by leaving `root` free must parameterize `Msg`, then `Model`, then `init`/`update`/`view` — contagious enough that nobody does it by accident.

**The property that matters most for the showcase:** a component generic in `root` can still call `root_typed`, but it has no fields for an abstract tag and so can do nothing with the result. Panel components become *structurally* unable to touch the root, rather than merely asked not to.

**What it does not fix.** `typed(root(doc))` still produces any tag you like (`src/watershed_js.gleam:415`). That is the documented cast and it should stay — the change turns the mistake from invisible into a one-line grep.

## Decisions already made (flagged — confirm before DR1)

1. **Parameter named `root`.** `Document(root)`, not `Document(s)` — `s` reads as "some schema" everywhere else in the typed layer, and this one is specifically the *root's* schema.
2. **Both facades, same shape.** `watershed.gleam` and `watershed_js.gleam` change together even though only the JS side has a composing app today. Facade divergence is the failure mode `facade_parity_test.gleam` exists to prevent, and letting the BEAM side lag would be a new instance of it.
3. **`presence_js` stops storing the `Document`.** Its private `Driver(a)` holds one (`src/watershed/presence_js.gleam:37`), so a parameterized `Document` would force `Driver(root, a)` and, through `Handle(cell: Cell(Driver(a)))`, a public `Handle(root, a)` — a root-schema tag leaking into the presence API, which every app annotates in its model (`examples/text_lustre/src/text_lustre.gleam:151`). Instead the driver stores the broadcast closure it actually needs (`fn(Json) -> Nil`, closing over the document at `start`). The tag is erased at that boundary, `Handle(a)` keeps its arity, and the driver ends up depending on "a way to send a ripple" rather than on a whole document — which is the better factoring regardless.
4. **JS/TS consumers are unaffected.** Gleam types erase, so the website's direct `.mjs` imports (`website/src/scripts/rich-text-demo.ts`) need no change. This is a source-compatibility break for Gleam callers only.
5. **Do it now.** Roughly 230 type-position mentions of `Document` repo-wide — `src/watershed/rich_text.gleam` has its own unrelated `Document` type and is excluded — of which 179 are inside the two facades and purely mechanical. At `0.1.0`, with no external consumers, this is the cheapest it will ever be, and it gets dearer every month.

## Rungs

The change is one type, so it cannot land file-by-file within a target. It splits cleanly by target and by package.

- **DR1 — JS facade.** `Document` → `Document(root)` in `watershed_js.gleam`; `root_typed` returns `TypedMap(root)`; `presence_js` refactored per decision 3; `sluice_js`'s `connect`/`pause`/`resume` become generic in `root` (they only pass it through). Gate: root package builds on the JavaScript target; the existing presence tests pass unchanged, which is the check that decision 3's refactor is behaviour-preserving.
- **DR2 — `watershed_lustre`.** ~24 signature sites, all pass-through. Gate: `just _test-lustre`.
- **DR3 — examples.** Five apps plus their smoke tests annotate the facade `Document` directly; each gains a concrete root tag. `dice_lustre` and `sudoku_lustre` have no root schema module today — give them a tag rather than inventing fields, since a tag with no fields is exactly right for an app whose root holds untyped keys. Gate: `just build` and every example smoke test.
- **DR4 — BEAM facade.** `watershed.gleam`, `sluice.gleam`, and any test that annotates `Document` (most infer it and will need no edit). Gate: `gleam test`, and confirm `facade_parity_test` is still green — it matches on function names read from source text, so a type parameter should be transparent to it, but confirm rather than assume.
- **DR5 — docs.** The `root_typed` doc comment gains the "one tag per document, pinned at your `Msg`/`Model`" explanation; `src/watershed/schema.gleam`'s module header gains a line on the root being tagged like any other map; README and any website guide page showing `root_typed` get the annotation. Include the `typed(root(doc))` escape hatch and why it stays.
- **DR6 — the negative test.** A fixture package that calls `root_typed` twice on one document with two tags, plus a `just` recipe asserting the build *fails*. There is no compile-fail harness in this repo today, so treat this as optional: if it turns fiddly, drop it, note the omission in DR5's docs, and let the showcase's root-purity test carry the regression coverage instead. Do not let it hold up DR1–DR5.

## Testing strategy

There is no behaviour here, so most of the value is in what still passes. The full existing suite — `gleam test`, `just _test-lustre`, every example smoke test, the parity test — is the assertion that this is a pure type change. Two things are genuinely new:

- **The presence refactor is the only rung with runtime risk.** Decision 3 changes what `Driver` stores and when the document is captured. The existing presence tests cover it; if they turn out to be thin on the heartbeat/rebroadcast path, thicken them *before* DR1 rather than after.
- **DR6's compile-fail fixture**, if it survives contact.

## Cost, honestly

Around 230 annotation sites, ~180 of them mechanical facade edits, and a source-compatibility break for every Gleam caller. In exchange: one class of silent bug becomes a compile error, components become structurally unable to reach the root, and the typed layer's premise finally covers the one map every document has. The alternative on the table — a witness argument, `root_typed(doc, doc_schema.text())` — touches one function and about six call sites, but enforces nothing; it only makes a foreign tag at the root require naming a foreign schema's field out loud. It is not worth spending a breaking change on a half-measure.
