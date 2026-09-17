@target(javascript)
import gleam/json
@target(javascript)
import gleam/option.{None, Some}
@target(javascript)
import startest/expect
@target(javascript)
import watershed
@target(javascript)
import watershed/or_map_kernel as kernel
@target(javascript)
import watershed/schema
@target(javascript)
import watershed/sluice_js as sluice
@target(javascript)
import watershed/transport_js

@target(javascript)
type Fields

@target(javascript)
fn field() -> schema.ChannelField(Fields, schema.OrMapChannel) {
  schema.channel_field("revisions")
}

@target(javascript)
pub fn mv_or_map_public_lifecycle_test() -> Nil {
  let rig = sluice.start(tenant: "default", document: "mv-or-map-js")
  let a = sluice.connect(rig, "a")
  let b = sluice.connect(rig, "b")
  sluice.settle(rig)
  watershed.resolve_or_map_field(a, watershed.root_typed(a), field())
  |> expect.to_equal(Ok(None))
  let assert Ok(map_a) = watershed.create_or_map(a, kernel.MvRegisterMode)
  watershed.or_map_values(map_a, "gate") |> expect.to_equal(Error(Nil))
  watershed.set_or_map_field(watershed.root_typed(a), field(), map_a)
  sluice.settle(rig)
  let assert Ok(Some(map_b)) =
    watershed.resolve_or_map_field(b, watershed.root_typed(b), field())
  let assert Ok(resolved) =
    watershed.resolve_or_map(a, watershed.or_map_handle_of(map_a))
  let events = transport_js.new_cell([])
  let subscription =
    watershed.subscribe_or_map(map_b, fn(event) {
      transport_js.set_cell(events, [event, ..transport_js.get_cell(events)])
    })
  watershed.or_map_set_mv_register(resolved, "gate", "open")
  watershed.or_map_set_mv_register(map_b, "gate", "closed")
  sluice.settle(rig)
  watershed.or_map_values(map_a, "gate")
  |> expect.to_equal(Ok(["closed", "open"]))
  watershed.or_map_values(map_b, "gate")
  |> expect.to_equal(Ok(["closed", "open"]))
  transport_js.get_cell(events)
  |> expect.to_equal([
    kernel.MvRegisterUpdated("gate", ["closed", "open"]),
    kernel.MvRegisterUpdated("gate", ["closed"]),
  ])
  sluice.drop(rig, a)
  watershed.or_map_set_mv_register(map_a, "gate", "resolved")
  sluice.rejoin(rig, a)
  sluice.settle(rig)
  watershed.or_map_values(map_b, "gate") |> expect.to_equal(Ok(["resolved"]))
  watershed.is_synced(a) |> expect.to_be_true()
  watershed.unsubscribe(subscription)
  watershed.or_map_remove(map_b, "gate")
  sluice.settle(rig)
  watershed.or_map_values(map_a, "gate") |> expect.to_equal(Error(Nil))
  let assert Ok(tally) = watershed.create_or_map(a, kernel.TallyMode)
  watershed.or_map_increment(tally, "k", 1)
  watershed.or_map_values(tally, "k") |> expect.to_equal(Error(Nil))
  watershed.close(a)
  watershed.close(b)
}

@target(javascript)
pub fn mv_or_map_ensure_waits_and_adopts_test() -> Nil {
  let rig = sluice.start(tenant: "default", document: "mv-or-map-ensure-js")
  let a = sluice.connect(rig, "a")
  let outcomes = transport_js.new_cell([])
  watershed.ensure_or_map(
    a,
    watershed.root_typed(a),
    field(),
    kernel.MvRegisterMode,
    fn(value) {
      transport_js.set_cell(outcomes, [value, ..transport_js.get_cell(outcomes)])
    },
  )
  transport_js.get_cell(outcomes) |> expect.to_equal([])
  sluice.settle(rig)
  sluice.advance(rig, 200)
  sluice.settle(rig)
  sluice.advance(rig, 200)
  let assert [Ok(map)] = transport_js.get_cell(outcomes)
  let adopted = transport_js.new_cell([])
  watershed.ensure_or_map(
    a,
    watershed.root_typed(a),
    field(),
    kernel.MvRegisterMode,
    fn(value) {
      transport_js.set_cell(adopted, [value, ..transport_js.get_cell(adopted)])
    },
  )
  let assert [Ok(same)] = transport_js.get_cell(adopted)
  watershed.or_map_handle_of(same)
  |> json.to_string
  |> expect.to_equal(watershed.or_map_handle_of(map) |> json.to_string)
  watershed.or_map_set_mv_register(same, "gate", "open")
  watershed.or_map_values(map, "gate") |> expect.to_equal(Ok(["open"]))
  watershed.close(a)
}
