//// Internal boundaries for JavaScript application callbacks.

@target(javascript)
@external(javascript, "./callback_ffi.mjs", "capture")
fn capture_ffi(
  work: fn() -> value,
  on_success: fn(value) -> Result(value, String),
  on_error: fn(String) -> Result(value, String),
) -> Result(value, String)

@target(javascript)
/// Invoke application code and return its exception as an error.
pub fn capture(work: fn() -> value) -> Result(value, String) {
  capture_ffi(work, Ok, Error)
}

@target(javascript)
/// Report a callback failure through the platform error reporter.
@external(javascript, "./callback_ffi.mjs", "report")
pub fn report(reason: String) -> Nil
