import code_map
import gleam/list
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn finds_public_and_private_functions_test() {
  let assert Ok(symbols) =
    code_map.parse("pub fn open() { Nil }\nfn close() { Nil }\n")
  symbols
  |> list.map(fn(symbol) { symbol.name })
  |> should.equal(["open", "close"])
}

pub fn finds_types_constants_and_callable_bindings_test() {
  let source =
    "pub opaque type Box { Box(Int) }\ntype Alias = Int\nconst size = 1\nfn outer() { let inner = fn(x) { x } let captured = inner(_) captured(size) }"
  let assert Ok(symbols) = code_map.parse(source)
  symbols
  |> list.map(fn(symbol) { symbol.name })
  |> should.equal(["Box", "Alias", "size", "outer", "inner", "captured"])
}

pub fn preserves_target_variants_and_external_functions_test() {
  let source =
    "@target(erlang)\n@external(erlang, \"mod\", \"open\")\npub fn open() -> Nil\n@target(javascript)\npub fn open() { Nil }"
  let assert Ok(symbols) = code_map.parse(source)
  list.length(symbols) |> should.equal(2)
}

pub fn malformed_source_is_an_error_test() {
  code_map.parse("pub fn broken(") |> should.be_error
}
