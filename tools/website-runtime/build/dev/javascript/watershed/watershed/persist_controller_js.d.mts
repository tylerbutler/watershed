import type * as $option from "../../gleam_stdlib/gleam/option.d.mts";
import type * as _ from "../gleam.d.mts";
import type * as $crdt_js from "../watershed/crdt_js.d.mts";
import type * as $persist_js from "../watershed/persist_js.d.mts";
import type * as $transport_js from "../watershed/transport_js.d.mts";

export class Saving extends _.CustomType {}
export function Status$Saving(): Status$;
export function Status$isSaving(value: any): value is Status$;

export class Saved extends _.CustomType {
  /** @deprecated */
  constructor(digest: string);
  /** @deprecated */
  digest: string;
}
export function Status$Saved(digest: string): Status$;
export function Status$isSaved(value: any): value is Status$;
export function Status$Saved$0(value: Status$): string;
export function Status$Saved$digest(value: Status$): string;

export class SaveFailed extends _.CustomType {
  /** @deprecated */
  constructor(error: $persist_js.PersistenceError$);
  /** @deprecated */
  error: $persist_js.PersistenceError$;
}
export function Status$SaveFailed(
  error: $persist_js.PersistenceError$,
): Status$;
export function Status$isSaveFailed(value: any): value is Status$;
export function Status$SaveFailed$0(value: Status$): $persist_js.PersistenceError$;
export function Status$SaveFailed$error(
  value: Status$,
): $persist_js.PersistenceError$;

export type Status$ = Saving | Saved | SaveFailed;

declare class Controller<BYIT> extends _.CustomType {
  /** @deprecated */
  constructor(cell: $transport_js.Cell$<State$<BYIT>>);
  /** @deprecated */
  cell: $transport_js.Cell$<State$<BYIT>>;
}

export type Controller$<BYIT> = Controller<BYIT>;

declare class State<BYIU> extends _.CustomType {
  /** @deprecated */
  constructor(
    save: (
      x0: $crdt_js.CrdtDocument$<BYIU>,
      x1: (x0: _.Result<string, $persist_js.PersistenceError$>) => undefined
    ) => undefined,
    document: $crdt_js.CrdtDocument$<BYIU>,
    scheduler: $transport_js.Scheduler$,
    on_status: (x0: Status$) => undefined,
    last_saved: string,
    dirty: boolean,
    saving: boolean,
    pagehide_pending: boolean,
    debounce: $option.Option$<() => undefined>,
    sweep: $option.Option$<() => undefined>,
    remove_pagehide: () => undefined,
    stopped: boolean
  );
  /** @deprecated */
  save: (
    x0: $crdt_js.CrdtDocument$<BYIU>,
    x1: (x0: _.Result<string, $persist_js.PersistenceError$>) => undefined
  ) => undefined;
  /** @deprecated */
  document: $crdt_js.CrdtDocument$<BYIU>;
  /** @deprecated */
  scheduler: $transport_js.Scheduler$;
  /** @deprecated */
  on_status: (x0: Status$) => undefined;
  /** @deprecated */
  last_saved: string;
  /** @deprecated */
  dirty: boolean;
  /** @deprecated */
  saving: boolean;
  /** @deprecated */
  pagehide_pending: boolean;
  /** @deprecated */
  debounce: $option.Option$<() => undefined>;
  /** @deprecated */
  sweep: $option.Option$<() => undefined>;
  /** @deprecated */
  remove_pagehide: () => undefined;
  /** @deprecated */
  stopped: boolean;
}

type State$<BYIU> = State<BYIU>;

export function start_with_save<BYJB>(
  document: $crdt_js.CrdtDocument$<BYJB>,
  on_status: (x0: Status$) => undefined,
  scheduler: $transport_js.Scheduler$,
  listen_pagehide: (x0: () => undefined) => () => undefined,
  save: (
    x0: $crdt_js.CrdtDocument$<BYJB>,
    x1: (x0: _.Result<string, $persist_js.PersistenceError$>) => undefined
  ) => undefined
): Controller$<BYJB>;

export function start_with<BYIY>(
  storage: $persist_js.Storage$,
  document: $crdt_js.CrdtDocument$<BYIY>,
  on_status: (x0: Status$) => undefined,
  scheduler: $transport_js.Scheduler$,
  listen_pagehide: (x0: () => undefined) => () => undefined
): Controller$<BYIY>;

export function start<BYIV>(
  storage: $persist_js.Storage$,
  document: $crdt_js.CrdtDocument$<BYIV>,
  on_status: (x0: Status$) => undefined
): Controller$<BYIV>;

export function changed(controller: Controller$<any>): undefined;

export function stop(controller: Controller$<any>): undefined;
