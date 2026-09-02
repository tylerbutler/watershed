//// Process exit with a status code.
////
//// Each target has an implementation, and each uses a function the runtime
//// supplies. No FFI module is necessary. The JavaScript implementation is
//// the one the tool uses, because the package compiles to JavaScript by
//// default. The Erlang implementation keeps the module correct for a build
//// that selects the Erlang target.

@external(erlang, "erlang", "halt")
@external(javascript, "node:process", "exit")
pub fn halt(code: Int) -> Nil
