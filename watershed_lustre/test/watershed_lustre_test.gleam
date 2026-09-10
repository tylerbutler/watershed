//// Test entrypoint and sequenced LWW-register effect tests.
////
//// The root `watershed` package runs on startest, but startest's dependency
//// tree pins `gleam_stdlib < 1.0` while this package (and lustre) are on 1.x,
//// so the two cannot share a harness. gleeunit resolves cleanly here and needs
//// no assertion library on Gleam 1.11+ — plain `assert` is enough.

import gleam/javascript/promise.{type Promise}
import gleam/json
import gleam/list
import gleam/option.{Some}
import gleeunit
import lustre/effect.{type Effect}
import watershed
import watershed/lww_register_kernel as lww
import watershed/schema
import watershed/sluice_js
import watershed/transport_js.{type Cell}
import watershed_lustre

pub fn main() -> Nil {
  gleeunit.main()
}

type Fields

type Msg {
  Ensured(Result(watershed.LwwRegister, String))
  Changed(lww.LwwRegisterEvent)
}

fn field() -> schema.ChannelField(Fields, schema.LwwRegisterChannel) {
  schema.channel_field("status")
}

fn run(effect_to_run: Effect(Msg), sink: Cell(List(Msg))) -> Nil {
  effect.perform(
    effect_to_run,
    fn(msg) {
      transport_js.set_cell(sink, [msg, ..transport_js.get_cell(sink)])
    },
    fn(_, _) { Nil },
    fn(_) { Nil },
    fn() { panic as "unexpected root action" },
    fn(_, _) { Nil },
    fn(_, _) { Nil },
    fn(_) { Nil },
  )
}

pub fn lww_register_sequenced_subscription_dispatches_on_a_microtask_test() -> Promise(
  Nil,
) {
  let rig = sluice_js.start(tenant: "default", document: "lww-effects")
  let a = sluice_js.connect(rig, "a")
  let b = sluice_js.connect(rig, "b")
  sluice_js.settle(rig)
  let assert Ok(register) = watershed.create_lww_register(a)
  watershed.set_lww_register_field(watershed.root_typed(a), field(), register)
  sluice_js.settle(rig)
  let assert Ok(Some(peer)) =
    watershed.resolve_lww_register_field(b, watershed.root_typed(b), field())
  let sink = transport_js.new_cell([])
  let subscription = watershed_lustre.subscribe_lww_register(register, Changed)
  let assert [] = transport_js.get_cell(sink)

  let assert Ok(Nil) = watershed.lww_register_set(register, "before")
  sluice_js.settle(rig)
  use _ <- promise.await(promise.wait(0))
  let assert [] = transport_js.get_cell(sink)

  run(subscription, sink)
  let assert [] = transport_js.get_cell(sink)
  let assert Ok(Nil) = watershed.lww_register_set(register, "local")
  sluice_js.settle(rig)
  let assert Ok(Nil) = watershed.lww_register_set(peer, "remote")
  sluice_js.settle(rig)
  let assert [] = transport_js.get_cell(sink)

  use _ <- promise.await(promise.wait(0))
  let assert [
    Changed(lww.Changed("local", "remote")),
    Changed(lww.Changed("before", "local")),
  ] = transport_js.get_cell(sink)
  let assert Ok("remote") = watershed.lww_register_value(register)
  let assert Ok("remote") = watershed.lww_register_value(peer)
  watershed.close(a)
  watershed.close(b)
  promise.resolve(Nil)
}

pub fn ensure_lww_register_does_not_mutate_during_update_test() -> Promise(Nil) {
  let rig = sluice_js.start(tenant: "default", document: "lww-ensure-effect")
  let document = sluice_js.connect(rig, "a")
  sluice_js.settle(rig)
  let sink = transport_js.new_cell([])
  let ensure =
    watershed_lustre.ensure_lww_register(
      document,
      watershed.root_typed(document),
      field(),
      Ensured,
    )
  let assert [] = transport_js.get_cell(sink)
  let assert False = watershed.has(watershed.root(document), "status")
  sluice_js.settle(rig)
  sluice_js.advance(rig, 200)
  use _ <- promise.await(promise.wait(0))
  let assert [] = transport_js.get_cell(sink)
  let assert False = watershed.has(watershed.root(document), "status")

  run(ensure, sink)
  let assert [] = transport_js.get_cell(sink)
  sluice_js.settle(rig)
  sluice_js.advance(rig, 200)
  let assert [] = transport_js.get_cell(sink)
  use _ <- promise.await(promise.wait(0))
  let assert [Ensured(Ok(register))] = transport_js.get_cell(sink)
  let assert Ok("") = watershed.lww_register_value(register)
  let assert Ok(Nil) = watershed.lww_register_set(register, "ready")
  sluice_js.settle(rig)

  transport_js.set_cell(sink, [])
  let adopt =
    watershed_lustre.ensure_lww_register(
      document,
      watershed.root_typed(document),
      field(),
      Ensured,
    )
  let assert [] = transport_js.get_cell(sink)
  run(adopt, sink)
  let assert [] = transport_js.get_cell(sink)
  use _ <- promise.await(promise.wait(0))
  let assert [Ensured(Ok(existing))] = transport_js.get_cell(sink)
  let assert Ok("ready") = watershed.lww_register_value(existing)
  watershed.close(document)
  promise.resolve(Nil)
}

pub fn ensure_lww_register_defers_invalid_handle_error_test() -> Promise(Nil) {
  let rig = sluice_js.start(tenant: "default", document: "lww-ensure-error")
  let document = sluice_js.connect(rig, "a")
  sluice_js.settle(rig)
  let root = watershed.root(document)
  watershed.set(root, "status", json.string("not a handle"))
  sluice_js.settle(rig)
  let sink = transport_js.new_cell([])
  let ensure =
    watershed_lustre.ensure_lww_register(
      document,
      watershed.root_typed(document),
      field(),
      Ensured,
    )
  let assert [] = transport_js.get_cell(sink)
  run(ensure, sink)
  let assert [] = transport_js.get_cell(sink)
  list.repeat(Nil, 30) |> list.each(fn(_) { sluice_js.advance(rig, 200) })
  let assert [] = transport_js.get_cell(sink)
  use _ <- promise.await(promise.wait(0))
  let assert [Ensured(Error(_reason))] = transport_js.get_cell(sink)
  watershed.close(document)
  promise.resolve(Nil)
}
