//// A deterministic in-memory mesh for the pure CRDT core.
////
//// Test scaffolding, not transport: there is no socket, no timer, and no
//// concurrency here. Peers hold `crdt_core.Document` values, links are an
//// explicit set of undirected edges, and messages sit in one FIFO queue of
//// encoded envelopes. Every peer-to-peer hop goes through
//// `crdt_wire.envelope_to_string`/`crdt_core.receive_encoded`, so the
//// simulator exercises the real wire codec rather than passing typed
//// values around.
////
//// Delivery order is explicit. `settle` drains the queue head-first;
//// `take_queue`/`enqueue` let a test reverse, duplicate, or interleave
//// packets before they land.

import gleam/list
import gleam/order
import gleam/string

import watershed/channel.{type ChannelInit, type P2pEdit}
import watershed/crdt_core.{type Document, type Outcome}
import watershed/crdt_wire
import watershed/p2p.{type P2pError}

pub type Packet {
  Packet(to: String, from: String, kind: String, raw: String)
}

pub opaque type Mesh {
  Mesh(
    peers: List(#(String, Document)),
    links: List(#(String, String)),
    queue: List(Packet),
  )
}

pub fn new() -> Mesh {
  Mesh(peers: [], links: [], queue: [])
}

pub fn add(mesh: Mesh, name: String, document: Document) -> Mesh {
  Mesh(..mesh, peers: list.key_set(mesh.peers, name, document))
}

pub fn names(mesh: Mesh) -> List(String) {
  list.map(mesh.peers, fn(peer) { peer.0 }) |> list.sort(string.compare)
}

pub fn document(mesh: Mesh, name: String) -> Document {
  let assert Ok(document) = list.key_find(mesh.peers, name)
  document
}

pub fn put(mesh: Mesh, name: String, document: Document) -> Mesh {
  Mesh(..mesh, peers: list.key_set(mesh.peers, name, document))
}

pub fn connect(mesh: Mesh, left: String, right: String) -> Mesh {
  let edge = normalize(left, right)
  case list.contains(mesh.links, edge) {
    True -> mesh
    False -> Mesh(..mesh, links: [edge, ..mesh.links])
  }
}

pub fn disconnect(mesh: Mesh, left: String, right: String) -> Mesh {
  let edge = normalize(left, right)
  Mesh(..mesh, links: list.filter(mesh.links, fn(link) { link != edge }))
}

pub fn peers_of(mesh: Mesh, name: String) -> List(String) {
  list.filter_map(mesh.links, fn(link) {
    case link {
      #(left, right) if left == name -> Ok(right)
      #(left, right) if right == name -> Ok(left)
      _ -> Error(Nil)
    }
  })
  |> list.sort(string.compare)
}

pub fn queue(mesh: Mesh) -> List(Packet) {
  mesh.queue
}

pub fn take_queue(mesh: Mesh) -> #(Mesh, List(Packet)) {
  #(Mesh(..mesh, queue: []), mesh.queue)
}

pub fn enqueue(mesh: Mesh, packets: List(Packet)) -> Mesh {
  Mesh(..mesh, queue: list.append(mesh.queue, packets))
}

pub fn of_kind(packets: List(Packet), kind: String) -> List(Packet) {
  list.filter(packets, fn(packet) { packet.kind == kind })
}

// --- transitions ----------------------------------------------------------

/// Run a local transition on one peer, storing the result and queueing
/// whatever it asked to broadcast to that peer's current links.
pub fn transition(
  mesh: Mesh,
  name: String,
  run: fn(Document) -> Result(#(Document, Outcome), P2pError),
) -> #(Mesh, Outcome) {
  let assert Ok(#(document, outcome)) = run(document(mesh, name))
  let mesh =
    put(mesh, name, document)
    |> broadcast(name, outcome.broadcast)
  #(mesh, outcome)
}

/// Create a channel on one peer and return its address.
pub fn create(mesh: Mesh, name: String, init: ChannelInit) -> #(Mesh, String) {
  let #(mesh, outcome) =
    transition(mesh, name, fn(document) {
      crdt_core.create_channel(document, init)
    })
  let assert [descriptor] = outcome.created
  #(mesh, descriptor.address)
}

pub fn edit(mesh: Mesh, name: String, address: String, edit: P2pEdit) -> Mesh {
  let #(mesh, _) =
    transition(mesh, name, fn(document) {
      crdt_core.edit(document, address, edit)
    })
  mesh
}

/// Queue one message from a peer to every peer it is currently linked to.
pub fn broadcast(
  mesh: Mesh,
  from: String,
  messages: List(crdt_wire.Message),
) -> Mesh {
  list.fold(peers_of(mesh, from), mesh, fn(mesh, to) {
    send(mesh, from, to, messages)
  })
}

/// Queue one message from a peer to one specific peer, whether or not they
/// are linked — a test may model a message that was already in flight when
/// the link dropped.
pub fn send(
  mesh: Mesh,
  from: String,
  to: String,
  messages: List(crdt_wire.Message),
) -> Mesh {
  let document = document(mesh, from)
  let packets =
    list.map(messages, fn(message) {
      Packet(
        to: to,
        from: from,
        kind: crdt_wire.message_type(message),
        raw: crdt_core.encode(document, message),
      )
    })
  enqueue(mesh, packets)
}

/// Every peer offers its whole state to its links. Two rounds fan a merge
/// across a chain: the middle peer merges first, then passes the join on.
pub fn gossip_state(mesh: Mesh) -> Mesh {
  list.fold(names(mesh), mesh, fn(mesh, name) {
    broadcast(mesh, name, [crdt_core.state_message(document(mesh, name))])
  })
  |> settle
}

/// Drain the queue head-first until quiescent. Replies go back to the
/// sender; nothing else is re-broadcast, because the core never asks a
/// received message to be forwarded.
pub fn settle(mesh: Mesh) -> Mesh {
  do_settle(mesh, 10_000)
}

fn do_settle(mesh: Mesh, fuel: Int) -> Mesh {
  case mesh.queue {
    [] -> mesh
    [packet, ..rest] -> {
      case fuel <= 0 {
        True -> panic as "crdt_sim: mesh never reached quiescence"
        False -> Nil
      }
      Mesh(..mesh, queue: rest)
      |> deliver(packet)
      |> do_settle(fuel - 1)
    }
  }
}

fn deliver(mesh: Mesh, packet: Packet) -> Mesh {
  let assert Ok(#(document, outcome)) =
    crdt_core.receive_encoded(document(mesh, packet.to), packet.raw)
  put(mesh, packet.to, document)
  |> send(packet.to, packet.from, outcome.reply)
  |> broadcast(packet.to, outcome.broadcast)
}

fn normalize(left: String, right: String) -> #(String, String) {
  case string.compare(left, right) {
    order.Lt -> #(left, right)
    order.Eq | order.Gt -> #(right, left)
  }
}
