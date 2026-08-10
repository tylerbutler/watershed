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
  Row(
    item: String,
    grow_only: Bool,
    two_phase: Bool,
    observed: Bool,
    diverges: Bool,
  )
}

pub type DiffCounts {
  DiffCounts(grow_only: Int, two_phase: Int, observed: Int)
}

pub fn empty_diff_counts() -> DiffCounts {
  DiffCounts(grow_only: 0, two_phase: 0, observed: 0)
}

pub fn rows(snapshots: Snapshots) -> List(Row) {
  let items =
    snapshots.grow_only
    |> list.append(snapshots.two_phase)
    |> list.append(snapshots.observed)
    |> sort_values
    |> list.unique

  list.map(items, fn(item) {
    let grow_only = list.contains(snapshots.grow_only, item)
    let two_phase = list.contains(snapshots.two_phase, item)
    let observed = list.contains(snapshots.observed, item)

    Row(
      item: item,
      grow_only: grow_only,
      two_phase: two_phase,
      observed: observed,
      diverges: row_diverges(grow_only, two_phase, observed),
    )
  })
}

pub fn diff_counts(rows: List(Row)) -> DiffCounts {
  list.fold(rows, empty_diff_counts(), fn(counts, row) {
    DiffCounts(
      grow_only: maybe_increment(counts.grow_only, grow_only_differs(row)),
      two_phase: maybe_increment(counts.two_phase, two_phase_differs(row)),
      observed: maybe_increment(counts.observed, observed_differs(row)),
    )
  })
}

pub fn grow_only_differs(row: Row) -> Bool {
  row.grow_only != row.two_phase && row.grow_only != row.observed
}

pub fn two_phase_differs(row: Row) -> Bool {
  row.two_phase != row.grow_only && row.two_phase != row.observed
}

pub fn observed_differs(row: Row) -> Bool {
  row.observed != row.grow_only && row.observed != row.two_phase
}

fn maybe_increment(total: Int, should_increment: Bool) -> Int {
  case should_increment {
    True -> total + 1
    False -> total
  }
}

fn row_diverges(grow_only: Bool, two_phase: Bool, observed: Bool) -> Bool {
  grow_only != two_phase || grow_only != observed
}

fn sort_values(values: List(String)) -> List(String) {
  list.sort(values, string.compare)
}
