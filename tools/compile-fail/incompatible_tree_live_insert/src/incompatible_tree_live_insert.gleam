import watershed/tree as live
import watershed/tree/error

pub type Card {
  Card(title: String)
}

pub fn invalid(
  items: live.Ref(List(Card)),
  card: live.Ref(Card),
) -> Result(Nil, error.Error) {
  live.array_insert(items, 0, [card])
}

pub fn invalid_collection_value(items: live.Ref(List(Card))) {
  live.array_insert(items, 0, ["not a card"])
}
