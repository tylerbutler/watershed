import type * as _ from "../gleam.d.mts";

export class Fin extends _.CustomType {}
export function Fin$Fin(): Fin$;
export function Fin$isFin(value: any): value is Fin$;

export class NoFin extends _.CustomType {}
export function Fin$NoFin(): Fin$;
export function Fin$isNoFin(value: any): value is Fin$;

export type Fin$ = Fin | NoFin;
