import gleeunit
import website_runtime

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn starts_and_resolves_clients_test() -> Nil {
  let assert Ok(runtime) =
    website_runtime.start("website", "runtime-test", ["a", "b", "c"])
  website_runtime.settle(runtime)

  let assert Ok(_) = website_runtime.client(runtime, "a")
  let assert Ok(_) = website_runtime.client(runtime, "b")
  let assert Ok(_) = website_runtime.client(runtime, "c")
  let assert Error("unknown client: missing") =
    website_runtime.client(runtime, "missing")
  let assert False = website_runtime.pending(runtime)
  Nil
}
