//// Typed schema for the JSON workspace's root document.
////
//// `tree` is the workspace's one channel: a `SharedDirectory`. Every folder
//// and every document lives inside it. A folder is a subdirectory; a
//// document is a directory *value* whose payload is a `JsonOt` handle. See
//// `json_workspace_lustre`'s doc comment for why a channel handle stored as
//// an ordinary directory value, and not only as a root-map field, is the
//// point of this example.

import watershed/schema.{type ChannelField, type DirectoryChannel}

/// Phantom tag scoping the root map of a JSON workspace document.
pub type Workspace

/// The workspace tree: folders and JSON documents, all under one directory
/// channel.
pub fn tree() -> ChannelField(Workspace, DirectoryChannel) {
  schema.channel_field("tree")
}
