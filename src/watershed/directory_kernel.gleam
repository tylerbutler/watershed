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
    /// Immutable local instance identity: the `create` this node was *born*
    /// with, never re-stamped or cleared. Two nodes at the same path are the
    /// same instance iff their births match — the kernel's stand-in for FF's
    /// object identity. Alias bookkeeping (a folded pending-create marker vs
    /// the sequenced slot) must compare births rather than assume the slot
    /// holds the marker's instance: an interleaved ack can commit a
    /// *different* instance into the slot while the marker still retains its
    /// own.
    birth: CreateInfo,
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
    birth: create,
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
    // children (overwriting any prior instance), and the slot is the canonical
    // copy — but only while the slot still holds *this* instance (matching
    // births). A later delete clears the slot (the instance survives in the
    // marker), and a later ack can commit a *different* instance into it; in
    // both cases the marker node is the pending create's instance, exactly as
    // FF's pending entry keeps referencing its own object. The marker node's
    // `disposed` flag is authoritative — set by the delete's dispose
    // lifecycle, cleared again by an undispose.
    Some(PendingCreate(_, pending_child, _, True)) ->
      case dict.get(node.subdirs, name) {
        Ok(live) ->
          case live.birth == pending_child.birth {
            True -> Some(live)
            False -> Some(pending_child)
          }
        Error(_) -> Some(pending_child)
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
    // Folded create: the canonical copy lives in the sequenced slot while the
    // slot still holds this instance (matching births), and the marker keeps a
    // same-instance alias. FF gets this for free (pending entry and sequenced
    // map hold the SAME object); in this immutable port we must mirror the
    // write into the marker too, or the alias drifts stale and a
    // delete/recreate race resurrects an out-of-date instance. If the slot was
    // cleared by a delete — or holds a *different* instance committed by an
    // interleaved ack — only the marker is written: FF never mutates another
    // object, and never re-inserts into the sequenced map outside sequenced-op
    // processing.
    Some(PendingCreate(_, _, _, True)) -> {
      let node = case dict.get(node.subdirs, name) {
        Ok(live) ->
          case live.birth == child.birth {
            True -> put_sequenced_child(node, name, child)
            False -> node
          }
        Error(_) -> node
      }
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

/// Names that may alias a child instance from this node: sequenced children
/// plus pending-create markers (FF `getSubdirectoriesEvenIfDisposed` reaches
/// both). Pending-remove-hidden names resolve to `None` via `optimistic_child`
/// and get skipped by callers, exactly as FF's iterators skip them.
fn aliased_child_names(node: DirectoryNode) -> List(String) {
  let marker_names =
    list.filter_map(node.pending_subdirs, fn(entry) {
      case entry {
        PendingCreate(name, _, _, _) ->
          case dict.has_key(node.subdirs, name) {
            True -> Error(Nil)
            False -> Ok(name)
          }
        PendingRemove(_, _) -> Error(Nil)
      }
    })
    |> list.unique
  list.append(node.subdir_order, marker_names)
}

/// FF `undisposeSubdirectoryTree`: clear the disposed flag on this node and
/// every reachable aliased child (including disposed ones — a revive must
/// reach the retained marker copies), bottom-up.
fn undispose_tree(
  node: DirectoryNode,
) -> #(DirectoryNode, List(DirectoryEvent)) {
  let #(node, child_events) =
    list.fold(aliased_child_names(node), #(node, []), fn(acc, name) {
      let #(node, events) = acc
      case optimistic_child(node, name, True) {
        Some(child) -> {
          let #(child, ev) = undispose_tree(child)
          #(put_optimistic_child(node, name, child), list.append(events, ev))
        }
        None -> acc
      }
    })
  #(DirectoryNode(..node, disposed: False), [
    Undisposed(node.path),
    ..child_events
  ])
}

/// FF `disposeSubDirectoryTree` + `clearSubDirectorySequencedData` + `dispose`:
/// walk the *optimistic* children bottom-up (pending-remove-hidden and already
/// disposed children are skipped, as in FF's `subdirectories()` iterator), then
/// reset this node's instance identity — create seq back to unknown (-1),
/// creators to just the local client (standing in for the create op this client
/// has pending or may later send) — and drop sequenced storage and children
/// while retaining all pending data, so a marker-retained node revived by a
/// later create carries a fresh identity instead of leaking the deleted
/// instance's. Cleared copies are written back into their marker slots first,
/// so the retained aliases stay in sync (FF mutates the shared objects).
fn dispose_subdir_tree(node: DirectoryNode, self: Int) -> DirectoryNode {
  let node =
    list.fold(aliased_child_names(node), node, fn(node, name) {
      case optimistic_child(node, name, False) {
        Some(child) ->
          put_optimistic_child(node, name, dispose_subdir_tree(child, self))
        None -> node
      }
    })
  DirectoryNode(
    ..node,
    create: CreateInfo(-1, -1),
    creators: [self],
    detached_created: False,
    disposed: True,
    storage: StorageState(
      ..node.storage,
      sequenced: dict.new(),
      insertion_order: [],
    ),
    subdirs: dict.new(),
    subdir_order: [],
  )
}

/// After a sequenced delete removed `name`'s instance from `subdirs`, keep a
/// folded pending-create marker pointing at the cleared node — but only when
/// the marker actually aliases *that* instance (matching births; FF's pending
/// entry holds the same object). A marker for a different instance — unfolded,
/// or folded but superseded in the slot by an interleaved ack — retains its
/// own node untouched; overwriting it would destroy that instance's retained
/// pending data.
fn sync_folded_marker(
  node: DirectoryNode,
  name: String,
  cleared: DirectoryNode,
) -> DirectoryNode {
  case latest_pending_subdir(node, name) {
    Some(PendingCreate(_, marker_node, _, True)) ->
      case marker_node.birth == cleared.birth {
        True ->
          DirectoryNode(
            ..node,
            pending_subdirs: mark_latest_pending_create_folded(
              node.pending_subdirs,
              name,
              cleared,
            ),
          )
        False -> node
      }
    _ -> node
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Remote operations (sequenced ops from other clients)
// ─────────────────────────────────────────────────────────────────────────────

pub fn apply_remote(
  state: DirectoryState,
  op: DirectoryOp,
  meta: SequencedMeta,
  self: Int,
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
        remote_delete_subdir(node, path, name, self, False)
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
      // instance, or one whose identity a sequenced delete reset) AND this
      // parent instance was itself live at this message (FF's re-stamp guard in
      // `processCreateSubDirectoryMessage`); an already-sequenced instance
      // keeps its original seq.
      let revived = case
        node.create.seq != -1
        && node.create.seq <= meta.sequence_number
        && revived.create.seq == -1
      {
        True -> DirectoryNode(..revived, create: create)
        False -> revived
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
  self: Int,
  local: Bool,
) -> #(DirectoryNode, List(DirectoryEvent)) {
  let child_path = join(path, name)
  case sequenced_child(node, name) {
    None -> #(node, [])
    Some(previous) -> {
      // Remove the child from sequenced (the whole subtree goes with it), and
      // reset the removed instance's identity (FF `disposeSubDirectoryTree`) on
      // the retained folded-marker alias, if one exists, so a later revive
      // starts from a cleared identity.
      let cleared = dispose_subdir_tree(previous, self)
      let node = remove_sequenced_child(node, name)
      let node = sync_folded_marker(node, name, cleared)
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
        case ack_storage_node(node.storage, op, meta.client_sequence_number) {
          Ok(Some(storage)) -> #(
            DirectoryNode(..node, storage: storage),
            Ok(Nil),
          )
          // Stale ack: this op's pending died with a superseded instance of
          // this path; the current instance's pending belongs to later ops.
          Ok(None) -> #(node, Ok(Nil))
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
    Ok(#(_, Error(detail))) -> Error(UnexpectedAck(op, detail))
  }
}

/// Commit one acked storage op against a node's storage. The pending entry is
/// matched by the ack's message id — the kernel's stand-in for FF's
/// `localOpMetadata` object-identity check (`pendingEntry === localOpMetadata`,
/// guarded by `targetSubdir === this`): an id that is no longer present means
/// this op's pending died with a superseded instance of this path (dropped at
/// create-dedup or delete time), so the ack is stale and a no-op (`Ok(None)`)
/// — matching by key alone would wrongly consume a *later* op's pending on the
/// current instance. An id that is present but out of FIFO position is a
/// genuine protocol violation.
fn ack_storage_node(
  storage: StorageState,
  op: DirectoryOp,
  ack_id: Int,
) -> Result(Option(StorageState), String) {
  let present = list.contains(storage_pending_ids(storage), ack_id)
  case op {
    Clear(_) ->
      case storage.pending {
        [PendingClear(id), ..rest] if id == ack_id ->
          Ok(
            Some(StorageState(
              sequenced: dict.new(),
              insertion_order: [],
              pending: rest,
            )),
          )
        _ if !present -> Ok(None)
        _ -> Error("expected pending clear at queue head")
      }
    Delete(_, key) ->
      case split_storage_at_first_for_key(storage.pending, key) {
        Ok(#(before, PendingDelete(_, id), after)) if id == ack_id ->
          Ok(
            Some(StorageState(
              sequenced: dict.delete(storage.sequenced, key),
              insertion_order: list.filter(storage.insertion_order, fn(k) {
                k != key
              }),
              pending: list.append(before, after),
            )),
          )
        _ if !present -> Ok(None)
        _ -> Error("expected pending delete for key " <> key)
      }
    Set(_, key, _) ->
      case split_storage_at_first_for_key(storage.pending, key) {
        Ok(#(
          before,
          PendingLifetime(_, [acked, ..rest_sets], [head_id, ..rest_ids]),
          after,
        ))
          if head_id == ack_id
        -> {
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
          Ok(
            Some(StorageState(
              sequenced: dict.insert(storage.sequenced, key, acked),
              insertion_order: insertion_order,
              pending: pending,
            )),
          )
        }
        _ if !present -> Ok(None)
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
    // Mirror FF `processCreateSubDirectoryMessage` (local branch): consume
    // *this submission's* pending create, then commit its single copy. The
    // marker is matched by message id — the stand-in for FF's `targetSubdir
    // === this` parent-object guard: an ack whose marker died with a
    // superseded parent instance must be a no-op, not consume a later
    // same-name create's marker (which would silently eat that create's
    // instance and drop its eventual commit).
    case
      take_pending_create_by_id(
        orig_node.pending_subdirs,
        name,
        meta.client_sequence_number,
      )
    {
      // No pending create for this submission: its marker died with a
      // superseded instance (or a stashed create was already reconciled).
      // Stale ack, no-op.
      Error(_) -> #(orig_node, Ok(Nil))
      Ok(#(#(marker_node, _folded), rest)) -> {
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
          // cleared the slot.) A disposed instance is revived whole
          // (`undisposeSubdirectoryTree`), and the create seq is stamped only
          // if still unknown and this parent instance was live at this message
          // (FF's re-stamp guard); self is already a creator from submit time.
          None -> {
            let #(child, _revive_events) = case marker_node.disposed {
              True -> undispose_tree(marker_node)
              False -> #(marker_node, [])
            }
            let child = case
              node.create.seq != -1
              && node.create.seq <= meta.sequence_number
              && child.create.seq == -1
            {
              True -> DirectoryNode(..child, create: create)
              False -> child
            }
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
    // Match this submission's pending remove by message id (the stand-in for
    // FF's `targetSubdir === this` parent-object guard — see
    // `ack_create_subdir`).
    case
      remove_pending_subdir(
        node.pending_subdirs,
        name,
        meta.client_sequence_number,
        False,
      )
    {
      // No pending remove for this submission: the delete was a no-op locally
      // (its target was already absent — e.g. a stashed delete of a subdir
      // that never existed), or its pending died with a superseded parent
      // instance. Stale ack, no-op.
      Error(_) -> #(node, Ok(Nil))
      Ok(rest) -> {
        let node = DirectoryNode(..node, pending_subdirs: rest)
        // Commit the delete into sequenced state, resetting the removed
        // instance's identity (FF `disposeSubDirectoryTree`) on the retained
        // folded-marker alias, if any — same lifecycle as the remote path.
        case sequenced_child(node, name) {
          None -> #(node, Ok(Nil))
          Some(previous) -> {
            let cleared = dispose_subdir_tree(previous, meta.author)
            let node = remove_sequenced_child(node, name)
            #(sync_folded_marker(node, name, cleared), Ok(Nil))
          }
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

/// FF `reSubmitCore` routing (D14): decide whether the pending op behind
/// `op`/`message_id` is still worth resubmitting, applying FF's resubmit-time
/// state effects. Targets are located on the *retained instance* — traversal
/// includes disposed marker aliases, because FF's `localOpMetadata` holds the
/// object itself, not a path — then gated on `!targetSubdir.disposed` plus the
/// per-entry pending check (`resubmitKeyMessage`/`resubmitSubDirectoryMessage`).
/// A create resubmit records the current client id as a creator and undisposes
/// the retained pending tree, which is what lets storage ops queued *behind*
/// it in the same reconnect batch see their target alive and resubmit too —
/// dropping them while their pending survives on the retained node would leak
/// a never-acked pending that only this client can see.
///
/// When an op IS dropped, its pending entry is stripped from the retained
/// instance (see `strip_dropped_pending`) — one deliberate divergence from FF,
/// which leaves the entry on the disposed object. That op will never be
/// sequenced, so if a later create ack revives the retained instance the
/// leftover entry resurfaces as a phantom optimistic edit no other client ever
/// sees; dropping the op and its pending together keeps the revive convergent.
pub fn resubmit(
  state: DirectoryState,
  op: DirectoryOp,
  message_id: Int,
  self: Int,
) -> #(DirectoryState, Option(DirectoryOp)) {
  case op {
    Set(path, _, _) | Delete(path, _) | Clear(path) -> {
      let locate = fn(node: DirectoryNode) {
        case
          !node.disposed
          && list.contains(storage_pending_ids(node.storage), message_id)
          && storage_pending_matches(node.storage.pending, op, message_id)
        {
          True -> Ok(#(node, Nil))
          False -> Error(Nil)
        }
      }
      case update_retained_instance(state.root, segments(path), locate) {
        Ok(_) -> #(state, Some(op))
        Error(_) -> #(strip_dropped_pending(state, op, message_id), None)
      }
    }
    CreateSubDirectory(path, name) -> {
      let revive = fn(node: DirectoryNode) {
        let owns_marker =
          list.any(node.pending_subdirs, fn(entry) {
            case entry {
              PendingCreate(n, _, id, _) -> n == name && id == message_id
              _ -> False
            }
          })
        case !node.disposed && owns_marker {
          False -> Error(Nil)
          True ->
            // FF revives the *latest* pending create's instance for the name
            // (`findLast` in `resubmitSubDirectoryMessage`), which may be a
            // later recreate rather than this submission's own node: creator
            // id for the (possibly new) connection, tree-wide undispose. The
            // live copy is the sequenced slot when the marker is folded and
            // the slot is still occupied; otherwise the marker node itself.
            case find_latest_pending_create(node.pending_subdirs, name) {
              None -> Error(Nil)
              Some(#(marker_node, folded)) -> {
                // The live copy is the sequenced slot only while it still
                // holds this instance (matching births).
                let slot_aliased =
                  folded
                  && case dict.get(node.subdirs, name) {
                    Ok(live) -> live.birth == marker_node.birth
                    Error(_) -> False
                  }
                let child = case slot_aliased {
                  True ->
                    case dict.get(node.subdirs, name) {
                      Ok(live) -> live
                      Error(_) -> marker_node
                    }
                  False -> marker_node
                }
                let child =
                  DirectoryNode(
                    ..child,
                    creators: add_creator(child.creators, self),
                  )
                let #(child, _events) = undispose_tree(child)
                let node = case slot_aliased {
                  True -> put_sequenced_child(node, name, child)
                  False -> node
                }
                Ok(#(
                  DirectoryNode(
                    ..node,
                    pending_subdirs: replace_latest_pending_create(
                      node.pending_subdirs,
                      name,
                      child,
                    ),
                  ),
                  Nil,
                ))
              }
            }
        }
      }
      case update_retained_instance(state.root, segments(path), revive) {
        Ok(#(root, Nil)) -> #(DirectoryState(..state, root: root), Some(op))
        Error(_) -> #(strip_dropped_pending(state, op, message_id), None)
      }
    }
    DeleteSubDirectory(path, name) -> {
      let locate = fn(node: DirectoryNode) {
        let owns_remove =
          list.any(node.pending_subdirs, fn(entry) {
            case entry {
              PendingRemove(n, id) -> n == name && id == message_id
              _ -> False
            }
          })
        case !node.disposed && owns_remove {
          True -> Ok(#(node, Nil))
          False -> Error(Nil)
        }
      }
      case update_retained_instance(state.root, segments(path), locate) {
        Ok(_) -> #(state, Some(op))
        Error(_) -> #(strip_dropped_pending(state, op, message_id), None)
      }
    }
  }
}

/// Remove the pending entry behind a dropped resubmit from wherever it still
/// lives — searching *all* retained instances, disposed ones included (the
/// drop usually happened precisely because the instance is disposed). The
/// entry's op will never be sequenced, so leaving it behind would let a later
/// revive of the retained instance surface a phantom optimistic edit.
fn strip_dropped_pending(
  state: DirectoryState,
  op: DirectoryOp,
  message_id: Int,
) -> DirectoryState {
  let #(path, mutate) = case op {
    Set(path, _, _) | Delete(path, _) | Clear(path) -> #(
      path,
      fn(node: DirectoryNode) {
        case list.contains(storage_pending_ids(node.storage), message_id) {
          False -> Error(Nil)
          True ->
            Ok(#(
              DirectoryNode(
                ..node,
                storage: StorageState(
                  ..node.storage,
                  pending: strip_storage_pending(
                    node.storage.pending,
                    message_id,
                  ),
                ),
              ),
              Nil,
            ))
        }
      },
    )
    CreateSubDirectory(path, name) -> #(path, fn(node: DirectoryNode) {
      case remove_pending_subdir(node.pending_subdirs, name, message_id, True) {
        Error(_) -> Error(Nil)
        Ok(rest) -> Ok(#(DirectoryNode(..node, pending_subdirs: rest), Nil))
      }
    })
    DeleteSubDirectory(path, name) -> #(path, fn(node: DirectoryNode) {
      case
        remove_pending_subdir(node.pending_subdirs, name, message_id, False)
      {
        Error(_) -> Error(Nil)
        Ok(rest) -> Ok(#(DirectoryNode(..node, pending_subdirs: rest), Nil))
      }
    })
  }
  case update_retained_instance(state.root, segments(path), mutate) {
    Ok(#(root, Nil)) -> DirectoryState(..state, root: root)
    Error(_) -> state
  }
}

/// Remove the single pending storage entry tagged `message_id`: the one set
/// inside a lifetime (dropping the lifetime when it empties), or the matching
/// delete/clear entry.
fn strip_storage_pending(
  pending: List(PendingStorage),
  message_id: Int,
) -> List(PendingStorage) {
  list.filter_map(pending, fn(entry) {
    case entry {
      PendingLifetime(key, sets, ids) ->
        case list.contains(ids, message_id) {
          False -> Ok(entry)
          True -> {
            let kept =
              list.zip(sets, ids)
              |> list.filter(fn(pair) { pair.1 != message_id })
            case kept {
              [] -> Error(Nil)
              _ ->
                Ok(PendingLifetime(
                  key,
                  list.map(kept, fn(pair) { pair.0 }),
                  list.map(kept, fn(pair) { pair.1 }),
                ))
            }
          }
        }
      PendingDelete(_, id) if id == message_id -> Error(Nil)
      PendingClear(id) if id == message_id -> Error(Nil)
      other -> Ok(other)
    }
  })
}

/// The latest pending create entry for `name` (FF `findLast` in
/// `resubmitSubDirectoryMessage`), skipping any later pending remove.
fn find_latest_pending_create(
  pending: List(PendingSubdir),
  name: String,
) -> Option(#(DirectoryNode, Bool)) {
  list.reverse(pending)
  |> list.find_map(fn(entry) {
    case entry {
      PendingCreate(n, node, _, folded) if n == name -> Ok(#(node, folded))
      _ -> Error(Nil)
    }
  })
  |> option.from_result
}

/// Whether this node's pending storage still holds `op`'s pending entry — FF
/// `resubmitKeyMessage`/`resubmitClearMessage`'s check. Only sets verify the
/// submission identity (FF `keySets.includes(localOpMetadata)`, here the
/// message id); deletes and clears match by kind (and key) alone.
fn storage_pending_matches(
  pending: List(PendingStorage),
  op: DirectoryOp,
  message_id: Int,
) -> Bool {
  list.any(pending, fn(entry) {
    case op, entry {
      Set(_, key, _), PendingLifetime(k, _, ids) ->
        k == key && list.contains(ids, message_id)
      Delete(_, key), PendingDelete(k, _) -> k == key
      Clear(_), PendingClear(_) -> True
      _, _ -> False
    }
  })
}

/// Every retained instance that may answer to `name` under `node`, newest
/// lifecycle first, tagged with the slot it canonically lives in. Unlike
/// `optimistic_child`, this surfaces instances *shadowed* by later pending
/// entries — e.g. the old sequenced instance hidden under a pending remove +
/// pending recreate — because FF's `localOpMetadata` holds a direct object
/// reference that a path lookup cannot reproduce; resubmit must be able to
/// find the specific instance whose pending it is deciding about.
fn candidate_children(
  node: DirectoryNode,
  name: String,
) -> List(#(ChildSlot, DirectoryNode)) {
  let marker_candidates =
    list.reverse(node.pending_subdirs)
    |> list.filter_map(fn(entry) {
      case entry {
        // A folded marker whose sequenced slot holds the *same* instance
        // (matching births) is an alias; the sequenced copy below covers it.
        PendingCreate(n, child, id, folded) if n == name -> {
          let aliased =
            folded
            && case dict.get(node.subdirs, name) {
              Ok(live) -> live.birth == child.birth
              Error(_) -> False
            }
          case aliased {
            True -> Error(Nil)
            False -> Ok(#(MarkerSlot(id), child))
          }
        }
        _ -> Error(Nil)
      }
    })
  let sequenced_candidate =
    dict.get(node.subdirs, name)
    |> result.map(fn(child) { [#(SequencedSlot, child)] })
    |> result.unwrap([])
  list.append(marker_candidates, sequenced_candidate)
}

type ChildSlot {
  SequencedSlot
  MarkerSlot(message_id: Int)
}

/// Write `child` back into the slot a candidate came from. A sequenced-slot
/// write also refreshes a folded marker aliasing that instance (mirroring
/// FF's shared object) — the counterpart of `put_optimistic_child`.
fn put_candidate_child(
  node: DirectoryNode,
  name: String,
  slot: ChildSlot,
  child: DirectoryNode,
) -> DirectoryNode {
  case slot {
    SequencedSlot -> {
      let node = put_sequenced_child(node, name, child)
      sync_folded_marker(node, name, child)
    }
    MarkerSlot(id) ->
      DirectoryNode(
        ..node,
        pending_subdirs: list.map(node.pending_subdirs, fn(entry) {
          case entry {
            PendingCreate(n, _, entry_id, folded)
              if n == name && entry_id == id
            -> PendingCreate(n, child, entry_id, folded)
            other -> other
          }
        }),
      )
  }
}

/// Depth-first search-and-update over retained instances: at each path
/// segment try every candidate instance (see `candidate_children`) until one
/// subtree's target satisfies `f`, then write the updated nodes back along
/// that branch. `f` returns `Error(Nil)` for "not this instance", making the
/// whole traversal the kernel's stand-in for following FF's metadata object
/// reference to wherever the pending actually lives.
fn update_retained_instance(
  node: DirectoryNode,
  segs: List(String),
  f: fn(DirectoryNode) -> Result(#(DirectoryNode, r), Nil),
) -> Result(#(DirectoryNode, r), Nil) {
  case segs {
    [] -> f(node)
    [name, ..rest] ->
      list.fold(candidate_children(node, name), Error(Nil), fn(acc, cand) {
        case acc {
          Ok(_) -> acc
          Error(_) -> {
            let #(slot, child) = cand
            case update_retained_instance(child, rest, f) {
              Ok(#(new_child, r)) ->
                Ok(#(put_candidate_child(node, name, slot, new_child), r))
              Error(_) -> Error(Nil)
            }
          }
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
    birth: summary.create,
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
