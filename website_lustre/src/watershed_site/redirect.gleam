import gleam/int
import gleam/list
import gleam/string

pub type Redirect {
  Redirect(from: String, to: String, status: Int)
}

pub fn all() -> List(Redirect) {
  [
    Redirect("/foundations/components", "/component-model/components", 301),
    Redirect("/foundations/ports", "/component-model/ports", 301),
    Redirect("/foundations/workspaces", "/component-model/workspaces", 301),
  ]
}

pub fn render(redirects: List(Redirect)) -> String {
  redirects
  |> list.map(fn(redirect) {
    redirect.from <> " " <> redirect.to <> " " <> int.to_string(redirect.status)
  })
  |> string.join("\n")
  |> fn(content) { content <> "\n" }
}
