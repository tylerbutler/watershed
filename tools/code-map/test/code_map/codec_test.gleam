import code_map/codec
import code_map/model
import gleam/json
import gleeunit/should

pub fn position_boundary_test() {
  json.parse("{\"line\":1,\"column\":2,\"byte\":3}", codec.position())
  |> should.equal(Ok(model.Position(1, 2, 3)))
  json.parse(
    "{\"line\":9007199254740992,\"column\":1,\"byte\":0}",
    codec.position(),
  )
  |> should.be_error
}

pub fn invalid_enum_test() {
  json.parse("\"typo\"", codec.kind()) |> should.be_error
}
