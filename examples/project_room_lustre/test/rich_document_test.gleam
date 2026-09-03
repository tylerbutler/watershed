import gleam/json
import gleam/option.{None, Some}
import gleeunit/should

import watershed
import watershed/component
import watershed/rich_text
import watershed/sluice_js
import watershed/transport_js

import project_room_lustre/component_event
import project_room_lustre/rich_document

type Root

fn document(name: String) -> #(sluice_js.Sluice, watershed.Document(Root)) {
  let sluice = sluice_js.start(tenant: "default", document: name)
  let document = sluice_js.connect(sluice, "user-a")
  sluice_js.settle(sluice)
  #(sluice, document)
}

fn new_subtree(document: watershed.Document(Root)) -> watershed.SharedMap {
  let assert Ok(subtree) = watershed.create_map(document)
  subtree
}

fn invalidations() -> transport_js.Cell(Int) {
  transport_js.new_cell(0)
}

fn count_invalidation(counter: transport_js.Cell(Int)) -> fn() -> Nil {
  fn() { transport_js.set_cell(counter, transport_js.get_cell(counter) + 1) }
}

fn start(
  document: watershed.Document(Root),
  subtree: watershed.SharedMap,
  instance_id: String,
  counter: transport_js.Cell(Int),
  config: rich_document.Config,
) -> rich_document.Running {
  let outcome = transport_js.new_cell(None)
  rich_document.start(
    document,
    subtree,
    instance_id,
    count_invalidation(counter),
    config,
    fn(result) { transport_js.set_cell(outcome, Some(result)) },
  )
  let assert Some(Ok(running)) = transport_js.get_cell(outcome)
  running
}

fn insert(text: String) -> rich_text.Delta {
  let assert Ok(delta) =
    rich_text.delta_insert_text(
      rich_text.empty_delta(),
      text,
      rich_text.attributes([]),
    )
  delta
}

pub fn config_round_trips_through_running_test() -> Nil {
  let #(_sluice, document) = document("rich-document-config")
  let config = rich_document.Config(title: "Project brief")
  let running =
    start(document, new_subtree(document), "brief-1", invalidations(), config)

  rich_document.config(running) |> should.equal(config)
  rich_document.stop(running) |> should.equal(Ok(Nil))
}

pub fn initialize_attaches_rich_text_to_detached_subtree_test() -> Nil {
  let #(_sluice, document) = document("rich-document-initialize")
  let subtree = new_subtree(document)

  rich_document.initialize(document, subtree) |> should.equal(Ok(Nil))

  let assert Ok(handle) = watershed.get(subtree, "document")
  let assert Ok(channel) = watershed.resolve_rich_text(document, handle)
  watershed.rich_text_handle_of(channel) |> should.equal(handle)
  let assert Ok(contents) = watershed.rich_text_view(channel)
  rich_text.document_to_json(contents)
  |> json.to_string
  |> should.equal("[{\"insert\":\"\\n\"}]")
}

pub fn start_adopts_existing_document_handle_test() -> Nil {
  let #(_sluice, document) = document("rich-document-existing")
  let subtree = new_subtree(document)
  let assert Ok(existing) = watershed.create_rich_text(document)
  watershed.set(subtree, "document", watershed.rich_text_handle_of(existing))

  let running =
    start(
      document,
      subtree,
      "brief-1",
      invalidations(),
      rich_document.Config(title: "Project brief"),
    )

  watershed.rich_text_handle_of(rich_document.channel(running))
  |> should.equal(watershed.rich_text_handle_of(existing))
  rich_document.stop(running) |> should.equal(Ok(Nil))
}

pub fn start_is_idempotent_test() -> Nil {
  let #(_sluice, document) = document("rich-document-idempotent")
  let subtree = new_subtree(document)
  rich_document.initialize(document, subtree) |> should.equal(Ok(Nil))

  let first =
    start(
      document,
      subtree,
      "brief-1",
      invalidations(),
      rich_document.Config(title: "Project brief"),
    )
  let first_handle = watershed.rich_text_handle_of(rich_document.channel(first))
  let second =
    start(
      document,
      subtree,
      "brief-2",
      invalidations(),
      rich_document.Config(title: "Project brief"),
    )
  let assert Ok(subtree_handle) = watershed.get(subtree, "document")

  watershed.rich_text_handle_of(rich_document.channel(first))
  |> should.equal(first_handle)
  watershed.rich_text_handle_of(rich_document.channel(second))
  |> should.equal(first_handle)
  subtree_handle |> should.equal(first_handle)
  let assert Ok(contents) =
    watershed.rich_text_view(rich_document.channel(second))
  rich_text.document_to_json(contents)
  |> json.to_string
  |> should.equal("[{\"insert\":\"\\n\"}]")
  rich_document.stop(first) |> should.equal(Ok(Nil))
  rich_document.stop(second) |> should.equal(Ok(Nil))
}

pub fn replacing_document_field_rebinds_and_unsubscribes_old_channel_test() -> Nil {
  let #(_sluice, document) = document("rich-document-rebind")
  let subtree = new_subtree(document)
  let counter = invalidations()
  let running =
    start(
      document,
      subtree,
      "brief-1",
      counter,
      rich_document.Config(title: "Project brief"),
    )
  let old_channel = rich_document.channel(running)
  let assert Ok(replacement) = watershed.create_rich_text(document)

  watershed.set(subtree, "document", watershed.rich_text_handle_of(replacement))

  watershed.rich_text_handle_of(rich_document.channel(running))
  |> should.equal(watershed.rich_text_handle_of(replacement))
  let after_rebind = transport_js.get_cell(counter)
  watershed.submit_rich_text(old_channel, insert("old"))
  transport_js.get_cell(counter) |> should.equal(after_rebind)
  watershed.submit_rich_text(replacement, insert("new"))
  transport_js.get_cell(counter) |> should.equal(after_rebind + 1)
  rich_document.stop(running) |> should.equal(Ok(Nil))
}

pub fn channel_edits_emit_no_output_and_publish_emits_component_event_test() -> Nil {
  let #(_sluice, document) = document("rich-document-publish")
  let counter = invalidations()
  let running =
    start(
      document,
      new_subtree(document),
      "brief-17",
      counter,
      rich_document.Config(title: "Project brief"),
    )

  watershed.submit_rich_text(rich_document.channel(running), insert("Draft"))
  transport_js.get_cell(counter) |> should.equal(1)

  let assert #(running, [event]) = rich_document.publish(running)
  component.output_id(event) |> should.equal(component_event.emitted_port_id)
  json.parse(
    json.to_string(component.output_payload(event)),
    component_event.decoder(),
  )
  |> should.equal(
    Ok(component_event.Event(
      source_instance_id: "brief-17",
      source_kind: "project-room/rich-document",
      source_title: "Project brief",
      action: component_event.Published,
      detail: "Published an update",
    )),
  )
  rich_document.stop(running) |> should.equal(Ok(Nil))
}

pub fn stop_unsubscribes_channel_and_subtree_test() -> Nil {
  let #(_sluice, document) = document("rich-document-stop")
  let subtree = new_subtree(document)
  let counter = invalidations()
  let running =
    start(
      document,
      subtree,
      "brief-1",
      counter,
      rich_document.Config(title: "Project brief"),
    )
  let channel = rich_document.channel(running)
  rich_document.stop(running) |> should.equal(Ok(Nil))
  let after_stop = transport_js.get_cell(counter)

  watershed.submit_rich_text(channel, insert("stopped"))
  let assert Ok(replacement) = watershed.create_rich_text(document)
  watershed.set(subtree, "document", watershed.rich_text_handle_of(replacement))

  transport_js.get_cell(counter) |> should.equal(after_stop)
}
