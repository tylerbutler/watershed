import gleam/bool
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import lustre/attribute as a
import lustre/element.{type Element}
import lustre/element/html as h
import lustre/event
import watershed_site/structure_demo/model
import watershed_site/structure_demo/runtime
import watershed_site/structure_demo/view as demo
import watershed_site/structures

pub fn view(
  family: structures.Family,
  demo_model: model.Model,
) -> Element(runtime.Msg) {
  h.main(
    [a.id("content"), a.class("plates")],
    list.index_map(family.entries, fn(entry, index) {
      plate(family, demo_model, entry, index)
    }),
  )
}

fn plate(
  family: structures.Family,
  demo_model: model.Model,
  entry: structures.Entry,
  index: Int,
) -> Element(runtime.Msg) {
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
        ..list.append(demo_links(entry), demo_toggle(demo_model, entry))
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
      ..demo_panel(family, demo_model, entry)
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

fn demo_toggle(
  demo_model: model.Model,
  entry: structures.Entry,
) -> List(Element(runtime.Msg)) {
  case entry.demo_href {
    Some(_) -> []
    None -> [
      h.div(
        [a.class("plate-viewbar"), a.attribute("data-structure-controls", "")],
        [
          h.button(
            [
              a.type_("button"),
              a.class("plate-toggle"),
              a.attribute("data-structure-toggle", entry.id),
              a.attribute("aria-controls", entry.id <> "-demo"),
              a.attribute("aria-describedby", entry.id <> "-title"),
              a.attribute(
                "aria-expanded",
                bool.to_string(is_open(demo_model, entry)),
              ),
              event.on_click(case runtime.structure_from_id(entry.id) {
                Ok(structure) -> runtime.TogglePanel(structure)
                Error(Nil) -> runtime.SelectStructure(demo_model.selected)
              }),
            ],
            [
              h.text(case is_open(demo_model, entry) {
                True -> "Close demo ↑"
                False -> "Try the live demo ↓"
              }),
            ],
          ),
        ],
      ),
    ]
  }
}

fn demo_panel(
  family: structures.Family,
  demo_model: model.Model,
  entry: structures.Entry,
) -> List(Element(runtime.Msg)) {
  case entry.demo_href {
    Some(_) -> []
    None -> [
      h.div(
        [
          a.class("plate-live"),
          a.id(entry.id <> "-demo"),
          a.attribute("data-structure-demo", ""),
          a.hidden(!is_open(demo_model, entry)),
        ],
        case is_open(demo_model, entry) {
          True -> [
            demo.view(
              demo_model,
              demo.Options(
                False,
                family.entries
                  |> list.filter(fn(item) { item.demo_href == None })
                  |> list.map(fn(item) { item.id }),
                Some("Live " <> family.name <> " demo"),
              ),
            ),
          ]
          False -> []
        },
      ),
      h.div([a.id(entry.id <> "-after-demo"), a.tabindex(-1)], []),
    ]
  }
}

fn is_open(demo_model: model.Model, entry: structures.Entry) -> Bool {
  case runtime.structure_from_id(entry.id) {
    Ok(structure) -> demo_model.open_panel == Some(structure)
    Error(Nil) -> False
  }
}

fn specification(term: String, description: String) -> Element(msg) {
  h.div([], [
    h.dt([], [h.text(term)]),
    h.dd([], [h.text(description)]),
  ])
}

fn pad_number(number: Int) -> String {
  let value = int.to_string(number)
  case number < 10 {
    True -> "0" <> value
    False -> value
  }
}

pub fn first_structure(family: structures.Family) -> model.Structure {
  family.entries
  |> list.filter_map(fn(entry) {
    case entry.demo_href {
      Some(_) -> Error(Nil)
      None -> runtime.structure_from_id(entry.id)
    }
  })
  |> list.first
  |> result.unwrap(model.Map)
}
