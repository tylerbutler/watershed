@external(javascript, "./smoke_ffi.mjs", "log")
fn log(message: String) -> Nil

@external(javascript, "./smoke_ffi.mjs", "exit")
fn exit(code: Int) -> Nil

pub fn main() {
  log("smoke: grocery_triptych_lustre placeholder")
  exit(0)
  Nil
}
