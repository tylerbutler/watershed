import gleam/list
import gleam/string
import gleeunit/should
import lustre/element
import watershed_site/guide
import watershed_site/practice
import watershed_site/snippet
import watershed_site/view/field_notes

pub fn reference_links_to_the_typed_practice_test() {
  let assert Ok(item) = practice.get("authoritative-channel")
  let html = field_notes.reference(item) |> element.to_string
  string.contains(html, "class=\"fnr\"") |> should.be_true()
  string.contains(html, "/guide/notes#authoritative-channel")
  |> should.be_true()
  string.contains(html, item.title <> " ↓") |> should.be_true()
}

pub fn connect_renders_six_source_backed_notes_test() {
  let assert Ok(manifest) =
    snippet.load("src/generated/snippets.json")
  let assert Ok(view) = field_notes.view(guide.Connect, manifest)
  let html = element.to_string(view)
  string.contains(html, "How the examples do it") |> should.be_true()
  string.contains(html, "id=\"relay-decorator\"") |> should.be_true()
  string.contains(html, "id=\"claims-seeding\"") |> should.be_true()
  string.contains(html, "https://github.com/tylerbutler/watershed/tree/main/")
  |> should.be_true()
  string.split(html, "class=\"fn-note\"")
  |> list.length
  |> should.equal(7)
}
