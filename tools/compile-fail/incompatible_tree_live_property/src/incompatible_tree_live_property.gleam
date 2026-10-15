import watershed/tree/live
import watershed/tree/live_types
import watershed/tree/schema_builder as builder

pub type Card {
  Card(title: String)
}

pub type Person {
  Person(name: String)
}

pub fn invalid(
  reference: live.Ref(Card),
  field: builder.Property(Person, String),
) -> Result(String, live_types.LiveError) {
  live.get(reference, field)
}
