//// Pure port of FluidFramework's `packages/dds/map/src/directory.ts`
//// (`SharedDirectory` + `SubDirectory`).
////
//// SharedDirectory is SharedMap with recursion. Each directory node has a
//// key-value store, the same as a SharedMap (see `map_kernel`), with a named
//// set of child directories. This kernel is a pure *tree* port. There is no
//// process and there are no side effects. Every operation returns the new
//// state with the events, and, for a local op, with the outbound op that it
//// produced.
////
//// The new difficulty over `map_kernel` is **hierarchical identity**. Several
//// clients can create one subdirectory at the same time, delete it, and
//// create it again under the same absolute path. An op addresses a directory
//// by its absolute path, but it must apply to the *current live instance* of
//// that path only. That filter is the central correctness rule. It is
//// `is_message_for_current_instance`, which is D12 in the plan, and this
//// kernel models it from the creator ids, the create sequence data, and the
//// reference sequence number of the op.
////
//// The state of each node has the same shape as in `map_kernel`. `sequenced`
//// holds the storage that the server confirmed, with `insertion_order`,
//// because the Gleam `Dict` type is unordered. `pending` holds the optimistic
//// local edits. A pending entry also carries a `message_id` value, so a
//// rollback, which is LIFO, and a resubmit, which keeps the entries that are
//// still relevant, can select one submission.

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
    /// The immutable local identity of this instance: the `create` operation
    /// that this node started with. The kernel never writes it again and never
    /// clears it. Two nodes at the same path are the same instance if, and
    /// only if, their birth values are equal. This field replaces the object
    /// identity of FluidFramework.
    ///
    /// The alias bookkeeping compares a folded pending-create marker with the
    /// sequenced slot. It must compare the birth values. It must not assume
    /// that the slot holds the instance of the marker: an ack that arrives
    /// between the two can commit a *different* instance into the slot while
    /// the marker still holds its own instance.
    birth: CreateInfo,
    /// The client ids that created this live instance. This is the
    /// `clientIds` field upstream.
    creators: List(Int),
    /// Whether a client created this instance while the directory was
    /// detached. This is `clientIds.has("detached")` upstream.
    detached_created: Bool,
    disposed: Bool,
    storage: StorageState,
    /// Server-confirmed child directories.
    subdirs: Dict(String, DirectoryNode),
    /// The insertion order of `subdirs`. A Gleam dict is unordered.
    subdir_order: List(String),
    pending_subdirs: List(PendingSubdir),
  )
}

/// The sequence data that identifies a directory instance and that orders the
/// sibling directories. `seq` is the server sequence number of the create
/// operation. It is `-1` while a local create has no ack, and `0` when a client
/// created the directory while it was detached.
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
  /// One or more consecutive local sets to one key, oldest first. Each set
  /// carries the `message_id` of its submission. A delete or a clear ends the
  /// lifetime. A later set starts a new lifetime.
  PendingLifetime(key: String, sets: List(Json), message_ids: List(Int))
  PendingDelete(key: String, message_id: Int)
  PendingClear(message_id: Int)
}

pub type PendingSubdir {
  /// A local create of `name`. `node` is the optimistic instance of this
  /// create, and it is the one copy of the storage and the children while
  /// `folded` is `False`.
  ///
  /// A concurrent remote create of the same name, or the ack of this create,
  /// moves the instance into the sequenced children. `folded` then becomes
  /// `True`, and `subdirs[name]` becomes the canonical copy. `node` is then a
  /// fallback only. The kernel uses it to insert the instance again if a later
  /// delete removes it before this create receives its ack.
  ///
  /// The instance stays in exactly one canonical place: the marker while the
  /// create is not folded, and `subdirs` after that. That rule prevents a
  /// drift between two copies of the storage. It follows the model of
  /// FluidFramework, which keeps one `SubDirectory` object for each instance,
  /// and where the pending-create entry and the sequenced map hold the *same*
  /// object.
  PendingCreate(
    name: String,
    node: DirectoryNode,
    message_id: Int,
    folded: Bool,
  )
  /// A local delete of `name`. The kernel keeps the sequenced child and hides
  /// it in the optimistic view only. The pending storage on that subtree thus
  /// stays for its acks, and a rollback shows the tree again. This is D13.
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

/// The metadata that a sequenced op carries: the client that wrote it, its
/// server sequence number, the reference sequence number of the author, and its
/// client sequence number. The reference sequence number is what the author had
/// seen at submit time, and the stale-instance filter uses it. The client
/// sequence number breaks a tie in the sibling order.
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

/// Split an absolute path into its segments, and remove the empty ones. `"/"`
/// gives `[]`.
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

/// The most recent pending subdir entry for `name`, if one exists.
fn latest_pending_subdir(
  node: DirectoryNode,
  name: String,
) -> Result(PendingSubdir, Nil) {
  list.reverse(node.pending_subdirs)
  |> list.find(fn(entry) { pending_subdir_name(entry) == name })
}

fn pending_subdir_name(entry: PendingSubdir) -> String {
  case entry {
    PendingCreate(name, _, _, _) -> name
    PendingRemove(name, _) -> name
  }
}

/// The optimistic child with this name. The function puts the pending creates
/// and the pending deletes over the sequenced children. It treats a disposed
/// node as absent, unless `include_disposed` is true.
fn optimistic_child(
  node: DirectoryNode,
  name: String,
  include_disposed: Bool,
) -> Result(DirectoryNode, Nil) {
  let child = case latest_pending_subdir(node, name) {
    // No pending marker: the sequenced child (if any) is the live instance.
    Error(Nil) -> dict.get(node.subdirs, name)
    // Latest op is a not-yet-folded create: its single copy lives in the marker
    // (this is the instance even if an older, being-deleted instance still sits
    // in `subdirs`).
    Ok(PendingCreate(_, pending_child, _, False)) -> Ok(pending_child)
    // Latest op is a folded create: its instance was moved into sequenced
    // children (overwriting any prior instance), and the slot is the canonical
    // copy — but only while the slot still holds *this* instance (matching
    // births). A later delete clears the slot (the instance survives in the
    // marker), and a later ack can commit a *different* instance into it; in
    // both cases the marker node is the pending create's instance, exactly as
    // FF's pending entry keeps referencing its own object. The marker node's
    // `disposed` flag is authoritative — set by the delete's dispose
    // lifecycle, cleared again by an undispose.
    Ok(PendingCreate(_, pending_child, _, True)) ->
      case dict.get(node.subdirs, name) {
        Ok(live) ->
          case live.birth == pending_child.birth {
            True -> Ok(live)
            False -> Ok(pending_child)
          }
        Error(Nil) -> Ok(pending_child)
      }
    // Latest op is a delete: optimistically absent.
    Ok(PendingRemove(_, _)) -> Error(Nil)
  }
  case child {
    Ok(found) if found.disposed && !include_disposed -> Error(Nil)
    other -> other
  }
}

fn sequenced_child(
  node: DirectoryNode,
  name: String,
) -> Result(DirectoryNode, Nil) {
  dict.get(node.subdirs, name)
}

/// Write `child` back to the canonical position of the live instance of `name`.
/// That position is the most recent pending create marker that is not folded
/// yet, or, if there is none, the sequenced children.
fn put_optimistic_child(
  node: DirectoryNode,
  name: String,
  child: DirectoryNode,
) -> DirectoryNode {
  case latest_pending_subdir(node, name) {
    // Not-yet-folded create instance: its single copy lives in the marker.
    Ok(PendingCreate(_, _, _, False)) ->
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
    Ok(PendingCreate(_, _, _, True)) -> {
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
    Ok(PendingRemove(_, _)) | Error(Nil) ->
      put_sequenced_child(node, name, child)
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

/// Mark the most recent pending create for `name` as folded. A concurrent
/// remote create moved its instance into the sequenced children, which are now
/// the canonical copy. The kernel keeps the `node` field of the marker, as a
/// fallback for a later insert.
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

/// Find the optimistic node at `path`, from the root.
pub fn get_working_directory(
  state: DirectoryState,
  path: String,
) -> Result(DirectoryNode, Nil) {
  do_get(state.root, segments(path), optimistic_child_reachable)
}

/// Find the node at `path` in the sequenced data only.
pub fn get_sequenced_directory(
  state: DirectoryState,
  path: String,
) -> Result(DirectoryNode, Nil) {
  do_get(state.root, segments(path), sequenced_child)
}

fn optimistic_child_reachable(
  node: DirectoryNode,
  name: String,
) -> Result(DirectoryNode, Nil) {
  optimistic_child(node, name, False)
}

fn do_get(
  node: DirectoryNode,
  path_segments: List(String),
  child_of: fn(DirectoryNode, String) -> Result(DirectoryNode, Nil),
) -> Result(DirectoryNode, Nil) {
  case path_segments {
    [] -> Ok(node)
    [name, ..rest] ->
      case child_of(node, name) {
        Error(Nil) -> Error(Nil)
        Ok(child) -> do_get(child, rest, child_of)
      }
  }
}

/// Update the optimistic node at `segs`, and return a result value with the
/// new state.
fn update_optimistic(
  node: DirectoryNode,
  path_segments: List(String),
  f: fn(DirectoryNode) -> #(DirectoryNode, a),
) -> Result(#(DirectoryNode, a), Nil) {
  case path_segments {
    [] -> Ok(f(node))
    [name, ..rest] ->
      case optimistic_child(node, name, False) {
        Error(Nil) -> Error(Nil)
        Ok(child) ->
          case update_optimistic(child, rest, f) {
            Ok(#(new_child, updated)) ->
              Ok(#(put_optimistic_child(node, name, new_child), updated))
            Error(Nil) -> Error(Nil)
          }
      }
  }
}

/// Update the sequenced node at `segs`, and return a result value with the new
/// state.
fn update_sequenced(
  node: DirectoryNode,
  path_segments: List(String),
  f: fn(DirectoryNode) -> #(DirectoryNode, a),
) -> Result(#(DirectoryNode, a), Nil) {
  case path_segments {
    [] -> Ok(f(node))
    [name, ..rest] ->
      case sequenced_child(node, name) {
        Error(Nil) -> Error(Nil)
        Ok(child) ->
          case update_sequenced(child, rest, f) {
            Ok(#(new_child, updated)) ->
              Ok(#(put_sequenced_child(node, name, new_child), updated))
            Error(Nil) -> Error(Nil)
          }
      }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Storage reads (per node)
// ─────────────────────────────────────────────────────────────────────────────

fn storage_get(storage: StorageState, key: String) -> Result(Json, Nil) {
  case latest_storage_pending_for(storage.pending, key) {
    Error(Nil) -> dict.get(storage.sequenced, key)
    Ok(PendingLifetime(_, sets, _)) -> list.last(sets)
    Ok(PendingDelete(_, _)) | Ok(PendingClear(_)) -> Error(Nil)
  }
}

fn storage_entries(storage: StorageState) -> List(#(String, Json)) {
  let sequenced_phase =
    list.filter_map(storage.insertion_order, fn(key) {
      case has_storage_delete_or_clear(storage.pending, key) {
        True -> Error(Nil)
        False ->
          storage_get(storage, key)
          |> result.map(fn(value) { #(key, value) })
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
        PendingDelete(_, _) | PendingClear(_) -> Error(Nil)
      }
    })

  list.append(sequenced_phase, pending_phase)
}

// Optimistic reads by path ---------------------------------------------------

pub fn get(
  state: DirectoryState,
  path: String,
  key: String,
) -> Result(Json, Nil) {
  case get_working_directory(state, path) {
    Ok(node) -> storage_get(node.storage, key)
    Error(Nil) -> Error(Nil)
  }
}

pub fn has(state: DirectoryState, path: String, key: String) -> Bool {
  result.is_ok(get(state, path, key))
}

pub fn entries(state: DirectoryState, path: String) -> List(#(String, Json)) {
  case get_working_directory(state, path) {
    Ok(node) -> storage_entries(node.storage)
    Error(Nil) -> []
  }
}

pub fn keys(state: DirectoryState, path: String) -> List(String) {
  entries(state, path) |> list.map(fn(e) { e.0 })
}

pub fn size(state: DirectoryState, path: String) -> Int {
  list.length(entries(state, path))
}

/// The names of the child directories that are visible optimistically at
/// `path`. The function orders them with `seqDataComparator`. An acked
/// directory and a detached directory come before a local one with no ack, and
/// a lower `seq` or `client_seq` value comes first.
pub fn subdirectories(state: DirectoryState, path: String) -> List(String) {
  case get_working_directory(state, path) {
    Error(Nil) -> []
    Ok(node) -> optimistic_subdir_names(node)
  }
}

pub fn has_subdirectory(
  state: DirectoryState,
  path: String,
  name: String,
) -> Bool {
  case get_working_directory(state, path) {
    Error(Nil) -> False
    Ok(node) -> result.is_ok(optimistic_child(node, name, False))
  }
}

pub fn count_subdirectory(state: DirectoryState, path: String) -> Int {
  list.length(subdirectories(state, path))
}

fn optimistic_subdir_names(node: DirectoryNode) -> List(String) {
  let sequenced_names =
    list.filter(node.subdir_order, fn(name) {
      result.is_ok(optimistic_child(node, name, False))
    })
  let pending_names =
    list.filter_map(node.pending_subdirs, fn(entry) {
      let name = pending_subdir_name(entry)
      case dict.has_key(node.subdirs, name) {
        True -> Error(Nil)
        False ->
          case optimistic_child(node, name, False) {
            Ok(_) -> Ok(name)
            Error(Nil) -> Error(Nil)
          }
      }
    })
    |> list.unique
  let all = list.append(sequenced_names, pending_names)
  // Pair each name with its create record before the sort. The pairing keeps
  // the comparison total: a name with no optimistic child cannot reach the
  // comparator.
  all
  |> list.filter_map(fn(name) {
    case optimistic_child(node, name, False) {
      Ok(child) -> Ok(#(name, child.create))
      Error(Nil) -> Error(Nil)
    }
  })
  |> list.sort(fn(a, b) { compare_create_info(a.1, b.1) })
  |> list.map(fn(entry) { entry.0 })
}

fn compare_create_info(a: CreateInfo, b: CreateInfo) -> Order {
  let a_acknowledged = a.seq >= 0
  let b_acknowledged = b.seq >= 0
  case a_acknowledged, b_acknowledged {
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
        [ValueChanged(path, key, option.from_result(previous), True)],
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
        Ok(value) -> [ValueChanged(path, key, Some(value), True)]
        Error(Nil) -> []
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
    Ok(PendingLifetime(_, _, _)) ->
      append_to_latest_lifetime(storage.pending, key, value, message_id)
    Ok(PendingDelete(_, _)) | Ok(PendingClear(_)) | Error(Nil) ->
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
          Ok(existing) -> {
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
          Error(Nil) -> {
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
      Error(Nil) -> #(node, None)
      Ok(previous) -> {
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

/// The dispose events for a subtree. The children come first, from the bottom
/// up, and this node comes last.
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

/// The undispose events for a subtree. This node comes first, from the top
/// down, and the children come after it.
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

/// The names that can alias a child instance from this node. Those names are
/// the sequenced children and the pending-create markers. The
/// `getSubdirectoriesEvenIfDisposed` function of FluidFramework reaches both.
/// A name that a pending remove hides resolves to `Error(Nil)` in
/// `optimistic_child`, and a caller thus skips it, exactly as the iterators of
/// FluidFramework skip it.
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

/// The `undisposeSubdirectoryTree` function of FluidFramework. Clear the
/// disposed flag on this node and on every aliased child that the function
/// reaches, from the bottom up. The function includes a disposed child, because
/// a revive must reach the marker copies that the kernel retained.
fn undispose_tree(
  node: DirectoryNode,
) -> #(DirectoryNode, List(DirectoryEvent)) {
  let #(node, child_events) =
    list.fold(aliased_child_names(node), #(node, []), fn(acc, name) {
      let #(node, events) = acc
      case optimistic_child(node, name, True) {
        Ok(child) -> {
          let #(child, ev) = undispose_tree(child)
          #(put_optimistic_child(node, name, child), list.append(events, ev))
        }
        Error(Nil) -> acc
      }
    })
  #(DirectoryNode(..node, disposed: False), [
    Undisposed(node.path),
    ..child_events
  ])
}

/// The `disposeSubDirectoryTree`, `clearSubDirectorySequencedData`, and
/// `dispose` functions of FluidFramework, together.
///
/// Walk the *optimistic* children from the bottom up. The walk skips a child
/// that a pending remove hides, and a child that is already disposed, the same
/// as the `subdirectories()` iterator of FluidFramework.
///
/// Then reset the instance identity of this node. Set the create seq back to
/// unknown, which is `-1`, and set the creators to the local client only. That
/// client stands for the create op that it has pending, or that it can send
/// later. Then drop the sequenced storage and the sequenced children, and keep
/// every pending value. A node that a marker retained thus carries a new
/// identity when a later create revives it, and it does not keep the identity
/// of the deleted instance.
///
/// The function writes each cleared copy back into its marker slot first, so
/// the retained aliases stay in agreement. FluidFramework changes the shared
/// objects instead.
fn dispose_subdir_tree(node: DirectoryNode, self: Int) -> DirectoryNode {
  let node =
    list.fold(aliased_child_names(node), node, fn(node, name) {
      case optimistic_child(node, name, False) {
        Ok(child) ->
          put_optimistic_child(node, name, dispose_subdir_tree(child, self))
        Error(Nil) -> node
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

/// After a sequenced delete removes the instance of `name` from `subdirs`, keep
/// a folded pending-create marker that points at the cleared node. Do that only
/// when the marker aliases *that* instance, which is true when the birth values
/// are equal. The pending entry of FluidFramework holds the same object.
///
/// A marker for a different instance keeps its own node, and the function does
/// not change it. Such a marker is not folded, or it is folded and an ack that
/// arrived between the two replaced the instance in the slot. To overwrite that
/// marker would destroy the pending data that its instance retained.
fn sync_folded_marker(
  node: DirectoryNode,
  name: String,
  cleared: DirectoryNode,
) -> DirectoryNode {
  case latest_pending_subdir(node, name) {
    Ok(PendingCreate(_, marker_node, _, True)) ->
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
    Ok(PendingCreate(_, _, _, False)) | Ok(PendingRemove(_, _)) | Error(Nil) ->
      node
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

/// Route a remote storage op to the sequenced directory at `path`, and apply
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

/// D12: whether this sequenced message is for the current live instance of
/// `node`. For a remote op, where `target` is `None`, one of three conditions
/// must hold. The author is a creator. Or a client created the instance while
/// the directory was detached. Or the create seq of the instance is known to
/// the other clients, which means it is not `-1`, and it is before the
/// reference sequence number of the op.
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
        PendingDelete(_, _) | PendingLifetime(_, _, _) -> False
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
    Ok(existing) -> {
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
      // parent instance was itself active when this message arrived (FF's re-stamp guard in
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
    Error(Nil) -> {
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
    Error(Nil) -> #(node, [])
    Ok(previous) -> {
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
      PendingCreate(_, _, _, _) -> False
    }
  })
}

// ─────────────────────────────────────────────────────────────────────────────
// Acks (own ops coming back sequenced)
// ─────────────────────────────────────────────────────────────────────────────

/// Commit an acked local op, which moves it from `pending` to `sequenced`. The
/// acks arrive in submission order, which is FIFO. A mismatch is fatal. An ack
/// emits no event, because the optimistic view already showed the op at submit
/// time.
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

/// Commit one acked storage op against the storage of a node.
///
/// The message id of the ack selects the pending entry. That id replaces the
/// object-identity check of FluidFramework on `localOpMetadata`, which is
/// `pendingEntry === localOpMetadata` with the guard `targetSubdir === this`.
///
/// An id that is no longer present means that the pending entry of this op
/// went away with a replaced instance of this path, at a create dedup or at a
/// delete. The ack is thus stale, and the function does nothing and returns
/// `Ok(None)`. To match by key alone would incorrectly consume the pending
/// entry of a *later* op on the current instance.
///
/// An id that is present but out of FIFO position is a true protocol
/// violation.
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
    CreateSubDirectory(_, _) | DeleteSubDirectory(_, _) ->
      Error("non-storage op in ack_storage_node")
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
          Ok(_) -> #(node, Ok(Nil))
          // Not in sequenced children: commit our instance. It was already
          // visible optimistically, so acking it doesn't change the view — it
          // just moves the single copy from the marker into `subdirs`. (This is
          // FF's re-insert of `pendingEntry.subdir` when the sequenced slot is
          // empty — e.g. a create/delete/recreate where an earlier delete
          // cleared the slot.) A disposed instance is revived whole
          // (`undisposeSubdirectoryTree`), and the create seq is stamped only
          // if still unknown and this parent instance was active when this message arrived
          // (FF's re-stamp guard); self is already a creator from submit time.
          Error(Nil) -> {
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
          Error(Nil) -> #(node, Ok(Nil))
          Ok(previous) -> {
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

/// Remove the pending create for `name` that carries `message_id`. Return its
/// node, and whether the kernel had folded that node into the sequenced
/// children.
fn take_pending_create_by_id(
  pending: List(PendingSubdir),
  name: String,
  message_id: Int,
) -> Result(#(#(DirectoryNode, Bool), List(PendingSubdir)), Nil) {
  do_take_pending(pending, [], fn(e) {
    case e {
      PendingCreate(n, node, id, folded) if n == name && id == message_id ->
        Some(#(node, folded))
      PendingCreate(_, _, _, _) -> None
      PendingRemove(_, _) -> None
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

/// The highest pending message id in the whole tree. That id belongs to the op
/// that the client submitted last, which is the op that a LIFO rollback
/// removes.
pub fn last_pending_message_id(state: DirectoryState) -> Result(Int, Nil) {
  case node_pending_ids(state.root) {
    [] -> Error(Nil)
    message_ids -> Ok(list.fold(message_ids, -1, int.max))
  }
}

/// The pending storage message ids on one node. The function does not
/// recurse.
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

fn rollback_set(
  state: DirectoryState,
  op: DirectoryOp,
  path: String,
  key: String,
  message_id: Int,
) -> Result(#(DirectoryState, List(DirectoryEvent)), KernelError) {
  rollback_storage(state, op, path, fn(node) {
    let storage_state = node.storage
    case remove_last_lifetime_set(storage_state.pending, key, message_id) {
      Error(_) -> Error("no pending set for key " <> key)
      Ok(#(pending, _restored_value)) -> {
        let storage = StorageState(..storage_state, pending: pending)
        // Compensating event: value reverts to the prior optimistic value.
        let node = DirectoryNode(..node, storage: storage)
        let previous = storage_get(storage, key)
        Ok(
          #(node, [ValueChanged(path, key, option.from_result(previous), True)]),
        )
      }
    }
  })
}

fn rollback_delete(
  state: DirectoryState,
  op: DirectoryOp,
  path: String,
  key: String,
  message_id: Int,
) -> Result(#(DirectoryState, List(DirectoryEvent)), KernelError) {
  rollback_storage(state, op, path, fn(node) {
    let storage_state = node.storage
    case
      remove_pending_entry(
        storage_state.pending,
        PendingDelete(key, message_id),
      )
    {
      Error(_) -> Error("no pending delete for key " <> key)
      Ok(pending) -> {
        let storage = StorageState(..storage_state, pending: pending)
        let node = DirectoryNode(..node, storage: storage)
        let events = case storage_get(storage, key) {
          Ok(restored) -> [ValueChanged(path, key, Some(restored), True)]
          Error(Nil) -> []
        }
        Ok(#(node, events))
      }
    }
  })
}

fn rollback_clear(
  state: DirectoryState,
  op: DirectoryOp,
  path: String,
  message_id: Int,
) -> Result(#(DirectoryState, List(DirectoryEvent)), KernelError) {
  rollback_storage(state, op, path, fn(node) {
    let storage_state = node.storage
    case remove_pending_entry(storage_state.pending, PendingClear(message_id)) {
      Error(_) -> Error("no pending clear")
      Ok(pending) -> {
        let storage = StorageState(..storage_state, pending: pending)
        let node = DirectoryNode(..node, storage: storage)
        Ok(#(node, []))
      }
    }
  })
}

fn rollback_create(
  state: DirectoryState,
  op: DirectoryOp,
  path: String,
  name: String,
  message_id: Int,
) -> Result(#(DirectoryState, List(DirectoryEvent)), KernelError) {
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

fn rollback_remove(
  state: DirectoryState,
  op: DirectoryOp,
  path: String,
  name: String,
  message_id: Int,
) -> Result(#(DirectoryState, List(DirectoryEvent)), KernelError) {
  let child_path = join(path, name)
  let mutate = fn(node: DirectoryNode) {
    case remove_pending_subdir(node.pending_subdirs, name, message_id, False) {
      Error(_) -> #(node, Error("no pending delete for " <> name))
      Ok(pending) -> {
        let node = DirectoryNode(..node, pending_subdirs: pending)
        // The retained child is re-exposed now that the pending delete is gone.
        let undispose = case optimistic_child(node, name, False) {
          Ok(child) -> undispose_events_only(child)
          Error(Nil) -> [Undisposed(child_path)]
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

/// The routing of the `reSubmitCore` function of FluidFramework, which is D14.
/// Decide whether the pending op behind `op` and `message_id` is still worth a
/// resubmit, and apply the state effects that FluidFramework applies at
/// resubmit time.
///
/// The function finds each target on the *retained instance*. The traversal
/// includes a disposed marker alias, because the `localOpMetadata` value of
/// FluidFramework holds the object itself, and not a path. The function then
/// checks `!targetSubdir.disposed`, and it checks the pending entry, the same
/// as `resubmitKeyMessage` and `resubmitSubDirectoryMessage`.
///
/// A resubmit of a create records the current client id as a creator, and it
/// undisposes the retained pending tree. A storage op that is *after* that
/// create in the same reconnect batch thus finds its target alive, and it
/// resubmits too. To drop such an op while its pending entry stays on the
/// retained node would leave a pending entry that never receives an ack, and
/// that only this client can see.
///
/// When the function DOES drop an op, it also removes the pending entry of
/// that op from the retained instance. See `strip_dropped_pending`. This is one
/// deliberate difference from FluidFramework, which keeps the entry on the
/// disposed object. That op will never sequence. If a later create ack revives
/// the retained instance, the entry that remains appears as an optimistic edit
/// that no other client sees. To drop the op and its pending entry together
/// thus keeps the revive convergent.
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
              PendingRemove(_, _) -> False
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
              Error(Nil) -> Error(Nil)
              Ok(#(marker_node, folded)) -> {
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
              PendingCreate(_, _, _, _) -> False
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

/// Remove the pending entry behind a dropped resubmit, from the position at
/// which it still exists. The function searches *every* retained instance, and
/// it includes the disposed ones, because the drop usually happened because
/// the instance is disposed. The op of that entry will never sequence. To keep
/// the entry would let a later revive of the retained instance show an
/// optimistic edit that no other client sees.
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

/// Remove the one pending storage entry that carries `message_id`. That entry
/// is one set inside a lifetime, and the function removes the lifetime when it
/// becomes empty. Or that entry is the matching delete or clear.
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

/// The most recent pending create entry for `name`, and the function skips a
/// later pending remove. FluidFramework uses `findLast` in
/// `resubmitSubDirectoryMessage`.
fn find_latest_pending_create(
  pending: List(PendingSubdir),
  name: String,
) -> Result(#(DirectoryNode, Bool), Nil) {
  list.reverse(pending)
  |> list.find_map(fn(entry) {
    case entry {
      PendingCreate(n, node, _, folded) if n == name -> Ok(#(node, folded))
      PendingCreate(_, _, _, _) -> Error(Nil)
      PendingRemove(_, _) -> Error(Nil)
    }
  })
}

/// Whether the pending storage of this node still holds the pending entry of
/// `op`. This is the check in `resubmitKeyMessage` and `resubmitClearMessage`
/// of FluidFramework. A set checks the identity of the submission, which is
/// `keySets.includes(localOpMetadata)` in FluidFramework and the message id
/// here. A delete and a clear match by their kind, and by their key, only.
fn storage_pending_matches(
  pending: List(PendingStorage),
  op: DirectoryOp,
  message_id: Int,
) -> Bool {
  list.any(pending, fn(entry) {
    case op {
      Set(_, key, _) ->
        case entry {
          PendingLifetime(k, _, ids) ->
            k == key && list.contains(ids, message_id)
          PendingDelete(_, _) | PendingClear(_) -> False
        }
      Delete(_, key) ->
        case entry {
          PendingDelete(k, _) -> k == key
          PendingLifetime(_, _, _) | PendingClear(_) -> False
        }
      Clear(_) ->
        case entry {
          PendingClear(_) -> True
          PendingLifetime(_, _, _) | PendingDelete(_, _) -> False
        }
      CreateSubDirectory(_, _) | DeleteSubDirectory(_, _) -> False
    }
  })
}

/// Every retained instance that can answer to `name` under `node`, newest
/// lifecycle first, with the slot that it canonically lives in. Unlike
/// `optimistic_child`, this function also returns an instance that a later
/// pending entry *hides*, for example an old sequenced instance under a pending
/// remove and a pending create. The `localOpMetadata` value of FluidFramework
/// holds a direct object reference, and a lookup by path cannot reproduce that
/// reference. A resubmit must find the exact instance whose pending entry it is
/// deciding about.
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
        PendingCreate(_, _, _, _) -> Error(Nil)
        PendingRemove(_, _) -> Error(Nil)
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

/// Write `child` back into the slot that the candidate came from. A write to a
/// sequenced slot also updates a folded marker that aliases that instance,
/// which follows the shared object of FluidFramework. This function is the
/// counterpart of `put_optimistic_child`.
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

/// A depth-first search and update over the retained instances. At each path
/// segment the function tries every candidate instance (see
/// `candidate_children`), until the target of one subtree satisfies `f`. It
/// then writes the new nodes back along that branch. `f` returns `Error(Nil)`
/// to say "this is not the instance". The whole traversal thus replaces the
/// step in FluidFramework that follows the metadata object reference to the
/// position of the pending entry.
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
) -> Result(PendingStorage, Nil) {
  list.reverse(pending)
  |> list.find(fn(entry) { storage_matches_key(entry, key) })
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
      PendingDelete(_, _) -> acc
      PendingLifetime(_, _, _) -> acc
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

/// Remove the most recent set that carries `message_id`, from the newest
/// lifetime of `key`.
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
        PendingCreate(_, _, _, _), False -> False
        PendingRemove(_, _), True -> False
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
            PendingCreate(_, _, _, _), False | PendingRemove(_, _), True -> True
          }
        }),
      )
  }
}
