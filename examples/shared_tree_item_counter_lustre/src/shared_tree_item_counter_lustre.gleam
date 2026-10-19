import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import shared_tree_item_counter_lustre/counter
import shared_tree_item_counter_lustre/schema as document_schema
import watershed
import watershed/id
import watershed/tree as shared_tree
import watershed/tree/error as tree_error
import watershed_lustre
import watershed_lustre/tree

type Phase {
  Creating
  Connecting
  Ready
  Failed
  Closed
}

type Config {
  Config(base_url: String, tenant: String, secret: String)
}

type Model {
  Model(
    config: Config,
    phase: Phase,
    document_id: String,
    document: Option(watershed.Document(Nil)),
    tree: Option(shared_tree.Tree(List(String))),
    subscription: Option(shared_tree.Subscription),
    count: Int,
    busy: Bool,
    errors: List(String),
  )
}

type Msg {
  Created(Result(String, tree_error.Error))
  GotDocument(watershed.Document(Nil))
  Connected(Result(Nil, String))
  Opened(Result(shared_tree.Tree(List(String)), tree_error.Error))
  Subscribed(Result(shared_tree.Subscription, tree_error.Error))
  Read(Result(List(String), tree_error.Error))
  Edit(counter.Action)
  Edited(Result(Nil, tree_error.Error))
  Close
}

@external(javascript, "./shared_tree_item_counter_lustre_ffi.mjs", "queryParameter")
fn query_parameter(name: String, fallback: String) -> String

@external(javascript, "./shared_tree_item_counter_lustre_ffi.mjs", "currentOrigin")
fn current_origin() -> String

@external(javascript, "./shared_tree_item_counter_lustre_ffi.mjs", "proxyFloodgateHttp")
fn proxy_floodgate_http(upstream: String) -> Nil

@external(javascript, "./shared_tree_item_counter_lustre_ffi.mjs", "replaceDocument")
fn replace_document(document_id: String) -> Nil

pub fn main() -> Nil {
  let assert Ok(_) =
    lustre.application(init, update, view)
    |> lustre.start("#app", Nil)
  Nil
}

fn init(_argument: Nil) -> #(Model, Effect(Msg)) {
  proxy_floodgate_http("http://127.0.0.1:4000")
  let config =
    Config(
      base_url: query_parameter("base", current_origin()),
      tenant: query_parameter("tenant", "dev-tenant"),
      secret: query_parameter("secret", "levee-dev-secret-change-in-production"),
    )
  let document_id = query_parameter("document", "")
  let model =
    Model(
      config: config,
      phase: case document_id {
        "" -> Creating
        _ -> Connecting
      },
      document_id: document_id,
      document: None,
      tree: None,
      subscription: None,
      count: 0,
      busy: False,
      errors: [],
    )
  // docs:snippet-start item-counter-watershed-create
  // Select create or load from the URL document ID, as loadFluidData does.
  case document_id {
    // Create with the schema and empty root. No separate attach is needed.
    "" -> #(
      model,
      tree.create_dev(
        config.base_url,
        config.tenant,
        config.secret,
        document_schema.configuration(),
        [],
        Created,
      ),
    )
    id -> #(model, connect(config, id))
  }
  // docs:snippet-end item-counter-watershed-create
}

fn connect(config: Config, document_id: String) -> Effect(Msg) {
  watershed_lustre.connect_dev(
    url: "ws://127.0.0.1:4000/socket/websocket?vsn=2.0.0",
    tenant: config.tenant,
    secret: config.secret,
    document: document_id,
    user_id: "item-counter-" <> id.uuid_v4(),
    got_document: GotDocument,
    connected: Connected,
  )
}

fn update(model: Model, message: Msg) -> #(Model, Effect(Msg)) {
  case model.phase, message {
    Closed, Subscribed(Ok(subscription)) -> #(
      model,
      tree.unsubscribe(subscription),
    )
    Closed, GotDocument(document) -> #(
      model,
      effect.from(fn(_) { watershed.close(document) }),
    )
    Closed, _ -> #(model, effect.none())
    _, _ -> update_active(model, message)
  }
}

fn update_active(model: Model, message: Msg) -> #(Model, Effect(Msg)) {
  case message {
    // docs:snippet-start item-counter-watershed-open
    Created(Ok(document_id)) -> {
      // Keep the new ID in the URL, as the container.attach result is kept.
      replace_document(document_id)
      #(
        Model(..model, phase: Connecting, document_id: document_id),
        connect(model.config, document_id),
      )
    }
    Created(Error(detail)) ->
      fail(
        model,
        "Creation failed. The service might have created a document whose ID was not received. Do not retry automatically: "
          <> tree_error.to_string(detail),
      )
    GotDocument(document) -> #(
      Model(..model, document: Some(document)),
      effect.none(),
    )
    Connected(Error(detail)) -> fail(model, detail)
    Connected(Ok(Nil)) ->
      case model.document {
        Some(document) -> #(
          model,
          // Open the view, as viewWith does. Creation initialized the root.
          tree.open(document, document_schema.configuration(), Opened),
        )
        None -> fail(model, "Connection completed without a document handle")
      }
    // docs:snippet-end item-counter-watershed-open
    Opened(Error(detail)) -> fail(model, tree_error.to_string(detail))
    // docs:snippet-start item-counter-watershed-observe
    Opened(Ok(shared_tree)) -> #(
      Model(..model, tree: Some(shared_tree)),
      effect.batch([
        // Register for changes, as Tree.on does, and read the initial count.
        tree.observe(shared_tree, Subscribed, Read),
        tree.read_root(shared_tree, Read),
      ]),
    )
    Subscribed(Error(detail)) -> fail(model, tree_error.to_string(detail))
    Subscribed(Ok(subscription)) -> #(
      // Keep the token for unsubscribe when the view closes.
      Model(..model, subscription: Some(subscription)),
      effect.none(),
    )
    Read(Error(detail)) -> fail(model, tree_error.to_string(detail))
    Read(Ok(values)) -> #(
      Model(..model, phase: Ready, count: list.length(values)),
      effect.none(),
    )
    // docs:snippet-end item-counter-watershed-observe
    // docs:snippet-start item-counter-watershed-apply
    Edit(action) ->
      case model.phase, model.busy, model.tree {
        Ready, False, Some(shared_tree) -> #(
          Model(..model, busy: True),
          tree.perform(fn() { counter.apply(shared_tree, action) }, Edited),
        )
        _, _, _ -> #(model, effect.none())
      }
    // docs:snippet-end item-counter-watershed-apply
    Edited(Ok(Nil)) -> #(Model(..model, busy: False), effect.none())
    Edited(Error(detail)) ->
      fail(Model(..model, busy: False), tree_error.to_string(detail))
    Close -> {
      let cleanup = case model.subscription {
        Some(subscription) -> tree.unsubscribe(subscription)
        None -> effect.none()
      }
      let close = case model.document {
        Some(document) -> effect.from(fn(_) { watershed.close(document) })
        None -> effect.none()
      }
      #(
        Model(
          ..model,
          phase: Closed,
          document: None,
          tree: None,
          subscription: None,
        ),
        effect.batch([cleanup, close]),
      )
    }
  }
}

fn fail(model: Model, detail: String) -> #(Model, Effect(Msg)) {
  #(
    Model(..model, phase: Failed, errors: [detail, ..model.errors]),
    effect.none(),
  )
}

fn phase_name(phase: Phase) -> String {
  case phase {
    Creating -> "creating"
    Connecting -> "connecting"
    Ready -> "ready"
    Failed -> "failed"
    Closed -> "closed"
  }
}

fn view(model: Model) -> Element(Msg) {
  let ready = model.phase == Ready && !model.busy
  let can_close = case model.document {
    Some(_) -> model.phase != Closed
    None -> False
  }
  html.div([], [
    html.h1([], [html.text("SharedTree item counter")]),
    html.p([], [
      html.text("One shared array. Copy this URL into another tab."),
    ]),
    html.p(
      [
        attribute.attribute("data-runtime-status", phase_name(model.phase)),
        attribute.attribute("role", "status"),
      ],
      [html.text(phase_name(model.phase))],
    ),
    html.p([attribute.attribute("data-document-id", model.document_id)], [
      html.text("document: " <> model.document_id),
    ]),
    html.div(
      [
        attribute.attribute("data-count", int.to_string(model.count)),
        attribute.attribute("aria-label", "Item count"),
        attribute.attribute("aria-live", "polite"),
      ],
      [html.text(int.to_string(model.count))],
    ),
    html.div([], [
      button("insert", "Insert", Edit(counter.Insert), !ready),
      button("remove", "Remove", Edit(counter.Remove), !ready),
      button("close", "Close", Close, !can_close),
    ]),
    html.div(
      [attribute.attribute("role", "alert")],
      list.map(list.reverse(model.errors), fn(detail) {
        html.p([attribute.attribute("data-error", "")], [html.text(detail)])
      }),
    ),
    html.p([attribute.attribute("data-development-auth", "")], [
      html.text(
        "Development authentication only. Production apps must obtain tokens from a backend.",
      ),
    ]),
    html.a(
      [
        attribute.href(
          "https://watershed.tylerbutler.com/sharedtree/item-counter",
        ),
      ],
      [html.text("Compare this source with Fluid")],
    ),
  ])
}

fn button(
  action: String,
  label: String,
  message: Msg,
  disabled: Bool,
) -> Element(Msg) {
  html.button(
    [
      attribute.type_("button"),
      attribute.attribute("data-action", action),
      attribute.disabled(disabled),
      event.on_click(message),
    ],
    [html.text(label)],
  )
}
