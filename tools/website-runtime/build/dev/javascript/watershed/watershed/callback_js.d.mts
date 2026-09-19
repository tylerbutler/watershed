import type * as _ from "../gleam.d.mts";

export function capture<AXDZ>(work: () => AXDZ): _.Result<AXDZ, string>;

export function report(reason: string): undefined;
