import watershed/tree/live
import watershed/tree/live_types

pub type Card {
  Card(title: String)
}

pub fn invalid(
  items: live.Ref(List(Card)),
  card: live.Ref(Card),
) -> Result(Nil, live_types.LiveError) {
  live.array_insert(items, 0, [card])
}
