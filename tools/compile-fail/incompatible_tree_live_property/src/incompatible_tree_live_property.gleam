import watershed/tree/error
import watershed/tree as live
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
) -> Result(String, error.Error) {
  live.get(reference, field)
}
