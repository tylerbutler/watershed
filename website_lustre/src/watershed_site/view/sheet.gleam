import gleam/list
import gleam/result
import gleam/string
import lustre/attribute as a
import lustre/element.{type Element}
import lustre/element/html as h
import watershed_site/foundations
import watershed_site/guide
import watershed_site/runtime

type Context {
  Context(title: String, href: String, links: List(#(String, String)))
}

pub fn active(path: String, match: String) -> Bool {
  path == match || string.starts_with(path, match <> "/")
}

pub fn view(path: String, children: List(Element(msg))) -> Element(msg) {
  element.fragment([
    h.a([a.class("skip-link"), a.href("#content")], [h.text("Skip to content")]),
    h.header([a.class("sheet-index")], [
      h.div([a.class("si-primary")], [
        h.a([a.class("si-mark"), a.href("/"), ..current(path == "/")], [
          h.span([a.class("si-name")], [h.text("watershed")]),
          h.span([a.class("si-tag annot")], [
            h.text("Collaborative data structures for Gleam"),
          ]),
        ]),
        h.nav([a.class("si-nav"), a.attribute("aria-label", "Sheet index")], [
          group(
            [
              #("Foundations", "/foundations"),
              #("Components", "/component-model"),
            ],
            path,
          ),
          group([#("Guide", "/guide")], path),
          group([#("Atlas", "/structures")], path),
          group([#("Runtime", "/runtime")], path),
          group([#("Models", "/models")], path),
          group([#("Examples", "/examples")], path),
          h.span([a.class("si-group")], [
            h.a(
              [
                a.class("si-link si-link-out annot"),
                a.href("https://github.com/tylerbutler/watershed"),
              ],
              [
                h.text("Source"),
                h.span([a.attribute("aria-hidden", "true")], [h.text(" ↗")]),
              ],
            ),
          ]),
        ]),
      ]),
      context(path),
    ]),
    h.div(
      [a.class("sheet")],
      list.map(["tl", "tr", "bl", "br"], fn(corner) {
        h.span(
          [a.class("reg reg-" <> corner), a.attribute("aria-hidden", "true")],
          [],
        )
      })
        |> list.append(children),
    ),
    h.div(
      [
        a.class("margin-row margin-bottom annot"),
        a.attribute("aria-hidden", "true"),
      ],
      [
        h.span([], [h.text("Magenta indicates revisions not yet field-checked")]),
        h.span([a.class("margin-mid")], [
          h.text(
            "Convergence by server sequencing — assumptions on the models sheet",
          ),
        ]),
        h.span([], [h.text("tylerbutler.com")]),
      ],
    ),
  ])
}

fn group(links: List(#(String, String)), path: String) -> Element(msg) {
  h.span(
    [a.class("si-group")],
    list.map(links, fn(item) {
      h.a(
        [
          a.href(item.1),
          a.class("si-link annot"),
          ..current(active(path, item.1))
        ],
        [h.text(item.0)],
      )
    }),
  )
}

fn context(path: String) -> Element(msg) {
  case context_for(path) {
    Error(Nil) -> element.none()
    Ok(Context(title, href, links)) ->
      h.nav(
        [
          a.class("si-context"),
          a.attribute("aria-label", title <> " sheets"),
        ],
        [
          h.a([a.class("si-context-title annot"), a.href(href)], [
            h.text(title),
          ]),
          h.span(
            [a.class("si-context-rule"), a.attribute("aria-hidden", "true")],
            [],
          ),
          h.div(
            [a.class("si-context-links")],
            list.map([#("Overview", href), ..links], fn(link) {
              h.a(
                [
                  a.class("si-context-link annot"),
                  a.href(link.1),
                  ..current(normalize(path) == link.1)
                ],
                [h.text(link.0)],
              )
            }),
          ),
        ],
      )
  }
}

fn context_for(path: String) -> Result(Context, Nil) {
  case string.split(normalize(path), "/") {
    ["", "foundations", ..] ->
      Ok(Context(
        "Foundations",
        "/foundations",
        numbered("/foundations", foundations.all()),
      ))
    ["", "component-model", ..] ->
      Ok(Context(
        "Component model",
        "/component-model",
        numbered("/component-model", foundations.component_model()),
      ))
    ["", "guide", ..] ->
      Ok(Context(
        "Build guide",
        "/guide",
        list.map(guide.all(), fn(step) {
          #(step.number <> " " <> step.title, guide.path(step.slug))
        }),
      ))
    ["", "structures", ..] ->
      Ok(
        Context("Field atlas", "/structures", [
          #("Counters", "/structures/counters"),
          #("Sets", "/structures/sets"),
          #("Registers", "/structures/registers"),
          #("Maps", "/structures/maps"),
          #("Sequences", "/structures/sequences"),
          #("Coordination", "/structures/coordination"),
          #("Transforms", "/structures/transforms"),
        ]),
      )
    ["", "runtime", ..] ->
      Ok(Context(
        "Runtime",
        "/runtime",
        list.map(runtime.all(), fn(item) {
          #(item.title, "/runtime/" <> item.slug)
        }),
      ))
    _ -> Error(Nil)
  }
}

fn numbered(
  base: String,
  docs: List(foundations.Doc),
) -> List(#(String, String)) {
  list.index_map(docs, fn(item, index) {
    #(
      pad_number(index + 1) <> " " <> first_title_part(item.title),
      base <> "/" <> item.slug,
    )
  })
}

fn first_title_part(title: String) -> String {
  string.split(title, " and ") |> list.first |> result.unwrap(title)
}

fn pad_number(number: Int) -> String {
  case number {
    1 -> "01"
    2 -> "02"
    3 -> "03"
    _ -> ""
  }
}

fn normalize(path: String) -> String {
  case path != "/", string.ends_with(path, "/") {
    True, True -> string.drop_end(path, 1)
    _, _ -> path
  }
}

pub fn current(active: Bool) -> List(a.Attribute(msg)) {
  case active {
    True -> [a.attribute("aria-current", "page")]
    False -> []
  }
}
