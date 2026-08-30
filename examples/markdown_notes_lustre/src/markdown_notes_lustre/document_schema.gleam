//// Root layout for the peer-to-peer markdown notes document.
////
//// The document root itself is a register-mode OR-map:
////
//// - note names map directly to `TextChannel` addresses.
//// - `"\ttags"` stores the shared OR-set channel address.
//// - `"\torder"` stores the shared sequence channel address.
////
//// Note names reject tabs, so the tab-prefixed reserved keys cannot collide
//// with user content.

import gleam/string

import watershed/or_map_kernel
import watershed/p2p
import watershed/schema.{
  type OrMapChannel, type OrSetChannel, type SequenceChannel, type TextChannel,
}

const tags_address_key = "\ttags"

const order_address_key = "\torder"

pub fn root() -> p2p.CrdtKind(OrMapChannel) {
  p2p.or_map_root(or_map_kernel.RegisterMode)
}

pub fn tags_key() -> String {
  tags_address_key
}

pub fn order_key() -> String {
  order_address_key
}

pub fn tags_kind() -> p2p.CrdtKind(OrSetChannel) {
  p2p.or_set_root()
}

pub fn order_kind() -> p2p.CrdtKind(SequenceChannel) {
  p2p.sequence_root()
}

pub fn text_kind() -> p2p.CrdtKind(TextChannel) {
  p2p.text_root()
}

pub fn is_reserved(name: String) -> Bool {
  string.starts_with(name, "\t")
}
