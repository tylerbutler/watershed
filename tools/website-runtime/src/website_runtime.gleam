//// Internal runtime boundary for the watershed website.

import gleam/dict.{type Dict}
import gleam/list
import gleam/result
import watershed.{type Document}
import watershed/sluice_js

pub type Root

pub opaque type Client {
  Client(document: Document(Root))
}

pub opaque type Runtime {
  Runtime(sluice: sluice_js.Sluice, clients: Dict(String, Client))
}

pub type Delivery =
  sluice_js.Delivery

pub fn start(
  tenant: String,
  document: String,
  client_ids: List(String),
) -> Result(Runtime, String) {
  let sluice = sluice_js.start(tenant: tenant, document: document)
  let clients =
    list.fold(client_ids, dict.new(), fn(clients, id) {
      dict.insert(clients, id, Client(sluice_js.connect(sluice, id)))
    })
  Ok(Runtime(sluice:, clients:))
}

pub fn client(runtime: Runtime, id: String) -> Result(Client, String) {
  case dict.get(runtime.clients, id) {
    Ok(client) -> Ok(client)
    Error(Nil) -> Error("unknown client: " <> id)
  }
}

pub fn settle(runtime: Runtime) -> Nil {
  sluice_js.settle(runtime.sluice)
}

pub fn peek(runtime: Runtime) -> Result(Delivery, Nil) {
  sluice_js.peek_info(runtime.sluice)
}

pub fn step(runtime: Runtime) -> Result(Delivery, Nil) {
  sluice_js.step_info(runtime.sluice)
}

pub fn pending(runtime: Runtime) -> Bool {
  sluice_js.pending(runtime.sluice)
}

pub fn sequence_number(runtime: Runtime) -> Int {
  sluice_js.sequence_number(runtime.sluice)
}

pub fn pause(runtime: Runtime, id: String) -> Result(Nil, String) {
  use Client(document) <- result.try(client(runtime, id))
  sluice_js.pause(runtime.sluice, document)
  Ok(Nil)
}

pub fn resume(runtime: Runtime, id: String) -> Result(Nil, String) {
  use Client(document) <- result.try(client(runtime, id))
  sluice_js.resume(runtime.sluice, document)
  Ok(Nil)
}

pub fn document(client: Client) -> Document(Root) {
  client.document
}
