import gleam/list
import gleam/option.{None, Some}
import gleeunit/should
import watershed_site/directory/runtime as directory

fn ready() {
  let assert Ok(rig) = directory.start_rig()
  #(directory.update(directory.init().0, directory.Started(0, Ok(rig))).0, rig)
}

fn land_all(model, delivery) {
  directory.replicas()
  |> list.fold(model, fn(current, replica) {
    directory.update(current, directory.Land(0, delivery, replica)).0
  })
}

pub fn starts_with_three_empty_roots_test() {
  let static = directory.static_model()
  static.phase |> should.equal(directory.Static)
  static.trees |> should.equal([])
  let #(model, _) = ready()
  model.phase |> should.equal(directory.Ready)
  model.converged |> should.be_true()
  model.trees |> list.length |> should.equal(3)
  model.trees
  |> list.each(fn(tree) {
    tree.root.path |> should.equal("/")
    tree.root.entries |> should.equal([])
    tree.root.children |> should.equal([])
  })
}

pub fn folder_creation_diverges_then_converges_test() {
  let #(model, rig) = ready()
  let assert Ok(mutation) =
    directory.create_folder(rig, directory.ClientA, "/", "surveys")
  let pending =
    directory.update(model, directory.MutationSubmitted(0, Ok(mutation))).0
  directory.node(pending, directory.ClientA, "/surveys")
  |> should.be_some()
  directory.node(pending, directory.ClientB, "/surveys")
  |> should.equal(None)
  let assert Ok(delivery) = directory.deliver_group(rig)
  let returning =
    directory.update(pending, directory.Delivered(0, Ok(delivery))).0
  returning.converged |> should.be_false()
  directory.node(returning, directory.ClientB, "/surveys")
  |> should.equal(None)
  let complete = land_all(returning, delivery)
  [directory.ClientA, directory.ClientB, directory.ClientC]
  |> list.each(fn(replica) {
    directory.node(complete, replica, "/surveys") |> should.be_some()
  })
  complete.converged |> should.be_true()
}

pub fn same_folder_race_merges_one_node_test() {
  let #(model, rig) = ready()
  let assert Ok(mutation) = directory.race_folder(rig)
  mutation.pending |> list.length |> should.equal(3)
  let pending =
    directory.update(model, directory.MutationSubmitted(0, Ok(mutation))).0
  let complete =
    list.fold([1, 2, 3], pending, fn(current, _) {
      let assert Ok(delivery) = directory.deliver_group(rig)
      directory.update(current, directory.Delivered(0, Ok(delivery))).0
      |> land_all(delivery)
    })
  complete.trees
  |> list.each(fn(tree) {
    tree.root.children
    |> list.filter(fn(child) { child.name == "kettle-run" })
    |> list.length
    |> should.equal(1)
  })
  complete.converged |> should.be_true()
}

pub fn stale_landing_does_not_replace_newer_tree_test() {
  let #(model, rig) = ready()
  let assert Ok(first) =
    directory.create_folder(rig, directory.ClientA, "/", "surveys")
  let first_pending =
    directory.update(model, directory.MutationSubmitted(0, Ok(first))).0
  let assert Ok(first_delivery) = directory.deliver_group(rig)
  let first_returning =
    directory.update(first_pending, directory.Delivered(0, Ok(first_delivery))).0

  let assert Ok(second) =
    directory.create_folder(rig, directory.ClientA, "/", "later")
  let second_pending =
    directory.update(
      first_returning,
      directory.MutationSubmitted(0, Ok(second)),
    ).0
  let assert Ok(second_delivery) = directory.deliver_group(rig)
  let second_returning =
    directory.update(
      second_pending,
      directory.Delivered(0, Ok(second_delivery)),
    ).0
  let newest =
    directory.update(
      second_returning,
      directory.Land(0, second_delivery, directory.ClientA),
    ).0
  let stale =
    directory.update(
      newest,
      directory.Land(0, first_delivery, directory.ClientA),
    ).0

  directory.node(stale, directory.ClientA, "/later") |> should.be_some()
}

pub fn sample_tree_and_delete_converge_test() {
  let #(model, rig) = ready()
  let assert Ok(seed) = directory.seed_tree(rig)
  let seeded =
    directory.update(model, directory.MutationSubmitted(0, Ok(seed))).0
  let seeded =
    list.fold([1, 2, 3, 4], seeded, fn(current, _) {
      let assert Ok(delivery) = directory.deliver_group(rig)
      directory.update(current, directory.Delivered(0, Ok(delivery))).0
      |> land_all(delivery)
    })
  let assert Some(surveys) =
    directory.node(seeded, directory.ClientA, "/surveys")
  surveys.entries
  |> should.equal([
    directory.Entry("BM-17", "recorded"),
  ])
  let assert Ok(removal) =
    directory.delete_folder(rig, directory.ClientB, "/", "surveys")
  let removing =
    directory.update(seeded, directory.MutationSubmitted(0, Ok(removal))).0
  let assert Ok(delivery) = directory.deliver_group(rig)
  let complete =
    directory.update(removing, directory.Delivered(0, Ok(delivery))).0
    |> land_all(delivery)
  complete.trees
  |> list.each(fn(tree) {
    tree.root.children
    |> list.any(fn(child) { child.name == "surveys" })
    |> should.be_false()
  })
}

pub fn reset_ignores_stale_mutation_test() {
  let #(model, rig) = ready()
  let reset = directory.update(model, directory.Reset).0
  reset.generation |> should.equal(1)
  let assert Ok(mutation) =
    directory.create_folder(rig, directory.ClientA, "/", "surveys")
  let stale =
    directory.update(reset, directory.MutationSubmitted(0, Ok(mutation))).0
  stale |> should.equal(reset)
  let assert Ok(delivery) = directory.deliver_group(rig)
  directory.update(reset, directory.Land(0, delivery, directory.ClientA)).0
  |> should.equal(reset)
}

pub fn browser_failure_is_visible_test() {
  let #(model, _) = ready()
  let failed =
    directory.update(model, directory.BrowserFailed("Cannot animate.")).0
  failed.phase |> should.equal(directory.Failed)
  failed.error
  |> should.equal(Some("Unexpected delivery: Cannot animate."))
  failed.converged |> should.be_false()
}
