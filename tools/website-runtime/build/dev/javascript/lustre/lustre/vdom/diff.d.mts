import type * as $json from "../../../gleam_json/gleam/json.d.mts";
import type * as _ from "../../gleam.d.mts";
import type * as $mutable_map from "../../lustre/internals/mutable_map.d.mts";
import type * as $cache from "../../lustre/vdom/cache.d.mts";
import type * as $patch from "../../lustre/vdom/patch.d.mts";
import type * as $path from "../../lustre/vdom/path.d.mts";
import type * as $vattr from "../../lustre/vdom/vattr.d.mts";
import type * as $vnode from "../../lustre/vdom/vnode.d.mts";

export class Diff<ABYJ> extends _.CustomType {
  /** @deprecated */
  constructor(patch: $patch.Patch$<ABYJ>, cache: $cache.Cache$<ABYJ>);
  /** @deprecated */
  patch: $patch.Patch$<ABYJ>;
  /** @deprecated */
  cache: $cache.Cache$<ABYJ>;
}
export function Diff$Diff<ABYJ>(
  patch: $patch.Patch$<ABYJ>,
  cache: $cache.Cache$<ABYJ>,
): Diff$<ABYJ>;
export function Diff$isDiff<ABYJ>(value: any): value is Diff$<unknown>;
export function Diff$Diff$0<ABYJ>(value: Diff$<ABYJ>): $patch.Patch$<ABYJ>;
export function Diff$Diff$patch<ABYJ>(value: Diff$<ABYJ>): $patch.Patch$<ABYJ>;
export function Diff$Diff$1<ABYJ>(value: Diff$<ABYJ>): $cache.Cache$<ABYJ>;
export function Diff$Diff$cache<ABYJ>(value: Diff$<ABYJ>): $cache.Cache$<ABYJ>;

export type Diff$<ABYJ> = Diff<ABYJ>;

declare class PartialDiff<ABYK> extends _.CustomType {
  /** @deprecated */
  constructor(
    patch: $patch.Patch$<ABYK>,
    cache: $cache.Cache$<ABYK>,
    events: $cache.Events$<ABYK>
  );
  /** @deprecated */
  patch: $patch.Patch$<ABYK>;
  /** @deprecated */
  cache: $cache.Cache$<ABYK>;
  /** @deprecated */
  events: $cache.Events$<ABYK>;
}

type PartialDiff$<ABYK> = PartialDiff<ABYK>;

declare class AttributeChange<ABYL> extends _.CustomType {
  /** @deprecated */
  constructor(
    added: _.List<$vattr.Attribute$<ABYL>>,
    removed: _.List<$vattr.Attribute$<ABYL>>,
    events: $cache.Events$<ABYL>
  );
  /** @deprecated */
  added: _.List<$vattr.Attribute$<ABYL>>;
  /** @deprecated */
  removed: _.List<$vattr.Attribute$<ABYL>>;
  /** @deprecated */
  events: $cache.Events$<ABYL>;
}

type AttributeChange$<ABYL> = AttributeChange<ABYL>;

export function diff<ABYM>(
  cache: $cache.Cache$<ABYM>,
  old: $vnode.Element$<ABYM>,
  new$: $vnode.Element$<ABYM>
): Diff$<ABYM>;
