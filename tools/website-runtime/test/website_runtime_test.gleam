import gleeunit
import website_runtime

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn bootstraps_the_atlas_counter_core_test() -> Nil {
  let assert Ok(core) =
    website_runtime.counter_core("demo-client-a", "sandbags-counter", 120)
  let assert Ok(120) = website_runtime.counter_value(core, "sandbags-counter")
  let assert Ok(website_runtime.CounterChange(next, write)) =
    website_runtime.counter_increment(core, "sandbags-counter", 5)
  let website_runtime.CounterPending(count, delta) =
    website_runtime.counter_pending(next, "sandbags-counter")
  let assert 1 = count
  let assert 5 = delta
  let assert Ok(delivered) =
    website_runtime.deliver_counter(next, "demo-client-a", 1, write)
  let assert Ok(125) =
    website_runtime.counter_value(delivered, "sandbags-counter")
  Nil
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
