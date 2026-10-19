import gleam/option.{type Option}
import gleam/result
import shared_tree_project_brief_lustre/brief
import watershed/tree/schema_builder as builder
import watershed/tree/types

fn factory() -> builder.Factory {
  builder.factory(scope: "shared_tree_project_brief")
}

pub fn brief_title() -> builder.Property(brief.ProjectBrief, String) {
  builder.required(
    key: "title",
    node: builder.string(),
    get: fn(value: brief.ProjectBrief) { value.title },
  )
}

pub fn owner() -> builder.Property(brief.ProjectBrief, brief.Owner) {
  builder.required(
    key: "owner",
    node: owner_node(),
    get: fn(value: brief.ProjectBrief) { value.owner },
  )
}

pub fn owner_name() -> builder.Property(brief.Owner, String) {
  builder.required(
    key: "name",
    node: builder.string(),
    get: fn(value: brief.Owner) { value.name },
  )
}

pub fn owner_email() -> builder.Property(brief.Owner, String) {
  builder.required(
    key: "email",
    node: builder.string(),
    get: fn(value: brief.Owner) { value.email },
  )
}

fn owner_node() -> builder.Node(brief.Owner) {
  builder.object2(factory(), "Owner", brief.Owner, owner_name(), owner_email())
}

pub fn schedule() -> builder.Property(brief.ProjectBrief, brief.Schedule) {
  builder.required(
    key: "schedule",
    node: schedule_node(),
    get: fn(value: brief.ProjectBrief) { value.schedule },
  )
}

pub fn schedule_start() -> builder.Property(brief.Schedule, String) {
  builder.required(
    key: "start",
    node: builder.string(),
    get: fn(value: brief.Schedule) { value.start },
  )
}

pub fn schedule_target() -> builder.Property(brief.Schedule, String) {
  builder.required(
    key: "target",
    node: builder.string(),
    get: fn(value: brief.Schedule) { value.target },
  )
}

pub fn milestones() -> builder.Property(brief.Schedule, List(brief.Milestone)) {
  builder.required(
    key: "milestones",
    node: builder.array(factory(), "Milestones", milestone_node()),
    get: fn(value: brief.Schedule) { value.milestones },
  )
}

fn schedule_node() -> builder.Node(brief.Schedule) {
  builder.object(
    factory: factory(),
    name: "Schedule",
    properties: [
      builder.property(schedule_start()),
      builder.property(schedule_target()),
      builder.property(milestones()),
    ],
    construct: fn(reader) {
      use start <- result.try(builder.read_property(
        reader:,
        property: schedule_start(),
      ))
      use target <- result.try(builder.read_property(
        reader:,
        property: schedule_target(),
      ))
      use milestones <- result.try(builder.read_property(
        reader:,
        property: milestones(),
      ))
      use _ <- result.try(
        brief.validate_unique_ids(milestones)
        |> result.map_error(fn(detail) {
          types.InvalidEdit(["schedule", "milestones"], detail)
        }),
      )
      Ok(brief.Schedule(start, target, milestones))
    },
  )
}

pub fn milestone_id() -> builder.Property(brief.Milestone, String) {
  builder.required(
    key: "id",
    node: builder.string(),
    get: fn(value: brief.Milestone) { value.id },
  )
}

pub fn milestone_title() -> builder.Property(brief.Milestone, String) {
  builder.required(
    key: "title",
    node: builder.string(),
    get: fn(value: brief.Milestone) { value.title },
  )
}

pub fn milestone_completed() -> builder.Property(brief.Milestone, Bool) {
  builder.required(
    key: "completed",
    node: builder.boolean(),
    get: fn(value: brief.Milestone) { value.completed },
  )
}

fn milestone_node() -> builder.Node(brief.Milestone) {
  builder.object3(
    factory(),
    "Milestone",
    brief.Milestone,
    milestone_id(),
    milestone_title(),
    milestone_completed(),
  )
}

pub fn review() -> builder.Property(brief.ProjectBrief, Option(brief.Review)) {
  builder.optional(
    key: "review",
    node: review_node(),
    get: fn(value: brief.ProjectBrief) { value.review },
  )
}

pub fn review_reviewer() -> builder.Property(brief.Review, String) {
  builder.required(
    key: "reviewer",
    node: builder.string(),
    get: fn(value: brief.Review) { value.reviewer },
  )
}

pub fn review_approved() -> builder.Property(brief.Review, Bool) {
  builder.required(
    key: "approved",
    node: builder.boolean(),
    get: fn(value: brief.Review) { value.approved },
  )
}

fn review_node() -> builder.Node(brief.Review) {
  builder.object2(
    factory(),
    "Review",
    brief.Review,
    review_reviewer(),
    review_approved(),
  )
}

pub fn configuration() -> builder.Root(brief.ProjectBrief) {
  builder.object4(
    factory(),
    "ProjectBrief",
    brief.ProjectBrief,
    brief_title(),
    owner(),
    schedule(),
    review(),
  )
  |> builder.root
}
