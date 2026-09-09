//// JavaScript API boundary. Core errors become JavaScript exceptions here.

import code_map/codec
import code_map/model
import gleam/dynamic/decode
import gleam/json

@external(javascript, "../code_map_ffi.mjs", "raise_error")
fn raise_error(message: String) -> a

fn for_javascript(value: Result(a, model.Error)) -> a {
  case value {
    Ok(value) -> value
    Error(error) -> raise_error(model.error_message(error))
  }
}

pub fn decode_index(value: decode.Dynamic) -> model.Index {
  codec.decode_index(value) |> for_javascript
}

pub fn encode_index(value: model.Index) -> json.Json {
  codec.encode_index(value)
}
