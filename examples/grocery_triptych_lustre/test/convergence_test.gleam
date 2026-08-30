import gleam/list
import gleam/option.{Some}
import gleam/string
import gleeunit
import gleeunit/should

import grocery_triptych_lustre/document_schema
import watershed.{type Document, type GSet, type OrSet, type TwoPSet}
import watershed/sluice_js.{type Sluice}

pub fn main() -> Nil {
  gleeunit.main()
}

type Client {
  Client(grow_only: GSet, two_phase: TwoPSet, observed: OrSet)
}

type Snapshot {
  Snapshot(
    grow_only: List(String),
    two_phase: List(String),
    observed: List(String),
  )
}

fn room(name: String) -> #(Sluice, Client, Client) {
  let sluice = sluice_js.start(tenant: "default", document: name)
  let document_a = sluice_js.connect(sluice, "user-a")
  let document_b = sluice_js.connect(sluice, "user-b")
  sluice_js.settle(sluice)

  let root_a = watershed.root_typed(document_a)
  let assert Ok(grow_only) = watershed.create_g_set(document_a)
  watershed.set_g_set_field(root_a, document_schema.grow_only(), grow_only)
  let assert Ok(two_phase) = watershed.create_two_p_set(document_a)
  watershed.set_two_p_set_field(root_a, document_schema.two_phase(), two_phase)
  let assert Ok(observed) = watershed.create_or_set(document_a)
  watershed.set_or_set_field(root_a, document_schema.observed(), observed)
  sluice_js.settle(sluice)

  #(sluice, client(document_a), client(document_b))
}

fn client(document: Document(document_schema.Pantry)) -> Client {
  let root = watershed.root_typed(document)
  let assert Ok(Some(grow_only)) =
    watershed.resolve_g_set_field(document, root, document_schema.grow_only())
  let assert Ok(Some(two_phase)) =
    watershed.resolve_two_p_set_field(
      document,
      root,
      document_schema.two_phase(),
    )
  let assert Ok(Some(observed)) =
    watershed.resolve_or_set_field(document, root, document_schema.observed())

  Client(grow_only: grow_only, two_phase: two_phase, observed: observed)
}

fn add_everywhere(client: Client, item: String) -> Nil {
  watershed.g_set_add(client.grow_only, item)
  watershed.two_p_set_add(client.two_phase, item)
  watershed.or_set_add(client.observed, item)
}

fn remove_shared(client: Client, item: String) -> Nil {
  watershed.two_p_set_remove(client.two_phase, item)
  watershed.or_set_remove(client.observed, item)
}

fn snapshot(client: Client) -> Snapshot {
  Snapshot(
    grow_only: g_set_values(client.grow_only),
    two_phase: two_p_set_values(client.two_phase),
    observed: or_set_values(client.observed),
  )
}

fn assert_both(client_a: Client, client_b: Client, expected: Snapshot) -> Nil {
  snapshot(client_a) |> should.equal(expected)
  snapshot(client_b) |> should.equal(expected)
}

fn expected(
  grow_only: List(String),
  two_phase: List(String),
  observed: List(String),
) -> Snapshot {
  Snapshot(
    grow_only: sort_values(grow_only),
    two_phase: sort_values(two_phase),
    observed: sort_values(observed),
  )
}

fn g_set_values(set: GSet) -> List(String) {
  watershed.g_set_values(set) |> sort_values
}

fn two_p_set_values(set: TwoPSet) -> List(String) {
  watershed.two_p_set_values(set) |> sort_values
}

fn or_set_values(set: OrSet) -> List(String) {
  watershed.or_set_values(set) |> sort_values
}

fn sort_values(values: List(String)) -> List(String) {
  list.sort(values, string.compare)
}

pub fn add_only_operations_converge_without_duplicates_test() -> Nil {
  let #(sluice, client_a, client_b) = room("grocery-convergence-add-only")

  list.each(["milk", "bread", "milk", "eggs"], fn(item) {
    add_everywhere(client_a, item)
  })
  list.each(["avocado", "milk", "bread", "avocado"], fn(item) {
    add_everywhere(client_b, item)
  })
  sluice_js.settle(sluice)

  assert_both(
    client_a,
    client_b,
    expected(
      ["milk", "bread", "eggs", "avocado"],
      ["milk", "bread", "eggs", "avocado"],
      ["milk", "bread", "eggs", "avocado"],
    ),
  )
}

pub fn shared_remove_retains_only_the_g_set_test() -> Nil {
  let #(sluice, client_a, client_b) = room("grocery-convergence-remove")

  add_everywhere(client_a, "milk")
  sluice_js.settle(sluice)
  assert_both(client_a, client_b, expected(["milk"], ["milk"], ["milk"]))

  remove_shared(client_b, "milk")
  sluice_js.settle(sluice)

  assert_both(client_a, client_b, expected(["milk"], [], []))
}

pub fn two_p_set_readd_stays_tombstoned_test() -> Nil {
  let #(sluice, client_a, client_b) =
    room("grocery-convergence-two-p-tombstone")

  add_everywhere(client_a, "milk")
  sluice_js.settle(sluice)
  assert_both(client_a, client_b, expected(["milk"], ["milk"], ["milk"]))

  remove_shared(client_a, "milk")
  sluice_js.settle(sluice)
  assert_both(client_a, client_b, expected(["milk"], [], []))

  watershed.two_p_set_add(client_b.two_phase, "milk")
  sluice_js.settle(sluice)

  assert_both(client_a, client_b, expected(["milk"], [], []))
}

pub fn or_set_remove_then_readd_becomes_present_test() -> Nil {
  let #(sluice, client_a, client_b) = room("grocery-convergence-or-readd")

  add_everywhere(client_a, "milk")
  sluice_js.settle(sluice)
  assert_both(client_a, client_b, expected(["milk"], ["milk"], ["milk"]))

  remove_shared(client_a, "milk")
  sluice_js.settle(sluice)
  assert_both(client_a, client_b, expected(["milk"], [], []))

  watershed.or_set_add(client_b.observed, "milk")
  sluice_js.settle(sluice)

  assert_both(client_a, client_b, expected(["milk"], [], ["milk"]))
}

pub fn concurrent_add_and_remove_follow_kind_specific_semantics_test() -> Nil {
  let #(sluice, client_a, client_b) = room("grocery-convergence-concurrent")

  add_everywhere(client_a, "eggs")
  sluice_js.settle(sluice)
  assert_both(client_a, client_b, expected(["eggs"], ["eggs"], ["eggs"]))

  remove_shared(client_a, "eggs")
  add_everywhere(client_b, "eggs")
  sluice_js.settle(sluice)

  assert_both(client_a, client_b, expected(["eggs"], [], ["eggs"]))
}
