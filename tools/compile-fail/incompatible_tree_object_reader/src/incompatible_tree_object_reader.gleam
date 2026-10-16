import watershed/tree/schema_builder as builder
import watershed/tree/types

pub type Card {
  Card(title: String)
}

pub type Person {
  Person(name: String)
}

pub fn invalid(
  reader: builder.ObjectReader(Card),
) -> Result(String, types.TreeError) {
  let name =
    builder.required("name", builder.string(), fn(v: Person) { v.name })
  builder.read_property(reader, name)
}
