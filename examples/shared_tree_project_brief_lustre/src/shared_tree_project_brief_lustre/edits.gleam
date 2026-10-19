import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import shared_tree_project_brief_lustre/brief
import shared_tree_project_brief_lustre/schema
import watershed/tree
import watershed/tree/error

pub type RenderState {
  RenderState(
    value: brief.ProjectBrief,
    root: tree.Ref(brief.ProjectBrief),
    owner: tree.Ref(brief.Owner),
    schedule: tree.Ref(brief.Schedule),
    milestones: tree.Ref(List(brief.Milestone)),
    milestone_nodes: List(#(String, tree.Ref(brief.Milestone))),
    review: Option(tree.Ref(brief.Review)),
  )
}

pub fn capture(
  handle: tree.Tree(brief.ProjectBrief),
) -> Result(RenderState, error.Error) {
  use value <- result.try(tree.read_root(handle))
  use root <- result.try(tree.required_root(handle))
  use owner <- result.try(tree.child(root, schema.owner()))
  use schedule <- result.try(tree.child(root, schema.schedule()))
  use milestones <- result.try(tree.child(schedule, schema.milestones()))
  use milestone_nodes <- result.try(capture_milestones(milestones, 0, []))
  use review <- result.try(tree.optional_child(root, schema.review()))
  Ok(RenderState(
    value:,
    root:,
    owner:,
    schedule:,
    milestones:,
    milestone_nodes:,
    review:,
  ))
}

fn capture_milestones(
  array: tree.Ref(List(brief.Milestone)),
  index: Int,
  captured: List(#(String, tree.Ref(brief.Milestone))),
) -> Result(List(#(String, tree.Ref(brief.Milestone))), error.Error) {
  use node <- result.try(tree.array_node(array, index))
  case node {
    None -> Ok(list.reverse(captured))
    Some(node) -> {
      use value <- result.try(tree.read(node))
      capture_milestones(array, index + 1, [#(value.id, node), ..captured])
    }
  }
}

pub fn append(
  schedule: tree.Ref(brief.Schedule),
  id: String,
) -> Result(Nil, error.Error) {
  use array <- result.try(tree.child(schedule, schema.milestones()))
  use current <- result.try(tree.read(array))
  tree.array_insert(array, list.length(current), [
    brief.Milestone(id, "", False),
  ])
}

pub fn remove(
  array: tree.Ref(List(brief.Milestone)),
  item: tree.Ref(brief.Milestone),
) -> Result(Nil, error.Error) {
  tree.array_remove_node(array, item)
}
