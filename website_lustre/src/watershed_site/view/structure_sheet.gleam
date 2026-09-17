import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import lustre/attribute as a
import lustre/element.{type Element}
import lustre/element/html as h
import watershed_site/structures
import watershed_site/view/ecosystem
import watershed_site/view/field_notes
import watershed_site/view/sheet

pub fn view(family: structures.Family) -> Element(msg) {
  let #(previous, next) = structures.neighbours(family.slug)
  sheet.view("/structures/" <> family.slug <> "/", [
    hero(family),
    h.main(
      [a.id("content"), a.class("plates")],
      list.index_map(family.entries, plate),
    ),
    field_notes.related("/structures/" <> family.slug),
    navigation(previous, next),
    ecosystem.view("/structures/" <> family.slug <> "/"),
  ])
}

fn hero(family: structures.Family) -> Element(msg) {
  let ordinal =
    structures.all()
    |> list.index_map(fn(item, index) { #(item.slug, index) })
    |> list.find(fn(item) { item.0 == family.slug })
    |> result.map(fn(item) { "Family " <> pad_number(item.1 + 1) })
    |> result.unwrap("")
  h.header([a.class("cat-hero")], [
    h.div([a.class("cat-hero-inner")], [
      h.p([a.class("eyebrow annot")], [
        h.a([a.href("/")], [h.text("← watershed")]),
        h.text(" · "),
        h.a([a.href("/structures")], [h.text("Data structures")]),
        h.text(" / " <> family.name),
      ]),
      h.div([a.class("cat-title")], [
        h.h1([], [h.text(family.name)]),
        h.span(
          [a.class("cat-index annot"), a.attribute("aria-hidden", "true")],
          [h.text(ordinal)],
        ),
      ]),
      h.p([a.class("cat-tagline")], [h.text(family.tagline)]),
      ..list.append(
        list.map(family.lede, fn(paragraph) {
          h.p([a.class("lede")], [h.text(paragraph)])
        }),
        [
          h.nav(
            [
              a.class("jump"),
              a.attribute("aria-label", family.name <> " in this family"),
            ],
            list.map(family.entries, fn(entry) {
              let kind = structures.kind_name(entry.kind)
              h.a([a.href("#" <> entry.id)], [
                h.code([], [h.text(entry.name)]),
                h.span(
                  [
                    a.class("jump-kind annot"),
                    a.attribute("data-kind", kind),
                  ],
                  [h.text(kind)],
                ),
              ])
            }),
          ),
        ],
      )
    ]),
  ])
}

fn plate(entry: structures.Entry, index: Int) -> Element(msg) {
  let kind = structures.kind_name(entry.kind)
  h.article(
    [
      a.class("plate"),
      a.id(entry.id),
      a.attribute("data-reveal", "rise"),
    ],
    [
      h.div([a.class("plate-mark annot"), a.attribute("aria-hidden", "true")], [
        h.text("No. " <> pad_number(index + 1)),
      ]),
      h.header([a.class("plate-head")], [
        h.div([a.class("plate-name")], [
          h.h2([a.id(entry.id <> "-title")], [h.text(entry.name)]),
          h.span([a.class("stamp"), a.attribute("data-kind", kind)], [
            h.text(kind),
          ]),
        ]),
        h.code([a.class("plate-module")], [h.text(entry.module_name)]),
        h.p([a.class("plate-tagline")], [h.text(entry.tagline)]),
        ..demo_links(entry)
      ]),
      h.div([a.class("plate-body")], [
        h.div(
          [a.class("plate-prose")],
          list.append(
            list.map(entry.how, fn(paragraph) { h.p([], [h.text(paragraph)]) }),
            [
              h.h3([a.class("uses-title annot")], [h.text("Best for")]),
              h.ul(
                [a.class("uses")],
                list.map(entry.use_cases, fn(use_case) {
                  h.li([], [h.text(use_case)])
                }),
              ),
            ],
          ),
        ),
        h.dl([a.class("spec")], [
          specification("Merge rule", entry.rule),
          specification("Optimistic behavior", entry.optimistic),
          specification("Summary shape", entry.summary),
          specification("Model", structures.model_description(entry.kind)),
        ]),
      ]),
    ],
  )
}

fn demo_links(entry: structures.Entry) -> List(Element(msg)) {
  let dedicated = case entry.demo_href {
    Some(href) -> [
      h.a([a.class("plate-demo"), a.href(href)], [
        h.text("Open the live " <> entry.name <> " demo →"),
      ]),
    ]
    None -> []
  }
  case entry.id {
    "mv-register" ->
      list.append(dedicated, [
        h.a([a.class("plate-demo"), a.href("/mv-register")], [
          h.text("Open the revision slate and API notes →"),
        ]),
      ])
    "map" ->
      list.append(dedicated, [
        h.a([a.class("plate-demo"), a.href("/sudoku")], [
          h.text("Open the live Sudoku cell demo →"),
        ]),
      ])
    _ -> dedicated
  }
}

fn specification(term: String, description: String) -> Element(msg) {
  h.div([], [
    h.dt([], [h.text(term)]),
    h.dd([], [h.text(description)]),
  ])
}

fn navigation(
  previous: Result(String, Nil),
  next: Result(String, Nil),
) -> Element(msg) {
  let assert Ok(previous_slug) = previous
  let assert Ok(previous_family) = structures.get(previous_slug)
  let assert Ok(next_slug) = next
  let assert Ok(next_family) = structures.get(next_slug)
  h.nav(
    [a.class("cat-nav"), a.attribute("aria-label", "More on data structures")],
    [
      h.a([a.class("cat-nav-side"), a.href("/structures/" <> previous_slug)], [
        h.span([a.class("annot")], [h.text("← Previous family")]),
        h.strong([], [h.text(previous_family.name)]),
      ]),
      h.div([a.class("cat-nav-mid")], [
        h.a([a.href("/structures")], [h.text("All families")]),
        h.a([a.href("/models")], [h.text("DDS vs CRDT vs OT →")]),
        h.a([a.href("/#demo")], [h.text("See it live ↓")]),
      ]),
      h.a(
        [
          a.class("cat-nav-side cat-nav-next"),
          a.href("/structures/" <> next_slug),
        ],
        [
          h.span([a.class("annot")], [h.text("Next family →")]),
          h.strong([], [h.text(next_family.name)]),
        ],
      ),
    ],
  )
}

fn pad_number(number: Int) -> String {
  let value = int.to_string(number)
  case number < 10 {
    True -> "0" <> value
    False -> value
  }
}
