import gleam/option.{None, Some}
import startest/expect
import watershed/tree/branch
import watershed/tree/live
import watershed/tree/error as tree_error
import watershed/tree/live_types as protocol
import watershed/tree/schema_builder as builder
import watershed/tree/types

fn token() -> protocol.ViewToken {
  protocol.view_token(
    branch.origin("protocol", "document", "tree"),
    types.DocumentCheckout,
    0,
  )
}

fn backend(response: protocol.Response) -> live.Backend {
  live.Backend(
    request: fn(request) {
      case request {
        protocol.Bind(_) -> Ok(protocol.Bound(token()))
        _ -> Ok(response)
      }
    },
    subscribe: fn(_) {
      Error(tree_error.RuntimeFailure("No subscription in this protocol case"))
    },
  )
}

pub fn live_protocol_rejects_wrong_response_variants_test() {
  let assert Ok(compiled) = builder.compile(builder.root(builder.string()))
  let assert Ok(view) = live.bind(compiled, backend(protocol.Done))
  let expected = tree_error.RuntimeFailure("Unexpected typed tree response")
  live.read_root(view) |> expect.to_equal(Error(expected))
  live.required_root(view) |> expect.to_equal(Error(expected))
  let assert Ok(view) = live.bind(compiled, backend(protocol.Snapshot(None)))
  live.replace_root(view, "new") |> expect.to_equal(Error(expected))
  live.dispose(view) |> expect.to_equal(Error(expected))
  let bad =
    live.Backend(request: fn(_) { Ok(protocol.Done) }, subscribe: fn(_) {
      Error(tree_error.ClosedTree)
    })
  live.bind(compiled, bad) |> expect.to_equal(Error(expected))
}

pub fn live_protocol_checks_acquisition_evidence_test() {
  let node = builder.object0(builder.factory("protocol"), "Node")
  let assert Ok(compiled) = builder.compile(builder.root(node))
  let anchor = protocol.anchor_token(token(), 0)
  let response =
    protocol.Acquired(
      Some(protocol.NodeEvidence(
        anchor,
        "wrong",
        types.ObjectValue("protocol.Node", []),
      )),
    )
  let assert Ok(view) = live.bind(compiled, backend(response))
  live.required_root(view)
  |> expect.to_equal(
    Error(tree_error.RuntimeFailure("Node evidence has an incorrect identifier")),
  )
  let response =
    protocol.Acquired(
      Some(protocol.NodeEvidence(
        anchor,
        "com.fluidframework.leaf.string",
        types.StringValue("leaf"),
      )),
    )
  let assert Ok(view) = live.bind(compiled, backend(response))
  live.required_root(view)
  |> expect.to_equal(
    Error(tree_error.WrongKind("composite", "com.fluidframework.leaf.string")),
  )
  let foreign =
    protocol.anchor_token(
      protocol.view_token(
        branch.origin("other", "document", "tree"),
        types.DocumentCheckout,
        0,
      ),
      0,
    )
  let response =
    protocol.Acquired(
      Some(protocol.NodeEvidence(
        foreign,
        "protocol.Node",
        types.ObjectValue("protocol.Node", []),
      )),
    )
  let assert Ok(view) = live.bind(compiled, backend(response))
  live.required_root(view) |> expect.to_equal(Error(tree_error.ForeignOrigin))
}
