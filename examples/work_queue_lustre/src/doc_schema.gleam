//// Typed schema for the dispatch board document.
////
//// Three channels, each carrying a different consensus story:
////
//// - `queue` — the job queue. A `ConsensusOrderedCollection`: FIFO, one
////   acquirer per job, non-optimistic. The Queued column *is* this channel.
//// - `roles` — the dispatcher lock. A `TaskManager`: a FIFO of volunteers per
////   named role, head owns it, released automatically when its holder leaves.
//// - `completed` — the Done column. The consensus kernels deliberately drop
////   completed jobs, so history lives in an ordinary append-only sequence.

import watershed/schema.{
  type ChannelField, type OrderedCollectionChannel, type SequenceChannel,
  type TaskManagerChannel,
}

/// Phantom tag scoping every field below to the dispatch root map.
pub type Dispatch

pub fn queue() -> ChannelField(Dispatch, OrderedCollectionChannel) {
  schema.channel_field("queue")
}

pub fn roles() -> ChannelField(Dispatch, TaskManagerChannel) {
  schema.channel_field("roles")
}

pub fn completed() -> ChannelField(Dispatch, SequenceChannel) {
  schema.channel_field("completed")
}
