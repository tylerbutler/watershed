import gleam/list
import gleam/option
import gleeunit/should
import watershed_site/example

pub fn catalog_groups_all_examples_test() {
  example.all() |> list.length |> should.equal(14)
  example.groups()
  |> list.map(fn(group) {
    #(group.title, example.by_group(group.id) |> list.length)
  })
  |> should.equal([
    #("Foundation and lifecycle", 3),
    #("Conflict semantics", 5),
    #("Composition and presence", 3),
    #("Specialized interaction", 3),
  ])
}

pub fn source_links_point_to_the_example_directory_test() {
  let assert Ok(item) =
    example.all() |> list.find(fn(item) { item.id == "dice_lustre" })
  example.source(item)
  |> should.equal(
    "https://github.com/tylerbutler/watershed/tree/main/examples/dice_lustre",
  )
}

pub fn catalog_preserves_linked_and_unlinked_structures_test() {
  example.structure_link("OrMap")
  |> should.equal(option.Some(#("maps", "ormap")))
  example.structure_link("Child maps") |> should.equal(option.None)
}
