import type * as $json from "../gleam_json/gleam/json.d.mts";
import type * as $effect from "../lustre/lustre/effect.d.mts";
import type * as $watershed from "../watershed/watershed.d.mts";
import type * as $claims_kernel from "../watershed/watershed/claims_kernel.d.mts";
import type * as $counter_kernel from "../watershed/watershed/counter_kernel.d.mts";
import type * as $directory_kernel from "../watershed/watershed/directory_kernel.d.mts";
import type * as $g_counter_kernel from "../watershed/watershed/g_counter_kernel.d.mts";
import type * as $g_set_kernel from "../watershed/watershed/g_set_kernel.d.mts";
import type * as $json_ot_kernel from "../watershed/watershed/json_ot_kernel.d.mts";
import type * as $lww_map_kernel from "../watershed/watershed/lww_map_kernel.d.mts";
import type * as $lww_register_kernel from "../watershed/watershed/lww_register_kernel.d.mts";
import type * as $map_kernel from "../watershed/watershed/map_kernel.d.mts";
import type * as $mv_register_kernel from "../watershed/watershed/mv_register_kernel.d.mts";
import type * as $or_map_kernel from "../watershed/watershed/or_map_kernel.d.mts";
import type * as $or_set_kernel from "../watershed/watershed/or_set_kernel.d.mts";
import type * as $ordered_collection_kernel from "../watershed/watershed/ordered_collection_kernel.d.mts";
import type * as $pact_map_kernel from "../watershed/watershed/pact_map_kernel.d.mts";
import type * as $pn_counter_kernel from "../watershed/watershed/pn_counter_kernel.d.mts";
import type * as $presence from "../watershed/watershed/presence.d.mts";
import type * as $presence_js from "../watershed/watershed/presence_js.d.mts";
import type * as $register_collection_kernel from "../watershed/watershed/register_collection_kernel.d.mts";
import type * as $rich_text_kernel from "../watershed/watershed/rich_text_kernel.d.mts";
import type * as $runtime from "../watershed/watershed/runtime.d.mts";
import type * as $schema from "../watershed/watershed/schema.d.mts";
import type * as $sequence_kernel from "../watershed/watershed/sequence_kernel.d.mts";
import type * as $summary_policy from "../watershed/watershed/summary_policy.d.mts";
import type * as $task_manager_kernel from "../watershed/watershed/task_manager_kernel.d.mts";
import type * as $text_kernel from "../watershed/watershed/text_kernel.d.mts";
import type * as $two_p_set_kernel from "../watershed/watershed/two_p_set_kernel.d.mts";
import type * as _ from "./gleam.d.mts";

export function connect<CBJQ>(
  config: $watershed.WatershedConfig$,
  got_document: (x0: $watershed.Document$<any>) => CBJQ,
  connected: (x0: _.Result<undefined, string>) => CBJQ
): $effect.Effect$<CBJQ>;

export function connect_dev<CBJW>(
  url: string,
  tenant: string,
  secret: string,
  document_id: string,
  user_id: string,
  got_document: (x0: $watershed.Document$<any>) => CBJW,
  connected: (x0: _.Result<undefined, string>) => CBJW
): $effect.Effect$<CBJW>;

export function subscribe<CBKA>(
  map: $watershed.SharedMap$,
  to_msg: (x0: $map_kernel.MapEvent$) => CBKA
): $effect.Effect$<CBKA>;

export function subscribe_directory<CBKC>(
  directory: $watershed.SharedDirectory$,
  to_msg: (x0: $directory_kernel.DirectoryEvent$) => CBKC
): $effect.Effect$<CBKC>;

export function subscribe_counter<CBKE>(
  counter: $watershed.SharedCounter$,
  to_msg: (x0: $counter_kernel.CounterEvent$) => CBKE
): $effect.Effect$<CBKE>;

export function subscribe_or_map<CBKG>(
  or_map: $watershed.OrMap$,
  to_msg: (x0: $or_map_kernel.OrMapEvent$) => CBKG
): $effect.Effect$<CBKG>;

export function or_map_set_mv_register(
  or_map: $watershed.OrMap$,
  key: string,
  value: string
): $effect.Effect$<any>;

export function subscribe_or_set<CBKK>(
  or_set: $watershed.OrSet$,
  to_msg: (x0: $or_set_kernel.OrSetEvent$) => CBKK
): $effect.Effect$<CBKK>;

export function subscribe_g_set<CBKM>(
  g_set: $watershed.GSet$,
  to_msg: (x0: $g_set_kernel.GSetEvent$) => CBKM
): $effect.Effect$<CBKM>;

export function subscribe_two_p_set<CBKO>(
  two_p_set: $watershed.TwoPSet$,
  to_msg: (x0: $two_p_set_kernel.TwoPSetEvent$) => CBKO
): $effect.Effect$<CBKO>;

export function subscribe_lww_map<CBKQ>(
  map: $watershed.LwwMap$,
  to_msg: (x0: $lww_map_kernel.LwwMapEvent$) => CBKQ
): $effect.Effect$<CBKQ>;

export function subscribe_lww_register<CBKS>(
  register: $watershed.LwwRegister$,
  to_msg: (x0: $lww_register_kernel.LwwRegisterEvent$) => CBKS
): $effect.Effect$<CBKS>;

export function subscribe_mv_register<CBKU>(
  register: $watershed.MvRegister$,
  to_msg: (x0: $mv_register_kernel.MvRegisterEvent$) => CBKU
): $effect.Effect$<CBKU>;

export function subscribe_pn_counter<CBKW>(
  pn_counter: $watershed.PnCounter$,
  to_msg: (x0: $pn_counter_kernel.PnCounterEvent$) => CBKW
): $effect.Effect$<CBKW>;

export function subscribe_g_counter<CBKY>(
  g_counter: $watershed.GCounter$,
  to_msg: (x0: $g_counter_kernel.GCounterEvent$) => CBKY
): $effect.Effect$<CBKY>;

export function subscribe_pact_map<CBLA>(
  pact_map: $watershed.PactMap$,
  to_msg: (x0: $pact_map_kernel.PactMapEvent$) => CBLA
): $effect.Effect$<CBLA>;

export function subscribe_ordered_collection<CBLC>(
  collection: $watershed.OrderedCollection$,
  to_msg: (x0: $ordered_collection_kernel.OrderedEvent$) => CBLC
): $effect.Effect$<CBLC>;

export function ordered_acquire<CBLE>(
  collection: $watershed.OrderedCollection$,
  to_msg: (x0: $ordered_collection_kernel.AcquireOutcome$) => CBLE
): $effect.Effect$<CBLE>;

export function subscribe_register_collection<CBLG>(
  collection: $watershed.RegisterCollection$,
  to_msg: (x0: $register_collection_kernel.RegisterEvent$) => CBLG
): $effect.Effect$<CBLG>;

export function subscribe_claims<CBLI>(
  claims: $watershed.Claims$,
  to_msg: (x0: $claims_kernel.ClaimEvent$) => CBLI
): $effect.Effect$<CBLI>;

export function claim_once<CBLK>(
  claims: $watershed.Claims$,
  key: string,
  value: $json.Json$,
  to_msg: (x0: $claims_kernel.ClaimOutcome$) => CBLK
): $effect.Effect$<CBLK>;

export function compare_and_set_claim<CBLM>(
  claims: $watershed.Claims$,
  key: string,
  value: $json.Json$,
  to_msg: (x0: $claims_kernel.ClaimOutcome$) => CBLM
): $effect.Effect$<CBLM>;

export function subscribe_task_manager<CBLO>(
  manager: $watershed.TaskManager$,
  to_msg: (x0: $task_manager_kernel.TaskManagerEvent$) => CBLO
): $effect.Effect$<CBLO>;

export function subscribe_sequence<CBLQ>(
  sequence: $watershed.SharedSequence$,
  to_msg: (x0: $sequence_kernel.SequenceEvent$) => CBLQ
): $effect.Effect$<CBLQ>;

export function subscribe_text<CBLS>(
  text: $watershed.SharedText$,
  to_msg: (x0: $text_kernel.TextEvent$) => CBLS
): $effect.Effect$<CBLS>;

export function subscribe_text_cancellable<CBLU>(
  text: $watershed.SharedText$,
  to_msg: (x0: $text_kernel.TextEvent$) => CBLU,
  subscribed: (x0: $watershed.SubscriptionToken$) => CBLU
): $effect.Effect$<CBLU>;

export function subscribe_rich_text<CBLW>(
  rich_text: $watershed.SharedRichText$,
  to_msg: (x0: $rich_text_kernel.RichTextEvent$) => CBLW
): $effect.Effect$<CBLW>;

export function subscribe_json_ot<CBLY>(
  json_ot: $watershed.JsonOt$,
  to_msg: (x0: $json_ot_kernel.JsonOtEvent$) => CBLY
): $effect.Effect$<CBLY>;

export function subscribe_ripples<CBMC>(
  document: $watershed.Document$<any>,
  to_msg: (x0: $watershed.Ripple$) => CBMC
): $effect.Effect$<CBMC>;

export function subscribe_field<CBME, CBMG, CBMK>(
  typed_map: $watershed.TypedMap$<CBME>,
  field: $schema.Field$<CBME, CBMG>,
  to_msg: (x0: $schema.FieldChange$<CBMG>) => CBMK
): $effect.Effect$<CBMK>;

export function subscribe_typed<CBMO>(
  typed_map: $watershed.TypedMap$<any>,
  to_msg: (x0: $map_kernel.MapEvent$) => CBMO
): $effect.Effect$<CBMO>;

export function ensure_map<CBMS, CBMY>(
  document: $watershed.Document$<any>,
  typed_map: $watershed.TypedMap$<CBMS>,
  field: $schema.ChannelField$<CBMS, $schema.MapChannel$>,
  to_msg: (x0: _.Result<$watershed.SharedMap$, string>) => CBMY
): $effect.Effect$<CBMY>;

export function ensure_directory<CBNC, CBNI>(
  document: $watershed.Document$<any>,
  typed_map: $watershed.TypedMap$<CBNC>,
  field: $schema.ChannelField$<CBNC, $schema.DirectoryChannel$>,
  to_msg: (x0: _.Result<$watershed.SharedDirectory$, string>) => CBNI
): $effect.Effect$<CBNI>;

export function ensure_counter<CBNM, CBNS>(
  document: $watershed.Document$<any>,
  typed_map: $watershed.TypedMap$<CBNM>,
  field: $schema.ChannelField$<CBNM, $schema.CounterChannel$>,
  to_msg: (x0: _.Result<$watershed.SharedCounter$, string>) => CBNS
): $effect.Effect$<CBNS>;

export function ensure_or_map<CBNW, CBOC>(
  document: $watershed.Document$<any>,
  typed_map: $watershed.TypedMap$<CBNW>,
  field: $schema.ChannelField$<CBNW, $schema.OrMapChannel$>,
  mode: $or_map_kernel.OrMapMode$,
  to_msg: (x0: _.Result<$watershed.OrMap$, string>) => CBOC
): $effect.Effect$<CBOC>;

export function ensure_or_set<CBOG, CBOM>(
  document: $watershed.Document$<any>,
  typed_map: $watershed.TypedMap$<CBOG>,
  field: $schema.ChannelField$<CBOG, $schema.OrSetChannel$>,
  to_msg: (x0: _.Result<$watershed.OrSet$, string>) => CBOM
): $effect.Effect$<CBOM>;

export function ensure_g_set<CBOQ, CBOW>(
  document: $watershed.Document$<any>,
  typed_map: $watershed.TypedMap$<CBOQ>,
  field: $schema.ChannelField$<CBOQ, $schema.GSetChannel$>,
  to_msg: (x0: _.Result<$watershed.GSet$, string>) => CBOW
): $effect.Effect$<CBOW>;

export function ensure_two_p_set<CBPA, CBPG>(
  document: $watershed.Document$<any>,
  typed_map: $watershed.TypedMap$<CBPA>,
  field: $schema.ChannelField$<CBPA, $schema.TwoPSetChannel$>,
  to_msg: (x0: _.Result<$watershed.TwoPSet$, string>) => CBPG
): $effect.Effect$<CBPG>;

export function ensure_register_collection<CBPK, CBPQ>(
  document: $watershed.Document$<any>,
  typed_map: $watershed.TypedMap$<CBPK>,
  field: $schema.ChannelField$<CBPK, $schema.RegisterCollectionChannel$>,
  to_msg: (x0: _.Result<$watershed.RegisterCollection$, string>) => CBPQ
): $effect.Effect$<CBPQ>;

export function ensure_claims<CBPU, CBQA>(
  document: $watershed.Document$<any>,
  typed_map: $watershed.TypedMap$<CBPU>,
  field: $schema.ChannelField$<CBPU, $schema.ClaimsChannel$>,
  to_msg: (x0: _.Result<$watershed.Claims$, string>) => CBQA
): $effect.Effect$<CBQA>;

export function ensure_task_manager<CBQE, CBQK>(
  document: $watershed.Document$<any>,
  typed_map: $watershed.TypedMap$<CBQE>,
  field: $schema.ChannelField$<CBQE, $schema.TaskManagerChannel$>,
  to_msg: (x0: _.Result<$watershed.TaskManager$, string>) => CBQK
): $effect.Effect$<CBQK>;

export function ensure_pn_counter<CBQO, CBQU>(
  document: $watershed.Document$<any>,
  typed_map: $watershed.TypedMap$<CBQO>,
  field: $schema.ChannelField$<CBQO, $schema.PnCounterChannel$>,
  to_msg: (x0: _.Result<$watershed.PnCounter$, string>) => CBQU
): $effect.Effect$<CBQU>;

export function ensure_g_counter<CBQY, CBRE>(
  document: $watershed.Document$<any>,
  typed_map: $watershed.TypedMap$<CBQY>,
  field: $schema.ChannelField$<CBQY, $schema.GCounterChannel$>,
  to_msg: (x0: _.Result<$watershed.GCounter$, string>) => CBRE
): $effect.Effect$<CBRE>;

export function ensure_lww_map<CBRI, CBRO>(
  document: $watershed.Document$<any>,
  typed_map: $watershed.TypedMap$<CBRI>,
  field: $schema.ChannelField$<CBRI, $schema.LwwMapChannel$>,
  to_msg: (x0: _.Result<$watershed.LwwMap$, string>) => CBRO
): $effect.Effect$<CBRO>;

export function ensure_lww_register<CBRS, CBRY>(
  document: $watershed.Document$<any>,
  typed_map: $watershed.TypedMap$<CBRS>,
  field: $schema.ChannelField$<CBRS, $schema.LwwRegisterChannel$>,
  to_msg: (x0: _.Result<$watershed.LwwRegister$, string>) => CBRY
): $effect.Effect$<CBRY>;

export function ensure_mv_register<CBSC, CBSI>(
  document: $watershed.Document$<any>,
  typed_map: $watershed.TypedMap$<CBSC>,
  field: $schema.ChannelField$<CBSC, $schema.MvRegisterChannel$>,
  to_msg: (x0: _.Result<$watershed.MvRegister$, string>) => CBSI
): $effect.Effect$<CBSI>;

export function ensure_pact_map<CBSM, CBSS>(
  document: $watershed.Document$<any>,
  typed_map: $watershed.TypedMap$<CBSM>,
  field: $schema.ChannelField$<CBSM, $schema.PactMapChannel$>,
  to_msg: (x0: _.Result<$watershed.PactMap$, string>) => CBSS
): $effect.Effect$<CBSS>;

export function ensure_ordered_collection<CBSW, CBTC>(
  document: $watershed.Document$<any>,
  typed_map: $watershed.TypedMap$<CBSW>,
  field: $schema.ChannelField$<CBSW, $schema.OrderedCollectionChannel$>,
  to_msg: (x0: _.Result<$watershed.OrderedCollection$, string>) => CBTC
): $effect.Effect$<CBTC>;

export function ensure_sequence<CBTG, CBTM>(
  document: $watershed.Document$<any>,
  typed_map: $watershed.TypedMap$<CBTG>,
  field: $schema.ChannelField$<CBTG, $schema.SequenceChannel$>,
  to_msg: (x0: _.Result<$watershed.SharedSequence$, string>) => CBTM
): $effect.Effect$<CBTM>;

export function ensure_text<CBTQ, CBTW>(
  document: $watershed.Document$<any>,
  typed_map: $watershed.TypedMap$<CBTQ>,
  field: $schema.ChannelField$<CBTQ, $schema.TextChannel$>,
  to_msg: (x0: _.Result<$watershed.SharedText$, string>) => CBTW
): $effect.Effect$<CBTW>;

export function ensure_rich_text<CBUA, CBUG>(
  document: $watershed.Document$<any>,
  typed_map: $watershed.TypedMap$<CBUA>,
  field: $schema.ChannelField$<CBUA, $schema.RichTextChannel$>,
  to_msg: (x0: _.Result<$watershed.SharedRichText$, string>) => CBUG
): $effect.Effect$<CBUG>;

export function ensure_json_ot<CBUK, CBUQ>(
  document: $watershed.Document$<any>,
  typed_map: $watershed.TypedMap$<CBUK>,
  field: $schema.ChannelField$<CBUK, $schema.JsonOtChannel$>,
  to_msg: (x0: _.Result<$watershed.JsonOt$, string>) => CBUQ
): $effect.Effect$<CBUQ>;

export function ensure_child<CBUU, CBUW, CBVC>(
  document: $watershed.Document$<any>,
  typed_map: $watershed.TypedMap$<CBUU>,
  field: $schema.ChildField$<CBUU, CBUW>,
  to_msg: (x0: _.Result<$watershed.TypedMap$<CBUW>, string>) => CBVC
): $effect.Effect$<CBVC>;

export function ensure_field<CBVE, CBVG>(
  typed_map: $watershed.TypedMap$<CBVE>,
  field: $schema.Field$<CBVE, CBVG>,
  default$: CBVG
): $effect.Effect$<any>;

export function after<CBVL>(milliseconds: number, msg: CBVL): $effect.Effect$<
  CBVL
>;

export function submit_ripple(
  document: $watershed.Document$<any>,
  ripple_type: string,
  content: $json.Json$
): $effect.Effect$<any>;

export function force_reconnect(document: $watershed.Document$<any>): $effect.Effect$<
  any
>;

export function go_offline(document: $watershed.Document$<any>): $effect.Effect$<
  any
>;

export function go_online(document: $watershed.Document$<any>): $effect.Effect$<
  any
>;

export function presence<CBWF, CBWI>(
  document: $watershed.Document$<any>,
  config: $presence.Config$<CBWF>,
  initial: CBWF,
  started: (x0: $presence_js.Handle$<CBWF>) => CBWI,
  on_event: (x0: $presence.Event$<CBWF>) => CBWI
): $effect.Effect$<CBWI>;

export function update_presence<CBWL>(
  handle: $presence_js.Handle$<CBWL>,
  metadata: CBWL
): $effect.Effect$<any>;

export function stop_presence(handle: $presence_js.Handle$<any>): $effect.Effect$<
  any
>;

export function auto_summarize(
  document: $watershed.Document$<any>,
  policy: $summary_policy.Policy$
): $effect.Effect$<any>;

export function stop_auto_summarize(document: $watershed.Document$<any>): $effect.Effect$<
  any
>;
