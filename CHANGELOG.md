# watershed changelog

## Unreleased

- **Breaking:** High-level SharedTree creation, opening, inspection, and
  resolution APIs accept `schema_builder.Root(a)` instead of `Compiled(a)`.
  Pass the root declaration directly; the API compiles it and reports
  declaration failures as `tree/error.InvalidSchema`. Explicit compilation
  remains available for snapshot codecs and low-level runtime APIs.
