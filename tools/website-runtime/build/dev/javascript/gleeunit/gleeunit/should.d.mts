import type * as $option from "../../gleam_stdlib/gleam/option.d.mts";
import type * as _ from "../gleam.d.mts";

export function equal<JDM>(a: JDM, b: JDM): undefined;

export function not_equal<JDN>(a: JDN, b: JDN): undefined;

export function be_ok<JDO>(a: _.Result<JDO, any>): JDO;

export function be_error<JDT>(a: _.Result<any, JDT>): JDT;

export function be_some<JDW>(a: $option.Option$<JDW>): JDW;

export function be_none(a: $option.Option$<any>): undefined;

export function be_true(actual: boolean): undefined;

export function be_false(actual: boolean): undefined;

export function fail(): undefined;
