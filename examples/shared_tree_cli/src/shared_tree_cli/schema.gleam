import watershed/tree/schema
import watershed/tree/types

const definition = "{\"version\":2,\"nodes\":{
  \"com.fluidframework.leaf.string\":{\"kind\":{\"leaf\":1}},
  \"shared_tree_cli.Note\":{\"kind\":{\"object\":{
    \"title\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.string\"]},
    \"note\":{\"kind\":\"Optional\",\"types\":[\"com.fluidframework.leaf.string\"]}
  }}}
},\"root\":{\"kind\":\"Value\",\"types\":[\"shared_tree_cli.Note\"]}}"

pub fn stored() -> schema.StoredSchema {
  let assert Ok(stored) = schema.stored_from_string(definition)
  stored
}

pub fn view() -> schema.ViewSchema {
  let assert Ok(view) = schema.view_from_string(definition)
  view
}

pub fn initial() -> types.TreeValue {
  types.ObjectValue("shared_tree_cli.Note", [
    #("title", types.StringValue("Created without an SDK seed")),
  ])
}
