//// Test entrypoint and sequenced LWW-register effect tests.
////
//// The root `watershed` package runs on startest, but startest's dependency
//// tree pins `gleam_stdlib < 1.0` while this package (and lustre) are on 1.x,
//// so the two cannot share a harness. gleeunit resolves cleanly here and needs
//// no assertion library on Gleam 1.11+ — plain `assert` is enough.

import gleam/javascript/promise.{type Promise}
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleeunit
import lustre/effect.{type Effect}
import watershed
import watershed/lww_register_kernel as lww
import watershed/or_map_kernel as or_map
import watershed/schema
import watershed/sluice_js
import watershed/transport_js.{type Cell}
import watershed_lustre
import watershed_lustre/crdt

pub fn main() -> Nil {
  gleeunit.main()
}

type Fields

type Msg {
  Ensured(Result(watershed.LwwRegister, String))
  Changed(lww.LwwRegisterEvent)
}

type SetMapMsg {
  MapEnsured(Result(watershed.OrMap, String))
  MapChanged(or_map.OrMapEvent)
  MapOutcome(Result(Nil, String))
}

fn map_field() -> schema.ChannelField(Fields, schema.OrMapChannel) {
  schema.channel_field("documents")
}

fn field() -> schema.ChannelField(Fields, schema.LwwRegisterChannel) {
  schema.channel_field("status")
}

fn run(effect_to_run: Effect(msg), sink: Cell(List(msg))) -> Nil {
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

pub fn set_map_ensure_is_lazy_and_adopts_the_typed_field_test() -> Promise(Nil) {
  let rig =
    sluice_js.start(tenant: "default", document: "set-map-ensure-effect")
  let a = sluice_js.connect(rig, "a")
  let b = sluice_js.connect(rig, "b")
  sluice_js.settle(rig)
  let sink = transport_js.new_cell([])
  let ensure =
    watershed_lustre.ensure_or_map(
      a,
      watershed.root_typed(a),
      map_field(),
      or_map.OrSetMode,
      MapEnsured,
    )
  sluice_js.settle(rig)
  sluice_js.advance(rig, 200)
  use _ <- promise.await(promise.wait(0))
  let assert [] = transport_js.get_cell(sink)
  let assert Ok(None) =
    watershed.resolve_or_map_field(a, watershed.root_typed(a), map_field())
  run(ensure, sink)
  sluice_js.settle(rig)
  sluice_js.advance(rig, 200)
  let assert [] = transport_js.get_cell(sink)
  use _ <- promise.await(promise.wait(0))
  let assert [MapEnsured(Ok(map))] = transport_js.get_cell(sink)
  let assert Ok(Nil) = watershed.or_map_add_member(map, "doc", "draft")
  sluice_js.settle(rig)
  transport_js.set_cell(sink, [])
  let adopt =
    watershed_lustre.ensure_or_map(
      b,
      watershed.root_typed(b),
      map_field(),
      or_map.OrSetMode,
      MapEnsured,
    )
  let assert [] = transport_js.get_cell(sink)
  run(adopt, sink)
  let assert [] = transport_js.get_cell(sink)
  use _ <- promise.await(promise.wait(0))
  let assert [MapEnsured(Ok(peer))] = transport_js.get_cell(sink)
  assert json.to_string(watershed.or_map_handle_of(map))
    == json.to_string(watershed.or_map_handle_of(peer))
  let assert Ok(or_map.SetMembers(["draft"])) =
    watershed.or_map_value(peer, "doc")
  watershed.close(a)
  watershed.close(b)
  promise.resolve(Nil)
}

pub fn set_map_sequenced_effects_defer_edits_events_and_outcomes_test() -> Promise(
  Nil,
) {
  let rig = sluice_js.start(tenant: "default", document: "set-map-effects")
  let a = sluice_js.connect(rig, "a")
  let b = sluice_js.connect(rig, "b")
  sluice_js.settle(rig)
  let assert Ok(map) = watershed.create_or_map(a, or_map.OrSetMode)
  watershed.set_or_map_field(watershed.root_typed(a), map_field(), map)
  sluice_js.settle(rig)
  let assert Ok(Some(peer)) =
    watershed.resolve_or_map_field(b, watershed.root_typed(b), map_field())
  let sink = transport_js.new_cell([])
  let subscription = watershed_lustre.subscribe_or_map(map, MapChanged)
  let assert Ok(Nil) = watershed.or_map_add_member(map, "doc", "draft")
  sluice_js.settle(rig)
  use _ <- promise.await(promise.wait(0))
  let assert [] = transport_js.get_cell(sink)
  run(subscription, sink)
  let add =
    crdt.perform(
      fn() { watershed.or_map_add_member(map, "doc", "approved") },
      MapOutcome,
    )
  let assert Ok(or_map.SetMembers(["draft"])) =
    watershed.or_map_value(map, "doc")
  let assert [] = transport_js.get_cell(sink)
  run(add, sink)
  let assert Ok(or_map.SetMembers(["approved", "draft"])) =
    watershed.or_map_value(map, "doc")
  let assert [] = transport_js.get_cell(sink)
  sluice_js.settle(rig)
  use _ <- promise.await(promise.wait(0))
  let assert [
    MapOutcome(Ok(Nil)),
    MapChanged(or_map.SetMembersUpdated("doc", ["approved", "draft"])),
  ] = transport_js.get_cell(sink)
  transport_js.set_cell(sink, [])
  run(add, sink)
  sluice_js.settle(rig)
  let assert [] = transport_js.get_cell(sink)
  use _ <- promise.await(promise.wait(0))
  let assert [MapOutcome(Ok(Nil))] = transport_js.get_cell(sink)
  transport_js.set_cell(sink, [])
  let assert Ok(Nil) = watershed.or_map_remove_member(peer, "doc", "draft")
  sluice_js.settle(rig)
  let assert [] = transport_js.get_cell(sink)
  use _ <- promise.await(promise.wait(0))
  let assert [MapChanged(or_map.SetMembersUpdated("doc", ["approved"]))] =
    transport_js.get_cell(sink)
  transport_js.set_cell(sink, [])
  let remove =
    crdt.perform(fn() { watershed.or_map_remove_key(map, "doc") }, MapOutcome)
  let assert Ok(or_map.SetMembers(["approved"])) =
    watershed.or_map_value(map, "doc")
  run(remove, sink)
  let assert Error(Nil) = watershed.or_map_value(map, "doc")
  let assert [] = transport_js.get_cell(sink)
  sluice_js.settle(rig)
  use _ <- promise.await(promise.wait(0))
  let assert [MapOutcome(Ok(Nil)), MapChanged(or_map.KeyRemoved("doc"))] =
    transport_js.get_cell(sink)
  watershed.close(a)
  watershed.close(b)
  promise.resolve(Nil)
}

pub fn set_map_sequenced_perform_preserves_wrong_mode_and_closed_errors_test() -> Promise(
  Nil,
) {
  let rig =
    sluice_js.start(tenant: "default", document: "set-map-effect-errors")
  let document = sluice_js.connect(rig, "a")
  sluice_js.settle(rig)
  let assert Ok(map) = watershed.create_or_map(document, or_map.TallyMode)
  let sink = transport_js.new_cell([])
  let edit =
    crdt.perform(
      fn() { watershed.or_map_add_member(map, "doc", "draft") },
      MapOutcome,
    )
  run(edit, sink)
  let assert [] = transport_js.get_cell(sink)
  use _ <- promise.await(promise.wait(0))
  let assert [MapOutcome(Error(_))] = transport_js.get_cell(sink)
  let assert [] = watershed.or_map_entries(map)
  transport_js.set_cell(sink, [])
  watershed.close(document)
  run(
    crdt.perform(fn() { watershed.or_map_remove_key(map, "doc") }, MapOutcome),
    sink,
  )
  let assert [] = transport_js.get_cell(sink)
  use _ <- promise.await(promise.wait(0))
  let assert [MapOutcome(Error(_))] = transport_js.get_cell(sink)
  promise.resolve(Nil)
}

pub fn set_map_ensure_defers_invalid_field_outcome_test() -> Promise(Nil) {
  let rig = sluice_js.start(tenant: "default", document: "set-map-ensure-error")
  let document = sluice_js.connect(rig, "a")
  sluice_js.settle(rig)
  watershed.set(watershed.root(document), "documents", json.string("invalid"))
  sluice_js.settle(rig)
  let sink = transport_js.new_cell([])
  let ensure =
    watershed_lustre.ensure_or_map(
      document,
      watershed.root_typed(document),
      map_field(),
      or_map.OrSetMode,
      MapEnsured,
    )
  run(ensure, sink)
  let assert [] = transport_js.get_cell(sink)
  list.repeat(Nil, 30) |> list.each(fn(_) { sluice_js.advance(rig, 200) })
  let assert [] = transport_js.get_cell(sink)
  use _ <- promise.await(promise.wait(0))
  let assert [MapEnsured(Error(_))] = transport_js.get_cell(sink)
  watershed.close(document)
  promise.resolve(Nil)
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
