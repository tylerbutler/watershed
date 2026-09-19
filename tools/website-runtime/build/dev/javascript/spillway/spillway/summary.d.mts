import type * as $dict from "../../gleam_stdlib/gleam/dict.d.mts";
import type * as $option from "../../gleam_stdlib/gleam/option.d.mts";
import type * as _ from "../gleam.d.mts";

export class Tree extends _.CustomType {}
export function SummaryType$Tree(): SummaryType$;
export function SummaryType$isTree(value: any): value is SummaryType$;

export class Blob extends _.CustomType {}
export function SummaryType$Blob(): SummaryType$;
export function SummaryType$isBlob(value: any): value is SummaryType$;

export class Attachment extends _.CustomType {}
export function SummaryType$Attachment(): SummaryType$;
export function SummaryType$isAttachment(value: any): value is SummaryType$;

export type SummaryType$ = Tree | Blob | Attachment;

export class SummaryTree extends _.CustomType {
  /** @deprecated */
  constructor(tree: $dict.Dict$<string, SummaryObject$>);
  /** @deprecated */
  tree: $dict.Dict$<string, SummaryObject$>;
}
export function SummaryTree$SummaryTree(
  tree: $dict.Dict$<string, SummaryObject$>,
): SummaryTree$;
export function SummaryTree$isSummaryTree(value: any): value is SummaryTree$;
export function SummaryTree$SummaryTree$0(value: SummaryTree$): $dict.Dict$<
  string,
  SummaryObject$
>;
export function SummaryTree$SummaryTree$tree(value: SummaryTree$): $dict.Dict$<
  string,
  SummaryObject$
>;

export type SummaryTree$ = SummaryTree;

export class SummaryBlob extends _.CustomType {
  /** @deprecated */
  constructor(content: string);
  /** @deprecated */
  content: string;
}
export function SummaryObject$SummaryBlob(content: string): SummaryObject$;
export function SummaryObject$isSummaryBlob(
  value: any,
): value is SummaryObject$;
export function SummaryObject$SummaryBlob$0(value: SummaryObject$): string;
export function SummaryObject$SummaryBlob$content(value: SummaryObject$): string;

export class SummaryHandle extends _.CustomType {
  /** @deprecated */
  constructor(handle: string, handle_type: SummaryType$);
  /** @deprecated */
  handle: string;
  /** @deprecated */
  handle_type: SummaryType$;
}
export function SummaryObject$SummaryHandle(
  handle: string,
  handle_type: SummaryType$,
): SummaryObject$;
export function SummaryObject$isSummaryHandle(
  value: any,
): value is SummaryObject$;
export function SummaryObject$SummaryHandle$0(value: SummaryObject$): string;
export function SummaryObject$SummaryHandle$handle(value: SummaryObject$): string;
export function SummaryObject$SummaryHandle$1(
  value: SummaryObject$,
): SummaryType$;
export function SummaryObject$SummaryHandle$handle_type(value: SummaryObject$): SummaryType$;

export class SummaryAttachment extends _.CustomType {
  /** @deprecated */
  constructor(id: string);
  /** @deprecated */
  id: string;
}
export function SummaryObject$SummaryAttachment(id: string): SummaryObject$;
export function SummaryObject$isSummaryAttachment(
  value: any,
): value is SummaryObject$;
export function SummaryObject$SummaryAttachment$0(value: SummaryObject$): string;
export function SummaryObject$SummaryAttachment$id(
  value: SummaryObject$,
): string;

export class SummaryTreeNode extends _.CustomType {
  /** @deprecated */
  constructor(tree: $dict.Dict$<string, SummaryObject$>);
  /** @deprecated */
  tree: $dict.Dict$<string, SummaryObject$>;
}
export function SummaryObject$SummaryTreeNode(
  tree: $dict.Dict$<string, SummaryObject$>,
): SummaryObject$;
export function SummaryObject$isSummaryTreeNode(
  value: any,
): value is SummaryObject$;
export function SummaryObject$SummaryTreeNode$0(value: SummaryObject$): $dict.Dict$<
  string,
  SummaryObject$
>;
export function SummaryObject$SummaryTreeNode$tree(value: SummaryObject$): $dict.Dict$<
  string,
  SummaryObject$
>;

export type SummaryObject$ = SummaryBlob | SummaryHandle | SummaryAttachment | SummaryTreeNode;

export class SummaryOp extends _.CustomType {
  /** @deprecated */
  constructor(
    parent_summary_handle: string,
    summary_tree: SummaryTree$,
    sequence_number: number
  );
  /** @deprecated */
  parent_summary_handle: string;
  /** @deprecated */
  summary_tree: SummaryTree$;
  /** @deprecated */
  sequence_number: number;
}
export function SummaryOp$SummaryOp(
  parent_summary_handle: string,
  summary_tree: SummaryTree$,
  sequence_number: number,
): SummaryOp$;
export function SummaryOp$isSummaryOp(value: any): value is SummaryOp$;
export function SummaryOp$SummaryOp$0(value: SummaryOp$): string;
export function SummaryOp$SummaryOp$parent_summary_handle(value: SummaryOp$): string;
export function SummaryOp$SummaryOp$1(
  value: SummaryOp$,
): SummaryTree$;
export function SummaryOp$SummaryOp$summary_tree(value: SummaryOp$): SummaryTree$;
export function SummaryOp$SummaryOp$2(
  value: SummaryOp$,
): number;
export function SummaryOp$SummaryOp$sequence_number(value: SummaryOp$): number;

export type SummaryOp$ = SummaryOp;

export class SummarizeContents extends _.CustomType {
  /** @deprecated */
  constructor(
    handle: string,
    message: string,
    parents: _.List<string>,
    head: string,
    includes_protocol_tree: $option.Option$<boolean>
  );
  /** @deprecated */
  handle: string;
  /** @deprecated */
  message: string;
  /** @deprecated */
  parents: _.List<string>;
  /** @deprecated */
  head: string;
  /** @deprecated */
  includes_protocol_tree: $option.Option$<boolean>;
}
export function SummarizeContents$SummarizeContents(
  handle: string,
  message: string,
  parents: _.List<string>,
  head: string,
  includes_protocol_tree: $option.Option$<boolean>,
): SummarizeContents$;
export function SummarizeContents$isSummarizeContents(
  value: any,
): value is SummarizeContents$;
export function SummarizeContents$SummarizeContents$0(value: SummarizeContents$): string;
export function SummarizeContents$SummarizeContents$handle(
  value: SummarizeContents$,
): string;
export function SummarizeContents$SummarizeContents$1(value: SummarizeContents$): string;
export function SummarizeContents$SummarizeContents$message(
  value: SummarizeContents$,
): string;
export function SummarizeContents$SummarizeContents$2(value: SummarizeContents$): _.List<
  string
>;
export function SummarizeContents$SummarizeContents$parents(value: SummarizeContents$): _.List<
  string
>;
export function SummarizeContents$SummarizeContents$3(value: SummarizeContents$): string;
export function SummarizeContents$SummarizeContents$head(
  value: SummarizeContents$,
): string;
export function SummarizeContents$SummarizeContents$4(value: SummarizeContents$): $option.Option$<
  boolean
>;
export function SummarizeContents$SummarizeContents$includes_protocol_tree(value: SummarizeContents$): $option.Option$<
  boolean
>;

export type SummarizeContents$ = SummarizeContents;

export class SummaryAck extends _.CustomType {
  /** @deprecated */
  constructor(handle: string, summary_sequence_number: number);
  /** @deprecated */
  handle: string;
  /** @deprecated */
  summary_sequence_number: number;
}
export function SummaryAck$SummaryAck(
  handle: string,
  summary_sequence_number: number,
): SummaryAck$;
export function SummaryAck$isSummaryAck(value: any): value is SummaryAck$;
export function SummaryAck$SummaryAck$0(value: SummaryAck$): string;
export function SummaryAck$SummaryAck$handle(value: SummaryAck$): string;
export function SummaryAck$SummaryAck$1(value: SummaryAck$): number;
export function SummaryAck$SummaryAck$summary_sequence_number(value: SummaryAck$): number;

export type SummaryAck$ = SummaryAck;

export class SummaryNack extends _.CustomType {
  /** @deprecated */
  constructor(
    summary_sequence_number: number,
    code: $option.Option$<number>,
    message: $option.Option$<string>,
    retry_after: $option.Option$<number>
  );
  /** @deprecated */
  summary_sequence_number: number;
  /** @deprecated */
  code: $option.Option$<number>;
  /** @deprecated */
  message: $option.Option$<string>;
  /** @deprecated */
  retry_after: $option.Option$<number>;
}
export function SummaryNack$SummaryNack(
  summary_sequence_number: number,
  code: $option.Option$<number>,
  message: $option.Option$<string>,
  retry_after: $option.Option$<number>,
): SummaryNack$;
export function SummaryNack$isSummaryNack(value: any): value is SummaryNack$;
export function SummaryNack$SummaryNack$0(value: SummaryNack$): number;
export function SummaryNack$SummaryNack$summary_sequence_number(value: SummaryNack$): number;
export function SummaryNack$SummaryNack$1(
  value: SummaryNack$,
): $option.Option$<number>;
export function SummaryNack$SummaryNack$code(value: SummaryNack$): $option.Option$<
  number
>;
export function SummaryNack$SummaryNack$2(value: SummaryNack$): $option.Option$<
  string
>;
export function SummaryNack$SummaryNack$message(value: SummaryNack$): $option.Option$<
  string
>;
export function SummaryNack$SummaryNack$3(value: SummaryNack$): $option.Option$<
  number
>;
export function SummaryNack$SummaryNack$retry_after(value: SummaryNack$): $option.Option$<
  number
>;

export type SummaryNack$ = SummaryNack;

export class PendingSummary extends _.CustomType {
  /** @deprecated */
  constructor(
    client_id: string,
    contents: SummarizeContents$,
    sequence_number: number,
    timestamp: number
  );
  /** @deprecated */
  client_id: string;
  /** @deprecated */
  contents: SummarizeContents$;
  /** @deprecated */
  sequence_number: number;
  /** @deprecated */
  timestamp: number;
}
export function PendingSummary$PendingSummary(
  client_id: string,
  contents: SummarizeContents$,
  sequence_number: number,
  timestamp: number,
): PendingSummary$;
export function PendingSummary$isPendingSummary(
  value: any,
): value is PendingSummary$;
export function PendingSummary$PendingSummary$0(value: PendingSummary$): string;
export function PendingSummary$PendingSummary$client_id(value: PendingSummary$): string;
export function PendingSummary$PendingSummary$1(
  value: PendingSummary$,
): SummarizeContents$;
export function PendingSummary$PendingSummary$contents(value: PendingSummary$): SummarizeContents$;
export function PendingSummary$PendingSummary$2(
  value: PendingSummary$,
): number;
export function PendingSummary$PendingSummary$sequence_number(value: PendingSummary$): number;
export function PendingSummary$PendingSummary$3(
  value: PendingSummary$,
): number;
export function PendingSummary$PendingSummary$timestamp(value: PendingSummary$): number;

export type PendingSummary$ = PendingSummary;

export class SummaryContext extends _.CustomType {
  /** @deprecated */
  constructor(handle: string, sequence_number: number);
  /** @deprecated */
  handle: string;
  /** @deprecated */
  sequence_number: number;
}
export function SummaryContext$SummaryContext(
  handle: string,
  sequence_number: number,
): SummaryContext$;
export function SummaryContext$isSummaryContext(
  value: any,
): value is SummaryContext$;
export function SummaryContext$SummaryContext$0(value: SummaryContext$): string;
export function SummaryContext$SummaryContext$handle(value: SummaryContext$): string;
export function SummaryContext$SummaryContext$1(
  value: SummaryContext$,
): number;
export function SummaryContext$SummaryContext$sequence_number(value: SummaryContext$): number;

export type SummaryContext$ = SummaryContext;

export function summary_type_to_string(st: SummaryType$): string;

export function summary_type_from_string(s: string): _.Result<
  SummaryType$,
  undefined
>;

export function summary_type_to_code(st: SummaryType$): number;

export function summary_type_from_code(code: number): _.Result<
  SummaryType$,
  undefined
>;

export function empty_summary_tree(): SummaryTree$;

export function new_summary_tree(entries: _.List<[string, SummaryObject$]>): SummaryTree$;

export function add_to_summary_tree(
  summary: SummaryTree$,
  path: string,
  object: SummaryObject$
): SummaryTree$;

export function get_from_summary_tree(summary: SummaryTree$, path: string): _.Result<
  SummaryObject$,
  undefined
>;

export function create_summary_ack(handle: string, sequence_number: number): SummaryAck$;

export function create_summary_nack(
  sequence_number: number,
  code: $option.Option$<number>,
  message: $option.Option$<string>
): SummaryNack$;

export function create_summary_nack_with_retry(
  sequence_number: number,
  code: $option.Option$<number>,
  message: $option.Option$<string>,
  retry_after: number
): SummaryNack$;

export function create_summary_context(handle: string, sequence_number: number): SummaryContext$;
