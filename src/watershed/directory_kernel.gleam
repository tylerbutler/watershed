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
  /// A local create of `name`. `node` is this create's optimistic instance —
  /// the single copy of its storage/children while `folded` is `False`. Once a
  /// concurrent remote create of the same name (or this create's own ack) has
  /// moved the instance into sequenced children, `folded` becomes `True` and
  /// `subdirs[name]` becomes the canonical copy; `node` is then only a fallback
  /// used to re-insert the instance if a later delete removes it before this
  /// create is acked. Keeping the instance in exactly one canonical place (the
  /// marker while unfolded, else `subdirs`) is what prevents storage copy-drift;
  /// it mirrors FF's single-`SubDirectory`-object-per-instance model, where the
  /// pending-create entry and the sequenced map hold the *same* object.
  PendingCreate(
    name: String,
    node: DirectoryNode,
    message_id: Int,
    folded: Bool,
  )
  /// A local delete of `name`. The sequenced child is left in place and only
  /// hidden optimistically, so pending storage on the subtree survives for its
  /// acks and a rollback simply re-exposes the retained tree (D13).
  PendingRemove(name: String, message_id: Int)
}

pub type DirectoryOp {
  Set(path: String, key: String, value: Json)
  Delete(path: String, key: String)
  Clear(path: String)
  CreateSubDirectory(path: String, name: String)
  DeleteSubDirectory(path: String, name: String)
}

pub type DirectoryEvent {
  ValueChanged(
    path: String,
    key: String,
    previous_value: Option(Json),
    local: Bool,
  )
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
  DirectoryState(
    root: new_node("/", CreateInfo(0, 0), [], True),
    next_message_id: 0,
  )
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
    storage: StorageState(
      sequenced: dict.new(),
      insertion_order: [],
      pending: [],
    ),
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
fn latest_pending_subdir(
  node: DirectoryNode,
  name: String,
) -> Option(PendingSubdir) {
  list.reverse(node.pending_subdirs)
  |> list.find(fn(entry) { pending_subdir_name(entry) == name })
  |> option.from_result
}

fn pending_subdir_name(entry: PendingSubdir) -> String {
  case entry {
    PendingCreate(name, _, _, _) -> name
    PendingRemove(name, _) -> name
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
    // No pending marker: the sequenced child (if any) is the live instance.
    None -> dict.get(node.subdirs, name) |> option.from_result
    // Latest op is a not-yet-folded create: its single copy lives in the marker
    // (this is the instance even if an older, being-deleted instance still sits
    // in `subdirs`).
    Some(PendingCreate(_, pending_child, _, False)) -> Some(pending_child)
    // Latest op is a folded create: its instance was moved into sequenced
    // children (overwriting any prior instance), which is now the canonical
    // copy. If a later delete has since cleared that slot, the instance is
    // retained as a disposed fallback in the marker (FF keeps the *same*
    // object referenced by the pending entry, disposed); surface it so
    // `include_disposed` callers (a re-fold on remote create) revive it.
    Some(PendingCreate(_, pending_child, _, True)) ->
      case dict.get(node.subdirs, name) {
        Ok(live) -> Some(live)
        Error(_) -> Some(DirectoryNode(..pending_child, disposed: True))
      }
    // Latest op is a delete: optimistically absent.
    Some(PendingRemove(_, _)) -> None
  }
  case child {
    Some(c) if c.disposed && !include_disposed -> None
    other -> other
  }
}

fn sequenced_child(node: DirectoryNode, name: String) -> Option(DirectoryNode) {
  dict.get(node.subdirs, name) |> option.from_result
}

/// Write `child` back to wherever `name`'s live instance canonically lives: into
/// the latest not-yet-folded pending create marker, else into sequenced children.
fn put_optimistic_child(
  node: DirectoryNode,
  name: String,
  child: DirectoryNode,
) -> DirectoryNode {
  case latest_pending_subdir(node, name) {
    // Not-yet-folded create instance: its single copy lives in the marker.
    Some(PendingCreate(_, _, _, False)) ->
      DirectoryNode(
        ..node,
        pending_subdirs: replace_latest_pending_create(
          node.pending_subdirs,
          name,
          child,
        ),
      )
    // Folded create: the canonical copy lives in sequenced children, but the
    // marker keeps a re-insert fallback used if a later delete clears the slot
    // before this create's ack. FF gets this for free (pending entry and
    // sequenced map hold the SAME object); in this immutable port we must
    // mirror the write into the marker too, or the fallback drifts stale and a
    // delete/recreate race resurrects an out-of-date instance.
    Some(PendingCreate(_, _, _, True)) -> {
      let node = put_sequenced_child(node, name, child)
      DirectoryNode(
        ..node,
        pending_subdirs: mark_latest_pending_create_folded(
          node.pending_subdirs,
          name,
          child,
        ),
      )
    }
    // No pending create: writes target the sequenced node.
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
    [PendingCreate(n, _, mid, folded), ..rest] if n == name -> [
      PendingCreate(n, child, mid, folded),
      ..rest
    ]
    [entry, ..rest] -> [entry, ..do_replace_first_create(rest, name, child)]
  }
}

/// Mark the latest pending create for `name` as folded — its instance has been
/// moved into sequenced children (the canonical copy) by a concurrent remote
/// create. The marker's `node` is kept as a re-insert fallback.
fn mark_latest_pending_create_folded(
  pending: List(PendingSubdir),
  name: String,
  folded_node: DirectoryNode,
) -> List(PendingSubdir) {
  list.reverse(pending)
  |> do_mark_first_create_folded(name, folded_node)
  |> list.reverse
}

fn do_mark_first_create_folded(
  reversed: List(PendingSubdir),
  name: String,
  folded_node: DirectoryNode,
) -> List(PendingSubdir) {
  case reversed {
    [] -> []
    [PendingCreate(n, _, mid, _), ..rest] if n == name -> [
      PendingCreate(n, folded_node, mid, True),
      ..rest
    ]
    // Stop at the first entry for this name (latest-wins) if it isn't a create.
    [entry, ..rest] if entry.name == name -> [entry, ..rest]
    [entry, ..rest] -> [
      entry,
      ..do_mark_first_create_folded(rest, name, folded_node)
    ]
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

fn optimistic_child_reachable(
  node: DirectoryNode,
  name: String,
) -> Option(DirectoryNode) {
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
            Ok(#(new_child, a)) ->
              Ok(#(put_optimistic_child(node, name, new_child), a))
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
            Ok(#(new_child, a)) ->
              Ok(#(put_sequenced_child(node, name, new_child), a))
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

pub fn has_subdirectory(
  state: DirectoryState,
  path: String,
  name: String,
) -> Bool {
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
) -> Result(
  #(DirectoryState, List(DirectoryEvent), DirectoryOp, Int),
  KernelError,
) {
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
) -> Result(
  #(DirectoryState, List(DirectoryEvent), DirectoryOp, Int),
  KernelError,
) {
  let message_id = state.next_message_id
  let mutate = fn(node: DirectoryNode) {
    let previous = storage_get(node.storage, key)
    let storage =
      StorageState(
        ..node.storage,
        pending: list.append(node.storage.pending, [
          PendingDelete(key, message_id),
        ]),
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
) -> Result(
  #(DirectoryState, List(DirectoryEvent), DirectoryOp, Int),
  KernelError,
) {
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
  self: Int,
) -> Result(
  #(DirectoryState, List(DirectoryEvent), Option(DirectoryOp), Int),
  KernelError,
) {
  case valid_subdir_name(name) {
    False -> Error(InvalidName(name))
    True -> {
      let message_id = state.next_message_id
      let child_path = join(path, name)
      let mutate = fn(node: DirectoryNode) {
        case optimistic_child(node, name, True) {
          Some(existing) -> {
            // Reuse (and undispose) the existing optimistic child; no new op.
            let #(revived, undispose_events) = case existing.disposed {
              True -> undispose_tree(existing)
              False -> #(existing, [])
            }
            let revived =
              DirectoryNode(
                ..revived,
                creators: add_creator(revived.creators, self),
              )
            #(
              put_optimistic_child(node, name, revived),
              #(False, undispose_events),
            )
          }
          None -> {
            let child =
              new_node(child_path, CreateInfo(-1, message_id), [self], False)
            let node =
              DirectoryNode(
                ..node,
                pending_subdirs: list.append(node.pending_subdirs, [
                  PendingCreate(name, child, message_id, False),
                ]),
              )
            #(node, #(True, []))
          }
        }
      }
      case update_optimistic(state.root, segments(path), mutate) {
        Error(_) -> Error(PathNotFound(path))
        Ok(#(root, #(is_new, undispose_events))) -> {
          let state =
            DirectoryState(root: root, next_message_id: message_id + 1)
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
) -> Result(
  #(DirectoryState, List(DirectoryEvent), Option(DirectoryOp), Int),
  KernelError,
) {
  let message_id = state.next_message_id
  let child_path = join(path, name)
  let mutate = fn(node: DirectoryNode) {
    case optimistic_child(node, name, False) {
      None -> #(node, None)
      Some(previous) -> {
        // Leave the sequenced child in place; only hide it optimistically with
        // a pending delete. Emit dispose events for the (unchanged) subtree.
        let dispose_events = dispose_events_only(previous)
        let node =
          DirectoryNode(
            ..node,
            pending_subdirs: list.append(node.pending_subdirs, [
              PendingRemove(name, message_id),
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

fn add_creator(creators: List(Int), client: Int) -> List(Int) {
  case list.contains(creators, client) {
    True -> creators
    False -> list.append(creators, [client])
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dispose / undispose event generation (walks a subtree, no mutation)
// ─────────────────────────────────────────────────────────────────────────────

/// Dispose events for a subtree, children first (bottom-up), then this node.
fn dispose_events_only(node: DirectoryNode) -> List(DirectoryEvent) {
  let child_events =
    list.flat_map(node.subdir_order, fn(name) {
      case dict.get(node.subdirs, name) {
        Ok(child) -> dispose_events_only(child)
        Error(_) -> []
      }
    })
  list.append(child_events, [Disposed(node.path)])
}

/// Undispose events for a subtree, this node first (top-down), then children.
fn undispose_events_only(node: DirectoryNode) -> List(DirectoryEvent) {
  let child_events =
    list.flat_map(node.subdir_order, fn(name) {
      case dict.get(node.subdirs, name) {
        Ok(child) -> undispose_events_only(child)
        Error(_) -> []
      }
    })
  [Undisposed(node.path), ..child_events]
}

fn undispose_tree(
  node: DirectoryNode,
) -> #(DirectoryNode, List(DirectoryEvent)) {
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
  #(DirectoryNode(..node, subdirs: subdirs), [
    Undisposed(node.path),
    ..child_events
  ])
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
  // Mirror FF `processCreateSubDirectoryMessage` (remote branch): fold the
  // current optimistic instance (a locally-pending create, or an existing
  // sequenced child) into sequenced children — the SAME single copy, never a
  // duplicate — stamping seq and recording the author as a creator.
  case optimistic_child(node, name, True) {
    Some(existing) -> {
      let #(revived, _) = case existing.disposed {
        True -> undispose_tree(existing)
        False -> #(existing, [])
      }
      let revived =
        DirectoryNode(
          ..revived,
          creators: add_creator(revived.creators, meta.author),
        )
      // Stamp the create seq only if still unknown (a fresh optimistic-only
      // instance); an already-sequenced instance keeps its original seq.
      let revived = case revived.create.seq {
        -1 -> DirectoryNode(..revived, create: create)
        _ -> revived
      }
      // Move the single copy into sequenced children (the canonical copy) and
      // mark its pending-create marker (if any) folded, keeping the node as a
      // re-insert fallback in case a later delete removes it before its ack.
      let node = put_sequenced_child(node, name, revived)
      let node =
        DirectoryNode(
          ..node,
          pending_subdirs: mark_latest_pending_create_folded(
            node.pending_subdirs,
            name,
            revived,
          ),
        )
      let masked = has_pending_subdir_named(node, name)
      let events = case local || masked {
        True -> []
        False -> [SubDirectoryCreated(child_path, False)]
      }
      #(node, events)
    }
    None -> {
      // No optimistic instance (optimistically deleted, or brand new): create a
      // fresh sequenced instance.
      let child = new_node(child_path, create, [meta.author], False)
      let node = put_sequenced_child(node, name, child)
      let masked = has_pending_subdir_named(node, name)
      let events = case local || masked {
        True -> []
        False -> [SubDirectoryCreated(child_path, False)]
      }
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
    Some(_) -> {
      // Remove the child from sequenced (the whole subtree goes with it).
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

fn has_pending_subdir_named(node: DirectoryNode, name: String) -> Bool {
  list.any(node.pending_subdirs, fn(e) { pending_subdir_name(e) == name })
}

fn has_pending_remove_named(node: DirectoryNode, name: String) -> Bool {
  list.any(node.pending_subdirs, fn(e) {
    case e {
      PendingRemove(n, _) -> n == name
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
      ack_storage(state, op, path, meta)
    CreateSubDirectory(path, name) ->
      ack_create_subdir(state, op, path, name, meta)
    DeleteSubDirectory(path, name) ->
      ack_delete_subdir(state, op, path, name, meta)
  }
}

fn ack_storage(
  state: DirectoryState,
  op: DirectoryOp,
  path: String,
  meta: SequencedMeta,
) -> Result(DirectoryState, KernelError) {
  let mutate = fn(node: DirectoryNode) {
    // Mirror `apply_remote`: a stale-instance op (its target was
    // deleted/recreated after the author's reference point) is a no-op here
    // too, so its now-absent pending isn't treated as a protocol error.
    case is_message_for_current_instance(node, meta, None) {
      False -> #(node, Ok(Nil))
      True ->
        case ack_storage_node(node.storage, op) {
          Ok(storage) -> #(DirectoryNode(..node, storage: storage), Ok(Nil))
          Error(detail) -> #(node, Error(detail))
        }
    }
  }
  case update_sequenced(state.root, segments(path), mutate) {
    // Path gone: the target instance was deleted/recreated out from under this
    // op (a stale ack). Its pending was discarded with the node; treat as a
    // no-op, matching how remote delivery ignores the same stale op elsewhere.
    Error(_) -> Ok(state)
    Ok(#(root, Ok(Nil))) -> Ok(DirectoryState(..state, root: root))
    Ok(#(_, Error(detail))) -> {
      // `ack_storage_node` couldn't commit the op against the current instance
      // at this path. Distinguish by whether this op's id is a live pending in
      // the current instance's own storage:
      //
      //  * id NOT present here → the op targeted a superseded instance of this
      //    path (created then deleted/recreated, or absorbed into a concurrent
      //    instance and later removed). Its pending died with that instance, so
      //    this is a stale ack and a no-op — mirroring FF's `targetSubdir ===
      //    this` object-identity check. Live absorptions are kept convergent by
      //    merging their storage into the surviving instance at create-ack time
      //    (see `ack_create_subdir`), so the only acks that reach here with an
      //    absent id are for genuinely dead instances, which are safe to drop.
      //
      //  * id present here → the pending exists but the op doesn't match it
      //    (wrong type/order): a genuine protocol violation.
      let id = meta.client_sequence_number
      let current_storage_ids = case get_sequenced_directory(state, path) {
        Some(node) -> storage_pending_ids(node.storage)
        None -> []
      }
      case list.contains(current_storage_ids, id) {
        False -> Ok(state)
        True -> Error(UnexpectedAck(op, detail))
      }
    }
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
          Ok(StorageState(
            sequenced: dict.new(),
            insertion_order: [],
            pending: rest,
          ))
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
        Ok(#(
          before,
          PendingLifetime(_, [acked, ..rest_sets], [_, ..rest_ids]),
          after,
        )) -> {
          let pending = case rest_sets {
            [] -> list.append(before, after)
            _ ->
              list.append(before, [
                PendingLifetime(key, rest_sets, rest_ids),
                ..after
              ])
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
  let mutate = fn(orig_node: DirectoryNode) {
    // Mirror FF `processCreateSubDirectoryMessage` (local branch): consume our
    // pending create for this name (FIFO), then commit its single copy.
    case take_first_pending_create(orig_node.pending_subdirs, name) {
      // No pending create for this name: nothing to commit (e.g. a stashed
      // create whose pending was already reconciled). No-op.
      Error(_) -> #(orig_node, Ok(Nil))
      Ok(#(marker_node, rest)) -> {
        let node = DirectoryNode(..orig_node, pending_subdirs: rest)
        case sequenced_child(node, name) {
          // Already in sequenced children (a concurrent remote create folded
          // our instance before this ack, or it is the same instance): dedup —
          // just drop the marker.
          Some(_) -> #(node, Ok(Nil))
          // Not in sequenced children: commit our instance. It was already
          // visible optimistically, so acking it doesn't change the view — it
          // just moves the single copy from the marker into `subdirs`. (This is
          // FF's re-insert of `pendingEntry.subdir` when the sequenced slot is
          // empty — e.g. a create/delete/recreate where an earlier delete
          // cleared the slot.)
          None -> {
            let child =
              DirectoryNode(
                ..marker_node,
                create: create,
                creators: add_creator(marker_node.creators, meta.author),
                disposed: False,
              )
            #(put_sequenced_child(node, name, child), Ok(Nil))
          }
        }
      }
    }
  }
  ack_subdir_apply(state, op, path, meta, mutate)
}

fn ack_delete_subdir(
  state: DirectoryState,
  op: DirectoryOp,
  path: String,
  name: String,
  meta: SequencedMeta,
) -> Result(DirectoryState, KernelError) {
  let mutate = fn(node: DirectoryNode) {
    case remove_first_pending_remove(node.pending_subdirs, name) {
      // No pending remove: the delete was a no-op locally (its target was
      // already absent) — e.g. a stashed delete of a subdir that never
      // existed. Acking it does nothing, matching remote delivery of the same
      // op.
      Error(_) -> #(node, Ok(Nil))
      Ok(rest) -> {
        let node = DirectoryNode(..node, pending_subdirs: rest)
        // Commit the delete into sequenced state.
        case sequenced_child(node, name) {
          None -> #(node, Ok(Nil))
          Some(_) -> #(remove_sequenced_child(node, name), Ok(Nil))
        }
      }
    }
  }
  ack_subdir_apply(state, op, path, meta, mutate)
}

fn ack_subdir_apply(
  state: DirectoryState,
  op: DirectoryOp,
  path: String,
  meta: SequencedMeta,
  mutate: fn(DirectoryNode) -> #(DirectoryNode, Result(Nil, String)),
) -> Result(DirectoryState, KernelError) {
  // Mirror `apply_remote_subdir`: only apply when the op targets the current
  // instance of the *parent* directory; a stale parent (deleted/recreated after
  // the author's reference point) makes the op a no-op, so its now-absent
  // pending isn't a protocol error.
  let guarded = fn(node: DirectoryNode) {
    case is_message_for_current_instance(node, meta, None) {
      True -> mutate(node)
      False -> #(node, Ok(Nil))
    }
  }
  case update_sequenced(state.root, segments(path), guarded) {
    // Path gone: the target instance was deleted/recreated out from under this
    // op (a stale ack). Its pending was discarded with the node; treat as a
    // no-op, matching how remote delivery ignores the same stale op elsewhere.
    Error(_) -> Ok(state)
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
      PendingCreate(n, node, _, _) if n == name -> Some(node)
      _ -> None
    }
  })
}

/// Remove the pending create for `name` with `message_id`, returning its node
/// and whether it had been folded into sequenced children.
fn take_pending_create_by_id(
  pending: List(PendingSubdir),
  name: String,
  message_id: Int,
) -> Result(#(#(DirectoryNode, Bool), List(PendingSubdir)), Nil) {
  do_take_pending(pending, [], fn(e) {
    case e {
      PendingCreate(n, node, id, folded) if n == name && id == message_id ->
        Some(#(node, folded))
      _ -> None
    }
  })
}

fn remove_first_pending_remove(
  pending: List(PendingSubdir),
  name: String,
) -> Result(List(PendingSubdir), Nil) {
  do_remove_first_pending_remove(pending, name, [])
}

fn do_remove_first_pending_remove(
  pending: List(PendingSubdir),
  name: String,
  seen: List(PendingSubdir),
) -> Result(List(PendingSubdir), Nil) {
  case pending {
    [] -> Error(Nil)
    [PendingRemove(n, _), ..rest] if n == name ->
      Ok(list.append(list.reverse(seen), rest))
    [entry, ..rest] ->
      do_remove_first_pending_remove(rest, name, [entry, ..seen])
  }
}

fn do_take_pending(
  pending: List(PendingSubdir),
  seen: List(PendingSubdir),
  match: fn(PendingSubdir) -> Option(a),
) -> Result(#(a, List(PendingSubdir)), Nil) {
  case pending {
    [] -> Error(Nil)
    [entry, ..rest] ->
      case match(entry) {
        Some(value) -> Ok(#(value, list.append(list.reverse(seen), rest)))
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

/// The pending storage message ids held directly on one node (non-recursive).
fn storage_pending_ids(storage: StorageState) -> List(Int) {
  list.flat_map(storage.pending, fn(entry) {
    case entry {
      PendingLifetime(_, _, ids) -> ids
      PendingDelete(_, id) -> [id]
      PendingClear(id) -> [id]
    }
  })
}

fn node_pending_ids(node: DirectoryNode) -> List(Int) {
  let storage_ids = storage_pending_ids(node.storage)
  let subdir_ids =
    list.flat_map(node.pending_subdirs, fn(entry) {
      case entry {
        PendingCreate(_, child, id, _) -> [id, ..node_pending_ids(child)]
        PendingRemove(_, id) -> [id]
      }
    })
  let child_ids =
    list.flat_map(node.subdir_order, fn(name) {
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
    Ok(#(root, Ok(events))) ->
      Ok(#(DirectoryState(..state, root: root), events))
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
    case take_pending_create_by_id(node.pending_subdirs, name, message_id) {
      Error(_) -> #(node, Error("no pending create for " <> name))
      Ok(#(#(_, folded), pending)) -> {
        let node = DirectoryNode(..node, pending_subdirs: pending)
        case folded {
          // Not yet folded: its single copy lived in the marker, so removing the
          // marker makes the subdir vanish.
          False -> #(
            node,
            Ok([SubDirectoryDeleted(child_path, True), Disposed(child_path)]),
          )
          // Already folded into sequenced children by a concurrent remote
          // co-creator: the sequenced instance survives our rollback and stays
          // visible, so there is no view change to report.
          True -> #(node, Ok([]))
        }
      }
    }
  }
  rollback_subdir_apply(state, op, path, mutate)
}

fn rollback_remove(state, op, path, name, message_id) {
  let child_path = join(path, name)
  let mutate = fn(node: DirectoryNode) {
    case remove_pending_subdir(node.pending_subdirs, name, message_id, False) {
      Error(_) -> #(node, Error("no pending delete for " <> name))
      Ok(pending) -> {
        let node = DirectoryNode(..node, pending_subdirs: pending)
        // The retained child is re-exposed now that the pending delete is gone.
        let undispose = case optimistic_child(node, name, False) {
          Some(child) -> undispose_events_only(child)
          None -> [Undisposed(child_path)]
        }
        #(
          node,
          Ok(list.append(undispose, [SubDirectoryCreated(child_path, True)])),
        )
      }
    }
  }
  rollback_subdir_apply(state, op, path, mutate)
}

fn rollback_subdir_apply(
  state: DirectoryState,
  op: DirectoryOp,
  path: String,
  mutate: fn(DirectoryNode) ->
    #(DirectoryNode, Result(List(DirectoryEvent), String)),
) -> Result(#(DirectoryState, List(DirectoryEvent)), KernelError) {
  case update_optimistic(state.root, segments(path), mutate) {
    Error(_) -> Error(UnexpectedRollback(op, "no directory at path " <> path))
    Ok(#(root, Ok(events))) ->
      Ok(#(DirectoryState(..state, root: root), events))
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
          PendingCreate(n, _, id, _), True -> n == name && id == message_id
          PendingRemove(n, id), False -> n == name && id == message_id
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
  self: Int,
) -> Result(
  #(DirectoryState, List(DirectoryEvent), Option(DirectoryOp), Int),
  KernelError,
) {
  case op {
    Set(path, key, value) -> some_op(set(state, path, key, value))
    Delete(path, key) -> some_op(delete(state, path, key))
    Clear(path) -> some_op(clear(state, path))
    CreateSubDirectory(path, name) ->
      create_subdirectory(state, path, name, self)
    DeleteSubDirectory(path, name) -> delete_subdirectory(state, path, name)
  }
}

fn some_op(
  r: Result(
    #(DirectoryState, List(DirectoryEvent), DirectoryOp, Int),
    KernelError,
  ),
) -> Result(
  #(DirectoryState, List(DirectoryEvent), Option(DirectoryOp), Int),
  KernelError,
) {
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
    False ->
      Error(InvariantViolation("child path mismatch under " <> node.path))
    True -> {
      // No duplicate visible child names optimistically.
      let visible = optimistic_subdir_names(node)
      case list.length(visible) == list.length(list.unique(visible)) {
        False ->
          Error(InvariantViolation(
            "duplicate visible child under " <> node.path,
          ))
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

fn has_storage_delete_or_clear(
  pending: List(PendingStorage),
  key: String,
) -> Bool {
  list.any(pending, fn(entry) {
    case entry {
      PendingClear(_) -> True
      PendingDelete(k, _) -> k == key
      PendingLifetime(_, _, _) -> False
    }
  })
}

fn has_storage_entry_for_key(
  pending: List(PendingStorage),
  key: String,
) -> Bool {
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
      PendingLifetime(
        k,
        list.append(sets, [value]),
        list.append(ids, [message_id]),
      ),
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
    [entry, ..rest] ->
      do_remove_last_set(rest, key, message_id, [entry, ..seen])
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
        PendingCreate(n, _, id, _), True -> n == name && id == message_id
        PendingRemove(n, id), False -> n == name && id == message_id
        _, _ -> False
      }
    })
  case found {
    False -> Error(Nil)
    True ->
      Ok(
        list.filter(pending, fn(entry) {
          case entry, is_create {
            PendingCreate(n, _, id, _), True ->
              !{ n == name && id == message_id }
            PendingRemove(n, id), False -> !{ n == name && id == message_id }
            _, _ -> True
          }
        }),
      )
  }
}
