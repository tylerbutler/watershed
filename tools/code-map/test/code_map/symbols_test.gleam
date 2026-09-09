import code_map
import code_map/model
import code_map/symbols
import gleam/list
import gleeunit/should

pub fn shared_identity_test() {
  let assert Ok(parsed) =
    code_map.extract(
      "a.gleam",
      "fn outer() { let inner = fn(x) { x } inner(1) }",
    )
  let assert [outer, inner] = parsed.symbols
  outer.qualified_name |> should.equal("a.gleam::outer")
  inner.qualified_name |> should.equal("a.gleam::outer.inner")
  inner.declaration.container |> should.equal(["outer"])
  inner.id |> should.equal(model.symbol_id("a.gleam", inner.declaration))
  symbols.normalize_parse(
    "a.gleam",
    list.map(parsed.symbols, fn(s) { s.declaration }),
    [],
    [],
  )
  |> should.equal(Ok(parsed))
}

pub fn source_error_is_not_a_boundary_error_test() {
  let assert Ok(parsed) = code_map.extract("a.gleam", "fn broken(")
  parsed.symbols |> should.equal([])
  list.length(parsed.diagnostics) |> should.equal(1)
}
