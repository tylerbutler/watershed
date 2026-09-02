//// Typed root schema for the component-runtime project room.

import watershed/schema.{type ChildField}
import watershed/workspace

/// The project room document root.
pub type ProjectRoom

/// The one workspace child below the document root.
pub fn workspace() -> ChildField(ProjectRoom, workspace.WorkspaceSchema) {
  schema.child_field("workspace")
}
