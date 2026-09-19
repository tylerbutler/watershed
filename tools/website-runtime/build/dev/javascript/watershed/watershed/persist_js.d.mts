import type * as $json from "../../gleam_json/gleam/json.d.mts";
import type * as $option from "../../gleam_stdlib/gleam/option.d.mts";
import type * as _ from "../gleam.d.mts";
import type * as $crdt_js from "../watershed/crdt_js.d.mts";
import type * as $p2p from "../watershed/p2p.d.mts";
import type * as $transport_js from "../watershed/transport_js.d.mts";

export class StorageFailure extends _.CustomType {
  /** @deprecated */
  constructor(detail: string);
  /** @deprecated */
  detail: string;
}
export function PersistenceError$StorageFailure(
  detail: string,
): PersistenceError$;
export function PersistenceError$isStorageFailure(
  value: any,
): value is PersistenceError$;
export function PersistenceError$StorageFailure$0(value: PersistenceError$): string;
export function PersistenceError$StorageFailure$detail(
  value: PersistenceError$,
): string;

export class SnapshotFailure extends _.CustomType {
  /** @deprecated */
  constructor(error: $p2p.P2pError$);
  /** @deprecated */
  error: $p2p.P2pError$;
}
export function PersistenceError$SnapshotFailure(
  error: $p2p.P2pError$,
): PersistenceError$;
export function PersistenceError$isSnapshotFailure(
  value: any,
): value is PersistenceError$;
export function PersistenceError$SnapshotFailure$0(value: PersistenceError$): $p2p.P2pError$;
export function PersistenceError$SnapshotFailure$error(
  value: PersistenceError$,
): $p2p.P2pError$;

export class SnapshotDecodeFailure extends _.CustomType {
  /** @deprecated */
  constructor(detail: string);
  /** @deprecated */
  detail: string;
}
export function PersistenceError$SnapshotDecodeFailure(
  detail: string,
): PersistenceError$;
export function PersistenceError$isSnapshotDecodeFailure(
  value: any,
): value is PersistenceError$;
export function PersistenceError$SnapshotDecodeFailure$0(value: PersistenceError$): string;
export function PersistenceError$SnapshotDecodeFailure$detail(
  value: PersistenceError$,
): string;

export type PersistenceError$ = StorageFailure | SnapshotFailure | SnapshotDecodeFailure;

declare class Storage extends _.CustomType {
  /** @deprecated */
  constructor(
    get: (
      x0: string,
      x1: (x0: _.Result<$option.Option$<string>, string>) => undefined
    ) => undefined,
    update: (
      x0: string,
      x1: (
        x0: boolean,
        x1: string,
        x2: (x0: string) => undefined,
        x3: () => undefined
      ) => undefined,
      x2: () => undefined,
      x3: () => undefined,
      x4: (x0: string) => undefined
    ) => undefined
  );
  /** @deprecated */
  get: (
    x0: string,
    x1: (x0: _.Result<$option.Option$<string>, string>) => undefined
  ) => undefined;
  /** @deprecated */
  update: (
    x0: string,
    x1: (
      x0: boolean,
      x1: string,
      x2: (x0: string) => undefined,
      x3: () => undefined
    ) => undefined,
    x2: () => undefined,
    x3: () => undefined,
    x4: (x0: string) => undefined
  ) => undefined;
}

export type Storage$ = Storage;

declare class WriteDigest extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: string);
  /** @deprecated */
  0: string;
}

declare class WriteTransformFailed extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: PersistenceError$);
  /** @deprecated */
  0: PersistenceError$;
}

type WriteResolution$ = WriteDigest | WriteTransformFailed;

export function storage(
  get: (
    x0: string,
    x1: (x0: _.Result<$option.Option$<string>, string>) => undefined
  ) => undefined,
  update: (
    x0: string,
    x1: (
      x0: boolean,
      x1: string,
      x2: (x0: string) => undefined,
      x3: () => undefined
    ) => undefined,
    x2: () => undefined,
    x3: () => undefined,
    x4: (x0: string) => undefined
  ) => undefined
): Storage$;

export function indexed_db(): Storage$;

export function load<BYBE>(
  storage: Storage$,
  config: $crdt_js.Config$<BYBE>,
  done: (
    x0: _.Result<
      $option.Option$<$crdt_js.CrdtDocument$<BYBE>>,
      PersistenceError$
    >
  ) => undefined
): undefined;

export function save(
  storage: Storage$,
  document: $crdt_js.CrdtDocument$<any>,
  done: (x0: _.Result<string, PersistenceError$>) => undefined
): undefined;

export function replace(
  storage: Storage$,
  document: $crdt_js.CrdtDocument$<any>,
  done: (x0: _.Result<string, PersistenceError$>) => undefined
): undefined;

export function describe_error(error: PersistenceError$): string;
