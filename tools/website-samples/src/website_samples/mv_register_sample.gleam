//// Typed MV-register examples for the revision slate.

import gleam/result
import watershed
import watershed/crdt_js
import watershed/p2p
import watershed/p2p_transport_js.{type Signaling}
import watershed/schema

// docs:snippet-start mv-register-sequenced
pub type RevisionSheet

pub fn revision() -> schema.ChannelField(
  RevisionSheet,
  schema.MvRegisterChannel,
) {
  schema.channel_field("revision")
}

pub fn ensure_and_revise(
  document: watershed.Document(RevisionSheet),
  text: String,
  done: fn(Result(List(String), String)) -> Nil,
) -> Nil {
  // Ensure waits for synchronization before it reads or creates the field.
  use ensured <- watershed.ensure_mv_register(
    document,
    watershed.root_typed(document),
    revision(),
  )
  let values = {
    use register <- result.try(ensured)
    watershed.mv_register_set(register, text)
    watershed.mv_register_values(register)
    |> result.map_error(fn(_) { "Could not read revision alternatives" })
  }
  done(values)
}

// docs:snippet-end mv-register-sequenced

// docs:snippet-start mv-register-p2p
pub fn configure(
  signaling: Signaling,
) -> crdt_js.Config(schema.MvRegisterChannel) {
  crdt_js.config(
    room_id: "revision-slate",
    replica_label: "field-crew",
    compatibility_tag: "revision-slate/v1",
    root: p2p.mv_register_root(),
    signaling: signaling,
  )
  |> crdt_js.with_transport_policy(crdt_js.P2pOnly)
}

// Call after readiness succeeds. Use this for an intentional user edit.
pub fn revise(
  document: crdt_js.CrdtDocument(schema.MvRegisterChannel),
  text: String,
) -> Result(List(String), p2p.P2pError) {
  let register = crdt_js.root(document)
  use _ <- result.try(crdt_js.mv_register_set(register, text))
  crdt_js.mv_register_values(register)
}
// docs:snippet-end mv-register-p2p
