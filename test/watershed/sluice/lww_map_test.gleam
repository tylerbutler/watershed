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
import watershed/lww_map_kernel as lww
@target(erlang)
import watershed/schema
@target(erlang)
import watershed/sluice
@target(erlang)
import watershed_beam as watershed

@target(erlang)
type Fields

@target(erlang)
fn field() -> schema.ChannelField(Fields, schema.LwwMapChannel) {
  schema.channel_field("settings")
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
pub fn public_lww_map_ensure_subscribe_reconnect_test() -> Nil {
  let assert Ok(rig) = sluice.start(tenant: "default", document: "lww-map-beam")
  let assert Ok(a) = sluice.connect(rig, "a")
  let reply = process.new_subject()
  let _worker =
    process.spawn(fn() {
      process.send(
        reply,
        watershed.ensure_lww_map(a, watershed.typed(watershed.root(a)), field()),
      )
    })
  let assert Ok(map_a) = settle_until(rig, reply, 100)
  let assert Ok(b) = sluice.connect(rig, "b")
  sluice.settle(rig)
  let assert Ok(Some(map_b)) =
    watershed.resolve_lww_map_field(
      b,
      watershed.typed(watershed.root(b)),
      field(),
    )
  let assert Ok(adopted) =
    watershed.ensure_lww_map(b, watershed.typed(watershed.root(b)), field())
  watershed.lww_map_handle_of(adopted)
  |> json.to_string
  |> expect.to_equal(watershed.lww_map_handle_of(map_a) |> json.to_string)
  let events_a = watershed.subscribe_lww_map(map_a)
  let events_b = watershed.subscribe_lww_map(map_b)
  watershed.lww_map_set(map_a, "status", "ready") |> expect.to_equal(Ok(Nil))
  sluice.settle(rig)
  process.receive(events_a, 1000)
  |> expect.to_equal(Ok(lww.ValueChanged("status", None, Some("ready"))))
  process.receive(events_b, 1000)
  |> expect.to_equal(Ok(lww.ValueChanged("status", None, Some("ready"))))
  watershed.lww_map_set(map_a, "status", "ready") |> expect.to_equal(Ok(Nil))
  watershed.lww_map_remove(map_a, "absent") |> expect.to_equal(Ok(Nil))
  watershed.is_synced(a) |> expect.to_be_false()
  sluice.settle(rig)
  watershed.is_synced(a) |> expect.to_be_true()
  process.receive(events_a, 0) |> expect.to_equal(Error(Nil))
  process.receive(events_b, 0) |> expect.to_equal(Error(Nil))
  sluice.drop(rig, a)
  watershed.lww_map_remove(map_a, "status") |> expect.to_equal(Ok(Nil))
  watershed.lww_map_get(map_b, "status") |> expect.to_equal(Ok("ready"))
  sluice.rejoin(rig, a)
  sluice.settle(rig)
  watershed.lww_map_get(map_b, "status") |> expect.to_equal(Error(Nil))
  process.receive(events_a, 1000)
  |> expect.to_equal(Ok(lww.ValueChanged("status", Some("ready"), None)))
  process.receive(events_b, 1000)
  |> expect.to_equal(Ok(lww.ValueChanged("status", Some("ready"), None)))
  watershed.lww_map_set(map_b, "status", "restored") |> expect.to_equal(Ok(Nil))
  watershed.lww_map_set(map_b, "", "") |> expect.to_equal(Ok(Nil))
  sluice.settle(rig)
  watershed.lww_map_entries(map_a)
  |> expect.to_equal([#("", ""), #("status", "restored")])
  watershed.lww_map_keys(map_a) |> expect.to_equal(["", "status"])
  watershed.is_synced(a) |> expect.to_be_true()
  watershed.close(a)
  watershed.close(b)
}

@target(erlang)
pub fn public_lww_map_create_and_wrong_kind_test() -> Nil {
  let assert Ok(rig) =
    sluice.start(tenant: "default", document: "lww-map-create")
  let assert Ok(document) = sluice.connect(rig, "a")
  sluice.settle(rig)
  let root = watershed.typed(watershed.root(document))
  watershed.resolve_lww_map_field(document, root, field())
  |> expect.to_equal(Ok(None))
  let assert Ok(map) = watershed.create_lww_map(document)
  watershed.lww_map_entries(map) |> expect.to_equal([])
  watershed.set_lww_map_field(root, field(), map)
  sluice.settle(rig)
  let assert Ok(resolved) =
    watershed.resolve_lww_map(document, watershed.lww_map_handle_of(map))
  watershed.lww_map_set(resolved, "k", "v") |> expect.to_equal(Ok(Nil))
  watershed.lww_map_get(map, "k") |> expect.to_equal(Ok("v"))
  sluice.settle(rig)
  let assert Ok(wrong) =
    watershed.resolve_lww_map(
      document,
      watershed.handle_of(watershed.root(document)),
    )
  watershed.lww_map_get(wrong, "k") |> expect.to_equal(Error(Nil))
  watershed.lww_map_entries(wrong) |> expect.to_equal([])
  watershed.lww_map_keys(wrong) |> expect.to_equal([])
  watershed.lww_map_set(wrong, "k", "v")
  |> result.is_error
  |> expect.to_be_true()
  watershed.lww_map_remove(wrong, "k") |> result.is_error |> expect.to_be_true()
  watershed.resolve_lww_map(document, json.string("bad"))
  |> result.is_error
  |> expect.to_be_true()
  watershed.is_synced(document) |> expect.to_be_true()
  watershed.close(document)
}
