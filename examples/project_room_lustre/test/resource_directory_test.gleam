import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import gleeunit/should

import watershed
import watershed/component
import watershed/sluice_js
import watershed/transport_js

import project_room_lustre/component_event
import project_room_lustre/resource_directory

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

fn start(
  document: watershed.Document(Root),
  subtree: watershed.SharedMap,
  instance_id: String,
  invalidations: transport_js.Cell(Int),
) -> resource_directory.Running {
  let outcome = transport_js.new_cell(None)
  resource_directory.start(
    document,
    subtree,
    instance_id,
    fn() {
      transport_js.set_cell(
        invalidations,
        transport_js.get_cell(invalidations) + 1,
      )
    },
    resource_directory.Config(title: "Resources"),
    fn(result) { transport_js.set_cell(outcome, Some(result)) },
  )
  let assert Some(Ok(running)) = transport_js.get_cell(outcome)
  running
}

fn event_action(event: component.OutputEvent) -> component_event.Event {
  let assert Ok(decoded) =
    json.parse(
      json.to_string(component.output_payload(event)),
      component_event.decoder(),
    )
  decoded
}

fn sorted_strings(values: List(String)) -> List(String) {
  list.sort(values, string.compare)
}

fn assert_client_entries(
  running_a: resource_directory.Running,
  running_b: resource_directory.Running,
  expected: List(resource_directory.Entry),
) -> Nil {
  [
    resource_directory.entries(running_a),
    resource_directory.entries(running_b),
  ]
  |> should.equal([expected, expected])
}

fn assert_invalidated(counter: transport_js.Cell(Int), before: Int) -> Nil {
  should.be_true(transport_js.get_cell(counter) > before)
}

pub fn config_round_trips_test() -> Nil {
  let config = resource_directory.Config(title: "Resources")
  json.parse(
    json.to_string(resource_directory.encode_config(config)),
    resource_directory.config_decoder(),
  )
  |> should.equal(Ok(config))
}

pub fn config_rejects_missing_or_non_string_title_test() -> Nil {
  json.parse("{}", resource_directory.config_decoder())
  |> result.is_error
  |> should.be_true
  json.parse("{\"title\":17}", resource_directory.config_decoder())
  |> result.is_error
  |> should.be_true
}

pub fn initialize_attaches_directory_to_detached_subtree_test() -> Nil {
  let #(_sluice, document) = document("resource-directory-initialize")
  let subtree = new_subtree(document)

  resource_directory.initialize(document, subtree) |> should.equal(Ok(Nil))

  let assert Ok(handle) = watershed.get(subtree, "tree")
  let assert Ok(directory) = watershed.resolve_directory(document, handle)
  watershed.directory_subdirectories(directory, "/")
  |> should.equal([])
}

pub fn start_adopts_existing_directory_handle_test() -> Nil {
  let #(_sluice, document) = document("resource-directory-existing")
  let subtree = new_subtree(document)
  let assert Ok(directory) = watershed.create_directory(document)
  watershed.set(subtree, "tree", watershed.directory_handle_of(directory))
  let running =
    start(document, subtree, "resources-1", transport_js.new_cell(0))

  let assert Ok(#(running, _)) =
    resource_directory.create_folder(running, "design")
  resource_directory.folders(running) |> should.equal(["design"])
}

pub fn start_is_idempotent_test() -> Nil {
  let #(_sluice, document) = document("resource-directory-idempotent")
  let subtree = new_subtree(document)
  resource_directory.initialize(document, subtree) |> should.equal(Ok(Nil))
  let first = start(document, subtree, "resources-1", transport_js.new_cell(0))
  let second = start(document, subtree, "resources-2", transport_js.new_cell(0))

  let assert Ok(#(_first, _)) =
    resource_directory.create_folder(first, "design")
  resource_directory.folders(second) |> should.equal(["design"])
}

pub fn replacing_tree_field_rebinds_and_unsubscribes_old_directory_test() -> Nil {
  let #(_sluice, document) = document("resource-directory-rebind")
  let subtree = new_subtree(document)
  let counter = transport_js.new_cell(0)
  let running = start(document, subtree, "resources-1", counter)
  let assert Ok(original) =
    watershed.resolve_directory(
      document,
      watershed.get(subtree, "tree")
        |> result.unwrap(json.null()),
    )
  let assert Ok(replacement) = watershed.create_directory(document)
  watershed.set(subtree, "tree", watershed.directory_handle_of(replacement))

  watershed.directory_create_subdirectory(replacement, "/", "new")
  resource_directory.folders(running) |> should.equal(["new"])
  let after_rebind = transport_js.get_cell(counter)

  watershed.directory_create_subdirectory(original, "/", "old")
  transport_js.get_cell(counter) |> should.equal(after_rebind)
  resource_directory.folders(running) |> should.equal(["new"])
}

pub fn replacing_tree_field_resets_nested_path_before_mutation_test() -> Nil {
  let #(_sluice, document) = document("resource-directory-rebind-path")
  let subtree = new_subtree(document)
  let running =
    start(document, subtree, "resources-1", transport_js.new_cell(0))
  let assert Ok(#(running, [_])) =
    resource_directory.create_folder(running, "design")
  let assert Ok(running) = resource_directory.open_folder(running, "design")
  resource_directory.path(running) |> should.equal("/design")

  let assert Ok(replacement) = watershed.create_directory(document)
  watershed.set(subtree, "tree", watershed.directory_handle_of(replacement))
  resource_directory.path(running) |> should.equal("/")

  let assert Ok(#(running, [event])) =
    resource_directory.create_folder(running, "drafts")
  event_action(event).detail |> should.equal("Created folder /drafts")
  resource_directory.folders(running) |> should.equal(["drafts"])
  watershed.directory_subdirectories(replacement, "/")
  |> should.equal(["drafts"])
}

pub fn stop_unsubscribes_directory_and_subtree_test() -> Nil {
  let #(_sluice, document) = document("resource-directory-stop")
  let subtree = new_subtree(document)
  let counter = transport_js.new_cell(0)
  let running = start(document, subtree, "resources-1", counter)
  let assert Ok(handle) = watershed.get(subtree, "tree")
  let assert Ok(directory) = watershed.resolve_directory(document, handle)
  resource_directory.stop(running) |> should.equal(Ok(Nil))
  let after_stop = transport_js.get_cell(counter)

  watershed.directory_create_subdirectory(directory, "/", "late")
  watershed.directory_set(directory, "/", "key", json.string("late"))
  transport_js.get_cell(counter) |> should.equal(after_stop)
  resource_directory.stop(running) |> should.equal(Ok(Nil))
}

pub fn root_and_nested_navigation_is_absolute_test() -> Nil {
  let #(_sluice, document) = document("resource-directory-navigation")
  let subtree = new_subtree(document)
  resource_directory.initialize(document, subtree) |> should.equal(Ok(Nil))
  let running =
    start(document, subtree, "resources-1", transport_js.new_cell(0))
  let assert Ok(#(running, _)) =
    resource_directory.create_folder(running, "design")
  let assert Ok(running) = resource_directory.open_folder(running, "design")
  resource_directory.path(running) |> should.equal("/design")
  let assert Ok(#(running, _)) =
    resource_directory.create_folder(running, "drafts")
  let assert Ok(running) = resource_directory.open_folder(running, "drafts")
  resource_directory.path(running) |> should.equal("/design/drafts")
  resource_directory.open_parent(running)
  |> resource_directory.path
  |> should.equal("/design")
  resource_directory.open_parent(running)
  |> resource_directory.open_parent
  |> resource_directory.path
  |> should.equal("/")
}

pub fn invalid_names_are_rejected_before_mutation_test() -> Nil {
  let #(_sluice, document) = document("resource-directory-names")
  let subtree = new_subtree(document)
  resource_directory.initialize(document, subtree) |> should.equal(Ok(Nil))
  let running =
    start(document, subtree, "resources-1", transport_js.new_cell(0))

  resource_directory.create_folder(running, "")
  |> result.is_error
  |> should.be_true
  resource_directory.create_folder(running, "a/b")
  |> result.is_error
  |> should.be_true
  resource_directory.set_entry(running, "", "value")
  |> result.is_error
  |> should.be_true
  resource_directory.set_entry(running, "a/b", "value")
  |> result.is_error
  |> should.be_true
  resource_directory.delete_folder(running, "")
  |> result.is_error
  |> should.be_true
  resource_directory.delete_entry(running, "a/b")
  |> result.is_error
  |> should.be_true
  resource_directory.folders(running) |> should.equal([])
  resource_directory.entries(running) |> should.equal([])
}

pub fn string_entries_are_sorted_and_unknown_json_is_omitted_test() -> Nil {
  let #(_sluice, document) = document("resource-directory-entries")
  let subtree = new_subtree(document)
  resource_directory.initialize(document, subtree) |> should.equal(Ok(Nil))
  let running =
    start(document, subtree, "resources-1", transport_js.new_cell(0))
  let assert Ok(handle) = watershed.get(subtree, "tree")
  let assert Ok(directory) = watershed.resolve_directory(document, handle)
  watershed.directory_set(directory, "/", "unknown", json.int(7))
  let assert Ok(#(running, _)) =
    resource_directory.set_entry(running, "zeta", "last")
  let assert Ok(#(running, _)) =
    resource_directory.set_entry(running, "alpha", "first")

  resource_directory.entries(running)
  |> should.equal([
    resource_directory.Entry(key: "alpha", value: "first"),
    resource_directory.Entry(key: "zeta", value: "last"),
  ])
  watershed.directory_get(directory, "/", "unknown")
  |> should.equal(Ok(json.int(7)))
}

pub fn create_update_and_delete_return_one_local_activity_event_test() -> Nil {
  let #(_sluice, document) = document("resource-directory-output")
  let subtree = new_subtree(document)
  resource_directory.initialize(document, subtree) |> should.equal(Ok(Nil))
  let running =
    start(document, subtree, "resources-17", transport_js.new_cell(0))

  let assert Ok(#(running, [folder_event])) =
    resource_directory.create_folder(running, "design")
  event_action(folder_event)
  |> should.equal(component_event.Event(
    source_instance_id: "resources-17",
    source_kind: "project-room/resource-directory",
    source_title: "Resources",
    action: component_event.FolderChanged,
    detail: "Created folder /design",
  ))
  let assert Ok(running) = resource_directory.open_folder(running, "design")
  let assert Ok(#(running, [entry_event])) =
    resource_directory.set_entry(running, "status", "draft")
  event_action(entry_event)
  |> should.equal(component_event.Event(
    source_instance_id: "resources-17",
    source_kind: "project-room/resource-directory",
    source_title: "Resources",
    action: component_event.EntryChanged,
    detail: "Updated /design/status",
  ))
  let assert Ok(#(running, [update_event])) =
    resource_directory.set_entry(running, "status", "ready")
  event_action(update_event).action
  |> should.equal(component_event.EntryChanged)
  let assert Ok(#(running, [delete_entry_event])) =
    resource_directory.delete_entry(running, "status")
  event_action(delete_entry_event).detail
  |> should.equal("Deleted /design/status")
  resource_directory.entries(running) |> should.equal([])
  let running = resource_directory.open_parent(running)
  let assert Ok(#(_running, [delete_folder_event])) =
    resource_directory.delete_folder(running, "design")
  event_action(delete_folder_event).detail
  |> should.equal("Deleted folder /design")
  resource_directory.folders(running) |> should.equal([])
}

pub fn replicated_deletion_returns_browsing_client_to_root_test() -> Nil {
  let sluice =
    sluice_js.start(tenant: "default", document: "resource-directory-delete")
  let document_a = sluice_js.connect(sluice, "user-a")
  let document_b = sluice_js.connect(sluice, "user-b")
  sluice_js.settle(sluice)
  let subtree_a = new_subtree(document_a)
  resource_directory.initialize(document_a, subtree_a) |> should.equal(Ok(Nil))
  watershed.set(
    watershed.root(document_a),
    "resource-subtree",
    watershed.handle_of(subtree_a),
  )
  sluice_js.settle(sluice)
  let assert Ok(subtree_handle) =
    watershed.get(watershed.root(document_b), "resource-subtree")
  let assert Ok(subtree_b) = watershed.resolve(document_b, subtree_handle)
  let assert Ok(tree_a) = watershed.get(subtree_a, "tree")
  let assert Ok(tree_b) = watershed.get(subtree_b, "tree")
  tree_b |> should.equal(tree_a)
  let invalidations_a = transport_js.new_cell(0)
  let invalidations_b = transport_js.new_cell(0)
  let running_a = start(document_a, subtree_a, "resources-a", invalidations_a)
  let running_b = start(document_b, subtree_b, "resources-b", invalidations_b)
  let before_create_b = transport_js.get_cell(invalidations_b)
  let assert Ok(#(running_a, [create_event])) =
    resource_directory.create_folder(running_a, "design")
  event_action(create_event)
  |> should.equal(component_event.Event(
    source_instance_id: "resources-a",
    source_kind: "project-room/resource-directory",
    source_title: "Resources",
    action: component_event.FolderChanged,
    detail: "Created folder /design",
  ))
  sluice_js.settle(sluice)
  resource_directory.folders(running_a) |> should.equal(["design"])
  resource_directory.folders(running_b) |> should.equal(["design"])
  let _ = assert_client_entries(running_a, running_b, [])

  let _ = assert_invalidated(invalidations_b, before_create_b)
  let assert Ok(running_b) = resource_directory.open_folder(running_b, "design")
  let before_delete_b = transport_js.get_cell(invalidations_b)
  let assert Ok(#(_running_a, [delete_event])) =
    resource_directory.delete_folder(running_a, "design")
  event_action(delete_event)
  |> should.equal(component_event.Event(
    source_instance_id: "resources-a",
    source_kind: "project-room/resource-directory",
    source_title: "Resources",
    action: component_event.FolderChanged,
    detail: "Deleted folder /design",
  ))
  resource_directory.path(running_b) |> should.equal("/design")
  sluice_js.settle(sluice)
  resource_directory.path(running_b) |> should.equal("/")
  resource_directory.folders(running_a) |> should.equal([])
  resource_directory.folders(running_b) |> should.equal([])
  let _ = assert_client_entries(running_a, running_b, [])

  let _ = assert_invalidated(invalidations_b, before_delete_b)
}

pub fn two_clients_converge_disjoint_edits_and_same_name_create_test() -> Nil {
  let sluice =
    sluice_js.start(tenant: "default", document: "resource-directory-converge")
  let document_a = sluice_js.connect(sluice, "user-a")
  let document_b = sluice_js.connect(sluice, "user-b")
  sluice_js.settle(sluice)
  let subtree_a = new_subtree(document_a)
  resource_directory.initialize(document_a, subtree_a) |> should.equal(Ok(Nil))
  watershed.set(
    watershed.root(document_a),
    "resource-subtree",
    watershed.handle_of(subtree_a),
  )
  sluice_js.settle(sluice)
  let assert Ok(subtree_handle) =
    watershed.get(watershed.root(document_b), "resource-subtree")
  let assert Ok(subtree_b) = watershed.resolve(document_b, subtree_handle)
  let assert Ok(tree_a) = watershed.get(subtree_a, "tree")
  let assert Ok(tree_b) = watershed.get(subtree_b, "tree")
  tree_b |> should.equal(tree_a)
  let invalidations_a = transport_js.new_cell(0)
  let invalidations_b = transport_js.new_cell(0)
  let running_a = start(document_a, subtree_a, "resources-a", invalidations_a)
  let running_b = start(document_b, subtree_b, "resources-b", invalidations_b)

  let before_design_b = transport_js.get_cell(invalidations_b)
  let assert Ok(#(running_a, [design_event])) =
    resource_directory.create_folder(running_a, "design")
  event_action(design_event)
  |> should.equal(component_event.Event(
    source_instance_id: "resources-a",
    source_kind: "project-room/resource-directory",
    source_title: "Resources",
    action: component_event.FolderChanged,
    detail: "Created folder /design",
  ))
  sluice_js.settle(sluice)
  resource_directory.folders(running_a) |> should.equal(["design"])
  resource_directory.folders(running_b) |> should.equal(["design"])
  let _ = assert_client_entries(running_a, running_b, [])

  let _ = assert_invalidated(invalidations_b, before_design_b)

  let before_owner_b = transport_js.get_cell(invalidations_b)
  let assert Ok(#(running_a, [owner_event])) =
    resource_directory.set_entry(running_a, "owner", "a")
  event_action(owner_event)
  |> should.equal(component_event.Event(
    source_instance_id: "resources-a",
    source_kind: "project-room/resource-directory",
    source_title: "Resources",
    action: component_event.EntryChanged,
    detail: "Updated /owner",
  ))
  sluice_js.settle(sluice)
  let _ =
    assert_client_entries(running_a, running_b, [
      resource_directory.Entry(key: "owner", value: "a"),
    ])

  let _ = assert_invalidated(invalidations_b, before_owner_b)

  let before_status_a = transport_js.get_cell(invalidations_a)
  let assert Ok(#(running_b, [status_event])) =
    resource_directory.set_entry(running_b, "status", "b")
  event_action(status_event)
  |> should.equal(component_event.Event(
    source_instance_id: "resources-b",
    source_kind: "project-room/resource-directory",
    source_title: "Resources",
    action: component_event.EntryChanged,
    detail: "Updated /status",
  ))
  sluice_js.settle(sluice)
  let _ =
    assert_client_entries(running_a, running_b, [
      resource_directory.Entry(key: "owner", value: "a"),
      resource_directory.Entry(key: "status", value: "b"),
    ])

  let _ = assert_invalidated(invalidations_a, before_status_a)

  sluice_js.pause(sluice, document_b)
  let before_shared_a = transport_js.get_cell(invalidations_a)
  let assert Ok(#(running_a, [shared_a_event])) =
    resource_directory.create_folder(running_a, "shared")
  let assert Ok(#(running_b, [shared_b_event])) =
    resource_directory.create_folder(running_b, "shared")
  event_action(shared_a_event)
  |> should.equal(component_event.Event(
    source_instance_id: "resources-a",
    source_kind: "project-room/resource-directory",
    source_title: "Resources",
    action: component_event.FolderChanged,
    detail: "Created folder /shared",
  ))
  event_action(shared_b_event)
  |> should.equal(component_event.Event(
    source_instance_id: "resources-b",
    source_kind: "project-room/resource-directory",
    source_title: "Resources",
    action: component_event.FolderChanged,
    detail: "Created folder /shared",
  ))
  sluice_js.settle(sluice)
  sluice_js.resume(sluice, document_b)
  sluice_js.settle(sluice)
  resource_directory.folders(running_a)
  |> sorted_strings
  |> should.equal(["design", "shared"])
  resource_directory.folders(running_b)
  |> sorted_strings
  |> should.equal(["design", "shared"])
  let _ =
    assert_client_entries(running_a, running_b, [
      resource_directory.Entry(key: "owner", value: "a"),
      resource_directory.Entry(key: "status", value: "b"),
    ])
  let _ = assert_invalidated(invalidations_a, before_shared_a)
  let _ = assert_invalidated(invalidations_a, before_shared_a)
}
