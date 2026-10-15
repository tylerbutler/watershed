import gleam/option.{Some}
import watershed/tree/schema_builder as builder

pub fn invalid() {
  builder.variant(builder.string(), fn(value: Float) { value }, fn(value) {
    Some(value)
  })
}
