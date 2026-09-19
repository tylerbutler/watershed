import type * as $json from "../../../gleam_json/gleam/json.d.mts";
import type * as $dict from "../../../gleam_stdlib/gleam/dict.d.mts";
import type * as $dynamic from "../../../gleam_stdlib/gleam/dynamic.d.mts";
import type * as $decode from "../../../gleam_stdlib/gleam/dynamic/decode.d.mts";
import type * as _ from "../../gleam.d.mts";
import type * as $mutable_map from "../../lustre/internals/mutable_map.d.mts";
import type * as $patch from "../../lustre/vdom/patch.d.mts";
import type * as $vnode from "../../lustre/vdom/vnode.d.mts";

export class Mount<WMW> extends _.CustomType {
  /** @deprecated */
  constructor(
    kind: number,
    open_shadow_root: boolean,
    will_adopt_styles: boolean,
    observed_attributes: _.List<string>,
    observed_properties: _.List<string>,
    requested_contexts: _.List<string>,
    provided_contexts: $dict.Dict$<string, $json.Json$>,
    vdom: $vnode.Element$<WMW>,
    memos: $mutable_map.MutableMap$<
      () => $vnode.Element$<WMW>,
      $vnode.Element$<WMW>
    >
  );
  /** @deprecated */
  kind: number;
  /** @deprecated */
  open_shadow_root: boolean;
  /** @deprecated */
  will_adopt_styles: boolean;
  /** @deprecated */
  observed_attributes: _.List<string>;
  /** @deprecated */
  observed_properties: _.List<string>;
  /** @deprecated */
  requested_contexts: _.List<string>;
  /** @deprecated */
  provided_contexts: $dict.Dict$<string, $json.Json$>;
  /** @deprecated */
  vdom: $vnode.Element$<WMW>;
  /** @deprecated */
  memos: $mutable_map.MutableMap$<
    () => $vnode.Element$<WMW>,
    $vnode.Element$<WMW>
  >;
}
export function ClientMessage$Mount<WMW>(
  kind: number,
  open_shadow_root: boolean,
  will_adopt_styles: boolean,
  observed_attributes: _.List<string>,
  observed_properties: _.List<string>,
  requested_contexts: _.List<string>,
  provided_contexts: $dict.Dict$<string, $json.Json$>,
  vdom: $vnode.Element$<WMW>,
  memos: $mutable_map.MutableMap$<
    () => $vnode.Element$<WMW>,
    $vnode.Element$<WMW>
  >,
): ClientMessage$<WMW>;
export function ClientMessage$isMount<WMW>(
  value: any,
): value is ClientMessage$<unknown>;
export function ClientMessage$Mount$0<WMW>(value: ClientMessage$<WMW>): number;
export function ClientMessage$Mount$kind<WMW>(value: ClientMessage$<WMW>): number;
export function ClientMessage$Mount$1<WMW>(
  value: ClientMessage$<WMW>,
): boolean;
export function ClientMessage$Mount$open_shadow_root<WMW>(value: ClientMessage$<
    WMW
  >): boolean;
export function ClientMessage$Mount$2<WMW>(value: ClientMessage$<WMW>): boolean;
export function ClientMessage$Mount$will_adopt_styles<WMW>(value: ClientMessage$<
    WMW
  >): boolean;
export function ClientMessage$Mount$3<WMW>(value: ClientMessage$<WMW>): _.List<
  string
>;
export function ClientMessage$Mount$observed_attributes<WMW>(value: ClientMessage$<
    WMW
  >): _.List<string>;
export function ClientMessage$Mount$4<WMW>(value: ClientMessage$<WMW>): _.List<
  string
>;
export function ClientMessage$Mount$observed_properties<WMW>(value: ClientMessage$<
    WMW
  >): _.List<string>;
export function ClientMessage$Mount$5<WMW>(value: ClientMessage$<WMW>): _.List<
  string
>;
export function ClientMessage$Mount$requested_contexts<WMW>(value: ClientMessage$<
    WMW
  >): _.List<string>;
export function ClientMessage$Mount$6<WMW>(value: ClientMessage$<WMW>): $dict.Dict$<
  string,
  $json.Json$
>;
export function ClientMessage$Mount$provided_contexts<WMW>(value: ClientMessage$<
    WMW
  >): $dict.Dict$<string, $json.Json$>;
export function ClientMessage$Mount$7<WMW>(value: ClientMessage$<WMW>): $vnode.Element$<
  WMW
>;
export function ClientMessage$Mount$vdom<WMW>(value: ClientMessage$<WMW>): $vnode.Element$<
  WMW
>;
export function ClientMessage$Mount$8<WMW>(value: ClientMessage$<WMW>): $mutable_map.MutableMap$<
  () => $vnode.Element$<WMW>,
  $vnode.Element$<WMW>
>;
export function ClientMessage$Mount$memos<WMW>(value: ClientMessage$<WMW>): $mutable_map.MutableMap$<
  () => $vnode.Element$<WMW>,
  $vnode.Element$<WMW>
>;

export class Reconcile<WMW> extends _.CustomType {
  /** @deprecated */
  constructor(
    kind: number,
    patch: $patch.Patch$<WMW>,
    memos: $mutable_map.MutableMap$<
      () => $vnode.Element$<WMW>,
      $vnode.Element$<WMW>
    >
  );
  /** @deprecated */
  kind: number;
  /** @deprecated */
  patch: $patch.Patch$<WMW>;
  /** @deprecated */
  memos: $mutable_map.MutableMap$<
    () => $vnode.Element$<WMW>,
    $vnode.Element$<WMW>
  >;
}
export function ClientMessage$Reconcile<WMW>(
  kind: number,
  patch: $patch.Patch$<WMW>,
  memos: $mutable_map.MutableMap$<
    () => $vnode.Element$<WMW>,
    $vnode.Element$<WMW>
  >,
): ClientMessage$<WMW>;
export function ClientMessage$isReconcile<WMW>(
  value: any,
): value is ClientMessage$<unknown>;
export function ClientMessage$Reconcile$0<WMW>(value: ClientMessage$<WMW>): number;
export function ClientMessage$Reconcile$kind<WMW>(
  value: ClientMessage$<WMW>,
): number;
export function ClientMessage$Reconcile$1<WMW>(value: ClientMessage$<WMW>): $patch.Patch$<
  WMW
>;
export function ClientMessage$Reconcile$patch<WMW>(value: ClientMessage$<WMW>): $patch.Patch$<
  WMW
>;
export function ClientMessage$Reconcile$2<WMW>(value: ClientMessage$<WMW>): $mutable_map.MutableMap$<
  () => $vnode.Element$<WMW>,
  $vnode.Element$<WMW>
>;
export function ClientMessage$Reconcile$memos<WMW>(value: ClientMessage$<WMW>): $mutable_map.MutableMap$<
  () => $vnode.Element$<WMW>,
  $vnode.Element$<WMW>
>;

export class Emit extends _.CustomType {
  /** @deprecated */
  constructor(kind: number, name: string, data: $json.Json$);
  /** @deprecated */
  kind: number;
  /** @deprecated */
  name: string;
  /** @deprecated */
  data: $json.Json$;
}
export function ClientMessage$Emit<WMW>(
  kind: number,
  name: string,
  data: $json.Json$,
): ClientMessage$<WMW>;
export function ClientMessage$isEmit<WMW>(
  value: any,
): value is ClientMessage$<unknown>;
export function ClientMessage$Emit$0<WMW>(value: ClientMessage$<WMW>): number;
export function ClientMessage$Emit$kind<WMW>(value: ClientMessage$<WMW>): number;
export function ClientMessage$Emit$1<WMW>(
  value: ClientMessage$<WMW>,
): string;
export function ClientMessage$Emit$name<WMW>(value: ClientMessage$<WMW>): string;
export function ClientMessage$Emit$2<WMW>(
  value: ClientMessage$<WMW>,
): $json.Json$;
export function ClientMessage$Emit$data<WMW>(value: ClientMessage$<WMW>): $json.Json$;

export class Provide extends _.CustomType {
  /** @deprecated */
  constructor(kind: number, key: string, value: $json.Json$);
  /** @deprecated */
  kind: number;
  /** @deprecated */
  key: string;
  /** @deprecated */
  value: $json.Json$;
}
export function ClientMessage$Provide<WMW>(
  kind: number,
  key: string,
  value: $json.Json$,
): ClientMessage$<WMW>;
export function ClientMessage$isProvide<WMW>(
  value: any,
): value is ClientMessage$<unknown>;
export function ClientMessage$Provide$0<WMW>(value: ClientMessage$<WMW>): number;
export function ClientMessage$Provide$kind<WMW>(
  value: ClientMessage$<WMW>,
): number;
export function ClientMessage$Provide$1<WMW>(value: ClientMessage$<WMW>): string;
export function ClientMessage$Provide$key<WMW>(
  value: ClientMessage$<WMW>,
): string;
export function ClientMessage$Provide$2<WMW>(value: ClientMessage$<WMW>): $json.Json$;
export function ClientMessage$Provide$value<WMW>(
  value: ClientMessage$<WMW>,
): $json.Json$;

export class Subscribe extends _.CustomType {
  /** @deprecated */
  constructor(kind: number, key: string);
  /** @deprecated */
  kind: number;
  /** @deprecated */
  key: string;
}
export function ClientMessage$Subscribe<WMW>(
  kind: number,
  key: string,
): ClientMessage$<WMW>;
export function ClientMessage$isSubscribe<WMW>(
  value: any,
): value is ClientMessage$<unknown>;
export function ClientMessage$Subscribe$0<WMW>(value: ClientMessage$<WMW>): number;
export function ClientMessage$Subscribe$kind<WMW>(
  value: ClientMessage$<WMW>,
): number;
export function ClientMessage$Subscribe$1<WMW>(value: ClientMessage$<WMW>): string;
export function ClientMessage$Subscribe$key<WMW>(
  value: ClientMessage$<WMW>,
): string;

export class Unsubscribe extends _.CustomType {
  /** @deprecated */
  constructor(kind: number, key: string);
  /** @deprecated */
  kind: number;
  /** @deprecated */
  key: string;
}
export function ClientMessage$Unsubscribe<WMW>(
  kind: number,
  key: string,
): ClientMessage$<WMW>;
export function ClientMessage$isUnsubscribe<WMW>(
  value: any,
): value is ClientMessage$<unknown>;
export function ClientMessage$Unsubscribe$0<WMW>(value: ClientMessage$<WMW>): number;
export function ClientMessage$Unsubscribe$kind<WMW>(
  value: ClientMessage$<WMW>,
): number;
export function ClientMessage$Unsubscribe$1<WMW>(value: ClientMessage$<WMW>): string;
export function ClientMessage$Unsubscribe$key<WMW>(
  value: ClientMessage$<WMW>,
): string;

export type ClientMessage$<WMW> = Mount<WMW> | Reconcile<WMW> | Emit | Provide | Subscribe | Unsubscribe;

export function ClientMessage$kind<WMW>(value: ClientMessage$<WMW>): number;

export class Batch extends _.CustomType {
  /** @deprecated */
  constructor(kind: number, messages: _.List<ServerMessage$>);
  /** @deprecated */
  kind: number;
  /** @deprecated */
  messages: _.List<ServerMessage$>;
}
export function ServerMessage$Batch(
  kind: number,
  messages: _.List<ServerMessage$>,
): ServerMessage$;
export function ServerMessage$isBatch(value: any): value is ServerMessage$;
export function ServerMessage$Batch$0(value: ServerMessage$): number;
export function ServerMessage$Batch$kind(value: ServerMessage$): number;
export function ServerMessage$Batch$1(value: ServerMessage$): _.List<
  ServerMessage$
>;
export function ServerMessage$Batch$messages(value: ServerMessage$): _.List<
  ServerMessage$
>;

export class AttributeChanged extends _.CustomType {
  /** @deprecated */
  constructor(kind: number, name: string, value: string);
  /** @deprecated */
  kind: number;
  /** @deprecated */
  name: string;
  /** @deprecated */
  value: string;
}
export function ServerMessage$AttributeChanged(
  kind: number,
  name: string,
  value: string,
): ServerMessage$;
export function ServerMessage$isAttributeChanged(
  value: any,
): value is ServerMessage$;
export function ServerMessage$AttributeChanged$0(value: ServerMessage$): number;
export function ServerMessage$AttributeChanged$kind(value: ServerMessage$): number;
export function ServerMessage$AttributeChanged$1(
  value: ServerMessage$,
): string;
export function ServerMessage$AttributeChanged$name(value: ServerMessage$): string;
export function ServerMessage$AttributeChanged$2(
  value: ServerMessage$,
): string;
export function ServerMessage$AttributeChanged$value(value: ServerMessage$): string;

export class PropertyChanged extends _.CustomType {
  /** @deprecated */
  constructor(kind: number, name: string, value: $dynamic.Dynamic$);
  /** @deprecated */
  kind: number;
  /** @deprecated */
  name: string;
  /** @deprecated */
  value: $dynamic.Dynamic$;
}
export function ServerMessage$PropertyChanged(
  kind: number,
  name: string,
  value: $dynamic.Dynamic$,
): ServerMessage$;
export function ServerMessage$isPropertyChanged(
  value: any,
): value is ServerMessage$;
export function ServerMessage$PropertyChanged$0(value: ServerMessage$): number;
export function ServerMessage$PropertyChanged$kind(value: ServerMessage$): number;
export function ServerMessage$PropertyChanged$1(
  value: ServerMessage$,
): string;
export function ServerMessage$PropertyChanged$name(value: ServerMessage$): string;
export function ServerMessage$PropertyChanged$2(
  value: ServerMessage$,
): $dynamic.Dynamic$;
export function ServerMessage$PropertyChanged$value(value: ServerMessage$): $dynamic.Dynamic$;

export class EventFired extends _.CustomType {
  /** @deprecated */
  constructor(
    kind: number,
    path: string,
    name: string,
    event: $dynamic.Dynamic$
  );
  /** @deprecated */
  kind: number;
  /** @deprecated */
  path: string;
  /** @deprecated */
  name: string;
  /** @deprecated */
  event: $dynamic.Dynamic$;
}
export function ServerMessage$EventFired(
  kind: number,
  path: string,
  name: string,
  event: $dynamic.Dynamic$,
): ServerMessage$;
export function ServerMessage$isEventFired(value: any): value is ServerMessage$;
export function ServerMessage$EventFired$0(value: ServerMessage$): number;
export function ServerMessage$EventFired$kind(value: ServerMessage$): number;
export function ServerMessage$EventFired$1(value: ServerMessage$): string;
export function ServerMessage$EventFired$path(value: ServerMessage$): string;
export function ServerMessage$EventFired$2(value: ServerMessage$): string;
export function ServerMessage$EventFired$name(value: ServerMessage$): string;
export function ServerMessage$EventFired$3(value: ServerMessage$): $dynamic.Dynamic$;
export function ServerMessage$EventFired$event(
  value: ServerMessage$,
): $dynamic.Dynamic$;

export class ContextProvided extends _.CustomType {
  /** @deprecated */
  constructor(kind: number, key: string, value: $dynamic.Dynamic$);
  /** @deprecated */
  kind: number;
  /** @deprecated */
  key: string;
  /** @deprecated */
  value: $dynamic.Dynamic$;
}
export function ServerMessage$ContextProvided(
  kind: number,
  key: string,
  value: $dynamic.Dynamic$,
): ServerMessage$;
export function ServerMessage$isContextProvided(
  value: any,
): value is ServerMessage$;
export function ServerMessage$ContextProvided$0(value: ServerMessage$): number;
export function ServerMessage$ContextProvided$kind(value: ServerMessage$): number;
export function ServerMessage$ContextProvided$1(
  value: ServerMessage$,
): string;
export function ServerMessage$ContextProvided$key(value: ServerMessage$): string;
export function ServerMessage$ContextProvided$2(
  value: ServerMessage$,
): $dynamic.Dynamic$;
export function ServerMessage$ContextProvided$value(value: ServerMessage$): $dynamic.Dynamic$;

export type ServerMessage$ = Batch | AttributeChanged | PropertyChanged | EventFired | ContextProvided;

export function ServerMessage$kind(value: ServerMessage$): number;

export const mount_kind: number;

export const reconcile_kind: number;

export const emit_kind: number;

export const provide_kind: number;

export const subscribe_kind: number;

export const unsubscribe_kind: number;

export const attribute_changed_kind: number;

export const event_fired_kind: number;

export const property_changed_kind: number;

export const batch_kind: number;

export const context_provided_kind: number;

export function mount<WNC>(
  open_shadow_root: boolean,
  will_adopt_styles: boolean,
  observed_attributes: _.List<string>,
  observed_properties: _.List<string>,
  requested_contexts: _.List<string>,
  provided_contexts: $dict.Dict$<string, $json.Json$>,
  vdom: $vnode.Element$<WNC>,
  memos: $mutable_map.MutableMap$<
    () => $vnode.Element$<WNC>,
    $vnode.Element$<WNC>
  >
): ClientMessage$<WNC>;

export function reconcile<WNG>(
  patch: $patch.Patch$<WNG>,
  memos: $mutable_map.MutableMap$<
    () => $vnode.Element$<WNG>,
    $vnode.Element$<WNG>
  >
): ClientMessage$<WNG>;

export function emit(name: string, data: $json.Json$): ClientMessage$<any>;

export function provide(key: string, value: $json.Json$): ClientMessage$<any>;

export function subscribe(key: string): ClientMessage$<any>;

export function unsubscribe(key: string): ClientMessage$<any>;

export function attribute_changed(name: string, value: string): ServerMessage$;

export function event_fired(
  path: string,
  name: string,
  event: $dynamic.Dynamic$
): ServerMessage$;

export function property_changed(name: string, value: $dynamic.Dynamic$): ServerMessage$;

export function batch(messages: _.List<ServerMessage$>): ServerMessage$;

export function context_provided(key: string, value: $dynamic.Dynamic$): ServerMessage$;

export function client_message_to_json(message: ClientMessage$<any>): $json.Json$;

export function server_message_decoder(): $decode.Decoder$<ServerMessage$>;

export function context_provided_decoder(): $decode.Decoder$<ServerMessage$>;
