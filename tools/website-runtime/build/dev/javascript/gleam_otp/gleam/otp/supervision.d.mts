import type * as _ from "../../gleam.d.mts";
import type * as $actor from "../../gleam/otp/actor.d.mts";

export class Permanent extends _.CustomType {}
export function Restart$Permanent(): Restart$;
export function Restart$isPermanent(value: any): value is Restart$;

export class Transient extends _.CustomType {}
export function Restart$Transient(): Restart$;
export function Restart$isTransient(value: any): value is Restart$;

export class Temporary extends _.CustomType {}
export function Restart$Temporary(): Restart$;
export function Restart$isTemporary(value: any): value is Restart$;

export type Restart$ = Permanent | Transient | Temporary;

export class Worker extends _.CustomType {
  /** @deprecated */
  constructor(shutdown_ms: number);
  /** @deprecated */
  shutdown_ms: number;
}
export function ChildType$Worker(shutdown_ms: number): ChildType$;
export function ChildType$isWorker(value: any): value is ChildType$;
export function ChildType$Worker$0(value: ChildType$): number;
export function ChildType$Worker$shutdown_ms(value: ChildType$): number;

export class Supervisor extends _.CustomType {}
export function ChildType$Supervisor(): ChildType$;
export function ChildType$isSupervisor(value: any): value is ChildType$;

export type ChildType$ = Worker | Supervisor;

export class ChildSpecification<EPZ> extends _.CustomType {
  /** @deprecated */
  constructor(
    start: () => _.Result<$actor.Started$<EPZ>, $actor.StartError$>,
    restart: Restart$,
    significant: boolean,
    child_type: ChildType$
  );
  /** @deprecated */
  start: () => _.Result<$actor.Started$<EPZ>, $actor.StartError$>;
  /** @deprecated */
  restart: Restart$;
  /** @deprecated */
  significant: boolean;
  /** @deprecated */
  child_type: ChildType$;
}
export function ChildSpecification$ChildSpecification<EPZ>(
  start: () => _.Result<$actor.Started$<EPZ>, $actor.StartError$>,
  restart: Restart$,
  significant: boolean,
  child_type: ChildType$,
): ChildSpecification$<EPZ>;
export function ChildSpecification$isChildSpecification<EPZ>(
  value: any,
): value is ChildSpecification$<unknown>;
export function ChildSpecification$ChildSpecification$0<EPZ>(value: ChildSpecification$<
    EPZ
  >): () => _.Result<$actor.Started$<EPZ>, $actor.StartError$>;
export function ChildSpecification$ChildSpecification$start<EPZ>(value: ChildSpecification$<
    EPZ
  >): () => _.Result<$actor.Started$<EPZ>, $actor.StartError$>;
export function ChildSpecification$ChildSpecification$1<EPZ>(value: ChildSpecification$<
    EPZ
  >): Restart$;
export function ChildSpecification$ChildSpecification$restart<EPZ>(value: ChildSpecification$<
    EPZ
  >): Restart$;
export function ChildSpecification$ChildSpecification$2<EPZ>(value: ChildSpecification$<
    EPZ
  >): boolean;
export function ChildSpecification$ChildSpecification$significant<EPZ>(value: ChildSpecification$<
    EPZ
  >): boolean;
export function ChildSpecification$ChildSpecification$3<EPZ>(value: ChildSpecification$<
    EPZ
  >): ChildType$;
export function ChildSpecification$ChildSpecification$child_type<EPZ>(value: ChildSpecification$<
    EPZ
  >): ChildType$;

export type ChildSpecification$<EPZ> = ChildSpecification<EPZ>;

export function worker<EQA>(
  start: () => _.Result<$actor.Started$<EQA>, $actor.StartError$>
): ChildSpecification$<EQA>;

export function supervisor<EQF>(
  start: () => _.Result<$actor.Started$<EQF>, $actor.StartError$>
): ChildSpecification$<EQF>;

export function significant<EQK>(
  child: ChildSpecification$<EQK>,
  significant: boolean
): ChildSpecification$<EQK>;

export function timeout<EQN>(child: ChildSpecification$<EQN>, ms: number): ChildSpecification$<
  EQN
>;

export function restart<EQQ>(child: ChildSpecification$<EQQ>, restart: Restart$): ChildSpecification$<
  EQQ
>;

export function map_data<EQT, EQV>(
  child: ChildSpecification$<EQT>,
  transform: (x0: EQT) => EQV
): ChildSpecification$<EQV>;
