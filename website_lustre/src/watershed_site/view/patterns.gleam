import gleam/int
import gleam/list
import gleam/result
import gleam/string
import lustre/attribute as a
import lustre/element.{type Element}
import lustre/element/html as h
import watershed_site/error.{type BuildError}
import watershed_site/guide
import watershed_site/practice
import watershed_site/snippet
import watershed_site/view/ecosystem
import watershed_site/view/sheet

pub fn view(manifest: snippet.Manifest) -> Result(Element(msg), BuildError) {
  use sections <- result.try(
    practice.themes()
    |> list.try_map(section(_, manifest)),
  )
  Ok(
    sheet.view("/patterns/", [
      hero(),
      h.main([a.id("index"), a.class("p-main")], sections),
      boundary(),
      ecosystem.view("/patterns/"),
    ]),
  )
}

fn hero() -> Element(msg) {
  h.header([a.class("p-hero")], [
    h.div([a.class("p-hero-inner")], [
      h.p([a.class("p-crumbs annot")], [
        h.a([a.href("/")], [h.text("← watershed")]),
        h.text(" / Patterns"),
      ]),
      h.h1([], [
        h.text("Implementation patterns"),
        h.br([]),
        h.text("from the examples."),
      ]),
      h.p([a.class("p-lede")], [
        h.text(
          "Each entry connects a problem to the example code that addresses it. Browse by problem here, or follow the build guide in implementation order.",
        ),
      ]),
      h.div([a.class("p-actions")], [
        h.a([a.class("cta-primary"), a.href("#index")], [
          h.text("Read the index ↓"),
        ]),
        h.a([a.class("cta-quiet"), a.href("/examples")], [
          h.text("Browse all examples →"),
        ]),
      ]),
    ]),
  ])
}

fn section(
  theme: practice.Theme,
  manifest: snippet.Manifest,
) -> Result(Element(msg), BuildError) {
  let items = practice.by_theme(theme)
  use rules <- result.try(list.try_map(items, rule(_, manifest)))
  let count = list.length(items)
  Ok(
    h.section([a.class("p-step")], [
      h.header([a.class("p-step-head")], [
        h.p([a.class("annot")], [
          h.text(
            int.to_string(count)
            <> case count {
              1 -> " note"
              _ -> " notes"
            },
          ),
        ]),
        h.h2([], [h.text(practice.theme_title(theme))]),
        h.p([a.class("p-step-goal")], [
          h.text(practice.theme_blurb(theme)),
        ]),
      ]),
      h.ol([a.class("p-rules")], rules),
    ]),
  )
}

fn rule(
  item: practice.Practice,
  manifest: snippet.Manifest,
) -> Result(Element(msg), BuildError) {
  use source <- result.try(snippet.get(
    manifest,
    "practice " <> item.id,
    item.snippet_id,
  ))
  let prefix = "examples/" <> item.example_id <> "/"
  let source_path = case string.starts_with(source.source_path, prefix) {
    True -> string.drop_start(source.source_path, string.length(prefix))
    False -> source.source_path
  }
  Ok(
    h.li([], [
      h.a([a.class("p-rule-link"), a.href(practice.href(item))], [
        h.text(item.title),
      ]),
      h.p([a.class("p-rule")], [h.text(item.rule)]),
      h.p([a.class("annot p-rule-src")], [
        h.text(
          item.example_name
          <> " · "
          <> source_path
          <> " · Step "
          <> guide.get(item.step).number,
        ),
      ]),
    ]),
  )
}

fn boundary() -> Element(msg) {
  h.aside(
    [a.class("p-boundary"), a.attribute("aria-labelledby", "p-boundary-title")],
    [
      h.div([], [
        h.h2([a.id("p-boundary-title")], [
          h.text("Copy the constraint, not the whole design."),
        ]),
        h.p([], [
          h.text(
            "The examples show lifecycle and ownership constraints, not boilerplate to copy whole. Reuse those rules; keep domain-specific state and views close to the app that needs them.",
          ),
        ]),
        h.a([a.href("/examples")], [h.text("Choose an example to trace →")]),
      ]),
    ],
  )
}
