//// Capture application callback failures at a runtime boundary.

@external(erlang, "watershed_callback_ffi", "capture")
@external(javascript, "./callback_ffi.mjs", "capture")
fn capture_ffi(
  work: fn() -> value,
  on_success: fn(value) -> Result(value, String),
  on_error: fn(String) -> Result(value, String),
) -> Result(value, String)

pub fn capture(work: fn() -> value) -> Result(value, String) {
  capture_ffi(work, Ok, Error)
}
