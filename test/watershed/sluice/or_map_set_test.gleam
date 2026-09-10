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
import watershed/or_map_kernel as or_map
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
  schema.channel_field("documents")
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
pub fn public_set_map_members_empty_keys_and_subscriptions_test() -> Nil {
  let assert Ok(rig) = sluice.start(tenant: "default", document: "set-map-beam")
  let assert Ok(a) = sluice.connect(rig, "a")
  let assert Ok(b) = sluice.connect(rig, "b")
  sluice.settle(rig)
  let root = watershed.typed(watershed.root(a))
  watershed.resolve_or_map_field(a, root, field())
  |> expect.to_equal(Ok(None))
  let assert Ok(map_a) = watershed.create_or_map(a, or_map.OrSetMode)
  watershed.or_map_add_member(map_a, "doc", "draft")
  |> expect.to_equal(Ok(Nil))
  watershed.is_synced(a) |> expect.to_be_true()
  watershed.set_or_map_field(root, field(), map_a)
  sluice.settle(rig)
  let assert Ok(Some(map_b)) =
    watershed.resolve_or_map_field(
      b,
      watershed.typed(watershed.root(b)),
      field(),
    )
  watershed.or_map_value(map_b, "doc")
  |> expect.to_equal(Ok(or_map.SetMembers(["draft"])))
  let events_a = watershed.subscribe_or_map(map_a)
  let events_b = watershed.subscribe_or_map(map_b)
  watershed.or_map_add_member(map_b, "doc", "approved")
  |> expect.to_equal(Ok(Nil))
  sluice.settle(rig)
  process.receive(events_a, 1000)
  |> expect.to_equal(Ok(or_map.SetMembersUpdated("doc", ["approved", "draft"])))
  process.receive(events_b, 1000)
  |> expect.to_equal(Ok(or_map.SetMembersUpdated("doc", ["approved", "draft"])))
  watershed.or_map_add_member(map_a, "doc", "draft")
  |> expect.to_equal(Ok(Nil))
  watershed.is_synced(a) |> expect.to_be_false()
  sluice.settle(rig)
  watershed.is_synced(a) |> expect.to_be_true()
  process.receive(events_a, 0) |> expect.to_equal(Error(Nil))
  process.receive(events_b, 0) |> expect.to_equal(Error(Nil))
  watershed.or_map_remove_member(map_a, "missing", "draft")
  |> expect.to_equal(Ok(Nil))
  watershed.or_map_remove_key(map_a, "missing")
  |> expect.to_equal(Ok(Nil))
  watershed.or_map_remove_member(map_a, "doc", "absent")
  |> expect.to_equal(Ok(Nil))
  sluice.settle(rig)
  watershed.or_map_value(map_b, "missing") |> expect.to_equal(Error(Nil))
  process.receive(events_b, 0) |> expect.to_equal(Error(Nil))
  watershed.or_map_remove_member(map_a, "doc", "draft")
  |> expect.to_equal(Ok(Nil))
  watershed.or_map_remove_member(map_a, "doc", "approved")
  |> expect.to_equal(Ok(Nil))
  sluice.settle(rig)
  watershed.or_map_entries(map_b)
  |> expect.to_equal([#("doc", or_map.SetMembers([]))])
  watershed.or_map_keys(map_b) |> expect.to_equal(["doc"])
  process.receive(events_b, 1000)
  |> expect.to_equal(Ok(or_map.SetMembersUpdated("doc", ["approved"])))
  process.receive(events_b, 1000)
  |> expect.to_equal(Ok(or_map.SetMembersUpdated("doc", [])))
  watershed.or_map_remove_key(map_a, "doc") |> expect.to_equal(Ok(Nil))
  sluice.settle(rig)
  watershed.or_map_value(map_b, "doc") |> expect.to_equal(Error(Nil))
  process.receive(events_b, 1000)
  |> expect.to_equal(Ok(or_map.KeyRemoved("doc")))
  watershed.or_map_add_member(map_a, "doc", "handoff")
  |> expect.to_equal(Ok(Nil))
  sluice.settle(rig)
  watershed.or_map_value(map_b, "doc")
  |> expect.to_equal(Ok(or_map.SetMembers(["handoff"])))
  watershed.close(a)
  watershed.close(b)
}

@target(erlang)
pub fn public_set_map_ensure_reconnect_and_concurrent_key_removal_test() -> Nil {
  let assert Ok(rig) =
    sluice.start(tenant: "default", document: "set-map-beam-reconnect")
  let assert Ok(a) = sluice.connect(rig, "a")
  let reply = process.new_subject()
  let _worker =
    process.spawn(fn() {
      process.send(
        reply,
        watershed.ensure_or_map(
          a,
          watershed.typed(watershed.root(a)),
          field(),
          or_map.OrSetMode,
        ),
      )
    })
  let assert Ok(map_a) = settle_until(rig, reply, 100)
  watershed.or_map_add_member(map_a, "doc", "old") |> expect.to_equal(Ok(Nil))
  sluice.settle(rig)
  let assert Ok(b) = sluice.connect(rig, "b")
  sluice.settle(rig)
  let assert Ok(map_b) =
    watershed.ensure_or_map(
      b,
      watershed.typed(watershed.root(b)),
      field(),
      or_map.OrSetMode,
    )
  watershed.or_map_handle_of(map_b)
  |> json.to_string
  |> expect.to_equal(watershed.or_map_handle_of(map_a) |> json.to_string)
  watershed.or_map_value(map_b, "doc")
  |> expect.to_equal(Ok(or_map.SetMembers(["old"])))
  sluice.drop(rig, b)
  watershed.or_map_remove_key(map_a, "doc") |> expect.to_equal(Ok(Nil))
  watershed.or_map_add_member(map_b, "doc", "new") |> expect.to_equal(Ok(Nil))
  watershed.is_synced(b) |> expect.to_be_false()
  sluice.settle(rig)
  sluice.rejoin(rig, b)
  sluice.settle(rig)
  watershed.or_map_value(map_a, "doc")
  |> expect.to_equal(Ok(or_map.SetMembers(["new"])))
  watershed.or_map_value(map_b, "doc")
  |> expect.to_equal(Ok(or_map.SetMembers(["new"])))
  watershed.is_synced(b) |> expect.to_be_true()
  watershed.close(a)
  watershed.close(b)
}

@target(erlang)
pub fn public_set_map_wrong_mode_and_kind_return_errors_test() -> Nil {
  let assert Ok(rig) =
    sluice.start(tenant: "default", document: "set-map-beam-errors")
  let assert Ok(document) = sluice.connect(rig, "a")
  sluice.settle(rig)
  let assert Ok(tally) = watershed.create_or_map(document, or_map.TallyMode)
  watershed.or_map_add_member(tally, "doc", "draft")
  |> result.is_error
  |> expect.to_be_true()
  watershed.or_map_remove_member(tally, "missing", "draft")
  |> result.is_error
  |> expect.to_be_true()
  let assert Ok(wrong) =
    watershed.resolve_or_map(
      document,
      watershed.handle_of(watershed.root(document)),
    )
  watershed.or_map_add_member(wrong, "doc", "draft")
  |> result.is_error
  |> expect.to_be_true()
  watershed.or_map_remove_member(wrong, "doc", "draft")
  |> result.is_error
  |> expect.to_be_true()
  watershed.or_map_remove_key(wrong, "doc")
  |> result.is_error
  |> expect.to_be_true()
  watershed.or_map_value(wrong, "doc") |> expect.to_equal(Error(Nil))
  watershed.resolve_or_map(document, json.string("invalid"))
  |> result.is_error
  |> expect.to_be_true()
  watershed.is_synced(document) |> expect.to_be_true()
  watershed.close(document)
}
