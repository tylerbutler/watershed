import gleam/list
import gleam/option.{None, Some}
import lustre/attribute as a
import lustre/element.{type Element}
import lustre/element/html as h
import watershed_site/guide
import watershed_site/view/ecosystem
import watershed_site/view/sheet

pub fn view(
  path: String,
  step: guide.Step,
  body: List(Element(msg)),
  demo: Element(msg),
) -> Element(msg) {
  let #(previous, next) = guide.neighbours(step.slug)
  sheet.view(path, [
    h.header([a.class("g-hero")], [
      h.div([a.class("g-hero-inner")], [
        h.p([a.class("g-crumbs annot")], [
          h.a([a.href("/")], [h.text("← watershed")]),
          h.text(" · "),
          h.a([a.href("/guide")], [h.text("Build guide")]),
          h.text(" / Step " <> step.number),
        ]),
        h.span([a.class("g-num annot"), a.attribute("aria-hidden", "true")], [
          h.text(step.number),
        ]),
        h.h1([], [h.text(step.title)]),
        h.p([a.class("g-goal")], [h.text(step.goal)]),
        h.p([a.class("g-surface annot")], [
          h.span([], [h.text("Surface")]),
          h.text(" " <> step.surface),
        ]),
      ]),
    ]),
    h.main([a.id("content"), a.class("doc-body")], list.append(body, [demo])),
    h.nav([a.class("g-step"), a.attribute("aria-label", "Guide steps")], [
      case previous {
        Some(step) ->
          step_link(
            "prev",
            guide.path(step.slug),
            "← Step " <> step.number,
            step.title,
          )
        None -> step_link("prev", "/guide", "← Index", "The survey procedure")
      },
      case next {
        Some(step) ->
          step_link(
            "next",
            guide.path(step.slug),
            "Step " <> step.number <> " →",
            step.title,
          )
        None ->
          step_link(
            "next",
            "/examples#retro_board_lustre",
            "Next build →",
            "The advanced retro board",
          )
      },
    ]),
    ecosystem.view(path),
  ])
}

fn step_link(
  direction: String,
  href: String,
  label: String,
  title: String,
) -> Element(msg) {
  h.a([a.class("g-step-cell g-step-" <> direction), a.href(href)], [
    h.span([a.class("annot")], [h.text(label)]),
    h.span([a.class("g-step-title")], [h.text(title)]),
  ])
}
