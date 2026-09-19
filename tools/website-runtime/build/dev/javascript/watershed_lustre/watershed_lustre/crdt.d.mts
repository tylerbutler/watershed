import type * as $json from "../../gleam_json/gleam/json.d.mts";
import type * as $effect from "../../lustre/lustre/effect.d.mts";
import type * as $crdt_js from "../../watershed/watershed/crdt_js.d.mts";
import type * as $g_counter_kernel from "../../watershed/watershed/g_counter_kernel.d.mts";
import type * as $g_set_kernel from "../../watershed/watershed/g_set_kernel.d.mts";
import type * as $lww_map_kernel from "../../watershed/watershed/lww_map_kernel.d.mts";
import type * as $lww_register_kernel from "../../watershed/watershed/lww_register_kernel.d.mts";
import type * as $mv_register_kernel from "../../watershed/watershed/mv_register_kernel.d.mts";
import type * as $or_map_kernel from "../../watershed/watershed/or_map_kernel.d.mts";
import type * as $or_set_kernel from "../../watershed/watershed/or_set_kernel.d.mts";
import type * as $p2p from "../../watershed/watershed/p2p.d.mts";
import type * as $p2p_transport_js from "../../watershed/watershed/p2p_transport_js.d.mts";
import type * as $persist_controller_js from "../../watershed/watershed/persist_controller_js.d.mts";
import type * as $persist_js from "../../watershed/watershed/persist_js.d.mts";
import type * as $pn_counter_kernel from "../../watershed/watershed/pn_counter_kernel.d.mts";
import type * as $schema from "../../watershed/watershed/schema.d.mts";
import type * as $sequence_kernel from "../../watershed/watershed/sequence_kernel.d.mts";
import type * as $text_kernel from "../../watershed/watershed/text_kernel.d.mts";
import type * as $two_p_set_kernel from "../../watershed/watershed/two_p_set_kernel.d.mts";
import type * as _ from "../gleam.d.mts";

export class NoLocalSnapshot extends _.CustomType {}
export function PersistenceStatus$NoLocalSnapshot(): PersistenceStatus$;
export function PersistenceStatus$isNoLocalSnapshot(
  value: any,
): value is PersistenceStatus$;

export class LocalSnapshotReady extends _.CustomType {}
export function PersistenceStatus$LocalSnapshotReady(): PersistenceStatus$;
export function PersistenceStatus$isLocalSnapshotReady(
  value: any,
): value is PersistenceStatus$;

export class PersistenceFailed extends _.CustomType {
  /** @deprecated */
  constructor(error: $persist_js.PersistenceError$);
  /** @deprecated */
  error: $persist_js.PersistenceError$;
}
export function PersistenceStatus$PersistenceFailed(
  error: $persist_js.PersistenceError$,
): PersistenceStatus$;
export function PersistenceStatus$isPersistenceFailed(
  value: any,
): value is PersistenceStatus$;
export function PersistenceStatus$PersistenceFailed$0(value: PersistenceStatus$): $persist_js.PersistenceError$;
export function PersistenceStatus$PersistenceFailed$error(
  value: PersistenceStatus$,
): $persist_js.PersistenceError$;

export type PersistenceStatus$ = NoLocalSnapshot | LocalSnapshotReady | PersistenceFailed;

export function open<CCJM, CCJO>(
  storage: $persist_js.Storage$,
  config: $crdt_js.Config$<CCJM>,
  connection: (x0: $crdt_js.CrdtConnection$) => CCJO,
  ready: (x0: _.Result<$crdt_js.CrdtDocument$<CCJM>, $p2p.P2pError$>) => CCJO,
  status: (x0: $crdt_js.Status$) => CCJO,
  persistence: (x0: PersistenceStatus$) => CCJO
): $effect.Effect$<CCJO>;

export function connect<CCJT, CCJV>(
  config: $crdt_js.Config$<CCJT>,
  connection: (x0: $crdt_js.CrdtConnection$) => CCJV,
  ready: (x0: _.Result<$crdt_js.CrdtDocument$<CCJT>, $p2p.P2pError$>) => CCJV,
  status: (x0: $crdt_js.Status$) => CCJV
): $effect.Effect$<CCJV>;

export function attach<CCKA, CCKC>(
  document: $crdt_js.CrdtDocument$<CCKA>,
  connection: (x0: $crdt_js.CrdtConnection$) => CCKC,
  ready: (x0: _.Result<$crdt_js.CrdtDocument$<CCKA>, $p2p.P2pError$>) => CCKC,
  status: (x0: $crdt_js.Status$) => CCKC
): $effect.Effect$<CCKC>;

export function attach_with_rtc<CCKH, CCKJ>(
  document: $crdt_js.CrdtDocument$<CCKH>,
  connection: (x0: $crdt_js.CrdtConnection$) => CCKJ,
  ready: (x0: _.Result<$crdt_js.CrdtDocument$<CCKH>, $p2p.P2pError$>) => CCKJ,
  status: (x0: $crdt_js.Status$) => CCKJ,
  rtc: $p2p_transport_js.Rtc$
): $effect.Effect$<CCKJ>;

export function close(connection: $crdt_js.CrdtConnection$): $effect.Effect$<
  any
>;

export function start_persistence<CCKZ, CCLC>(
  storage: $persist_js.Storage$,
  document: $crdt_js.CrdtDocument$<CCKZ>,
  started: (x0: $persist_controller_js.Controller$<CCKZ>) => CCLC,
  status: (x0: $persist_controller_js.Status$) => CCLC
): $effect.Effect$<CCLC>;

export function persistence_changed(
  controller: $persist_controller_js.Controller$<any>
): $effect.Effect$<any>;

export function stop_persistence(
  controller: $persist_controller_js.Controller$<any>
): $effect.Effect$<any>;

export function subscribe_pn_counter<CCLQ>(
  handle: $crdt_js.Handle$<$schema.PnCounterChannel$>,
  subscribed: (x0: $crdt_js.Subscription$) => CCLQ,
  event: (x0: $pn_counter_kernel.PnCounterEvent$) => CCLQ
): $effect.Effect$<CCLQ>;

export function subscribe_g_counter<CCLT>(
  handle: $crdt_js.Handle$<$schema.GCounterChannel$>,
  subscribed: (x0: $crdt_js.Subscription$) => CCLT,
  event: (x0: $g_counter_kernel.GCounterEvent$) => CCLT
): $effect.Effect$<CCLT>;

export function subscribe_lww_map<CCLW>(
  handle: $crdt_js.Handle$<$schema.LwwMapChannel$>,
  subscribed: (x0: $crdt_js.Subscription$) => CCLW,
  event: (x0: $lww_map_kernel.LwwMapEvent$) => CCLW
): $effect.Effect$<CCLW>;

export function subscribe_lww_register<CCLZ>(
  handle: $crdt_js.Handle$<$schema.LwwRegisterChannel$>,
  subscribed: (x0: $crdt_js.Subscription$) => CCLZ,
  event: (x0: $lww_register_kernel.LwwRegisterEvent$) => CCLZ
): $effect.Effect$<CCLZ>;

export function subscribe_mv_register<CCMC>(
  handle: $crdt_js.Handle$<$schema.MvRegisterChannel$>,
  subscribed: (x0: $crdt_js.Subscription$) => CCMC,
  event: (x0: $mv_register_kernel.MvRegisterEvent$) => CCMC
): $effect.Effect$<CCMC>;

export function subscribe_or_map<CCMF>(
  handle: $crdt_js.Handle$<$schema.OrMapChannel$>,
  subscribed: (x0: $crdt_js.Subscription$) => CCMF,
  event: (x0: $or_map_kernel.OrMapEvent$) => CCMF
): $effect.Effect$<CCMF>;

export function subscribe_or_set<CCMI>(
  handle: $crdt_js.Handle$<$schema.OrSetChannel$>,
  subscribed: (x0: $crdt_js.Subscription$) => CCMI,
  event: (x0: $or_set_kernel.OrSetEvent$) => CCMI
): $effect.Effect$<CCMI>;

export function subscribe_g_set<CCML>(
  handle: $crdt_js.Handle$<$schema.GSetChannel$>,
  subscribed: (x0: $crdt_js.Subscription$) => CCML,
  event: (x0: $g_set_kernel.GSetEvent$) => CCML
): $effect.Effect$<CCML>;

export function subscribe_two_p_set<CCMO>(
  handle: $crdt_js.Handle$<$schema.TwoPSetChannel$>,
  subscribed: (x0: $crdt_js.Subscription$) => CCMO,
  event: (x0: $two_p_set_kernel.TwoPSetEvent$) => CCMO
): $effect.Effect$<CCMO>;

export function subscribe_sequence<CCMR>(
  handle: $crdt_js.Handle$<$schema.SequenceChannel$>,
  subscribed: (x0: $crdt_js.Subscription$) => CCMR,
  event: (x0: $sequence_kernel.SequenceEvent$) => CCMR
): $effect.Effect$<CCMR>;

export function subscribe_text<CCMU>(
  handle: $crdt_js.Handle$<$schema.TextChannel$>,
  subscribed: (x0: $crdt_js.Subscription$) => CCMU,
  event: (x0: $text_kernel.TextEvent$) => CCMU
): $effect.Effect$<CCMU>;

export function unsubscribe(subscription: $crdt_js.Subscription$): $effect.Effect$<
  any
>;

export function perform<CCMY, CCMZ>(
  operation: () => CCMY,
  outcome: (x0: CCMY) => CCMZ
): $effect.Effect$<CCMZ>;

export function or_map_set_mv_register<CCNE>(
  handle: $crdt_js.Handle$<$schema.OrMapChannel$>,
  key: string,
  value: string,
  outcome: (x0: _.Result<undefined, $p2p.P2pError$>) => CCNE
): $effect.Effect$<CCNE>;

export function export_snapshot<CCNK>(
  document: $crdt_js.CrdtDocument$<any>,
  exported: (x0: _.Result<$json.Json$, $p2p.P2pError$>) => CCNK
): $effect.Effect$<CCNK>;

export function import_snapshot<CCNM, CCNR>(
  config: $crdt_js.Config$<CCNM>,
  snapshot: $json.Json$,
  imported: (x0: _.Result<$crdt_js.CrdtDocument$<CCNM>, $p2p.P2pError$>) => CCNR
): $effect.Effect$<CCNR>;
