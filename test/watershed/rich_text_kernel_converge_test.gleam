import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import qcheck
import watershed/fuzz/kernel_fuzz
import watershed/json_ot.{VBool, VObject, VString}
import watershed/json_ot_gen.{type Rng, new_rng, rand_int}
import watershed/rich_text
import watershed/rich_text_kernel.{type RichTextState, type RichTextWireOp} as kernel

const client_count = 3

type Entry {
  Entry(seq: Int, author: Int, wire: RichTextWireOp)
}

type Client {
  Client(state: RichTextState, delivered: Int, outbox: List(RichTextWireOp))
}

type Sim {
  Sim(clients: List(Client), log: List(Entry))
}

fn ids() -> List(Int) {
  list.index_map(list.repeat(Nil, client_count), fn(_, id) { id })
}

fn initial_document() -> rich_text.Document {
  let assert Ok(document) =
    rich_text.document_from_json_string(
      "[{\"insert\":\"a😀\"},{\"insert\":{\"image\":\"seed\"}}]",
    )
  document
}

fn get(sim: Sim, id: Int) -> Client {
  case list.drop(sim.clients, id) {
    [client, ..] -> client
    [] -> panic as "client id out of range"
  }
}

fn put(sim: Sim, id: Int, client: Client) -> Sim {
  Sim(
    ..sim,
    clients: list.index_map(sim.clients, fn(existing, index) {
      case index == id {
        True -> client
        False -> existing
      }
    }),
  )
}

fn new_sim() -> Sim {
  Sim(
    ids()
      |> list.map(fn(id) {
        Client(kernel.from_document(id, initial_document()), 0, [])
      }),
    [],
  )
}

/// Every generated delta uses only document start/end or total-length spans.
/// Thus deletes and formatting never split a supplementary UTF-16 character.
fn gen_delta(
  document: rich_text.Document,
  rng: Rng,
) -> #(rich_text.Delta, Rng) {
  let #(choice, rng) = rand_int(rng, 5)
  let length = rich_text.document_length(document)
  let empty = rich_text.empty_delta()
  case choice {
    // Front insertion. The seeded document carries a supplementary code
    // point; generated edits avoid an upstream compose split of an inserted
    // surrogate pair against a leading embed.
    0 -> {
      let assert Ok(delta) =
        rich_text.delta_insert_text(empty, "x", rich_text.attributes([]))
      #(delta, rng)
    }
    // End insertion is always a scalar boundary.
    1 if length > 0 -> {
      let assert Ok(prefix) =
        rich_text.delta_retain(empty, length, rich_text.attributes([]))
      let assert Ok(delta) =
        rich_text.delta_insert_text(prefix, "y", rich_text.attributes([]))
      #(delta, rng)
    }
    // Formatting covers an entire valid document span.
    2 if length > 0 -> {
      let assert Ok(delta) =
        rich_text.delta_retain(
          empty,
          length,
          rich_text.attributes([#("bold", VBool(True))]),
        )
      #(delta, rng)
    }
    // Deletes also cover the full document, preserving UTF-16 boundaries.
    3 if length > 0 -> {
      let assert Ok(delta) = rich_text.delta_delete(empty, length)
      #(delta, rng)
    }
    // Embedded inserts exercise unit-length non-text content.
    _ -> {
      let assert Ok(delta) =
        rich_text.delta_insert_embed(
          empty,
          VObject([#("image", VString("generated"))]),
          rich_text.attributes([]),
        )
      #(delta, rng)
    }
  }
}

fn msn(sim: Sim) -> Int {
  let min_delivered =
    list.fold(sim.clients, list.length(sim.log), fn(acc, client) {
      int.min(acc, client.delivered)
    })
  let with_outbox =
    list.fold(sim.clients, min_delivered, fn(acc, client) {
      list.fold(client.outbox, acc, fn(acc, wire) { int.min(acc, wire.ref_seq) })
    })
  list.fold(sim.log, with_outbox, fn(acc, entry) {
    case entry.seq > min_delivered {
      True -> int.min(acc, entry.wire.ref_seq)
      False -> acc
    }
  })
}

fn submit(sim: Sim, id: Int, rng: Rng) -> #(Sim, Rng) {
  let client = get(sim, id)
  let assert Ok(document) = kernel.view(client.state)
  let #(delta, rng) = gen_delta(document, rng)
  let #(state, maybe_wire, _) = case
    kernel.submit(client.state, delta, client.delivered)
  {
    Ok(value) -> value
    Error(error) ->
      panic as {
        "generated valid delta was rejected: "
        <> string.inspect(#(rich_text.document_to_json(document), delta, error))
      }
  }
  let outbox = case maybe_wire {
    None -> client.outbox
    Some(wire) -> list.append(client.outbox, [wire])
  }
  #(put(sim, id, Client(..client, state: state, outbox: outbox)), rng)
}

fn sequence(sim: Sim, id: Int) -> Sim {
  let client = get(sim, id)
  case client.outbox {
    [] -> sim
    [wire, ..rest] ->
      put(
        Sim(
          ..sim,
          log: list.append(sim.log, [Entry(list.length(sim.log) + 1, id, wire)]),
        ),
        id,
        Client(..client, outbox: rest),
      )
  }
}

fn deliver_one(sim: Sim, id: Int) -> Sim {
  let client = get(sim, id)
  case list.drop(sim.log, client.delivered) {
    [] -> sim
    [entry, ..] -> {
      let min = msn(sim)
      case entry.author == id {
        True -> {
          let assert Ok(#(state, _)) =
            kernel.ack_local(client.state, entry.wire, entry.seq, min)
          let #(state, released) = kernel.take_outbound(state)
          let outbox = case released {
            None -> client.outbox
            Some(wire) -> list.append(client.outbox, [wire])
          }
          put(sim, id, Client(state, client.delivered + 1, outbox))
        }
        False -> {
          let assert Ok(#(state, _)) =
            kernel.apply_remote(
              client.state,
              entry.wire,
              entry.seq,
              entry.author,
              min,
            )
          put(
            sim,
            id,
            Client(..client, state: state, delivered: client.delivered + 1),
          )
        }
      }
    }
  }
}

fn deliver_until(sim: Sim, id: Int, target: Int) -> Sim {
  case get(sim, id).delivered >= target {
    True -> sim
    False -> deliver_until(deliver_one(sim, id), id, target)
  }
}

fn deliver_all(sim: Sim) -> Sim {
  list.fold(ids(), sim, fn(sim, id) {
    deliver_until(sim, id, list.length(sim.log))
  })
}

fn sequence_all(sim: Sim) -> Sim {
  case list.all(sim.clients, fn(client) { client.outbox == [] }) {
    True -> sim
    False -> sequence_all(list.fold(ids(), sim, sequence))
  }
}

fn drain(sim: Sim) -> Sim {
  let sim = deliver_all(sequence_all(sim))
  case
    list.all(sim.clients, fn(client) {
      client.outbox == [] && client.delivered == list.length(sim.log)
    })
  {
    True -> sim
    False -> drain(sim)
  }
}

fn play(sim: Sim, rng: Rng, rounds: Int) -> #(Sim, Rng) {
  case rounds <= 0 {
    True -> #(sim, rng)
    False -> {
      let #(action, rng) = rand_int(rng, 10)
      let #(id, rng) = rand_int(rng, client_count)
      let #(sim, rng) = case action {
        n if n < 5 -> submit(sim, id, rng)
        n if n < 7 -> #(sequence(sim, id), rng)
        n if n < 9 -> #(deliver_one(sim, id), rng)
        _ -> #(deliver_one(sequence(sim, id), id), rng)
      }
      play(sim, rng, rounds - 1)
    }
  }
}

fn run(seed: Int) -> Result(Nil, String) {
  let #(sim, _) = play(new_sim(), new_rng(seed), 40)
  let sim = drain(sim)
  let documents = list.map(sim.clients, fn(client) { client.state.sequenced })
  let pending =
    list.any(sim.clients, fn(client) {
      client.state.inflight != None || client.state.buffer != None
    })
  case documents {
    [] -> Ok(Nil)
    [first, ..rest] -> {
      case list.all(rest, fn(document) { document == first }) && !pending {
        True -> Ok(Nil)
        False ->
          Error(
            "rich-text convergence failure:\n"
            <> string.inspect(
              list.map(sim.clients, fn(client) {
                #(
                  rich_text.document_to_json(client.state.sequenced),
                  client.state.inflight,
                  client.state.buffer,
                )
              }),
            )
            <> "\nlog:\n"
            <> string.inspect(sim.log),
          )
      }
    }
  }
}

pub fn clients_converge_with_text_formatting_deletes_emoji_and_embeds_test() {
  let config = kernel_fuzz.config_from_env()
  qcheck.run(config, qcheck.uniform_int(), fn(seed) {
    case run(seed) {
      Ok(Nil) -> Nil
      Error(message) ->
        panic as {
          "rich-text convergence failure (seed="
          <> int.to_string(seed)
          <> "):\n"
          <> message
        }
    }
  })
}
