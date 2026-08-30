//// Deterministic p2p convergence tests for the markdown notes layout.
////
//// Two peers run through the in-package `p2p_fake`: a queued in-memory
//// signaling hub plus a fake WebRTC mesh. The room is fully deterministic,
//// so create/open races, partitions, reconnects, and persistence attach all
//// run without sleeps or a live server.

@target(javascript)
import gleam/dynamic/decode
@target(javascript)
import gleam/json
@target(javascript)
import gleam/list
@target(javascript)
import gleam/option.{type Option, None, Some}
@target(javascript)
import gleam/result
@target(javascript)
import gleam/string
@target(javascript)
import gleeunit/should

@target(javascript)
import markdown_notes_lustre/document_schema
@target(javascript)
import markdown_notes_lustre/p2p_fake
@target(javascript)
import markdown_notes_lustre/sidebar
@target(javascript)
import markdown_notes_lustre/toolbar
@target(javascript)
import watershed/crdt_js.{
  type Config, type CrdtConnection, type CrdtDocument, type Handle,
}
@target(javascript)
import watershed/or_map_kernel
@target(javascript)
import watershed/persist_js
@target(javascript)
import watershed/schema.{
  type OrMapChannel, type OrSetChannel, type SequenceChannel, type TextChannel,
}
@target(javascript)
import watershed/transport_js.{type Cell}

type Member {
  Member(
    document: CrdtDocument(OrMapChannel),
    connection: CrdtConnection,
    replica: String,
  )
}

type Channels {
  Channels(
    root: Handle(OrMapChannel),
    tags: Handle(OrSetChannel),
    order: Handle(SequenceChannel),
  )
}

type Memory {
  Memory(value: Cell(Option(String)))
}

type UpdateDecision {
  WriteSnapshot(String)
  AbortUpdate
  NoDecision
}

fn room(name: String) -> #(p2p_fake.World, Member, Member, Channels, Channels) {
  let world = p2p_fake.new_world()
  let alpha = spawn(world, name, "alpha")
  let beta = spawn(world, name, "beta")
  p2p_fake.settle(world)

  let channels_a = bootstrap(alpha.document)
  p2p_fake.settle(world)
  let channels_b = channels_of(beta.document)
  #(world, alpha, beta, channels_a, channels_b)
}

fn spawn(world: p2p_fake.World, room: String, label: String) -> Member {
  let assert Ok(document) = crdt_js.new_document(config(world, room, label))
  let connection =
    crdt_js.attach_with_rtc(
      document,
      on_ready: fn(_outcome) { Nil },
      on_status: fn(_status) { Nil },
      rtc: p2p_fake.rtc(world, crdt_js.replica_id(document)),
    )
  Member(document:, connection:, replica: crdt_js.replica_id(document))
}

fn config(
  world: p2p_fake.World,
  room: String,
  label: String,
) -> Config(OrMapChannel) {
  crdt_js.config(
    room_id: room,
    replica_label: label,
    compatibility_tag: "markdown-notes/v2",
    root: document_schema.root(),
    signaling: p2p_fake.signaling(world),
  )
}

fn bootstrap(document: CrdtDocument(OrMapChannel)) -> Channels {
  let root = crdt_js.root(document)
  let tags = case crdt_js.or_map_value(root, key: document_schema.tags_key()) {
    Ok(Ok(or_map_kernel.Register(address))) -> {
      let assert Ok(tags) =
        crdt_js.resolve_channel(
          document,
          document_schema.tags_kind(),
          address: address,
        )
      tags
    }
    _ -> {
      let assert Ok(tags) =
        crdt_js.create_channel(document, document_schema.tags_kind())
      let assert Ok(Nil) =
        crdt_js.or_map_set(
          root,
          key: document_schema.tags_key(),
          value: crdt_js.address(tags),
        )
      tags
    }
  }
  let order = case
    crdt_js.or_map_value(root, key: document_schema.order_key())
  {
    Ok(Ok(or_map_kernel.Register(address))) -> {
      let assert Ok(order) =
        crdt_js.resolve_channel(
          document,
          document_schema.order_kind(),
          address: address,
        )
      order
    }
    _ -> {
      let assert Ok(order) =
        crdt_js.create_channel(document, document_schema.order_kind())
      let assert Ok(Nil) =
        crdt_js.or_map_set(
          root,
          key: document_schema.order_key(),
          value: crdt_js.address(order),
        )
      order
    }
  }
  Channels(root:, tags:, order:)
}

fn channels_of(document: CrdtDocument(OrMapChannel)) -> Channels {
  let root = crdt_js.root(document)
  let assert Ok(Ok(or_map_kernel.Register(tags_address))) =
    crdt_js.or_map_value(root, key: document_schema.tags_key())
  let assert Ok(tags) =
    crdt_js.resolve_channel(
      document,
      document_schema.tags_kind(),
      address: tags_address,
    )
  let assert Ok(Ok(or_map_kernel.Register(order_address))) =
    crdt_js.or_map_value(root, key: document_schema.order_key())
  let assert Ok(order) =
    crdt_js.resolve_channel(
      document,
      document_schema.order_kind(),
      address: order_address,
    )
  Channels(root:, tags:, order:)
}

fn create_note(
  document: CrdtDocument(OrMapChannel),
  channels: Channels,
  name: String,
) -> Handle(TextChannel) {
  let assert Ok(text) =
    crdt_js.create_channel(document, document_schema.text_kind())
  let assert Ok(Nil) = crdt_js.text_append(text, "# " <> name <> "\n")
  let assert Ok(Nil) =
    crdt_js.or_map_set(channels.root, key: name, value: crdt_js.address(text))
  let assert Ok(values) = crdt_js.sequence_values(channels.order)
  let assert Ok(Nil) =
    crdt_js.sequence_insert(
      channels.order,
      index: list.length(values),
      value: json.string(name),
    )
  text
}

fn open_note(
  document: CrdtDocument(OrMapChannel),
  channels: Channels,
  name: String,
) -> Handle(TextChannel) {
  let assert Ok(Ok(or_map_kernel.Register(address))) =
    crdt_js.or_map_value(channels.root, key: name)
  let assert Ok(text) =
    crdt_js.resolve_channel(
      document,
      document_schema.text_kind(),
      address: address,
    )
  text
}

fn text_value(text: Handle(TextChannel)) -> String {
  let assert Ok(value) = crdt_js.text_value(text)
  value
}

fn note_names_unsorted(channels: Channels) -> List(String) {
  let assert Ok(entries) = crdt_js.or_map_entries(channels.root)
  entries
  |> list.filter_map(fn(entry) {
    case document_schema.is_reserved(entry.0), entry.1 {
      True, _ -> Error(Nil)
      False, or_map_kernel.Register(_) -> Ok(entry.0)
      False, or_map_kernel.Tally(_) -> Error(Nil)
    }
  })
}

fn note_names(channels: Channels) -> List(String) {
  note_names_unsorted(channels) |> list.sort(by: string.compare)
}

fn order_names(channels: Channels) -> List(String) {
  let assert Ok(values) = crdt_js.sequence_values(channels.order)
  values
  |> list.filter_map(fn(value) {
    json.parse(json.to_string(value), decode.string)
    |> result.replace_error(Nil)
  })
}

fn rendered_order(channels: Channels) -> List(String) {
  sidebar.display_order(note_names_unsorted(channels), order_names(channels))
}

fn memory(initial: Option(String)) -> Memory {
  Memory(transport_js.new_cell(initial))
}

fn memory_storage(memory: Memory) -> persist_js.Storage {
  persist_js.storage(
    get: fn(_key, done) {
      let Memory(value:) = memory
      done(Ok(transport_js.get_cell(value)))
    },
    update: fn(_key, transform, on_ok, on_abort, on_error) {
      let Memory(value:) = memory
      let current = transport_js.get_cell(value)
      let decision = transport_js.new_cell(NoDecision)
      transform(
        case current {
          Some(_) -> True
          None -> False
        },
        case current {
          Some(raw) -> raw
          None -> ""
        },
        fn(snapshot) {
          case transport_js.get_cell(decision) {
            NoDecision ->
              transport_js.set_cell(decision, WriteSnapshot(snapshot))
            WriteSnapshot(_) | AbortUpdate -> Nil
          }
        },
        fn() {
          case transport_js.get_cell(decision) {
            NoDecision -> transport_js.set_cell(decision, AbortUpdate)
            WriteSnapshot(_) | AbortUpdate -> Nil
          }
        },
      )
      case transport_js.get_cell(decision) {
        WriteSnapshot(snapshot) -> {
          transport_js.set_cell(value, Some(snapshot))
          on_ok()
        }
        AbortUpdate -> on_abort()
        NoDecision -> on_error("memory storage update did not write or abort")
      }
    },
  )
}

// ── Address round trip ───────────────────────────────────────────────────────

@target(javascript)
pub fn created_note_opens_identically_on_the_other_client_test() -> Nil {
  let #(world, alpha, beta, channels_a, channels_b) = room("mn2-round-trip")

  let text_a = create_note(alpha.document, channels_a, "meeting notes")
  p2p_fake.settle(world)

  note_names(channels_b) |> should.equal(["meeting notes"])
  let text_b = open_note(beta.document, channels_b, "meeting notes")
  text_value(text_b) |> should.equal(text_value(text_a))
  text_value(text_b) |> should.equal("# meeting notes\n")
}

// ── MN3: concurrent typing in one note ───────────────────────────────────────

@target(javascript)
pub fn concurrent_typing_in_one_note_converges_test() -> Nil {
  let #(world, alpha, beta, channels_a, channels_b) = room("mn3-typing")

  let text_a = create_note(alpha.document, channels_a, "draft")
  p2p_fake.settle(world)
  let text_b = open_note(beta.document, channels_b, "draft")

  let assert Ok(Nil) = crdt_js.text_append(text_a, "alpha from a\n")
  let assert Ok(Nil) = crdt_js.text_insert(text_b, 2, "shared ")
  p2p_fake.settle(world)

  text_value(text_a) |> should.equal(text_value(text_b))
  text_value(text_a) |> should.equal("# shared draft\nalpha from a\n")
}

// ── MN4: race 1, toolbar vs. typing inside a word ───────────────────────────

@target(javascript)
pub fn race_one_bold_vs_concurrent_typing_inside_word_test() -> Nil {
  let #(world, alpha, beta, channels_a, channels_b) = room("mn4-race-one")

  let text_a = create_note(alpha.document, channels_a, "fmt")
  let assert Ok(Nil) = crdt_js.text_append(text_a, "meet the deadline now\n")
  p2p_fake.settle(world)
  let text_b = open_note(beta.document, channels_b, "fmt")

  let assert Ok(Nil) =
    list.try_each(
      toolbar.edits(toolbar.Bold, text_value(text_a), #(15, 23)),
      fn(edit) { crdt_js.text_insert(text_a, edit.0, edit.1) },
    )
  let assert Ok(Nil) = crdt_js.text_insert(text_b, 19, "LATE")
  p2p_fake.settle(world)

  text_value(text_a) |> should.equal(text_value(text_b))
  text_value(text_a)
  |> should.equal("# fmt\nmeet the **deadLATEline** now\n")
}

// ── MN5: race 2, partitioned edits reconverge ───────────────────────────────

@target(javascript)
pub fn race_two_divergent_offline_edits_reconverge_test() -> Nil {
  let #(world, alpha, beta, channels_a, channels_b) = room("mn5-offline")

  let text_a = create_note(alpha.document, channels_a, "field notes")
  let assert Ok(Nil) =
    crdt_js.text_append(text_a, "first paragraph\n\nsecond paragraph\n")
  p2p_fake.settle(world)
  let text_b = open_note(beta.document, channels_b, "field notes")

  p2p_fake.sever(world, alpha.replica, beta.replica)
  p2p_fake.settle(world)

  let assert Ok(Nil) = crdt_js.text_insert(text_a, 29, " (checked)")
  let assert Ok(Nil) = crdt_js.text_append(text_b, "\nthird, from b\n")
  p2p_fake.settle(world)

  text_value(text_a)
  |> should.equal(
    "# field notes\nfirst paragraph (checked)\n\nsecond paragraph\n",
  )
  text_value(text_b)
  |> should.equal(
    "# field notes\nfirst paragraph\n\nsecond paragraph\n\nthird, from b\n",
  )

  p2p_fake.reconnect(world, alpha.replica, beta.replica)
  p2p_fake.settle(world)

  text_value(text_a) |> should.equal(text_value(text_b))
  text_value(text_a)
  |> should.equal(
    "# field notes\nfirst paragraph (checked)\n\nsecond paragraph\n\nthird, from b\n",
  )
}

// ── MN5: race 4, delete while editing ───────────────────────────────────────

@target(javascript)
pub fn race_four_delete_while_editing_keeps_the_channel_working_test() -> Nil {
  let #(world, alpha, beta, channels_a, channels_b) = room("mn5-delete")

  let text_a = create_note(alpha.document, channels_a, "doomed")
  p2p_fake.settle(world)
  let text_b = open_note(beta.document, channels_b, "doomed")

  let assert Ok(Nil) = crdt_js.or_map_remove(channels_a.root, key: "doomed")
  p2p_fake.settle(world)
  note_names(channels_a) |> should.equal([])
  note_names(channels_b) |> should.equal([])

  let assert Ok(Nil) = crdt_js.text_append(text_b, "still here\n")
  p2p_fake.settle(world)
  text_value(text_a) |> should.equal(text_value(text_b))
  text_value(text_b) |> should.equal("# doomed\nstill here\n")
}

@target(javascript)
pub fn race_four_concurrent_reset_beats_remove_test() -> Nil {
  let #(world, alpha, beta, channels_a, channels_b) = room("mn5-reset")

  let text_a = create_note(alpha.document, channels_a, "contested")
  p2p_fake.settle(world)
  let text_b = open_note(beta.document, channels_b, "contested")

  let assert Ok(Nil) = crdt_js.or_map_remove(channels_a.root, key: "contested")
  let assert Ok(Nil) =
    crdt_js.or_map_set(
      channels_b.root,
      key: "contested",
      value: crdt_js.address(text_b),
    )
  p2p_fake.settle(world)

  note_names(channels_a) |> should.equal(["contested"])
  note_names(channels_b) |> should.equal(["contested"])
  text_value(open_note(alpha.document, channels_a, "contested"))
  |> should.equal(text_value(text_a))
}

// ── MN7: race 5, re-tag vs. untag ───────────────────────────────────────────

@target(javascript)
pub fn race_five_readd_beats_concurrent_untag_test() -> Nil {
  let #(world, alpha, _beta, channels_a, channels_b) = room("mn7-retag")

  let _ = create_note(alpha.document, channels_a, "todo")
  let assert Ok(Nil) = crdt_js.or_set_add(channels_a.tags, "todo\turgent")
  p2p_fake.settle(world)
  let assert Ok(values) = crdt_js.or_set_values(channels_b.tags)
  values |> should.equal(["todo\turgent"])

  let assert Ok(Nil) = crdt_js.or_set_remove(channels_a.tags, "todo\turgent")
  let assert Ok(Nil) = crdt_js.or_set_add(channels_b.tags, "todo\turgent")
  p2p_fake.settle(world)

  let assert Ok(values_a) = crdt_js.or_set_values(channels_a.tags)
  values_a |> should.equal(["todo\turgent"])
  let assert Ok(values_b) = crdt_js.or_set_values(channels_b.tags)
  values_b |> should.equal(["todo\turgent"])
}

// ── MN8: race 6, create vs. reorder ──────────────────────────────────────────

@target(javascript)
pub fn race_six_create_vs_reorder_converges_test() -> Nil {
  let #(world, alpha, _beta, channels_a, channels_b) = room("mn8-reorder")

  let _ = create_note(alpha.document, channels_a, "one")
  let _ = create_note(alpha.document, channels_a, "two")
  p2p_fake.settle(world)

  let _ = create_note(alpha.document, channels_a, "three")
  let assert Ok(Nil) = crdt_js.sequence_move(channels_b.order, from: 0, to: 1)
  p2p_fake.settle(world)

  order_names(channels_a) |> should.equal(order_names(channels_b))
  rendered_order(channels_a) |> should.equal(rendered_order(channels_b))
}

@target(javascript)
pub fn race_six_doubled_create_renders_once_test() -> Nil {
  let #(world, alpha, beta, channels_a, channels_b) = room("mn8-doubled")

  let _ = create_note(alpha.document, channels_a, "dup")
  let _ = create_note(beta.document, channels_b, "dup")
  p2p_fake.settle(world)

  order_names(channels_a) |> should.equal(["dup", "dup"])
  rendered_order(channels_a) |> should.equal(["dup"])
  rendered_order(channels_b) |> should.equal(["dup"])
}

// ── Race 3: concurrent create, same name ─────────────────────────────────────

@target(javascript)
pub fn concurrent_create_same_name_converges_on_one_handle_test() -> Nil {
  let #(world, alpha, beta, channels_a, channels_b) = room("mn2-create-race")

  let _ = create_note(alpha.document, channels_a, "shared")
  let _ = create_note(beta.document, channels_b, "shared")
  p2p_fake.settle(world)

  note_names(channels_a) |> should.equal(["shared"])
  note_names(channels_b) |> should.equal(["shared"])
  let assert Ok(Ok(or_map_kernel.Register(address_a))) =
    crdt_js.or_map_value(channels_a.root, key: "shared")
  let assert Ok(Ok(or_map_kernel.Register(address_b))) =
    crdt_js.or_map_value(channels_b.root, key: "shared")
  address_a |> should.equal(address_b)

  let text_a = open_note(alpha.document, channels_a, "shared")
  let text_b = open_note(beta.document, channels_b, "shared")
  text_value(text_a) |> should.equal(text_value(text_b))
  text_value(text_a) |> should.equal("# shared\n")
}

// ── Persistence: save, drop, load, edit, attach ─────────────────────────────

@target(javascript)
pub fn save_drop_load_edit_and_attach_converges_test() -> Nil {
  let #(world, alpha, beta, channels_a, channels_b) = room("mn-persistence")

  let _text_a = create_note(alpha.document, channels_a, "archive")
  p2p_fake.settle(world)
  let text_b = open_note(beta.document, channels_b, "archive")

  let store = memory(None)
  let saved = transport_js.new_cell(None)
  persist_js.save(memory_storage(store), alpha.document, fn(result) {
    transport_js.set_cell(saved, Some(result))
  })
  let assert Some(Ok(_digest)) = transport_js.get_cell(saved)

  crdt_js.close(alpha.connection)
  p2p_fake.settle(world)

  let assert Ok(Nil) = crdt_js.text_append(text_b, "live beta\n")
  p2p_fake.settle(world)

  let loaded = transport_js.new_cell(None)
  persist_js.load(
    memory_storage(store),
    config(world, "mn-persistence", "restored"),
    fn(result) { transport_js.set_cell(loaded, Some(result)) },
  )
  let restored = case transport_js.get_cell(loaded) {
    Some(Ok(Some(document))) -> document
    _ -> panic as "expected stored snapshot"
  }

  let restored_channels = channels_of(restored)
  let restored_text = open_note(restored, restored_channels, "archive")
  let assert Ok(Nil) = crdt_js.text_append(restored_text, "offline disk\n")
  let _ =
    crdt_js.attach_with_rtc(
      restored,
      on_ready: fn(_outcome) { Nil },
      on_status: fn(_status) { Nil },
      rtc: p2p_fake.rtc(world, crdt_js.replica_id(restored)),
    )
  p2p_fake.settle(world)

  text_value(restored_text) |> should.equal(text_value(text_b))
  { string.contains(text_value(restored_text), "live beta") }
  |> should.equal(True)
  { string.contains(text_value(restored_text), "offline disk") }
  |> should.equal(True)
  crdt_js.digest(restored) |> should.equal(crdt_js.digest(beta.document))
}
