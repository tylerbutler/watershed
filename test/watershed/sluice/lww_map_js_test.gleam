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
import watershed/lww_map_kernel as lww
@target(javascript)
import watershed/schema
@target(javascript)
import watershed/sluice_js as sluice
@target(javascript)
import watershed/transport_js

@target(javascript)
type Fields

@target(javascript)
fn field() -> schema.ChannelField(Fields, schema.LwwMapChannel) {
  schema.channel_field("settings")
}

@target(javascript)
pub fn public_lww_map_typed_lifecycle_test() -> Nil {
  let rig = sluice.start(tenant: "default", document: "lww-map-public")
  let a = sluice.connect(rig, "a")
  let b = sluice.connect(rig, "b")
  sluice.settle(rig)
  watershed.resolve_lww_map_field(a, watershed.root_typed(a), field())
  |> expect.to_equal(Ok(None))
  let assert Ok(map_a) = watershed.create_lww_map(a)
  watershed.lww_map_entries(map_a) |> expect.to_equal([])
  watershed.set_lww_map_field(watershed.root_typed(a), field(), map_a)
  sluice.settle(rig)
  let assert Ok(Some(map_b)) =
    watershed.resolve_lww_map_field(b, watershed.root_typed(b), field())
  let events = transport_js.new_cell([])
  let subscription =
    watershed.subscribe_lww_map(map_b, fn(event) {
      transport_js.set_cell(events, [event, ..transport_js.get_cell(events)])
    })
  watershed.lww_map_set(map_a, "status", "ready") |> expect.to_equal(Ok(Nil))
  sluice.settle(rig)
  watershed.lww_map_get(map_b, "status") |> expect.to_equal(Ok("ready"))
  let expected = [lww.ValueChanged("status", None, Some("ready"))]
  transport_js.get_cell(events) |> expect.to_equal(expected)
  let before = sluice.sequence_number(rig)
  watershed.lww_map_set(map_a, "status", "ready") |> expect.to_equal(Ok(Nil))
  watershed.lww_map_remove(map_a, "absent") |> expect.to_equal(Ok(Nil))
  sluice.settle(rig)
  sluice.sequence_number(rig) |> expect.to_equal(before + 2)
  transport_js.get_cell(events) |> expect.to_equal(expected)
  sluice.drop(rig, a)
  watershed.lww_map_remove(map_a, "status") |> expect.to_equal(Ok(Nil))
  watershed.lww_map_get(map_a, "status") |> expect.to_equal(Error(Nil))
  watershed.lww_map_get(map_b, "status") |> expect.to_equal(Ok("ready"))
  sluice.rejoin(rig, a)
  sluice.settle(rig)
  watershed.lww_map_get(map_b, "status") |> expect.to_equal(Error(Nil))
  watershed.is_synced(a) |> expect.to_be_true()
  watershed.lww_map_set(map_b, "status", "restored") |> expect.to_equal(Ok(Nil))
  watershed.lww_map_set(map_b, "", "") |> expect.to_equal(Ok(Nil))
  sluice.settle(rig)
  watershed.lww_map_entries(map_a)
  |> expect.to_equal([#("", ""), #("status", "restored")])
  watershed.lww_map_keys(map_a) |> expect.to_equal(["", "status"])
  let recorded = transport_js.get_cell(events)
  watershed.unsubscribe(subscription)
  watershed.lww_map_remove(map_a, "status") |> expect.to_equal(Ok(Nil))
  sluice.settle(rig)
  transport_js.get_cell(events) |> expect.to_equal(recorded)
  watershed.close(a)
  watershed.close(b)
}

@target(javascript)
pub fn ensure_lww_map_waits_and_adopts_test() -> Nil {
  let rig = sluice.start(tenant: "default", document: "lww-map-ensure")
  let a = sluice.connect(rig, "a")
  let outcomes = transport_js.new_cell([])
  watershed.ensure_lww_map(a, watershed.root_typed(a), field(), fn(value) {
    transport_js.set_cell(outcomes, [value, ..transport_js.get_cell(outcomes)])
  })
  transport_js.get_cell(outcomes) |> expect.to_equal([])
  sluice.settle(rig)
  sluice.advance(rig, 200)
  sluice.settle(rig)
  sluice.advance(rig, 200)
  let assert [Ok(map_a)] = transport_js.get_cell(outcomes)
  let b = sluice.connect(rig, "b")
  let adopted = transport_js.new_cell([])
  watershed.ensure_lww_map(b, watershed.root_typed(b), field(), fn(value) {
    transport_js.set_cell(adopted, [value, ..transport_js.get_cell(adopted)])
  })
  transport_js.get_cell(adopted) |> expect.to_equal([])
  sluice.settle(rig)
  sluice.advance(rig, 200)
  let assert [Ok(map_b)] = transport_js.get_cell(adopted)
  watershed.lww_map_handle_of(map_a)
  |> json.to_string
  |> expect.to_equal(watershed.lww_map_handle_of(map_b) |> json.to_string)
  watershed.close(a)
  watershed.close(b)
}

@target(javascript)
pub fn lww_map_wrong_kind_and_invalid_handles_test() -> Nil {
  let rig = sluice.start(tenant: "default", document: "lww-map-invalid")
  let document = sluice.connect(rig, "a")
  sluice.settle(rig)
  let assert Ok(map) =
    watershed.resolve_lww_map(
      document,
      watershed.handle_of(watershed.root(document)),
    )
  watershed.lww_map_get(map, "k") |> expect.to_equal(Error(Nil))
  watershed.lww_map_entries(map) |> expect.to_equal([])
  watershed.lww_map_keys(map) |> expect.to_equal([])
  watershed.lww_map_set(map, "k", "value")
  |> result.is_error
  |> expect.to_be_true()
  watershed.lww_map_remove(map, "k") |> result.is_error |> expect.to_be_true()
  watershed.resolve_lww_map(document, json.string("bad"))
  |> result.is_error
  |> expect.to_be_true()
  watershed.diagnostics(document).in_flight_count |> expect.to_equal(0)
  watershed.close(document)
}
