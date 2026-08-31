//// Focused p2p tests for `watershed_lustre/textarea`.
////
//// The textarea's `Msg` stays opaque, so these tests exercise the p2p path
//// through the component's real effect boundary: subscribe with `init_crdt`,
//// capture the dispatched opaque messages, feed them back through
//// `textarea.update`, and assert on the public accessors.

import gleam/javascript/promise.{type Promise}
import gleam/list
import gleam/option.{None}

import lustre/effect.{type Effect}

import watershed/crdt_js.{type CrdtDocument}
import watershed/p2p
import watershed/p2p_transport_js.{type Signaling, Roster, Signaling}
import watershed/schema
import watershed/transport_js.{type Cell}

import watershed_lustre/textarea

fn solo_signaling() -> Signaling {
  Signaling(
    join: fn(room, peer, on_signal) {
      on_signal(Roster([]))
      Ok(p2p_transport_js.signaling_session(room: room, peer_id: peer))
    },
    send: fn(_session, _to, _payload) { Nil },
    leave: fn(_session) { Nil },
  )
}

fn text_document() -> CrdtDocument(schema.TextChannel) {
  let assert Ok(document) =
    crdt_js.new_document(crdt_js.config(
      room_id: "textarea-p2p-test",
      replica_label: "tab",
      compatibility_tag: "textarea-p2p/v1",
      root: p2p.text_root(),
      signaling: solo_signaling(),
    ))
  document
}

fn run(
  effect_to_run: Effect(textarea.Msg),
  sink: Cell(List(textarea.Msg)),
) -> Nil {
  effect.perform(
    effect_to_run,
    fn(msg) {
      transport_js.set_cell(sink, [msg, ..transport_js.get_cell(sink)])
    },
    fn(_name, _json) { Nil },
    fn(_selector) { Nil },
    fn() { panic as "root action is unused by textarea tests" },
    fn(_name, _json) { Nil },
    fn(_name, _decoder) { Nil },
    fn(_name) { Nil },
  )
}

fn new_sink() -> Cell(List(textarea.Msg)) {
  transport_js.new_cell([])
}

fn messages(sink: Cell(List(textarea.Msg))) -> List(textarea.Msg) {
  list.reverse(transport_js.get_cell(sink))
}

fn clear(sink: Cell(List(textarea.Msg))) -> Nil {
  transport_js.set_cell(sink, [])
}

fn drain(
  model: textarea.Editor(channel),
  sink: Cell(List(textarea.Msg)),
) -> textarea.Editor(channel) {
  let next =
    list.fold(messages(sink), model, fn(model, msg) {
      let #(updated, _effect) = textarea.update(model, msg)
      updated
    })

  clear(sink)
  next
}

fn flush() -> Promise(Nil) {
  promise.wait(0)
}

pub fn init_crdt_snapshots_existing_text_and_exposes_a_typed_handle_test() -> Nil {
  let document = text_document()
  let handle = crdt_js.root(document)
  let assert Ok(Nil) = crdt_js.text_append(handle, "hello")

  let #(model, _effect) = textarea.init_crdt(handle)

  assert textarea.value(model) == "hello"
  assert textarea.length(model) == 5
  let assert Ok(value) = crdt_js.text_value(textarea.channel(model))
  assert value == "hello"
}

pub fn init_crdt_subscribes_and_replays_text_events_test() -> Promise(Nil) {
  let document = text_document()
  let handle = crdt_js.root(document)
  let #(model, subscribed) = textarea.init_crdt(handle)
  let sink = new_sink()

  run(subscribed, sink)
  let assert [] = messages(sink)

  use _ <- promise.await(flush())
  let model = drain(model, sink)

  let assert Ok(Nil) = crdt_js.text_append(textarea.channel(model), "p2p")
  let assert [] = messages(sink)

  use _ <- promise.await(flush())
  let model = drain(model, sink)

  assert textarea.value(model) == "p2p"
  assert textarea.length(model) == 3
  assert textarea.error(model) == None

  promise.resolve(Nil)
}
