import gleam/int
import gleam/list
import gleam/option.{None, Some}
import lustre/attribute as a
import lustre/element.{type Element}
import lustre/element/html as h
import watershed_site/example
import watershed_site/practice
import watershed_site/view/ecosystem
import watershed_site/view/sheet

pub fn view() -> Element(msg) {
  sheet.view("/examples/", [
    hero(),
    h.main(
      [a.id("catalog"), a.class("e-main")],
      example.groups() |> list.map(group),
    ),
    next(),
    ecosystem.view("/examples/"),
  ])
}

fn hero() -> Element(msg) {
  let count = example.all() |> list.length |> int.to_string
  h.header([a.class("e-hero")], [
    h.div([a.class("e-hero-inner")], [
      h.p([a.class("e-crumbs annot")], [
        h.a([a.href("/")], [h.text("← watershed")]),
        h.text(" / Examples"),
      ]),
      h.h1([], [h.text("Run the examples.")]),
      h.p([a.class("e-lede")], [
        h.text(
          count
          <> " complete Lustre applications, all compiled from Gleam. Start with a small lifecycle trace, compare conflict rules under the same action, or open the apps that push composition and browser interaction hardest.",
        ),
      ]),
      h.div([a.class("e-actions")], [
        h.a([a.class("cta-primary"), a.href("#catalog")], [
          h.text("Open the field index ↓"),
        ]),
        h.a([a.class("cta-quiet"), a.href("/guide")], [
          h.text("Build one with the guide →"),
        ]),
      ]),
    ]),
  ])
}

fn group(group: example.Group) -> Element(msg) {
  h.section(
    [
      a.class("e-group"),
      a.attribute("aria-labelledby", "group-" <> group_id(group.id)),
    ],
    [
      h.header([a.class("e-group-head")], [
        h.h2([a.id("group-" <> group_id(group.id))], [h.text(group.title)]),
        h.p([], [h.text(group.description)]),
      ]),
      h.ol([a.class("e-ledger")], example.by_group(group.id) |> list.map(entry)),
    ],
  )
}

fn group_id(group: example.GroupId) -> String {
  case group {
    example.Foundation -> "foundation"
    example.Conflicts -> "conflicts"
    example.Composition -> "composition"
    example.Specialized -> "specialized"
  }
}

fn entry(item: example.Example) -> Element(msg) {
  let practices = practice.by_example(item.id)
  h.li([a.id(item.id), a.class("e-entry")], [
    h.article([], [
      h.header([a.class("e-entry-head")], [
        h.div([], [
          h.h3([], [h.text(item.name)]),
          h.p([], [h.text(item.summary)]),
        ]),
        h.a([a.class("e-source annot"), a.href(example.source(item))], [
          h.text("Source and run guide ↗"),
        ]),
      ]),
      h.dl([a.class("e-facts")], [
        h.div([], [
          h.dt([a.class("annot")], [h.text("Structures")]),
          h.dd(
            [a.class("e-structures")],
            item.structures |> list.map(structure),
          ),
        ]),
        h.div([], [
          h.dt([a.class("annot")], [h.text("Payoff race")]),
          h.dd([], [h.text(item.payoff)]),
        ]),
        case practices {
          [] -> element.none()
          practices ->
            h.div([], [
              h.dt([a.class("annot")], [h.text("Demonstrates")]),
              h.dd(
                [a.class("e-practices")],
                practices
                  |> list.map(fn(item) {
                    h.a([a.href(practice.href(item))], [h.text(item.title)])
                  }),
              ),
            ])
        },
      ]),
    ]),
  ])
}

fn structure(name: String) -> Element(msg) {
  case example.structure_link(name) {
    Some(#(slug, id)) ->
      h.a([a.href("/structures/" <> slug <> "#" <> id)], [
        h.code([], [h.text(name)]),
      ])
    None -> h.code([], [h.text(name)])
  }
}

fn next() -> Element(msg) {
  h.aside([a.class("e-next"), a.attribute("aria-labelledby", "e-next-title")], [
    h.div([], [
      h.h2([a.id("e-next-title")], [
        h.text("Trace one before copying five."),
      ]),
      h.p([], [
        h.text(
          "Each README explains why its structure fits and the race worth watching. The build guide walks the same shape step by step.",
        ),
      ]),
      h.a([a.href("/guide")], [h.text("Follow the build guide →")]),
    ]),
  ])
}
