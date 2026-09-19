import type * as $request from "../../gleam_http/gleam/http/request.d.mts";
import type * as $response from "../../gleam_http/gleam/http/response.d.mts";
import type * as $promise from "../../gleam_javascript/gleam/javascript/promise.d.mts";
import type * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.d.mts";
import type * as $types from "../../spillway/spillway/types.d.mts";
import type * as _ from "../gleam.d.mts";
import type * as $channel from "../watershed/channel.d.mts";
import type * as $summary_blob from "../watershed/wire/summary_blob.d.mts";

export class SummaryVersion extends _.CustomType {
  /** @deprecated */
  constructor(id: string, tree_id: string, message: string, created_at: string);
  /** @deprecated */
  id: string;
  /** @deprecated */
  tree_id: string;
  /** @deprecated */
  message: string;
  /** @deprecated */
  created_at: string;
}
export function SummaryVersion$SummaryVersion(
  id: string,
  tree_id: string,
  message: string,
  created_at: string,
): SummaryVersion$;
export function SummaryVersion$isSummaryVersion(
  value: any,
): value is SummaryVersion$;
export function SummaryVersion$SummaryVersion$0(value: SummaryVersion$): string;
export function SummaryVersion$SummaryVersion$id(value: SummaryVersion$): string;
export function SummaryVersion$SummaryVersion$1(
  value: SummaryVersion$,
): string;
export function SummaryVersion$SummaryVersion$tree_id(value: SummaryVersion$): string;
export function SummaryVersion$SummaryVersion$2(
  value: SummaryVersion$,
): string;
export function SummaryVersion$SummaryVersion$message(value: SummaryVersion$): string;
export function SummaryVersion$SummaryVersion$3(
  value: SummaryVersion$,
): string;
export function SummaryVersion$SummaryVersion$created_at(value: SummaryVersion$): string;

export type SummaryVersion$ = SummaryVersion;

export class InvalidVersionCount extends _.CustomType {
  /** @deprecated */
  constructor(count: number);
  /** @deprecated */
  count: number;
}
export function StorageError$InvalidVersionCount(count: number): StorageError$;
export function StorageError$isInvalidVersionCount(
  value: any,
): value is StorageError$;
export function StorageError$InvalidVersionCount$0(value: StorageError$): number;
export function StorageError$InvalidVersionCount$count(
  value: StorageError$,
): number;

export class BadRequestUrl extends _.CustomType {
  /** @deprecated */
  constructor(url: string);
  /** @deprecated */
  url: string;
}
export function StorageError$BadRequestUrl(url: string): StorageError$;
export function StorageError$isBadRequestUrl(
  value: any,
): value is StorageError$;
export function StorageError$BadRequestUrl$0(value: StorageError$): string;
export function StorageError$BadRequestUrl$url(value: StorageError$): string;

export class RequestFailed extends _.CustomType {
  /** @deprecated */
  constructor(url: string, detail: string);
  /** @deprecated */
  url: string;
  /** @deprecated */
  detail: string;
}
export function StorageError$RequestFailed(
  url: string,
  detail: string,
): StorageError$;
export function StorageError$isRequestFailed(
  value: any,
): value is StorageError$;
export function StorageError$RequestFailed$0(value: StorageError$): string;
export function StorageError$RequestFailed$url(value: StorageError$): string;
export function StorageError$RequestFailed$1(value: StorageError$): string;
export function StorageError$RequestFailed$detail(value: StorageError$): string;

export class BodyReadFailed extends _.CustomType {
  /** @deprecated */
  constructor(url: string, detail: string);
  /** @deprecated */
  url: string;
  /** @deprecated */
  detail: string;
}
export function StorageError$BodyReadFailed(
  url: string,
  detail: string,
): StorageError$;
export function StorageError$isBodyReadFailed(
  value: any,
): value is StorageError$;
export function StorageError$BodyReadFailed$0(value: StorageError$): string;
export function StorageError$BodyReadFailed$url(value: StorageError$): string;
export function StorageError$BodyReadFailed$1(value: StorageError$): string;
export function StorageError$BodyReadFailed$detail(value: StorageError$): string;

export class UnexpectedStatus extends _.CustomType {
  /** @deprecated */
  constructor(url: string, status: number, body: string);
  /** @deprecated */
  url: string;
  /** @deprecated */
  status: number;
  /** @deprecated */
  body: string;
}
export function StorageError$UnexpectedStatus(
  url: string,
  status: number,
  body: string,
): StorageError$;
export function StorageError$isUnexpectedStatus(
  value: any,
): value is StorageError$;
export function StorageError$UnexpectedStatus$0(value: StorageError$): string;
export function StorageError$UnexpectedStatus$url(value: StorageError$): string;
export function StorageError$UnexpectedStatus$1(value: StorageError$): number;
export function StorageError$UnexpectedStatus$status(value: StorageError$): number;
export function StorageError$UnexpectedStatus$2(
  value: StorageError$,
): string;
export function StorageError$UnexpectedStatus$body(value: StorageError$): string;

export class ResponseDecodeFailed extends _.CustomType {
  /** @deprecated */
  constructor(url: string, detail: string);
  /** @deprecated */
  url: string;
  /** @deprecated */
  detail: string;
}
export function StorageError$ResponseDecodeFailed(
  url: string,
  detail: string,
): StorageError$;
export function StorageError$isResponseDecodeFailed(
  value: any,
): value is StorageError$;
export function StorageError$ResponseDecodeFailed$0(value: StorageError$): string;
export function StorageError$ResponseDecodeFailed$url(
  value: StorageError$,
): string;
export function StorageError$ResponseDecodeFailed$1(value: StorageError$): string;
export function StorageError$ResponseDecodeFailed$detail(
  value: StorageError$,
): string;

export class SummaryBlobMissing extends _.CustomType {
  /** @deprecated */
  constructor(handle: string, path: string);
  /** @deprecated */
  handle: string;
  /** @deprecated */
  path: string;
}
export function StorageError$SummaryBlobMissing(
  handle: string,
  path: string,
): StorageError$;
export function StorageError$isSummaryBlobMissing(
  value: any,
): value is StorageError$;
export function StorageError$SummaryBlobMissing$0(value: StorageError$): string;
export function StorageError$SummaryBlobMissing$handle(value: StorageError$): string;
export function StorageError$SummaryBlobMissing$1(
  value: StorageError$,
): string;
export function StorageError$SummaryBlobMissing$path(value: StorageError$): string;

export class SummaryBlobUnreadable extends _.CustomType {
  /** @deprecated */
  constructor(blob_sha: string, detail: string);
  /** @deprecated */
  blob_sha: string;
  /** @deprecated */
  detail: string;
}
export function StorageError$SummaryBlobUnreadable(
  blob_sha: string,
  detail: string,
): StorageError$;
export function StorageError$isSummaryBlobUnreadable(
  value: any,
): value is StorageError$;
export function StorageError$SummaryBlobUnreadable$0(value: StorageError$): string;
export function StorageError$SummaryBlobUnreadable$blob_sha(
  value: StorageError$,
): string;
export function StorageError$SummaryBlobUnreadable$1(value: StorageError$): string;
export function StorageError$SummaryBlobUnreadable$detail(
  value: StorageError$,
): string;

export class SummaryBlobInvalid extends _.CustomType {
  /** @deprecated */
  constructor(blob_sha: string, detail: string);
  /** @deprecated */
  blob_sha: string;
  /** @deprecated */
  detail: string;
}
export function StorageError$SummaryBlobInvalid(
  blob_sha: string,
  detail: string,
): StorageError$;
export function StorageError$isSummaryBlobInvalid(
  value: any,
): value is StorageError$;
export function StorageError$SummaryBlobInvalid$0(value: StorageError$): string;
export function StorageError$SummaryBlobInvalid$blob_sha(value: StorageError$): string;
export function StorageError$SummaryBlobInvalid$1(
  value: StorageError$,
): string;
export function StorageError$SummaryBlobInvalid$detail(value: StorageError$): string;

export type StorageError$ = InvalidVersionCount | BadRequestUrl | RequestFailed | BodyReadFailed | UnexpectedStatus | ResponseDecodeFailed | SummaryBlobMissing | SummaryBlobUnreadable | SummaryBlobInvalid;

declare class BlobContent extends _.CustomType {
  /** @deprecated */
  constructor(content: string);
  /** @deprecated */
  content: string;
}

type BlobContent$ = BlobContent;

export function error_to_string(error: StorageError$): string;

export function resolve_summary_tree_id(
  version_id: string,
  commit_result: _.Result<string, StorageError$>
): _.Result<string, StorageError$>;

export function commit_tree_decoder(): $decode.Decoder$<string>;

export function commit_url(base_url: string, tenant: string, commit_id: string): string;

export function fetch_summary(
  base_url: string,
  tenant: string,
  token: string,
  handle: string
): $promise.Promise$<_.Result<$summary_blob.SummaryBlob$, StorageError$>>;

export function upload_summary(
  base_url: string,
  tenant: string,
  token: string,
  sequence_number: number,
  members: _.List<number>,
  channels: _.List<[string, $channel.Snapshot$]>
): $promise.Promise$<_.Result<string, StorageError$>>;

export function fetch_deltas(
  base_url: string,
  tenant: string,
  token: string,
  document: string,
  from: number,
  to: number
): $promise.Promise$<
  _.Result<_.List<$types.SequencedDocumentMessage$>, StorageError$>
>;

export function versions_decoder(): $decode.Decoder$<_.List<SummaryVersion$>>;

export function versions_url(
  base_url: string,
  tenant: string,
  document: string,
  count: number
): string;

export function validate_version_count(count: number): _.Result<
  undefined,
  StorageError$
>;

export function fetch_versions(
  base_url: string,
  tenant: string,
  token: string,
  document: string,
  count: number
): $promise.Promise$<_.Result<_.List<SummaryVersion$>, StorageError$>>;
