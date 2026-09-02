//// Minimal Erlang halt for nonzero process exits.

@external(erlang, "erlang", "halt")
pub fn halt(code: Int) -> Nil
