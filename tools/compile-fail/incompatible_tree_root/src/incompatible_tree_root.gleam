@target(javascript)
import watershed as client
import watershed/container
import watershed/tree/schema_builder as builder
@target(erlang)
import watershed_beam as client

pub fn invalid(schema: builder.Root(String)) {
  client.with_initial_tree(container.layout(), "A", "tree", schema, 42)
}
