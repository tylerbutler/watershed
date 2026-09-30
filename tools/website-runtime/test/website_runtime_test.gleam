import gleeunit
import watershed
import watershed/json_ot
import watershed/sluice_js
import website_runtime

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn bootstraps_the_atlas_counter_core_test() -> Nil {
  let assert Ok(core) =
    website_runtime.counter_core("demo-client-a", "sandbags-counter", 120)
  let assert Ok(120) = website_runtime.counter_value(core, "sandbags-counter")
  let assert Ok(website_runtime.CounterChange(next, write)) =
    website_runtime.counter_increment(core, "sandbags-counter", 5)
  let website_runtime.CounterPending(count, delta) =
    website_runtime.counter_pending(next, "sandbags-counter")
  let assert 1 = count
  let assert 5 = delta
  let assert Ok(125) = website_runtime.counter_value(next, "sandbags-counter")
  let assert Ok(delivered) =
    website_runtime.deliver_counter(next, "demo-client-a", 1, write)
  let assert Ok(125) =
    website_runtime.counter_value(delivered, "sandbags-counter")
  let website_runtime.CounterPending(count, delta) =
    website_runtime.counter_pending(delivered, "sandbags-counter")
  let assert 0 = count
  let assert 0 = delta
  Nil
}

pub fn converts_json_ot_values_test() -> Nil {
  let assert Ok(value) =
    website_runtime.json_ot_parse(
      "{\"site\":\"Mill Race\",\"crew\":[\"Ada\",\"Ben\"],\"stage\":24}",
    )
  let assert "{\"crew\":[\"Ada\",\"Ben\"],\"site\":\"Mill Race\",\"stage\":24}" =
    website_runtime.json_ot_stringify(value)
  let assert Error("invalid JSON") = website_runtime.json_ot_parse("{")
  Nil
}

pub fn constructs_json_ot_path_keys_and_integers_test() -> Nil {
  let key = website_runtime.json_ot_key("gauge")
  let index = website_runtime.json_ot_index(2)
  let integer = website_runtime.json_ot_integer(-1)
  let assert Ok("gauge") = website_runtime.json_ot_key_value(key)
  let assert Ok(2) = website_runtime.json_ot_index_value(index)
  let assert Ok(-1) = website_runtime.json_ot_integer_value(integer)
  let assert Error("JSON-OT path is not an object key") =
    website_runtime.json_ot_key_value(index)
  let assert Error("JSON-OT path is not an array index") =
    website_runtime.json_ot_index_value(key)
  let assert Error("JSON-OT number is not an integer") =
    website_runtime.json_ot_integer_value(json_ot.NFloat(1.5))
  Nil
}

pub fn creates_and_decodes_register_or_maps_test() -> Nil {
  let rig =
    sluice_js.start(tenant: "default", document: "website-runtime-register")
  let document = sluice_js.connect(rig, "a")
  sluice_js.settle(rig)
  let assert Ok(or_map) = website_runtime.create_register_or_map(document)
  watershed.or_map_set(or_map, "note-1", "ship week went smoothly")
  let assert Ok([entry]) = website_runtime.register_entries(or_map)
  let assert website_runtime.RegisterEntry(
    key: "note-1",
    value: "ship week went smoothly",
  ) = website_runtime.read_register_entry(entry)
  Nil
}

pub fn creates_and_decodes_tally_or_maps_test() -> Nil {
  let rig =
    sluice_js.start(tenant: "default", document: "website-runtime-tally")
  let document = sluice_js.connect(rig, "a")
  sluice_js.settle(rig)
  let assert Ok(or_map) = website_runtime.create_tally_or_map(document)
  watershed.or_map_increment(or_map, "note-1", 2)
  let assert Ok([entry]) = website_runtime.tally_entries(or_map)
  let assert website_runtime.TallyEntry(key: "note-1", value: 2) =
    website_runtime.read_tally_entry(entry)
  Nil
}

pub fn rejects_wrong_or_map_entry_modes_test() -> Nil {
  let rig =
    sluice_js.start(tenant: "default", document: "website-runtime-wrong-mode")
  let document = sluice_js.connect(rig, "a")
  sluice_js.settle(rig)

  let assert Ok(tally) = website_runtime.create_tally_or_map(document)
  watershed.or_map_increment(tally, "votes", 1)
  let assert Error("register OR-map contains tally value at key: votes") =
    website_runtime.register_entries(tally)

  let assert Ok(register) = website_runtime.create_register_or_map(document)
  watershed.or_map_set(register, "notes", "ready")
  let assert Error("tally OR-map contains register value at key: notes") =
    website_runtime.tally_entries(register)
  Nil
}

pub fn exposes_seeded_shared_tree_checklists_test() -> Nil {
  let assert Ok(seed) = website_runtime.shared_tree_checklist_seed()
  let rig =
    sluice_js.start(
      tenant: "default",
      document: "website-runtime-shared-tree-checklist",
    )
  let document_a = sluice_js.connect_seeded(rig, "a", seed)
  let document_b = sluice_js.connect_seeded(rig, "b", seed)
  sluice_js.settle(rig)

  let assert Ok(checklist_a) =
    website_runtime.open_shared_tree_checklist(document_a)
  let assert Ok(checklist_b) =
    website_runtime.open_shared_tree_checklist(document_b)
  let baseline = [
    website_runtime.SharedTreeChecklistItem(
      "inspect-spillway",
      "inspect spillway",
      False,
    ),
    website_runtime.SharedTreeChecklistItem(
      "review-field-notes",
      "review field notes",
      False,
    ),
    website_runtime.SharedTreeChecklistItem(
      "publish-survey",
      "publish survey",
      False,
    ),
  ]
  let assert Ok(items_a) =
    website_runtime.shared_tree_checklist_items(checklist_a)
  let assert Ok(items_b) =
    website_runtime.shared_tree_checklist_items(checklist_b)
  let assert True = items_a == baseline
  let assert True = items_b == baseline

  let assert Ok(Nil) =
    website_runtime.shared_tree_checklist_move_up(
      checklist_a,
      "inspect-spillway",
    )
  let assert Ok(Nil) =
    website_runtime.shared_tree_checklist_toggle(
      checklist_a,
      "review-field-notes",
    )
  let assert Ok(Nil) =
    website_runtime.shared_tree_checklist_toggle(
      checklist_a,
      "review-field-notes",
    )

  let assert Ok(Nil) =
    website_runtime.shared_tree_checklist_add(
      checklist_a,
      "mark-low-ford",
      "mark low ford",
    )
  sluice_js.settle(rig)

  let assert Ok(Nil) =
    website_runtime.shared_tree_checklist_edit(
      checklist_a,
      "publish-survey",
      "publish revised survey",
    )
  let assert Ok(Nil) =
    website_runtime.shared_tree_checklist_move_down(
      checklist_b,
      "inspect-spillway",
    )
  sluice_js.settle(rig)

  let expected = [
    website_runtime.SharedTreeChecklistItem(
      "review-field-notes",
      "review field notes",
      False,
    ),
    website_runtime.SharedTreeChecklistItem(
      "inspect-spillway",
      "inspect spillway",
      False,
    ),
    website_runtime.SharedTreeChecklistItem(
      "publish-survey",
      "publish revised survey",
      False,
    ),
    website_runtime.SharedTreeChecklistItem(
      "mark-low-ford",
      "mark low ford",
      False,
    ),
  ]
  let assert Ok(items_a) =
    website_runtime.shared_tree_checklist_items(checklist_a)
  let assert Ok(items_b) =
    website_runtime.shared_tree_checklist_items(checklist_b)
  let assert True = items_a == expected
  let assert True = items_b == expected
  Nil
}
