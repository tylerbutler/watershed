# watershed_lustre changelog

## Unreleased

- **Breaking:** SharedTree `create`, `create_dev`, and `open` effects accept
  `schema_builder.Root(a)` declarations instead of `Compiled(a)`. Compilation
  runs when the effect is performed, and schema failures reach the existing
  result callback as `tree/error.InvalidSchema`.
