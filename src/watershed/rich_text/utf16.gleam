//// UTF-16 offsets are the wire/index unit used by Quill Delta.

@external(erlang, "watershed_rich_text_utf16", "length")
@external(javascript, "./utf16_ffi.mjs", "length")
pub fn length(value: String) -> Int

@external(erlang, "watershed_rich_text_utf16", "valid")
@external(javascript, "./utf16_ffi.mjs", "valid")
pub fn valid(value: String) -> Bool

@external(erlang, "watershed_rich_text_utf16", "boundary")
@external(javascript, "./utf16_ffi.mjs", "boundary")
pub fn boundary(value: String, offset: Int) -> Bool

@external(erlang, "watershed_rich_text_utf16", "slice")
@external(javascript, "./utf16_ffi.mjs", "slice")
fn slice_unchecked(value: String, start: Int, size: Int) -> String

/// Returns a UTF-16 slice only when both endpoints are scalar boundaries.
pub fn slice(value: String, start: Int, size: Int) -> Result(String, Nil) {
  let end = start + size
  case
    start >= 0
    && size >= 0
    && end <= length(value)
    && boundary(value, start)
    && boundary(value, end)
  {
    True -> Ok(slice_unchecked(value, start, size))
    False -> Error(Nil)
  }
}
