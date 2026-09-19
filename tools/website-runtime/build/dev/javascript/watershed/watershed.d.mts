import type * as $promise from "../gleam_javascript/gleam/javascript/promise.d.mts";
import type * as $json from "../gleam_json/gleam/json.d.mts";
import type * as $option from "../gleam_stdlib/gleam/option.d.mts";
import type * as $sequence from "../lattice_sequence/lattice_sequence/sequence.d.mts";
import type * as $message from "../spillway/spillway/message.d.mts";
import type * as _ from "./gleam.d.mts";
import type * as $channel from "./watershed/channel.d.mts";
import type * as $claims_kernel from "./watershed/claims_kernel.d.mts";
import type * as $counter_kernel from "./watershed/counter_kernel.d.mts";
import type * as $directory_kernel from "./watershed/directory_kernel.d.mts";
import type * as $g_counter_kernel from "./watershed/g_counter_kernel.d.mts";
import type * as $g_set_kernel from "./watershed/g_set_kernel.d.mts";
import type * as $git_storage from "./watershed/git_storage.d.mts";
import type * as $json_ot from "./watershed/json_ot.d.mts";
import type * as $json_ot_kernel from "./watershed/json_ot_kernel.d.mts";
import type * as $lww_map_kernel from "./watershed/lww_map_kernel.d.mts";
import type * as $lww_register_kernel from "./watershed/lww_register_kernel.d.mts";
import type * as $map_kernel from "./watershed/map_kernel.d.mts";
import type * as $mv_register_kernel from "./watershed/mv_register_kernel.d.mts";
import type * as $or_map_kernel from "./watershed/or_map_kernel.d.mts";
import type * as $or_set_kernel from "./watershed/or_set_kernel.d.mts";
import type * as $ordered_collection_kernel from "./watershed/ordered_collection_kernel.d.mts";
import type * as $pact_map_kernel from "./watershed/pact_map_kernel.d.mts";
import type * as $pn_counter_kernel from "./watershed/pn_counter_kernel.d.mts";
import type * as $register_collection_kernel from "./watershed/register_collection_kernel.d.mts";
import type * as $rich_text from "./watershed/rich_text.d.mts";
import type * as $rich_text_kernel from "./watershed/rich_text_kernel.d.mts";
import type * as $runtime from "./watershed/runtime.d.mts";
import type * as $schema from "./watershed/schema.d.mts";
import type * as $sequence_kernel from "./watershed/sequence_kernel.d.mts";
import type * as $summary_policy from "./watershed/summary_policy.d.mts";
import type * as $task_manager_kernel from "./watershed/task_manager_kernel.d.mts";
import type * as $text_kernel from "./watershed/text_kernel.d.mts";
import type * as $two_p_set_kernel from "./watershed/two_p_set_kernel.d.mts";
import type * as $summary_blob from "./watershed/wire/summary_blob.d.mts";

export class WatershedConfig extends _.CustomType {
  /** @deprecated */
  constructor(
    url: string,
    tenant: string,
    document: string,
    token: string,
    user_id: string
  );
  /** @deprecated */
  url: string;
  /** @deprecated */
  tenant: string;
  /** @deprecated */
  document: string;
  /** @deprecated */
  token: string;
  /** @deprecated */
  user_id: string;
}
export function WatershedConfig$WatershedConfig(
  url: string,
  tenant: string,
  document: string,
  token: string,
  user_id: string,
): WatershedConfig$;
export function WatershedConfig$isWatershedConfig(
  value: any,
): value is WatershedConfig$;
export function WatershedConfig$WatershedConfig$0(value: WatershedConfig$): string;
export function WatershedConfig$WatershedConfig$url(
  value: WatershedConfig$,
): string;
export function WatershedConfig$WatershedConfig$1(value: WatershedConfig$): string;
export function WatershedConfig$WatershedConfig$tenant(
  value: WatershedConfig$,
): string;
export function WatershedConfig$WatershedConfig$2(value: WatershedConfig$): string;
export function WatershedConfig$WatershedConfig$document(
  value: WatershedConfig$,
): string;
export function WatershedConfig$WatershedConfig$3(value: WatershedConfig$): string;
export function WatershedConfig$WatershedConfig$token(
  value: WatershedConfig$,
): string;
export function WatershedConfig$WatershedConfig$4(value: WatershedConfig$): string;
export function WatershedConfig$WatershedConfig$user_id(
  value: WatershedConfig$,
): string;

export type WatershedConfig$ = WatershedConfig;

declare class Document extends _.CustomType {
  /** @deprecated */
  constructor(runtime: $runtime.Runtime$);
  /** @deprecated */
  runtime: $runtime.Runtime$;
}

export type Document$<BHAL> = Document;

declare class SubscriptionToken extends _.CustomType {
  /** @deprecated */
  constructor(runtime_token: $runtime.SubscriptionToken$);
  /** @deprecated */
  runtime_token: $runtime.SubscriptionToken$;
}

export type SubscriptionToken$ = SubscriptionToken;

declare class SharedMap extends _.CustomType {
  /** @deprecated */
  constructor(runtime: $runtime.Runtime$, address: string);
  /** @deprecated */
  runtime: $runtime.Runtime$;
  /** @deprecated */
  address: string;
}

export type SharedMap$ = SharedMap;

declare class SharedCounter extends _.CustomType {
  /** @deprecated */
  constructor(runtime: $runtime.Runtime$, address: string);
  /** @deprecated */
  runtime: $runtime.Runtime$;
  /** @deprecated */
  address: string;
}

export type SharedCounter$ = SharedCounter;

declare class OrMap extends _.CustomType {
  /** @deprecated */
  constructor(runtime: $runtime.Runtime$, address: string);
  /** @deprecated */
  runtime: $runtime.Runtime$;
  /** @deprecated */
  address: string;
}

export type OrMap$ = OrMap;

declare class OrSet extends _.CustomType {
  /** @deprecated */
  constructor(runtime: $runtime.Runtime$, address: string);
  /** @deprecated */
  runtime: $runtime.Runtime$;
  /** @deprecated */
  address: string;
}

export type OrSet$ = OrSet;

declare class RegisterCollection extends _.CustomType {
  /** @deprecated */
  constructor(runtime: $runtime.Runtime$, address: string);
  /** @deprecated */
  runtime: $runtime.Runtime$;
  /** @deprecated */
  address: string;
}

export type RegisterCollection$ = RegisterCollection;

declare class Claims extends _.CustomType {
  /** @deprecated */
  constructor(runtime: $runtime.Runtime$, address: string);
  /** @deprecated */
  runtime: $runtime.Runtime$;
  /** @deprecated */
  address: string;
}

export type Claims$ = Claims;

declare class TaskManager extends _.CustomType {
  /** @deprecated */
  constructor(runtime: $runtime.Runtime$, address: string);
  /** @deprecated */
  runtime: $runtime.Runtime$;
  /** @deprecated */
  address: string;
}

export type TaskManager$ = TaskManager;

declare class PnCounter extends _.CustomType {
  /** @deprecated */
  constructor(runtime: $runtime.Runtime$, address: string);
  /** @deprecated */
  runtime: $runtime.Runtime$;
  /** @deprecated */
  address: string;
}

export type PnCounter$ = PnCounter;

declare class GCounter extends _.CustomType {
  /** @deprecated */
  constructor(runtime: $runtime.Runtime$, address: string);
  /** @deprecated */
  runtime: $runtime.Runtime$;
  /** @deprecated */
  address: string;
}

export type GCounter$ = GCounter;

declare class LwwRegister extends _.CustomType {
  /** @deprecated */
  constructor(runtime: $runtime.Runtime$, address: string);
  /** @deprecated */
  runtime: $runtime.Runtime$;
  /** @deprecated */
  address: string;
}

export type LwwRegister$ = LwwRegister;

declare class LwwMap extends _.CustomType {
  /** @deprecated */
  constructor(runtime: $runtime.Runtime$, address: string);
  /** @deprecated */
  runtime: $runtime.Runtime$;
  /** @deprecated */
  address: string;
}

export type LwwMap$ = LwwMap;

declare class PactMap extends _.CustomType {
  /** @deprecated */
  constructor(runtime: $runtime.Runtime$, address: string);
  /** @deprecated */
  runtime: $runtime.Runtime$;
  /** @deprecated */
  address: string;
}

export type PactMap$ = PactMap;

declare class OrderedCollection extends _.CustomType {
  /** @deprecated */
  constructor(runtime: $runtime.Runtime$, address: string);
  /** @deprecated */
  runtime: $runtime.Runtime$;
  /** @deprecated */
  address: string;
}

export type OrderedCollection$ = OrderedCollection;

declare class SharedSequence extends _.CustomType {
  /** @deprecated */
  constructor(runtime: $runtime.Runtime$, address: string);
  /** @deprecated */
  runtime: $runtime.Runtime$;
  /** @deprecated */
  address: string;
}

export type SharedSequence$ = SharedSequence;

declare class SharedText extends _.CustomType {
  /** @deprecated */
  constructor(runtime: $runtime.Runtime$, address: string);
  /** @deprecated */
  runtime: $runtime.Runtime$;
  /** @deprecated */
  address: string;
}

export type SharedText$ = SharedText;

declare class JsonOt extends _.CustomType {
  /** @deprecated */
  constructor(runtime: $runtime.Runtime$, address: string);
  /** @deprecated */
  runtime: $runtime.Runtime$;
  /** @deprecated */
  address: string;
}

export type JsonOt$ = JsonOt;

declare class SharedRichText extends _.CustomType {
  /** @deprecated */
  constructor(runtime: $runtime.Runtime$, address: string);
  /** @deprecated */
  runtime: $runtime.Runtime$;
  /** @deprecated */
  address: string;
}

export type SharedRichText$ = SharedRichText;

declare class GSet extends _.CustomType {
  /** @deprecated */
  constructor(runtime: $runtime.Runtime$, address: string);
  /** @deprecated */
  runtime: $runtime.Runtime$;
  /** @deprecated */
  address: string;
}

export type GSet$ = GSet;

declare class TwoPSet extends _.CustomType {
  /** @deprecated */
  constructor(runtime: $runtime.Runtime$, address: string);
  /** @deprecated */
  runtime: $runtime.Runtime$;
  /** @deprecated */
  address: string;
}

export type TwoPSet$ = TwoPSet;

declare class SharedDirectory extends _.CustomType {
  /** @deprecated */
  constructor(runtime: $runtime.Runtime$, address: string);
  /** @deprecated */
  runtime: $runtime.Runtime$;
  /** @deprecated */
  address: string;
}

export type SharedDirectory$ = SharedDirectory;

declare class TypedMap extends _.CustomType {
  /** @deprecated */
  constructor(map: SharedMap$);
  /** @deprecated */
  map: SharedMap$;
}

export type TypedMap$<BHAM> = TypedMap;

declare class Ripple extends _.CustomType {
  /** @deprecated */
  constructor(signal: $message.SignalMessage$);
  /** @deprecated */
  signal: $message.SignalMessage$;
}

export type Ripple$ = Ripple;

declare class MvRegister extends _.CustomType {
  /** @deprecated */
  constructor(runtime: $runtime.Runtime$, address: string);
  /** @deprecated */
  runtime: $runtime.Runtime$;
  /** @deprecated */
  address: string;
}

export type MvRegister$ = MvRegister;

export type Diagnostics = $runtime.Diagnostics$;

export type TextAnchor = $text_kernel.TextAnchor$;

export type Bias = $sequence.Bias$;

export const bias_before: $sequence.Bias$;

export const bias_after: $sequence.Bias$;

export function connect(
  config: WatershedConfig$,
  on_ready: (x0: _.Result<undefined, string>) => undefined
): Document$<any>;

export function connect_via(
  tenant: string,
  document: string,
  user_id: string,
  transport: $runtime.Transport$,
  on_ready: (x0: _.Result<undefined, string>) => undefined
): Document$<any>;

export function runtime_of(document: Document$<any>): $runtime.Runtime$;

export function root(document: Document$<any>): SharedMap$;

export function create_map(document: Document$<any>): _.Result<
  SharedMap$,
  string
>;

export function handle_of(map: SharedMap$): $json.Json$;

export function is_handle(value: $json.Json$): boolean;

export function resolve(document: Document$<any>, value: $json.Json$): _.Result<
  SharedMap$,
  string
>;

export function typed(map: SharedMap$): TypedMap$<any>;

export function untyped(typed_map: TypedMap$<any>): SharedMap$;

export function root_typed<BHBL>(document: Document$<BHBL>): TypedMap$<BHBL>;

export function create_typed_map(document: Document$<any>): _.Result<
  TypedMap$<any>,
  string
>;

export function set(map: SharedMap$, key: string, value: $json.Json$): undefined;

export function set_field<BHBU, BHBW>(
  typed_map: TypedMap$<BHBU>,
  field: $schema.Field$<BHBU, BHBW>,
  value: BHBW
): undefined;

export function delete$(map: SharedMap$, key: string): undefined;

export function delete_field<BHBZ>(
  typed_map: TypedMap$<BHBZ>,
  field: $schema.Field$<BHBZ, any>
): undefined;

export function get(map: SharedMap$, key: string): _.Result<
  $json.Json$,
  undefined
>;

export function get_field<BHCE, BHCG>(
  typed_map: TypedMap$<BHCE>,
  field: $schema.Field$<BHCE, BHCG>
): _.Result<$option.Option$<BHCG>, $schema.FieldError$>;

export function get_required<BHCM, BHCO>(
  typed_map: TypedMap$<BHCM>,
  field: $schema.Field$<BHCM, BHCO>
): _.Result<BHCO, $schema.FieldError$>;

export function has(map: SharedMap$, key: string): boolean;

export function has_field<BHCT>(
  typed_map: TypedMap$<BHCT>,
  field: $schema.Field$<BHCT, any>
): boolean;

export function set_child<BHCY, BHDA>(
  typed_map: TypedMap$<BHCY>,
  field: $schema.ChildField$<BHCY, BHDA>,
  child: TypedMap$<BHDA>
): undefined;

export function resolve_child<BHDG, BHDI>(
  document: Document$<any>,
  typed_map: TypedMap$<BHDG>,
  field: $schema.ChildField$<BHDG, BHDI>
): _.Result<$option.Option$<TypedMap$<BHDI>>, string>;

export function entries(map: SharedMap$): _.List<[string, $json.Json$]>;

export function read<BHDP, BHDR>(
  typed_map: TypedMap$<BHDP>,
  map_schema: $schema.Schema$<BHDP, BHDR>
): _.Result<BHDR, $schema.FieldError$>;

export function write<BHDW, BHDY>(
  typed_map: TypedMap$<BHDW>,
  map_schema: $schema.Schema$<BHDW, BHDY>,
  value: BHDY
): undefined;

export function stamp<BHEB>(
  typed_map: TypedMap$<BHEB>,
  map_schema: $schema.Schema$<BHEB, any>
): undefined;

export function typed_children(
  document: Document$<any>,
  typed_map: TypedMap$<any>
): _.List<[string, _.Result<TypedMap$<any>, string>]>;

export function set_map_field<BHFI>(
  typed_map: TypedMap$<BHFI>,
  field: $schema.ChannelField$<BHFI, $schema.MapChannel$>,
  map: SharedMap$
): undefined;

export function resolve_map_field<BHFO>(
  document: Document$<any>,
  typed_map: TypedMap$<BHFO>,
  field: $schema.ChannelField$<BHFO, $schema.MapChannel$>
): _.Result<$option.Option$<SharedMap$>, string>;

export function counter_handle_of(counter: SharedCounter$): $json.Json$;

export function set_counter_field<BHFV>(
  typed_map: TypedMap$<BHFV>,
  field: $schema.ChannelField$<BHFV, $schema.CounterChannel$>,
  counter: SharedCounter$
): undefined;

export function resolve_counter(document: Document$<any>, value: $json.Json$): _.Result<
  SharedCounter$,
  string
>;

export function resolve_counter_field<BHGB>(
  document: Document$<any>,
  typed_map: TypedMap$<BHGB>,
  field: $schema.ChannelField$<BHGB, $schema.CounterChannel$>
): _.Result<$option.Option$<SharedCounter$>, string>;

export function or_map_handle_of(or_map: OrMap$): $json.Json$;

export function set_or_map_field<BHGI>(
  typed_map: TypedMap$<BHGI>,
  field: $schema.ChannelField$<BHGI, $schema.OrMapChannel$>,
  or_map: OrMap$
): undefined;

export function resolve_or_map(document: Document$<any>, value: $json.Json$): _.Result<
  OrMap$,
  string
>;

export function resolve_or_map_field<BHGO>(
  document: Document$<any>,
  typed_map: TypedMap$<BHGO>,
  field: $schema.ChannelField$<BHGO, $schema.OrMapChannel$>
): _.Result<$option.Option$<OrMap$>, string>;

export function or_set_handle_of(or_set: OrSet$): $json.Json$;

export function set_or_set_field<BHGV>(
  typed_map: TypedMap$<BHGV>,
  field: $schema.ChannelField$<BHGV, $schema.OrSetChannel$>,
  or_set: OrSet$
): undefined;

export function resolve_or_set(document: Document$<any>, value: $json.Json$): _.Result<
  OrSet$,
  string
>;

export function resolve_or_set_field<BHHB>(
  document: Document$<any>,
  typed_map: TypedMap$<BHHB>,
  field: $schema.ChannelField$<BHHB, $schema.OrSetChannel$>
): _.Result<$option.Option$<OrSet$>, string>;

export function sequence_handle_of(sequence: SharedSequence$): $json.Json$;

export function set_sequence_field<BHHI>(
  typed_map: TypedMap$<BHHI>,
  field: $schema.ChannelField$<BHHI, $schema.SequenceChannel$>,
  sequence: SharedSequence$
): undefined;

export function resolve_sequence(document: Document$<any>, value: $json.Json$): _.Result<
  SharedSequence$,
  string
>;

export function resolve_sequence_field<BHHO>(
  document: Document$<any>,
  typed_map: TypedMap$<BHHO>,
  field: $schema.ChannelField$<BHHO, $schema.SequenceChannel$>
): _.Result<$option.Option$<SharedSequence$>, string>;

export function text_handle_of(text: SharedText$): $json.Json$;

export function set_text_field<BHHV>(
  typed_map: TypedMap$<BHHV>,
  field: $schema.ChannelField$<BHHV, $schema.TextChannel$>,
  text: SharedText$
): undefined;

export function resolve_text(document: Document$<any>, value: $json.Json$): _.Result<
  SharedText$,
  string
>;

export function resolve_text_field<BHIB>(
  document: Document$<any>,
  typed_map: TypedMap$<BHIB>,
  field: $schema.ChannelField$<BHIB, $schema.TextChannel$>
): _.Result<$option.Option$<SharedText$>, string>;

export function register_collection_handle_of(collection: RegisterCollection$): $json.Json$;

export function set_register_collection_field<BHII>(
  typed_map: TypedMap$<BHII>,
  field: $schema.ChannelField$<BHII, $schema.RegisterCollectionChannel$>,
  collection: RegisterCollection$
): undefined;

export function resolve_register_collection(
  document: Document$<any>,
  value: $json.Json$
): _.Result<RegisterCollection$, string>;

export function resolve_register_collection_field<BHIO>(
  document: Document$<any>,
  typed_map: TypedMap$<BHIO>,
  field: $schema.ChannelField$<BHIO, $schema.RegisterCollectionChannel$>
): _.Result<$option.Option$<RegisterCollection$>, string>;

export function claims_handle_of(claims: Claims$): $json.Json$;

export function set_claims_field<BHIV>(
  typed_map: TypedMap$<BHIV>,
  field: $schema.ChannelField$<BHIV, $schema.ClaimsChannel$>,
  claims: Claims$
): undefined;

export function resolve_claims(document: Document$<any>, value: $json.Json$): _.Result<
  Claims$,
  string
>;

export function resolve_claims_field<BHJB>(
  document: Document$<any>,
  typed_map: TypedMap$<BHJB>,
  field: $schema.ChannelField$<BHJB, $schema.ClaimsChannel$>
): _.Result<$option.Option$<Claims$>, string>;

export function task_manager_handle_of(manager: TaskManager$): $json.Json$;

export function set_task_manager_field<BHJI>(
  typed_map: TypedMap$<BHJI>,
  field: $schema.ChannelField$<BHJI, $schema.TaskManagerChannel$>,
  manager: TaskManager$
): undefined;

export function resolve_task_manager(
  document: Document$<any>,
  value: $json.Json$
): _.Result<TaskManager$, string>;

export function resolve_task_manager_field<BHJO>(
  document: Document$<any>,
  typed_map: TypedMap$<BHJO>,
  field: $schema.ChannelField$<BHJO, $schema.TaskManagerChannel$>
): _.Result<$option.Option$<TaskManager$>, string>;

export function pn_counter_handle_of(pn_counter: PnCounter$): $json.Json$;

export function set_pn_counter_field<BHJV>(
  typed_map: TypedMap$<BHJV>,
  field: $schema.ChannelField$<BHJV, $schema.PnCounterChannel$>,
  pn_counter: PnCounter$
): undefined;

export function g_counter_handle_of(g_counter: GCounter$): $json.Json$;

export function set_g_counter_field<BHJZ>(
  typed_map: TypedMap$<BHJZ>,
  field: $schema.ChannelField$<BHJZ, $schema.GCounterChannel$>,
  g_counter: GCounter$
): undefined;

export function resolve_pn_counter(document: Document$<any>, value: $json.Json$): _.Result<
  PnCounter$,
  string
>;

export function resolve_pn_counter_field<BHKF>(
  document: Document$<any>,
  typed_map: TypedMap$<BHKF>,
  field: $schema.ChannelField$<BHKF, $schema.PnCounterChannel$>
): _.Result<$option.Option$<PnCounter$>, string>;

export function resolve_g_counter(document: Document$<any>, value: $json.Json$): _.Result<
  GCounter$,
  string
>;

export function resolve_g_counter_field<BHKO>(
  document: Document$<any>,
  typed_map: TypedMap$<BHKO>,
  field: $schema.ChannelField$<BHKO, $schema.GCounterChannel$>
): _.Result<$option.Option$<GCounter$>, string>;

export function lww_register_handle_of(register: LwwRegister$): $json.Json$;

export function set_lww_register_field<BHKV>(
  typed_map: TypedMap$<BHKV>,
  field: $schema.ChannelField$<BHKV, $schema.LwwRegisterChannel$>,
  register: LwwRegister$
): undefined;

export function resolve_lww_register(
  document: Document$<any>,
  value: $json.Json$
): _.Result<LwwRegister$, string>;

export function resolve_lww_register_field<BHLB>(
  document: Document$<any>,
  typed_map: TypedMap$<BHLB>,
  field: $schema.ChannelField$<BHLB, $schema.LwwRegisterChannel$>
): _.Result<$option.Option$<LwwRegister$>, string>;

export function pact_map_handle_of(pact_map: PactMap$): $json.Json$;

export function set_pact_map_field<BHLI>(
  typed_map: TypedMap$<BHLI>,
  field: $schema.ChannelField$<BHLI, $schema.PactMapChannel$>,
  pact_map: PactMap$
): undefined;

export function resolve_pact_map(document: Document$<any>, value: $json.Json$): _.Result<
  PactMap$,
  string
>;

export function resolve_pact_map_field<BHLO>(
  document: Document$<any>,
  typed_map: TypedMap$<BHLO>,
  field: $schema.ChannelField$<BHLO, $schema.PactMapChannel$>
): _.Result<$option.Option$<PactMap$>, string>;

export function ordered_collection_handle_of(collection: OrderedCollection$): $json.Json$;

export function set_ordered_collection_field<BHLV>(
  typed_map: TypedMap$<BHLV>,
  field: $schema.ChannelField$<BHLV, $schema.OrderedCollectionChannel$>,
  collection: OrderedCollection$
): undefined;

export function resolve_ordered_collection(
  document: Document$<any>,
  value: $json.Json$
): _.Result<OrderedCollection$, string>;

export function resolve_ordered_collection_field<BHMB>(
  document: Document$<any>,
  typed_map: TypedMap$<BHMB>,
  field: $schema.ChannelField$<BHMB, $schema.OrderedCollectionChannel$>
): _.Result<$option.Option$<OrderedCollection$>, string>;

export function json_ot_handle_of(json_ot: JsonOt$): $json.Json$;

export function set_json_ot_field<BHMI>(
  typed_map: TypedMap$<BHMI>,
  field: $schema.ChannelField$<BHMI, $schema.JsonOtChannel$>,
  json_ot: JsonOt$
): undefined;

export function resolve_json_ot(document: Document$<any>, value: $json.Json$): _.Result<
  JsonOt$,
  string
>;

export function resolve_json_ot_field<BHMO>(
  document: Document$<any>,
  typed_map: TypedMap$<BHMO>,
  field: $schema.ChannelField$<BHMO, $schema.JsonOtChannel$>
): _.Result<$option.Option$<JsonOt$>, string>;

export function rich_text_handle_of(rich_text: SharedRichText$): $json.Json$;

export function set_rich_text_field<BHMV>(
  typed_map: TypedMap$<BHMV>,
  field: $schema.ChannelField$<BHMV, $schema.RichTextChannel$>,
  rich_text: SharedRichText$
): undefined;

export function resolve_rich_text(document: Document$<any>, value: $json.Json$): _.Result<
  SharedRichText$,
  string
>;

export function resolve_rich_text_field<BHNB>(
  document: Document$<any>,
  typed_map: TypedMap$<BHNB>,
  field: $schema.ChannelField$<BHNB, $schema.RichTextChannel$>
): _.Result<$option.Option$<SharedRichText$>, string>;

export function g_set_handle_of(set: GSet$): $json.Json$;

export function set_g_set_field<BHNI>(
  typed_map: TypedMap$<BHNI>,
  field: $schema.ChannelField$<BHNI, $schema.GSetChannel$>,
  set: GSet$
): undefined;

export function resolve_g_set(document: Document$<any>, value: $json.Json$): _.Result<
  GSet$,
  string
>;

export function resolve_g_set_field<BHNO>(
  document: Document$<any>,
  typed_map: TypedMap$<BHNO>,
  field: $schema.ChannelField$<BHNO, $schema.GSetChannel$>
): _.Result<$option.Option$<GSet$>, string>;

export function two_p_set_handle_of(set: TwoPSet$): $json.Json$;

export function set_two_p_set_field<BHNV>(
  typed_map: TypedMap$<BHNV>,
  field: $schema.ChannelField$<BHNV, $schema.TwoPSetChannel$>,
  set: TwoPSet$
): undefined;

export function resolve_two_p_set(document: Document$<any>, value: $json.Json$): _.Result<
  TwoPSet$,
  string
>;

export function resolve_two_p_set_field<BHOB>(
  document: Document$<any>,
  typed_map: TypedMap$<BHOB>,
  field: $schema.ChannelField$<BHOB, $schema.TwoPSetChannel$>
): _.Result<$option.Option$<TwoPSet$>, string>;

export function directory_handle_of(directory: SharedDirectory$): $json.Json$;

export function set_directory_field<BHOI>(
  typed_map: TypedMap$<BHOI>,
  field: $schema.ChannelField$<BHOI, $schema.DirectoryChannel$>,
  directory: SharedDirectory$
): undefined;

export function resolve_directory(document: Document$<any>, value: $json.Json$): _.Result<
  SharedDirectory$,
  string
>;

export function resolve_directory_field<BHOO>(
  document: Document$<any>,
  typed_map: TypedMap$<BHOO>,
  field: $schema.ChannelField$<BHOO, $schema.DirectoryChannel$>
): _.Result<$option.Option$<SharedDirectory$>, string>;

export function is_synced(document: Document$<any>): boolean;

export function ensure_map<BHPV>(
  document: Document$<any>,
  typed_map: TypedMap$<BHPV>,
  field: $schema.ChannelField$<BHPV, $schema.MapChannel$>,
  done: (x0: _.Result<SharedMap$, string>) => undefined
): undefined;

export function create_counter(document: Document$<any>): _.Result<
  SharedCounter$,
  string
>;

export function ensure_counter<BHQD>(
  document: Document$<any>,
  typed_map: TypedMap$<BHQD>,
  field: $schema.ChannelField$<BHQD, $schema.CounterChannel$>,
  done: (x0: _.Result<SharedCounter$, string>) => undefined
): undefined;

export function create_or_map(
  document: Document$<any>,
  mode: $or_map_kernel.OrMapMode$
): _.Result<OrMap$, string>;

export function ensure_or_map<BHQL>(
  document: Document$<any>,
  typed_map: TypedMap$<BHQL>,
  field: $schema.ChannelField$<BHQL, $schema.OrMapChannel$>,
  mode: $or_map_kernel.OrMapMode$,
  done: (x0: _.Result<OrMap$, string>) => undefined
): undefined;

export function create_or_set(document: Document$<any>): _.Result<
  OrSet$,
  string
>;

export function ensure_or_set<BHQT>(
  document: Document$<any>,
  typed_map: TypedMap$<BHQT>,
  field: $schema.ChannelField$<BHQT, $schema.OrSetChannel$>,
  done: (x0: _.Result<OrSet$, string>) => undefined
): undefined;

export function create_sequence(document: Document$<any>): _.Result<
  SharedSequence$,
  string
>;

export function ensure_sequence<BHRB>(
  document: Document$<any>,
  typed_map: TypedMap$<BHRB>,
  field: $schema.ChannelField$<BHRB, $schema.SequenceChannel$>,
  done: (x0: _.Result<SharedSequence$, string>) => undefined
): undefined;

export function create_text(document: Document$<any>): _.Result<
  SharedText$,
  string
>;

export function ensure_text<BHRJ>(
  document: Document$<any>,
  typed_map: TypedMap$<BHRJ>,
  field: $schema.ChannelField$<BHRJ, $schema.TextChannel$>,
  done: (x0: _.Result<SharedText$, string>) => undefined
): undefined;

export function create_register_collection(document: Document$<any>): _.Result<
  RegisterCollection$,
  string
>;

export function ensure_register_collection<BHRR>(
  document: Document$<any>,
  typed_map: TypedMap$<BHRR>,
  field: $schema.ChannelField$<BHRR, $schema.RegisterCollectionChannel$>,
  done: (x0: _.Result<RegisterCollection$, string>) => undefined
): undefined;

export function create_claims(document: Document$<any>): _.Result<
  Claims$,
  string
>;

export function ensure_claims<BHRZ>(
  document: Document$<any>,
  typed_map: TypedMap$<BHRZ>,
  field: $schema.ChannelField$<BHRZ, $schema.ClaimsChannel$>,
  done: (x0: _.Result<Claims$, string>) => undefined
): undefined;

export function create_task_manager(document: Document$<any>): _.Result<
  TaskManager$,
  string
>;

export function ensure_task_manager<BHSH>(
  document: Document$<any>,
  typed_map: TypedMap$<BHSH>,
  field: $schema.ChannelField$<BHSH, $schema.TaskManagerChannel$>,
  done: (x0: _.Result<TaskManager$, string>) => undefined
): undefined;

export function create_pn_counter(document: Document$<any>): _.Result<
  PnCounter$,
  string
>;

export function ensure_pn_counter<BHSP>(
  document: Document$<any>,
  typed_map: TypedMap$<BHSP>,
  field: $schema.ChannelField$<BHSP, $schema.PnCounterChannel$>,
  done: (x0: _.Result<PnCounter$, string>) => undefined
): undefined;

export function create_g_counter(document: Document$<any>): _.Result<
  GCounter$,
  string
>;

export function ensure_g_counter<BHSX>(
  document: Document$<any>,
  typed_map: TypedMap$<BHSX>,
  field: $schema.ChannelField$<BHSX, $schema.GCounterChannel$>,
  done: (x0: _.Result<GCounter$, string>) => undefined
): undefined;

export function create_lww_register(document: Document$<any>): _.Result<
  LwwRegister$,
  string
>;

export function ensure_lww_register<BHTF>(
  document: Document$<any>,
  typed_map: TypedMap$<BHTF>,
  field: $schema.ChannelField$<BHTF, $schema.LwwRegisterChannel$>,
  done: (x0: _.Result<LwwRegister$, string>) => undefined
): undefined;

export function create_pact_map(document: Document$<any>): _.Result<
  PactMap$,
  string
>;

export function ensure_pact_map<BHTN>(
  document: Document$<any>,
  typed_map: TypedMap$<BHTN>,
  field: $schema.ChannelField$<BHTN, $schema.PactMapChannel$>,
  done: (x0: _.Result<PactMap$, string>) => undefined
): undefined;

export function create_ordered_collection(document: Document$<any>): _.Result<
  OrderedCollection$,
  string
>;

export function ensure_ordered_collection<BHTV>(
  document: Document$<any>,
  typed_map: TypedMap$<BHTV>,
  field: $schema.ChannelField$<BHTV, $schema.OrderedCollectionChannel$>,
  done: (x0: _.Result<OrderedCollection$, string>) => undefined
): undefined;

export function create_json_ot(document: Document$<any>): _.Result<
  JsonOt$,
  string
>;

export function ensure_json_ot<BHUD>(
  document: Document$<any>,
  typed_map: TypedMap$<BHUD>,
  field: $schema.ChannelField$<BHUD, $schema.JsonOtChannel$>,
  done: (x0: _.Result<JsonOt$, string>) => undefined
): undefined;

export function create_rich_text(document: Document$<any>): _.Result<
  SharedRichText$,
  string
>;

export function ensure_rich_text<BHUL>(
  document: Document$<any>,
  typed_map: TypedMap$<BHUL>,
  field: $schema.ChannelField$<BHUL, $schema.RichTextChannel$>,
  done: (x0: _.Result<SharedRichText$, string>) => undefined
): undefined;

export function create_g_set(document: Document$<any>): _.Result<GSet$, string>;

export function ensure_g_set<BHUT>(
  document: Document$<any>,
  typed_map: TypedMap$<BHUT>,
  field: $schema.ChannelField$<BHUT, $schema.GSetChannel$>,
  done: (x0: _.Result<GSet$, string>) => undefined
): undefined;

export function create_two_p_set(document: Document$<any>): _.Result<
  TwoPSet$,
  string
>;

export function ensure_two_p_set<BHVB>(
  document: Document$<any>,
  typed_map: TypedMap$<BHVB>,
  field: $schema.ChannelField$<BHVB, $schema.TwoPSetChannel$>,
  done: (x0: _.Result<TwoPSet$, string>) => undefined
): undefined;

export function create_directory(document: Document$<any>): _.Result<
  SharedDirectory$,
  string
>;

export function ensure_directory<BHVJ>(
  document: Document$<any>,
  typed_map: TypedMap$<BHVJ>,
  field: $schema.ChannelField$<BHVJ, $schema.DirectoryChannel$>,
  done: (x0: _.Result<SharedDirectory$, string>) => undefined
): undefined;

export function ensure_child<BHVR, BHVT>(
  document: Document$<any>,
  typed_map: TypedMap$<BHVR>,
  field: $schema.ChildField$<BHVR, BHVT>,
  done: (x0: _.Result<TypedMap$<BHVT>, string>) => undefined
): undefined;

export function ensure_field<BHVZ, BHWB>(
  typed_map: TypedMap$<BHVZ>,
  field: $schema.Field$<BHVZ, BHWB>,
  default$: BHWB
): undefined;

export function increment(counter: SharedCounter$, amount: number): undefined;

export function counter_value(counter: SharedCounter$): _.Result<
  number,
  undefined
>;

export function unsubscribe(token: SubscriptionToken$): undefined;

export function subscribe_counter(
  counter: SharedCounter$,
  handler: (x0: $counter_kernel.CounterEvent$) => undefined
): SubscriptionToken$;

export function or_map_increment(or_map: OrMap$, key: string, amount: number): undefined;

export function or_map_set(or_map: OrMap$, key: string, value: string): undefined;

export function or_map_set_json(or_map: OrMap$, key: string, value: $json.Json$): undefined;

export function or_map_set_mv_register(
  or_map: OrMap$,
  key: string,
  value: string
): undefined;

export function or_map_values(or_map: OrMap$, key: string): _.Result<
  _.List<string>,
  undefined
>;

export function or_map_remove(or_map: OrMap$, key: string): undefined;

export function or_map_add_member(or_map: OrMap$, key: string, member: string): _.Result<
  undefined,
  string
>;

export function or_map_remove_member(
  or_map: OrMap$,
  key: string,
  member: string
): _.Result<undefined, string>;

export function or_map_remove_key(or_map: OrMap$, key: string): _.Result<
  undefined,
  string
>;

export function or_map_value(or_map: OrMap$, key: string): _.Result<
  $or_map_kernel.OrMapValue$,
  undefined
>;

export function or_map_entries(or_map: OrMap$): _.List<
  [string, $or_map_kernel.OrMapValue$]
>;

export function or_map_keys(or_map: OrMap$): _.List<string>;

export function subscribe_or_map(
  or_map: OrMap$,
  handler: (x0: $or_map_kernel.OrMapEvent$) => undefined
): SubscriptionToken$;

export function or_set_add(or_set: OrSet$, element: string): undefined;

export function or_set_remove(or_set: OrSet$, element: string): undefined;

export function or_set_contains(or_set: OrSet$, element: string): boolean;

export function or_set_values(or_set: OrSet$): _.List<string>;

export function subscribe_or_set(
  or_set: OrSet$,
  handler: (x0: $or_set_kernel.OrSetEvent$) => undefined
): SubscriptionToken$;

export function sequence_insert(
  sequence: SharedSequence$,
  index: number,
  value: $json.Json$
): _.Result<undefined, string>;

export function sequence_delete(sequence: SharedSequence$, index: number): _.Result<
  undefined,
  string
>;

export function sequence_move(
  sequence: SharedSequence$,
  from_index: number,
  to_index: number
): _.Result<undefined, string>;

export function sequence_replace(
  sequence: SharedSequence$,
  index: number,
  value: $json.Json$
): _.Result<undefined, string>;

export function sequence_values(sequence: SharedSequence$): _.List<$json.Json$>;

export function sequence_length(sequence: SharedSequence$): number;

export function subscribe_sequence(
  sequence: SharedSequence$,
  handler: (x0: $sequence_kernel.SequenceEvent$) => undefined
): SubscriptionToken$;

export function text_insert(text: SharedText$, index: number, value: string): _.Result<
  undefined,
  string
>;

export function text_delete_range(text: SharedText$, start: number, end: number): _.Result<
  undefined,
  string
>;

export function text_replace_range(
  text: SharedText$,
  start: number,
  end: number,
  value: string
): _.Result<undefined, string>;

export function text_append(text: SharedText$, value: string): _.Result<
  undefined,
  string
>;

export function text_value(text: SharedText$): string;

export function text_length(text: SharedText$): number;

export function text_substring(text: SharedText$, start: number, end: number): _.Result<
  string,
  string
>;

export function text_anchor_at(
  text: SharedText$,
  index: number,
  bias: $sequence.Bias$
): _.Result<$text_kernel.TextAnchor$, string>;

export function text_resolve_anchor(
  text: SharedText$,
  anchor: $text_kernel.TextAnchor$
): _.Result<number, string>;

export function text_start_anchor(): $text_kernel.TextAnchor$;

export function text_end_anchor(): $text_kernel.TextAnchor$;

export function text_anchor_to_json(anchor: $text_kernel.TextAnchor$): $json.Json$;

export function text_anchor_from_json(json_string: string): _.Result<
  $text_kernel.TextAnchor$,
  string
>;

export function subscribe_text(
  text: SharedText$,
  handler: (x0: $text_kernel.TextEvent$) => undefined
): SubscriptionToken$;

export function register_write(
  collection: RegisterCollection$,
  key: string,
  value: $json.Json$
): undefined;

export function register_read(
  collection: RegisterCollection$,
  key: string,
  policy: $register_collection_kernel.ReadPolicy$
): _.Result<$json.Json$, undefined>;

export function register_get(collection: RegisterCollection$, key: string): _.Result<
  $json.Json$,
  undefined
>;

export function register_versions(collection: RegisterCollection$, key: string): _.Result<
  _.List<$json.Json$>,
  undefined
>;

export function register_keys(collection: RegisterCollection$): _.List<string>;

export function subscribe_register_collection(
  collection: RegisterCollection$,
  handler: (x0: $register_collection_kernel.RegisterEvent$) => undefined
): SubscriptionToken$;

export function claim_once(claims: Claims$, key: string, value: $json.Json$): $runtime.ClaimSubmitReply$;

export function compare_and_set_claim(
  claims: Claims$,
  key: string,
  value: $json.Json$
): $runtime.ClaimSubmitReply$;

export function get_claim(claims: Claims$, key: string): _.Result<
  $json.Json$,
  undefined
>;

export function has_claim(claims: Claims$, key: string): boolean;

export function subscribe_claims(
  claims: Claims$,
  handler: (x0: $claims_kernel.ClaimEvent$) => undefined
): SubscriptionToken$;

export function volunteer_for_task(manager: TaskManager$, task_id: string): $task_manager_kernel.VolunteerOutcome$;

export function abandon_task(manager: TaskManager$, task_id: string): undefined;

export function complete_task(manager: TaskManager$, task_id: string): _.Result<
  undefined,
  string
>;

export function task_assigned(manager: TaskManager$, task_id: string): boolean;

export function task_queued(manager: TaskManager$, task_id: string): boolean;

export function task_queues(manager: TaskManager$): _.List<
  [string, _.List<number>]
>;

export function subscribe_task_manager(
  manager: TaskManager$,
  handler: (x0: $task_manager_kernel.TaskManagerEvent$) => undefined
): SubscriptionToken$;

export function pn_counter_update(pn_counter: PnCounter$, amount: number): undefined;

export function pn_counter_value(pn_counter: PnCounter$): _.Result<
  number,
  undefined
>;

export function subscribe_pn_counter(
  pn_counter: PnCounter$,
  handler: (x0: $pn_counter_kernel.PnCounterEvent$) => undefined
): SubscriptionToken$;

export function g_counter_increment(g_counter: GCounter$, amount: number): _.Result<
  undefined,
  string
>;

export function g_counter_value(g_counter: GCounter$): _.Result<
  number,
  undefined
>;

export function subscribe_g_counter(
  g_counter: GCounter$,
  handler: (x0: $g_counter_kernel.GCounterEvent$) => undefined
): SubscriptionToken$;

export function create_lww_map(document: Document$<any>): _.Result<
  LwwMap$,
  string
>;

export function lww_map_handle_of(map: LwwMap$): $json.Json$;

export function resolve_lww_map(document: Document$<any>, value: $json.Json$): _.Result<
  LwwMap$,
  string
>;

export function set_lww_map_field<BIBZ>(
  typed_map: TypedMap$<BIBZ>,
  field: $schema.ChannelField$<BIBZ, $schema.LwwMapChannel$>,
  map: LwwMap$
): undefined;

export function resolve_lww_map_field<BICF>(
  document: Document$<any>,
  typed_map: TypedMap$<BICF>,
  field: $schema.ChannelField$<BICF, $schema.LwwMapChannel$>
): _.Result<$option.Option$<LwwMap$>, string>;

export function ensure_lww_map<BICO>(
  document: Document$<any>,
  typed_map: TypedMap$<BICO>,
  field: $schema.ChannelField$<BICO, $schema.LwwMapChannel$>,
  done: (x0: _.Result<LwwMap$, string>) => undefined
): undefined;

export function lww_map_set(map: LwwMap$, key: string, value: string): _.Result<
  undefined,
  string
>;

export function lww_map_remove(map: LwwMap$, key: string): _.Result<
  undefined,
  string
>;

export function lww_map_get(map: LwwMap$, key: string): _.Result<
  string,
  undefined
>;

export function lww_map_entries(map: LwwMap$): _.List<[string, string]>;

export function lww_map_keys(map: LwwMap$): _.List<string>;

export function subscribe_lww_map(
  map: LwwMap$,
  handler: (x0: $lww_map_kernel.LwwMapEvent$) => undefined
): SubscriptionToken$;

export function lww_register_set(register: LwwRegister$, value: string): _.Result<
  undefined,
  string
>;

export function lww_register_value(register: LwwRegister$): _.Result<
  string,
  undefined
>;

export function subscribe_lww_register(
  register: LwwRegister$,
  handler: (x0: $lww_register_kernel.LwwRegisterEvent$) => undefined
): SubscriptionToken$;

export function pact_map_set(
  pact_map: PactMap$,
  key: string,
  value: $json.Json$
): undefined;

export function pact_map_delete(pact_map: PactMap$, key: string): undefined;

export function pact_map_get(pact_map: PactMap$, key: string): _.Result<
  $json.Json$,
  undefined
>;

export function pact_map_keys(pact_map: PactMap$): _.List<string>;

export function subscribe_pact_map(
  pact_map: PactMap$,
  handler: (x0: $pact_map_kernel.PactMapEvent$) => undefined
): SubscriptionToken$;

export function pact_map_is_pending(pact_map: PactMap$, key: string): boolean;

export function pact_map_pending(pact_map: PactMap$, key: string): _.Result<
  $pact_map_kernel.Pending$,
  undefined
>;

export function pact_map_pending_signoffs(pact_map: PactMap$, key: string): _.Result<
  _.List<number>,
  undefined
>;

export function pact_map_get_with_details(pact_map: PactMap$, key: string): _.Result<
  $pact_map_kernel.Accepted$,
  undefined
>;

export function ordered_add(collection: OrderedCollection$, value: $json.Json$): undefined;

export function ordered_acquire(collection: OrderedCollection$): string;

export function ordered_acquire_with_outcome(
  collection: OrderedCollection$,
  on_outcome: (x0: $ordered_collection_kernel.AcquireOutcome$) => undefined
): string;

export function ordered_complete(
  collection: OrderedCollection$,
  acquire_id: string
): undefined;

export function ordered_release(
  collection: OrderedCollection$,
  acquire_id: string
): undefined;

export function ordered_size(collection: OrderedCollection$): _.Result<
  number,
  undefined
>;

export function ordered_queue(collection: OrderedCollection$): _.List<
  $json.Json$
>;

export function ordered_jobs(collection: OrderedCollection$): _.List<
  [string, $ordered_collection_kernel.JobEntry$]
>;

export function subscribe_ordered_collection(
  collection: OrderedCollection$,
  handler: (x0: $ordered_collection_kernel.OrderedEvent$) => undefined
): SubscriptionToken$;

export function submit_json_ot(
  json_ot: JsonOt$,
  operation: _.List<$json_ot.Component$>
): undefined;

export function json_ot_view(json_ot: JsonOt$): _.Result<
  $json_ot.JsonValue$,
  undefined
>;

export function subscribe_json_ot(
  json_ot: JsonOt$,
  handler: (x0: $json_ot_kernel.JsonOtEvent$) => undefined
): SubscriptionToken$;

export function submit_rich_text(
  rich_text: SharedRichText$,
  delta: $rich_text.Delta$
): undefined;

export function rich_text_view(rich_text: SharedRichText$): _.Result<
  $rich_text.Document$,
  undefined
>;

export function subscribe_rich_text(
  rich_text: SharedRichText$,
  handler: (x0: $rich_text_kernel.RichTextEvent$) => undefined
): SubscriptionToken$;

export function g_set_add(set: GSet$, element: string): undefined;

export function g_set_contains(set: GSet$, element: string): boolean;

export function g_set_values(set: GSet$): _.List<string>;

export function subscribe_g_set(
  set: GSet$,
  handler: (x0: $g_set_kernel.GSetEvent$) => undefined
): SubscriptionToken$;

export function two_p_set_add(set: TwoPSet$, element: string): undefined;

export function two_p_set_remove(set: TwoPSet$, element: string): undefined;

export function two_p_set_contains(set: TwoPSet$, element: string): boolean;

export function two_p_set_values(set: TwoPSet$): _.List<string>;

export function subscribe_two_p_set(
  set: TwoPSet$,
  handler: (x0: $two_p_set_kernel.TwoPSetEvent$) => undefined
): SubscriptionToken$;

export function directory_set(
  directory: SharedDirectory$,
  path: string,
  key: string,
  value: $json.Json$
): undefined;

export function directory_delete(
  directory: SharedDirectory$,
  path: string,
  key: string
): undefined;

export function directory_clear(directory: SharedDirectory$, path: string): undefined;

export function directory_create_subdirectory(
  directory: SharedDirectory$,
  path: string,
  name: string
): undefined;

export function directory_delete_subdirectory(
  directory: SharedDirectory$,
  path: string,
  name: string
): undefined;

export function directory_get(
  directory: SharedDirectory$,
  path: string,
  key: string
): _.Result<$json.Json$, undefined>;

export function directory_entries(directory: SharedDirectory$, path: string): _.List<
  [string, $json.Json$]
>;

export function directory_subdirectories(
  directory: SharedDirectory$,
  path: string
): _.List<string>;

export function directory_has_subdirectory(
  directory: SharedDirectory$,
  path: string,
  name: string
): boolean;

export function subscribe_directory(
  directory: SharedDirectory$,
  handler: (x0: $directory_kernel.DirectoryEvent$) => undefined
): SubscriptionToken$;

export function close(document: Document$<any>): undefined;

export function force_reconnect(document: Document$<any>): undefined;

export function go_offline(document: Document$<any>): undefined;

export function go_online(document: Document$<any>): undefined;

export function client_id(document: Document$<any>): $option.Option$<string>;

export function submit_ripple(
  document: Document$<any>,
  ripple_type: string,
  content: $json.Json$
): undefined;

export function subscribe_ripples(
  document: Document$<any>,
  handler: (x0: Ripple$) => undefined
): undefined;

export function ripple_type(ripple: Ripple$): $option.Option$<string>;

export function ripple_content(ripple: Ripple$): $json.Json$;

export function ripple_client_id(ripple: Ripple$): $option.Option$<string>;

export function diagnostics(document: Document$<any>): $runtime.Diagnostics$;

export function summarize(document: Document$<any>): $promise.Promise$<
  _.Result<string, string>
>;

export function auto_summarize(
  document: Document$<any>,
  policy: $summary_policy.Policy$
): undefined;

export function stop_auto_summarize(document: Document$<any>): undefined;

export function operations_since_summary(document: Document$<any>): number;

export function get_versions(document: Document$<any>, count: number): $promise.Promise$<
  _.Result<_.List<$git_storage.SummaryVersion$>, string>
>;

export function load_version(document: Document$<any>, handle: string): $promise.Promise$<
  _.Result<$summary_blob.SummaryBlob$, string>
>;

export function clear(map: SharedMap$): undefined;

export function keys(map: SharedMap$): _.List<string>;

export function size(map: SharedMap$): number;

export function subscribe(
  map: SharedMap$,
  handler: (x0: $map_kernel.MapEvent$) => undefined
): SubscriptionToken$;

export function subscribe_typed(
  typed_map: TypedMap$<any>,
  handler: (x0: $map_kernel.MapEvent$) => undefined
): SubscriptionToken$;

export function subscribe_field<BIIT, BIIV>(
  typed_map: TypedMap$<BIIT>,
  field: $schema.Field$<BIIT, BIIV>,
  handler: (x0: $schema.FieldChange$<BIIV>) => undefined
): SubscriptionToken$;

export function dev_token(
  secret: string,
  tenant: string,
  document: string,
  user_id: string
): $promise.Promise$<string>;

export function create_mv_register(document: Document$<any>): _.Result<
  MvRegister$,
  string
>;

export function mv_register_handle_of(mv_register: MvRegister$): $json.Json$;

export function mv_register_values(mv_register: MvRegister$): _.Result<
  _.List<string>,
  undefined
>;

export function resolve_mv_register(
  document: Document$<any>,
  value: $json.Json$
): _.Result<MvRegister$, string>;

export function set_mv_register_field<BIJI>(
  typed_map: TypedMap$<BIJI>,
  field: $schema.ChannelField$<BIJI, $schema.MvRegisterChannel$>,
  mv_register: MvRegister$
): undefined;

export function resolve_mv_register_field<BIJO>(
  document: Document$<any>,
  typed_map: TypedMap$<BIJO>,
  field: $schema.ChannelField$<BIJO, $schema.MvRegisterChannel$>
): _.Result<$option.Option$<MvRegister$>, string>;

export function ensure_mv_register<BIJX>(
  document: Document$<any>,
  typed_map: TypedMap$<BIJX>,
  field: $schema.ChannelField$<BIJX, $schema.MvRegisterChannel$>,
  done: (x0: _.Result<MvRegister$, string>) => undefined
): undefined;

export function mv_register_set(mv_register: MvRegister$, value: string): undefined;

export function subscribe_mv_register(
  mv_register: MvRegister$,
  handler: (x0: $mv_register_kernel.MvRegisterEvent$) => undefined
): SubscriptionToken$;
