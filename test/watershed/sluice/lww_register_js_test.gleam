@target(javascript)
import gleam/json
@target(javascript)
import gleam/option.{None, Some}
@target(javascript)
import gleam/result
@target(javascript)
import startest/expect
@target(javascript)
import watershed
@target(javascript)
import watershed/lww_register_kernel as lww
@target(javascript)
import watershed/schema
@target(javascript)
import watershed/sluice_js as sluice
@target(javascript)
import watershed/transport_js

@target(javascript)
type Fields

@target(javascript)
fn field() -> schema.ChannelField(Fields, schema.LwwRegisterChannel) {
  schema.channel_field("status")
}

@target(javascript)
pub fn public_lww_register_create_resolve_write_and_subscribe_test() -> Nil {
  let rig = sluice.start(tenant: "default", document: "lww-public")
  let a = sluice.connect(rig, "a")
  let b = sluice.connect(rig, "b")
  sluice.settle(rig)
  watershed.resolve_lww_register_field(a, watershed.root_typed(a), field())
  |> expect.to_equal(Ok(None))
  let assert Ok(register_a) = watershed.create_lww_register(a)
  watershed.lww_register_value(register_a) |> expect.to_equal(Ok(""))
  watershed.set_lww_register_field(watershed.root_typed(a), field(), register_a)
  sluice.settle(rig)
  let assert Ok(Some(register_b)) =
    watershed.resolve_lww_register_field(b, watershed.root_typed(b), field())
  let events_a = transport_js.new_cell([])
  let events_b = transport_js.new_cell([])
  let subscription_a =
    watershed.subscribe_lww_register(register_a, fn(event) {
      transport_js.set_cell(events_a, [event, ..transport_js.get_cell(events_a)])
    })
  let subscription_b =
    watershed.subscribe_lww_register(register_b, fn(event) {
      transport_js.set_cell(events_b, [event, ..transport_js.get_cell(events_b)])
    })
  watershed.lww_register_set(register_a, "first") |> expect.to_equal(Ok(Nil))
  watershed.lww_register_value(register_a) |> expect.to_equal(Ok("first"))
  sluice.settle(rig)
  watershed.lww_register_set(register_b, "second") |> expect.to_equal(Ok(Nil))
  sluice.settle(rig)
  watershed.lww_register_value(register_a) |> expect.to_equal(Ok("second"))
  watershed.lww_register_value(register_b) |> expect.to_equal(Ok("second"))
  let expected = [lww.Changed("first", "second"), lww.Changed("", "first")]
  transport_js.get_cell(events_a) |> expect.to_equal(expected)
  transport_js.get_cell(events_b) |> expect.to_equal(expected)
  let before = sluice.sequence_number(rig)
  watershed.lww_register_set(register_a, "second") |> expect.to_equal(Ok(Nil))
  sluice.settle(rig)
  sluice.sequence_number(rig) |> expect.to_equal(before + 1)
  transport_js.get_cell(events_a) |> expect.to_equal(expected)
  transport_js.get_cell(events_b) |> expect.to_equal(expected)
  watershed.unsubscribe(subscription_a)
  watershed.unsubscribe(subscription_b)
  watershed.lww_register_set(register_a, "final") |> expect.to_equal(Ok(Nil))
  sluice.settle(rig)
  watershed.lww_register_value(register_b) |> expect.to_equal(Ok("final"))
  transport_js.get_cell(events_a) |> expect.to_equal(expected)
  transport_js.get_cell(events_b) |> expect.to_equal(expected)
  watershed.close(a)
  watershed.close(b)
}

@target(javascript)
pub fn ensure_lww_register_waits_and_adopts_test() -> Nil {
  let rig = sluice.start(tenant: "default", document: "lww-ensure")
  let a = sluice.connect(rig, "a")
  let outcomes = transport_js.new_cell([])
  watershed.ensure_lww_register(a, watershed.root_typed(a), field(), fn(value) {
    transport_js.set_cell(outcomes, [value, ..transport_js.get_cell(outcomes)])
  })
  transport_js.get_cell(outcomes) |> expect.to_equal([])
  sluice.settle(rig)
  sluice.advance(rig, 200)
  sluice.settle(rig)
  sluice.advance(rig, 200)
  let assert [Ok(register_a)] = transport_js.get_cell(outcomes)
  watershed.lww_register_set(register_a, "ready") |> expect.to_equal(Ok(Nil))
  sluice.settle(rig)
  let b = sluice.connect(rig, "b")
  let adopted = transport_js.new_cell([])
  watershed.ensure_lww_register(b, watershed.root_typed(b), field(), fn(value) {
    transport_js.set_cell(adopted, [value, ..transport_js.get_cell(adopted)])
  })
  transport_js.get_cell(adopted) |> expect.to_equal([])
  sluice.settle(rig)
  sluice.advance(rig, 200)
  let assert [Ok(register_b)] = transport_js.get_cell(adopted)
  watershed.lww_register_handle_of(register_a)
  |> json.to_string
  |> expect.to_equal(
    watershed.lww_register_handle_of(register_b) |> json.to_string,
  )
  watershed.lww_register_value(register_b) |> expect.to_equal(Ok("ready"))
  watershed.close(a)
  watershed.close(b)
}

@target(javascript)
pub fn reconnect_preserves_pending_lww_write_test() -> Nil {
  let rig = sluice.start(tenant: "default", document: "lww-reconnect")
  let a = sluice.connect(rig, "a")
  let b = sluice.connect(rig, "b")
  sluice.settle(rig)
  let assert Ok(register_a) = watershed.create_lww_register(a)
  watershed.set_lww_register_field(watershed.root_typed(a), field(), register_a)
  sluice.settle(rig)
  let assert Ok(Some(register_b)) =
    watershed.resolve_lww_register_field(b, watershed.root_typed(b), field())
  sluice.drop(rig, a)
  watershed.lww_register_set(register_a, "offline") |> expect.to_equal(Ok(Nil))
  watershed.diagnostics(a).in_flight_count |> expect.to_equal(1)
  watershed.lww_register_set(register_b, "online") |> expect.to_equal(Ok(Nil))
  // Advance B past A even when both writes use the same wall-clock millisecond.
  watershed.lww_register_set(register_b, "online") |> expect.to_equal(Ok(Nil))
  sluice.settle(rig)
  watershed.lww_register_value(register_a) |> expect.to_equal(Ok("offline"))
  watershed.lww_register_value(register_b) |> expect.to_equal(Ok("online"))
  sluice.rejoin(rig, a)
  sluice.settle(rig)
  // Restamping A after replay would incorrectly replace B's newer value.
  watershed.lww_register_value(register_a) |> expect.to_equal(Ok("online"))
  watershed.lww_register_value(register_b) |> expect.to_equal(Ok("online"))
  watershed.diagnostics(a).in_flight_count |> expect.to_equal(0)
  watershed.is_synced(a) |> expect.to_be_true()
  watershed.close(a)
  watershed.close(b)
}

@target(javascript)
pub fn lww_register_wrong_kind_handle_fails_reads_and_writes_test() -> Nil {
  let rig = sluice.start(tenant: "default", document: "lww-wrong-kind")
  let document = sluice.connect(rig, "a")
  sluice.settle(rig)
  let root = watershed.root(document)
  let assert Ok(register) =
    watershed.resolve_lww_register(document, watershed.handle_of(root))
  watershed.lww_register_value(register) |> expect.to_equal(Error(Nil))
  watershed.lww_register_set(register, "wrong")
  |> result.is_error
  |> expect.to_be_true()
  watershed.diagnostics(document).in_flight_count |> expect.to_equal(0)
  let events = transport_js.new_cell([])
  let subscription =
    watershed.subscribe_lww_register(register, fn(event) {
      transport_js.set_cell(events, [event, ..transport_js.get_cell(events)])
    })
  watershed.set(root, "plain", json.string("map value"))
  sluice.settle(rig)
  transport_js.get_cell(events) |> expect.to_equal([])
  watershed.unsubscribe(subscription)
  watershed.resolve_lww_register(document, json.string("not a handle"))
  |> result.is_error
  |> expect.to_be_true()
  watershed.resolve_lww_register(
    document,
    json.object([
      #("type", json.string("__fluid_handle__")),
      #("url", json.string("/missing")),
    ]),
  )
  |> result.is_error
  |> expect.to_be_true()
  watershed.close(document)
}
