import type * as $json from "../../gleam_json/gleam/json.d.mts";
import type * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.d.mts";
import type * as _ from "../gleam.d.mts";
import type * as $effect from "../lustre/effect.d.mts";
import type * as $vattr from "../lustre/vdom/vattr.d.mts";

export type Handler = $vattr.Handler$<any>;

export function emit(event: string, data: $json.Json$): $effect.Effect$<any>;

export function on<ABNC>(name: string, handler: $decode.Decoder$<ABNC>): $vattr.Attribute$<
  ABNC
>;

export function advanced<ABNF>(
  name: string,
  handler: $decode.Decoder$<$vattr.Handler$<ABNF>>
): $vattr.Attribute$<ABNF>;

export function handler<ABNJ>(
  message: ABNJ,
  prevent_default: boolean,
  stop_propagation: boolean
): $vattr.Handler$<ABNJ>;

export function prevent_default<ABNL>(event: $vattr.Attribute$<ABNL>): $vattr.Attribute$<
  ABNL
>;

export function stop_propagation<ABNO>(event: $vattr.Attribute$<ABNO>): $vattr.Attribute$<
  ABNO
>;

export function debounce<ABNR>(event: $vattr.Attribute$<ABNR>, delay: number): $vattr.Attribute$<
  ABNR
>;

export function throttle<ABNU>(event: $vattr.Attribute$<ABNU>, delay: number): $vattr.Attribute$<
  ABNU
>;

export function on_click<ABNX>(message: ABNX): $vattr.Attribute$<ABNX>;

export function on_mouse_down<ABNZ>(message: ABNZ): $vattr.Attribute$<ABNZ>;

export function on_mouse_up<ABOB>(message: ABOB): $vattr.Attribute$<ABOB>;

export function on_mouse_enter<ABOD>(message: ABOD): $vattr.Attribute$<ABOD>;

export function on_mouse_leave<ABOF>(message: ABOF): $vattr.Attribute$<ABOF>;

export function on_mouse_over<ABOH>(message: ABOH): $vattr.Attribute$<ABOH>;

export function on_mouse_out<ABOJ>(message: ABOJ): $vattr.Attribute$<ABOJ>;

export function on_keypress<ABOL>(message: (x0: string) => ABOL): $vattr.Attribute$<
  ABOL
>;

export function on_keydown<ABON>(message: (x0: string) => ABON): $vattr.Attribute$<
  ABON
>;

export function on_keyup<ABOP>(message: (x0: string) => ABOP): $vattr.Attribute$<
  ABOP
>;

export function on_input<ABOR>(message: (x0: string) => ABOR): $vattr.Attribute$<
  ABOR
>;

export function on_change<ABOT>(message: (x0: string) => ABOT): $vattr.Attribute$<
  ABOT
>;

export function on_check<ABOV>(message: (x0: boolean) => ABOV): $vattr.Attribute$<
  ABOV
>;

export function on_submit<ABOY>(message: (x0: _.List<[string, string]>) => ABOY): $vattr.Attribute$<
  ABOY
>;

export function on_focus<ABPC>(message: ABPC): $vattr.Attribute$<ABPC>;

export function on_blur<ABPE>(message: ABPE): $vattr.Attribute$<ABPE>;
