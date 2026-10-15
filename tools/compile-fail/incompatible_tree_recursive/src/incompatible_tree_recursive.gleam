import watershed/tree/schema_builder as builder

pub fn invalid() -> builder.Node(String) {
  builder.lazy(builder.factory("com.example"), "Wrong", fn() {
    builder.number()
  })
}
