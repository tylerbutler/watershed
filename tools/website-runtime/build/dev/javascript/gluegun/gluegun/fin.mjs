/// <reference types="./fin.d.mts" />
import { CustomType as $CustomType } from "../gleam.mjs";

export class Fin extends $CustomType {}
export const Fin$Fin$const = new Fin();
export const Fin$Fin = () => Fin$Fin$const;
export const Fin$isFin = (value) => value instanceof Fin;

export class NoFin extends $CustomType {}
export const Fin$NoFin$const = new NoFin();
export const Fin$NoFin = () => Fin$NoFin$const;
export const Fin$isNoFin = (value) => value instanceof NoFin;
