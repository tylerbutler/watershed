import type * as $process from "../../gleam_erlang/gleam/erlang/process.d.mts";
import type * as $json from "../../gleam_json/gleam/json.d.mts";
import type * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.d.mts";
import type * as _ from "../gleam.d.mts";
import type * as $effect from "../lustre/effect.d.mts";
import type * as $runtime from "../lustre/runtime/server/runtime.d.mts";
import type * as $transport from "../lustre/runtime/transport.d.mts";
import type * as $vattr from "../lustre/vdom/vattr.d.mts";
import type * as $vnode from "../lustre/vdom/vnode.d.mts";

export class WebSocket extends _.CustomType {}
export function TransportMethod$WebSocket(): TransportMethod$;
export function TransportMethod$isWebSocket(
  value: any,
): value is TransportMethod$;

export class ServerSentEvents extends _.CustomType {}
export function TransportMethod$ServerSentEvents(): TransportMethod$;
export function TransportMethod$isServerSentEvents(
  value: any,
): value is TransportMethod$;

export class Polling extends _.CustomType {}
export function TransportMethod$Polling(): TransportMethod$;
export function TransportMethod$isPolling(
  value: any,
): value is TransportMethod$;

export type TransportMethod$ = WebSocket | ServerSentEvents | Polling;

export type ClientMessage = $transport.ClientMessage$<any>;

export function element<ABVL>(
  attributes: _.List<$vattr.Attribute$<ABVL>>,
  children: _.List<$vnode.Element$<ABVL>>
): $vnode.Element$<ABVL>;

export function script(): $vnode.Element$<any>;

export function route(path: string): $vattr.Attribute$<any>;

export function method(value: TransportMethod$): $vattr.Attribute$<any>;

export function include<ABVX>(
  event: $vattr.Attribute$<ABVX>,
  properties: _.List<string>
): $vattr.Attribute$<ABVX>;

export function csrf_token(token: string): $vattr.Attribute$<any>;

export function register_subject<ABWD>(
  client: $process.Subject$<$transport.ClientMessage$<ABWD>>
): $runtime.Message$<ABWD>;

export function deregister_subject<ABWH>(
  client: $process.Subject$<$transport.ClientMessage$<ABWH>>
): $runtime.Message$<ABWH>;

export function register_callback<ABWL>(
  callback: (x0: $transport.ClientMessage$<ABWL>) => undefined
): $runtime.Message$<ABWL>;

export function deregister_callback<ABWO>(
  callback: (x0: $transport.ClientMessage$<ABWO>) => undefined
): $runtime.Message$<ABWO>;

export function emit(event: string, data: $json.Json$): $effect.Effect$<any>;

export function select<ABWT>(
  sel: (x0: (x0: ABWT) => undefined, x1: $process.Subject$<any>) => $process.Selector$<
    ABWT
  >
): $effect.Effect$<ABWT>;

export function runtime_message_decoder(): $decode.Decoder$<
  $runtime.Message$<any>
>;

export function client_message_to_json(message: $transport.ClientMessage$<any>): $json.Json$;
