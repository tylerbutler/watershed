//// A deterministic stand-in for the browser, for `p2p_transport_js` tests.
////
//// One `World` holds an in-memory signaling hub and a fake
//// `RTCPeerConnection` mesh. Both are effect queues rather than direct
//// calls: every signal delivery and every browser callback is enqueued
//// and runs only inside `settle`, so a test never observes a hook firing
//// re-entrantly out of the call that caused it, and every run of a test
//// produces the same interleaving.
////
//// The fake models what the transport is allowed to depend on and
//// nothing more: signaling state transitions, implicit rollback on a
//// colliding offer, one data channel per link created by the offerer and
//// received by the answerer, string delivery, and teardown that notifies
//// the far side but not the near one — a real `closePeer` detaches its
//// own listeners first.
////
//// It also records. `calls` is the ordered log of backend operations,
//// `signaling_payloads` is everything the hub was ever asked to carry,
//// and `channel_specs` is the label and options every data channel was
//// created with. Those three are what let a test assert that signaling
//// saw only offers, answers, and candidates, and that the document
//// channel is unordered and reliable.

@target(javascript)
import gleam/dict.{type Dict}
@target(javascript)
import gleam/int
@target(javascript)
import gleam/list
@target(javascript)
import gleam/option.{type Option, None, Some}
@target(javascript)
import gleam/string

@target(javascript)
import watershed/p2p_transport_js.{
  type PeerHooks, type Rtc, type Signal, type SignalPayload, type Signaling,
  Answer, Candidate, Message, Offer, PeerJoined, PeerLeft, Roster, Rtc,
  Signaling,
}
@target(javascript)
import watershed/transport_js.{type Cell}

@target(javascript)
pub opaque type World {
  World(cell: Cell(WorldState))
}

@target(javascript)
type WorldState {
  WorldState(
    members: List(Member),
    /// Keyed `owner|remote`: one directed half of a peer link, holding the
    /// hooks that owner's transport installed.
    links: Dict(String, Link),
    /// Oldest first. Only `settle` drains it.
    queue: List(Effect),
    calls: List(String),
    signaling_payloads: List(String),
    /// Every document payload written to a data channel, newest first,
    /// as `#(from, to, payload)`. The mesh's own traffic log: what a
    /// peer *answered* is a claim a test can make from it.
    channel_payloads: List(#(String, String, String)),
    channel_specs: List(#(String, String, String)),
    configurations: List(#(String, String)),
    rollbacks: List(String),
    applied_candidates: List(#(String, String)),
    fail_candidates: Bool,
    /// Makes `open` report a synchronous construction failure, the way a
    /// browser does for a malformed `RTCConfiguration` or no WebRTC at all.
    fail_open: Bool,
    /// Makes `offer` reject instead of producing a description, the way
    /// `setLocalDescription` does in a bad state. The signaling state does
    /// not move, because in a browser it does not either.
    fail_offer: Bool,
    /// Makes `open_channel` report a synchronous failure and create
    /// nothing, the way `createDataChannel` throws on a closing connection.
    fail_channel: Bool,
    /// Which side of a join the hub announces to.
    join_notice: JoinNotice,
    join_failure: Option(String),
    counter: Int,
  )
}

@target(javascript)
/// Which members a join is announced to, so a test can reproduce the
/// adapter shapes in the wild: both sides, a roster to the newcomer only,
/// or a notice to the members already in the room only.
pub type JoinNotice {
  NotifyBoth
  NotifyNewcomer
  NotifyExistingMembers
}

@target(javascript)
type Member {
  Member(room: String, peer_id: String, on_signal: fn(Signal) -> Nil)
}

@target(javascript)
type Link {
  Link(
    owner: String,
    remote: String,
    signaling_state: String,
    hooks: PeerHooks,
    has_channel: Bool,
    open: Bool,
  )
}

@target(javascript)
type Effect {
  DeliverSignal(to: String, signal: Signal)
  FireHook(owner: String, remote: String, run: fn(PeerHooks) -> Nil)
  /// Both halves of a link reaching the connected state at once, which is
  /// what a real answer being applied produces.
  Connect(owner: String, remote: String)
}

// ─────────────────────────────────────────────────────────────────────────────
// World
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
pub fn new_world() -> World {
  World(
    cell: transport_js.new_cell(WorldState(
      members: [],
      links: dict.new(),
      queue: [],
      calls: [],
      signaling_payloads: [],
      channel_payloads: [],
      channel_specs: [],
      configurations: [],
      rollbacks: [],
      applied_candidates: [],
      fail_candidates: False,
      fail_open: False,
      fail_offer: False,
      fail_channel: False,
      join_notice: NotifyBoth,
      join_failure: None,
      counter: 0,
    )),
  )
}

@target(javascript)
/// Run every queued effect, and everything they queue in turn, until the
/// world is quiet.
pub fn settle(world: World) -> Nil {
  drain(world, 10_000)
}

@target(javascript)
fn drain(world: World, fuel: Int) -> Nil {
  case fuel <= 0 {
    True -> panic as "p2p_fake: world did not settle"
    False -> {
      let state = get(world)
      case state.queue {
        [] -> Nil
        [effect, ..rest] -> {
          set(world, WorldState(..state, queue: rest))
          run(world, effect)
          drain(world, fuel - 1)
        }
      }
    }
  }
}

@target(javascript)
fn run(world: World, effect: Effect) -> Nil {
  case effect {
    DeliverSignal(to, signal) ->
      case find_member(get(world), to) {
        Ok(member) -> member.on_signal(signal)
        Error(Nil) -> Nil
      }
    FireHook(owner, remote, action) ->
      // A hook for a link that has since been closed is a browser callback
      // arriving after its listeners were detached: nothing to do.
      case dict.get(get(world).links, key(owner, remote)) {
        Ok(link) -> action(link.hooks)
        Error(Nil) -> Nil
      }
    Connect(owner, remote) -> connect(world, owner, remote)
  }
}

@target(javascript)
fn connect(world: World, owner: String, remote: String) -> Nil {
  let state = get(world)
  case dict.get(state.links, key(owner, remote)) {
    Error(Nil) -> Nil
    Ok(near) -> {
      let far = dict.get(state.links, key(remote, owner))
      let links =
        dict.insert(state.links, key(owner, remote), Link(..near, open: True))
      let links = case far {
        Ok(far) ->
          dict.insert(links, key(remote, owner), Link(..far, open: True))
        Error(Nil) -> links
      }
      set(world, WorldState(..state, links: links))
      enqueue(world, [
        FireHook(owner, remote, fn(hooks) {
          hooks.on_ice_state(remote, "connected")
        }),
        FireHook(owner, remote, fn(hooks) { hooks.on_channel_open(remote) }),
      ])
      case far {
        Ok(_) ->
          enqueue(world, [
            FireHook(remote, owner, fn(hooks) {
              hooks.on_ice_state(owner, "connected")
            }),
            FireHook(remote, owner, fn(hooks) { hooks.on_channel_open(owner) }),
          ])
        Error(Nil) -> Nil
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Signaling hub
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// An in-memory signaling adapter that routes between every transport in
/// this world.
pub fn signaling(world: World) -> Signaling {
  Signaling(
    join: fn(room, peer_id, on_signal) {
      record(world, "signaling.join " <> room <> " " <> peer_id)
      let state = get(world)
      case state.join_failure {
        Some(detail) -> Error(detail)
        None -> {
          let peers =
            state.members
            |> list.filter(fn(member) {
              member.room == room && member.peer_id != peer_id
            })
          set(
            world,
            WorldState(..state, members: [
              Member(room: room, peer_id: peer_id, on_signal: on_signal),
              ..state.members
            ]),
          )
          enqueue(world, case state.join_notice {
            // The shape of a real service: the newcomer is told the whole
            // room, and the room is told the newcomer. The roster is
            // enqueued rather than delivered inside `join`, because that
            // is what a socket does.
            NotifyBoth -> [
              DeliverSignal(
                peer_id,
                Roster(
                  peers
                  |> list.map(fn(peer) { peer.peer_id })
                  |> list.sort(string.compare),
                ),
              ),
              ..list.map(peers, fn(peer) {
                DeliverSignal(peer.peer_id, PeerJoined(peer_id))
              })
            ]
            NotifyNewcomer -> [
              DeliverSignal(
                peer_id,
                Roster(
                  peers
                  |> list.map(fn(peer) { peer.peer_id })
                  |> list.sort(string.compare),
                ),
              ),
            ]
            // Only the room hears anything at all, roster included: the
            // one-sided shape the discovery contract calls out.
            NotifyExistingMembers ->
              list.map(peers, fn(peer) {
                DeliverSignal(peer.peer_id, PeerJoined(peer_id))
              })
          })
          Ok(p2p_transport_js.signaling_session(room: room, peer_id: peer_id))
        }
      }
    },
    send: fn(session, to, payload) {
      let from = p2p_transport_js.session_peer_id(session)
      let state = get(world)
      set(
        world,
        WorldState(..state, signaling_payloads: [
          from <> "->" <> to <> " " <> describe_payload(payload),
          ..state.signaling_payloads
        ]),
      )
      record(
        world,
        "signaling.send " <> from <> "->" <> to <> " " <> tag(payload),
      )
      case find_member(get(world), to) {
        Ok(_) -> enqueue(world, [DeliverSignal(to, Message(from, payload))])
        Error(Nil) -> Nil
      }
    },
    leave: fn(session) {
      let peer_id = p2p_transport_js.session_peer_id(session)
      let room = p2p_transport_js.session_room(session)
      record(world, "signaling.leave " <> peer_id)
      let state = get(world)
      let remaining =
        list.filter(state.members, fn(member) { member.peer_id != peer_id })
      set(world, WorldState(..state, members: remaining))
      enqueue(
        world,
        remaining
          |> list.filter(fn(member) { member.room == room })
          |> list.map(fn(member) {
            DeliverSignal(member.peer_id, PeerLeft(peer_id))
          }),
      )
    },
  )
}

@target(javascript)
/// A signaling adapter that hands the transport's inbound callback to
/// `capture` instead of routing anything, so a test can deliver signals in
/// whatever order it likes.
pub fn scripted_signaling(
  world: World,
  capture: fn(fn(Signal) -> Nil) -> Nil,
) -> Signaling {
  Signaling(
    join: fn(room, peer_id, on_signal) {
      record(world, "signaling.join " <> room <> " " <> peer_id)
      case get(world).join_failure {
        Some(detail) -> Error(detail)
        None -> {
          capture(on_signal)
          Ok(p2p_transport_js.signaling_session(room: room, peer_id: peer_id))
        }
      }
    },
    send: fn(session, to, payload) {
      let from = p2p_transport_js.session_peer_id(session)
      let state = get(world)
      set(
        world,
        WorldState(..state, signaling_payloads: [
          from <> "->" <> to <> " " <> describe_payload(payload),
          ..state.signaling_payloads
        ]),
      )
      record(
        world,
        "signaling.send " <> from <> "->" <> to <> " " <> tag(payload),
      )
    },
    leave: fn(session) {
      record(
        world,
        "signaling.leave " <> p2p_transport_js.session_peer_id(session),
      )
    },
  )
}

@target(javascript)
/// Make the next `join` fail with `detail`.
pub fn fail_join(world: World, detail: String) -> Nil {
  let state = get(world)
  set(world, WorldState(..state, join_failure: Some(detail)))
}

// ─────────────────────────────────────────────────────────────────────────────
// Fake RTC backend
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// The browser seam for the transport whose local peer ID is `owner`.
pub fn rtc(world: World, owner: String) -> Rtc {
  Rtc(
    open: fn(remote, configuration, hooks) {
      record(world, owner <> " open " <> remote)
      let state = get(world)
      set(
        world,
        WorldState(..state, configurations: [
          #(owner <> "->" <> remote, configuration),
          ..state.configurations
        ]),
      )
      case get(world).fail_open {
        // No link is registered, and the failure is reported before `open`
        // returns — exactly what the native FFI does when the
        // `RTCPeerConnection` constructor throws.
        True -> hooks.on_failure(remote, "open", "fake construction failure")
        False ->
          case dict.get(get(world).links, key(owner, remote)) {
            Ok(_) -> Nil
            Error(Nil) ->
              put_link(
                world,
                Link(
                  owner: owner,
                  remote: remote,
                  signaling_state: "stable",
                  hooks: hooks,
                  has_channel: False,
                  open: False,
                ),
              )
          }
      }
    },
    open_channel: fn(remote, label, options) {
      record(world, owner <> " open_channel " <> remote <> " " <> label)
      let state = get(world)
      set(
        world,
        WorldState(..state, channel_specs: [
          #(owner, label, options),
          ..state.channel_specs
        ]),
      )
      with_link(world, owner, remote, fn(link) {
        case get(world).fail_channel, link.has_channel {
          // `createDataChannel` throws inline, so the failure is reported
          // before `open_channel` returns, exactly as the FFI does.
          True, _ ->
            link.hooks.on_failure(remote, "channel", "fake channel refusal")
          False, True -> Nil
          False, False -> {
            put_link(world, Link(..link, has_channel: True))
            enqueue(world, [
              FireHook(owner, remote, fn(hooks) {
                hooks.on_negotiation_needed(remote)
              }),
            ])
          }
        }
      })
    },
    offer: fn(remote) {
      record(world, owner <> " offer " <> remote)
      with_link(world, owner, remote, fn(link) {
        case get(world).fail_offer {
          // A rejected `setLocalDescription` leaves the signaling state
          // where it was and produces no description at all.
          True ->
            enqueue(world, [
              FireHook(owner, remote, fn(hooks) {
                hooks.on_failure(remote, "offer", "fake offer rejection")
              }),
            ])
          False -> {
            put_link(world, Link(..link, signaling_state: "have-local-offer"))
            let sdp = mint(world, "offer:" <> owner <> ">" <> remote)
            enqueue(world, [
              FireHook(owner, remote, fn(hooks) {
                hooks.on_description(remote, "offer", sdp)
              }),
              FireHook(owner, remote, fn(hooks) {
                hooks.on_candidate(remote, candidate_json(owner, remote))
              }),
            ])
          }
        }
      })
    },
    accept_offer: fn(remote, _sdp) {
      record(world, owner <> " accept_offer " <> remote)
      with_link(world, owner, remote, fn(link) {
        // Applying a remote offer over an outstanding local one rolls the
        // local one back, exactly as a browser does.
        case link.signaling_state == "have-local-offer" {
          True -> {
            let state = get(world)
            set(
              world,
              WorldState(..state, rollbacks: [
                owner <> "<-" <> remote,
                ..state.rollbacks
              ]),
            )
          }
          False -> Nil
        }
        // The answering side receives the offerer's channel.
        let inherited = case dict.get(get(world).links, key(remote, owner)) {
          Ok(far) -> far.has_channel
          Error(Nil) -> False
        }
        put_link(
          world,
          Link(
            ..link,
            signaling_state: "stable",
            has_channel: link.has_channel || inherited,
          ),
        )
        let sdp = mint(world, "answer:" <> owner <> ">" <> remote)
        enqueue(world, [
          FireHook(owner, remote, fn(hooks) {
            hooks.on_remote_description(remote)
          }),
          FireHook(owner, remote, fn(hooks) {
            hooks.on_description(remote, "answer", sdp)
          }),
          FireHook(owner, remote, fn(hooks) {
            hooks.on_candidate(remote, candidate_json(owner, remote))
          }),
        ])
      })
    },
    accept_answer: fn(remote, _sdp) {
      record(world, owner <> " accept_answer " <> remote)
      with_link(world, owner, remote, fn(link) {
        put_link(world, Link(..link, signaling_state: "stable"))
        enqueue(world, [
          FireHook(owner, remote, fn(hooks) {
            hooks.on_remote_description(remote)
          }),
          Connect(owner, remote),
        ])
      })
    },
    add_candidate: fn(remote, candidate) {
      record(world, owner <> " add_candidate " <> remote)
      let state = get(world)
      set(
        world,
        WorldState(..state, applied_candidates: [
          #(owner <> "->" <> remote, candidate),
          ..state.applied_candidates
        ]),
      )
      case get(world).fail_candidates {
        False -> Nil
        True ->
          enqueue(world, [
            FireHook(owner, remote, fn(hooks) {
              hooks.on_failure(remote, "candidate", "fake candidate rejection")
            }),
          ])
      }
    },
    signaling_state: fn(remote) {
      case dict.get(get(world).links, key(owner, remote)) {
        Ok(link) -> link.signaling_state
        Error(Nil) -> "closed"
      }
    },
    send: fn(remote, payload) {
      record(world, owner <> " send " <> remote)
      let state = get(world)
      set(
        world,
        WorldState(..state, channel_payloads: [
          #(owner, remote, payload),
          ..state.channel_payloads
        ]),
      )
      case dict.get(get(world).links, key(owner, remote)) {
        Ok(link) if link.open -> {
          enqueue(world, [
            FireHook(remote, owner, fn(hooks) {
              hooks.on_message(owner, payload)
            }),
          ])
          True
        }
        _ -> False
      }
    },
    close: fn(remote) {
      record(world, owner <> " close " <> remote)
      let state = get(world)
      set(
        world,
        WorldState(..state, links: dict.delete(state.links, key(owner, remote))),
      )
      // The far side's channel really does close; the near side detached
      // its listeners first, so it hears nothing.
      case dict.get(get(world).links, key(remote, owner)) {
        Ok(far) if far.open -> {
          put_link(world, Link(..far, open: False))
          enqueue(world, [
            FireHook(remote, owner, fn(hooks) { hooks.on_channel_close(owner) }),
          ])
        }
        _ -> Nil
      }
    },
    diagnostics: fn(remote) {
      case dict.get(get(world).links, key(owner, remote)) {
        Error(Nil) -> "{\"known\":false}"
        Ok(link) ->
          "{\"known\":true,\"signalingState\":\""
          <> link.signaling_state
          <> "\",\"open\":"
          <> case link.open {
            True -> "true"
            False -> "false"
          }
          <> "}"
      }
    },
  )
}

// ─────────────────────────────────────────────────────────────────────────────
// Controls
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// Make the browser ask `owner` to renegotiate with `remote`, which is how
/// a peer that is not the designated offerer comes to have an outstanding
/// offer — the situation perfect negotiation exists to resolve.
pub fn force_negotiation(world: World, owner: String, remote: String) -> Nil {
  enqueue(world, [
    FireHook(owner, remote, fn(hooks) { hooks.on_negotiation_needed(remote) }),
  ])
}

@target(javascript)
/// Deliver a non-string payload on `owner`'s channel with `remote`.
pub fn deliver_binary(world: World, owner: String, remote: String) -> Nil {
  enqueue(world, [
    FireHook(owner, remote, fn(hooks) {
      hooks.on_invalid_message(remote, "non-string data channel message: Blob")
    }),
  ])
}

@target(javascript)
/// Report an ICE connection state change to `owner` for `remote`.
pub fn fire_ice(
  world: World,
  owner: String,
  remote: String,
  ice_state: String,
) -> Nil {
  enqueue(world, [
    FireHook(owner, remote, fn(hooks) { hooks.on_ice_state(remote, ice_state) }),
  ])
}

@target(javascript)
/// Report an asynchronous browser rejection to `owner` for `remote`.
pub fn fire_failure(
  world: World,
  owner: String,
  remote: String,
  stage: String,
  detail: String,
) -> Nil {
  enqueue(world, [
    FireHook(owner, remote, fn(hooks) {
      hooks.on_failure(remote, stage, detail)
    }),
  ])
}

@target(javascript)
/// Make every subsequent `addIceCandidate` reject.
pub fn set_candidate_failure(world: World, failing: Bool) -> Nil {
  let state = get(world)
  set(world, WorldState(..state, fail_candidates: failing))
}

@target(javascript)
/// Make every subsequent `open` fail synchronously, before it returns.
pub fn set_open_failure(world: World, failing: Bool) -> Nil {
  let state = get(world)
  set(world, WorldState(..state, fail_open: failing))
}

@target(javascript)
/// Make every subsequent `offer` reject instead of describing itself.
pub fn set_offer_failure(world: World, failing: Bool) -> Nil {
  let state = get(world)
  set(world, WorldState(..state, fail_offer: failing))
}

@target(javascript)
/// Make every subsequent `open_channel` fail before creating anything.
pub fn set_channel_failure(world: World, failing: Bool) -> Nil {
  let state = get(world)
  set(world, WorldState(..state, fail_channel: failing))
}

@target(javascript)
/// Choose which members the hub announces a join to.
pub fn set_join_notice(world: World, notice: JoinNotice) -> Nil {
  let state = get(world)
  set(world, WorldState(..state, join_notice: notice))
}

@target(javascript)
/// Announce `peer_id` to one member out of band, the way an adapter that
/// delivers its roster late does.
pub fn announce_peer(world: World, to: String, peer_id: String) -> Nil {
  enqueue(world, [DeliverSignal(to, PeerJoined(peer_id))])
}

@target(javascript)
/// Partition two connected peers, the way a network drop does: each
/// transport hears its document channel close and tears the other down.
/// Both directed links are gone once the world settles, so a later
/// `reconnect` re-negotiates from scratch rather than reusing a stale one.
pub fn sever(world: World, a: String, b: String) -> Nil {
  enqueue(world, [
    FireHook(a, b, fn(hooks) { hooks.on_channel_close(b) }),
    FireHook(b, a, fn(hooks) { hooks.on_channel_close(a) }),
  ])
}

@target(javascript)
/// Heal a partition between two peers by re-announcing each to the other,
/// the way signaling does when a route comes back. The transports
/// re-negotiate, a fresh channel opens, and the documents exchange state
/// again — exactly the reconnect path a returning edge takes.
pub fn reconnect(world: World, a: String, b: String) -> Nil {
  enqueue(world, [
    DeliverSignal(a, PeerJoined(b)),
    DeliverSignal(b, PeerJoined(a)),
  ])
}

@target(javascript)
/// Report a signaling failure to one member, the way an adapter whose
/// socket died after `join` returned does.
///
/// Delivered immediately rather than queued, so a test can fail
/// signaling *before* the roster the join enqueued has been drained —
/// which is the case that would otherwise hang.
pub fn fail_signaling(world: World, to: String, detail: String) -> Nil {
  case find_member(get(world), to) {
    Ok(member) -> member.on_signal(p2p_transport_js.Failed(detail))
    Error(Nil) -> Nil
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Inspection
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
/// Every backend and signaling operation, oldest first.
pub fn calls(world: World) -> List(String) {
  list.reverse(get(world).calls)
}

@target(javascript)
/// Whether any backend operation matching `fragment` was performed.
pub fn called(world: World, fragment: String) -> Bool {
  list.any(calls(world), fn(call) { string.contains(call, fragment) })
}

@target(javascript)
/// Everything the signaling hub was asked to carry, oldest first, rendered
/// as `from->to type body`.
pub fn signaling_payloads(world: World) -> List(String) {
  list.reverse(get(world).signaling_payloads)
}

@target(javascript)
/// Every document payload written to a data channel, oldest first, as
/// `#(from, to, payload)`.
pub fn channel_payloads(world: World) -> List(#(String, String, String)) {
  list.reverse(get(world).channel_payloads)
}

@target(javascript)
/// The label and `RTCDataChannelInit` JSON of every data channel created,
/// oldest first.
pub fn channel_specs(world: World) -> List(#(String, String, String)) {
  list.reverse(get(world).channel_specs)
}

@target(javascript)
/// The `RTCConfiguration` JSON every peer connection was built with.
pub fn configurations(world: World) -> List(#(String, String)) {
  list.reverse(get(world).configurations)
}

@target(javascript)
/// Links where applying a remote offer rolled a local offer back.
pub fn rollbacks(world: World) -> List(String) {
  list.reverse(get(world).rollbacks)
}

@target(javascript)
/// Remote candidates handed to the browser for one link, in the order they
/// were applied.
pub fn applied_candidates(
  world: World,
  owner: String,
  remote: String,
) -> List(String) {
  get(world).applied_candidates
  |> list.reverse
  |> list.filter(fn(entry) { entry.0 == owner <> "->" <> remote })
  |> list.map(fn(entry) { entry.1 })
}

@target(javascript)
/// Every live directed link, as `owner->remote`, sorted.
pub fn links(world: World) -> List(String) {
  get(world).links
  |> dict.values
  |> list.map(fn(link) { link.owner <> "->" <> link.remote })
  |> list.sort(string.compare)
}

@target(javascript)
/// One link's signaling state, or `"closed"` if there is no such link.
pub fn link_state(world: World, owner: String, remote: String) -> String {
  case dict.get(get(world).links, key(owner, remote)) {
    Ok(link) -> link.signaling_state
    Error(Nil) -> "closed"
  }
}

@target(javascript)
/// Signaling members still joined, sorted.
pub fn members(world: World) -> List(String) {
  get(world).members
  |> list.map(fn(member) { member.peer_id })
  |> list.sort(string.compare)
}

// ─────────────────────────────────────────────────────────────────────────────
// Internals
// ─────────────────────────────────────────────────────────────────────────────

@target(javascript)
fn get(world: World) -> WorldState {
  transport_js.get_cell(world.cell)
}

@target(javascript)
fn set(world: World, state: WorldState) -> Nil {
  transport_js.set_cell(world.cell, state)
}

@target(javascript)
fn enqueue(world: World, effects: List(Effect)) -> Nil {
  let state = get(world)
  set(world, WorldState(..state, queue: list.append(state.queue, effects)))
}

@target(javascript)
fn record(world: World, call: String) -> Nil {
  let state = get(world)
  set(world, WorldState(..state, calls: [call, ..state.calls]))
}

@target(javascript)
fn key(owner: String, remote: String) -> String {
  owner <> "|" <> remote
}

@target(javascript)
fn put_link(world: World, link: Link) -> Nil {
  let state = get(world)
  set(
    world,
    WorldState(
      ..state,
      links: dict.insert(state.links, key(link.owner, link.remote), link),
    ),
  )
}

@target(javascript)
fn with_link(
  world: World,
  owner: String,
  remote: String,
  action: fn(Link) -> Nil,
) -> Nil {
  case dict.get(get(world).links, key(owner, remote)) {
    Ok(link) -> action(link)
    Error(Nil) -> Nil
  }
}

@target(javascript)
fn find_member(state: WorldState, peer_id: String) -> Result(Member, Nil) {
  case list.filter(state.members, fn(member) { member.peer_id == peer_id }) {
    [member, ..] -> Ok(member)
    [] -> Error(Nil)
  }
}

@target(javascript)
/// A fresh, ordered token so two descriptions are never accidentally equal.
fn mint(world: World, label: String) -> String {
  let state = get(world)
  let counter = state.counter + 1
  set(world, WorldState(..state, counter: counter))
  "sdp:" <> label <> ":" <> int.to_string(counter)
}

@target(javascript)
fn candidate_json(owner: String, remote: String) -> String {
  "{\"candidate\":\"candidate:" <> owner <> "-" <> remote <> "\"}"
}

@target(javascript)
fn tag(payload: SignalPayload) -> String {
  case payload {
    Offer(_) -> "offer"
    Answer(_) -> "answer"
    Candidate(_) -> "candidate"
  }
}

@target(javascript)
fn describe_payload(payload: SignalPayload) -> String {
  case payload {
    Offer(sdp) -> "offer " <> sdp
    Answer(sdp) -> "answer " <> sdp
    Candidate(candidate) -> "candidate " <> candidate
  }
}
