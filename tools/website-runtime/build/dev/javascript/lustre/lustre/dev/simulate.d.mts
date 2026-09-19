import type * as $json from "../../../gleam_json/gleam/json.d.mts";
import type * as $dynamic from "../../../gleam_stdlib/gleam/dynamic.d.mts";
import type * as _ from "../../gleam.d.mts";
import type * as $query from "../../lustre/dev/query.d.mts";
import type * as $effect from "../../lustre/effect.d.mts";
import type * as $vnode from "../../lustre/vdom/vnode.d.mts";

declare class App<AADC, AADD, AADE> extends _.CustomType {
  /** @deprecated */
  constructor(
    init: (x0: AADC) => [AADD, $effect.Effect$<AADE>],
    update: (x0: AADD, x1: AADE) => [AADD, $effect.Effect$<AADE>],
    view: (x0: AADD) => $vnode.Element$<AADE>
  );
  /** @deprecated */
  init: (x0: AADC) => [AADD, $effect.Effect$<AADE>];
  /** @deprecated */
  update: (x0: AADD, x1: AADE) => [AADD, $effect.Effect$<AADE>];
  /** @deprecated */
  view: (x0: AADD) => $vnode.Element$<AADE>;
}

export type App$<AADC, AADD, AADE> = App<AADC, AADD, AADE>;

declare class Simulation<AADF, AADG> extends _.CustomType {
  /** @deprecated */
  constructor(
    update: (x0: AADF, x1: AADG) => [AADF, $effect.Effect$<AADG>],
    view: (x0: AADF) => $vnode.Element$<AADG>,
    history: _.List<Event$<AADG>>,
    model: AADF,
    html: $vnode.Element$<AADG>
  );
  /** @deprecated */
  update: (x0: AADF, x1: AADG) => [AADF, $effect.Effect$<AADG>];
  /** @deprecated */
  view: (x0: AADF) => $vnode.Element$<AADG>;
  /** @deprecated */
  history: _.List<Event$<AADG>>;
  /** @deprecated */
  model: AADF;
  /** @deprecated */
  html: $vnode.Element$<AADG>;
}

export type Simulation$<AADF, AADG> = Simulation<AADF, AADG>;

export class Dispatch<AADH> extends _.CustomType {
  /** @deprecated */
  constructor(message: AADH);
  /** @deprecated */
  message: AADH;
}
export function Event$Dispatch<AADH>(message: AADH): Event$<AADH>;
export function Event$isDispatch<AADH>(value: any): value is Event$<unknown>;
export function Event$Dispatch$0<AADH>(value: Event$<AADH>): AADH;
export function Event$Dispatch$message<AADH>(value: Event$<AADH>): AADH;

export class Event extends _.CustomType {
  /** @deprecated */
  constructor(target: $query.Query$, name: string, data: $json.Json$);
  /** @deprecated */
  target: $query.Query$;
  /** @deprecated */
  name: string;
  /** @deprecated */
  data: $json.Json$;
}
export function Event$Event<AADH>(
  target: $query.Query$,
  name: string,
  data: $json.Json$,
): Event$<AADH>;
export function Event$isEvent<AADH>(value: any): value is Event$<unknown>;
export function Event$Event$0<AADH>(value: Event$<AADH>): $query.Query$;
export function Event$Event$target<AADH>(value: Event$<AADH>): $query.Query$;
export function Event$Event$1<AADH>(value: Event$<AADH>): string;
export function Event$Event$name<AADH>(value: Event$<AADH>): string;
export function Event$Event$2<AADH>(value: Event$<AADH>): $json.Json$;
export function Event$Event$data<AADH>(value: Event$<AADH>): $json.Json$;

export class Problem extends _.CustomType {
  /** @deprecated */
  constructor(name: string, message: string);
  /** @deprecated */
  name: string;
  /** @deprecated */
  message: string;
}
export function Event$Problem<AADH>(
  name: string,
  message: string,
): Event$<AADH>;
export function Event$isProblem<AADH>(value: any): value is Event$<unknown>;
export function Event$Problem$0<AADH>(value: Event$<AADH>): string;
export function Event$Problem$name<AADH>(value: Event$<AADH>): string;
export function Event$Problem$1<AADH>(value: Event$<AADH>): string;
export function Event$Problem$message<AADH>(value: Event$<AADH>): string;

export type Event$<AADH> = Dispatch<AADH> | Event | Problem;

export function simple<AADI, AADJ, AADK>(
  init: (x0: AADI) => AADJ,
  update: (x0: AADJ, x1: AADK) => AADJ,
  view: (x0: AADJ) => $vnode.Element$<AADK>
): App$<AADI, AADJ, AADK>;

export function application<AADP, AADQ, AADR>(
  init: (x0: AADP) => [AADQ, $effect.Effect$<AADR>],
  update: (x0: AADQ, x1: AADR) => [AADQ, $effect.Effect$<AADR>],
  view: (x0: AADQ) => $vnode.Element$<AADR>
): App$<AADP, AADQ, AADR>;

export function start<AADY, AADZ, AAEA>(app: App$<AADY, AADZ, AAEA>, args: AADY): Simulation$<
  AADZ,
  AAEA
>;

export function message<AAEG, AAEH>(
  simulation: Simulation$<AAEG, AAEH>,
  message: AAEH
): Simulation$<AAEG, AAEH>;

export function problem<AAFM, AAFN>(
  simulation: Simulation$<AAFM, AAFN>,
  name: string,
  message: string
): Simulation$<AAFM, AAFN>;

export function event<AAEM, AAEN>(
  simulation: Simulation$<AAEM, AAEN>,
  query: $query.Query$,
  event: string,
  payload: _.List<[string, $json.Json$]>
): Simulation$<AAEM, AAEN>;

export function click<AAET, AAEU>(
  simulation: Simulation$<AAET, AAEU>,
  query: $query.Query$
): Simulation$<AAET, AAEU>;

export function input<AAEZ, AAFA>(
  simulation: Simulation$<AAEZ, AAFA>,
  query: $query.Query$,
  value: string
): Simulation$<AAEZ, AAFA>;

export function submit<AAFF, AAFG>(
  simulation: Simulation$<AAFF, AAFG>,
  query: $query.Query$,
  form_data: _.List<[string, string]>
): Simulation$<AAFF, AAFG>;

export function model<AAFS>(simulation: Simulation$<AAFS, any>): AAFS;

export function view<AAFX>(simulation: Simulation$<any, AAFX>): $vnode.Element$<
  AAFX
>;

export function history<AAGC>(simulation: Simulation$<any, AAGC>): _.List<
  Event$<AAGC>
>;
