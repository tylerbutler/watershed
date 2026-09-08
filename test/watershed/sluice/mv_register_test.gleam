@target(erlang)
import gleam/erlang/process
@target(erlang)
import gleam/option.{Some}
@target(erlang)
import gleam/result
@target(erlang)
import startest/expect
@target(erlang)
import watershed/mv_register_kernel as mv
@target(erlang)
import watershed/schema
@target(erlang)
import watershed/sluice
@target(erlang)
import watershed_beam as watershed

@target(erlang)
type Fields

@target(erlang)
fn field() -> schema.ChannelField(Fields, schema.MvRegisterChannel) {
  schema.channel_field("slate")
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
pub fn public_mv_register_ensure_conflict_and_resolution_test() -> Nil {
  let assert Ok(rig) = sluice.start(tenant: "default", document: "mv-beam")
  let assert Ok(a) = sluice.connect(rig, "a")
  let reply = process.new_subject()
  let _worker =
    process.spawn(fn() {
      process.send(
        reply,
        watershed.ensure_mv_register(
          a,
          watershed.typed(watershed.root(a)),
          field(),
        ),
      )
    })
  let assert Ok(register_a) = settle_until(rig, reply, 100)
  let assert Ok(b) = sluice.connect(rig, "b")
  sluice.settle(rig)
  let assert Ok(Some(register_b)) =
    watershed.resolve_mv_register_field(
      b,
      watershed.typed(watershed.root(b)),
      field(),
    )
  let events = watershed.subscribe_mv_register(register_a)
  watershed.mv_register_set(register_a, "raise crest")
  watershed.mv_register_set(register_b, "arm pump")
  sluice.settle(rig)
  watershed.mv_register_values(register_a)
  |> expect.to_equal(Ok(["arm pump", "raise crest"]))
  watershed.mv_register_values(register_b)
  |> expect.to_equal(Ok(["arm pump", "raise crest"]))
  process.receive(events, 1000)
  |> expect.to_equal(Ok(mv.ValuesChanged(["raise crest"])))
  process.receive(events, 1000)
  |> expect.to_equal(Ok(mv.ValuesChanged(["arm pump", "raise crest"])))
  process.receive(events, 0) |> expect.to_equal(Error(Nil))
  watershed.mv_register_set(register_a, "resolved")
  sluice.settle(rig)
  watershed.mv_register_values(register_b) |> expect.to_equal(Ok(["resolved"]))
  watershed.resolve_mv_register(a, watershed.handle_of(watershed.root(a)))
  |> result.is_error
  |> expect.to_be_true()
  watershed.close(a)
  watershed.close(b)
}
