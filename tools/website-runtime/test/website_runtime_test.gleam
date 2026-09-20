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
  let assert Ok(delivered) =
    website_runtime.deliver_counter(next, "demo-client-a", 1, write)
  let assert Ok(125) =
    website_runtime.counter_value(delivered, "sandbags-counter")
  Nil
}

pub fn converts_json_ot_values_test() -> Nil {
  let assert Ok(value) =
    website_runtime.json_ot_parse(
      "{\"site\":\"Mill Race\",\"crew\":[\"Ada\",\"Ben\"],\"stage\":24}",
    )
  let assert "{\"crew\":[\"Ada\",\"Ben\"],\"site\":\"Mill Race\",\"stage\":24}" =
    website_runtime.json_ot_stringify(value)
  Nil
}

pub fn constructs_json_ot_path_keys_and_integers_test() -> Nil {
  let assert json_ot.Key("gauge") = website_runtime.json_ot_key("gauge")
  let assert json_ot.Index(2) = website_runtime.json_ot_index(2)
  let assert json_ot.NInt(-1) = website_runtime.json_ot_integer(-1)
  Nil
}

pub fn creates_and_decodes_register_or_maps_test() -> Nil {
  let rig =
    sluice_js.start(tenant: "default", document: "website-runtime-register")
  let document = sluice_js.connect(rig, "a")
  sluice_js.settle(rig)
  let assert Ok(or_map) = website_runtime.create_register_or_map(document)
  watershed.or_map_set(or_map, "note-1", "ship week went smoothly")
  let assert Ok([#("note-1", "ship week went smoothly")]) =
    website_runtime.register_entries(or_map)
  Nil
}

pub fn creates_and_decodes_tally_or_maps_test() -> Nil {
  let rig =
    sluice_js.start(tenant: "default", document: "website-runtime-tally")
  let document = sluice_js.connect(rig, "a")
  sluice_js.settle(rig)
  let assert Ok(or_map) = website_runtime.create_tally_or_map(document)
  watershed.or_map_increment(or_map, "note-1", 2)
  let assert Ok([#("note-1", 2)]) = website_runtime.tally_entries(or_map)
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
