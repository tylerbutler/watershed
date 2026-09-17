@target(erlang)
import gleam/erlang/process
@target(erlang)
import gleam/json
@target(erlang)
import gleam/option.{None, Some}
@target(erlang)
import gleam/result
@target(erlang)
import startest/expect
@target(erlang)
import watershed/lww_register_kernel as lww
@target(erlang)
import watershed/schema
@target(erlang)
import watershed/sluice
@target(erlang)
import watershed_beam as watershed

@target(erlang)
type Fields

@target(erlang)
fn field() -> schema.ChannelField(Fields, schema.LwwRegisterChannel) {
  schema.channel_field("status")
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
pub fn public_lww_register_ensure_write_subscribe_and_reconnect_test() -> Nil {
  let assert Ok(rig) = sluice.start(tenant: "default", document: "lww-beam")
  let assert Ok(a) = sluice.connect(rig, "a")
  let reply = process.new_subject()
  let _worker =
    process.spawn(fn() {
      process.send(
        reply,
        watershed.ensure_lww_register(
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
    watershed.resolve_lww_register_field(
      b,
      watershed.typed(watershed.root(b)),
      field(),
    )
  let assert Ok(adopted) =
    watershed.ensure_lww_register(
      b,
      watershed.typed(watershed.root(b)),
      field(),
    )
  watershed.lww_register_handle_of(adopted)
  |> json.to_string
  |> expect.to_equal(
    watershed.lww_register_handle_of(register_a) |> json.to_string,
  )
  let events = watershed.subscribe_lww_register(register_a)
  watershed.lww_register_set(register_a, "first") |> expect.to_equal(Ok(Nil))
  watershed.lww_register_value(register_a) |> expect.to_equal(Ok("first"))
  sluice.settle(rig)
  watershed.lww_register_set(register_b, "second") |> expect.to_equal(Ok(Nil))
  sluice.settle(rig)
  watershed.lww_register_value(register_a) |> expect.to_equal(Ok("second"))
  watershed.lww_register_value(register_b) |> expect.to_equal(Ok("second"))
  process.receive(events, 1000)
  |> expect.to_equal(Ok(lww.Changed("", "first")))
  process.receive(events, 1000)
  |> expect.to_equal(Ok(lww.Changed("first", "second")))
  process.receive(events, 0) |> expect.to_equal(Error(Nil))

  sluice.drop(rig, b)
  watershed.lww_register_set(register_b, "offline") |> expect.to_equal(Ok(Nil))
  watershed.lww_register_value(register_b) |> expect.to_equal(Ok("offline"))
  watershed.is_synced(b) |> expect.to_be_false()
  watershed.lww_register_set(register_a, "online") |> expect.to_equal(Ok(Nil))
  // The second write wins even when both clocks report the same millisecond.
  watershed.lww_register_set(register_a, "online") |> expect.to_equal(Ok(Nil))
  sluice.settle(rig)
  sluice.rejoin(rig, b)
  sluice.settle(rig)
  // A resubmission must not give the older pending write a new timestamp.
  watershed.lww_register_value(register_a) |> expect.to_equal(Ok("online"))
  watershed.lww_register_value(register_b) |> expect.to_equal(Ok("online"))
  watershed.is_synced(b) |> expect.to_be_true()

  sluice.drop(rig, b)
  watershed.lww_register_set(register_b, "retained")
  |> expect.to_equal(Ok(Nil))
  sluice.rejoin(rig, b)
  sluice.settle(rig)
  watershed.lww_register_value(register_a) |> expect.to_equal(Ok("retained"))
  watershed.lww_register_value(register_b) |> expect.to_equal(Ok("retained"))
  watershed.is_synced(b) |> expect.to_be_true()
  watershed.close(a)
  watershed.close(b)
}

@target(erlang)
pub fn public_lww_register_simultaneous_ensures_share_one_field_test() -> Nil {
  let assert Ok(rig) = sluice.start(tenant: "default", document: "lww-ensures")
  let assert Ok(a) = sluice.connect(rig, "a")
  let assert Ok(b) = sluice.connect(rig, "b")
  let replies = process.new_subject()
  let ensure = fn(document) {
    process.send(
      replies,
      watershed.ensure_lww_register(
        document,
        watershed.typed(watershed.root(document)),
        field(),
      ),
    )
  }
  let _a = process.spawn(fn() { ensure(a) })
  let _b = process.spawn(fn() { ensure(b) })
  let assert Ok(_) = settle_until(rig, replies, 100)
  let assert Ok(_) = settle_until(rig, replies, 100)
  sluice.settle(rig)
  let assert Ok(Some(register_a)) =
    watershed.resolve_lww_register_field(
      a,
      watershed.typed(watershed.root(a)),
      field(),
    )
  let assert Ok(Some(register_b)) =
    watershed.resolve_lww_register_field(
      b,
      watershed.typed(watershed.root(b)),
      field(),
    )
  watershed.lww_register_handle_of(register_a)
  |> json.to_string
  |> expect.to_equal(
    watershed.lww_register_handle_of(register_b) |> json.to_string,
  )
  watershed.lww_register_set(register_a, "shared") |> expect.to_equal(Ok(Nil))
  sluice.settle(rig)
  watershed.lww_register_value(register_b) |> expect.to_equal(Ok("shared"))
  watershed.close(a)
  watershed.close(b)
}

@target(erlang)
pub fn public_lww_register_same_value_write_emits_no_event_test() -> Nil {
  let assert Ok(rig) = sluice.start(tenant: "default", document: "lww-same")
  let assert Ok(a) = sluice.connect(rig, "a")
  let assert Ok(b) = sluice.connect(rig, "b")
  sluice.settle(rig)
  let root = watershed.typed(watershed.root(a))
  watershed.resolve_lww_register_field(a, root, field())
  |> expect.to_equal(Ok(None))
  let assert Ok(register_a) = watershed.create_lww_register(a)
  watershed.lww_register_value(register_a) |> expect.to_equal(Ok(""))
  watershed.set_lww_register_field(root, field(), register_a)
  sluice.settle(rig)
  let assert Ok(register_b) =
    watershed.resolve_lww_register(
      b,
      watershed.lww_register_handle_of(register_a),
    )
  let events_a = watershed.subscribe_lww_register(register_a)
  let events_b = watershed.subscribe_lww_register(register_b)
  watershed.lww_register_set(register_a, "ready") |> expect.to_equal(Ok(Nil))
  sluice.settle(rig)
  process.receive(events_a, 1000)
  |> expect.to_equal(Ok(lww.Changed("", "ready")))
  process.receive(events_b, 1000)
  |> expect.to_equal(Ok(lww.Changed("", "ready")))
  watershed.is_synced(a) |> expect.to_be_true()
  watershed.lww_register_set(register_a, "ready") |> expect.to_equal(Ok(Nil))
  watershed.is_synced(a) |> expect.to_be_false()
  sluice.settle(rig)
  watershed.is_synced(a) |> expect.to_be_true()
  watershed.lww_register_value(register_a) |> expect.to_equal(Ok("ready"))
  watershed.lww_register_value(register_b) |> expect.to_equal(Ok("ready"))
  process.receive(events_a, 0) |> expect.to_equal(Error(Nil))
  process.receive(events_b, 0) |> expect.to_equal(Error(Nil))
  watershed.close(a)
  watershed.close(b)
}

@target(erlang)
pub fn public_lww_register_invalid_handles_and_wrong_kind_return_errors_test() -> Nil {
  let assert Ok(rig) = sluice.start(tenant: "default", document: "lww-errors")
  let assert Ok(document) = sluice.connect(rig, "a")
  sluice.settle(rig)
  let root = watershed.root(document)
  let assert Ok(register) =
    watershed.resolve_lww_register(document, watershed.handle_of(root))
  watershed.lww_register_value(register) |> expect.to_equal(Error(Nil))
  watershed.lww_register_set(register, "wrong")
  |> result.is_error
  |> expect.to_be_true()
  watershed.is_synced(document) |> expect.to_be_true()
  let events = watershed.subscribe_lww_register(register)
  watershed.set(root, "plain", json.string("map value"))
  sluice.settle(rig)
  process.receive(events, 0) |> expect.to_equal(Error(Nil))
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
