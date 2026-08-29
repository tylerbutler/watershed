//// Two failures the app used to swallow: a signaling socket that dies after
//// the document is open, and a local snapshot the browser is free to evict.

@target(javascript)
import gleeunit/should
@target(javascript)
import lustre/dev/query.{type Query}
@target(javascript)
import lustre/dev/simulate.{type Simulation}
@target(javascript)
import lustre/element.{type Element}

@target(javascript)
import markdown_notes_lustre

fn started() -> Simulation(
  markdown_notes_lustre.Model,
  markdown_notes_lustre.Msg,
) {
  simulate.application(
    init: markdown_notes_lustre.init,
    update: markdown_notes_lustre.update,
    view: markdown_notes_lustre.view,
  )
  |> simulate.start("status-test-room")
}

fn smoke(name: String) -> Query {
  query.element(matching: query.data("smoke", name))
}

fn find(
  view: Element(markdown_notes_lustre.Msg),
  selector: Query,
) -> Element(markdown_notes_lustre.Msg) {
  query.find(in: view, matching: selector) |> should.be_ok
}

fn should_read(
  view: Element(markdown_notes_lustre.Msg),
  name: String,
  text: String,
) -> Nil {
  view
  |> find(smoke(name))
  |> query.has(matching: query.text(text))
  |> should.be_true
}

pub fn signaling_failure_is_reported_on_screen_test() -> Nil {
  started()
  |> simulate.message(markdown_notes_lustre.SignalingFailed(
    "signaling service closed the socket",
  ))
  |> simulate.view
  |> should_read(
    "system-errors",
    "signaling · signaling service closed the socket",
  )
}

pub fn storage_durability_is_unstated_until_the_browser_answers_test() -> Nil {
  started()
  |> simulate.view
  |> should_read("storage-status", "storage · opening local snapshot…")
}

pub fn refused_persistence_is_named_as_evictable_test() -> Nil {
  started()
  |> simulate.message(markdown_notes_lustre.StorageDurability(False))
  |> simulate.view
  |> should_read(
    "storage-status",
    "storage · opening local snapshot… · evictable",
  )
}

pub fn granted_persistence_is_named_as_durable_test() -> Nil {
  started()
  |> simulate.message(markdown_notes_lustre.StorageDurability(True))
  |> simulate.view
  |> should_read(
    "storage-status",
    "storage · opening local snapshot… · durable",
  )
}
