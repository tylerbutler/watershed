@target(javascript)
import gleam/json
@target(javascript)
import gleam/list
@target(javascript)
import gleam/option.{type Option, None, Some}
@target(javascript)
import gleam/string

@target(javascript)
import markdown_notes_lustre/doc_schema
@target(javascript)
import markdown_notes_lustre/p2p_fake
@target(javascript)
import watershed/crdt_js.{type CrdtConnection, type CrdtDocument, type Handle}
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

const room = "mdnotes-smoke"

const compatibility = "markdown-notes/v2"

const note_name = "field notes"

@external(javascript, "./smoke_ffi.mjs", "log")
fn log(message: String) -> Nil

@external(javascript, "./smoke_ffi.mjs", "exit")
fn exit(code: Int) -> Nil

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

pub fn main() -> Nil {
  log("smoke: p2p round trip, reconnect, and persistence attach")

  let world = p2p_fake.new_world()
  let alpha = spawn(world, "alpha")
  let beta = spawn(world, "beta")
  p2p_fake.settle(world)

  let channels_a = bootstrap(alpha.document)
  p2p_fake.settle(world)
  let channels_b = channels_of(beta.document)

  let text_a = create_note(alpha.document, channels_a, note_name)
  p2p_fake.settle(world)
  let text_b = open_note(beta.document, channels_b, note_name)
  assert_text_equal(text_a, text_b, "address round trip")

  log("  severing peers and editing both sides")
  p2p_fake.sever(world, alpha.replica, beta.replica)
  p2p_fake.settle(world)
  let assert Ok(Nil) = crdt_js.text_insert(text_a, 29, " (checked)")
  let assert Ok(Nil) = crdt_js.text_append(text_b, "\nthird, from b\n")
  p2p_fake.settle(world)

  let assert Ok(alpha_offline) = crdt_js.text_value(text_a)
  let assert Ok(beta_offline) = crdt_js.text_value(text_b)
  case alpha_offline == beta_offline {
    True -> fail("partitioned peers should diverge before reconnect")
    False -> Nil
  }

  log("  reconnecting peers")
  p2p_fake.reconnect(world, alpha.replica, beta.replica)
  p2p_fake.settle(world)
  assert_text_equal(text_a, text_b, "reconnect convergence")
  let assert Ok(converged) = crdt_js.text_value(text_a)
  assert_contains(converged, "(checked)", "A offline edit survived")
  assert_contains(converged, "third, from b", "B offline edit survived")

  log(
    "  saving alpha, dropping it, loading from disk, editing, and reattaching",
  )
  let store = memory(None)
  let save_result = transport_js.new_cell(None)
  persist_js.save(memory_storage(store), alpha.document, fn(result) {
    transport_js.set_cell(save_result, Some(result))
  })
  case transport_js.get_cell(save_result) {
    Some(Ok(_digest)) -> Nil
    _ -> fail("could not save alpha snapshot")
  }

  crdt_js.close(alpha.connection)
  p2p_fake.settle(world)

  let assert Ok(Nil) = crdt_js.text_append(text_b, "fourth, from beta\n")
  p2p_fake.settle(world)

  let loaded = transport_js.new_cell(None)
  persist_js.load(memory_storage(store), config(world, "restored"), fn(result) {
    transport_js.set_cell(loaded, Some(result))
  })
  let restored = case transport_js.get_cell(loaded) {
    Some(Ok(Some(document))) -> document
    _ -> fail("could not load persisted snapshot")
  }

  let restored_channels = channels_of(restored)
  let restored_text = open_note(restored, restored_channels, note_name)
  let assert Ok(Nil) = crdt_js.text_append(restored_text, "fifth, from disk\n")
  let _connection =
    crdt_js.attach_with_rtc(
      restored,
      on_ready: fn(_outcome) { Nil },
      on_status: fn(_status) { Nil },
      rtc: p2p_fake.rtc(world, crdt_js.replica_id(restored)),
    )
  p2p_fake.settle(world)

  assert_text_equal(restored_text, text_b, "persistence attach convergence")
  let assert Ok(final_text) = crdt_js.text_value(restored_text)
  assert_contains(final_text, "fourth, from beta", "live beta edit merged")
  assert_contains(final_text, "fifth, from disk", "disk edit merged")
  assert_digest_equal(restored, beta.document, "persistence attach digest")

  log("SMOKE PASS")
  exit(0)
}

fn spawn(world: p2p_fake.World, label: String) -> Member {
  let assert Ok(document) = crdt_js.new_document(config(world, label))
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
  label: String,
) -> crdt_js.Config(OrMapChannel) {
  crdt_js.config(
    room_id: room,
    replica_label: label,
    compatibility_tag: compatibility,
    root: doc_schema.root(),
    signaling: p2p_fake.signaling(world),
  )
}

fn bootstrap(document: CrdtDocument(OrMapChannel)) -> Channels {
  let root = crdt_js.root(document)
  let tags = case crdt_js.or_map_value(root, key: doc_schema.tags_key()) {
    Ok(Ok(or_map_kernel.Register(address))) -> {
      let assert Ok(tags) =
        crdt_js.resolve_channel(
          document,
          doc_schema.tags_kind(),
          address: address,
        )
      tags
    }
    _ -> {
      let assert Ok(tags) =
        crdt_js.create_channel(document, doc_schema.tags_kind())
      let assert Ok(Nil) =
        crdt_js.or_map_set(
          root,
          key: doc_schema.tags_key(),
          value: crdt_js.address(tags),
        )
      tags
    }
  }
  let order = case crdt_js.or_map_value(root, key: doc_schema.order_key()) {
    Ok(Ok(or_map_kernel.Register(address))) -> {
      let assert Ok(order) =
        crdt_js.resolve_channel(
          document,
          doc_schema.order_kind(),
          address: address,
        )
      order
    }
    _ -> {
      let assert Ok(order) =
        crdt_js.create_channel(document, doc_schema.order_kind())
      let assert Ok(Nil) =
        crdt_js.or_map_set(
          root,
          key: doc_schema.order_key(),
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
    crdt_js.or_map_value(root, key: doc_schema.tags_key())
  let assert Ok(tags) =
    crdt_js.resolve_channel(
      document,
      doc_schema.tags_kind(),
      address: tags_address,
    )
  let assert Ok(Ok(or_map_kernel.Register(order_address))) =
    crdt_js.or_map_value(root, key: doc_schema.order_key())
  let assert Ok(order) =
    crdt_js.resolve_channel(
      document,
      doc_schema.order_kind(),
      address: order_address,
    )
  Channels(root:, tags:, order:)
}

fn create_note(
  document: CrdtDocument(OrMapChannel),
  channels: Channels,
  name: String,
) -> Handle(TextChannel) {
  let assert Ok(text) = crdt_js.create_channel(document, doc_schema.text_kind())
  let assert Ok(Nil) =
    crdt_js.text_append(
      text,
      "# " <> name <> "\nfirst paragraph\n\nsecond paragraph\n",
    )
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
    crdt_js.resolve_channel(document, doc_schema.text_kind(), address: address)
  text
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

fn assert_text_equal(
  left: Handle(TextChannel),
  right: Handle(TextChannel),
  label: String,
) -> Nil {
  let assert Ok(left_text) = crdt_js.text_value(left)
  let assert Ok(right_text) = crdt_js.text_value(right)
  case left_text == right_text {
    True -> log("  " <> label <> " ok")
    False -> fail(label <> " diverged")
  }
}

fn assert_contains(text: String, needle: String, label: String) -> Nil {
  case string.contains(text, needle) {
    True -> log("  " <> label <> " ok")
    False -> fail(label <> " missing")
  }
}

fn assert_digest_equal(
  left: CrdtDocument(a),
  right: CrdtDocument(a),
  label: String,
) -> Nil {
  case crdt_js.digest(left) == crdt_js.digest(right) {
    True -> log("  " <> label <> " ok")
    False -> fail(label <> " diverged")
  }
}

fn fail(reason: String) -> a {
  log("SMOKE FAIL: " <> reason)
  exit(1)
  panic as reason
}
