import gleam/list
import gleam/string
import lustre/element
import watershed_site/content
import watershed_site/page
import watershed_site/route
import watershed_site/snippet

pub fn component_model_pages_render_shared_layout_and_snippets_test() {
  let assert Ok(manifest) =
    snippet.load("../website/src/generated/snippets.json")
  [
    #(
      "components",
      "Why a components layer exists",
      "src/watershed/component.gleam",
      "/component-model/ports",
    ),
    #(
      "ports",
      "A port is a component&#39;s declared connection point",
      "test/watershed/port_test.gleam",
      "/component-model/workspaces",
    ),
    #(
      "workspaces",
      "A workspace is the saved board",
      "src/watershed/workspace.gleam",
      "/guide",
    ),
  ]
  |> list.each(fn(expected) {
    let page_route = route.component_model(expected.0)
    let assert Ok(source) = content.load(page_route)
    let assert Ok(document) = page.render(source, page_route, manifest, "test")
    let html = element.to_document_string(document)
    [
      expected.1,
      expected.2,
      expected.3,
      "class=\"fd-hero\"",
      "aria-label=\"Component model sheets\"",
      "href=\"/styles/concept-sheet.css\"",
      "data-language=\"gleam\"",
    ]
    |> list.each(fn(text) {
      let assert True = string.contains(html, text) as text
    })
    ["/guide_race.js", "astro-island", "/_astro/", "@vite", "data-component"]
    |> list.each(fn(text) {
      let assert False = string.contains(html, text) as text
    })
  })
}
