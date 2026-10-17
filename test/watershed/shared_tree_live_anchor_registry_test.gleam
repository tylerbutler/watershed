import gleam/list
import gleam/option.{None, Some}
import startest/expect
import watershed/fluid_ids
import watershed/tree/branch
import watershed/tree/change
import watershed/tree/forest
import watershed/tree/identifier_fixture
import watershed/tree/live_anchor as anchors
import watershed/tree/error as tree_error
import watershed/tree/live_types as live
import watershed/tree/types

fn origin() -> branch.Origin {
  branch.origin("runtime", "document", "tree")
}

fn content() -> forest.Forest {
  let assert Ok(view_id) =
    fluid_ids.stable_id("30000000-0000-4000-8000-000000000001")
  let assert Ok(forest) =
    forest.new(
      view_id,
      identifier_fixture.full_stored(),
      Some(
        identifier_fixture.full_root(
          identifier_fixture.point("featured", "featured"),
          [
            identifier_fixture.point("duplicate", "same"),
            identifier_fixture.point("duplicate", "same"),
          ],
          [],
          [],
        ),
      ),
    )
  forest
}

pub fn live_anchor_registry_interns_by_identity_test() {
  let forest = content()
  let assert Ok(first) = forest.locate(forest, ["left", "0"])
  let assert Ok(second) = forest.locate(forest, ["left", "1"])
  let #(registry, view) =
    anchors.open(anchors.new(), origin(), types.DocumentCheckout)
  let assert Ok(#(registry, first_token)) =
    anchors.acquire(registry, view, first)
  let assert Ok(#(registry, repeated)) = anchors.acquire(registry, view, first)
  repeated |> expect.to_equal(first_token)
  let assert Ok(#(registry, second_token)) =
    anchors.acquire(registry, view, second)
  second_token |> expect.to_not_equal(first_token)
  anchors.resolve(
    registry,
    origin(),
    types.DocumentCheckout,
    second_token,
    forest,
  )
  |> expect.to_equal(Ok(second))
  anchors.status(
    registry,
    origin(),
    types.DocumentCheckout,
    second_token,
    forest,
  )
  |> expect.to_equal(Ok(tree_error.Attached))
}

pub fn live_anchor_registry_ownership_and_close_test() {
  let forest = content()
  let assert Ok(reference) = forest.locate(forest, ["left", "0"])
  let #(registry, view) =
    anchors.open(anchors.new(), origin(), types.DocumentCheckout)
  let assert Ok(#(registry, token)) = anchors.acquire(registry, view, reference)
  let foreign = branch.origin("other-runtime", "document", "tree")
  anchors.resolve(registry, foreign, types.DocumentCheckout, token, forest)
  |> expect.to_equal(Error(tree_error.ForeignOrigin))
  anchors.resolve(
    registry,
    origin(),
    types.LocalCheckout(types.LocalCheckoutId(1)),
    token,
    forest,
  )
  |> expect.to_equal(Error(tree_error.ForeignOrigin))
  let #(registry, other_view) =
    anchors.open(registry, origin(), types.DocumentCheckout)
  let assert Ok(#(registry, other_token)) =
    anchors.acquire(registry, other_view, reference)
  token |> expect.to_not_equal(other_token)
  let closed = anchors.close(registry, view)
  anchors.close(closed, view) |> expect.to_equal(closed)
  anchors.acquire(closed, view, reference)
  |> expect.to_equal(Error(tree_error.ClosedTree))
  anchors.status(closed, origin(), types.DocumentCheckout, token, forest)
  |> expect.to_equal(Error(tree_error.ClosedTree))
  anchors.resolve(closed, origin(), types.DocumentCheckout, other_token, forest)
  |> expect.to_equal(Ok(reference))
}

pub fn live_anchor_registry_explicit_promotion_test() {
  let forest = content()
  let assert Ok(before) = forest.locate(forest, ["left", "0"])
  let assert Ok(after) = forest.locate(forest, ["left", "1"])
  let #(registry, view) =
    anchors.open(anchors.new(), origin(), types.DocumentCheckout)
  let assert Ok(#(registry, token)) = anchors.acquire(registry, view, before)
  let assert Ok(registry) =
    anchors.apply_changes(registry, origin(), types.DocumentCheckout, [
      live.Promote(before, after),
    ])
  anchors.resolve(registry, origin(), types.DocumentCheckout, token, forest)
  |> expect.to_equal(Ok(after))
  let assert Ok(#(_, repeated)) = anchors.acquire(registry, view, after)
  repeated |> expect.to_equal(token)
}

pub fn live_anchor_registry_tombstones_and_conflicts_test() {
  let forest = content()
  let assert Ok(first) = forest.locate(forest, ["left", "0"])
  let assert Ok(second) = forest.locate(forest, ["left", "1"])
  let assert Ok(third) = forest.locate(forest, ["child"])
  let #(registry, view) =
    anchors.open(anchors.new(), origin(), types.DocumentCheckout)
  let assert Ok(#(registry, token)) = anchors.acquire(registry, view, first)
  [
    #(live.Discard(first), tree_error.Invalidated),
    #(live.Forget(first), tree_error.Deleted),
  ]
  |> list.each(fn(pair) {
    let assert Ok(changed) =
      anchors.apply_changes(registry, origin(), types.DocumentCheckout, [pair.0])
    anchors.status(changed, origin(), types.DocumentCheckout, token, forest)
    |> expect.to_equal(Ok(pair.1))
    anchors.resolve(changed, origin(), types.DocumentCheckout, token, forest)
    |> expect.to_equal(Error(tree_error.InvalidReference(pair.1)))
    let assert Ok(#(changed, replacement)) =
      anchors.acquire(changed, view, first)
    replacement |> expect.to_not_equal(token)
    anchors.status(changed, origin(), types.DocumentCheckout, token, forest)
    |> expect.to_equal(Ok(pair.1))
  })
  [
    [live.Promote(first, second), live.Promote(first, third)],
    [live.Promote(first, third), live.Promote(second, third)],
    [live.Promote(first, second), live.Discard(first)],
  ]
  |> list.each(fn(changes) {
    anchors.apply_changes(registry, origin(), types.DocumentCheckout, changes)
    |> expect.to_be_error
    Nil
  })
  let assert Ok(#(registry, _)) = anchors.acquire(registry, view, second)
  anchors.apply_changes(registry, origin(), types.DocumentCheckout, [
    live.Promote(first, second),
  ])
  |> expect.to_be_error
  Nil
}

pub fn live_anchor_registry_removed_and_destroyed_test() {
  let before = content()
  let assert Ok(reference) = forest.locate(before, ["left", "1"])
  let #(registry, view) =
    anchors.open(anchors.new(), origin(), types.DocumentCheckout)
  let assert Ok(#(registry, token)) = anchors.acquire(registry, view, reference)
  let assert Ok(revision) =
    fluid_ids.stable_id("40000000-0000-4000-8000-000000000001")
  let assert Ok(order) = change.identity_order([#(revision, -1)])
  let assert Ok(edit) =
    change.edit(
      identifier_fixture.full_stored(),
      before,
      revision,
      types.ArrayRemove(["left"], 1, 2),
      order,
    )
  let assert Ok(delta) =
    change.into_delta(change.TaggedChange(Some(revision), None, edit))
  let assert Ok(removed) = forest.apply_delta(before, delta)
  anchors.status(registry, origin(), types.DocumentCheckout, token, removed)
  |> expect.to_equal(Ok(tree_error.Removed))
  anchors.resolve(registry, origin(), types.DocumentCheckout, token, removed)
  |> expect.to_equal(Error(tree_error.InvalidReference(tree_error.Removed)))
  let assert Ok(destroyed) = forest.trim_revisions(removed, [revision])
  anchors.status(registry, origin(), types.DocumentCheckout, token, destroyed)
  |> expect.to_equal(Ok(tree_error.Deleted))
  anchors.resolve(registry, origin(), types.DocumentCheckout, token, destroyed)
  |> expect.to_equal(Error(tree_error.InvalidReference(tree_error.Deleted)))
}

pub fn live_anchor_path_preserves_map_keys_test() {
  let assert Ok(view) =
    fluid_ids.stable_id("30000000-0000-4000-8000-000000000002")
  let assert Ok(state) =
    forest.new(
      view,
      identifier_fixture.full_stored(),
      Some(
        identifier_fixture.full_root(
          identifier_fixture.point("featured", "featured"),
          [],
          [],
          [
            #("", identifier_fixture.point("duplicate", "empty")),
            #("0", identifier_fixture.point("duplicate", "numeric")),
          ],
        ),
      ),
    )
  [[], ["byKey"], ["byKey", ""], ["byKey", "0"]]
  |> list.each(fn(path) {
    let assert Ok(reference) = forest.locate(state, path)
    forest.path_of_reference(state, reference) |> expect.to_equal(Ok(path))
    forest.reference_status(content(), reference)
    |> expect.to_equal(Ok(forest.ForeignNode))
  })
}
