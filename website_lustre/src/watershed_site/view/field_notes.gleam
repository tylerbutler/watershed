import gleam/list
import gleam/option.{None, Some}
import gleam/result
import lustre/attribute as a
import lustre/element.{type Element}
import lustre/element/html as h
import watershed_site/code
import watershed_site/error.{type BuildError}
import watershed_site/guide
import watershed_site/practice
import watershed_site/snippet

pub fn reference(item: practice.Practice) -> Element(msg) {
  h.p([a.class("fnr")], [
    h.span([a.class("fnr-label annot")], [h.text("Field note")]),
    h.a([a.href(practice.href(item))], [h.text(item.title <> " ↓")]),
  ])
}

pub fn view(
  step: guide.Slug,
  manifest: snippet.Manifest,
) -> Result(Element(msg), BuildError) {
  let practices = practice.by_step(step)
  use notes <- result.try(list.try_map(practices, note(_, manifest)))
  case notes {
    [] -> Ok(element.none())
    _ ->
      Ok(
        h.section([a.class("fn"), a.attribute("aria-labelledby", "fn-title")], [
          h.h2([a.id("fn-title")], [h.text("How the examples do it")]),
          h.p([a.class("fn-lede")], [
            h.text(
              "Each note connects an implementation practice to a checked-in example. Open it for the code and reasoning.",
            ),
          ]),
          ..notes
        ]),
      )
  }
}

pub fn related(path: String) -> Element(msg) {
  case practice.related_to(path) {
    [] -> element.none()
    practices ->
      h.aside([a.class("rfn"), a.attribute("aria-labelledby", "rfn-title")], [
        h.div([a.class("rfn-inner")], [
          h.h2([a.id("rfn-title")], [h.text("Field notes from the examples")]),
          h.p([a.class("rfn-lede")], [
            h.text(
              "How the checked-in examples handle the problems described on this page.",
            ),
          ]),
          h.ul(
            [a.class("rfn-list")],
            list.map(practices, fn(item) {
              h.li([], [
                h.a([a.href(practice.href(item))], [h.text(item.title)]),
                h.p([], [h.text(item.rule)]),
                h.span([a.class("annot")], [h.text(item.example_name)]),
              ])
            }),
          ),
        ]),
      ])
  }
}

fn note(
  item: practice.Practice,
  manifest: snippet.Manifest,
) -> Result(Element(msg), BuildError) {
  use source <- result.try(snippet.get(
    manifest,
    "practice " <> item.id,
    item.snippet_id,
  ))
  let check = case item.test_note {
    None -> []
    Some(text) -> [
      h.div([a.class("g-note")], [
        h.p([], [h.strong([], [h.text("The check.")]), h.text(" " <> text)]),
      ]),
    ]
  }
  let evidence = case item.example_href {
    Some(href) -> h.a([a.href(href)], [h.text(item.example_name)])
    None -> h.span([], [h.text(item.example_name)])
  }
  Ok(
    h.details([a.id(item.id), a.class("fn-note")], [
      h.summary([], [
        h.h3([], [h.text(item.title)]),
        h.p([a.class("fn-rule")], [h.text(item.rule)]),
      ]),
      h.div(
        [a.class("fn-body")],
        list.flatten([
          list.map(item.body, fn(paragraph) { h.p([], [h.text(paragraph)]) }),
          [
            code.source_block(
              source,
              Some(
                "https://github.com/tylerbutler/watershed/tree/main/"
                <> source.source_path,
              ),
              Some(item.example_name),
            ),
          ],
          check,
          [
            h.p([a.class("fn-evidence")], [
              h.span([a.class("annot")], [h.text("Demonstrated by")]),
              evidence,
            ]),
          ],
        ]),
      ),
    ]),
  )
}
