import gleam/json
import gleam/option.{None, Some}
import gleeunit
import gleeunit/should
import watershed
import watershed/crdt_js
import watershed/p2p_transport_js.{type Signaling, Roster, Signaling}
import watershed/schema
import watershed/sluice_js
import watershed/transport_js
import website_samples/board_app
import website_samples/board_schema
import website_samples/mv_register_sample
import website_samples/optimistic_sample
import website_samples/p2p_sample

pub fn main() {
  gleeunit.main()
}

fn test_signaling() -> Signaling {
  Signaling(
    join: fn(room, peer_id, on_signal) {
      on_signal(Roster([]))
      Ok(p2p_transport_js.signaling_session(room: room, peer_id: peer_id))
    },
    send: fn(_, _, _) { Nil },
    leave: fn(_) { Nil },
  )
}

pub fn optimistic_edit_reads_the_pending_value_test() -> Nil {
  let sluice =
    sluice_js.start(tenant: "default", document: "sample-optimistic-edit")
  let document = sluice_js.connect(sluice, "author")
  sluice_js.settle(sluice)

  optimistic_sample.optimistic_edit(watershed.root(document))
  |> should.equal(Ok(json.float(3.4)))

  watershed.close(document)
}

pub fn revision_uses_the_published_field_and_returns_the_write_test() -> Nil {
  schema.channel_field_key(mv_register_sample.revision())
  |> should.equal("revision")

  let sluice =
    sluice_js.start(tenant: "default", document: "sample-revision-write")
  let document = sluice_js.connect(sluice, "author")
  let outcome = transport_js.new_cell(None)

  mv_register_sample.ensure_and_revise(document, "published", fn(result) {
    transport_js.set_cell(outcome, Some(result))
  })
  transport_js.get_cell(outcome) |> should.equal(None)

  sluice_js.settle(sluice)
  sluice_js.advance(sluice, 200)
  sluice_js.settle(sluice)
  sluice_js.advance(sluice, 200)

  transport_js.get_cell(outcome)
  |> should.equal(Some(Ok(["published"])))

  watershed.close(document)
}

pub fn p2p_config_uses_a_counter_root_and_auto_policy_test() -> Nil {
  let assert Ok(document) =
    p2p_sample.p2p_config(test_signaling())
    |> crdt_js.new_document

  crdt_js.pn_counter_value(crdt_js.root(document))
  |> should.equal(Ok(0))
  crdt_js.policy(document) |> should.equal(crdt_js.Auto)
}

pub fn board_fields_work_with_a_real_typed_root_test() -> Nil {
  let sluice =
    sluice_js.start(tenant: "default", document: "sample-board-fields")
  let document = sluice_js.connect(sluice, "author")
  sluice_js.settle(sluice)
  let root = watershed.root_typed(document)

  watershed.set_field(root, board_schema.title(), "Sprint board")
  let assert Ok(cards) = watershed.create_map(document)
  watershed.set_map_field(root, board_schema.cards(), cards)
  let assert Ok(breaches) = watershed.create_counter(document)
  watershed.set_counter_field(root, board_schema.wip_breaches(), breaches)

  watershed.get_field(root, board_schema.title())
  |> should.equal(Ok(Some("Sprint board")))
  watershed.resolve_map_field(document, root, board_schema.cards())
  |> should.equal(Ok(Some(cards)))
  watershed.resolve_counter_field(document, root, board_schema.wip_breaches())
  |> should.equal(Ok(Some(breaches)))

  watershed.close(document)
}

pub fn write_card_decodes_the_published_record_test() -> Nil {
  let sluice =
    sluice_js.start(tenant: "default", document: "sample-card-record")
  let document = sluice_js.connect(sluice, "author")
  sluice_js.settle(sluice)
  let assert Ok(card) = watershed.create_typed_map(document)

  board_app.write_card(card) |> should.equal(Ok(Nil))
  let assert Ok(card_schema) = board_app.card_schema()
  let assert Ok(board_app.CardState(
    title: "Ship it",
    column: "doing",
    owner: None,
  )) = watershed.read(card, card_schema)

  watershed.close(document)
}
