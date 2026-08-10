import gleam/list
import gleam/string

/// The three sorted snapshot lists rendered by the triptych.
pub type Snapshots {
  Snapshots(
    grow_only: List(String),
    two_phase: List(String),
    observed: List(String),
  )
}

pub fn empty() -> Snapshots {
  Snapshots(grow_only: [], two_phase: [], observed: [])
}

/// Sort every panel's values so rendering is deterministic across tabs.
pub fn from_values(
  grow_only grow_only: List(String),
  two_phase two_phase: List(String),
  observed observed: List(String),
) -> Snapshots {
  Snapshots(
    grow_only: sort_values(grow_only),
    two_phase: sort_values(two_phase),
    observed: sort_values(observed),
  )
}

/// One rendered row, driven by the union of all three snapshots so absence can
/// still be shown explicitly per panel.
pub type Row {
  Row(item: String, grow_only: Bool, two_phase: Bool, observed: Bool)
}

pub fn rows(snapshots: Snapshots) -> List(Row) {
  let items =
    snapshots.grow_only
    |> list.append(snapshots.two_phase)
    |> list.append(snapshots.observed)
    |> sort_values
    |> list.unique

  list.map(items, fn(item) {
    Row(
      item: item,
      grow_only: list.contains(snapshots.grow_only, item),
      two_phase: list.contains(snapshots.two_phase, item),
      observed: list.contains(snapshots.observed, item),
    )
  })
}

fn sort_values(values: List(String)) -> List(String) {
  list.sort(values, string.compare)
}
