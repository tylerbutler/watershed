//// Pure port of FluidFramework's `packages/dds/map/src/directory.ts`
//// (`SharedDirectory` + `SubDirectory`).
////
//// SharedDirectory is "SharedMap, but recursive": each directory node has a
//// SharedMap-like key/value store (see `map_kernel`) plus a named set of
//// child directories. This kernel is a pure *tree* port — no process, no
//// side effects: every operation returns the new state plus the events and
//// (for local ops) the outbound op it produced.
////
//// The new complexity over `map_kernel` is **hierarchical identity**: a
//// subdirectory can be concurrently created by multiple clients, deleted,
//// and recreated under the same absolute path. Ops address a directory by
//// absolute path but must only apply to the *current live instance* of that
//// path. That filtering (`is_message_for_current_instance`, D12 in the plan)
//// is the core correctness rule and is modelled explicitly from creator ids,
//// create sequence data, and the op's reference sequence number.
////
//// State per node mirrors `map_kernel`: `sequenced` storage (server-confirmed,
//// plus `insertion_order` because Gleam's `Dict` is unordered) and `pending`
//// optimistic local edits. Pending entries additionally carry `message_id`s so
//// rollback (LIFO) and resubmit (filter still-relevant) can target a specific
//// submission.

import gleam/dict.{type Dict}
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order.{type Order}
import gleam/result
import gleam/string

// ─────────────────────────────────────────────────────────────────────────────
// Types
// ─────────────────────────────────────────────────────────────────────────────

pub type DirectoryState {
  DirectoryState(root: DirectoryNode, next_message_id: Int)
}

pub type DirectoryNode {
  DirectoryNode(
    path: String,
    create: CreateInfo,
    /// Client ids that created this live instance (upstream `clientIds`).
    creators: List(Int),
    /// Whether this instance was created while detached (upstream
    /// `clientIds.has("detached")`).
    detached_created: Bool,
    disposed: Bool,
    storage: StorageState,
    /// Server-confirmed child directories.
    subdirs: Dict(String, DirectoryNode),
    /// Insertion order of `subdirs` (Gleam dicts are unordered).
    subdir_order: List(String),
    pending_subdirs: List(PendingSubdir),
  )
}

/// Sequence data used both to identify a directory instance and to order
/// sibling directories. `seq` is the server sequence number of the create
/// (`-1` while a local create is unacked, `0` when created detached).
pub type CreateInfo {
  CreateInfo(seq: Int, client_seq: Int)
}

pub type StorageState {
  StorageState(
    sequenced: Dict(String, Json),
    insertion_order: List(String),
    pending: List(PendingStorage),
  )
}

pub type PendingStorage {
  /// One or more consecutive local sets to a key, oldest first, each tagged
  /// with the submission `message_id`. A delete or clear terminates the
  /// lifetime; a later set starts a new one.
  PendingLifetime(key: String, sets: List(Json), message_ids: List(Int))
  PendingDelete(key: String, message_id: Int)
  PendingClear(message_id: Int)
}

pub type PendingSubdir {
  /// A local create of `name`; `node` is the optimistic child instance that
  /// accumulates pending storage/children until the create is acked.
  PendingCreate(name: String, node: DirectoryNode, message_id: Int)
  /// A local delete of `name`; `deleted_node` is retained so a rollback can
  /// re-expose the prior tree (D13).
  PendingRemove(name: String, deleted_node: DirectoryNode, message_id: Int)
}

pub type DirectoryOp {
  Set(path: String, key: String, value: Json)
  Delete(path: String, key: String)
  Clear(path: String)
  CreateSubDirectory(path: String, name: String)
  DeleteSubDirectory(path: String, name: String)
}

pub type DirectoryEvent {
  ValueChanged(path: String, key: String, previous_value: Option(Json), local: Bool)
  Cleared(path: String, local: Bool)
  SubDirectoryCreated(path: String, local: Bool)
  SubDirectoryDeleted(path: String, local: Bool)
  Disposed(path: String)
  Undisposed(path: String)
}

/// Metadata carried by a sequenced op: who authored it, its server sequence
/// number, the author's reference sequence number (what they had seen when
/// they submitted — drives the stale-instance filter), and its client
/// sequence number (tie-breaker for sibling ordering).
pub type SequencedMeta {
  SequencedMeta(
    author: Int,
    sequence_number: Int,
    reference_sequence_number: Int,
    client_sequence_number: Int,
  )
}

pub type KernelError {
  UnexpectedAck(op: DirectoryOp, detail: String)
  UnexpectedRollback(op: DirectoryOp, detail: String)
  PathNotFound(path: String)
  InvalidName(name: String)
  InvariantViolation(detail: String)
}

// ─────────────────────────────────────────────────────────────────────────────
// Construction
// ─────────────────────────────────────────────────────────────────────────────

pub fn new() -> DirectoryState {
  DirectoryState(root: new_node("/", CreateInfo(0, 0), [], True), next_message_id: 0)
}

fn new_node(
  path: String,
  create: CreateInfo,
  creators: List(Int),
  detached_created: Bool,
) -> DirectoryNode {
  DirectoryNode(
    path: path,
    create: create,
    creators: creators,
    detached_created: detached_created,
    disposed: False,
    storage: StorageState(sequenced: dict.new(), insertion_order: [], pending: []),
    subdirs: dict.new(),
    subdir_order: [],
    pending_subdirs: [],
  )
}

// ─────────────────────────────────────────────────────────────────────────────
// Path helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Split an absolute path into its non-empty segments. `"/"` → `[]`.
pub fn segments(path: String) -> List(String) {
  string.split(path, "/") |> list.filter(fn(s) { s != "" })
}

fn join(path: String, name: String) -> String {
  case path {
    "/" -> "/" <> name
    _ -> path <> "/" <> name
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Optimistic vs sequenced child lookup
// ─────────────────────────────────────────────────────────────────────────────

/// The latest pending subdir entry for `name`, if any.
fn latest_pending_subdir(node: DirectoryNode, name: String) -> Option(PendingSubdir) {
  list.reverse(node.pending_subdirs)
  |> list.find(fn(entry) { pending_subdir_name(entry) == name })
  |> option.from_result
}

fn pending_subdir_name(entry: PendingSubdir) -> String {
  case entry {
    PendingCreate(name, _, _) -> name
    PendingRemove(name, _, _) -> name
  }
}

/// Optimistic child by name: overlays pending creates/deletes on sequenced
/// children. Disposed nodes are treated as absent unless `include_disposed`.
fn optimistic_child(
  node: DirectoryNode,
  name: String,
  include_disposed: Bool,
) -> Option(DirectoryNode) {
  let child = case latest_pending_subdir(node, name) {
    None -> dict.get(node.subdirs, name) |> option.from_result
    Some(PendingCreate(_, child, _)) -> Some(child)
    Some(PendingRemove(_, _, _)) -> None
  }
  case child {
    Some(c) if c.disposed && !include_disposed -> None
    other -> other
  }
}

fn sequenced_child(node: DirectoryNode, name: String) -> Option(DirectoryNode) {
  dict.get(node.subdirs, name) |> option.from_result
}

/// Write `child` back to wherever `name` currently lives: into the latest
/// pending create entry if one exists, else into sequenced children.
fn put_optimistic_child(
  node: DirectoryNode,
  name: String,
  child: DirectoryNode,
) -> DirectoryNode {
  case latest_pending_subdir(node, name) {
    Some(PendingCreate(_, _, _)) ->
      DirectoryNode(
        ..node,
        pending_subdirs: replace_latest_pending_create(node.pending_subdirs, name, child),
      )
    _ -> put_sequenced_child(node, name, child)
  }
}

fn replace_latest_pending_create(
  pending: List(PendingSubdir),
  name: String,
  child: DirectoryNode,
) -> List(PendingSubdir) {
  list.reverse(pending)
  |> do_replace_first_create(name, child)
  |> list.reverse
}

fn do_replace_first_create(
  reversed: List(PendingSubdir),
  name: String,
  child: DirectoryNode,
) -> List(PendingSubdir) {
  case reversed {
    [] -> []
    [PendingCreate(n, _, mid), ..rest] if n == name -> [
      PendingCreate(n, child, mid),
      ..rest
    ]
    [entry, ..rest] -> [entry, ..do_replace_first_create(rest, name, child)]
  }
}

fn put_sequenced_child(
  node: DirectoryNode,
  name: String,
  child: DirectoryNode,
) -> DirectoryNode {
  let order = case dict.has_key(node.subdirs, name) {
    True -> node.subdir_order
    False -> list.append(node.subdir_order, [name])
  }
  DirectoryNode(
    ..node,
    subdirs: dict.insert(node.subdirs, name, child),
    subdir_order: order,
  )
}

fn remove_sequenced_child(node: DirectoryNode, name: String) -> DirectoryNode {
  DirectoryNode(
    ..node,
    subdirs: dict.delete(node.subdirs, name),
    subdir_order: list.filter(node.subdir_order, fn(n) { n != name }),
  )
}

// ─────────────────────────────────────────────────────────────────────────────
// Recursive node traversal / update
// ─────────────────────────────────────────────────────────────────────────────

/// Look up the optimistic node at `path` from the root.
pub fn get_working_directory(
  state: DirectoryState,
  path: String,
) -> Option(DirectoryNode) {
  do_get(state.root, segments(path), optimistic_child_reachable)
}

/// Look up the sequenced-only node at `path`.
pub fn get_sequenced_directory(
  state: DirectoryState,
  path: String,
) -> Option(DirectoryNode) {
  do_get(state.root, segments(path), sequenced_child)
}

fn optimistic_child_reachable(node: DirectoryNode, name: String) -> Option(DirectoryNode) {
  optimistic_child(node, name, False)
}

fn do_get(
  node: DirectoryNode,
  segs: List(String),
  child_of: fn(DirectoryNode, String) -> Option(DirectoryNode),
) -> Option(DirectoryNode) {
  case segs {
    [] -> Some(node)
    [name, ..rest] ->
      case child_of(node, name) {
        None -> None
        Some(child) -> do_get(child, rest, child_of)
      }
  }
}

/// Update the optimistic node at `segs`, threading a result value out.
fn update_optimistic(
  node: DirectoryNode,
  segs: List(String),
  f: fn(DirectoryNode) -> #(DirectoryNode, a),
) -> Result(#(DirectoryNode, a), Nil) {
  case segs {
    [] -> Ok(f(node))
    [name, ..rest] ->
      case optimistic_child(node, name, False) {
        None -> Error(Nil)
        Some(child) ->
          case update_optimistic(child, rest, f) {
            Ok(#(new_child, a)) -> Ok(#(put_optimistic_child(node, name, new_child), a))
            Error(e) -> Error(e)
          }
      }
  }
}

/// Update the sequenced node at `segs`, threading a result value out.
fn update_sequenced(
  node: DirectoryNode,
  segs: List(String),
  f: fn(DirectoryNode) -> #(DirectoryNode, a),
) -> Result(#(DirectoryNode, a), Nil) {
  case segs {
    [] -> Ok(f(node))
    [name, ..rest] ->
      case sequenced_child(node, name) {
        None -> Error(Nil)
        Some(child) ->
          case update_sequenced(child, rest, f) {
            Ok(#(new_child, a)) -> Ok(#(put_sequenced_child(node, name, new_child), a))
            Error(e) -> Error(e)
          }
      }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Storage reads (per node)
// ─────────────────────────────────────────────────────────────────────────────

fn storage_get(storage: StorageState, key: String) -> Option(Json) {
  case latest_storage_pending_for(storage.pending, key) {
    None -> dict.get(storage.sequenced, key) |> option.from_result
    Some(PendingLifetime(_, sets, _)) -> list.last(sets) |> option.from_result
    Some(PendingDelete(_, _)) | Some(PendingClear(_)) -> None
  }
}

fn storage_entries(storage: StorageState) -> List(#(String, Json)) {
  let sequenced_phase =
    list.filter_map(storage.insertion_order, fn(key) {
      case has_storage_delete_or_clear(storage.pending, key) {
        True -> Error(Nil)
        False ->
          case storage_get(storage, key) {
            Some(value) -> Ok(#(key, value))
            None -> Error(Nil)
          }
      }
    })

  let indexed = list.index_map(storage.pending, fn(entry, i) { #(i, entry) })
  let pending_phase =
    list.filter_map(indexed, fn(pair) {
      let #(index, entry) = pair
      case entry {
        PendingLifetime(key, sets, _) -> {
          let last_dc = last_storage_delete_or_clear_index(indexed, key)
          let survives = index > last_dc
          let already_iterated =
            dict.has_key(storage.sequenced, key) && last_dc == -1
          case survives && !already_iterated {
            True -> list.last(sets) |> result.map(fn(value) { #(key, value) })
            False -> Error(Nil)
          }
        }
        _ -> Error(Nil)
      }
    })

  list.append(sequenced_phase, pending_phase)
}

// Optimistic reads by path ---------------------------------------------------

pub fn get(state: DirectoryState, path: String, key: String) -> Option(Json) {
  case get_working_directory(state, path) {
    Some(node) -> storage_get(node.storage, key)
    None -> None
  }
}

pub fn has(state: DirectoryState, path: String, key: String) -> Bool {
  get(state, path, key) != None
}

pub fn entries(state: DirectoryState, path: String) -> List(#(String, Json)) {
  case get_working_directory(state, path) {
    Some(node) -> storage_entries(node.storage)
    None -> []
  }
}

pub fn keys(state: DirectoryState, path: String) -> List(String) {
  entries(state, path) |> list.map(fn(e) { e.0 })
}

pub fn size(state: DirectoryState, path: String) -> Int {
  list.length(entries(state, path))
}

/// Optimistically visible child directory names at `path`, ordered by
/// `seqDataComparator` (acknowledged/detached before unacked-local; lower
/// seq/client_seq first).
pub fn subdirectories(state: DirectoryState, path: String) -> List(String) {
  case get_working_directory(state, path) {
    None -> []
    Some(node) -> optimistic_subdir_names(node)
  }
}

pub fn has_subdirectory(state: DirectoryState, path: String, name: String) -> Bool {
  case get_working_directory(state, path) {
    None -> False
    Some(node) -> optimistic_child(node, name, False) != None
  }
}

pub fn count_subdirectory(state: DirectoryState, path: String) -> Int {
  list.length(subdirectories(state, path))
}

fn optimistic_subdir_names(node: DirectoryNode) -> List(String) {
  let sequenced_names =
    list.filter(node.subdir_order, fn(name) {
      optimistic_child(node, name, False) != None
    })
  let pending_names =
    list.filter_map(node.pending_subdirs, fn(entry) {
      let name = pending_subdir_name(entry)
      case dict.has_key(node.subdirs, name) {
        True -> Error(Nil)
        False ->
          case optimistic_child(node, name, False) {
            Some(_) -> Ok(name)
            None -> Error(Nil)
          }
      }
    })
    |> list.unique
  let all = list.append(sequenced_names, pending_names)
  list.sort(all, fn(a, b) {
    let assert Some(ca) = optimistic_child(node, a, False)
    let assert Some(cb) = optimistic_child(node, b, False)
    seq_data_comparator(ca.create, cb.create)
  })
}

fn seq_data_comparator(a: CreateInfo, b: CreateInfo) -> Order {
  let a_ack = a.seq >= 0
  let b_ack = b.seq >= 0
  case a_ack, b_ack {
    True, False -> order.Lt
    False, True -> order.Gt
    _, _ ->
      case a.seq == b.seq {
        True -> int.compare(a.client_seq, b.client_seq)
        False -> int.compare(a.seq, b.seq)
      }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Local storage operations (optimistic apply + outbound op)
// ─────────────────────────────────────────────────────────────────────────────

pub fn set(
  state: DirectoryState,
  path: String,
  key: String,
  value: Json,
) -> Result(#(DirectoryState, List(DirectoryEvent), DirectoryOp, Int), KernelError) {
  let message_id = state.next_message_id
  let mutate = fn(node: DirectoryNode) {
    let previous = storage_get(node.storage, key)
    let storage = storage_set(node.storage, key, value, message_id)
    #(DirectoryNode(..node, storage: storage), previous)
  }
  case update_optimistic(state.root, segments(path), mutate) {
    Error(_) -> Error(PathNotFound(path))
    Ok(#(root, previous)) ->
      Ok(#(
        DirectoryState(root: root, next_message_id: message_id + 1),
        [ValueChanged(path, key, previous, True)],
        Set(path, key, value),
        message_id,
      ))
  }
}

pub fn delete(
  state: DirectoryState,
  path: String,
  key: String,
) -> Result(#(DirectoryState, List(DirectoryEvent), DirectoryOp, Int), KernelError) {
  let message_id = state.next_message_id
  let mutate = fn(node: DirectoryNode) {
    let previous = storage_get(node.storage, key)
    let storage =
      StorageState(
        ..node.storage,
        pending: list.append(node.storage.pending, [PendingDelete(key, message_id)]),
      )
    #(DirectoryNode(..node, storage: storage), previous)
  }
  case update_optimistic(state.root, segments(path), mutate) {
    Error(_) -> Error(PathNotFound(path))
    Ok(#(root, previous)) -> {
      let events = case previous {
        Some(value) -> [ValueChanged(path, key, Some(value), True)]
        None -> []
      }
      Ok(#(
        DirectoryState(root: root, next_message_id: message_id + 1),
        events,
        Delete(path, key),
        message_id,
      ))
    }
  }
}

pub fn clear(
  state: DirectoryState,
  path: String,
) -> Result(#(DirectoryState, List(DirectoryEvent), DirectoryOp, Int), KernelError) {
  let message_id = state.next_message_id
  let mutate = fn(node: DirectoryNode) {
    let visible = storage_entries(node.storage)
    let storage =
      StorageState(
        ..node.storage,
        pending: list.append(node.storage.pending, [PendingClear(message_id)]),
      )
    #(DirectoryNode(..node, storage: storage), visible)
  }
  case update_optimistic(state.root, segments(path), mutate) {
    Error(_) -> Error(PathNotFound(path))
    Ok(#(root, visible)) -> {
      let events = [
        Cleared(path, True),
        ..list.map(visible, fn(e) { ValueChanged(path, e.0, Some(e.1), True) })
      ]
      Ok(#(
        DirectoryState(root: root, next_message_id: message_id + 1),
        events,
        Clear(path),
        message_id,
      ))
    }
  }
}

fn storage_set(
  storage: StorageState,
  key: String,
  value: Json,
  message_id: Int,
) -> StorageState {
  let pending = case latest_storage_pending_for(storage.pending, key) {
    Some(PendingLifetime(_, _, _)) ->
      append_to_latest_lifetime(storage.pending, key, value, message_id)
    _ ->
      list.append(storage.pending, [PendingLifetime(key, [value], [message_id])])
  }
  StorageState(..storage, pending: pending)
}

// ─────────────────────────────────────────────────────────────────────────────
// Local subdirectory operations
// ─────────────────────────────────────────────────────────────────────────────

pub fn create_subdirectory(
  state: DirectoryState,
  path: String,
  name: String,
) -> Result(#(DirectoryState, List(DirectoryEvent), Option(DirectoryOp), Int), KernelError) {
  case valid_subdir_name(name) {
    False -> Error(InvalidName(name))
    True -> {
      let message_id = state.next_message_id
      let child_path = join(path, name)
      let self = author_of_local(state)
      let mutate = fn(node: DirectoryNode) {
        case optimistic_child(node, name, True) {
          Some(existing) -> {
            // Reuse (and undispose) the existing optimistic child; no new op.
            let #(revived, undispose_events) = case existing.disposed {
              True -> undispose_tree(existing)
              False -> #(existing, [])
            }
            let revived =
              DirectoryNode(..revived, creators: add_creator(revived.creators, self))
            #(put_optimistic_child(node, name, revived), #(False, undispose_events))
          }
          None -> {
            let child =
              new_node(child_path, CreateInfo(-1, message_id), [self], False)
            let node =
              DirectoryNode(
                ..node,
                pending_subdirs: list.append(node.pending_subdirs, [
                  PendingCreate(name, child, message_id),
                ]),
              )
            #(node, #(True, []))
          }
        }
      }
      case update_optimistic(state.root, segments(path), mutate) {
        Error(_) -> Error(PathNotFound(path))
        Ok(#(root, #(is_new, undispose_events))) -> {
          let state = DirectoryState(root: root, next_message_id: message_id + 1)
          case is_new {
            True ->
              Ok(#(
                state,
                [SubDirectoryCreated(child_path, True)],
                Some(CreateSubDirectory(path, name)),
                message_id,
              ))
            False ->
              Ok(#(
                DirectoryState(..state, next_message_id: message_id),
                undispose_events,
                None,
                message_id,
              ))
          }
        }
      }
    }
  }
}

pub fn delete_subdirectory(
  state: DirectoryState,
  path: String,
  name: String,
) -> Result(#(DirectoryState, List(DirectoryEvent), Option(DirectoryOp), Int), KernelError) {
  let message_id = state.next_message_id
  let child_path = join(path, name)
  let mutate = fn(node: DirectoryNode) {
    case optimistic_child(node, name, False) {
      None -> #(node, None)
      Some(previous) -> {
        let #(disposed_tree, dispose_events) = dispose_tree_events(previous)
        let node =
          DirectoryNode(
            ..node,
            pending_subdirs: list.append(node.pending_subdirs, [
              PendingRemove(name, disposed_tree, message_id),
            ]),
          )
        #(node, Some(dispose_events))
      }
    }
  }
  case update_optimistic(state.root, segments(path), mutate) {
    Error(_) -> Error(PathNotFound(path))
    Ok(#(_, None)) ->
      // Optimistically absent: nothing to delete, no op.
      Ok(#(state, [], None, message_id))
    Ok(#(root, Some(dispose_events))) ->
      Ok(#(
        DirectoryState(root: root, next_message_id: message_id + 1),
        list.append([SubDirectoryDeleted(child_path, True)], dispose_events),
        Some(DeleteSubDirectory(path, name)),
        message_id,
      ))
  }
}

fn valid_subdir_name(name: String) -> Bool {
  name != "" && !string.contains(name, "/")
}

fn author_of_local(_state: DirectoryState) -> Int {
  // Local ops in the pure kernel are authored by "self". The runtime maps a
  // concrete client id at the delivery boundary; the kernel only needs a
  // stable marker so a client recognizes its own creates as a creator. We use
  // a sentinel that is later reconciled on ack (which records the true author).
  local_author
}

const local_author = -1

fn add_creator(creators: List(Int), client: Int) -> List(Int) {
  case list.contains(creators, client) {
    True -> creators
    False -> list.append(creators, [client])
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dispose / undispose (marks the tree, emits events bottom-up / top-down)
// ─────────────────────────────────────────────────────────────────────────────

fn dispose_tree_events(node: DirectoryNode) -> #(DirectoryNode, List(DirectoryEvent)) {
  // Dispose children first (bottom-up), then this node.
  let #(subdirs, child_events) =
    list.fold(node.subdir_order, #(node.subdirs, []), fn(acc, name) {
      let #(subdirs, events) = acc
      case dict.get(subdirs, name) {
        Ok(child) -> {
          let #(child, ev) = dispose_tree_events(child)
          #(dict.insert(subdirs, name, child), list.append(events, ev))
        }
        Error(_) -> acc
      }
    })
  let node = DirectoryNode(..node, subdirs: subdirs, disposed: True)
  #(node, list.append(child_events, [Disposed(node.path)]))
}

fn undispose_tree(node: DirectoryNode) -> #(DirectoryNode, List(DirectoryEvent)) {
  let node = DirectoryNode(..node, disposed: False)
  let #(subdirs, child_events) =
    list.fold(node.subdir_order, #(node.subdirs, []), fn(acc, name) {
      let #(subdirs, events) = acc
      case dict.get(subdirs, name) {
        Ok(child) -> {
          let #(child, ev) = undispose_tree(child)
          #(dict.insert(subdirs, name, child), list.append(events, ev))
        }
        Error(_) -> acc
      }
    })
  #(DirectoryNode(..node, subdirs: subdirs), [Undisposed(node.path), ..child_events])
}

/// Reset a disposed node's sequenced data (D13): its sequenced storage and
/// children are cleared, but pending state is kept so a rollback/recreate can
/// continue to reference the same object.
fn clear_sequenced_data(node: DirectoryNode) -> DirectoryNode {
  DirectoryNode(
    ..node,
    storage: StorageState(..node.storage, sequenced: dict.new(), insertion_order: []),
    subdirs: dict.new(),
    subdir_order: [],
  )
}

// ─────────────────────────────────────────────────────────────────────────────
// Remote operations (sequenced ops from other clients)
// ─────────────────────────────────────────────────────────────────────────────

pub fn apply_remote(
  state: DirectoryState,
  op: DirectoryOp,
  meta: SequencedMeta,
) -> #(DirectoryState, List(DirectoryEvent)) {
  case op {
    Set(path, key, value) ->
      apply_remote_storage(state, path, meta, fn(node) {
        remote_storage_set(node, path, key, value)
      })
    Delete(path, key) ->
      apply_remote_storage(state, path, meta, fn(node) {
        remote_storage_delete(node, path, key)
      })
    Clear(path) ->
      apply_remote_storage(state, path, meta, fn(node) {
        remote_storage_clear(node, path)
      })
    CreateSubDirectory(path, name) ->
      apply_remote_subdir(state, path, meta, fn(node) {
        remote_create_subdir(node, path, name, meta, False)
      })
    DeleteSubDirectory(path, name) ->
      apply_remote_subdir(state, path, meta, fn(node) {
        remote_delete_subdir(node, path, name, False)
      })
  }
}

/// Route a remote storage op to the sequenced directory at `path`, applying
/// the stale-instance filter to that target node.
fn apply_remote_storage(
  state: DirectoryState,
  path: String,
  meta: SequencedMeta,
  f: fn(DirectoryNode) -> #(DirectoryNode, List(DirectoryEvent)),
) -> #(DirectoryState, List(DirectoryEvent)) {
  let mutate = fn(node: DirectoryNode) {
    case is_message_for_current_instance(node, meta, None) {
      True -> f(node)
      False -> #(node, [])
    }
  }
  case update_sequenced(state.root, segments(path), mutate) {
    Ok(#(root, events)) -> #(DirectoryState(..state, root: root), events)
    Error(_) -> #(state, [])
  }
}

/// Route a remote subdir op to the sequenced *parent* directory at `path`.
fn apply_remote_subdir(
  state: DirectoryState,
  path: String,
  meta: SequencedMeta,
  f: fn(DirectoryNode) -> #(DirectoryNode, List(DirectoryEvent)),
) -> #(DirectoryState, List(DirectoryEvent)) {
  let mutate = fn(node: DirectoryNode) {
    case is_message_for_current_instance(node, meta, None) {
      True -> f(node)
      False -> #(node, [])
    }
  }
  case update_sequenced(state.root, segments(path), mutate) {
    Ok(#(root, events)) -> #(DirectoryState(..state, root: root), events)
    Error(_) -> #(state, [])
  }
}

/// D12: is this sequenced message for the current live instance of `node`?
/// For remote ops (`target` is `None`): the author must be a creator, or the
/// instance was detached-created, or its create seq is known to others
/// (`!= -1`) and predates the op's reference sequence number.
fn is_message_for_current_instance(
  node: DirectoryNode,
  meta: SequencedMeta,
  target: Option(DirectoryNode),
) -> Bool {
  let targets_this = case target {
    None -> True
    Some(t) -> t.path == node.path && t.create == node.create
  }
  let by_creator = list.contains(node.creators, meta.author)
  let by_detached = node.detached_created
  let by_ref =
    node.create.seq != -1 && node.create.seq <= meta.reference_sequence_number
  targets_this && { by_creator || by_detached || by_ref }
}

fn remote_storage_set(
  node: DirectoryNode,
  path: String,
  key: String,
  value: Json,
) -> #(DirectoryNode, List(DirectoryEvent)) {
  let s = node.storage
  let previous = dict.get(s.sequenced, key) |> option.from_result
  let insertion_order = case dict.has_key(s.sequenced, key) {
    True -> s.insertion_order
    False -> list.append(s.insertion_order, [key])
  }
  let storage =
    StorageState(
      ..s,
      sequenced: dict.insert(s.sequenced, key, value),
      insertion_order: insertion_order,
    )
  let events = case has_storage_pending_for(s.pending, key) {
    True -> []
    False -> [ValueChanged(path, key, previous, False)]
  }
  #(DirectoryNode(..node, storage: storage), events)
}

fn remote_storage_delete(
  node: DirectoryNode,
  path: String,
  key: String,
) -> #(DirectoryNode, List(DirectoryEvent)) {
  let s = node.storage
  let previous = dict.get(s.sequenced, key) |> option.from_result
  let storage =
    StorageState(
      ..s,
      sequenced: dict.delete(s.sequenced, key),
      insertion_order: list.filter(s.insertion_order, fn(k) { k != key }),
    )
  let events = case has_storage_pending_for(s.pending, key) {
    True -> []
    False -> [ValueChanged(path, key, previous, False)]
  }
  #(DirectoryNode(..node, storage: storage), events)
}

fn remote_storage_clear(
  node: DirectoryNode,
  path: String,
) -> #(DirectoryNode, List(DirectoryEvent)) {
  let s = node.storage
  let deleted =
    list.filter_map(s.insertion_order, fn(key) {
      case has_storage_entry_for_key(s.pending, key) {
        True -> Error(Nil)
        False ->
          dict.get(s.sequenced, key) |> result.map(fn(value) { #(key, value) })
      }
    })
  let has_pending_clear =
    list.any(s.pending, fn(entry) {
      case entry {
        PendingClear(_) -> True
        _ -> False
      }
    })
  let events = case has_pending_clear {
    True -> []
    False -> [
      Cleared(path, False),
      ..list.map(deleted, fn(e) { ValueChanged(path, e.0, Some(e.1), False) })
    ]
  }
  let storage = StorageState(..s, sequenced: dict.new(), insertion_order: [])
  #(DirectoryNode(..node, storage: storage), events)
}

fn remote_create_subdir(
  node: DirectoryNode,
  path: String,
  name: String,
  meta: SequencedMeta,
  local: Bool,
) -> #(DirectoryNode, List(DirectoryEvent)) {
  let child_path = join(path, name)
  let create = CreateInfo(meta.sequence_number, meta.client_sequence_number)
  case sequenced_child(node, name) {
    Some(existing) -> {
      // Already sequenced: record the author as a creator, undispose if needed.
      let #(revived, _) = case existing.disposed {
        True -> undispose_tree(existing)
        False -> #(existing, [])
      }
      let revived =
        DirectoryNode(..revived, creators: add_creator(revived.creators, meta.author))
      let node = put_sequenced_child(node, name, revived)
      // Suppress event: change already visible (subdir existed).
      #(node, suppress_if_local(local, []))
    }
    None -> {
      // Reuse a locally-pending create's node if present (stamp its seq).
      let #(child, had_pending) = case latest_pending_subdir(node, name) {
        Some(PendingCreate(_, pending_node, _)) -> #(
          DirectoryNode(
            ..pending_node,
            create: create,
            creators: add_creator(pending_node.creators, meta.author),
            disposed: False,
          ),
          True,
        )
        _ -> #(new_node(child_path, create, [meta.author], False), False)
      }
      let node = put_sequenced_child(node, name, child)
      let masked = has_pending_subdir_named(node, name)
      let events = case local || masked {
        True -> []
        False -> [SubDirectoryCreated(child_path, False)]
      }
      let _ = had_pending
      #(node, events)
    }
  }
}

fn remote_delete_subdir(
  node: DirectoryNode,
  path: String,
  name: String,
  local: Bool,
) -> #(DirectoryNode, List(DirectoryEvent)) {
  let child_path = join(path, name)
  case sequenced_child(node, name) {
    None -> #(node, [])
    Some(previous) -> {
      // Remove from sequenced, dispose + reset sequenced data of the old tree.
      let #(disposed, _) = dispose_tree_events(previous)
      let _ = clear_sequenced_data(disposed)
      let node = remove_sequenced_child(node, name)
      let masked = has_pending_remove_named(node, name)
      let events = case local || masked {
        True -> []
        False -> [SubDirectoryDeleted(child_path, False)]
      }
      #(node, events)
    }
  }
}

fn suppress_if_local(local: Bool, events: List(DirectoryEvent)) -> List(DirectoryEvent) {
  case local {
    True -> []
    False -> events
  }
}

fn has_pending_subdir_named(node: DirectoryNode, name: String) -> Bool {
  list.any(node.pending_subdirs, fn(e) { pending_subdir_name(e) == name })
}

fn has_pending_remove_named(node: DirectoryNode, name: String) -> Bool {
  list.any(node.pending_subdirs, fn(e) {
    case e {
      PendingRemove(n, _, _) -> n == name
      _ -> False
    }
  })
}

// ─────────────────────────────────────────────────────────────────────────────
// Acks (own ops coming back sequenced)
// ─────────────────────────────────────────────────────────────────────────────

/// Commit an acked local op: pending → sequenced. Acks arrive in submission
/// order (FIFO); a mismatch is fatal. Acking emits no events (the optimistic
/// view already reflected the op at submit).
pub fn ack_local(
  state: DirectoryState,
  op: DirectoryOp,
  meta: SequencedMeta,
) -> Result(DirectoryState, KernelError) {
  case op {
    Set(path, _, _) | Delete(path, _) | Clear(path) ->
      ack_storage(state, op, path)
    CreateSubDirectory(path, name) -> ack_create_subdir(state, op, path, name, meta)
    DeleteSubDirectory(path, name) -> ack_delete_subdir(state, op, path, name)
  }
}

fn ack_storage(
  state: DirectoryState,
  op: DirectoryOp,
  path: String,
) -> Result(DirectoryState, KernelError) {
  let mutate = fn(node: DirectoryNode) {
    case ack_storage_node(node.storage, op) {
      Ok(storage) -> #(DirectoryNode(..node, storage: storage), Ok(Nil))
      Error(detail) -> #(node, Error(detail))
    }
  }
  case update_sequenced(state.root, segments(path), mutate) {
    Error(_) ->
      Error(UnexpectedAck(op, "no sequenced directory at path " <> path))
    Ok(#(root, Ok(Nil))) -> Ok(DirectoryState(..state, root: root))
    Ok(#(_, Error(detail))) -> Error(UnexpectedAck(op, detail))
  }
}

fn ack_storage_node(
  storage: StorageState,
  op: DirectoryOp,
) -> Result(StorageState, String) {
  case op {
    Clear(_) ->
      case storage.pending {
        [PendingClear(_), ..rest] ->
          Ok(StorageState(sequenced: dict.new(), insertion_order: [], pending: rest))
        _ -> Error("expected pending clear at queue head")
      }
    Delete(_, key) ->
      case split_storage_at_first_for_key(storage.pending, key) {
        Ok(#(before, PendingDelete(_, _), after)) ->
          Ok(StorageState(
            sequenced: dict.delete(storage.sequenced, key),
            insertion_order: list.filter(storage.insertion_order, fn(k) {
              k != key
            }),
            pending: list.append(before, after),
          ))
        _ -> Error("expected pending delete for key " <> key)
      }
    Set(_, key, _) ->
      case split_storage_at_first_for_key(storage.pending, key) {
        Ok(#(before, PendingLifetime(_, [acked, ..rest_sets], [_, ..rest_ids]), after)) -> {
          let pending = case rest_sets {
            [] -> list.append(before, after)
            _ ->
              list.append(before, [PendingLifetime(key, rest_sets, rest_ids), ..after])
          }
          let insertion_order = case dict.has_key(storage.sequenced, key) {
            True -> storage.insertion_order
            False -> list.append(storage.insertion_order, [key])
          }
          Ok(StorageState(
            sequenced: dict.insert(storage.sequenced, key, acked),
            insertion_order: insertion_order,
            pending: pending,
          ))
        }
        _ -> Error("expected pending lifetime for key " <> key)
      }
    _ -> Error("non-storage op in ack_storage_node")
  }
}

fn ack_create_subdir(
  state: DirectoryState,
  op: DirectoryOp,
  path: String,
  name: String,
  meta: SequencedMeta,
) -> Result(DirectoryState, KernelError) {
  let create = CreateInfo(meta.sequence_number, meta.client_sequence_number)
  let mutate = fn(node: DirectoryNode) {
    case take_first_pending_create(node.pending_subdirs, name) {
      Error(_) -> #(node, Error("expected pending create for " <> name))
      Ok(#(pending_node, rest)) -> {
        let node = DirectoryNode(..node, pending_subdirs: rest)
        case sequenced_child(node, name) {
          Some(_) ->
            // Already committed by a concurrent remote create; drop pending.
            #(node, Ok(Nil))
          None -> {
            let child =
              DirectoryNode(
                ..pending_node,
                create: create,
                creators: add_creator(pending_node.creators, meta.author),
                disposed: False,
              )
            #(put_sequenced_child(node, name, child), Ok(Nil))
          }
        }
      }
    }
  }
  ack_subdir_apply(state, op, path, mutate)
}

fn ack_delete_subdir(
  state: DirectoryState,
  op: DirectoryOp,
  path: String,
  name: String,
) -> Result(DirectoryState, KernelError) {
  let mutate = fn(node: DirectoryNode) {
    case take_first_pending_remove(node.pending_subdirs, name) {
      Error(_) -> #(node, Error("expected pending delete for " <> name))
      Ok(#(_, rest)) -> {
        let node = DirectoryNode(..node, pending_subdirs: rest)
        // Commit the delete into sequenced state (dispose the sequenced tree).
        case sequenced_child(node, name) {
          None -> #(node, Ok(Nil))
          Some(_) -> #(remove_sequenced_child(node, name), Ok(Nil))
        }
      }
    }
  }
  ack_subdir_apply(state, op, path, mutate)
}

fn ack_subdir_apply(
  state: DirectoryState,
  op: DirectoryOp,
  path: String,
  mutate: fn(DirectoryNode) -> #(DirectoryNode, Result(Nil, String)),
) -> Result(DirectoryState, KernelError) {
  case update_sequenced(state.root, segments(path), mutate) {
    Error(_) ->
      Error(UnexpectedAck(op, "no sequenced directory at path " <> path))
    Ok(#(root, Ok(Nil))) -> Ok(DirectoryState(..state, root: root))
    Ok(#(_, Error(detail))) -> Error(UnexpectedAck(op, detail))
  }
}

fn take_first_pending_create(
  pending: List(PendingSubdir),
  name: String,
) -> Result(#(DirectoryNode, List(PendingSubdir)), Nil) {
  do_take_pending(pending, [], fn(e) {
    case e {
      PendingCreate(n, node, _) if n == name -> Some(node)
      _ -> None
    }
  })
}

fn take_first_pending_remove(
  pending: List(PendingSubdir),
  name: String,
) -> Result(#(DirectoryNode, List(PendingSubdir)), Nil) {
  do_take_pending(pending, [], fn(e) {
    case e {
      PendingRemove(n, node, _) if n == name -> Some(node)
      _ -> None
    }
  })
}

fn do_take_pending(
  pending: List(PendingSubdir),
  seen: List(PendingSubdir),
  match: fn(PendingSubdir) -> Option(DirectoryNode),
) -> Result(#(DirectoryNode, List(PendingSubdir)), Nil) {
  case pending {
    [] -> Error(Nil)
    [entry, ..rest] ->
      case match(entry) {
        Some(node) -> Ok(#(node, list.append(list.reverse(seen), rest)))
        None -> do_take_pending(rest, [entry, ..seen], match)
      }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Rollback (undo an unacked local op; LIFO-compatible per key/subdir)
// ─────────────────────────────────────────────────────────────────────────────

/// The highest pending message id anywhere in the tree — the last submitted
/// op, i.e. the one a LIFO rollback targets.
pub fn last_pending_message_id(state: DirectoryState) -> Option(Int) {
  case node_pending_ids(state.root) {
    [] -> None
    ids -> Some(list.fold(ids, -1, int.max))
  }
}

fn node_pending_ids(node: DirectoryNode) -> List(Int) {
  let storage_ids =
    list.flat_map(node.storage.pending, fn(entry) {
      case entry {
        PendingLifetime(_, _, ids) -> ids
        PendingDelete(_, id) -> [id]
        PendingClear(id) -> [id]
      }
    })
  let subdir_ids =
    list.flat_map(node.pending_subdirs, fn(entry) {
      case entry {
        PendingCreate(_, child, id) -> [id, ..node_pending_ids(child)]
        PendingRemove(_, _, id) -> [id]
      }
    })
  let child_ids = list.flat_map(node.subdir_order, fn(name) {
    case dict.get(node.subdirs, name) {
      Ok(child) -> node_pending_ids(child)
      Error(_) -> []
    }
  })
  list.flatten([storage_ids, subdir_ids, child_ids])
}

pub fn rollback(
  state: DirectoryState,
  op: DirectoryOp,
  message_id: Int,
) -> Result(#(DirectoryState, List(DirectoryEvent)), KernelError) {
  case op {
    Set(path, key, _) -> rollback_set(state, op, path, key, message_id)
    Delete(path, key) -> rollback_delete(state, op, path, key, message_id)
    Clear(path) -> rollback_clear(state, op, path, message_id)
    CreateSubDirectory(path, name) ->
      rollback_create(state, op, path, name, message_id)
    DeleteSubDirectory(path, name) ->
      rollback_remove(state, op, path, name, message_id)
  }
}

fn rollback_storage(
  state: DirectoryState,
  op: DirectoryOp,
  path: String,
  f: fn(DirectoryNode) -> Result(#(DirectoryNode, List(DirectoryEvent)), String),
) -> Result(#(DirectoryState, List(DirectoryEvent)), KernelError) {
  let mutate = fn(node: DirectoryNode) {
    case f(node) {
      Ok(#(node, events)) -> #(node, Ok(events))
      Error(detail) -> #(node, Error(detail))
    }
  }
  case update_optimistic(state.root, segments(path), mutate) {
    Error(_) -> Error(UnexpectedRollback(op, "no directory at path " <> path))
    Ok(#(root, Ok(events))) -> Ok(#(DirectoryState(..state, root: root), events))
    Ok(#(_, Error(detail))) -> Error(UnexpectedRollback(op, detail))
  }
}

fn rollback_set(state, op, path, key, message_id) {
  rollback_storage(state, op, path, fn(node) {
    let s = node.storage
    case remove_last_lifetime_set(s.pending, key, message_id) {
      Error(_) -> Error("no pending set for key " <> key)
      Ok(#(pending, restored_value)) -> {
        let storage = StorageState(..s, pending: pending)
        // Compensating event: value reverts to the prior optimistic value.
        let node = DirectoryNode(..node, storage: storage)
        let previous = storage_get(storage, key)
        let _ = restored_value
        Ok(#(node, [ValueChanged(path, key, previous, True)]))
      }
    }
  })
}

fn rollback_delete(state, op, path, key, message_id) {
  rollback_storage(state, op, path, fn(node) {
    let s = node.storage
    case remove_pending_entry(s.pending, PendingDelete(key, message_id)) {
      Error(_) -> Error("no pending delete for key " <> key)
      Ok(pending) -> {
        let storage = StorageState(..s, pending: pending)
        let node = DirectoryNode(..node, storage: storage)
        let restored = storage_get(storage, key)
        let events = case restored {
          Some(_) -> [ValueChanged(path, key, restored, True)]
          None -> []
        }
        Ok(#(node, events))
      }
    }
  })
}

fn rollback_clear(state, op, path, message_id) {
  rollback_storage(state, op, path, fn(node) {
    let s = node.storage
    case remove_pending_entry(s.pending, PendingClear(message_id)) {
      Error(_) -> Error("no pending clear")
      Ok(pending) -> {
        let storage = StorageState(..s, pending: pending)
        let node = DirectoryNode(..node, storage: storage)
        Ok(#(node, []))
      }
    }
  })
}

fn rollback_create(state, op, path, name, message_id) {
  let child_path = join(path, name)
  let mutate = fn(node: DirectoryNode) {
    case remove_pending_subdir(node.pending_subdirs, name, message_id, True) {
      Error(_) -> #(node, Error("no pending create for " <> name))
      Ok(pending) -> #(
        DirectoryNode(..node, pending_subdirs: pending),
        Ok([SubDirectoryDeleted(child_path, True), Disposed(child_path)]),
      )
    }
  }
  rollback_subdir_apply(state, op, path, mutate)
}

fn rollback_remove(state, op, path, name, message_id) {
  let child_path = join(path, name)
  let mutate = fn(node: DirectoryNode) {
    case pop_pending_remove(node.pending_subdirs, name, message_id) {
      Error(_) -> #(node, Error("no pending delete for " <> name))
      Ok(#(deleted_node, pending)) -> {
        let #(revived, _) = undispose_tree(deleted_node)
        let node = DirectoryNode(..node, pending_subdirs: pending)
        #(node, Ok([Undisposed(child_path), SubDirectoryCreated(child_path, True)]))
        |> fn(pair) {
          let #(n, r) = pair
          // Re-expose the previously-deleted tree if it isn't otherwise present.
          case r {
            Ok(ev) ->
              case optimistic_child(n, name, False) {
                Some(_) -> #(n, Ok(ev))
                None -> {
                  let n = case dict.has_key(n.subdirs, name) {
                    True -> put_sequenced_child(n, name, revived)
                    False ->
                      DirectoryNode(
                        ..n,
                        pending_subdirs: list.append(n.pending_subdirs, [
                          PendingCreate(name, revived, message_id),
                        ]),
                      )
                  }
                  #(n, Ok(ev))
                }
              }
            Error(_) -> pair
          }
        }
      }
    }
  }
  rollback_subdir_apply(state, op, path, mutate)
}

fn rollback_subdir_apply(
  state: DirectoryState,
  op: DirectoryOp,
  path: String,
  mutate: fn(DirectoryNode) -> #(DirectoryNode, Result(List(DirectoryEvent), String)),
) -> Result(#(DirectoryState, List(DirectoryEvent)), KernelError) {
  case update_optimistic(state.root, segments(path), mutate) {
    Error(_) -> Error(UnexpectedRollback(op, "no directory at path " <> path))
    Ok(#(root, Ok(events))) -> Ok(#(DirectoryState(..state, root: root), events))
    Ok(#(_, Error(detail))) -> Error(UnexpectedRollback(op, detail))
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Resubmit (re-send still-relevant pending ops after reconnect)
// ─────────────────────────────────────────────────────────────────────────────

/// Whether the pending entry that `op`/`message_id` produced is still present.
/// Only still-present pending entries are worth resubmitting (D14).
pub fn resubmit(
  state: DirectoryState,
  op: DirectoryOp,
  message_id: Int,
) -> Result(Option(DirectoryOp), KernelError) {
  let still_present = case op {
    Set(path, key, _) -> storage_pending_has_id(state, path, key, message_id)
    Delete(path, key) -> storage_pending_has_id(state, path, key, message_id)
    Clear(path) -> storage_pending_has_id(state, path, "", message_id)
    CreateSubDirectory(path, name) ->
      subdir_pending_has_id(state, path, name, message_id, True)
    DeleteSubDirectory(path, name) ->
      subdir_pending_has_id(state, path, name, message_id, False)
  }
  case still_present {
    True -> Ok(Some(op))
    False -> Ok(None)
  }
}

fn storage_pending_has_id(
  state: DirectoryState,
  path: String,
  _key: String,
  message_id: Int,
) -> Bool {
  case get_working_directory(state, path) {
    None -> False
    Some(node) -> list.contains(node_storage_ids(node), message_id)
  }
}

fn node_storage_ids(node: DirectoryNode) -> List(Int) {
  list.flat_map(node.storage.pending, fn(entry) {
    case entry {
      PendingLifetime(_, _, ids) -> ids
      PendingDelete(_, id) -> [id]
      PendingClear(id) -> [id]
    }
  })
}

fn subdir_pending_has_id(
  state: DirectoryState,
  path: String,
  name: String,
  message_id: Int,
  is_create: Bool,
) -> Bool {
  case get_working_directory(state, path) {
    None -> False
    Some(node) ->
      list.any(node.pending_subdirs, fn(entry) {
        case entry, is_create {
          PendingCreate(n, _, id), True -> n == name && id == message_id
          PendingRemove(n, _, id), False -> n == name && id == message_id
          _, _ -> False
        }
      })
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stashed ops (replay through the local API, generating fresh metadata)
// ─────────────────────────────────────────────────────────────────────────────

pub fn apply_stashed_op(
  state: DirectoryState,
  op: DirectoryOp,
) -> Result(#(DirectoryState, List(DirectoryEvent), Option(DirectoryOp), Int), KernelError) {
  case op {
    Set(path, key, value) -> some_op(set(state, path, key, value))
    Delete(path, key) -> some_op(delete(state, path, key))
    Clear(path) -> some_op(clear(state, path))
    CreateSubDirectory(path, name) -> create_subdirectory(state, path, name)
    DeleteSubDirectory(path, name) -> delete_subdirectory(state, path, name)
  }
}

fn some_op(
  r: Result(#(DirectoryState, List(DirectoryEvent), DirectoryOp, Int), KernelError),
) -> Result(#(DirectoryState, List(DirectoryEvent), Option(DirectoryOp), Int), KernelError) {
  result.map(r, fn(tuple) {
    let #(state, events, op, id) = tuple
    #(state, events, Some(op), id)
  })
}

// ─────────────────────────────────────────────────────────────────────────────
// Summary (recursive, sequenced-only, pending excluded)
// ─────────────────────────────────────────────────────────────────────────────

pub type DirectorySummary {
  DirectorySummary(
    storage: List(#(String, Json)),
    create: CreateInfo,
    creators: List(Int),
    detached_created: Bool,
    subdirs: List(#(String, DirectorySummary)),
  )
}

pub fn summary_tree(state: DirectoryState) -> DirectorySummary {
  summary_node(state.root)
}

fn summary_node(node: DirectoryNode) -> DirectorySummary {
  let storage =
    list.filter_map(node.storage.insertion_order, fn(key) {
      case dict.get(node.storage.sequenced, key) {
        Ok(value) -> Ok(#(key, value))
        Error(_) -> Error(Nil)
      }
    })
  let subdirs =
    list.filter_map(node.subdir_order, fn(name) {
      case dict.get(node.subdirs, name) {
        Ok(child) -> Ok(#(name, summary_node(child)))
        Error(_) -> Error(Nil)
      }
    })
  DirectorySummary(
    storage: storage,
    create: node.create,
    creators: node.creators,
    detached_created: node.detached_created,
    subdirs: subdirs,
  )
}

pub fn from_summary(summary: DirectorySummary) -> DirectoryState {
  DirectoryState(root: load_node("/", summary), next_message_id: 0)
}

fn load_node(path: String, summary: DirectorySummary) -> DirectoryNode {
  let #(sequenced, order) =
    list.fold(summary.storage, #(dict.new(), []), fn(acc, entry) {
      let #(d, o) = acc
      let #(key, value) = entry
      let o = case dict.has_key(d, key) {
        True -> o
        False -> [key, ..o]
      }
      #(dict.insert(d, key, value), o)
    })
  let #(subdirs, subdir_order) =
    list.fold(summary.subdirs, #(dict.new(), []), fn(acc, entry) {
      let #(d, o) = acc
      let #(name, child_summary) = entry
      let child = load_node(join(path, name), child_summary)
      #(dict.insert(d, name, child), [name, ..o])
    })
  DirectoryNode(
    path: path,
    create: summary.create,
    creators: summary.creators,
    detached_created: summary.detached_created,
    disposed: False,
    storage: StorageState(
      sequenced: sequenced,
      insertion_order: list.reverse(order),
      pending: [],
    ),
    subdirs: subdirs,
    subdir_order: list.reverse(subdir_order),
    pending_subdirs: [],
  )
}

// ─────────────────────────────────────────────────────────────────────────────
// Invariants
// ─────────────────────────────────────────────────────────────────────────────

pub fn check_invariants(state: DirectoryState) -> Result(Nil, KernelError) {
  check_node(state.root)
}

fn check_node(node: DirectoryNode) -> Result(Nil, KernelError) {
  // Every sequenced child's path must match parent + name.
  let path_ok =
    list.all(dict.to_list(node.subdirs), fn(pair) {
      let #(name, child) = pair
      child.path == join(node.path, name)
    })
  case path_ok {
    False -> Error(InvariantViolation("child path mismatch under " <> node.path))
    True -> {
      // No duplicate visible child names optimistically.
      let visible = optimistic_subdir_names(node)
      case list.length(visible) == list.length(list.unique(visible)) {
        False ->
          Error(InvariantViolation("duplicate visible child under " <> node.path))
        True ->
          list.try_fold(dict.values(node.subdirs), Nil, fn(_, child) {
            check_node(child)
          })
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Storage pending-queue helpers (mirror map_kernel, plus message ids)
// ─────────────────────────────────────────────────────────────────────────────

fn latest_storage_pending_for(
  pending: List(PendingStorage),
  key: String,
) -> Option(PendingStorage) {
  list.reverse(pending)
  |> list.find(fn(entry) { storage_matches_key(entry, key) })
  |> option.from_result
}

fn storage_matches_key(entry: PendingStorage, key: String) -> Bool {
  case entry {
    PendingClear(_) -> True
    PendingDelete(k, _) -> k == key
    PendingLifetime(k, _, _) -> k == key
  }
}

fn has_storage_pending_for(pending: List(PendingStorage), key: String) -> Bool {
  list.any(pending, fn(entry) { storage_matches_key(entry, key) })
}

fn has_storage_delete_or_clear(pending: List(PendingStorage), key: String) -> Bool {
  list.any(pending, fn(entry) {
    case entry {
      PendingClear(_) -> True
      PendingDelete(k, _) -> k == key
      PendingLifetime(_, _, _) -> False
    }
  })
}

fn has_storage_entry_for_key(pending: List(PendingStorage), key: String) -> Bool {
  list.any(pending, fn(entry) {
    case entry {
      PendingDelete(k, _) -> k == key
      PendingLifetime(k, _, _) -> k == key
      PendingClear(_) -> False
    }
  })
}

fn last_storage_delete_or_clear_index(
  indexed: List(#(Int, PendingStorage)),
  key: String,
) -> Int {
  list.fold(indexed, -1, fn(acc, pair) {
    case pair.1 {
      PendingClear(_) -> pair.0
      PendingDelete(k, _) if k == key -> pair.0
      _ -> acc
    }
  })
}

fn append_to_latest_lifetime(
  pending: List(PendingStorage),
  key: String,
  value: Json,
  message_id: Int,
) -> List(PendingStorage) {
  list.reverse(pending)
  |> do_append_to_first_lifetime(key, value, message_id)
  |> list.reverse
}

fn do_append_to_first_lifetime(
  reversed: List(PendingStorage),
  key: String,
  value: Json,
  message_id: Int,
) -> List(PendingStorage) {
  case reversed {
    [] -> []
    [PendingLifetime(k, sets, ids), ..rest] if k == key -> [
      PendingLifetime(k, list.append(sets, [value]), list.append(ids, [message_id])),
      ..rest
    ]
    [entry, ..rest] -> [
      entry,
      ..do_append_to_first_lifetime(rest, key, value, message_id)
    ]
  }
}

fn split_storage_at_first_for_key(
  pending: List(PendingStorage),
  key: String,
) -> Result(#(List(PendingStorage), PendingStorage, List(PendingStorage)), Nil) {
  do_split_storage(pending, key, [])
}

fn do_split_storage(
  pending: List(PendingStorage),
  key: String,
  seen: List(PendingStorage),
) -> Result(#(List(PendingStorage), PendingStorage, List(PendingStorage)), Nil) {
  case pending {
    [] -> Error(Nil)
    [PendingDelete(k, _) as entry, ..rest] if k == key ->
      Ok(#(list.reverse(seen), entry, rest))
    [PendingLifetime(k, _, _) as entry, ..rest] if k == key ->
      Ok(#(list.reverse(seen), entry, rest))
    [entry, ..rest] -> do_split_storage(rest, key, [entry, ..seen])
  }
}

/// Remove the most recent set in `key`'s latest lifetime tagged `message_id`.
fn remove_last_lifetime_set(
  pending: List(PendingStorage),
  key: String,
  message_id: Int,
) -> Result(#(List(PendingStorage), Option(Json)), Nil) {
  list.reverse(pending)
  |> do_remove_last_set(key, message_id, [])
  |> result.map(fn(pair) {
    let #(reversed, value) = pair
    #(list.reverse(reversed), value)
  })
}

fn do_remove_last_set(
  reversed: List(PendingStorage),
  key: String,
  message_id: Int,
  seen: List(PendingStorage),
) -> Result(#(List(PendingStorage), Option(Json)), Nil) {
  case reversed {
    [] -> Error(Nil)
    [PendingLifetime(k, sets, ids), ..rest] if k == key -> {
      case list.last(ids) == Ok(message_id) {
        True -> {
          let new_sets = drop_last(sets)
          let new_ids = drop_last(ids)
          let removed = list.last(sets) |> option.from_result
          case new_ids {
            [] -> Ok(#(list.append(list.reverse(seen), rest), removed))
            _ ->
              Ok(#(
                list.append(list.reverse(seen), [
                  PendingLifetime(k, new_sets, new_ids),
                  ..rest
                ]),
                removed,
              ))
          }
        }
        False -> Error(Nil)
      }
    }
    [entry, ..rest] -> do_remove_last_set(rest, key, message_id, [entry, ..seen])
  }
}

fn drop_last(xs: List(a)) -> List(a) {
  case list.reverse(xs) {
    [] -> []
    [_, ..rest] -> list.reverse(rest)
  }
}

fn remove_pending_entry(
  pending: List(PendingStorage),
  target: PendingStorage,
) -> Result(List(PendingStorage), Nil) {
  case list.contains(pending, target) {
    True -> Ok(list.filter(pending, fn(e) { e != target }))
    False -> Error(Nil)
  }
}

fn remove_pending_subdir(
  pending: List(PendingSubdir),
  name: String,
  message_id: Int,
  is_create: Bool,
) -> Result(List(PendingSubdir), Nil) {
  let found =
    list.any(pending, fn(entry) {
      case entry, is_create {
        PendingCreate(n, _, id), True -> n == name && id == message_id
        PendingRemove(n, _, id), False -> n == name && id == message_id
        _, _ -> False
      }
    })
  case found {
    False -> Error(Nil)
    True ->
      Ok(
        list.filter(pending, fn(entry) {
          case entry, is_create {
            PendingCreate(n, _, id), True -> !{ n == name && id == message_id }
            PendingRemove(n, _, id), False -> !{ n == name && id == message_id }
            _, _ -> True
          }
        }),
      )
  }
}

fn pop_pending_remove(
  pending: List(PendingSubdir),
  name: String,
  message_id: Int,
) -> Result(#(DirectoryNode, List(PendingSubdir)), Nil) {
  do_pop_pending_remove(pending, name, message_id, [])
}

fn do_pop_pending_remove(
  pending: List(PendingSubdir),
  name: String,
  message_id: Int,
  seen: List(PendingSubdir),
) -> Result(#(DirectoryNode, List(PendingSubdir)), Nil) {
  case pending {
    [] -> Error(Nil)
    [PendingRemove(n, node, id), ..rest] if n == name && id == message_id ->
      Ok(#(node, list.append(list.reverse(seen), rest)))
    [entry, ..rest] -> do_pop_pending_remove(rest, name, message_id, [entry, ..seen])
  }
}
