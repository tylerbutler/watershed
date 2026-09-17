import gleam/dynamic/decode
import gleam/json
import gleam/list
import startest/expect
import watershed/channel
import watershed/crdt_core as core
import watershed/crdt_sim as sim
import watershed/crdt_wire
import watershed/or_map_kernel as kernel

fn document(replica: String) -> core.Document {
  let assert Ok(document) =
    core.new(core.config(
      room: "mv-or-map",
      compatibility: "mv-or-map/v1",
      replica: replica,
      session: replica <> "-session",
      root: channel.InitOrMap(kernel.MvRegisterMode),
    ))
  document
}

fn write(document: core.Document, key: String, value: String) -> core.Document {
  let assert Ok(#(document, _)) =
    core.edit(document, "root", channel.OrMapSetMvRegisterEdit(key, value))
  document
}

fn entries(document: core.Document) -> List(#(String, kernel.OrMapValue)) {
  let assert Ok(channel.OrMapState(state)) =
    core.channel_state(document, "root")
  kernel.entries(state)
}

fn projected_leaves(document: core.Document) -> List(#(String, String)) {
  let assert Ok([leaves]) =
    json.parse(
      core.digest_canonical_json(document),
      decode.at(
        ["channels"],
        decode.list(decode.at(
          ["state", "state", "entries"],
          decode.list({
            use key <- decode.field("key", decode.string)
            use leaf <- decode.field("value", decode.string)
            decode.success(#(key, leaf))
          }),
        )),
      ),
    )
  leaves
}

pub fn mv_or_map_digest_sorts_keys_nested_tags_and_vclocks_test() -> Nil {
  let a =
    document("a")
    |> write("z", "aaa")
    |> write("a", "zzz")
    |> write("gate", "open")
  let b = document("b") |> write("gate", "closed")
  let assert Ok(#(merged, _)) =
    core.receive(a, core.envelope(b, core.state_message(b)))
  let leaves = projected_leaves(merged)
  list.map(leaves, fn(pair) { pair.0 }) |> expect.to_equal(["a", "gate", "z"])
  list.key_find(leaves, "gate")
  |> expect.to_equal(Ok(
    "{\"state\":{\"entries\":[{\"tag\":{\"c\":1,\"r\":\"a\"},\"value\":\"open\"},{\"tag\":{\"c\":1,\"r\":\"b\"},\"value\":\"closed\"}],\"vclock\":{\"a\":1,\"b\":1}},\"type\":\"mv_register\",\"v\":1}",
  ))
  let assert Ok(#(reverse, _)) =
    core.receive(b, core.envelope(a, core.state_message(a)))
  core.digest(reverse) |> expect.to_equal(core.digest(merged))
  let assert Ok(#(imported, _)) =
    core.import_snapshot(document("loader"), core.canonical_json(merged))
  core.digest(imported) |> expect.to_equal(core.digest(merged))
}

pub fn mv_or_map_mesh_reorder_duplicate_late_join_and_reconnect_test() -> Nil {
  let mesh =
    sim.new()
    |> sim.add("a", document("a"))
    |> sim.add("b", document("b"))
    |> sim.connect("a", "b")
    |> sim.settle
    |> sim.edit("a", "root", channel.OrMapSetMvRegisterEdit("gate", "open"))
    |> sim.edit("b", "root", channel.OrMapSetMvRegisterEdit("gate", "closed"))
  let #(mesh, packets) = sim.take_queue(mesh)
  let mesh =
    mesh
    |> sim.enqueue(list.append(list.reverse(packets), packets))
    |> sim.settle
    |> sim.add("late", document("late"))
    |> sim.connect("b", "late")
    |> sim.settle
    |> sim.gossip_state
  list.each(["a", "b", "late"], fn(name) {
    entries(sim.document(mesh, name))
    |> expect.to_equal([#("gate", kernel.MvRegister(["closed", "open"]))])
    core.digest(sim.document(mesh, name))
    |> expect.to_equal(core.digest(sim.document(mesh, "a")))
  })
  let mesh =
    mesh
    |> sim.disconnect("a", "b")
    |> sim.edit("a", "root", channel.OrMapSetMvRegisterEdit("gate", "resolved"))
    |> sim.connect("a", "b")
    |> sim.settle
    |> sim.gossip_state
    |> sim.gossip_state
    |> sim.enqueue(packets)
    |> sim.settle
  list.each(["a", "b", "late"], fn(name) {
    entries(sim.document(mesh, name))
    |> expect.to_equal([#("gate", kernel.MvRegister(["resolved"]))])
    core.digest(sim.document(mesh, name))
    |> expect.to_equal(core.digest(sim.document(mesh, "a")))
  })
}

pub fn mv_or_map_digest_retains_resolution_and_removed_leaf_history_test() -> Nil {
  let a = document("a") |> write("gate", "same")
  let b = document("b") |> write("gate", "same")
  let assert Ok(#(both, _)) =
    core.receive(a, core.envelope(b, core.state_message(b)))
  entries(both)
  |> expect.to_equal([#("gate", kernel.MvRegister(["same", "same"]))])
  let resolved = write(both, "gate", "same")
  entries(resolved) |> expect.to_equal(entries(a))
  core.digest(resolved) |> expect.to_not_equal(core.digest(a))
  core.digest(resolved) |> expect.to_not_equal(core.digest(both))
  let assert Ok(#(removed, _)) =
    core.edit(resolved, "root", channel.OrMapRemoveEdit("gate"))
  entries(removed) |> expect.to_equal([])
  projected_leaves(removed) |> expect.to_equal(projected_leaves(resolved))
  core.digest(removed) |> expect.to_not_equal(core.digest(document("a")))
  let assert Ok(#(loaded, _)) =
    core.import_snapshot(document("new"), core.canonical_json(removed))
  let assert Ok(#(loaded, _)) =
    core.receive(loaded, core.envelope(b, core.state_message(b)))
  entries(loaded) |> expect.to_equal([])
  let loaded = write(loaded, "gate", "restored")
  entries(loaded)
  |> expect.to_equal([#("gate", kernel.MvRegister(["restored"]))])
}

pub fn mv_or_map_replaying_delta_under_new_message_id_is_idempotent_test() -> Nil {
  let assert Ok(#(a, outcome)) =
    core.edit(
      document("a"),
      "root",
      channel.OrMapSetMvRegisterEdit("gate", "open"),
    )
  let assert [crdt_wire.Delta(id, address, kind, operation)] = outcome.broadcast
  let b = document("b")
  let original = crdt_wire.Delta(id, address, kind, operation)
  let assert Ok(#(b, _)) = core.receive(b, core.envelope(a, original))
  let duplicate =
    crdt_wire.Delta(
      crdt_wire.MessageId(id.replica, id.counter + 1),
      address,
      kind,
      operation,
    )
  let assert Ok(#(b, result)) = core.receive(b, core.envelope(a, duplicate))
  result.events |> expect.to_equal([])
  entries(b) |> expect.to_equal([#("gate", kernel.MvRegister(["open"]))])
  core.digest(b) |> expect.to_equal(core.digest(a))
}
