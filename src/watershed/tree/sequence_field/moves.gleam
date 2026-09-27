//// Shared range effects and ownership notifications for sequence moves.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import watershed/fluid_ids.{type StableId}
import watershed/tree/sequence_field
import watershed/tree/types.{
  type AtomId, type TreeError, AtomId, CorruptData, UnsupportedFeature,
}

pub fn invalidated(context: Context) -> List(FieldId) {
  list.reverse(context.invalidated)
}

const max_safe_integer = 9_007_199_254_740_991

pub type Side {
  Source
  Destination
}

pub type Key {
  Key(side: Side, revision: Option(StableId), local_id: Int)
}

pub type FieldId {
  FieldId(parent: Option(AtomId), field: String)
}

pub type Effect {
  MoveEffect(
    modify_after: Option(AtomId),
    moved_effect: Option(sequence_field.Detach),
    rebased_child: Option(AtomId),
    endpoint: Option(AtomId),
    truncated_endpoint: Option(AtomId),
    truncated_endpoint_for_inner: Option(AtomId),
  )
  InvertedChild(child: AtomId)
}

pub type Query {
  Query(count: Int, effect: Option(Effect))
}

pub type Notification {
  NodeMoved(node: AtomId, field: FieldId)
  KeyMoved(key: Key, count: Int, field: FieldId)
}

pub type TraceEvent {
  HandlerCalled(operation: String, field: FieldId)
  RangeRead(
    field: FieldId,
    key: Key,
    count: Int,
    add_dependency: Bool,
    found: Bool,
    returned_length: Int,
  )
  RangeWritten(field: FieldId, key: Key, count: Int, invalidate: Bool)
  MoveInNotified(field: FieldId, node: AtomId)
  KeyMoveNotified(field: FieldId, key: Key, count: Int)
}

type Entry {
  Entry(key: Key, count: Int, effect: Effect)
}

type Dependency {
  Dependency(key: Key, count: Int, field: FieldId)
}

pub opaque type Context {
  Context(
    entries: List(Entry),
    dependencies: List(Dependency),
    invalidated: List(FieldId),
    notifications: List(Notification),
    active_field: Option(FieldId),
    trace: List(TraceEvent),
  )
}

pub fn new() -> Context {
  Context([], [], [], [], None, [])
}

pub fn enter_field(
  context: Context,
  operation: String,
  field: FieldId,
) -> Context {
  Context(..context, active_field: Some(field), trace: [
    HandlerCalled(operation, field),
    ..context.trace
  ])
}

pub fn trace(context: Context) -> List(TraceEvent) {
  list.reverse(context.trace)
}

pub fn same_work_state(first: Context, second: Context) -> Bool {
  first.entries == second.entries
  && first.dependencies == second.dependencies
  && first.invalidated == second.invalidated
  && first.notifications == second.notifications
}

pub fn get(
  context: Context,
  key: Key,
  count: Int,
  dependent: Option(FieldId),
) -> Result(#(Query, Context), TreeError) {
  use _ <- result.try(validate_range(key, count))
  let Context(
    entries,
    dependencies,
    invalidated,
    notifications,
    active_field,
    trace,
  ) = context
  let query = query(entries, key, count)
  let dependencies = case dependent {
    None -> dependencies
    Some(field) -> put_dependency(dependencies, Dependency(key, count, field))
  }
  let trace = case active_field {
    None -> trace
    Some(field) -> [
      RangeRead(
        field,
        key,
        count,
        dependent != None,
        query.effect != None,
        query.count,
      ),
      ..trace
    ]
  }
  Ok(#(
    query,
    Context(
      entries,
      dependencies,
      invalidated,
      notifications,
      active_field,
      trace,
    ),
  ))
}

pub fn set(
  context: Context,
  key: Key,
  count: Int,
  effect: Effect,
) -> Result(Context, TreeError) {
  use _ <- result.try(validate_range(key, count))
  use _ <- result.try(validate_effect(effect, count))
  let Context(
    entries,
    dependencies,
    invalidated,
    notifications,
    active_field,
    trace,
  ) = context
  let unchanged = range_matches(entries, key, count, effect)
  let entries = replace_range(entries, key, count, effect)
  let invalidated = case unchanged {
    True -> invalidated
    False ->
      list.fold(dependencies, invalidated, fn(found, dependency) {
        case ranges_overlap(key, count, dependency.key, dependency.count) {
          True -> put_unique(found, dependency.field)
          False -> found
        }
      })
  }
  let trace = case active_field {
    None -> trace
    Some(field) -> [RangeWritten(field, key, count, True), ..trace]
  }
  Ok(Context(
    entries,
    dependencies,
    invalidated,
    notifications,
    active_field,
    trace,
  ))
}

pub fn take_invalidated(context: Context) -> #(List(FieldId), Context) {
  let Context(entries, _, invalidated, notifications, active_field, trace) =
    context
  #(
    list.reverse(invalidated),
    Context(entries, [], [], notifications, active_field, trace),
  )
}

pub fn take_invalidated_for(
  context: Context,
  field: FieldId,
) -> #(Bool, Context) {
  let Context(
    entries,
    dependencies,
    invalidated,
    notifications,
    active_field,
    trace,
  ) = context
  #(
    list.contains(invalidated, field),
    Context(
      entries,
      list.filter(dependencies, fn(dependency) { dependency.field != field }),
      list.filter(invalidated, fn(invalidated_field) {
        invalidated_field != field
      }),
      notifications,
      active_field,
      trace,
    ),
  )
}

pub fn on_move_in(
  context: Context,
  node: AtomId,
  field: FieldId,
) -> Result(Context, TreeError) {
  use _ <- result.try(validate_atom(node, 1))
  let Context(
    entries,
    dependencies,
    invalidated,
    notifications,
    active_field,
    trace,
  ) = context
  let notification = NodeMoved(node, field)
  Ok(
    Context(
      entries,
      dependencies,
      invalidated,
      put_unique(notifications, notification),
      active_field,
      [MoveInNotified(field, node), ..trace],
    ),
  )
}

pub fn move_key(
  context: Context,
  key: Key,
  count: Int,
  field: FieldId,
) -> Result(Context, TreeError) {
  use _ <- result.try(validate_range(key, count))
  let Context(
    entries,
    dependencies,
    invalidated,
    notifications,
    active_field,
    trace,
  ) = context
  let notification = KeyMoved(key, count, field)
  Ok(
    Context(
      entries,
      dependencies,
      invalidated,
      put_unique(notifications, notification),
      active_field,
      [KeyMoveNotified(field, key, count), ..trace],
    ),
  )
}

pub fn compose_move_key(
  _context: Context,
  _key: Key,
  _count: Int,
  _field: FieldId,
) -> Result(Context, TreeError) {
  Error(UnsupportedFeature("sequence_field.compose", "key relocation"))
}

pub fn notifications(context: Context) -> List(Notification) {
  list.reverse(context.notifications)
}

fn query(entries: List(Entry), key: Key, count: Int) -> Query {
  case containing_entry(entries, key) {
    Some(Entry(entry_key, entry_count, effect)) -> {
      let shift = key.local_id - entry_key.local_id
      Query(
        int.min(count, entry_count - shift),
        Some(offset_effect(effect, shift)),
      )
    }
    None -> Query(first_absent_count(entries, key, count), None)
  }
}

fn containing_entry(entries: List(Entry), key: Key) -> Option(Entry) {
  case entries {
    [] -> None
    [entry, ..rest] ->
      case contains(entry, key) {
        True -> Some(entry)
        False -> containing_entry(rest, key)
      }
  }
}

fn contains(entry: Entry, key: Key) -> Bool {
  same_range(entry.key, key)
  && key.local_id >= entry.key.local_id
  && key.local_id < entry.key.local_id + entry.count
}

fn first_absent_count(entries: List(Entry), key: Key, count: Int) -> Int {
  let next =
    list.fold(entries, count, fn(current, entry) {
      case
        same_range(entry.key, key)
        && entry.key.local_id > key.local_id
        && entry.key.local_id - key.local_id < current
      {
        True -> entry.key.local_id - key.local_id
        False -> current
      }
    })
  int.max(1, next)
}

fn range_matches(
  entries: List(Entry),
  key: Key,
  count: Int,
  effect: Effect,
) -> Bool {
  range_matches_loop(entries, key, count, effect, 0)
}

fn range_matches_loop(
  entries: List(Entry),
  key: Key,
  remaining: Int,
  effect: Effect,
  offset: Int,
) -> Bool {
  case remaining {
    0 -> True
    _ -> {
      let current = Key(..key, local_id: key.local_id + offset)
      let Query(length, found) = query(entries, current, remaining)
      case found == Some(offset_effect(effect, offset)) {
        False -> False
        True ->
          range_matches_loop(
            entries,
            key,
            remaining - length,
            effect,
            offset + length,
          )
      }
    }
  }
}

fn replace_range(
  entries: List(Entry),
  key: Key,
  count: Int,
  effect: Effect,
) -> List(Entry) {
  let end = key.local_id + count
  let retained =
    list.flat_map(entries, fn(entry) {
      case same_range(entry.key, key) {
        False -> [entry]
        True -> {
          let entry_end = entry.key.local_id + entry.count
          case entry_end <= key.local_id || entry.key.local_id >= end {
            True -> [entry]
            False -> {
              let prefix = case entry.key.local_id < key.local_id {
                True -> [
                  Entry(
                    entry.key,
                    key.local_id - entry.key.local_id,
                    entry.effect,
                  ),
                ]
                False -> []
              }
              let suffix = case entry_end > end {
                True -> [
                  Entry(
                    Key(..entry.key, local_id: end),
                    entry_end - end,
                    offset_effect(entry.effect, end - entry.key.local_id),
                  ),
                ]
                False -> []
              }
              list.append(prefix, suffix)
            }
          }
        }
      }
    })
  [Entry(key, count, effect), ..retained]
}

fn ranges_overlap(
  first: Key,
  first_count: Int,
  second: Key,
  second_count: Int,
) -> Bool {
  same_range(first, second)
  && first.local_id < second.local_id + second_count
  && second.local_id < first.local_id + first_count
}

fn same_range(first: Key, second: Key) -> Bool {
  first.side == second.side && first.revision == second.revision
}

fn put_dependency(
  dependencies: List(Dependency),
  dependency: Dependency,
) -> List(Dependency) {
  put_unique(dependencies, dependency)
}

fn put_unique(values: List(a), value: a) -> List(a) {
  case list.contains(values, value) {
    True -> values
    False -> [value, ..values]
  }
}

fn offset_effect(effect: Effect, amount: Int) -> Effect {
  case effect, amount {
    _, 0 -> effect
    InvertedChild(_), _ -> effect
    MoveEffect(
      modify_after,
      moved_effect,
      rebased_child,
      endpoint,
      truncated_endpoint,
      truncated_endpoint_for_inner,
    ),
      _
    ->
      MoveEffect(
        modify_after:,
        moved_effect: option.map(moved_effect, sequence_field.offset_detach(
          _,
          amount,
        )),
        rebased_child:,
        endpoint: option.map(endpoint, offset_atom(_, amount)),
        truncated_endpoint: option.map(truncated_endpoint, offset_atom(
          _,
          amount,
        )),
        truncated_endpoint_for_inner: option.map(
          truncated_endpoint_for_inner,
          offset_atom(_, amount),
        ),
      )
  }
}

fn validate_effect(effect: Effect, count: Int) -> Result(Nil, TreeError) {
  case effect {
    InvertedChild(child) -> validate_atom(child, 1)
    MoveEffect(
      modify_after,
      moved_effect,
      rebased_child,
      endpoint,
      truncated_endpoint,
      truncated_endpoint_for_inner,
    ) -> {
      use _ <- result.try(validate_optional_atom(modify_after, 1))
      use _ <- result.try(validate_optional_atom(rebased_child, 1))
      use _ <- result.try(validate_optional_atom(endpoint, count))
      use _ <- result.try(validate_optional_atom(truncated_endpoint, count))
      use _ <- result.try(validate_optional_atom(
        truncated_endpoint_for_inner,
        count,
      ))
      case moved_effect {
        None -> Ok(Nil)
        Some(detach) -> sequence_field.validate_detach_range(detach, count)
      }
    }
  }
}

fn validate_range(key: Key, count: Int) -> Result(Nil, TreeError) {
  validate_atom(AtomId(key.revision, key.local_id), count)
}

fn validate_optional_atom(
  id: Option(AtomId),
  count: Int,
) -> Result(Nil, TreeError) {
  case id {
    None -> Ok(Nil)
    Some(id) -> validate_atom(id, count)
  }
}

fn validate_atom(id: AtomId, count: Int) -> Result(Nil, TreeError) {
  case
    count > 0
    && count <= max_safe_integer
    && id.local_id >= 0
    && id.local_id <= max_safe_integer
    && count - 1 <= max_safe_integer - id.local_id
  {
    True -> Ok(Nil)
    False ->
      Error(CorruptData(
        "sequence move effects",
        "range is outside the safe integer range",
      ))
  }
}

fn offset_atom(id: AtomId, amount: Int) -> AtomId {
  AtomId(..id, local_id: id.local_id + amount)
}
