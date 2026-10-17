import watershed/tree/error
import watershed/tree as live

pub type Card {
  Card(title: String)
}

pub fn invalid(
  items: live.Ref(List(Card)),
  card: live.Ref(Card),
) -> Result(Nil, error.Error) {
  live.array_insert(items, 0, [card])
}
