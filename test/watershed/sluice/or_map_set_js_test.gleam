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
import watershed/or_map_kernel as or_map
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
  schema.channel_field("documents")
}

@target(javascript)
pub fn public_set_map_members_empty_keys_and_subscriptions_test() -> Nil {
  let rig = sluice.start(tenant: "default", document: "set-map-public")
  let a = sluice.connect(rig, "a")
  let b = sluice.connect(rig, "b")
  sluice.settle(rig)
  watershed.resolve_or_map_field(a, watershed.root_typed(a), field())
  |> expect.to_equal(Ok(None))
  let assert Ok(map_a) = watershed.create_or_map(a, or_map.OrSetMode)
  watershed.or_map_add_member(map_a, "doc", "draft")
  |> expect.to_equal(Ok(Nil))
  watershed.diagnostics(a).in_flight_count |> expect.to_equal(0)
  watershed.set_or_map_field(watershed.root_typed(a), field(), map_a)
  sluice.settle(rig)
  let assert Ok(Some(map_b)) =
    watershed.resolve_or_map_field(b, watershed.root_typed(b), field())
  watershed.or_map_value(map_b, "doc")
  |> expect.to_equal(Ok(or_map.SetMembers(["draft"])))
  let events_a = transport_js.new_cell([])
  let events_b = transport_js.new_cell([])
  let subscription_a =
    watershed.subscribe_or_map(map_a, fn(event) {
      transport_js.set_cell(events_a, [event, ..transport_js.get_cell(events_a)])
    })
  let subscription_b =
    watershed.subscribe_or_map(map_b, fn(event) {
      transport_js.set_cell(events_b, [event, ..transport_js.get_cell(events_b)])
    })
  watershed.or_map_add_member(map_b, "doc", "approved")
  |> expect.to_equal(Ok(Nil))
  sluice.settle(rig)
  let expected = [or_map.SetMembersUpdated("doc", ["approved", "draft"])]
  transport_js.get_cell(events_a) |> expect.to_equal(expected)
  transport_js.get_cell(events_b) |> expect.to_equal(expected)
  let before = sluice.sequence_number(rig)
  watershed.or_map_add_member(map_a, "doc", "draft")
  |> expect.to_equal(Ok(Nil))
  watershed.diagnostics(a).in_flight_count |> expect.to_equal(1)
  sluice.settle(rig)
  sluice.sequence_number(rig) |> expect.to_equal(before + 1)
  watershed.diagnostics(a).in_flight_count |> expect.to_equal(0)
  transport_js.get_cell(events_a) |> expect.to_equal(expected)
  transport_js.get_cell(events_b) |> expect.to_equal(expected)
  watershed.or_map_remove_member(map_a, "missing", "draft")
  |> expect.to_equal(Ok(Nil))
  watershed.or_map_remove_key(map_a, "missing")
  |> expect.to_equal(Ok(Nil))
  watershed.or_map_remove_member(map_a, "doc", "absent")
  |> expect.to_equal(Ok(Nil))
  sluice.settle(rig)
  watershed.or_map_value(map_b, "missing") |> expect.to_equal(Error(Nil))
  transport_js.get_cell(events_b) |> expect.to_equal(expected)
  watershed.or_map_remove_member(map_a, "doc", "draft")
  |> expect.to_equal(Ok(Nil))
  watershed.or_map_remove_member(map_a, "doc", "approved")
  |> expect.to_equal(Ok(Nil))
  sluice.settle(rig)
  watershed.or_map_entries(map_b)
  |> expect.to_equal([#("doc", or_map.SetMembers([]))])
  watershed.or_map_keys(map_b) |> expect.to_equal(["doc"])
  watershed.or_map_remove_key(map_a, "doc") |> expect.to_equal(Ok(Nil))
  sluice.settle(rig)
  watershed.or_map_value(map_b, "doc") |> expect.to_equal(Error(Nil))
  let observed = transport_js.get_cell(events_b)
  watershed.unsubscribe(subscription_a)
  watershed.unsubscribe(subscription_b)
  watershed.or_map_add_member(map_a, "doc", "handoff")
  |> expect.to_equal(Ok(Nil))
  sluice.settle(rig)
  watershed.or_map_value(map_b, "doc")
  |> expect.to_equal(Ok(or_map.SetMembers(["handoff"])))
  transport_js.get_cell(events_b) |> expect.to_equal(observed)
  watershed.close(a)
  watershed.close(b)
}

@target(javascript)
pub fn public_set_map_ensure_reconnect_and_concurrent_key_removal_test() -> Nil {
  let rig = sluice.start(tenant: "default", document: "set-map-reconnect")
  let a = sluice.connect(rig, "a")
  let outcomes = transport_js.new_cell([])
  watershed.ensure_or_map(
    a,
    watershed.root_typed(a),
    field(),
    or_map.OrSetMode,
    fn(value) {
      transport_js.set_cell(outcomes, [value, ..transport_js.get_cell(outcomes)])
    },
  )
  transport_js.get_cell(outcomes) |> expect.to_equal([])
  sluice.settle(rig)
  sluice.advance(rig, 200)
  sluice.settle(rig)
  sluice.advance(rig, 200)
  let assert [Ok(map_a)] = transport_js.get_cell(outcomes)
  watershed.or_map_add_member(map_a, "doc", "old") |> expect.to_equal(Ok(Nil))
  sluice.settle(rig)
  let b = sluice.connect(rig, "b")
  let adopted = transport_js.new_cell([])
  watershed.ensure_or_map(
    b,
    watershed.root_typed(b),
    field(),
    or_map.OrSetMode,
    fn(value) {
      transport_js.set_cell(adopted, [value, ..transport_js.get_cell(adopted)])
    },
  )
  sluice.settle(rig)
  sluice.advance(rig, 200)
  let assert [Ok(map_b)] = transport_js.get_cell(adopted)
  watershed.or_map_handle_of(map_b)
  |> json.to_string
  |> expect.to_equal(watershed.or_map_handle_of(map_a) |> json.to_string)
  watershed.or_map_value(map_b, "doc")
  |> expect.to_equal(Ok(or_map.SetMembers(["old"])))
  sluice.drop(rig, b)
  watershed.or_map_remove_key(map_a, "doc") |> expect.to_equal(Ok(Nil))
  watershed.or_map_add_member(map_b, "doc", "new") |> expect.to_equal(Ok(Nil))
  watershed.diagnostics(b).in_flight_count |> expect.to_equal(1)
  sluice.settle(rig)
  sluice.rejoin(rig, b)
  sluice.settle(rig)
  watershed.or_map_value(map_a, "doc")
  |> expect.to_equal(Ok(or_map.SetMembers(["new"])))
  watershed.or_map_value(map_b, "doc")
  |> expect.to_equal(Ok(or_map.SetMembers(["new"])))
  watershed.diagnostics(b).in_flight_count |> expect.to_equal(0)
  watershed.is_synced(b) |> expect.to_be_true()
  watershed.close(a)
  watershed.close(b)
}

@target(javascript)
pub fn public_set_map_wrong_mode_kind_and_closed_document_fail_test() -> Nil {
  let rig = sluice.start(tenant: "default", document: "set-map-errors")
  let document = sluice.connect(rig, "a")
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
  watershed.diagnostics(document).in_flight_count |> expect.to_equal(0)
  watershed.close(document)
  watershed.or_map_add_member(tally, "doc", "closed")
  |> result.is_error
  |> expect.to_be_true()
  watershed.or_map_remove_member(tally, "doc", "closed")
  |> result.is_error
  |> expect.to_be_true()
  watershed.or_map_remove_key(tally, "doc")
  |> result.is_error
  |> expect.to_be_true()
}
