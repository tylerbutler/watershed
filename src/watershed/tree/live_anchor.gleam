//// Checkout-scoped node anchors and explicit identity transitions.

import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import watershed/tree/branch
import watershed/tree/error as tree_error
import watershed/tree/forest
import watershed/tree/live_types as live
import watershed/tree/types

type Entry {
  Entry(
    reference: forest.NodeRef,
    tombstone: Option(tree_error.ReferenceStatus),
    preview: Bool,
  )
}

pub opaque type Registry {
  Registry(
    views: Dict(live.ViewToken, Nil),
    entries: Dict(live.AnchorToken, Entry),
    next_view: Int,
    next_anchor: Int,
  )
}

pub fn new() -> Registry {
  Registry(dict.new(), dict.new(), 0, 0)
}

pub fn open(
  registry: Registry,
  origin: branch.Origin,
  checkout: types.CheckoutSelector,
) -> #(Registry, live.ViewToken) {
  let token = live.view_token(origin, checkout, registry.next_view)
  #(
    Registry(
      ..registry,
      views: dict.insert(registry.views, token, Nil),
      next_view: registry.next_view + 1,
    ),
    token,
  )
}

pub fn close(registry: Registry, view: live.ViewToken) -> Registry {
  Registry(
    ..registry,
    views: dict.delete(registry.views, view),
    entries: dict.filter(registry.entries, fn(token, _) {
      live.anchor_view(token) != view
    }),
  )
}

pub fn acquire(
  registry: Registry,
  view: live.ViewToken,
  reference: forest.NodeRef,
) -> Result(#(Registry, live.AnchorToken), tree_error.Error) {
  use _ <- result.try(require_view(registry, view))
  case
    list.find(dict.to_list(registry.entries), fn(entry) {
      live.anchor_view(entry.0) == view
      && entry.1.reference == reference
      && entry.1.tombstone == None
    })
  {
    Ok(entry) -> Ok(#(registry, entry.0))
    Error(Nil) -> {
      let token = live.anchor_token(view, registry.next_anchor)
      Ok(#(
        Registry(
          ..registry,
          entries: dict.insert(
            registry.entries,
            token,
            Entry(reference, None, False),
          ),
          next_anchor: registry.next_anchor + 1,
        ),
        token,
      ))
    }
  }
}

@internal
pub fn mark_preview(
  registry: Registry,
  token: live.AnchorToken,
) -> Result(Registry, tree_error.Error) {
  use _ <- result.try(require_view(registry, live.anchor_view(token)))
  use entry <- result.try(
    dict.get(registry.entries, token)
    |> result.map_error(fn(_) {
      tree_error.InvalidReference(tree_error.Invalidated)
    }),
  )
  Ok(
    Registry(
      ..registry,
      entries: dict.insert(
        registry.entries,
        token,
        Entry(..entry, preview: True),
      ),
    ),
  )
}

@internal
pub fn finish_preview(
  registry: Registry,
  origin: branch.Origin,
  checkout: types.CheckoutSelector,
  visible: forest.Forest,
  complete: Bool,
) -> Result(Registry, tree_error.Error) {
  use entries <- result.try(
    dict.to_list(registry.entries)
    |> list.try_map(fn(pair) {
      let #(token, entry) = pair
      case
        live.view_matches(live.anchor_view(token), origin, checkout)
        && entry.preview
        && entry.tombstone == None
      {
        False -> Ok(pair)
        True -> {
          use status <- result.try(
            forest.reference_status(visible, entry.reference)
            |> result.map_error(tree_error.InvalidValue),
          )
          case status {
            forest.DeletedNode ->
              Ok(#(
                token,
                Entry(
                  ..entry,
                  tombstone: Some(tree_error.Invalidated),
                  preview: False,
                ),
              ))
            forest.ForeignNode -> Error(tree_error.ForeignOrigin)
            forest.AttachedNode | forest.RemovedNode ->
              Ok(#(token, Entry(..entry, preview: !complete)))
          }
        }
      }
    }),
  )
  Ok(Registry(..registry, entries: dict.from_list(entries)))
}

fn require_view(
  registry: Registry,
  view: live.ViewToken,
) -> Result(Nil, tree_error.Error) {
  dict.get(registry.views, view)
  |> result.map_error(fn(_) { tree_error.ClosedTree })
}

fn entry(
  registry: Registry,
  origin: branch.Origin,
  checkout: types.CheckoutSelector,
  token: live.AnchorToken,
) -> Result(Entry, tree_error.Error) {
  let view = live.anchor_view(token)
  use _ <- result.try(case live.view_matches(view, origin, checkout) {
    True -> Ok(Nil)
    False -> Error(tree_error.ForeignOrigin)
  })
  use _ <- result.try(require_view(registry, view))
  dict.get(registry.entries, token)
  |> result.map_error(fn(_) {
    tree_error.InvalidReference(tree_error.Invalidated)
  })
}

pub fn status(
  registry: Registry,
  origin: branch.Origin,
  checkout: types.CheckoutSelector,
  token: live.AnchorToken,
  forest: forest.Forest,
) -> Result(tree_error.ReferenceStatus, tree_error.Error) {
  use entry <- result.try(entry(registry, origin, checkout, token))
  case entry.tombstone {
    Some(status) -> Ok(status)
    None -> {
      use status <- result.try(
        forest.reference_status(forest, entry.reference)
        |> result.map_error(tree_error.InvalidValue),
      )
      case status {
        forest.AttachedNode -> Ok(tree_error.Attached)
        forest.RemovedNode -> Ok(tree_error.Removed)
        forest.DeletedNode -> Ok(tree_error.Deleted)
        forest.ForeignNode -> Error(tree_error.ForeignOrigin)
      }
    }
  }
}

pub fn resolve(
  registry: Registry,
  origin: branch.Origin,
  checkout: types.CheckoutSelector,
  token: live.AnchorToken,
  forest: forest.Forest,
) -> Result(forest.NodeRef, tree_error.Error) {
  use status <- result.try(status(registry, origin, checkout, token, forest))
  case status {
    tree_error.Attached ->
      entry(registry, origin, checkout, token)
      |> result.map(fn(e) { e.reference })
    _ -> Error(tree_error.InvalidReference(status))
  }
}

pub fn apply_changes(
  registry: Registry,
  origin: branch.Origin,
  checkout: types.CheckoutSelector,
  changes: List(live.IdentityChange),
) -> Result(Registry, tree_error.Error) {
  use _ <- result.try(
    list.try_each(changes, fn(change) {
      let occupied = case change {
        live.Promote(before, after) if before != after ->
          list.any(dict.to_list(registry.entries), fn(pair) {
            live.view_matches(live.anchor_view(pair.0), origin, checkout)
            && pair.1.tombstone == None
            && pair.1.reference == after
            && !list.any(changes, fn(other) {
              source(other) == after && other != live.Promote(after, after)
            })
          })
        _ -> False
      }
      case
        occupied || list.any(changes, fn(other) { conflicting(change, other) })
      {
        False -> Ok(Nil)
        True ->
          Error(tree_error.RuntimeFailure(
            "Conflicting node identity transitions",
          ))
      }
    }),
  )
  let entries =
    registry.entries
    |> dict.to_list
    |> list.map(fn(pair) {
      let #(token, entry) = pair
      case
        live.view_matches(live.anchor_view(token), origin, checkout),
        entry.tombstone
      {
        True, None ->
          case
            list.find(changes, fn(change) { source(change) == entry.reference })
          {
            Error(Nil) -> pair
            Ok(live.Promote(_, after)) -> #(
              token,
              Entry(..entry, reference: after),
            )
            Ok(live.Discard(_)) -> #(
              token,
              Entry(
                ..entry,
                tombstone: Some(tree_error.Invalidated),
                preview: False,
              ),
            )
            Ok(live.Forget(_)) -> #(
              token,
              Entry(
                ..entry,
                tombstone: Some(tree_error.Deleted),
                preview: False,
              ),
            )
          }
        _, _ -> pair
      }
    })
    |> dict.from_list
  Ok(Registry(..registry, entries:))
}

fn source(change: live.IdentityChange) -> forest.NodeRef {
  case change {
    live.Promote(before, _) -> before
    live.Discard(reference) | live.Forget(reference) -> reference
  }
}

fn conflicting(
  first: live.IdentityChange,
  second: live.IdentityChange,
) -> Bool {
  case source(first) == source(second) && first != second {
    True -> True
    False ->
      case first, second {
        live.Promote(before, after), live.Promote(other_before, other_after) ->
          after == other_after && before != other_before
        _, _ -> False
      }
  }
}
