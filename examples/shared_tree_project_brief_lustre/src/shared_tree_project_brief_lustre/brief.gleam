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

pub fn validate_unique_ids(items: List(Milestone)) -> Result(Nil, String) {
  let ids = list.map(items, fn(item) { item.id }) |> set.from_list
  case set.size(ids) == list.length(items) {
    True -> Ok(Nil)
    False -> Error("Duplicate milestone IDs")
  }
}
