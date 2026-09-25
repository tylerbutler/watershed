import gleam/list
@target(erlang)
import gleam/option.{None, Some}
import gleam/string
import startest/expect
import watershed/container
import watershed/git_storage
@target(erlang)
import watershed/tree/schema
@target(erlang)
import watershed/tree/types

@target(erlang)
fn stored() -> schema.StoredSchema {
  let assert Ok(stored) =
    schema.stored_from_string(
      "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.string\":{\"kind\":{\"leaf\":1}}},\"root\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.string\"]}}",
    )
  stored
}

@target(erlang)
pub fn shared_tree_creation_checks_initial_value_before_network_test() -> Nil {
  let assert Error(container.InvalidInitialTree(_)) =
    container.create_tree(
      container.CreateConfig("http://127.0.0.1:1", "tenant", "not-a-secret"),
      stored(),
      None,
    )
  Nil
}

@target(erlang)
pub fn shared_tree_creation_rejects_unsafe_configuration_test() -> Nil {
  list.each(
    [
      container.CreateConfig("file:///tmp/create", "tenant", "token"),
      container.CreateConfig("http://user:pass@127.0.0.1", "tenant", "token"),
      container.CreateConfig("http://127.0.0.1?token=secret", "tenant", "token"),
      container.CreateConfig("http://127.0.0.1#fragment", "tenant", "token"),
      container.CreateConfig("http://127.0.0.1:65536", "tenant", "token"),
      container.CreateConfig("http://bad host", "tenant", "token"),
      container.CreateConfig("http://127.0.0.1", "", "token"),
      container.CreateConfig("http://127.0.0.1", "tenant", ""),
      container.CreateConfig("http://127.0.0.1:1", ".", "token"),
      container.CreateConfig("http://127.0.0.1:1", "..", "token"),
      container.CreateConfig("http://127.0.0.1:1", "tenant", "bad\u{0}token"),
      container.CreateConfig("http://127.0.0.1:1", "tenant", "bad token"),
      container.CreateConfig("http://127.0.0.1:1", "tenant", "bad\u{2603}token"),
    ],
    fn(config) {
      let assert Error(container.InvalidConfiguration(_)) =
        container.create_tree(
          config,
          stored(),
          Some(types.StringValue("initial")),
        )
      Nil
    },
  )
}

pub fn shared_tree_creation_storage_errors_do_not_echo_credentials_test() -> Nil {
  list.each(
    [
      git_storage.UnexpectedStatus("secret", 401, "secret"),
      git_storage.UnexpectedStatus("secret", 500, "secret"),
      git_storage.RequestFailed("secret", "secret"),
      git_storage.BodyReadFailed("secret", "secret"),
      git_storage.ResponseDecodeFailed("secret", "secret"),
      git_storage.BadRequestUrl("secret"),
    ],
    fn(error) {
      container.error_to_string(container.StorageFailed(error))
      |> string.contains("secret")
      |> expect.to_equal(False)
    },
  )
}
