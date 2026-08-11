import gleam/option.{type Option, None, Some}

pub type Puzzle {
  Puzzle(id: String, name: String, givens: List(Int), solution: List(Int))
}

pub fn default_puzzle() -> Puzzle {
  let assert Some(puzzle) = by_id("classic")
  puzzle
}

pub fn by_id(id: String) -> Option(Puzzle) {
  puzzles()
  |> find(fn(puzzle) { puzzle.id == id })
}

pub fn puzzles() -> List(Puzzle) {
  [classic(), gentle(), sparse()]
}

pub fn given_at(puzzle: Puzzle, row: Int, col: Int) -> Int {
  value_at(puzzle.givens, row, col)
}

pub fn solution_at(puzzle: Puzzle, row: Int, col: Int) -> Int {
  value_at(puzzle.solution, row, col)
}

pub fn is_given(puzzle: Puzzle, row: Int, col: Int) -> Bool {
  given_at(puzzle, row, col) != 0
}

fn value_at(values: List(Int), row: Int, col: Int) -> Int {
  nth(values, row * 9 + col)
  |> option.unwrap(0)
}

fn nth(values: List(a), index: Int) -> Option(a) {
  case values, index {
    [], _ -> None
    [first, ..], 0 -> Some(first)
    [_, ..rest], _ -> nth(rest, index - 1)
  }
}

fn find(values: List(a), predicate: fn(a) -> Bool) -> Option(a) {
  case values {
    [] -> None
    [first, ..rest] ->
      case predicate(first) {
        True -> Some(first)
        False -> find(rest, predicate)
      }
  }
}

fn classic() -> Puzzle {
  Puzzle(
    id: "classic",
    name: "Classic warm-up",
    givens: [
      5, 3, 0, 0, 7, 0, 0, 0, 0, 6, 0, 0, 1, 9, 5, 0, 0, 0, 0, 9, 8, 0, 0, 0, 0,
      6, 0, 8, 0, 0, 0, 6, 0, 0, 0, 3, 4, 0, 0, 8, 0, 3, 0, 0, 1, 7, 0, 0, 0, 2,
      0, 0, 0, 6, 0, 6, 0, 0, 0, 0, 2, 8, 0, 0, 0, 0, 4, 1, 9, 0, 0, 5, 0, 0, 0,
      0, 8, 0, 0, 7, 9,
    ],
    solution: [
      5, 3, 4, 6, 7, 8, 9, 1, 2, 6, 7, 2, 1, 9, 5, 3, 4, 8, 1, 9, 8, 3, 4, 2, 5,
      6, 7, 8, 5, 9, 7, 6, 1, 4, 2, 3, 4, 2, 6, 8, 5, 3, 7, 9, 1, 7, 1, 3, 9, 2,
      4, 8, 5, 6, 9, 6, 1, 5, 3, 7, 2, 8, 4, 2, 8, 7, 4, 1, 9, 6, 3, 5, 3, 4, 5,
      2, 8, 6, 1, 7, 9,
    ],
  )
}

fn gentle() -> Puzzle {
  Puzzle(
    id: "gentle",
    name: "Gentle co-op",
    givens: [
      0, 0, 0, 2, 6, 0, 7, 0, 1, 6, 8, 0, 0, 7, 0, 0, 9, 0, 1, 9, 0, 0, 0, 4, 5,
      0, 0, 8, 2, 0, 1, 0, 0, 0, 4, 0, 0, 0, 4, 6, 0, 2, 9, 0, 0, 0, 5, 0, 0, 0,
      3, 0, 2, 8, 0, 0, 9, 3, 0, 0, 0, 7, 4, 0, 4, 0, 0, 5, 0, 0, 3, 6, 7, 0, 3,
      0, 1, 8, 0, 0, 0,
    ],
    solution: [
      4, 3, 5, 2, 6, 9, 7, 8, 1, 6, 8, 2, 5, 7, 1, 4, 9, 3, 1, 9, 7, 8, 3, 4, 5,
      6, 2, 8, 2, 6, 1, 9, 5, 3, 4, 7, 3, 7, 4, 6, 8, 2, 9, 1, 5, 9, 5, 1, 7, 4,
      3, 6, 2, 8, 5, 1, 9, 3, 2, 6, 8, 7, 4, 2, 4, 8, 9, 5, 7, 1, 3, 6, 7, 6, 3,
      4, 1, 8, 2, 5, 9,
    ],
  )
}

fn sparse() -> Puzzle {
  Puzzle(
    id: "sparse",
    name: "Sparse classic",
    givens: [
      0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 8, 0, 0, 0, 7, 0, 9, 0, 6, 0, 2, 0, 0, 0, 5,
      0, 0, 0, 7, 0, 0, 6, 0, 0, 0, 0, 0, 0, 0, 9, 0, 1, 0, 0, 0, 0, 0, 0, 0, 2,
      0, 0, 4, 0, 0, 0, 5, 0, 0, 0, 6, 0, 3, 0, 9, 0, 4, 0, 0, 0, 7, 0, 0, 0, 6,
      0, 0, 0, 0, 0, 0,
    ],
    solution: [
      9, 5, 7, 6, 1, 3, 2, 8, 4, 4, 8, 3, 2, 5, 7, 1, 9, 6, 6, 1, 2, 8, 4, 9, 5,
      3, 7, 1, 7, 8, 3, 6, 4, 9, 5, 2, 5, 2, 4, 9, 7, 1, 3, 6, 8, 3, 6, 9, 5, 2,
      8, 7, 4, 1, 8, 4, 5, 7, 9, 2, 6, 1, 3, 2, 9, 1, 4, 3, 6, 8, 7, 5, 7, 3, 6,
      1, 8, 5, 4, 2, 9,
    ],
  )
}
