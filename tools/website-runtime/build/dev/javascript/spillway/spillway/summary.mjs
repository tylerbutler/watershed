/// <reference types="./summary.d.mts" />
import * as $dict from "../../gleam_stdlib/gleam/dict.mjs";
import * as $option from "../../gleam_stdlib/gleam/option.mjs";
import { Ok, Error, CustomType as $CustomType } from "../gleam.mjs";

/**
 * Tree node containing other summary objects
 */
export class Tree extends $CustomType {}
export const SummaryType$Tree$const = new Tree();
export const SummaryType$Tree = () => SummaryType$Tree$const;
export const SummaryType$isTree = (value) => value instanceof Tree;

/**
 * Blob containing raw data
 */
export class Blob extends $CustomType {}
export const SummaryType$Blob$const = new Blob();
export const SummaryType$Blob = () => SummaryType$Blob$const;
export const SummaryType$isBlob = (value) => value instanceof Blob;

/**
 * Attachment reference to externally uploaded blob
 */
export class Attachment extends $CustomType {}
export const SummaryType$Attachment$const = new Attachment();
export const SummaryType$Attachment = () => SummaryType$Attachment$const;
export const SummaryType$isAttachment = (value) => value instanceof Attachment;

export class SummaryTree extends $CustomType {
  constructor(tree) {
    super();
    this.tree = tree;
  }
}
export const SummaryTree$SummaryTree = (tree) => new SummaryTree(tree);
export const SummaryTree$isSummaryTree = (value) =>
  value instanceof SummaryTree;
export const SummaryTree$SummaryTree$tree = (value) => value.tree;
export const SummaryTree$SummaryTree$0 = (value) => value.tree;

/**
 * A blob of data (string content)
 */
export class SummaryBlob extends $CustomType {
  constructor(content) {
    super();
    this.content = content;
  }
}
export const SummaryObject$SummaryBlob = (content) => new SummaryBlob(content);
export const SummaryObject$isSummaryBlob = (value) =>
  value instanceof SummaryBlob;
export const SummaryObject$SummaryBlob$content = (value) => value.content;
export const SummaryObject$SummaryBlob$0 = (value) => value.content;

/**
 * A handle referencing a previous summary's content
 */
export class SummaryHandle extends $CustomType {
  constructor(handle, handle_type) {
    super();
    this.handle = handle;
    this.handle_type = handle_type;
  }
}
export const SummaryObject$SummaryHandle = (handle, handle_type) =>
  new SummaryHandle(handle, handle_type);
export const SummaryObject$isSummaryHandle = (value) =>
  value instanceof SummaryHandle;
export const SummaryObject$SummaryHandle$handle = (value) => value.handle;
export const SummaryObject$SummaryHandle$0 = (value) => value.handle;
export const SummaryObject$SummaryHandle$handle_type = (value) =>
  value.handle_type;
export const SummaryObject$SummaryHandle$1 = (value) => value.handle_type;

/**
 * An attachment reference to an externally uploaded blob
 */
export class SummaryAttachment extends $CustomType {
  constructor(id) {
    super();
    this.id = id;
  }
}
export const SummaryObject$SummaryAttachment = (id) =>
  new SummaryAttachment(id);
export const SummaryObject$isSummaryAttachment = (value) =>
  value instanceof SummaryAttachment;
export const SummaryObject$SummaryAttachment$id = (value) => value.id;
export const SummaryObject$SummaryAttachment$0 = (value) => value.id;

/**
 * A nested tree node
 */
export class SummaryTreeNode extends $CustomType {
  constructor(tree) {
    super();
    this.tree = tree;
  }
}
export const SummaryObject$SummaryTreeNode = (tree) =>
  new SummaryTreeNode(tree);
export const SummaryObject$isSummaryTreeNode = (value) =>
  value instanceof SummaryTreeNode;
export const SummaryObject$SummaryTreeNode$tree = (value) => value.tree;
export const SummaryObject$SummaryTreeNode$0 = (value) => value.tree;

export class SummaryOp extends $CustomType {
  constructor(parent_summary_handle, summary_tree, sequence_number) {
    super();
    this.parent_summary_handle = parent_summary_handle;
    this.summary_tree = summary_tree;
    this.sequence_number = sequence_number;
  }
}
export const SummaryOp$SummaryOp = (parent_summary_handle, summary_tree, sequence_number) =>
  new SummaryOp(parent_summary_handle, summary_tree, sequence_number);
export const SummaryOp$isSummaryOp = (value) => value instanceof SummaryOp;
export const SummaryOp$SummaryOp$parent_summary_handle = (value) =>
  value.parent_summary_handle;
export const SummaryOp$SummaryOp$0 = (value) => value.parent_summary_handle;
export const SummaryOp$SummaryOp$summary_tree = (value) => value.summary_tree;
export const SummaryOp$SummaryOp$1 = (value) => value.summary_tree;
export const SummaryOp$SummaryOp$sequence_number = (value) =>
  value.sequence_number;
export const SummaryOp$SummaryOp$2 = (value) => value.sequence_number;

export class SummarizeContents extends $CustomType {
  constructor(handle, message, parents, head, includes_protocol_tree) {
    super();
    this.handle = handle;
    this.message = message;
    this.parents = parents;
    this.head = head;
    this.includes_protocol_tree = includes_protocol_tree;
  }
}
export const SummarizeContents$SummarizeContents = (handle, message, parents, head, includes_protocol_tree) =>
  new SummarizeContents(handle, message, parents, head, includes_protocol_tree);
export const SummarizeContents$isSummarizeContents = (value) =>
  value instanceof SummarizeContents;
export const SummarizeContents$SummarizeContents$handle = (value) =>
  value.handle;
export const SummarizeContents$SummarizeContents$0 = (value) => value.handle;
export const SummarizeContents$SummarizeContents$message = (value) =>
  value.message;
export const SummarizeContents$SummarizeContents$1 = (value) => value.message;
export const SummarizeContents$SummarizeContents$parents = (value) =>
  value.parents;
export const SummarizeContents$SummarizeContents$2 = (value) => value.parents;
export const SummarizeContents$SummarizeContents$head = (value) => value.head;
export const SummarizeContents$SummarizeContents$3 = (value) => value.head;
export const SummarizeContents$SummarizeContents$includes_protocol_tree = (value) =>
  value.includes_protocol_tree;
export const SummarizeContents$SummarizeContents$4 = (value) =>
  value.includes_protocol_tree;

export class SummaryAck extends $CustomType {
  constructor(handle, summary_sequence_number) {
    super();
    this.handle = handle;
    this.summary_sequence_number = summary_sequence_number;
  }
}
export const SummaryAck$SummaryAck = (handle, summary_sequence_number) =>
  new SummaryAck(handle, summary_sequence_number);
export const SummaryAck$isSummaryAck = (value) => value instanceof SummaryAck;
export const SummaryAck$SummaryAck$handle = (value) => value.handle;
export const SummaryAck$SummaryAck$0 = (value) => value.handle;
export const SummaryAck$SummaryAck$summary_sequence_number = (value) =>
  value.summary_sequence_number;
export const SummaryAck$SummaryAck$1 = (value) => value.summary_sequence_number;

export class SummaryNack extends $CustomType {
  constructor(summary_sequence_number, code, message, retry_after) {
    super();
    this.summary_sequence_number = summary_sequence_number;
    this.code = code;
    this.message = message;
    this.retry_after = retry_after;
  }
}
export const SummaryNack$SummaryNack = (summary_sequence_number, code, message, retry_after) =>
  new SummaryNack(summary_sequence_number, code, message, retry_after);
export const SummaryNack$isSummaryNack = (value) =>
  value instanceof SummaryNack;
export const SummaryNack$SummaryNack$summary_sequence_number = (value) =>
  value.summary_sequence_number;
export const SummaryNack$SummaryNack$0 = (value) =>
  value.summary_sequence_number;
export const SummaryNack$SummaryNack$code = (value) => value.code;
export const SummaryNack$SummaryNack$1 = (value) => value.code;
export const SummaryNack$SummaryNack$message = (value) => value.message;
export const SummaryNack$SummaryNack$2 = (value) => value.message;
export const SummaryNack$SummaryNack$retry_after = (value) => value.retry_after;
export const SummaryNack$SummaryNack$3 = (value) => value.retry_after;

export class PendingSummary extends $CustomType {
  constructor(client_id, contents, sequence_number, timestamp) {
    super();
    this.client_id = client_id;
    this.contents = contents;
    this.sequence_number = sequence_number;
    this.timestamp = timestamp;
  }
}
export const PendingSummary$PendingSummary = (client_id, contents, sequence_number, timestamp) =>
  new PendingSummary(client_id, contents, sequence_number, timestamp);
export const PendingSummary$isPendingSummary = (value) =>
  value instanceof PendingSummary;
export const PendingSummary$PendingSummary$client_id = (value) =>
  value.client_id;
export const PendingSummary$PendingSummary$0 = (value) => value.client_id;
export const PendingSummary$PendingSummary$contents = (value) => value.contents;
export const PendingSummary$PendingSummary$1 = (value) => value.contents;
export const PendingSummary$PendingSummary$sequence_number = (value) =>
  value.sequence_number;
export const PendingSummary$PendingSummary$2 = (value) => value.sequence_number;
export const PendingSummary$PendingSummary$timestamp = (value) =>
  value.timestamp;
export const PendingSummary$PendingSummary$3 = (value) => value.timestamp;

export class SummaryContext extends $CustomType {
  constructor(handle, sequence_number) {
    super();
    this.handle = handle;
    this.sequence_number = sequence_number;
  }
}
export const SummaryContext$SummaryContext = (handle, sequence_number) =>
  new SummaryContext(handle, sequence_number);
export const SummaryContext$isSummaryContext = (value) =>
  value instanceof SummaryContext;
export const SummaryContext$SummaryContext$handle = (value) => value.handle;
export const SummaryContext$SummaryContext$0 = (value) => value.handle;
export const SummaryContext$SummaryContext$sequence_number = (value) =>
  value.sequence_number;
export const SummaryContext$SummaryContext$1 = (value) => value.sequence_number;

/**
 * Convert SummaryType to string for wire format
 */
export function summary_type_to_string(st) {
  if (st instanceof Tree) {
    return "tree";
  } else if (st instanceof Blob) {
    return "blob";
  } else {
    return "attachment";
  }
}

/**
 * Parse SummaryType from wire format string
 */
export function summary_type_from_string(s) {
  if (s === "tree") {
    return new Ok(SummaryType$Tree$const);
  } else if (s === "blob") {
    return new Ok(SummaryType$Blob$const);
  } else if (s === "attachment") {
    return new Ok(SummaryType$Attachment$const);
  } else {
    return new Error(undefined);
  }
}

/**
 * Convert SummaryType to numeric type code (for ISummaryTree interface)
 */
export function summary_type_to_code(st) {
  if (st instanceof Tree) {
    return 1;
  } else if (st instanceof Blob) {
    return 2;
  } else {
    return 4;
  }
}

/**
 * Parse SummaryType from numeric type code
 */
export function summary_type_from_code(code) {
  if (code === 1) {
    return new Ok(SummaryType$Tree$const);
  } else if (code === 2) {
    return new Ok(SummaryType$Blob$const);
  } else if (code === 4) {
    return new Ok(SummaryType$Attachment$const);
  } else {
    return new Error(undefined);
  }
}

/**
 * Create an empty summary tree
 */
export function empty_summary_tree() {
  return new SummaryTree($dict.new$());
}

/**
 * Create a summary tree with entries
 */
export function new_summary_tree(entries) {
  return new SummaryTree($dict.from_list(entries));
}

/**
 * Add an entry to a summary tree
 */
export function add_to_summary_tree(summary, path, object) {
  return new SummaryTree($dict.insert(summary.tree, path, object));
}

/**
 * Get an entry from a summary tree
 */
export function get_from_summary_tree(summary, path) {
  return $dict.get(summary.tree, path);
}

/**
 * Create a SummaryAck
 */
export function create_summary_ack(handle, sequence_number) {
  return new SummaryAck(handle, sequence_number);
}

/**
 * Create a SummaryNack with error message
 */
export function create_summary_nack(sequence_number, code, message) {
  return new SummaryNack(
    sequence_number,
    code,
    message,
    $option.Option$None$const,
  );
}

/**
 * Create a SummaryNack with retry information
 */
export function create_summary_nack_with_retry(
  sequence_number,
  code,
  message,
  retry_after
) {
  return new SummaryNack(
    sequence_number,
    code,
    message,
    new $option.Some(retry_after),
  );
}

/**
 * Create a SummaryContext for document open response
 */
export function create_summary_context(handle, sequence_number) {
  return new SummaryContext(handle, sequence_number);
}
