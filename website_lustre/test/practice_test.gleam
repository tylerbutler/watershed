import fixtures/catalog_contract
import gleam/list
import gleeunit/should
import watershed_site/guide
import watershed_site/practice
import watershed_site/snippet

pub fn catalog_groups_all_practices_by_guide_step_test() {
  practice.all() |> list.length |> should.equal(17)
  [
    #(guide.Connect, 6),
    #(guide.Notes, 4),
    #(guide.Race, 0),
    #(guide.Votes, 2),
    #(guide.Presence, 3),
    #(guide.Testing, 2),
  ]
  |> list.each(fn(expected) {
    practice.by_step(expected.0) |> list.length |> should.equal(expected.1)
  })
}

pub fn practice_links_to_its_guide_anchor_test() {
  let assert Ok(item) = practice.get("authoritative-channel")
  practice.href(item)
  |> should.equal("/guide/notes#authoritative-channel")
  practice.get("missing") |> should.equal(Error(Nil))
}

pub fn practice_catalog_matches_contract_and_manifest_test() {
  practice.all() |> should.equal(catalog_contract.practices())
  practice.themes()
  |> list.map(fn(theme) {
    #(theme, practice.theme_title(theme), practice.theme_blurb(theme))
  })
  |> should.equal(catalog_contract.practice_themes())
  let assert Ok(manifest) = snippet.load("src/generated/snippets.json")
  practice.all()
  |> list.each(fn(item) {
    let assert Ok(code) =
      snippet.get(manifest, "practice catalog", item.snippet_id)
    let assert snippet.Source(_) = code.origin
  })
}
