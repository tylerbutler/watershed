import gleam/list
import gleam/string
import gleeunit/should
import watershed_site/redirect
import watershed_site/route

pub fn migration_inventory_accounts_for_every_production_route_test() {
  let expected = [
    "/",
    "/component-model",
    "/component-model/components",
    "/component-model/ports",
    "/component-model/workspaces",
    "/counter-bug",
    "/directory",
    "/examples",
    "/foundations",
    "/foundations/components",
    "/foundations/lifecycle",
    "/foundations/ports",
    "/foundations/schema",
    "/foundations/topology",
    "/foundations/workspaces",
    "/guide",
    "/guide/connect",
    "/guide/notes",
    "/guide/presence",
    "/guide/race",
    "/guide/testing",
    "/guide/votes",
    "/json-ot",
    "/models",
    "/mv-register",
    "/patterns",
    "/rich-text",
    "/runtime",
    "/runtime/optimistic",
    "/runtime/p2p",
    "/runtime/presence",
    "/runtime/reconnect",
    "/runtime/redelivery",
    "/sequence",
    "/sharedtree",
    "/structures",
    "/structures/coordination",
    "/structures/counters",
    "/structures/maps",
    "/structures/registers",
    "/structures/sequences",
    "/structures/sets",
    "/structures/transforms",
    "/sudoku",
    "/text",
  ]
  let actual =
    list.append(
      route.all() |> list.map(fn(item) { item.path }),
      redirect.all() |> list.map(fn(item) { item.from }),
    )
  let pending = ["/"]
  list.sort(list.append(actual, pending), by: string_order)
  |> should.equal(list.sort(expected, by: string_order))
  pending |> list.length |> should.equal(1)
}

fn string_order(left: String, right: String) {
  string.compare(left, right)
}

pub fn legacy_foundation_routes_remain_permanent_redirects_test() {
  redirect.all()
  |> should.equal([
    redirect.Redirect(
      "/foundations/components",
      "/component-model/components",
      301,
    ),
    redirect.Redirect("/foundations/ports", "/component-model/ports", 301),
    redirect.Redirect(
      "/foundations/workspaces",
      "/component-model/workspaces",
      301,
    ),
  ])
}
