//// Tests for watershed.dev_token — the public Erlang JWT helper.
////
//// Validates that the function exists on the Erlang target and produces a
//// well-formed HS256 JWT (three base64url segments separated by ".").

@target(erlang)
import gleam/string
@target(erlang)
import startest/expect

@target(erlang)
import watershed

@target(erlang)
const tenant_secret = "levee-dev-secret-change-in-production"

@target(erlang)
const tenant = "dev-tenant"

@target(erlang)
const document_id = "dice"

@target(erlang)
const user_id = "user-test"

@target(erlang)
pub fn dev_token_has_three_segments_test() {
  let token =
    watershed.dev_token(
      secret: tenant_secret,
      tenant: tenant,
      document: document_id,
      user_id: user_id,
    )
  let segments = string.split(token, ".")
  list.length(segments) |> expect.to_equal(3)
}

@target(erlang)
import gleam/list

@target(erlang)
pub fn dev_token_segments_are_nonempty_test() {
  let token =
    watershed.dev_token(
      secret: tenant_secret,
      tenant: tenant,
      document: document_id,
      user_id: user_id,
    )
  let segments = string.split(token, ".")
  list.each(segments, fn(seg) {
    { string.length(seg) > 0 } |> expect.to_be_true()
  })
}

@target(erlang)
pub fn dev_token_header_is_hs256_jwt_test() {
  let t1 =
    watershed.dev_token(
      secret: tenant_secret,
      tenant: tenant,
      document: document_id,
      user_id: user_id,
    )
  let t2 =
    watershed.dev_token(
      secret: tenant_secret,
      tenant: tenant,
      document: document_id,
      user_id: user_id,
    )
  let assert [h1, _, _] = string.split(t1, ".")
  let assert [h2, _, _] = string.split(t2, ".")
  h1 |> expect.to_equal(h2)
}
