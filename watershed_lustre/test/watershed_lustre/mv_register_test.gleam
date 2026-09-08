import gleam/javascript/promise.{type Promise}
import gleam/list
import gleam/option.{Some}
import lustre/effect.{type Effect}
import watershed
import watershed/crdt_js
import watershed/mv_register_kernel as mv
import watershed/p2p
import watershed/p2p_transport_js
import watershed/schema
import watershed/sluice_js
import watershed/transport_js
import watershed_lustre
import watershed_lustre/crdt

type Fields

pub fn ensure_mv_register_defers_wrong_kind_failure_test() -> Promise(Nil) {
  let rig = sluice_js.start(tenant: "default", document: "mv-effect-error")
  let document = sluice_js.connect(rig, "a")
  sluice_js.settle(rig)
  let root = watershed.root(document)
  watershed.set(root, "slate", watershed.handle_of(root))
  sluice_js.settle(rig)
  let field: schema.ChannelField(Fields, schema.MvRegisterChannel) =
    schema.channel_field("slate")
  let sink = transport_js.new_cell([])
  run(
    watershed_lustre.ensure_mv_register(
      document,
      watershed.typed(root),
      field,
      Ensured,
    ),
    sink,
  )
  let assert [] = transport_js.get_cell(sink)
  list.repeat(Nil, 30) |> list.each(fn(_) { sluice_js.advance(rig, 200) })
  use _ <- promise.await(promise.wait(0))
  let assert [Ensured(Error("address does not name an MV-register channel"))] =
    transport_js.get_cell(sink)
  watershed.close(document)
  promise.resolve(Nil)
}

type Msg {
  Ensured(Result(watershed.MvRegister, String))
  Changed(mv.MvRegisterEvent)
  Subscribed(crdt_js.Subscription)
  Written(Result(Nil, p2p.P2pError))
}

fn run(effect: Effect(Msg), sink: transport_js.Cell(List(Msg))) -> Nil {
  effect.perform(
    effect,
    fn(message) {
      transport_js.set_cell(sink, [message, ..transport_js.get_cell(sink)])
    },
    fn(_, _) { Nil },
    fn(_) { Nil },
    fn() { panic as "unexpected root action" },
    fn(_, _) { Nil },
    fn(_, _) { Nil },
    fn(_) { Nil },
  )
}

pub fn sequenced_mv_effects_are_lazy_and_defer_local_and_remote_events_test() -> Promise(
  Nil,
) {
  let rig = sluice_js.start(tenant: "default", document: "mv-effects")
  let a = sluice_js.connect(rig, "a")
  let b = sluice_js.connect(rig, "b")
  sluice_js.settle(rig)
  let field: schema.ChannelField(Fields, schema.MvRegisterChannel) =
    schema.channel_field("slate")
  let sink = transport_js.new_cell([])
  let ensure =
    watershed_lustre.ensure_mv_register(
      a,
      watershed.typed(watershed.root(a)),
      field,
      Ensured,
    )
  let assert False = watershed.has(watershed.root(a), "slate")
  run(ensure, sink)
  let assert [] = transport_js.get_cell(sink)
  sluice_js.settle(rig)
  sluice_js.advance(rig, 200)
  let assert [] = transport_js.get_cell(sink)
  use _ <- promise.await(promise.wait(0))
  let assert [Ensured(Ok(register))] = transport_js.get_cell(sink)
  transport_js.set_cell(sink, [])
  let subscription = watershed_lustre.subscribe_mv_register(register, Changed)
  watershed.mv_register_set(register, "before subscription")
  sluice_js.settle(rig)
  use _ <- promise.await(promise.wait(0))
  let assert [] = transport_js.get_cell(sink)
  run(subscription, sink)
  watershed.mv_register_set(register, "local")
  sluice_js.settle(rig)
  let assert Ok(Some(peer)) =
    watershed.resolve_mv_register_field(
      b,
      watershed.typed(watershed.root(b)),
      field,
    )
  watershed.mv_register_set(peer, "remote")
  sluice_js.settle(rig)
  let assert [] = transport_js.get_cell(sink)
  use _ <- promise.await(promise.wait(0))
  let assert [
    Changed(mv.ValuesChanged(["remote"])),
    Changed(mv.ValuesChanged(["local"])),
  ] = transport_js.get_cell(sink)
  watershed.close(a)
  watershed.close(b)
  promise.resolve(Nil)
}

pub fn crdt_mv_subscription_and_write_effects_are_lazy_test() -> Promise(Nil) {
  let signaling =
    p2p_transport_js.Signaling(
      join: fn(room, peer, callback) {
        callback(p2p_transport_js.Roster([]))
        Ok(p2p_transport_js.signaling_session(room: room, peer_id: peer))
      },
      send: fn(_, _, _) { Nil },
      leave: fn(_) { Nil },
    )
  let assert Ok(document) =
    crdt_js.new_document(crdt_js.config(
      room_id: "mv-effects",
      replica_label: "a",
      compatibility_tag: "mv/v1",
      root: p2p.mv_register_root(),
      signaling: signaling,
    ))
  let root = crdt_js.root(document)
  let sink = transport_js.new_cell([])
  let subscribe = crdt.subscribe_mv_register(root, Subscribed, Changed)
  let assert Ok(Nil) = crdt_js.mv_register_set(root, "before")
  use _ <- promise.await(promise.wait(0))
  let assert [] = transport_js.get_cell(sink)
  run(subscribe, sink)
  let assert [] = transport_js.get_cell(sink)
  use _ <- promise.await(promise.wait(0))
  let assert [Subscribed(subscription)] = transport_js.get_cell(sink)
  transport_js.set_cell(sink, [])
  let write =
    crdt.perform(fn() { crdt_js.mv_register_set(root, "after") }, Written)
  let assert Ok(["before"]) = crdt_js.mv_register_values(root)
  run(write, sink)
  let assert [] = transport_js.get_cell(sink)
  use _ <- promise.await(promise.wait(0))
  let assert [Written(Ok(Nil)), Changed(mv.ValuesChanged(["after"]))] =
    transport_js.get_cell(sink)
  crdt_js.unsubscribe(subscription)
  transport_js.set_cell(sink, [])
  let assert Ok(Nil) = crdt_js.mv_register_set(root, "unsubscribed")
  use _ <- promise.await(promise.wait(0))
  let assert [] = transport_js.get_cell(sink)
  promise.resolve(Nil)
}
