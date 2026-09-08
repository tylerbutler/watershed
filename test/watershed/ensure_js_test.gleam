@target(javascript)
import gleam/json
@target(javascript)
import gleam/list
@target(javascript)
import gleam/option.{None, Some}
@target(javascript)
import startest/expect
@target(javascript)
import watershed
@target(javascript)
import watershed/schema
@target(javascript)
import watershed/sluice_js
@target(javascript)
import watershed/transport_js

@target(javascript)
type Fields

@target(javascript)
fn counter_field() -> schema.ChannelField(Fields, schema.CounterChannel) {
  schema.channel_field("counter")
}

@target(javascript)
fn exhaust_wait(advance: fn(Int) -> Nil) -> Nil {
  list.repeat(Nil, 30) |> list.each(fn(_) { advance(200) })
}

@target(javascript)
pub fn ensure_waits_for_a_fresh_document_before_seeding_test() -> Nil {
  let sluice = sluice_js.start(tenant: "default", document: "ensure-fresh")
  let advance = fn(milliseconds) { sluice_js.advance(sluice, milliseconds) }
  let document = sluice_js.connect(sluice, "author")
  let root = watershed.typed(watershed.root(document))
  let outcomes = transport_js.new_cell([])
  watershed.ensure_counter(document, root, counter_field(), fn(outcome) {
    transport_js.set_cell(outcomes, [outcome, ..transport_js.get_cell(outcomes)])
  })
  transport_js.get_cell(outcomes) |> expect.to_equal([])
  watershed.entries(watershed.root(document)) |> expect.to_equal([])

  sluice_js.settle(sluice)
  advance(200)
  transport_js.get_cell(outcomes) |> expect.to_equal([])
  sluice_js.settle(sluice)
  advance(200)
  let assert [Ok(counter)] = transport_js.get_cell(outcomes)
  watershed.increment(counter, 3)
  sluice_js.settle(sluice)

  let peer = sluice_js.connect(sluice, "reader")
  sluice_js.settle(sluice)
  let assert Ok(Some(peer_counter)) =
    watershed.resolve_counter_field(
      peer,
      watershed.typed(watershed.root(peer)),
      counter_field(),
    )
  watershed.counter_value(peer_counter) |> expect.to_equal(Ok(3))
  exhaust_wait(advance)
  list.length(transport_js.get_cell(outcomes)) |> expect.to_equal(1)
  watershed.close(document)
  watershed.close(peer)
}

@target(javascript)
pub fn ensure_adopts_a_field_replayed_during_the_handshake_test() -> Nil {
  let sluice = sluice_js.start(tenant: "default", document: "ensure-existing")
  let advance = fn(milliseconds) { sluice_js.advance(sluice, milliseconds) }
  let author = sluice_js.connect(sluice, "author")
  sluice_js.settle(sluice)
  let assert Ok(counter) = watershed.create_counter(author)
  watershed.increment(counter, 7)
  watershed.set_counter_field(
    watershed.typed(watershed.root(author)),
    counter_field(),
    counter,
  )
  sluice_js.settle(sluice)
  let peer = sluice_js.connect(sluice, "reader")
  let outcomes = transport_js.new_cell([])
  watershed.ensure_counter(
    peer,
    watershed.typed(watershed.root(peer)),
    counter_field(),
    fn(outcome) {
      transport_js.set_cell(outcomes, [
        outcome,
        ..transport_js.get_cell(outcomes)
      ])
    },
  )
  transport_js.get_cell(outcomes) |> expect.to_equal([])
  sluice_js.settle(sluice)
  advance(200)
  let assert [Ok(adopted)] = transport_js.get_cell(outcomes)
  watershed.counter_value(adopted) |> expect.to_equal(Ok(7))
  watershed.counter_handle_of(adopted)
  |> json.to_string
  |> expect.to_equal(json.to_string(watershed.counter_handle_of(counter)))
  watershed.is_synced(peer) |> expect.to_be_true()
  watershed.close(author)
  watershed.close(peer)
}

@target(javascript)
pub fn ensure_times_out_without_seeding_after_a_late_handshake_test() -> Nil {
  let sluice = sluice_js.start(tenant: "default", document: "ensure-timeout")
  let advance = fn(milliseconds) { sluice_js.advance(sluice, milliseconds) }
  let document = sluice_js.connect(sluice, "author")
  let outcomes = transport_js.new_cell([])
  watershed.ensure_counter(
    document,
    watershed.typed(watershed.root(document)),
    counter_field(),
    fn(outcome) {
      transport_js.set_cell(outcomes, [
        outcome,
        ..transport_js.get_cell(outcomes)
      ])
    },
  )
  transport_js.get_cell(outcomes) |> expect.to_equal([])
  exhaust_wait(advance)
  let assert [Error(_)] = transport_js.get_cell(outcomes)
  sluice_js.settle(sluice)
  exhaust_wait(advance)
  watershed.has(watershed.root(document), "counter") |> expect.to_be_false()
  list.length(transport_js.get_cell(outcomes)) |> expect.to_equal(1)
  watershed.close(document)
}

@target(javascript)
pub fn ensure_does_not_report_an_unacknowledged_seed_as_success_test() -> Nil {
  let sluice = sluice_js.start(tenant: "default", document: "ensure-unacked")
  let advance = fn(milliseconds) { sluice_js.advance(sluice, milliseconds) }
  let document = sluice_js.connect(sluice, "author")
  sluice_js.settle(sluice)
  let outcomes = transport_js.new_cell(None)
  watershed.ensure_counter(
    document,
    watershed.typed(watershed.root(document)),
    counter_field(),
    fn(outcome) { transport_js.set_cell(outcomes, Some(outcome)) },
  )
  watershed.is_synced(document) |> expect.to_be_false()
  exhaust_wait(advance)
  let assert Some(Error(_)) = transport_js.get_cell(outcomes)
  watershed.close(document)
}

@target(javascript)
pub fn ensure_reports_failure_if_the_document_closes_while_waiting_test() -> Nil {
  let sluice = sluice_js.start(tenant: "default", document: "ensure-closed")
  let advance = fn(milliseconds) { sluice_js.advance(sluice, milliseconds) }
  let document = sluice_js.connect(sluice, "author")
  let outcomes = transport_js.new_cell([])
  watershed.ensure_counter(
    document,
    watershed.typed(watershed.root(document)),
    counter_field(),
    fn(outcome) {
      transport_js.set_cell(outcomes, [
        outcome,
        ..transport_js.get_cell(outcomes)
      ])
    },
  )
  transport_js.get_cell(outcomes) |> expect.to_equal([])
  watershed.close(document)
  exhaust_wait(advance)
  let assert [Error(_)] = transport_js.get_cell(outcomes)
  watershed.has(watershed.root(document), "counter") |> expect.to_be_false()
}
