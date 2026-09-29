import gleam/list
import gleam/option.{type Option, None, Some}
import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import shared_tree_checklist_lustre/checklist
import shared_tree_checklist_lustre/schema as document_schema
import watershed
import watershed/id
import watershed/tree/types
import watershed/tree_kernel
import watershed_lustre
import watershed_lustre/tree

const default_host = "127.0.0.1"

const default_port = "4000"

const default_tenant = "dev-tenant"

const default_secret = "levee-dev-secret-change-in-production"

type Config {
  Config(base_url: String, socket_url: String, tenant: String, secret: String)
}

type Phase {
  Creating
  Connecting
  Ready
  Failed(String)
}

type Model {
  Model(
    config: Config,
    phase: Phase,
    document_id: String,
    document: Option(watershed.Document(Nil)),
    tree: Option(watershed.SharedTree),
    subscription: Option(watershed.SubscriptionToken),
    checklist: checklist.Checklist,
    errors: List(String),
  )
}

type Msg {
  Created(Result(String, String))
  GotDocument(watershed.Document(Nil))
  Connected(Result(Nil, String))
  Opened(Result(watershed.SharedTree, String))
  Subscribed(watershed.SubscriptionToken)
  TreeChanged(tree_kernel.TreeEvent)
  Read(Result(Option(types.TreeValue), String))
}

@external(javascript, "./shared_tree_checklist_lustre_ffi.mjs", "queryParameter")
fn query_parameter(name: String, fallback: String) -> String

@external(javascript, "./shared_tree_checklist_lustre_ffi.mjs", "replaceDocument")
fn replace_document(document_id: String) -> Nil

pub fn main() -> Nil {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

pub fn base_url(host: String, port: String) -> String {
  "http://" <> host <> ":" <> port
}

pub fn socket_url(host: String, port: String) -> String {
  "ws://" <> host <> ":" <> port <> "/socket/websocket?vsn=2.0.0"
}

pub fn creation_error(detail: String) -> String {
  "Creation failed. The service might have created a document whose ID this browser did not receive: "
  <> detail
}

fn init(_argument: Nil) -> #(Model, Effect(Msg)) {
  let host = query_parameter("host", default_host)
  let port = query_parameter("port", default_port)
  let config =
    Config(
      base_url: base_url(host, port),
      socket_url: socket_url(host, port),
      tenant: query_parameter("tenant", default_tenant),
      secret: query_parameter("secret", default_secret),
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
      checklist: checklist.empty(),
      errors: [],
    )
  case document_id {
    "" -> #(
      model,
      tree.create_dev(
        config.base_url,
        config.tenant,
        config.secret,
        document_schema.stored(),
        Some(document_schema.initial()),
        Created,
      ),
    )
    id -> #(model, connect(config, id))
  }
}

fn connect(config: Config, document_id: String) -> Effect(Msg) {
  watershed_lustre.connect_dev(
    url: config.socket_url,
    tenant: config.tenant,
    secret: config.secret,
    document: document_id,
    user_id: "checklist-" <> id.uuid_v4(),
    got_document: GotDocument,
    connected: Connected,
  )
}

fn update(model: Model, message: Msg) -> #(Model, Effect(Msg)) {
  case message {
    Created(Ok(document_id)) -> {
      replace_document(document_id)
      let model = Model(..model, phase: Connecting, document_id: document_id)
      #(model, connect(model.config, document_id))
    }
    Created(Error(detail)) -> fail(model, creation_error(detail))
    GotDocument(document) -> #(
      Model(..model, document: Some(document)),
      effect.none(),
    )
    Connected(Error(detail)) -> fail(model, detail)
    Connected(Ok(Nil)) ->
      case model.document {
        Some(document) -> #(
          model,
          tree.open(document, document_schema.view(), Opened),
        )
        None ->
          fail(model, "connection completed before the document handle arrived")
      }
    Opened(Error(detail)) -> fail(model, detail)
    Opened(Ok(shared_tree)) -> #(
      Model(..model, tree: Some(shared_tree)),
      effect.batch([
        tree.subscribe(shared_tree, Subscribed, TreeChanged),
        tree.read_root(shared_tree, Read),
      ]),
    )
    Subscribed(subscription) -> #(
      Model(..model, subscription: Some(subscription)),
      effect.none(),
    )
    TreeChanged(_) ->
      case model.tree {
        Some(shared_tree) -> #(model, tree.read_root(shared_tree, Read))
        None -> #(model, effect.none())
      }
    Read(Error(detail)) -> fail(model, detail)
    Read(Ok(None)) -> fail(model, "The SharedTree root is absent")
    Read(Ok(Some(value))) ->
      case checklist.decode(value) {
        Ok(decoded) -> #(
          Model(..model, phase: Ready, checklist: decoded),
          effect.none(),
        )
        Error(detail) -> fail(model, "Invalid checklist snapshot: " <> detail)
      }
  }
}

fn fail(model: Model, detail: String) -> #(Model, Effect(Msg)) {
  #(
    Model(..model, phase: Failed(detail), errors: [detail, ..model.errors]),
    effect.none(),
  )
}

fn view(model: Model) -> Element(Msg) {
  html.main([], [
    html.h1([], [html.text("watershed · SharedTree checklist")]),
    html.p(
      [
        attribute.attribute("data-runtime-status", phase_name(model.phase)),
      ],
      [html.text(phase_label(model.phase))],
    ),
    html.p(
      [
        attribute.attribute("data-document-id", model.document_id),
      ],
      [html.text("document: " <> model.document_id)],
    ),
    html.p([attribute.attribute("data-development-auth", "true")], [
      html.text(
        "Local development only: this page mints tokens with a tenant secret.",
      ),
    ]),
    html.div(
      [],
      list.map(list.reverse(model.errors), fn(error) {
        html.p([attribute.attribute("data-error", "true")], [html.text(error)])
      }),
    ),
  ])
}

fn phase_name(phase: Phase) -> String {
  case phase {
    Creating -> "creating"
    Connecting -> "connecting"
    Ready -> "ready"
    Failed(_) -> "failed"
  }
}

fn phase_label(phase: Phase) -> String {
  case phase {
    Creating -> "creating document"
    Connecting -> "connecting"
    Ready -> "ready"
    Failed(detail) -> "failed: " <> detail
  }
}
