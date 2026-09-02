//// CRDT document configuration sample for `/runtime/p2p`.
////
//// Shows `crdt_js.config` with transport policy and sequencer options.
//// This is a fixture: signaling is a function parameter; the module
//// compiles but is not wired to a real transport.

import watershed/crdt_js
import watershed/p2p
import watershed/p2p_transport_js.{type Signaling}
import watershed/schema

// docs:snippet-start p2p-config
fn p2p_config(signaling: Signaling) -> crdt_js.Config(schema.PnCounterChannel) {
  // Auto starts on WebRTC and attempts the relay in parallel — it never
  // waits for one, and prefers it while healthy.
  let config =
    crdt_js.config(
      room_id: "retro-board-9c2",
      replica_label: "ada",
      compatibility_tag: "retro-board/v1",
      root: p2p.pn_counter_root(),
      signaling: signaling,
    )
    |> crdt_js.with_transport_policy(crdt_js.Auto)
    |> crdt_js.with_sequencer(crdt_js.sequencer("wss://relay.example/room"))
  config
}
// docs:snippet-end p2p-config
