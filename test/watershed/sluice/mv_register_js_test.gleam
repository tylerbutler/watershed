@target(javascript)
import gleam/json
@target(javascript)
import gleam/option.{Some}
@target(javascript)
import gleam/result
@target(javascript)
import startest/expect
@target(javascript)
import watershed
@target(javascript)
import watershed/mv_register_kernel as mv
@target(javascript)
import watershed/schema
@target(javascript)
import watershed/sluice_js as sluice
@target(javascript)
import watershed/transport_js

@target(javascript)
type Fields

@target(javascript)
fn field() -> schema.ChannelField(Fields, schema.MvRegisterChannel) {
  schema.channel_field("slate")
}

@target(javascript)
pub fn public_mv_register_conflict_resolution_and_late_join_test() -> Nil {
  let rig = sluice.start(tenant: "default", document: "mv-public")
  let a = sluice.connect(rig, "a")
  let b = sluice.connect(rig, "b")
  sluice.settle(rig)
  let assert Ok(register_a) = watershed.create_mv_register(a)
  watershed.mv_register_set(register_a, "baseline")
  watershed.set_mv_register_field(
    watershed.typed(watershed.root(a)),
    field(),
    register_a,
  )
  sluice.settle(rig)
  let assert Ok(Some(register_b)) =
    watershed.resolve_mv_register_field(
      b,
      watershed.typed(watershed.root(b)),
      field(),
    )
  let events = transport_js.new_cell([])
  let subscription =
    watershed.subscribe_mv_register(register_a, fn(event) {
      transport_js.set_cell(events, [event, ..transport_js.get_cell(events)])
    })
  watershed.mv_register_set(register_a, "raise crest")
  watershed.mv_register_set(register_b, "arm pump")
  sluice.settle(rig)
  watershed.mv_register_values(register_a)
  |> expect.to_equal(Ok(["arm pump", "raise crest"]))
  watershed.mv_register_values(register_b)
  |> expect.to_equal(Ok(["arm pump", "raise crest"]))
  transport_js.get_cell(events)
  |> expect.to_equal([
    mv.ValuesChanged(["arm pump", "raise crest"]),
    mv.ValuesChanged(["raise crest"]),
  ])
  watershed.mv_register_set(register_a, "raise crest + arm pump")
  sluice.settle(rig)
  watershed.mv_register_values(register_b)
  |> expect.to_equal(Ok(["raise crest + arm pump"]))
  watershed.unsubscribe(subscription)
  let before = transport_js.get_cell(events)
  watershed.mv_register_set(register_a, "final")
  sluice.settle(rig)
  transport_js.get_cell(events) |> expect.to_equal(before)
  let c = sluice.connect(rig, "c")
  sluice.settle(rig)
  let assert Ok(Some(register_c)) =
    watershed.resolve_mv_register_field(
      c,
      watershed.typed(watershed.root(c)),
      field(),
    )
  watershed.mv_register_values(register_c) |> expect.to_equal(Ok(["final"]))
  watershed.resolve_mv_register(a, watershed.handle_of(watershed.root(a)))
  |> result.is_error
  |> expect.to_be_true()
  watershed.close(a)
  watershed.close(b)
  watershed.close(c)
}

@target(javascript)
pub fn ensure_mv_register_waits_and_adopts_test() -> Nil {
  let rig = sluice.start(tenant: "default", document: "mv-ensure")
  let a = sluice.connect(rig, "a")
  let outcomes = transport_js.new_cell([])
  watershed.ensure_mv_register(
    a,
    watershed.typed(watershed.root(a)),
    field(),
    fn(value) {
      transport_js.set_cell(outcomes, [value, ..transport_js.get_cell(outcomes)])
    },
  )
  transport_js.get_cell(outcomes) |> expect.to_equal([])
  sluice.settle(rig)
  sluice.advance(rig, 200)
  sluice.settle(rig)
  sluice.advance(rig, 200)
  let assert [Ok(register)] = transport_js.get_cell(outcomes)
  watershed.mv_register_set(register, "ready")
  sluice.settle(rig)
  let b = sluice.connect(rig, "b")
  let adopted = transport_js.new_cell([])
  watershed.ensure_mv_register(
    b,
    watershed.typed(watershed.root(b)),
    field(),
    fn(value) {
      transport_js.set_cell(adopted, [value, ..transport_js.get_cell(adopted)])
    },
  )
  sluice.settle(rig)
  sluice.advance(rig, 200)
  let assert [Ok(register_b)] = transport_js.get_cell(adopted)
  watershed.mv_register_values(register_b) |> expect.to_equal(Ok(["ready"]))
  watershed.close(a)
  watershed.close(b)
}

@target(javascript)
pub fn reconnect_preserves_pending_mv_deltas_test() -> Nil {
  let rig = sluice.start(tenant: "default", document: "mv-reconnect")
  let a = sluice.connect(rig, "a")
  let b = sluice.connect(rig, "b")
  sluice.settle(rig)
  let assert Ok(register_a) = watershed.create_mv_register(a)
  watershed.set_mv_register_field(
    watershed.typed(watershed.root(a)),
    field(),
    register_a,
  )
  sluice.settle(rig)
  let assert Ok(Some(register_b)) =
    watershed.resolve_mv_register_field(
      b,
      watershed.typed(watershed.root(b)),
      field(),
    )
  sluice.drop(rig, a)
  watershed.mv_register_set(register_a, "offline")
  watershed.mv_register_set(register_b, "online")
  sluice.settle(rig)
  watershed.mv_register_values(register_a) |> expect.to_equal(Ok(["offline"]))
  sluice.rejoin(rig, a)
  sluice.settle(rig)
  watershed.mv_register_values(register_a)
  |> expect.to_equal(Ok(["offline", "online"]))
  watershed.mv_register_values(register_b)
  |> expect.to_equal(Ok(["offline", "online"]))
  watershed.close(a)
  watershed.close(b)
}

@target(javascript)
pub fn simultaneous_ensure_adopts_one_field_winner_test() -> Nil {
  let rig = sluice.start(tenant: "default", document: "mv-ensure-race")
  let a = sluice.connect(rig, "a")
  let b = sluice.connect(rig, "b")
  sluice.settle(rig)
  let outcomes_a = transport_js.new_cell([])
  let outcomes_b = transport_js.new_cell([])
  watershed.ensure_mv_register(
    a,
    watershed.typed(watershed.root(a)),
    field(),
    fn(value) { transport_js.set_cell(outcomes_a, [value]) },
  )
  watershed.ensure_mv_register(
    b,
    watershed.typed(watershed.root(b)),
    field(),
    fn(value) { transport_js.set_cell(outcomes_b, [value]) },
  )
  sluice.settle(rig)
  sluice.advance(rig, 200)
  let assert [Ok(register_a)] = transport_js.get_cell(outcomes_a)
  let assert [Ok(register_b)] = transport_js.get_cell(outcomes_b)
  watershed.mv_register_handle_of(register_a)
  |> json.to_string
  |> expect.to_equal(
    watershed.mv_register_handle_of(register_b) |> json.to_string,
  )
  watershed.close(a)
  watershed.close(b)
}
