//// Deterministic tests for `p2p_transport_ffi.mjs` itself, the module that
//// holds the browser's promises.
////
//// `p2p_transport_js_test.gleam` substitutes the whole `Rtc` seam, which is
//// where negotiation policy lives and where a Gleam fake belongs. It cannot
//// reach the FFI's own bookkeeping: which connection a settled promise
//// belongs to, and whether an inbound data channel is one of ours. Those are
//// what these tests pin down, through the synchronous fake browser in
//// `p2p_ffi_harness.mjs` — no real `RTCPeerConnection`, no waiting, no
//// browser.
////
//// The scenario that matters is a peer closing and rejoining under the same
//// ID while an operation is in flight. A peer ID is not an identity, so a
//// continuation that outlived its connection must not hand the new peer the
//// old one's SDP, remote description, or failure.

@target(javascript)
import gleam/list
@target(javascript)
import startest/expect

@target(javascript)
import watershed/p2p_transport_js

@target(javascript)
@external(javascript, "./p2p_ffi_harness.mjs", "liveContinuation")
fn live_continuation(stage: String) -> String

@target(javascript)
@external(javascript, "./p2p_ffi_harness.mjs", "staleContinuation")
fn stale_continuation(stage: String) -> String

@target(javascript)
@external(javascript, "./p2p_ffi_harness.mjs", "closedContinuation")
fn closed_continuation(stage: String) -> String

@target(javascript)
@external(javascript, "./p2p_ffi_harness.mjs", "incomingChannel")
fn incoming_channel(label: String) -> String

@target(javascript)
@external(javascript, "./p2p_ffi_harness.mjs", "secondChannel")
fn second_channel() -> String

@target(javascript)
/// Every deferred operation the FFI starts, and the one hook its
/// continuation fires on the peer that started it.
fn continuations() -> List(#(String, String)) {
  [
    #("offer", "gen1 description offer sdp-1"),
    #("offer-failure", "gen1 failure offer boom"),
    #(
      "offer-no-description",
      "gen1 failure offer no local description was produced",
    ),
    #("accept-offer", "gen1 remote-description"),
    #("accept-offer-failure", "gen1 failure answer boom"),
    #("accept-answer", "gen1 remote-description"),
    #("accept-answer-failure", "gen1 failure answer boom"),
    #("candidate", "gen1 failure candidate boom"),
  ]
}

@target(javascript)
pub fn every_continuation_reaches_the_peer_that_started_it_test() -> Nil {
  // The control. Without it, the guard tests below would pass just as well
  // against an FFI that reported nothing at all.
  continuations()
  |> list.each(fn(entry) {
    live_continuation(entry.0) |> expect.to_equal(entry.1)
  })
}

@target(javascript)
pub fn no_continuation_reaches_a_peer_recreated_under_the_same_id_test() -> Nil {
  // The peer is closed and a new one is created under the same ID before
  // the operation settles. Neither generation may hear from it: the first
  // is gone, and the second is a different connection whose SDP, remote
  // description, and failures are its own.
  continuations()
  |> list.each(fn(entry) { stale_continuation(entry.0) |> expect.to_equal("") })
}

@target(javascript)
pub fn no_continuation_reaches_a_closed_peer_test() -> Nil {
  continuations()
  |> list.each(fn(entry) { closed_continuation(entry.0) |> expect.to_equal("") })
}

@target(javascript)
pub fn an_incoming_document_channel_is_accepted_test() -> Nil {
  // Driven with the Gleam constant, so the label the FFI admits and the
  // label this module advertises cannot drift apart.
  incoming_channel(p2p_transport_js.document_channel_label)
  |> expect.to_equal("gen1 channel-open,gen1 message hello")
}

@target(javascript)
pub fn an_incoming_channel_with_a_foreign_label_is_rejected_test() -> Nil {
  // A peer opening some other channel is not speaking this protocol. It is
  // reported and the channel is closed, rather than being adopted as the
  // document channel and fed to the application.
  incoming_channel("chat")
  |> expect.to_equal(
    "gen1 invalid unexpected data channel label: chat,channel closed",
  )
}

@target(javascript)
pub fn a_second_incoming_channel_is_rejected_test() -> Nil {
  second_channel()
  |> expect.to_equal(
    "gen1 invalid unexpected second data channel: watershed-crdt-v1,"
    <> "channel closed",
  )
}
