import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result
import startest/expect
import watershed/presence.{type Config, Config, Peer}

// A tiny app payload for the generic roster.
type Cursor {
  Cursor(cell: String)
}

fn encode_cursor(c: Cursor) -> json.Json {
  json.object([#("cell", json.string(c.cell))])
}

fn cursor_decoder() -> decode.Decoder(Cursor) {
  use cell <- decode.field("cell", decode.string)
  decode.success(Cursor(cell))
}

fn config() -> Config {
  Config(heartbeat_ms: 2000, ttl_ms: 6500)
}

pub fn observe_replaces_prior_entry_per_user_test() {
  let peers =
    presence.new()
    |> presence.observe("web-1", Cursor("r0c0"), 100)
    |> presence.observe("web-1", Cursor("r1c1"), 200)

  presence.roster(peers)
  |> expect.to_equal([
    Peer(user: "web-1", payload: Cursor("r1c1"), last_seen: 200),
  ])
}

pub fn prune_drops_exactly_peers_past_ttl_test() {
  let peers =
    presence.new()
    |> presence.observe("web-1", Cursor("a"), 0)
    |> presence.observe("web-2", Cursor("b"), 100)

  // now=6600: web-1 is 6600ms stale (> 6500 ttl) and dropped; web-2 is 6500ms
  // stale (== ttl) and kept.
  let pruned = presence.prune(peers, config(), 6600)

  presence.roster(pruned)
  |> list.map(fn(p) { p.user })
  |> expect.to_equal(["web-2"])
}

pub fn roster_is_sorted_by_user_id_test() {
  let peers =
    presence.new()
    |> presence.observe("web-3", Cursor("c"), 0)
    |> presence.observe("web-1", Cursor("a"), 0)
    |> presence.observe("web-2", Cursor("b"), 0)

  presence.roster(peers)
  |> list.map(fn(p) { p.user })
  |> expect.to_equal(["web-1", "web-2", "web-3"])
}

pub fn find_filters_by_payload_test() {
  let peers =
    presence.new()
    |> presence.observe("web-1", Cursor("r0c0"), 0)
    |> presence.observe("web-2", Cursor("r1c1"), 0)

  presence.find(peers, fn(c) { c.cell == "r0c0" })
  |> list.map(fn(p) { p.user })
  |> expect.to_equal(["web-1"])
}

pub fn envelope_round_trips_test() {
  let encoded =
    presence.encode_envelope("web-1", encode_cursor, Cursor("r2c2"))
    |> json.to_string

  let decoded =
    json.parse(encoded, presence.decode_envelope(decode: cursor_decoder()))

  decoded
  |> expect.to_equal(Ok(#("web-1", Cursor("r2c2"))))
}

pub fn decode_rejects_foreign_kind_test() {
  let foreign =
    json.object([
      #("kind", json.string("chat")),
      #("user", json.string("web-1")),
      #("payload", encode_cursor(Cursor("r0c0"))),
    ])
    |> json.to_string

  json.parse(foreign, presence.decode_envelope(decode: cursor_decoder()))
  |> result.is_error
  |> expect.to_be_true
}

pub fn decode_rejects_malformed_payload_test() {
  let malformed =
    json.object([
      #("kind", json.string("presence")),
      #("user", json.string("web-1")),
      #("payload", json.object([#("wrong", json.int(1))])),
    ])
    |> json.to_string

  json.parse(malformed, presence.decode_envelope(decode: cursor_decoder()))
  |> result.is_error
  |> expect.to_be_true
}
