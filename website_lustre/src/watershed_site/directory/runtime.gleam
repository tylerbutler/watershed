import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import lustre/effect.{type Effect}
import watershed
import watershed/sluice_js
import watershed_lustre

pub type Replica {
  ClientA
  ClientB
  ClientC
}

pub type Phase {
  Static
  Starting
  Ready
  Delivering
  Failed
}

pub type Entry {
  Entry(key: String, value: String)
}

pub type Node {
  Node(path: String, name: String, entries: List(Entry), children: List(Node))
}

pub type Tree {
  Tree(replica: Replica, root: Node)
}

pub type Pending {
  Pending(sequence_number: Int, replica: Replica, marker: String, label: String)
}

pub type Flow {
  Flow(id: Int, from: String, to: String, label: String)
}

pub type LogEntry {
  LogEntry(sequence_number: Int, author: Replica, label: String)
}

pub type Model {
  Model(
    phase: Phase,
    rig: Option(Rig),
    trees: List(Tree),
    pending: List(Pending),
    flows: List(Flow),
    log: List(LogEntry),
    generation: Int,
    pace_quarters: Int,
    jitter: Bool,
    delivery_active: Bool,
    converged: Bool,
    latest_sequence: Int,
    error: Option(String),
    folder_cursors: List(Int),
    reading_cursors: List(Int),
    in_flight: Int,
  )
}

pub type Msg {
  Start
  Started(Int, Result(Rig, DemoError))
  AddFolder(Replica, String)
  AddReading(Replica, String)
  DeleteFolder(Replica, String, String)
  Race
  Seed
  MutationSubmitted(Int, Result(Mutation, DemoError))
  Deliver(Int)
  Delivered(Int, Result(Delivery, DemoError))
  Land(Int, Delivery, Replica)
  ClearFlow(Int, Int)
  SetPace(String)
  SetJitter(Bool)
  Reset
  ResetDone(Int, Result(Rig, DemoError))
  BrowserFailed(String)
}

pub opaque type Rig {
  Rig(sluice: sluice_js.Sluice, clients: List(Client))
}

type Client {
  Client(
    replica: Replica,
    client_id: String,
    document: watershed.Document(Nil),
    directory: watershed.SharedDirectory,
  )
}

pub type Mutation {
  Mutation(trees: List(Tree), pending: List(Pending), flows: List(Flow))
}

pub type Delivery {
  Delivery(trees: List(Tree), sequence_number: Int, author: Replica, more: Bool)
}

pub type DemoError {
  CannotCreate(String)
  CannotResolve(Replica, String)
  MissingClientId(Replica)
  MissingReplica(Replica)
  InvalidValue(Replica, String, String)
  UnexpectedDelivery(String)
}

pub fn static_model() -> Model {
  Model(
    Static,
    None,
    [],
    [],
    [],
    [],
    0,
    4,
    False,
    False,
    True,
    0,
    None,
    [0, 1, 2],
    [0, 1, 2],
    0,
  )
}

pub fn init() -> #(Model, Effect(Msg)) {
  update(static_model(), Start)
}

pub fn update(model: Model, message: Msg) -> #(Model, Effect(Msg)) {
  case message {
    Started(generation, _)
      | ResetDone(generation, _)
      | MutationSubmitted(generation, _)
      | Deliver(generation)
      | Delivered(generation, _)
      | Land(generation, _, _)
      | ClearFlow(generation, _)
      if generation != model.generation
    -> #(model, effect.none())
    Start if model.phase == Static -> begin(model, False)
    Start -> #(model, effect.none())
    Reset ->
      begin(
        Model(
          ..static_model(),
          generation: model.generation + 1,
          pace_quarters: model.pace_quarters,
          jitter: model.jitter,
        ),
        True,
      )
    Started(_, outcome) | ResetDone(_, outcome) ->
      case outcome {
        Error(reason) -> failed(model, reason)
        Ok(rig) ->
          case project_all(rig) {
            Error(reason) -> failed(model, reason)
            Ok(trees) -> #(
              Model(
                ..model,
                phase: Ready,
                rig: Some(rig),
                trees:,
                converged: True,
                error: None,
              ),
              effect.none(),
            )
          }
      }
    AddFolder(replica, path) -> {
      let #(name, cursor) = next_folder(model, replica, path)
      submit(
        Model(
          ..model,
          folder_cursors: set_cursor(model.folder_cursors, replica, cursor),
        ),
        fn(rig) { create_folder(rig, replica, path, name) },
      )
    }
    AddReading(replica, path) -> {
      let #(key, value, cursor) = next_reading(model, replica)
      submit(
        Model(
          ..model,
          reading_cursors: set_cursor(model.reading_cursors, replica, cursor),
        ),
        fn(rig) { set_reading(rig, replica, path, key, value) },
      )
    }
    DeleteFolder(replica, path, name) ->
      submit(model, fn(rig) { delete_folder(rig, replica, path, name) })
    Race -> submit(model, race_folder)
    Seed ->
      submit(
        Model(
          ..model,
          folder_cursors: advance_cursor(model.folder_cursors, ClientA, 2),
          reading_cursors: advance_cursor(model.reading_cursors, ClientA, 2),
        ),
        seed_tree,
      )
    MutationSubmitted(_, outcome) ->
      case outcome {
        Error(reason) -> failed(model, reason)
        Ok(mutation) -> {
          let schedule = case model.delivery_active {
            True -> effect.none()
            False ->
              watershed_lustre.after(delay(model), Deliver(model.generation))
          }
          #(
            Model(
              ..model,
              phase: Delivering,
              trees: mutation.trees,
              pending: list.append(model.pending, mutation.pending),
              flows: list.append(model.flows, mutation.flows),
              delivery_active: True,
              converged: False,
            ),
            effect.batch([schedule, clear_flows(model, mutation.flows)]),
          )
        }
      }
    Deliver(_) if model.phase != Delivering -> #(model, effect.none())
    Deliver(_) ->
      case model.rig {
        Some(rig) -> #(
          model,
          watershed_lustre.perform(
            operation: fn() { deliver_group(rig) },
            outcome: fn(value) { Delivered(model.generation, value) },
          ),
        )
        None -> #(model, effect.none())
      }
    Delivered(_, outcome) ->
      case outcome {
        Error(reason) -> failed(model, reason)
        Ok(delivery) -> {
          let marker =
            model.pending
            |> list.find(fn(item) {
              item.sequence_number == delivery.sequence_number
            })
          let flows =
            replicas()
            |> list.index_map(fn(replica, index) {
              Flow(
                delivery.sequence_number * 4 + index,
                "seq",
                replica_id(replica),
                "SN " <> int.to_string(delivery.sequence_number),
              )
            })
          let landings =
            replicas()
            |> list.index_map(fn(replica, index) {
              watershed_lustre.after(
                return_delay(model, index),
                Land(model.generation, delivery, replica),
              )
            })
          let next = case delivery.more {
            True ->
              watershed_lustre.after(
                return_delay(model, 2) + 1,
                Deliver(model.generation),
              )
            False -> effect.none()
          }
          #(
            Model(
              ..model,
              phase: Delivering,
              flows: list.append(model.flows, flows),
              log: [
                LogEntry(
                  delivery.sequence_number,
                  delivery.author,
                  case marker {
                    Ok(item) -> item.label
                    Error(Nil) ->
                      "SN " <> int.to_string(delivery.sequence_number)
                  },
                ),
                ..model.log
              ],
              delivery_active: delivery.more,
              converged: False,
              latest_sequence: delivery.sequence_number,
              in_flight: model.in_flight + 3,
            ),
            effect.batch([
              next,
              effect.batch(landings),
              clear_flows(model, flows),
            ]),
          )
        }
      }
    Land(_, delivery, replica) -> {
      let trees = land_tree(model.trees, delivery.trees, replica)
      let pending = case replica == delivery.author {
        True ->
          list.filter(model.pending, fn(item) {
            item.sequence_number != delivery.sequence_number
          })
        False -> model.pending
      }
      let in_flight = int.max(0, model.in_flight - 1)
      let converged =
        !model.delivery_active
        && in_flight == 0
        && trees_equal(trees)
        && list.is_empty(pending)
      #(
        Model(
          ..model,
          phase: case converged {
            True -> Ready
            False -> Delivering
          },
          trees:,
          pending:,
          in_flight:,
          converged:,
        ),
        effect.none(),
      )
    }
    ClearFlow(_, id) -> #(
      Model(
        ..model,
        flows: list.filter(model.flows, fn(flow) { flow.id != id }),
      ),
      effect.none(),
    )
    SetPace(value) -> #(
      Model(..model, pace_quarters: pace(value, model.pace_quarters)),
      effect.none(),
    )
    SetJitter(value) -> #(Model(..model, jitter: value), effect.none())
    BrowserFailed(reason) -> failed(model, UnexpectedDelivery(reason))
  }
}

fn submit(
  model: Model,
  operation: fn(Rig) -> Result(Mutation, DemoError),
) -> #(Model, Effect(Msg)) {
  case model.rig, model.phase {
    Some(rig), Ready | Some(rig), Delivering -> #(
      Model(..model, phase: Delivering, converged: False),
      watershed_lustre.perform(
        operation: fn() { operation(rig) },
        outcome: fn(value) { MutationSubmitted(model.generation, value) },
      ),
    )
    _, _ -> #(model, effect.none())
  }
}

fn begin(model: Model, reset: Bool) -> #(Model, Effect(Msg)) {
  #(
    Model(..model, phase: Starting, converged: False),
    watershed_lustre.perform(operation: start_rig, outcome: fn(value) {
      case reset {
        True -> ResetDone(model.generation, value)
        False -> Started(model.generation, value)
      }
    }),
  )
}

fn failed(model: Model, reason: DemoError) -> #(Model, Effect(Msg)) {
  #(
    Model(
      ..model,
      phase: Failed,
      error: Some(describe_error(reason)),
      delivery_active: False,
      converged: False,
    ),
    effect.none(),
  )
}

fn delay(model: Model) -> Int {
  case model.jitter {
    True -> 3200 / model.pace_quarters
    False -> 2800 / model.pace_quarters
  }
}

fn return_delay(model: Model, index: Int) -> Int {
  case model.jitter {
    True -> { 2400 + index * 400 } / model.pace_quarters
    False -> 2800 / model.pace_quarters
  }
}

fn clear_flows(model: Model, flows: List(Flow)) -> Effect(Msg) {
  flows
  |> list.map(fn(flow) {
    watershed_lustre.after(delay(model), ClearFlow(model.generation, flow.id))
  })
  |> effect.batch
}

fn pace(value: String, fallback: Int) -> Int {
  case value {
    "0.25" -> 1
    "0.5" -> 2
    "0.75" -> 3
    "1" -> 4
    "1.25" -> 5
    "1.5" -> 6
    "1.75" -> 7
    "2" -> 8
    _ -> fallback
  }
}

pub fn start_rig() -> Result(Rig, DemoError) {
  let sluice =
    sluice_js.start(tenant: "directory-demo", document: "directory-demo")
  let documents =
    replicas()
    |> list.map(fn(replica) {
      #(replica, sluice_js.connect(sluice, "user-" <> replica_id(replica)))
    })
  sluice_js.settle(sluice)
  let assert [#(ClientA, alpha), ..] = documents
  use directory <- result.try(
    watershed.create_directory(alpha) |> result.map_error(CannotCreate),
  )
  watershed.set(
    watershed.root(alpha),
    "tree",
    watershed.directory_handle_of(directory),
  )
  sluice_js.settle(sluice)
  use clients <- result.try(
    list.try_map(documents, fn(item) {
      use client_id <- result.try(
        sluice_js.client_id(sluice, item.1)
        |> result.replace_error(MissingClientId(item.0)),
      )
      use resolved <- result.try(case item.0 {
        ClientA -> Ok(directory)
        _ -> {
          use stored <- result.try(
            watershed.get(watershed.root(item.1), "tree")
            |> result.replace_error(CannotResolve(
              item.0,
              "The directory handle is missing.",
            )),
          )
          watershed.resolve_directory(item.1, stored)
          |> result.map_error(CannotResolve(item.0, _))
        }
      })
      Ok(Client(item.0, client_id, item.1, resolved))
    }),
  )
  Ok(Rig(sluice, clients))
}

pub fn create_folder(
  rig: Rig,
  replica: Replica,
  path: String,
  name: String,
) -> Result(Mutation, DemoError) {
  use client <- result.try(find_client(rig, replica))
  watershed.directory_create_subdirectory(client.directory, path, name)
  operation(
    rig,
    replica,
    "sub:" <> join(path, name),
    "mkdir " <> join(path, name),
  )
}

pub fn set_reading(
  rig: Rig,
  replica: Replica,
  path: String,
  key: String,
  value: String,
) -> Result(Mutation, DemoError) {
  use client <- result.try(find_client(rig, replica))
  watershed.directory_set(client.directory, path, key, json.string(value))
  operation(
    rig,
    replica,
    "key:" <> path <> "::" <> key,
    "set " <> path <> " · " <> key,
  )
}

pub fn delete_folder(
  rig: Rig,
  replica: Replica,
  path: String,
  name: String,
) -> Result(Mutation, DemoError) {
  use client <- result.try(find_client(rig, replica))
  watershed.directory_delete_subdirectory(client.directory, path, name)
  operation(
    rig,
    replica,
    "del:" <> join(path, name),
    "rmdir " <> join(path, name),
  )
}

pub fn race_folder(rig: Rig) -> Result(Mutation, DemoError) {
  use a <- result.try(write_folder(rig, ClientA, "/", "kettle-run"))
  use b <- result.try(write_folder(rig, ClientB, "/", "kettle-run"))
  use c <- result.try(write_folder(rig, ClientC, "/", "kettle-run"))
  mutation(rig, [a, b, c])
}

pub fn seed_tree(rig: Rig) -> Result(Mutation, DemoError) {
  use a <- result.try(write_folder(rig, ClientA, "/", "surveys"))
  use b <- result.try(write_reading(
    rig,
    ClientA,
    "/surveys",
    "BM-17",
    "recorded",
  ))
  use c <- result.try(write_folder(rig, ClientA, "/", "plans"))
  use d <- result.try(write_reading(rig, ClientA, "/plans", "grade", "2.1%"))
  mutation(rig, [a, b, c, d])
}

fn write_folder(
  rig: Rig,
  replica: Replica,
  path: String,
  name: String,
) -> Result(Pending, DemoError) {
  use client <- result.try(find_client(rig, replica))
  watershed.directory_create_subdirectory(client.directory, path, name)
  Ok(pending(
    rig,
    replica,
    "sub:" <> join(path, name),
    "mkdir " <> join(path, name),
  ))
}

fn write_reading(
  rig: Rig,
  replica: Replica,
  path: String,
  key: String,
  value: String,
) -> Result(Pending, DemoError) {
  use client <- result.try(find_client(rig, replica))
  watershed.directory_set(client.directory, path, key, json.string(value))
  Ok(pending(
    rig,
    replica,
    "key:" <> path <> "::" <> key,
    "set " <> path <> " · " <> key,
  ))
}

fn operation(
  rig: Rig,
  replica: Replica,
  marker: String,
  label: String,
) -> Result(Mutation, DemoError) {
  mutation(rig, [pending(rig, replica, marker, label)])
}

fn pending(
  rig: Rig,
  replica: Replica,
  marker: String,
  label: String,
) -> Pending {
  Pending(sluice_js.sequence_number(rig.sluice), replica, marker, label)
}

fn mutation(rig: Rig, pending: List(Pending)) -> Result(Mutation, DemoError) {
  use _ <- result.try(next_operation(rig))
  use trees <- result.try(project_all(rig))
  Ok(Mutation(
    trees,
    pending,
    list.map(pending, fn(item) {
      Flow(-item.sequence_number, replica_id(item.replica), "seq", item.label)
    }),
  ))
}

pub fn deliver_group(rig: Rig) -> Result(Delivery, DemoError) {
  use next <- result.try(next_operation(rig))
  use author <- result.try(replica_by_id(rig, next.author))
  use _ <- result.try(drain(rig, next.sequence_number))
  use trees <- result.try(project_all(rig))
  Ok(Delivery(
    trees,
    next.sequence_number,
    author,
    sluice_js.pending(rig.sluice),
  ))
}

fn next_operation(rig: Rig) -> Result(sluice_js.Delivery, DemoError) {
  use next <- result.try(
    sluice_js.peek_info(rig.sluice)
    |> result.replace_error(UnexpectedDelivery("No operation is queued.")),
  )
  case next.sequence_number > 0 && next.event == "op" {
    True -> Ok(next)
    False -> Error(UnexpectedDelivery(next.event))
  }
}

fn drain(rig: Rig, sequence: Int) -> Result(Nil, DemoError) {
  case sluice_js.peek_info(rig.sluice) {
    Ok(next) if next.sequence_number == sequence -> {
      use _ <- result.try(
        sluice_js.step_info(rig.sluice)
        |> result.replace_error(UnexpectedDelivery(
          "Cannot deliver the operation.",
        )),
      )
      drain(rig, sequence)
    }
    Ok(next) if next.sequence_number == 0 ->
      Error(UnexpectedDelivery(next.event))
    Ok(_) | Error(Nil) -> Ok(Nil)
  }
}

fn project_all(rig: Rig) -> Result(List(Tree), DemoError) {
  list.try_map(rig.clients, fn(client) {
    project_node(client, "/", "/") |> result.map(Tree(client.replica, _))
  })
}

fn project_node(
  client: Client,
  path: String,
  name: String,
) -> Result(Node, DemoError) {
  use entries <- result.try(
    watershed.directory_entries(client.directory, path)
    |> list.try_map(fn(entry) {
      json.parse(json.to_string(entry.1), decode.string)
      |> result.map(Entry(entry.0, _))
      |> result.map_error(fn(_) { InvalidValue(client.replica, path, entry.0) })
    }),
  )
  use children <- result.try(
    watershed.directory_subdirectories(client.directory, path)
    |> list.try_map(fn(child) { project_node(client, join(path, child), child) }),
  )
  Ok(Node(path, name, entries, children))
}

pub fn node(model: Model, replica: Replica, path: String) -> Option(Node) {
  model.trees
  |> list.find(fn(tree) { tree.replica == replica })
  |> result.map(fn(tree) { find_node(tree.root, path) })
  |> result.unwrap(None)
}

fn find_node(root: Node, path: String) -> Option(Node) {
  case root.path == path {
    True -> Some(root)
    False -> find_in_children(root.children, path)
  }
}

fn find_in_children(children: List(Node), path: String) -> Option(Node) {
  case children {
    [] -> None
    [child, ..rest] ->
      case find_node(child, path) {
        Some(node) -> Some(node)
        None -> find_in_children(rest, path)
      }
  }
}

fn trees_equal(trees: List(Tree)) -> Bool {
  case trees {
    [] -> True
    [first, ..rest] -> list.all(rest, fn(tree) { tree.root == first.root })
  }
}

fn find_client(rig: Rig, replica: Replica) -> Result(Client, DemoError) {
  rig.clients
  |> list.find(fn(client) { client.replica == replica })
  |> result.replace_error(MissingReplica(replica))
}

fn replica_by_id(rig: Rig, id: String) -> Result(Replica, DemoError) {
  rig.clients
  |> list.find(fn(client) { client.client_id == id })
  |> result.map(fn(client) { client.replica })
  |> result.replace_error(UnexpectedDelivery("Unknown replica: " <> id))
}

fn next_folder(model: Model, replica: Replica, path: String) -> #(String, Int) {
  let names = [
    "surveys", "plans", "logs", "spoil", "borrow-pit", "wash-fill", "intake",
    "weir", "kettle-run", "mill-race",
  ]
  let siblings =
    node(model, replica, path)
    |> option.map(fn(root) { list.map(root.children, fn(child) { child.name }) })
    |> option.unwrap([])
  choose_folder(
    names,
    siblings,
    get_cursor(model.folder_cursors, replica),
    list.length(names),
  )
}

fn choose_folder(
  names: List(String),
  siblings: List(String),
  cursor: Int,
  remaining: Int,
) -> #(String, Int) {
  let name =
    names
    |> list.drop(cursor % list.length(names))
    |> list.first
    |> result.unwrap("surveys")
  let next = cursor + 3
  case remaining > 0 && list.contains(siblings, name) {
    True -> choose_folder(names, siblings, next, remaining - 1)
    False -> #(name, next)
  }
}

fn next_reading(model: Model, replica: Replica) -> #(String, String, Int) {
  let readings = [
    #("BM-17", "recorded"),
    #("grade", "2.1%"),
    #("silt", "high"),
    #("stage", "24"),
    #("flow", "61"),
    #("BM-22", "recorded"),
    #("datum", "set"),
  ]
  let cursor = get_cursor(model.reading_cursors, replica)
  let #(key, value) =
    readings
    |> list.drop(cursor % list.length(readings))
    |> list.first
    |> result.unwrap(#("BM-17", "recorded"))
  #(key, value, cursor + 1)
}

fn get_cursor(cursors: List(Int), replica: Replica) -> Int {
  cursors
  |> list.drop(replica_index(replica))
  |> list.first
  |> result.unwrap(replica_index(replica))
}

fn set_cursor(cursors: List(Int), replica: Replica, value: Int) -> List(Int) {
  list.index_map(cursors, fn(cursor, index) {
    case index == replica_index(replica) {
      True -> value
      False -> cursor
    }
  })
}

fn advance_cursor(
  cursors: List(Int),
  replica: Replica,
  amount: Int,
) -> List(Int) {
  set_cursor(cursors, replica, get_cursor(cursors, replica) + amount)
}

fn replica_index(replica: Replica) -> Int {
  case replica {
    ClientA -> 0
    ClientB -> 1
    ClientC -> 2
  }
}

fn land_tree(
  current: List(Tree),
  delivered: List(Tree),
  replica: Replica,
) -> List(Tree) {
  let replacement =
    delivered
    |> list.find(fn(tree) { tree.replica == replica })
    |> option.from_result
  list.map(current, fn(tree) {
    case tree.replica == replica, replacement {
      True, Some(value) -> value
      _, _ -> tree
    }
  })
}

fn join(path: String, name: String) -> String {
  case path {
    "/" -> "/" <> name
    _ -> path <> "/" <> name
  }
}

pub fn replicas() -> List(Replica) {
  [ClientA, ClientB, ClientC]
}

pub fn replica_id(replica: Replica) -> String {
  case replica {
    ClientA -> "a"
    ClientB -> "b"
    ClientC -> "c"
  }
}

pub fn replica_label(replica: Replica) -> String {
  case replica {
    ClientA -> "Client A"
    ClientB -> "Client B"
    ClientC -> "Client C"
  }
}

pub fn describe_error(error: DemoError) -> String {
  case error {
    CannotCreate(reason) -> "Cannot create the directory: " <> reason
    CannotResolve(replica, reason) ->
      replica_label(replica) <> ": Cannot resolve the directory: " <> reason
    MissingClientId(replica) -> replica_label(replica) <> ": Missing client ID."
    MissingReplica(replica) -> replica_label(replica) <> ": Missing replica."
    InvalidValue(replica, path, key) ->
      replica_label(replica)
      <> ": Invalid value at "
      <> path
      <> " · "
      <> key
      <> "."
    UnexpectedDelivery(reason) -> "Unexpected delivery: " <> reason
  }
}
