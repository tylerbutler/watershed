//// Sprint board Lustre app — compiled fixtures for the `/sharedtree`
//// comparison page. Each marker or definition that the website extracts is
//// real Gleam that type-checks against the live watershed and watershed_lustre
//// APIs.
////
//// This module is a fixture: it compiles, but it is not wired to a real
//// transport. Its only consumer is the website's `?raw` import pipeline.

import gleam/dynamic/decode as gleam_decode
import gleam/json as gleam_json
import gleam/option.{type Option, None, Some}
import gleam/result
import lustre/effect.{type Effect}
import watershed.{type SharedCounter, type SharedMap}
import watershed/schema.{type FieldChange, FieldChange}
import watershed_lustre
import website_samples/board_schema as document_schema

// ── Msg ───────────────────────────────────────────────────────────────────────

type Msg {
  EnsuredCards(Result(SharedMap, String))
  EnsuredBreaches(Result(SharedCounter, String))
  SharedChanged
}

// ── Bootstrap ─────────────────────────────────────────────────────────────────

// docs:snippet-start sharedtree-bootstrap
fn bootstrap(
  document: watershed.Document(document_schema.Board),
) -> Effect(Msg) {
  let root = watershed.root_typed(document)
  effect.batch([
    // Idempotent, and run by every client on every boot. Each one
    // seeds a candidate and adopts the handle visible after its own
    // sync — a later concurrent write can still replace the field,
    // so the channel handed back here is not promised to be final.
    watershed_lustre.ensure_field(root, document_schema.title(), "Sprint board"),
    watershed_lustre.ensure_map(
      document,
      root,
      document_schema.cards(),
      EnsuredCards,
    ),
    watershed_lustre.ensure_counter(
      document,
      root,
      document_schema.wip_breaches(),
      EnsuredBreaches,
    ),
  ])
}

// docs:snippet-end sharedtree-bootstrap

// ── Read / write ──────────────────────────────────────────────────────────────

// docs:snippet-start sharedtree-read-write
fn read_write_example(root: watershed.TypedMap(document_schema.Board)) -> Nil {
  // Writing is checked at the field — only a String is accepted here.
  watershed.set_field(root, document_schema.title(), "Q3 sprint board")

  // Reading decodes at the boundary. A peer running an older build — or
  // a stale summary — could have written anything here, so the result is
  // a `Result`, never a raw value.
  case watershed.get_field(root, document_schema.title()) {
    Ok(Some(title)) -> render_header(title)
    Ok(None) -> render_header("Untitled board")
    Error(_) -> render_header("Untitled board")
  }
}

// docs:snippet-end sharedtree-read-write

fn render_header(_title: String) -> Nil {
  Nil
}

// ── Record schema ─────────────────────────────────────────────────────────────

type Card

type CardState {
  CardState(title: String, column: String, owner: Option(String))
}

fn card_title() -> schema.Field(Card, String) {
  schema.field("title", gleam_json.string, gleam_decode.string)
}

fn card_column() -> schema.Field(Card, String) {
  schema.field("column", gleam_json.string, gleam_decode.string)
}

fn card_owner() -> schema.Field(Card, String) {
  schema.field("owner", gleam_json.string, gleam_decode.string)
}

// docs:snippet-start sharedtree-record
/// `record3` derives the decoder AND the per-key encoder from one
/// prop list, so the two can never drift. `sealed_known` seals the
/// schema to exactly these keys without a hand-repeated list, and
/// `versioned` stamps a version and rejects any stored version that differs.
fn card_schema() -> Result(schema.Schema(Card, CardState), Nil) {
  schema.record3(
    CardState,
    schema.prop(card_title(), fn(c: CardState) { c.title }),
    schema.prop(card_column(), fn(c: CardState) { c.column }),
    schema.optional_prop(card_owner(), fn(c: CardState) { c.owner }),
  )
  |> schema.versioned(1)
  |> schema.sealed_known
}

// `write` emits one op per key, never a blob — so a peer editing
// `owner` at the same time keeps their edit. An optional prop that is
// `None` deletes its key rather than skipping it.
fn write_card(card: watershed.TypedMap(Card)) -> Result(Nil, Nil) {
  use card_schema <- result.try(card_schema())
  watershed.write(
    card,
    card_schema,
    CardState(title: "Ship it", column: "doing", owner: None),
  )
  Ok(Nil)
}

// docs:snippet-end sharedtree-record

// ── Field events ──────────────────────────────────────────────────────────────

// docs:snippet-start sharedtree-events
fn subscribe_title(
  root: watershed.TypedMap(document_schema.Board),
) -> watershed.SubscriptionToken {
  // Per field. The change carries the decoded previous value AND the
  // new one, plus whether this client made it — and a peer's
  // type-confused write surfaces here as `Error(Invalid(_))`.
  watershed.subscribe_field(root, document_schema.title(), fn(change) {
    case change {
      FieldChange(value: Ok(Some(title)), local: False, ..) ->
        render_header(title)
      FieldChange(value: Error(_), ..) -> keep_previous_header()
      _ -> Nil
    }
  })
}

// docs:snippet-end sharedtree-events

fn keep_previous_header() -> Nil {
  Nil
}
