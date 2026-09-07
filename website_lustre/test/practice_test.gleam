import gleam/list
import gleam/string
import gleeunit/should
import simplifile
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

pub fn practice_catalog_matches_astro_and_manifest_test() {
  let assert Ok(practices_source) =
    simplifile.read("../website/src/data/practices.ts")
  let assert Ok(snippets_source) =
    simplifile.read("../website/src/data/practice-snippets.ts")
  let assert Ok(manifest) =
    snippet.load("../website/src/generated/snippets.json")
  practice.all()
  |> list.each(fn(item) {
    [
      "id: \"" <> item.id <> "\"",
      "title: \"" <> item.title <> "\"",
      "step: \"" <> string.replace(guide.path(item.step), "/guide/", "") <> "\"",
      "rule: \"" <> item.rule <> "\"",
    ]
    |> list.each(fn(expected) {
      string.contains(practices_source, expected) |> should.be_true()
    })
    string.contains(
      snippets_source,
      "sourceSnippet(\"" <> item.snippet_id <> "\")",
    )
    |> should.be_true()
    let assert Ok(code) =
      snippet.get(manifest, "practice catalog", item.snippet_id)
    let assert snippet.Source(_) = code.origin
  })
}
