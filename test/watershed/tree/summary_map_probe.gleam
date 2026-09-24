//// Loads an upstream summary with a split SharedMap value on either target.

import envoy
import gleam/json
import gleam/list
import gleam/option.{None}
import simplifile
import watershed/channel
import watershed/fluid_ids
import watershed/runtime_core
import watershed/tree/runtime_fixture
import watershed/wire
import watershed/wire/fluid_document

pub fn main() {
  let assert Ok(path) = envoy.get("WATERSHED_TREE_MAP_SNAPSHOT")
  let assert Ok(expected) = envoy.get("WATERSHED_TREE_MAP_VALUE")
  let assert Ok(raw) = simplifile.read(path)
  let assert Ok(snapshot) = json.parse(raw, wire.json_value_decoder())
  let assert Ok(hierarchy) = runtime_fixture.read_snapshot(snapshot)
  let assert Ok(session) =
    fluid_ids.session_id("70000000-0000-4000-8000-000000000007")
  let assert Ok(view) =
    fluid_ids.stable_id("60000000-0000-4000-8000-000000000006")
  let assert Ok(summary) = fluid_document.decode(hierarchy, None, session, view)
  let assert Ok(root_store) =
    list.key_find(fluid_document.aliases(summary), "root")
  let assert [address] =
    list.flat_map(fluid_document.datastores(summary), fn(store) {
      case store.id == root_store {
        True ->
          list.flat_map(store.channels, fn(item) {
            case item.snapshot {
              channel.MapSnapshot(_) -> [store.id <> "/" <> item.id]
              _ -> []
            }
          })
        False -> []
      }
    })
  let assert Ok(runtime_core.Complete(core)) =
    runtime_core.bootstrap_document(
      runtime_fixture.connected(
        "reader",
        [],
        fluid_document.sequence_number(summary),
      ),
      summary,
    )
  let assert Ok(value) = runtime_core.get(core, address, "large")
  let assert True = value == json.string(expected)
  let assert Ok(encoded) = fluid_document.encode(summary)
  let assert Ok(restored) = fluid_document.decode(encoded, None, session, view)
  let assert Ok(runtime_core.Complete(core)) =
    runtime_core.bootstrap_document(
      runtime_fixture.connected(
        "reader",
        [],
        fluid_document.sequence_number(restored),
      ),
      restored,
    )
  let assert Ok(value) = runtime_core.get(core, address, "large")
  let assert True = value == json.string(expected)
  Nil
}
