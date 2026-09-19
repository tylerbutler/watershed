import watershed_site/route as site_route

pub fn route(path: String) -> site_route.Route {
  let assert Ok(route) = site_route.find(path)
  route
}
