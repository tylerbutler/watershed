import gleam/list
import gleam/option.{type Option, None, Some}

pub type Slug {
  Connect
  Notes
  Race
  Votes
  Presence
  Testing
}

pub type Step {
  Step(number: String, slug: Slug, title: String, goal: String, surface: String)
}

pub fn all() -> List(Step) {
  list.map([Connect, Notes, Race, Votes, Presence, Testing], get)
}

pub fn from_string(value: String) -> Result(Slug, Nil) {
  case value {
    "connect" -> Ok(Connect)
    "notes" -> Ok(Notes)
    "race" -> Ok(Race)
    "votes" -> Ok(Votes)
    "presence" -> Ok(Presence)
    "testing" -> Ok(Testing)
    _ -> Error(Nil)
  }
}

pub fn path(slug: Slug) -> String {
  "/guide/"
  <> case slug {
    Connect -> "connect"
    Notes -> "notes"
    Race -> "race"
    Votes -> "votes"
    Presence -> "presence"
    Testing -> "testing"
  }
}

pub fn get(slug: Slug) -> Step {
  case slug {
    Connect ->
      Step(
        "01",
        slug,
        "Connect the board",
        "Open the same empty board in two browser tabs.",
        "connect_dev · root_typed · ensure_or_map · subscribe",
      )
    Notes ->
      Step(
        "02",
        slug,
        "Add notes",
        "Create a note and watch it show up in both tabs.",
        "RegisterMode · or_map_set_json · or_map_entries",
      )
    Race ->
      Step(
        "03",
        slug,
        "Try two edits at once",
        "Add notes from both tabs at the same instant and confirm both appear.",
        "sluice · or_map_set_json · or_map_entries",
      )
    Votes ->
      Step(
        "04",
        slug,
        "Add votes",
        "Build a vote count that stays correct even when clicks overlap.",
        "TallyMode · or_map_increment · Tally",
      )
    Presence ->
      Step(
        "05",
        slug,
        "Add presence",
        "Show who is looking at each note, and clear it when they leave.",
        "presence.config · watershed_lustre.presence · update_presence",
      )
    Testing ->
      Step(
        "06",
        slug,
        "Write repeatable tests",
        "Turn the two-tab checks you've been running by hand into tests you can run anytime.",
        "sluice_js · start · settle · step",
      )
  }
}

pub fn neighbours(slug: Slug) -> #(Option(Step), Option(Step)) {
  case slug {
    Connect -> #(None, Some(get(Notes)))
    Notes -> #(Some(get(Connect)), Some(get(Race)))
    Race -> #(Some(get(Notes)), Some(get(Votes)))
    Votes -> #(Some(get(Race)), Some(get(Presence)))
    Presence -> #(Some(get(Votes)), Some(get(Testing)))
    Testing -> #(Some(get(Presence)), None)
  }
}
