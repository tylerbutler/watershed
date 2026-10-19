import gleam/dict.{type Dict}
import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import shared_tree_project_brief_lustre/brief.{type ProjectBrief}
import watershed/presence

pub type FixedField {
  Title
  OwnerName
  OwnerEmail
  ScheduleStart
  ScheduleTarget
  ReviewReviewer
  ReviewApproved
}

pub type MilestoneField {
  MilestoneTitle
  Completed
}

pub type Field {
  Fixed(FixedField)
  Milestone(id: String, field: MilestoneField)
}

pub type Color {
  Blue
  Green
  Amber
  Violet
}

pub type Metadata {
  Metadata(name: String, color: Color, token: Int, selected: Option(Field))
}

pub opaque type Policy {
  Policy(
    latest: Dict(String, Metadata),
    invalid: Dict(String, Int),
    peers: List(presence.PresenceEntry(Metadata)),
  )
}

fn fixed_fields() -> List(#(String, FixedField)) {
  [
    #("title", Title),
    #("owner.name", OwnerName),
    #("owner.email", OwnerEmail),
    #("schedule.start", ScheduleStart),
    #("schedule.target", ScheduleTarget),
    #("review.reviewer", ReviewReviewer),
    #("review.approved", ReviewApproved),
  ]
}

fn colors() -> List(#(String, Color)) {
  [#("blue", Blue), #("green", Green), #("amber", Amber), #("violet", Violet)]
}

fn enum_decoder(values: List(#(String, a)), fallback: a) -> Decoder(a) {
  use value <- decode.then(decode.string)
  case list.find(values, fn(pair) { pair.0 == value }) {
    Ok(#(_, found)) -> decode.success(found)
    Error(_) -> decode.failure(fallback, "Recognized selection value")
  }
}

fn fixed_key(field: FixedField) -> String {
  let assert Ok(#(key, _)) =
    list.find(fixed_fields(), fn(pair) { pair.1 == field })
  key
}

fn color_key(color: Color) -> String {
  let assert Ok(#(key, _)) = list.find(colors(), fn(pair) { pair.1 == color })
  key
}

fn milestone_key(field: MilestoneField) -> String {
  case field {
    MilestoneTitle -> "title"
    Completed -> "completed"
  }
}

pub fn field_key(field: Field) -> String {
  case field {
    Fixed(field) -> fixed_key(field)
    Milestone(id, field) -> "milestone/" <> id <> "/" <> milestone_key(field)
  }
}

fn encode_field(field: Field) -> Json {
  case field {
    Fixed(field) ->
      json.object([
        #("kind", json.string("fixed")),
        #("field", json.string(fixed_key(field))),
      ])
    Milestone(id, field) ->
      json.object([
        #("kind", json.string("milestone")),
        #("id", json.string(id)),
        #("field", json.string(milestone_key(field))),
      ])
  }
}

/// Limit display names to 80 Unicode code points. Render names as plain text.
fn display_name(name: String) -> String {
  name
  |> string.to_utf_codepoints
  |> list.take(80)
  |> string.from_utf_codepoints
}

pub fn encode(metadata: Metadata) -> Json {
  json.object([
    #("name", json.string(display_name(metadata.name))),
    #("color", json.string(color_key(metadata.color))),
    #("token", json.int(metadata.token)),
    #("selected", case metadata.selected {
      None -> json.null()
      Some(field) -> encode_field(field)
    }),
  ])
}

fn field_decoder() -> Decoder(Field) {
  use kind <- decode.field("kind", decode.string)
  case kind {
    "fixed" -> {
      use field <- decode.field("field", enum_decoder(fixed_fields(), Title))
      decode.success(Fixed(field))
    }
    "milestone" -> {
      use id <- decode.field("id", decode.string)
      use field <- decode.field(
        "field",
        enum_decoder(
          [#("title", MilestoneTitle), #("completed", Completed)],
          MilestoneTitle,
        ),
      )
      case id != "" && !string.contains(id, "/") {
        True -> decode.success(Milestone(id, field))
        False -> decode.failure(Fixed(Title), "Nonempty milestone ID without /")
      }
    }
    _ -> decode.failure(Fixed(Title), "Recognized selection target")
  }
}

pub fn decoder() -> Decoder(Metadata) {
  use name <- decode.field("name", decode.string)
  use color <- decode.field("color", enum_decoder(colors(), Blue))
  use token <- decode.field("token", decode.int)
  use selected <- decode.field("selected", decode.optional(field_decoder()))
  case token >= 0 && token <= 9_007_199_254_740_991 {
    True -> decode.success(Metadata(display_name(name), color, token, selected))
    False ->
      decode.failure(
        Metadata("", Blue, 0, None),
        "Nonnegative safe selection token",
      )
  }
}

pub fn available(field: Field, value: ProjectBrief) -> Bool {
  case field {
    Fixed(ReviewReviewer) | Fixed(ReviewApproved) -> value.review != None
    Fixed(_) -> True
    Milestone(id, _) ->
      list.any(value.schedule.milestones, fn(item) { item.id == id })
  }
}

pub fn focus(metadata: Metadata, selected: Option(Field)) -> Metadata {
  case metadata.selected == selected {
    True -> metadata
    False -> Metadata(..metadata, token: metadata.token + 1, selected: selected)
  }
}

pub fn reconcile_local(metadata: Metadata, value: ProjectBrief) -> Metadata {
  case metadata.selected {
    Some(field) ->
      case available(field, value) {
        True -> metadata
        False -> focus(metadata, None)
      }
    None -> metadata
  }
}

/// Use the existing driver for the heartbeat, expiry, and connection state.
pub fn config() -> presence.Config(Metadata) {
  presence.config(encode, decoder()) |> presence.with_mode(presence.Ripple)
}

pub fn new() -> Policy {
  Policy(dict.new(), dict.new(), [])
}

pub fn peers(policy: Policy) -> List(presence.PresenceEntry(Metadata)) {
  policy.peers
}

/// Keep token watermarks until the view closes, including expired sessions.
pub fn reconcile(
  policy: Policy,
  entries: List(presence.PresenceEntry(Metadata)),
  value: ProjectBrief,
) -> Policy {
  let latest =
    list.fold(entries, policy.latest, fn(latest, peer) {
      let metadata = case dict.get(latest, peer.session_id) {
        Ok(old) if old.token >= peer.meta.token -> old
        _ -> peer.meta
      }
      dict.insert(latest, peer.session_id, metadata)
    })
  let invalid =
    dict.fold(latest, policy.invalid, fn(invalid, id, metadata) {
      case metadata.selected {
        Some(field) ->
          case available(field, value) {
            True -> invalid
            False -> dict.insert(invalid, id, metadata.token)
          }
        None -> invalid
      }
    })
  let peers =
    list.map(entries, fn(peer) {
      let assert Ok(metadata) = dict.get(latest, peer.session_id)
      let metadata = case dict.get(invalid, peer.session_id) {
        Ok(token) if metadata.token <= token ->
          Metadata(..metadata, selected: None)
        _ -> metadata
      }
      presence.PresenceEntry(..peer, meta: metadata)
    })
  Policy(latest, invalid, peers)
}

pub fn on_event(
  policy: Policy,
  event: presence.Event(Metadata),
  value: ProjectBrief,
  local_session: String,
) -> Policy {
  case event {
    presence.State(entries) | presence.Changed(_, entries) ->
      reconcile(policy, presence.remote_entries(entries, local_session), value)
    presence.Failed(_) -> policy
  }
}
