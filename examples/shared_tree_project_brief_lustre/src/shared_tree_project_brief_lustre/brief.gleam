//// Immutable values decoded from the shared tree. Node references live in edits.

import gleam/list
import gleam/option.{type Option, None}
import gleam/set

pub type Milestone {
  Milestone(id: String, title: String, completed: Bool)
}

pub type Owner {
  Owner(name: String, email: String)
}

pub type Schedule {
  // Dates remain strings so incomplete text is valid while an editor types.
  Schedule(start: String, target: String, milestones: List(Milestone))
}

pub type Review {
  Review(reviewer: String, approved: Bool)
}

pub type ProjectBrief {
  ProjectBrief(
    title: String,
    owner: Owner,
    schedule: Schedule,
    review: Option(Review),
  )
}

pub fn initial(first_id: String, second_id: String) -> ProjectBrief {
  ProjectBrief(
    title: "Release brief",
    owner: Owner("Alex", "alex@example.test"),
    schedule: Schedule("2026-11-02", "2026-11-16", [
      Milestone(first_id, "Agree scope", False),
      Milestone(second_id, "Ship preview", False),
    ]),
    review: None,
  )
}

// IDs belong to the application, not the array position or tree node identity.
// They must be unique because the form uses them for row keys and selections.
pub fn validate_unique_ids(items: List(Milestone)) -> Result(Nil, String) {
  let ids = list.map(items, fn(item) { item.id }) |> set.from_list
  case set.size(ids) == list.length(items) {
    True -> Ok(Nil)
    False -> Error("Duplicate milestone IDs")
  }
}
