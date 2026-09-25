import argv
import envoy
@target(erlang)
import gleam/erlang/process
import gleam/int
import gleam/io
@target(javascript)
import gleam/javascript/promise.{type Promise}
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import shared_tree_cli/schema
@target(javascript)
import watershed as client
import watershed/container
import watershed/tree/types
@target(erlang)
import watershed_beam as client

pub type Command {
  Create
  Open(String)
  SetTitle(String, String)
}

pub fn parse(arguments: List(String)) -> Result(Command, String) {
  case arguments {
    ["create"] -> Ok(Create)
    ["open", id] if id != "" -> Ok(Open(id))
    ["set-title", id, text] if id != "" -> Ok(SetTitle(id, text))
    _ -> Error("usage: create | open <id> | set-title <id> <text>")
  }
}

type Config {
  Config(host: String, port: Int, tenant: String, secret: String)
}

fn setting(name: String) -> Result(String, String) {
  use value <- result.try(
    envoy.get(name) |> result.replace_error(missing_setting(name)),
  )
  case string.trim(value) {
    "" -> Error(missing_setting(name))
    _ -> Ok(value)
  }
}

fn missing_setting(name: String) -> String {
  "set " <> name <> " before running this example"
}

fn config() -> Result(Config, String) {
  use host <- result.try(setting("WATERSHED_HOST"))
  use port <- result.try(setting("WATERSHED_PORT"))
  use port <- result.try(
    int.parse(port) |> result.replace_error("WATERSHED_PORT must be an integer"),
  )
  use _ <- result.try(case port > 0 && port <= 65_535 {
    True -> Ok(Nil)
    False -> Error("WATERSHED_PORT must be between 1 and 65535")
  })
  use tenant <- result.try(setting("WATERSHED_TENANT"))
  use secret <- result.try(setting("WATERSHED_SECRET"))
  Ok(Config(host, port, tenant, secret))
}

fn base_url(config: Config) -> String {
  "http://" <> config.host <> ":" <> int.to_string(config.port)
}

fn input() -> Result(#(Command, Config), String) {
  use command <- result.try(parse(argv.load().arguments))
  use config <- result.try(config())
  Ok(#(command, config))
}

fn finish(result: Result(Nil, String)) -> Nil {
  case result {
    Ok(Nil) -> exit(0)
    Error(error) -> {
      io.println_error(error)
      exit(1)
    }
  }
}

@external(erlang, "erlang", "halt")
@external(javascript, "./shared_tree_cli_ffi.mjs", "exit")
fn exit(status: Int) -> Nil

@target(erlang)
pub fn main() -> Nil {
  let outcome = {
    use #(command, config) <- result.try(input())
    run(command, config)
  }
  finish(outcome)
}

@target(javascript)
pub fn main() -> Promise(Nil) {
  case input() {
    Error(error) -> {
      finish(Error(error))
      promise.resolve(Nil)
    }
    Ok(#(command, config)) -> run(command, config) |> promise.map(finish)
  }
}

@target(erlang)
fn run(command: Command, config: Config) -> Result(Nil, String) {
  case command {
    Create -> {
      let token = token(config, "")
      use id <- result.try(client.create_tree_container(
        container.CreateConfig(base_url(config), config.tenant, token),
        schema.stored(),
        Some(schema.initial()),
      ))
      io.println("document: " <> id)
      open(config, id, None)
    }
    Open(id) -> open(config, id, None)
    SetTitle(id, title) -> open(config, id, Some(title))
  }
}

@target(javascript)
fn run(command: Command, config: Config) -> Promise(Result(Nil, String)) {
  case command {
    Create -> {
      use token <- promise.await(token(config, ""))
      use id <- promise.try_await(client.create_tree_container(
        container.CreateConfig(base_url(config), config.tenant, token),
        schema.stored(),
        Some(schema.initial()),
      ))
      io.println("document: " <> id)
      open(config, id, None)
    }
    Open(id) -> open(config, id, None)
    SetTitle(id, title) -> open(config, id, Some(title))
  }
}

@target(erlang)
fn token(config: Config, id: String) -> String {
  client.dev_token(config.secret, config.tenant, id, "shared-tree-cli")
}

@target(javascript)
fn token(config: Config, id: String) -> Promise(String) {
  client.dev_token(config.secret, config.tenant, id, "shared-tree-cli")
}

@target(erlang)
fn open(
  config: Config,
  id: String,
  title: Option(String),
) -> Result(Nil, String) {
  use document <- result.try(client.connect(
    host: config.host,
    port: config.port,
    tenant: config.tenant,
    document: id,
    token: token(config, id),
    user_id: "shared-tree-cli",
  ))
  let outcome = {
    use tree <- result.try(edit(document, title))
    use _ <- result.try(await_synced(document, 200))
    print_tree(tree)
  }
  client.close(document)
  outcome
}

@target(javascript)
fn open(
  config: Config,
  id: String,
  title: Option(String),
) -> Promise(Result(Nil, String)) {
  use token <- promise.await(token(config, id))
  let #(ready, resolve) = promise.start()
  let document =
    client.connect(
      client.WatershedConfig(
        "ws://"
          <> config.host
          <> ":"
          <> int.to_string(config.port)
          <> "/socket/websocket?vsn=2.0.0",
        config.tenant,
        id,
        token,
        "shared-tree-cli",
      ),
      resolve,
    )
  use connected <- promise.await(
    promise.race_list([
      ready,
      promise.wait(30_000)
        |> promise.map(fn(_) { Error("connection timed out") }),
    ]),
  )
  let outcome = {
    use _ <- result.try(connected)
    edit(document, title)
  }
  case outcome {
    Error(error) -> {
      client.close(document)
      promise.resolve(Error(error))
    }
    Ok(tree) -> {
      use synced <- promise.await(await_synced(document, 200))
      let outcome = {
        use _ <- result.try(synced)
        print_tree(tree)
      }
      client.close(document)
      promise.resolve(outcome)
    }
  }
}

fn edit(
  document: client.Document(root),
  title: Option(String),
) -> Result(client.SharedTree, String) {
  use root <- result.try(client.resolve_root(document))
  use handle <- result.try(
    client.get(root, "tree") |> result.replace_error("tree handle is absent"),
  )
  use tree <- result.try(client.resolve_tree(document, handle, schema.view()))
  use _ <- result.try(case title {
    None -> Ok(Nil)
    Some(title) -> client.tree_set(tree, ["title"], types.StringValue(title))
  })
  Ok(tree)
}

fn print_tree(tree: client.SharedTree) -> Result(Nil, String) {
  use root <- result.try(client.tree_get(tree, []))
  io.println(string.inspect(root))
  Ok(Nil)
}

@target(erlang)
fn await_synced(
  document: client.Document(root),
  attempts: Int,
) -> Result(Nil, String) {
  case client.is_synced(document), attempts {
    True, _ -> Ok(Nil)
    False, 0 -> Error("synchronization timed out; the edit is not confirmed")
    False, _ -> {
      process.sleep(50)
      await_synced(document, attempts - 1)
    }
  }
}

@target(javascript)
fn await_synced(
  document: client.Document(root),
  attempts: Int,
) -> Promise(Result(Nil, String)) {
  case client.is_synced(document), attempts {
    True, _ -> promise.resolve(Ok(Nil))
    False, 0 ->
      promise.resolve(Error(
        "synchronization timed out; the edit is not confirmed",
      ))
    False, _ -> {
      use _ <- promise.await(promise.wait(50))
      await_synced(document, attempts - 1)
    }
  }
}
