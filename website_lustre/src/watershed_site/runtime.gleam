pub type Doc {
  Doc(slug: String, title: String, gloss: String, concept: String)
}

pub fn all() -> List(Doc) {
  [
    Doc(
      "optimistic",
      "Optimistic edits",
      "Show a local edit the instant it happens, reconcile it when the server sequences it, and unwind it cleanly if it loses.",
      "apply · pending → ack_local → sequenced",
    ),
    Doc(
      "reconnect",
      "Reconnect & resync",
      "Drop the link and rejoin the flow. A returning client rehydrates from a summary (the same path a fresh client boots from).",
      "from_summary · replay · catch-up",
    ),
    Doc(
      "redelivery",
      "Idempotent re-delivery",
      "Why a re-sent delta lands as a non-event: the runtime's sequence-number check drops it, or an idempotent merge absorbs it.",
      "re-deliver · dedupe · absorb",
    ),
    Doc(
      "presence",
      "Presence & ripples",
      "The ephemeral tier beside your state: throwaway broadcasts, and the roster built on them (connection-backed where the server offers it, heartbeat-and-TTL where it does not).",
      "submit_ripple · sessions · server or heartbeat",
    ),
    Doc(
      "p2p",
      "Peer-to-peer over WebRTC",
      "A document that runs on a WebRTC mesh with no sequencer at all. Eligible structures merge instead of ordering, and a relay can attach later for durability without changing the document's state or handles.",
      "CrdtDocument · Auto / SequencedOnly / P2pOnly · crdt_relay_v1",
    ),
  ]
}
