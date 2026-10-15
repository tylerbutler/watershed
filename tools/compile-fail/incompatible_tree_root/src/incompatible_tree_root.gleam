import watershed/tree/schema_builder as builder

pub fn invalid(schema: builder.Compiled(String)) {
  builder.encode(schema, 42)
}
