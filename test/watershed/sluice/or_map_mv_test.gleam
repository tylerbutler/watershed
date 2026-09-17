@target(erlang)
import gleam/erlang/process
@target(erlang)
import gleam/json
@target(erlang)
import gleam/option.{None, Some}
@target(erlang)
import startest/expect
@target(erlang)
import watershed/or_map_kernel as kernel
@target(erlang)
import watershed/schema
@target(erlang)
import watershed/sluice
@target(erlang)
import watershed_beam as watershed

@target(erlang)
type Fields

@target(erlang)
fn field() -> schema.ChannelField(Fields, schema.OrMapChannel) {
  schema.channel_field("revisions")
}

@target(erlang)
fn settle_until(
  rig: sluice.Sluice,
  reply: process.Subject(a),
  attempts: Int,
) -> a {
  sluice.settle(rig)
  case process.receive(reply, 20) {
    Ok(value) -> value
    Error(Nil) if attempts > 0 -> settle_until(rig, reply, attempts - 1)
    Error(Nil) -> panic as "ensure did not complete"
  }
}

@target(erlang)
pub fn mv_or_map_public_ensure_subscribe_reconnect_test() -> Nil {
  let assert Ok(rig) =
    sluice.start(tenant: "default", document: "mv-or-map-beam")
  let assert Ok(a) = sluice.connect(rig, "a")
  let root = watershed.typed(watershed.root(a))
  watershed.resolve_or_map_field(a, root, field()) |> expect.to_equal(Ok(None))
  let reply = process.new_subject()
  let _worker =
    process.spawn(fn() {
      process.send(
        reply,
        watershed.ensure_or_map(a, root, field(), kernel.MvRegisterMode),
      )
    })
  let assert Ok(map_a) = settle_until(rig, reply, 100)
  let assert Ok(b) = sluice.connect(rig, "b")
  sluice.settle(rig)
  let assert Ok(Some(map_b)) =
    watershed.resolve_or_map_field(
      b,
      watershed.typed(watershed.root(b)),
      field(),
    )
  let assert Ok(adopted) =
    watershed.ensure_or_map(a, root, field(), kernel.MvRegisterMode)
  watershed.or_map_handle_of(adopted)
  |> json.to_string
  |> expect.to_equal(watershed.or_map_handle_of(map_a) |> json.to_string)
  let assert Ok(resolved) =
    watershed.resolve_or_map(a, watershed.or_map_handle_of(map_a))
  watershed.or_map_values(resolved, "missing") |> expect.to_equal(Error(Nil))
  let events = watershed.subscribe_or_map(map_b)
  watershed.or_map_set_mv_register(resolved, "gate", "open")
  watershed.or_map_set_mv_register(map_b, "gate", "closed")
  sluice.settle(rig)
  watershed.or_map_values(map_a, "gate")
  |> expect.to_equal(Ok(["closed", "open"]))
  watershed.or_map_values(map_b, "gate")
  |> expect.to_equal(Ok(["closed", "open"]))
  process.receive(events, 1000)
  |> expect.to_equal(Ok(kernel.MvRegisterUpdated("gate", ["closed"])))
  process.receive(events, 1000)
  |> expect.to_equal(Ok(kernel.MvRegisterUpdated("gate", ["closed", "open"])))
  sluice.drop(rig, a)
  watershed.or_map_set_mv_register(map_a, "gate", "resolved")
  sluice.rejoin(rig, a)
  sluice.settle(rig)
  watershed.or_map_values(map_b, "gate") |> expect.to_equal(Ok(["resolved"]))
  watershed.is_synced(a) |> expect.to_be_true()
  watershed.or_map_remove(map_b, "gate")
  sluice.settle(rig)
  watershed.or_map_values(map_a, "gate") |> expect.to_equal(Error(Nil))
  let assert Ok(tally) = watershed.create_or_map(a, kernel.TallyMode)
  watershed.or_map_increment(tally, "k", 1)
  watershed.or_map_values(tally, "k") |> expect.to_equal(Error(Nil))
  watershed.close(a)
  watershed.close(b)
}
