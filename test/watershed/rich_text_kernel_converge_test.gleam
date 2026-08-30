import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import qcheck
import watershed/fuzz/kernel_fuzz
import watershed/json_ot.{VBool, VObject, VString}
import watershed/json_ot_gen.{type Random}
import watershed/ot_client
import watershed/rich_text
import watershed/rich_text_kernel.{type RichTextState, type RichTextWireOp} as kernel

const client_count = 3

type Entry {
  Entry(seq: Int, author: Int, wire: RichTextWireOp)
}

type Client {
  Client(state: RichTextState, delivered: Int, outbox: List(RichTextWireOp))
}

type Simulation {
  Simulation(clients: List(Client), log: List(Entry))
}

fn ids() -> List(Int) {
  list.index_map(list.repeat(Nil, client_count), fn(_, id) { id })
}

fn initial_document() -> rich_text.Document {
  let assert Ok(document) =
    rich_text.parse_document(
      "[{\"insert\":\"a😀\"},{\"insert\":{\"image\":\"seed\"}}]",
    )
  document
}

fn get(simulation: Simulation, id: Int) -> Client {
  case list.drop(simulation.clients, id) {
    [client, ..] -> client
    [] -> panic as "client id out of range"
  }
}

fn put(simulation: Simulation, id: Int, client: Client) -> Simulation {
  Simulation(
    ..simulation,
    clients: list.index_map(simulation.clients, fn(existing, index) {
      case index == id {
        True -> client
        False -> existing
      }
    }),
  )
}

fn new_simulation() -> Simulation {
  Simulation(
    ids()
      |> list.map(fn(_id) {
        Client(kernel.from_document(initial_document()), 0, [])
      }),
    [],
  )
}

/// Every generated delta uses only document start/end or total-length spans.
/// Thus deletes and formatting never split a supplementary UTF-16 character.
fn gen_delta(
  document: rich_text.Document,
  random: Random,
) -> #(rich_text.Delta, Random) {
  let #(choice, random) = json_ot_gen.random_int(random, 5)
  let length = rich_text.document_length(document)
  let empty = rich_text.empty_delta()
  case choice {
    // Front insertion. The seeded document carries a supplementary code
    // point; generated edits avoid an upstream compose split of an inserted
    // surrogate pair against a leading embed.
    0 -> {
      let assert Ok(delta) =
        rich_text.delta_insert_text(empty, "x", rich_text.attributes([]))
      #(delta, random)
    }
    // End insertion is always a scalar boundary.
    1 if length > 0 -> {
      let assert Ok(prefix) =
        rich_text.delta_retain(empty, length, rich_text.attributes([]))
      let assert Ok(delta) =
        rich_text.delta_insert_text(prefix, "y", rich_text.attributes([]))
      #(delta, random)
    }
    // Formatting covers an entire valid document span.
    2 if length > 0 -> {
      let assert Ok(delta) =
        rich_text.delta_retain(
          empty,
          length,
          rich_text.attributes([#("bold", VBool(True))]),
        )
      #(delta, random)
    }
    // Deletes also cover the full document, preserving UTF-16 boundaries.
    3 if length > 0 -> {
      let assert Ok(delta) = rich_text.delta_delete(empty, length)
      #(delta, random)
    }
    // Embedded inserts exercise unit-length non-text content.
    _ -> {
      let assert Ok(delta) =
        rich_text.delta_insert_embed(
          empty,
          VObject([#("image", VString("generated"))]),
          rich_text.attributes([]),
        )
      #(delta, random)
    }
  }
}

fn minimum_sequence_number(simulation: Simulation) -> Int {
  let min_delivered =
    list.fold(simulation.clients, list.length(simulation.log), fn(acc, client) {
      int.min(acc, client.delivered)
    })
  let with_outbox =
    list.fold(simulation.clients, min_delivered, fn(acc, client) {
      list.fold(client.outbox, acc, fn(acc, wire) { int.min(acc, wire.ref_seq) })
    })
  list.fold(simulation.log, with_outbox, fn(acc, entry) {
    case entry.seq > min_delivered {
      True -> int.min(acc, entry.wire.ref_seq)
      False -> acc
    }
  })
}

fn submit(
  simulation: Simulation,
  id: Int,
  random: Random,
) -> #(Simulation, Random) {
  let client = get(simulation, id)
  let assert Ok(document) = kernel.view(client.state)
  let #(delta, random) = gen_delta(document, random)
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
  #(put(simulation, id, Client(..client, state: state, outbox: outbox)), random)
}

fn sequence(simulation: Simulation, id: Int) -> Simulation {
  let client = get(simulation, id)
  case client.outbox {
    [] -> simulation
    [wire, ..rest] ->
      put(
        Simulation(
          ..simulation,
          log: list.append(simulation.log, [
            Entry(list.length(simulation.log) + 1, id, wire),
          ]),
        ),
        id,
        Client(..client, outbox: rest),
      )
  }
}

fn deliver_one(simulation: Simulation, id: Int) -> Simulation {
  let client = get(simulation, id)
  case list.drop(simulation.log, client.delivered) {
    [] -> simulation
    [entry, ..] -> {
      let min = minimum_sequence_number(simulation)
      case entry.author == id {
        True -> {
          let assert Ok(#(state, _)) =
            kernel.ack_local(client.state, entry.wire, entry.seq, min)
          let #(state, released) = kernel.take_outbound(state)
          let outbox = case released {
            None -> client.outbox
            Some(wire) -> list.append(client.outbox, [wire])
          }
          put(simulation, id, Client(state, client.delivered + 1, outbox))
        }
        False -> {
          let assert Ok(#(state, _)) =
            kernel.apply_remote(client.state, entry.wire, entry.seq, min)
          put(
            simulation,
            id,
            Client(..client, state: state, delivered: client.delivered + 1),
          )
        }
      }
    }
  }
}

fn deliver_until(simulation: Simulation, id: Int, target: Int) -> Simulation {
  case get(simulation, id).delivered >= target {
    True -> simulation
    False -> deliver_until(deliver_one(simulation, id), id, target)
  }
}

fn deliver_all(simulation: Simulation) -> Simulation {
  list.fold(ids(), simulation, fn(simulation, id) {
    deliver_until(simulation, id, list.length(simulation.log))
  })
}

fn sequence_all(simulation: Simulation) -> Simulation {
  case list.all(simulation.clients, fn(client) { client.outbox == [] }) {
    True -> simulation
    False -> sequence_all(list.fold(ids(), simulation, sequence))
  }
}

fn drain(simulation: Simulation) -> Simulation {
  let simulation = deliver_all(sequence_all(simulation))
  case
    list.all(simulation.clients, fn(client) {
      client.outbox == [] && client.delivered == list.length(simulation.log)
    })
  {
    True -> simulation
    False -> drain(simulation)
  }
}

fn play(
  simulation: Simulation,
  random: Random,
  rounds: Int,
) -> #(Simulation, Random) {
  case rounds <= 0 {
    True -> #(simulation, random)
    False -> {
      let #(action, random) = json_ot_gen.random_int(random, 10)
      let #(id, random) = json_ot_gen.random_int(random, client_count)
      let #(simulation, random) = case action {
        n if n < 5 -> submit(simulation, id, random)
        n if n < 7 -> #(sequence(simulation, id), random)
        n if n < 9 -> #(deliver_one(simulation, id), random)
        _ -> #(deliver_one(sequence(simulation, id), id), random)
      }
      play(simulation, random, rounds - 1)
    }
  }
}

fn run(seed: Int) -> Result(Nil, String) {
  let #(simulation, _) =
    play(new_simulation(), json_ot_gen.new_random(seed), 40)
  let simulation = drain(simulation)
  let documents =
    list.map(simulation.clients, fn(client) { client.state.sequenced })
  let pending =
    list.any(simulation.clients, fn(client) {
      client.state.pending != ot_client.Idle
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
              list.map(simulation.clients, fn(client) {
                #(
                  rich_text.document_to_json(client.state.sequenced),
                  client.state.pending,
                )
              }),
            )
            <> "\nlog:\n"
            <> string.inspect(simulation.log),
          )
      }
    }
  }
}

pub fn clients_converge_with_text_formatting_deletes_emoji_and_embeds_test() -> Nil {
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
