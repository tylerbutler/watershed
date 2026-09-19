/// <reference types="./sequence.d.mts" />
import * as $json from "../../gleam_json/gleam/json.mjs";
import * as $bool from "../../gleam_stdlib/gleam/bool.mjs";
import * as $dict from "../../gleam_stdlib/gleam/dict.mjs";
import * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.mjs";
import * as $int from "../../gleam_stdlib/gleam/int.mjs";
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import * as $option from "../../gleam_stdlib/gleam/option.mjs";
import { None, Some, Option$None$const } from "../../gleam_stdlib/gleam/option.mjs";
import * as $order from "../../gleam_stdlib/gleam/order.mjs";
import * as $result from "../../gleam_stdlib/gleam/result.mjs";
import * as $replica_id from "../../lattice_core/lattice_core/replica_id.mjs";
import * as $version_vector from "../../lattice_core/lattice_core/version_vector.mjs";
import {
  Ok,
  Error,
  toList,
  Empty as $Empty,
  List$Empty$const as $List$Empty$const,
  prepend as listPrepend,
  CustomType as $CustomType,
  isEqual,
} from "../gleam.mjs";

class ItemId extends $CustomType {
  constructor(replica_id, counter) {
    super();
    this.replica_id = replica_id;
    this.counter = counter;
  }
}

class OpId extends $CustomType {
  constructor(replica_id, counter) {
    super();
    this.replica_id = replica_id;
    this.counter = counter;
  }
}

class Move extends $CustomType {
  constructor(op_id, origin_left, origin_right) {
    super();
    this.op_id = op_id;
    this.origin_left = origin_left;
    this.origin_right = origin_right;
  }
}

class Item extends $CustomType {
  constructor(id, origin_left, origin_right, value, deleted, move) {
    super();
    this.id = id;
    this.origin_left = origin_left;
    this.origin_right = origin_right;
    this.value = value;
    this.deleted = deleted;
    this.move = move;
  }
}

class Block extends $CustomType {
  constructor(first_id, values) {
    super();
    this.first_id = first_id;
    this.values = values;
  }
}

class Live extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}

class Stable extends $CustomType {
  constructor(id, value) {
    super();
    this.id = id;
    this.value = value;
  }
}

class LiveEl extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}

class Forwarding extends $CustomType {
  constructor(left, right) {
    super();
    this.left = left;
    this.right = right;
  }
}

class ForwardingMap extends $CustomType {
  constructor(entries) {
    super();
    this.entries = entries;
  }
}

class Sequence extends $CustomType {
  constructor(replica_id, counter, segments, forwardings, frontier) {
    super();
    this.replica_id = replica_id;
    this.counter = counter;
    this.segments = segments;
    this.forwardings = forwardings;
    this.frontier = frontier;
  }
}

export class IndexOutOfBounds extends $CustomType {
  constructor(index, length) {
    super();
    this.index = index;
    this.length = length;
  }
}
export const InsertError$IndexOutOfBounds = (index, length) =>
  new IndexOutOfBounds(index, length);
export const InsertError$isIndexOutOfBounds = (value) =>
  value instanceof IndexOutOfBounds;
export const InsertError$IndexOutOfBounds$index = (value) => value.index;
export const InsertError$IndexOutOfBounds$0 = (value) => value.index;
export const InsertError$IndexOutOfBounds$length = (value) => value.length;
export const InsertError$IndexOutOfBounds$1 = (value) => value.length;

export class DeleteIndexOutOfBounds extends $CustomType {
  constructor(index, length) {
    super();
    this.index = index;
    this.length = length;
  }
}
export const DeleteError$DeleteIndexOutOfBounds = (index, length) =>
  new DeleteIndexOutOfBounds(index, length);
export const DeleteError$isDeleteIndexOutOfBounds = (value) =>
  value instanceof DeleteIndexOutOfBounds;
export const DeleteError$DeleteIndexOutOfBounds$index = (value) => value.index;
export const DeleteError$DeleteIndexOutOfBounds$0 = (value) => value.index;
export const DeleteError$DeleteIndexOutOfBounds$length = (value) =>
  value.length;
export const DeleteError$DeleteIndexOutOfBounds$1 = (value) => value.length;

export class MoveFromIndexOutOfBounds extends $CustomType {
  constructor(index, length) {
    super();
    this.index = index;
    this.length = length;
  }
}
export const MoveError$MoveFromIndexOutOfBounds = (index, length) =>
  new MoveFromIndexOutOfBounds(index, length);
export const MoveError$isMoveFromIndexOutOfBounds = (value) =>
  value instanceof MoveFromIndexOutOfBounds;
export const MoveError$MoveFromIndexOutOfBounds$index = (value) => value.index;
export const MoveError$MoveFromIndexOutOfBounds$0 = (value) => value.index;
export const MoveError$MoveFromIndexOutOfBounds$length = (value) =>
  value.length;
export const MoveError$MoveFromIndexOutOfBounds$1 = (value) => value.length;

export class MoveToIndexOutOfBounds extends $CustomType {
  constructor(index, length_after_removal) {
    super();
    this.index = index;
    this.length_after_removal = length_after_removal;
  }
}
export const MoveError$MoveToIndexOutOfBounds = (index, length_after_removal) =>
  new MoveToIndexOutOfBounds(index, length_after_removal);
export const MoveError$isMoveToIndexOutOfBounds = (value) =>
  value instanceof MoveToIndexOutOfBounds;
export const MoveError$MoveToIndexOutOfBounds$index = (value) => value.index;
export const MoveError$MoveToIndexOutOfBounds$0 = (value) => value.index;
export const MoveError$MoveToIndexOutOfBounds$length_after_removal = (value) =>
  value.length_after_removal;
export const MoveError$MoveToIndexOutOfBounds$1 = (value) =>
  value.length_after_removal;

export const MoveError$index = (value) => value.index;

/**
 * An origin references an ID that is neither present nor forwarded —
 * its forwarding entry has expired. The host must degrade the op (e.g.
 * re-insert by position) or drop it.
 */
export class UnknownOriginTarget extends $CustomType {}
export const TranslateError$UnknownOriginTarget$const =
  new UnknownOriginTarget();
export const TranslateError$UnknownOriginTarget = () =>
  TranslateError$UnknownOriginTarget$const;
export const TranslateError$isUnknownOriginTarget = (value) =>
  value instanceof UnknownOriginTarget;

/**
 * Attach to the item after the gap: inserts at the gap push the anchor
 * right, so it stays glued to its item.
 */
export class Before extends $CustomType {}
export const Bias$Before$const = new Before();
export const Bias$Before = () => Bias$Before$const;
export const Bias$isBefore = (value) => value instanceof Before;

/**
 * Attach to the item before the gap: inserts at the gap land after the
 * anchor, so it stays put.
 */
export class After extends $CustomType {}
export const Bias$After$const = new After();
export const Bias$After = () => Bias$After$const;
export const Bias$isAfter = (value) => value instanceof After;

class Start extends $CustomType {}
const Anchor$Start$const = new Start();

class End extends $CustomType {}
const Anchor$End$const = new End();

class AtItem extends $CustomType {
  constructor(id, bias) {
    super();
    this.id = id;
    this.bias = bias;
  }
}

export class AnchorIndexOutOfBounds extends $CustomType {
  constructor(index, length) {
    super();
    this.index = index;
    this.length = length;
  }
}
export const AnchorError$AnchorIndexOutOfBounds = (index, length) =>
  new AnchorIndexOutOfBounds(index, length);
export const AnchorError$isAnchorIndexOutOfBounds = (value) =>
  value instanceof AnchorIndexOutOfBounds;
export const AnchorError$AnchorIndexOutOfBounds$index = (value) => value.index;
export const AnchorError$AnchorIndexOutOfBounds$0 = (value) => value.index;
export const AnchorError$AnchorIndexOutOfBounds$length = (value) =>
  value.length;
export const AnchorError$AnchorIndexOutOfBounds$1 = (value) => value.length;

/**
 * The anchor references an item this replica cannot locate: either it was
 * created remotely and not merged yet, or it was compacted away and its
 * forwarding entry has expired. Treat this as "re-anchor".
 */
export class UnknownAnchorTarget extends $CustomType {}
export const AnchorError$UnknownAnchorTarget$const = new UnknownAnchorTarget();
export const AnchorError$UnknownAnchorTarget = () =>
  AnchorError$UnknownAnchorTarget$const;
export const AnchorError$isUnknownAnchorTarget = (value) =>
  value instanceof UnknownAnchorTarget;

/**
 * Directly before this element, i.e. at the right end of the gap this
 * element closes. `apply_moves` records the landing under that gap's
 * anchor so later movers resolving `AfterGap` stack after it.
 * 
 * @ignore
 */
class BeforeElement extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}

/**
 * The gap after this element (`None` = document start). Successive moves
 * into the same gap must also stack left-to-right in op order, which
 * `apply_moves` tracks per gap.
 * 
 * @ignore
 */
class AfterGap extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}

/**
 * The gap collapsed past everything (target compacted away with nothing
 * retained around it).
 * 
 * @ignore
 */
class AtEnd extends $CustomType {}
const MoveTarget$AtEnd$const = new AtEnd();

class Retained extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}

class Dropped extends $CustomType {
  constructor(id) {
    super();
    this.id = id;
  }
}

class DropTombstone extends $CustomType {}
const Stability$DropTombstone$const = new DropTombstone();

class ToStable extends $CustomType {}
const Stability$ToStable$const = new ToStable();

class KeepLive extends $CustomType {}
const Stability$KeepLive$const = new KeepLive();

class ScanEntry extends $CustomType {
  constructor(id, left, right, stable) {
    super();
    this.id = id;
    this.left = left;
    this.right = right;
    this.stable = stable;
  }
}

/**
 * The item belongs before this window entry: stop, keep current dest.
 * 
 * @ignore
 */
class StopScan extends $CustomType {}
const ScanStep$StopScan$const = new StopScan();

/**
 * This entry becomes the item's effective left neighbor.
 * 
 * @ignore
 */
class TakeAsLeft extends $CustomType {}
const ScanStep$TakeAsLeft$const = new TakeAsLeft();

/**
 * Undecided; keep this entry in the conflicting set and scan on.
 * 
 * @ignore
 */
class AdvancePast extends $CustomType {}
const ScanStep$AdvancePast$const = new AdvancePast();

/**
 * Create an empty sequence for a replica.
 */
export function new$(replica_id) {
  return new Sequence(
    replica_id,
    0,
    $List$Empty$const,
    $dict.new$(),
    $version_vector.new$(),
  );
}

function flush_run(run, acc) {
  if (run instanceof Some) {
    let first = run[0][0];
    let values_rev = run[0][1];
    return listPrepend(new Block(first, $list.reverse(values_rev)), acc);
  } else {
    return acc;
  }
}

function follows(last, next) {
  let last_rid = last.replica_id;
  let last_counter = last.counter;
  let next_rid = next.replica_id;
  let next_counter = next.counter;
  return (isEqual(last_rid, next_rid)) && (next_counter === (last_counter + 1));
}

function chunk_elements(loop$elements, loop$run, loop$acc) {
  while (true) {
    let elements = loop$elements;
    let run = loop$run;
    let acc = loop$acc;
    if (elements instanceof $Empty) {
      return flush_run(run, acc);
    } else {
      let $ = elements.head;
      if ($ instanceof Stable) {
        let rest = elements.tail;
        let id = $.id;
        let value = $.value;
        if (run instanceof Some) {
          let first = run[0][0];
          let values_rev = run[0][1];
          let last = run[0][2];
          let $1 = follows(last, id);
          if ($1) {
            loop$elements = rest;
            loop$run = new Some([first, listPrepend(value, values_rev), id]);
            loop$acc = acc;
          } else {
            loop$elements = rest;
            loop$run = new Some([id, toList([value]), id]);
            loop$acc = flush_run(run, acc);
          }
        } else {
          loop$elements = rest;
          loop$run = new Some([id, toList([value]), id]);
          loop$acc = acc;
        }
      } else {
        let rest = elements.tail;
        let item = $[0];
        loop$elements = rest;
        loop$run = Option$None$const;
        loop$acc = listPrepend(new Live(item), flush_run(run, acc));
      }
    }
  }
}

function elements_to_segments(elements) {
  let _pipe = chunk_elements(elements, Option$None$const, $List$Empty$const);
  return $list.reverse(_pipe);
}

function element_id(el) {
  if (el instanceof Stable) {
    let id = el.id;
    return id;
  } else {
    let item = el[0];
    return item.id;
  }
}

function insert_run_after_id(
  loop$elements,
  loop$after,
  loop$run,
  loop$prefix_reversed
) {
  while (true) {
    let elements = loop$elements;
    let after = loop$after;
    let run = loop$run;
    let prefix_reversed = loop$prefix_reversed;
    if (elements instanceof $Empty) {
      return $list.fold(
        prefix_reversed,
        run,
        (tail, el) => { return listPrepend(el, tail); },
      );
    } else {
      let first = elements.head;
      let rest = elements.tail;
      let $ = isEqual(element_id(first), after);
      if ($) {
        return $list.fold(
          prefix_reversed,
          listPrepend(first, $list.append(run, rest)),
          (tail, el) => { return listPrepend(el, tail); },
        );
      } else {
        loop$elements = rest;
        loop$after = after;
        loop$run = run;
        loop$prefix_reversed = listPrepend(first, prefix_reversed);
      }
    }
  }
}

/**
 * Splice a run of elements into the stored order immediately after `after`
 * (or at the head when `after` is `None`), preserving run order.
 * 
 * @ignore
 */
function splice_run_after(elements, after, run) {
  if (after instanceof Some) {
    let id = after[0];
    return insert_run_after_id(elements, id, run, $List$Empty$const);
  } else {
    return $list.append(run, elements);
  }
}

/**
 * Build a contiguous run of new items with chained left origins and a shared
 * right origin, minting consecutive counters from `start_counter`. Returns
 * the items in insertion order and the last counter used.
 * 
 * @ignore
 */
function build_insert_run(
  replica_id,
  start_counter,
  values,
  origin_left,
  origin_right
) {
  let items = $list.index_map(
    values,
    (value, offset) => {
      let _block;
      if (offset === 0) {
        _block = origin_left;
      } else {
        _block = new Some(new ItemId(replica_id, (start_counter + offset) - 1));
      }
      let left = _block;
      return new Item(
        new ItemId(replica_id, start_counter + offset),
        left,
        origin_right,
        value,
        Option$None$const,
        Option$None$const,
      );
    },
  );
  return [items, (start_counter + $list.length(values)) - 1];
}

function next_element_id(elements) {
  if (elements instanceof $Empty) {
    return Option$None$const;
  } else {
    let el = elements.head;
    return new Some(element_id(el));
  }
}

function successor_of(loop$elements, loop$id) {
  while (true) {
    let elements = loop$elements;
    let id = loop$id;
    if (elements instanceof $Empty) {
      return Option$None$const;
    } else {
      let el = elements.head;
      let rest = elements.tail;
      let $ = isEqual(element_id(el), id);
      if ($) {
        return next_element_id(rest);
      } else {
        loop$elements = rest;
        loop$id = id;
      }
    }
  }
}

/**
 * The element that follows `left` in the canonical order (`None` means the
 * head of the document, so the first canonical element).
 * 
 * @ignore
 */
function canonical_successor(base, left) {
  if (left instanceof Some) {
    let id = left[0];
    return successor_of(base, id);
  } else {
    return next_element_id(base);
  }
}

function element_is_visible(el) {
  if (el instanceof Stable) {
    return true;
  } else {
    let item = el[0];
    return item.deleted instanceof None;
  }
}

function visible_element_id_at(loop$elements, loop$index) {
  while (true) {
    let elements = loop$elements;
    let index = loop$index;
    if (elements instanceof $Empty) {
      return Option$None$const;
    } else {
      let el = elements.head;
      let rest = elements.tail;
      let $ = element_is_visible(el);
      if ($) {
        let $1 = index === 0;
        if ($1) {
          return new Some(element_id(el));
        } else {
          loop$elements = rest;
          loop$index = index - 1;
        }
      } else {
        loop$elements = rest;
        loop$index = index;
      }
    }
  }
}

/**
 * An empty delta carrying no items — the neutral element for `merge`,
 * returned when an insert covers zero values.
 * 
 * @ignore
 */
function empty_delta(replica_id) {
  return new Sequence(
    replica_id,
    0,
    $List$Empty$const,
    $dict.new$(),
    $version_vector.new$(),
  );
}

function visible_length_elements(elements) {
  let _pipe = elements;
  return $list.fold(
    _pipe,
    0,
    (count, el) => {
      let $ = element_is_visible(el);
      if ($) {
        return count + 1;
      } else {
        return count;
      }
    },
  );
}

function insert_element_after_id(elements, left, el) {
  if (elements instanceof $Empty) {
    return toList([el]);
  } else {
    let first = elements.head;
    let rest = elements.tail;
    let $ = isEqual(element_id(first), left);
    if ($) {
      return listPrepend(first, listPrepend(el, rest));
    } else {
      return listPrepend(first, insert_element_after_id(rest, left, el));
    }
  }
}

function splice_into_gap(elements, previous_in_gap, anchor, el) {
  if (previous_in_gap instanceof Ok) {
    let previous = previous_in_gap[0];
    return insert_element_after_id(elements, previous, el);
  } else if (anchor instanceof Some) {
    let left_id = anchor[0];
    return insert_element_after_id(elements, left_id, el);
  } else {
    return listPrepend(el, elements);
  }
}

/**
 * Canonicalize an `AfterGap` key without changing its physical splice anchor.
 *
 * Base tombstones map to their preceding visible neighbour. An absent ID is
 * a mover already placed in this pass, so it remains its own gap anchor.
 * 
 * @ignore
 */
function canonical_after_gap(anchor, after_gap_anchors) {
  if (anchor instanceof Some) {
    let id = anchor[0];
    let $ = $dict.get(after_gap_anchors, id);
    if ($ instanceof Ok) {
      let anchor$1 = $[0];
      return anchor$1;
    } else {
      return new Some(id);
    }
  } else {
    return anchor;
  }
}

function insert_element_before_id(elements, right, el) {
  if (elements instanceof $Empty) {
    return toList([el]);
  } else {
    let first = elements.head;
    let rest = elements.tail;
    let $ = isEqual(element_id(first), right);
    if ($) {
      return listPrepend(el, listPrepend(first, rest));
    } else {
      return listPrepend(first, insert_element_before_id(rest, right, el));
    }
  }
}

/**
 * Splice a `BeforeElement` landing after any earlier mover in the same gap,
 * then record it as the gap's rightmost mover.
 *
 * Usually inserting immediately before `right_id` lands at the right end of
 * its gap. Tombstones can put an earlier co-gap mover physically after that
 * boundary while remaining in the same visible gap, though, so the tracked
 * mover is authoritative when present.
 *
 * A `right_id` absent from the base is a mover placed earlier in this pass.
 * Landing before it is not the gap's right end, so there is nothing to
 * record and the previous entry stands.
 * 
 * @ignore
 */
function splice_before_and_record(
  elements,
  last_in_gap,
  gap_anchors,
  right_id,
  el
) {
  let $ = $dict.get(gap_anchors, right_id);
  if ($ instanceof Ok) {
    let anchor = $[0];
    return [
      (() => {
        let $1 = $dict.get(last_in_gap, anchor);
        if ($1 instanceof Ok) {
          let previous = $1[0];
          return insert_element_after_id(elements, previous, el);
        } else {
          return insert_element_before_id(elements, right_id, el);
        }
      })(),
      $dict.insert(last_in_gap, anchor, element_id(el)),
    ];
  } else {
    return [insert_element_before_id(elements, right_id, el), last_in_gap];
  }
}

function contains_element_id(elements, id) {
  return $list.any(elements, (el) => { return isEqual(element_id(el), id); });
}

function chase_left(loop$target, loop$entries, loop$fuel) {
  while (true) {
    let target = loop$target;
    let entries = loop$entries;
    let fuel = loop$fuel;
    let $ = fuel <= 0;
    if (target instanceof Some) {
      if ($) {
        return target;
      } else {
        let id = target[0];
        let $1 = $dict.get(entries, id);
        if ($1 instanceof Ok) {
          let left = $1[0].left;
          loop$target = left;
          loop$entries = entries;
          loop$fuel = fuel - 1;
        } else {
          return target;
        }
      }
    } else {
      return target;
    }
  }
}

/**
 * The gap a reclaimed right boundary left behind, named by its left edge.
 *
 * The move targeted the gap immediately before that boundary, so once the
 * boundary is gone the same gap is "after whatever was retained to its
 * left". Falling back to the move's own left origin instead would aim at the
 * far edge of the original gap and skip past everything inserted into it
 * since the move was made — which is how a compacted replica and an
 * uncompacted one end up ordering the mover differently.
 * 
 * @ignore
 */
function reclaimed_boundary_gap(elements, move_right, forwardings, fuel) {
  let $ = chase_left(move_right, forwardings, fuel);
  if ($ instanceof Some) {
    let left_id = $[0];
    let $1 = contains_element_id(elements, left_id);
    if ($1) {
      return new AfterGap(new Some(left_id));
    } else {
      return MoveTarget$AtEnd$const;
    }
  } else {
    return new AfterGap(Option$None$const);
  }
}

function chase_right(loop$target, loop$entries, loop$fuel) {
  while (true) {
    let target = loop$target;
    let entries = loop$entries;
    let fuel = loop$fuel;
    let $ = fuel <= 0;
    if (target instanceof Some) {
      if ($) {
        return target;
      } else {
        let id = target[0];
        let $1 = $dict.get(entries, id);
        if ($1 instanceof Ok) {
          let right = $1[0].right;
          loop$target = right;
          loop$entries = entries;
          loop$fuel = fuel - 1;
        } else {
          return target;
        }
      }
    } else {
      return target;
    }
  }
}

/**
 * Where a move lands when its right boundary was reclaimed by a pass.
 *
 * Prefer the nearest retained element to the boundary's right, so the move
 * still splices before the same neighbour. A forwarded boundary that is
 * itself being moved in this pass is not a faithful gap edge — a replica
 * that still held the reclaimed target would not anchor on it — so that
 * falls through to the gap's left edge instead.
 * 
 * @ignore
 */
function reclaimed_boundary_target(
  elements,
  move_right,
  forwardings,
  mover_ids,
  fuel
) {
  let $ = chase_right(move_right, forwardings, fuel);
  if ($ instanceof Some) {
    let right_id = $[0];
    let $1 = !$dict.has_key(mover_ids, right_id) && contains_element_id(
      elements,
      right_id,
    );
    if ($1) {
      return new BeforeElement(right_id);
    } else {
      return reclaimed_boundary_gap(elements, move_right, forwardings, fuel);
    }
  } else {
    return reclaimed_boundary_gap(elements, move_right, forwardings, fuel);
  }
}

function resolve_move_target(
  elements,
  move_left,
  move_right,
  forwardings,
  mover_ids
) {
  let fuel = $dict.size(forwardings) + 1;
  let _block;
  let $ = chase_left(move_left, forwardings, fuel);
  if ($ instanceof Some) {
    let left_id = $[0];
    let $1 = contains_element_id(elements, left_id);
    if ($1) {
      _block = new AfterGap(new Some(left_id));
    } else {
      _block = MoveTarget$AtEnd$const;
    }
  } else {
    _block = new AfterGap(Option$None$const);
  }
  let left_gap = _block;
  if (move_right instanceof Some) {
    let raw_right = move_right[0];
    let $1 = contains_element_id(elements, raw_right);
    if ($1) {
      return new BeforeElement(raw_right);
    } else {
      let $2 = $dict.has_key(forwardings, raw_right);
      if ($2) {
        return reclaimed_boundary_target(
          elements,
          move_right,
          forwardings,
          mover_ids,
          fuel,
        );
      } else {
        return left_gap;
      }
    }
  } else {
    return left_gap;
  }
}

/**
 * Index the visible gaps on both sides of every element in the move-free base.
 *
 * Movers are spliced into the gaps of this base, so `BeforeElement(right)`
 * and `AfterGap(left)` name the same gap exactly when `left` is `right`'s
 * base predecessor. Keying both on that anchor is what lets co-gap movers
 * stack in op order no matter which path each one resolved through.
 *
 * Tombstones do not split visible gaps and may disappear during compaction,
 * so they keep the preceding visible anchor on both sides. This makes the
 * gap key invariant when an unreferenced tombstone is reclaimed.
 * 
 * @ignore
 */
function base_gap_anchors(elements) {
  let $ = $list.fold(
    elements,
    [$dict.new$(), $dict.new$(), Option$None$const],
    (acc, el) => {
      let before = acc[0];
      let after = acc[1];
      let previous = acc[2];
      let id = element_id(el);
      let _block;
      let $1 = element_is_visible(el);
      if ($1) {
        _block = new Some(id);
      } else {
        _block = previous;
      }
      let next = _block;
      return [
        $dict.insert(before, id, previous),
        $dict.insert(after, id, next),
        next,
      ];
    },
  );
  let before = $[0];
  let after = $[1];
  return [before, after];
}

function remove_element_by_id(elements, id) {
  if (elements instanceof $Empty) {
    return elements;
  } else {
    let el = elements.head;
    let rest = elements.tail;
    let $ = isEqual(element_id(el), id);
    if ($) {
      return rest;
    } else {
      return listPrepend(el, remove_element_by_id(rest, id));
    }
  }
}

/**
 * Return the replica identity used for subsequent local edits.
 *
 * This accessor does not change the state. Use `bind` to adopt a snapshot
 * without merging, or `merge` when combining state or deltas.
 *
 * ## Examples
 *
 * ```gleam
 * let replica = replica_id.new("A")
 * sequence.replica_id(sequence.new(replica)) == replica
 * // -> True
 * ```
 */
export function replica_id(sequence) {
  return sequence.replica_id;
}

function compare_item_ids(a, b) {
  let a_replica = a.replica_id;
  let a_counter = a.counter;
  let b_replica = b.replica_id;
  let b_counter = b.counter;
  let $ = $replica_id.compare(a_replica, b_replica);
  if ($ instanceof $order.Eq) {
    return $int.compare(a_counter, b_counter);
  } else {
    return $;
  }
}

function compare_op_ids(a, b) {
  let a_replica = a.replica_id;
  let a_counter = a.counter;
  let b_replica = b.replica_id;
  let b_counter = b.counter;
  let $ = $int.compare(a_counter, b_counter);
  if ($ instanceof $order.Eq) {
    return $replica_id.compare(a_replica, b_replica);
  } else {
    return $;
  }
}

function compare_moves(a, b) {
  let a_op_id = a.op_id;
  let b_op_id = b.op_id;
  return compare_op_ids(a_op_id, b_op_id);
}

function compare_item_moves(a, b) {
  let $ = a.move;
  let $1 = b.move;
  if ($ instanceof Some) {
    if ($1 instanceof Some) {
      let a_move = $[0];
      let b_move = $1[0];
      let $2 = compare_moves(a_move, b_move);
      if ($2 instanceof $order.Eq) {
        return compare_item_ids(a.id, b.id);
      } else {
        return $2;
      }
    } else {
      return $order.Order$Gt$const;
    }
  } else if ($1 instanceof Some) {
    return $order.Order$Lt$const;
  } else {
    return compare_item_ids(a.id, b.id);
  }
}

function has_move(item) {
  return $option.is_some(item.move);
}

function live_items_of(elements) {
  return $list.filter_map(
    elements,
    (el) => {
      if (el instanceof Stable) {
        return new Error(undefined);
      } else {
        let item = el[0];
        return new Ok(item);
      }
    },
  );
}

/**
 * Re-place every moved item from a canonical base: strip all moved items
 * first, then apply the moves in op order. Both merge directions therefore
 * start from the same non-moved skeleton and converge, regardless of which
 * side had already applied which move. Moves landing in the same gap stack
 * left-to-right in op order, matching how they stack when the gap's right
 * boundary still exists.
 * 
 * @ignore
 */
function apply_moves(elements, forwardings) {
  let _block;
  let _pipe = elements;
  let _pipe$1 = live_items_of(_pipe);
  let _pipe$2 = $list.filter(_pipe$1, has_move);
  _block = $list.sort(_pipe$2, compare_item_moves);
  let movers = _block;
  let stripped = $list.fold(
    movers,
    elements,
    (current, item) => { return remove_element_by_id(current, item.id); },
  );
  let mover_ids = $list.fold(
    movers,
    $dict.new$(),
    (acc, item) => { return $dict.insert(acc, item.id, undefined); },
  );
  let $ = base_gap_anchors(stripped);
  let before_gap_anchors = $[0];
  let after_gap_anchors = $[1];
  let $1 = $list.fold(
    movers,
    [stripped, $dict.new$()],
    (acc, item) => {
      let current = acc[0];
      let last_in_gap = acc[1];
      let $2 = item.move;
      if ($2 instanceof Some) {
        let move_left = $2[0].origin_left;
        let move_right = $2[0].origin_right;
        let $3 = resolve_move_target(
          current,
          move_left,
          move_right,
          forwardings,
          mover_ids,
        );
        if ($3 instanceof BeforeElement) {
          let right_id = $3[0];
          return splice_before_and_record(
            current,
            last_in_gap,
            before_gap_anchors,
            right_id,
            new LiveEl(item),
          );
        } else if ($3 instanceof AfterGap) {
          let anchor = $3[0];
          let gap = canonical_after_gap(anchor, after_gap_anchors);
          return [
            splice_into_gap(
              current,
              $dict.get(last_in_gap, gap),
              anchor,
              new LiveEl(item),
            ),
            $dict.insert(last_in_gap, gap, item.id),
          ];
        } else {
          return [
            $list.append(current, toList([new LiveEl(item)])),
            last_in_gap,
          ];
        }
      } else {
        return acc;
      }
    },
  );
  let result = $1[0];
  return result;
}

function segments_to_elements(segments) {
  return $list.flat_map(
    segments,
    (segment) => {
      if (segment instanceof Block) {
        let first_id = segment.first_id;
        let values$1 = segment.values;
        let rid = first_id.replica_id;
        let first_counter = first_id.counter;
        return $list.index_map(
          values$1,
          (value, offset) => {
            return new Stable(new ItemId(rid, first_counter + offset), value);
          },
        );
      } else {
        let item = segment[0];
        return toList([new LiveEl(item)]);
      }
    },
  );
}

/**
 * Insert several values and return both the updated sequence and the merged
 * insertion delta covering every new item.
 *
 * Returns `IndexOutOfBounds` when `index` is outside `[0, length]`.
 *
 * Each new item's left origin is the previous new item (the first pins to the
 * visible left neighbor) and every item shares the same right origin — the
 * left neighbor's canonical successor — so the run integrates contiguously on
 * every replica. When the state holds no live move record, stored order is
 * already the canonical order, so the run is spliced directly in place rather
 * than re-deriving the whole order; otherwise it falls back to a full rebuild.
 *
 * Apply the delta with `merge(peer_state, delta, peer_replica)`.
 */
export function insert_many_with_delta(sequence, index, values) {
  let elements = segments_to_elements(sequence.segments);
  let visible = apply_moves(elements, sequence.forwardings);
  let size = visible_length_elements(elements);
  let $ = (index < 0) || (index > size);
  if ($) {
    return new Error(new IndexOutOfBounds(index, size));
  } else {
    if (values instanceof $Empty) {
      return new Ok([sequence, empty_delta(sequence.replica_id)]);
    } else {
      let _block;
      if (index === 0) {
        _block = Option$None$const;
      } else {
        _block = visible_element_id_at(visible, index - 1);
      }
      let origin_left = _block;
      let origin_right = canonical_successor(elements, origin_left);
      let $1 = build_insert_run(
        sequence.replica_id,
        sequence.counter + 1,
        values,
        origin_left,
        origin_right,
      );
      let items = $1[0];
      let last_counter = $1[1];
      let new_elements = $list.map(
        items,
        (var0) => { return new LiveEl(var0); },
      );
      let updated_elements = splice_run_after(
        elements,
        origin_left,
        new_elements,
      );
      let updated = new Sequence(
        sequence.replica_id,
        last_counter,
        elements_to_segments(updated_elements),
        sequence.forwardings,
        sequence.frontier,
      );
      let delta = new Sequence(
        sequence.replica_id,
        last_counter,
        $list.map(items, (var0) => { return new Live(var0); }),
        $dict.new$(),
        $version_vector.new$(),
      );
      return new Ok([updated, delta]);
    }
  }
}

/**
 * Insert a value and return both the updated sequence and insertion delta.
 *
 * Returns `IndexOutOfBounds` when `index` is outside `[0, length]`.
 * Apply the delta with `merge(peer_state, delta, peer_replica)`.
 */
export function insert_with_delta(sequence, index, value) {
  return insert_many_with_delta(sequence, index, toList([value]));
}

/**
 * Insert a value at the visible item index.
 *
 * Returns `IndexOutOfBounds` when `index` is outside `[0, length]`.
 */
export function insert(sequence, index, value) {
  let _pipe = insert_with_delta(sequence, index, value);
  return $result.map(_pipe, (pair) => { return pair[0]; });
}

/**
 * Insert several values at consecutive visible indices starting at `index`.
 *
 * `values` are placed in order — the first at `index`, the next at
 * `index + 1`, and so on — exactly as looping `insert` would, but the whole
 * run is spliced in a single pass and reported as one delta. Returns
 * `IndexOutOfBounds` when `index` is outside `[0, length]`.
 */
export function insert_many(sequence, index, values) {
  let _pipe = insert_many_with_delta(sequence, index, values);
  return $result.map(_pipe, (pair) => { return pair[0]; });
}

function delta_sequence(replica_id, counter, item) {
  return new Sequence(
    replica_id,
    counter,
    toList([new Live(item)]),
    $dict.new$(),
    $version_vector.new$(),
  );
}

function prepend_element_result(result, el) {
  if (result instanceof Some) {
    let updated_rest = result[0][0];
    let item = result[0][1];
    return new Some([listPrepend(el, updated_rest), item]);
  } else {
    return result;
  }
}

function tombstone_of(el, prev, next, op) {
  if (el instanceof Stable) {
    let id = el.id;
    let value = el.value;
    return new Item(id, prev, next, value, new Some(op), Option$None$const);
  } else {
    let item = el[0];
    return new Item(
      item.id,
      item.origin_left,
      item.origin_right,
      item.value,
      new Some(op),
      item.move,
    );
  }
}

function tombstone_element_by_id(elements, id, prev, op) {
  if (elements instanceof $Empty) {
    return Option$None$const;
  } else {
    let el = elements.head;
    let rest = elements.tail;
    let $ = isEqual(element_id(el), id);
    if ($) {
      let item = tombstone_of(el, prev, next_element_id(rest), op);
      return new Some([listPrepend(new LiveEl(item), rest), item]);
    } else {
      let _pipe = tombstone_element_by_id(
        rest,
        id,
        new Some(element_id(el)),
        op,
      );
      return prepend_element_result(_pipe, el);
    }
  }
}

/**
 * Walk to the visible element at `target`, replacing it with a tombstone.
 * A stable block member is extracted to a live item with origins
 * synthesized from its current neighbors so ordering keeps it in place.
 * Tombstone the element sitting at visible index `target`, updating the
 * CANONICAL base. A stable block member is extracted with its base
 * neighbours as origins, not the neighbours the move overlay gave it.
 * 
 * @ignore
 */
function tombstone_in_base(elements, visible, target, op) {
  let $ = visible_element_id_at(visible, target);
  if ($ instanceof Some) {
    let id = $[0];
    return tombstone_element_by_id(elements, id, Option$None$const, op);
  } else {
    return $;
  }
}

/**
 * Delete a value and return both the updated sequence and deletion delta.
 *
 * Returns `DeleteIndexOutOfBounds` when `index` is outside `[0, length)`.
 *
 * Deletes mint an op ID (bumping this replica's counter) so a compaction
 * frontier can distinguish acknowledged deletes from in-flight ones.
 *
 * Apply the delta with `merge(peer_state, delta, peer_replica)`.
 */
export function delete_with_delta(sequence, index) {
  let elements = segments_to_elements(sequence.segments);
  let visible = apply_moves(elements, sequence.forwardings);
  let size = visible_length_elements(elements);
  let $ = (index < 0) || (index >= size);
  if ($) {
    return new Error(new DeleteIndexOutOfBounds(index, size));
  } else {
    let next_counter = sequence.counter + 1;
    let op = new OpId(sequence.replica_id, next_counter);
    let $1 = tombstone_in_base(elements, visible, index, op);
    if ($1 instanceof Some) {
      let updated_elements = $1[0][0];
      let deleted_item = $1[0][1];
      let updated = new Sequence(
        sequence.replica_id,
        next_counter,
        elements_to_segments(updated_elements),
        sequence.forwardings,
        sequence.frontier,
      );
      let delta = delta_sequence(
        sequence.replica_id,
        next_counter,
        deleted_item,
      );
      return new Ok([updated, delta]);
    } else {
      return new Error(new DeleteIndexOutOfBounds(index, size));
    }
  }
}

/**
 * Delete the value at the visible item index.
 *
 * Returns `DeleteIndexOutOfBounds` when `index` is outside `[0, length)`.
 */
export function delete$(sequence, index) {
  let _pipe = delete_with_delta(sequence, index);
  return $result.map(_pipe, (pair) => { return pair[0]; });
}

function swap_in_item(elements, item) {
  if (elements instanceof $Empty) {
    return toList([new LiveEl(item)]);
  } else {
    let el = elements.head;
    let rest = elements.tail;
    let $ = isEqual(element_id(el), item.id);
    if ($) {
      return listPrepend(new LiveEl(item), rest);
    } else {
      return listPrepend(el, swap_in_item(rest, item));
    }
  }
}

function insert_element_at(
  loop$elements,
  loop$index,
  loop$el,
  loop$prefix_reversed
) {
  while (true) {
    let elements = loop$elements;
    let index = loop$index;
    let el = loop$el;
    let prefix_reversed = loop$prefix_reversed;
    let $ = index <= 0;
    if ($) {
      return $list.fold(
        prefix_reversed,
        listPrepend(el, elements),
        (tail, first) => { return listPrepend(first, tail); },
      );
    } else {
      if (elements instanceof $Empty) {
        return $list.fold(
          prefix_reversed,
          toList([el]),
          (tail, first) => { return listPrepend(first, tail); },
        );
      } else {
        let first = elements.head;
        let rest = elements.tail;
        loop$elements = rest;
        loop$index = index - 1;
        loop$el = el;
        loop$prefix_reversed = listPrepend(first, prefix_reversed);
      }
    }
  }
}

function replica_of(id) {
  let rid = id.replica_id;
  return rid;
}

function scan_step(
  entry,
  item_left,
  item_right,
  item_replica,
  before_origin,
  conflicting
) {
  let $ = isEqual(entry.left, item_left);
  if ($) {
    let $1 = $replica_id.compare(replica_of(entry.id), item_replica);
    if ($1 instanceof $order.Lt) {
      return ScanStep$TakeAsLeft$const;
    } else if ($1 instanceof $order.Eq) {
      let $2 = isEqual(entry.right, item_right);
      if ($2) {
        return ScanStep$StopScan$const;
      } else {
        return ScanStep$AdvancePast$const;
      }
    } else {
      let $2 = isEqual(entry.right, item_right);
      if ($2) {
        return ScanStep$StopScan$const;
      } else {
        return ScanStep$AdvancePast$const;
      }
    }
  } else {
    let $1 = entry.left;
    if ($1 instanceof Some) {
      let entry_left = $1[0];
      let $2 = $dict.has_key(before_origin, entry_left);
      let $3 = $dict.has_key(conflicting, entry_left);
      if ($2) {
        if ($3) {
          return ScanStep$AdvancePast$const;
        } else {
          return ScanStep$TakeAsLeft$const;
        }
      } else {
        return ScanStep$StopScan$const;
      }
    } else {
      return ScanStep$StopScan$const;
    }
  }
}

function yata_scan(
  loop$window,
  loop$item_left,
  loop$item_right,
  loop$item_replica,
  loop$position,
  loop$dest,
  loop$before_origin,
  loop$conflicting
) {
  while (true) {
    let window = loop$window;
    let item_left = loop$item_left;
    let item_right = loop$item_right;
    let item_replica = loop$item_replica;
    let position = loop$position;
    let dest = loop$dest;
    let before_origin = loop$before_origin;
    let conflicting = loop$conflicting;
    if (window instanceof $Empty) {
      return dest;
    } else {
      let entry = window.head;
      let rest = window.tail;
      let $ = entry.stable;
      if ($) {
        return dest;
      } else {
        let before_origin$1 = $dict.insert(before_origin, entry.id, undefined);
        let conflicting$1 = $dict.insert(conflicting, entry.id, undefined);
        let $1 = scan_step(
          entry,
          item_left,
          item_right,
          item_replica,
          before_origin$1,
          conflicting$1,
        );
        if ($1 instanceof StopScan) {
          return dest;
        } else if ($1 instanceof TakeAsLeft) {
          loop$window = rest;
          loop$item_left = item_left;
          loop$item_right = item_right;
          loop$item_replica = item_replica;
          loop$position = position + 1;
          loop$dest = position + 1;
          loop$before_origin = before_origin$1;
          loop$conflicting = $dict.new$();
        } else {
          loop$window = rest;
          loop$item_left = item_left;
          loop$item_right = item_right;
          loop$item_replica = item_replica;
          loop$position = position + 1;
          loop$dest = dest;
          loop$before_origin = before_origin$1;
          loop$conflicting = conflicting$1;
        }
      }
    }
  }
}

function scan_entry(el, forwardings, fuel) {
  if (el instanceof Stable) {
    let id = el.id;
    return new ScanEntry(id, Option$None$const, Option$None$const, true);
  } else {
    let other = el[0];
    return new ScanEntry(
      other.id,
      chase_left(other.origin_left, forwardings, fuel),
      other.origin_right,
      false,
    );
  }
}

function index_of_element_loop(loop$elements, loop$id, loop$current) {
  while (true) {
    let elements = loop$elements;
    let id = loop$id;
    let current = loop$current;
    if (elements instanceof $Empty) {
      return new Error(undefined);
    } else {
      let el = elements.head;
      let rest = elements.tail;
      let $ = isEqual(element_id(el), id);
      if ($) {
        return new Ok(current);
      } else {
        loop$elements = rest;
        loop$id = id;
        loop$current = current + 1;
      }
    }
  }
}

function index_of_element(elements, id) {
  return index_of_element_loop(elements, id, 0);
}

/**
 * Degrade origins that reference IDs this state has never seen (or whose
 * forwardings expired) to the document boundary, mirroring how unmerged
 * origins have always been treated.
 * 
 * @ignore
 */
function resolve_origin(origin, elements) {
  if (origin instanceof Some) {
    let id = origin[0];
    let $ = contains_element_id(elements, id);
    if ($) {
      return new Some(id);
    } else {
      return Option$None$const;
    }
  } else {
    return origin;
  }
}

/**
 * Place a new item into the element order using its origins.
 *
 * Follows the YATA/Yjs `integrate` algorithm: the item lands between its
 * left and right origins, and the scan over the conflict window decides its
 * position among concurrently inserted items. For causally valid ops the
 * window never contains a stable (origin-stripped) element — those were
 * visible when the op was created, so they cannot sit strictly between its
 * visible-adjacent origins; a stale op that does hit one degrades by
 * stopping the scan there.
 * 
 * @ignore
 */
function integrate_element(elements, item, forwardings) {
  let fuel = $dict.size(forwardings) + 1;
  let item_left = chase_left(item.origin_left, forwardings, fuel);
  let item_right = item.origin_right;
  let left = resolve_origin(item_left, elements);
  let right = resolve_origin(
    chase_right(item.origin_right, forwardings, fuel),
    elements,
  );
  let _block;
  if (left instanceof Some) {
    let id = left[0];
    let $ = index_of_element(elements, id);
    if ($ instanceof Ok) {
      let pos = $[0];
      _block = pos;
    } else {
      _block = -1;
    }
  } else {
    _block = -1;
  }
  let left_pos = _block;
  let total = $list.length(elements);
  let _block$1;
  if (right instanceof Some) {
    let id = right[0];
    let $ = index_of_element(elements, id);
    if ($ instanceof Ok) {
      let pos = $[0];
      _block$1 = pos;
    } else {
      _block$1 = total;
    }
  } else {
    _block$1 = total;
  }
  let right_pos = _block$1;
  let _block$2;
  let _pipe = elements;
  let _pipe$1 = $list.drop(_pipe, left_pos + 1);
  let _pipe$2 = $list.take(_pipe$1, (right_pos - left_pos) - 1);
  _block$2 = $list.map(
    _pipe$2,
    (_capture) => { return scan_entry(_capture, forwardings, fuel); },
  );
  let window = _block$2;
  let offset = yata_scan(
    window,
    item_left,
    item_right,
    replica_of(item.id),
    0,
    0,
    $dict.new$(),
    $dict.new$(),
  );
  return insert_element_at(
    elements,
    (left_pos + 1) + offset,
    new LiveEl(item),
    $List$Empty$const,
  );
}

function compare_lamport(x, y) {
  let $ = x.id;
  let x_rid = $.replica_id;
  let x_counter = $.counter;
  let $1 = y.id;
  let y_rid = $1.replica_id;
  let y_counter = $1.counter;
  let $2 = $int.compare(x_counter, y_counter);
  if ($2 instanceof $order.Eq) {
    return $replica_id.compare(x_rid, y_rid);
  } else {
    return $2;
  }
}

function frontier_covers(frontier, id) {
  let rid = id.replica_id;
  let counter = id.counter;
  return $version_vector.get(frontier, rid) >= counter;
}

/**
 * The canonical pre-move order: pinned covered elements in list order with
 * everything else integrated in Lamport order.
 *
 * A covered element that carries a still-volatile move record is NOT
 * pinned: its stored position reflects whichever moves this replica has
 * already applied, which differs between replicas. It always carries its
 * origins, so it re-integrates at its settled base position instead (its
 * Lamport position sorts it before every volatile item automatically); the
 * move overlay then re-places it.
 * 
 * @ignore
 */
function rebuild_base(elements, forwardings, frontier) {
  let pinned = $list.filter(
    elements,
    (el) => {
      if (el instanceof Stable) {
        return true;
      } else {
        let item = el[0];
        return frontier_covers(frontier, item.id);
      }
    },
  );
  let _pipe = elements;
  let _pipe$1 = live_items_of(_pipe);
  let _pipe$2 = $list.filter(
    _pipe$1,
    (item) => { return !frontier_covers(frontier, item.id); },
  );
  let _pipe$3 = $list.sort(_pipe$2, compare_lamport);
  return $list.fold(
    _pipe$3,
    pinned,
    (current, item) => { return integrate_element(current, item, forwardings); },
  );
}

/**
 * Deterministically rebuild the element order.
 *
 * Everything at or below the frontier — stable elements and old live items
 * alike — is pinned at its stored position: those positions converged on
 * every replica before the frontier passed them, so the pinned skeleton is
 * identical everywhere. Items above the frontier are integrated YATA-style
 * one at a time in Lamport order (a canonical total order), which makes
 * the result a pure function of the element set; finally moves are applied
 * last-writer-wins. Every construction path (local edits and both merge
 * directions) goes through this, so convergence holds by construction.
 *
 * Because ops record canonical-adjacent origins, a volatile item's
 * conflict window can only ever contain other volatile items — never a
 * pinned element — so integration never needs the origins compaction
 * stripped.
 * 
 * @ignore
 */
function rebuild(elements, forwardings, frontier) {
  return rebuild_base(elements, forwardings, frontier);
}

function element_as_item_by_id(loop$elements, loop$id, loop$prev) {
  while (true) {
    let elements = loop$elements;
    let id = loop$id;
    let prev = loop$prev;
    if (elements instanceof $Empty) {
      return Option$None$const;
    } else {
      let el = elements.head;
      let rest = elements.tail;
      let $ = isEqual(element_id(el), id);
      if ($) {
        if (el instanceof Stable) {
          let stable_id = el.id;
          let value = el.value;
          return new Some(
            new Item(
              stable_id,
              prev,
              next_element_id(rest),
              value,
              Option$None$const,
              Option$None$const,
            ),
          );
        } else {
          let item = el[0];
          return new Some(item);
        }
      } else {
        loop$elements = rest;
        loop$id = id;
        loop$prev = new Some(element_id(el));
      }
    }
  }
}

/**
 * The item at visible index `target`, read out of the CANONICAL base so a
 * stable block member gets its base neighbours as origins.
 * 
 * @ignore
 */
function base_item_at_visible_index(elements, visible, target) {
  let $ = visible_element_id_at(visible, target);
  if ($ instanceof Some) {
    let id = $[0];
    return element_as_item_by_id(elements, id, Option$None$const);
  } else {
    return $;
  }
}

function move_visible_element(sequence, elements, visible, from_index, to_index) {
  let $ = base_item_at_visible_index(elements, visible, from_index);
  if ($ instanceof Some) {
    let item = $[0];
    let remaining = $list.filter(
      visible,
      (el) => { return !isEqual(element_id(el), item.id); },
    );
    let _block;
    if (to_index === 0) {
      _block = Option$None$const;
    } else {
      _block = visible_element_id_at(remaining, to_index - 1);
    }
    let origin_left = _block;
    let origin_right = visible_element_id_at(remaining, to_index);
    let next_counter = sequence.counter + 1;
    let moved_item = new Item(
      item.id,
      item.origin_left,
      item.origin_right,
      item.value,
      item.deleted,
      new Some(
        new Move(
          new OpId(sequence.replica_id, next_counter),
          origin_left,
          origin_right,
        ),
      ),
    );
    let updated_elements = rebuild(
      swap_in_item(elements, moved_item),
      sequence.forwardings,
      sequence.frontier,
    );
    let updated = new Sequence(
      sequence.replica_id,
      next_counter,
      elements_to_segments(updated_elements),
      sequence.forwardings,
      sequence.frontier,
    );
    let delta = delta_sequence(sequence.replica_id, next_counter, moved_item);
    return new Ok([updated, delta]);
  } else {
    return new Error(
      new MoveFromIndexOutOfBounds(
        from_index,
        visible_length_elements(elements),
      ),
    );
  }
}

/**
 * Move a visible item and return both the updated sequence and move delta.
 *
 * The `to_index` is interpreted after removing the item from `from_index`.
 *
 * Returns a `MoveError` when either index is out of bounds.
 * Apply the delta with `merge(peer_state, delta, peer_replica)`.
 */
export function move_with_delta(sequence, from_index, to_index) {
  let elements = segments_to_elements(sequence.segments);
  let visible = apply_moves(elements, sequence.forwardings);
  let size = visible_length_elements(elements);
  let length_after_removal = size - 1;
  let $ = (from_index < 0) || (from_index >= size);
  let $1 = (to_index < 0) || (to_index > length_after_removal);
  if ($) {
    return new Error(new MoveFromIndexOutOfBounds(from_index, size));
  } else if ($1) {
    return new Error(new MoveToIndexOutOfBounds(to_index, length_after_removal));
  } else {
    return move_visible_element(
      sequence,
      elements,
      visible,
      from_index,
      to_index,
    );
  }
}

/**
 * Move a visible item to another visible index.
 *
 * The `to_index` is interpreted after removing the item from `from_index`.
 *
 * Returns a `MoveError` when either index is out of bounds.
 */
export function move(sequence, from_index, to_index) {
  let _pipe = move_with_delta(sequence, from_index, to_index);
  return $result.map(_pipe, (pair) => { return pair[0]; });
}

/**
 * Create an anchor at the start of the sequence. Always resolves to 0.
 */
export function start_anchor() {
  return Anchor$Start$const;
}

/**
 * Create an anchor at the end of the sequence. Always resolves to the
 * current visible length, tracking growth.
 */
export function end_anchor() {
  return Anchor$End$const;
}

/**
 * The user-facing element order: the stored base with every move overlaid.
 *
 * Moves are an overlay, not part of the stored order, so every read that
 * depends on position — values, index lookups, anchors — goes through here.
 * Writes go the other way: they compute origins from this view and then
 * update the base.
 * 
 * @ignore
 */
function visible_elements(sequence) {
  return apply_moves(
    segments_to_elements(sequence.segments),
    sequence.forwardings,
  );
}

/**
 * Create an anchor at the gap before the visible item at `index`.
 *
 * `Before` bias binds the anchor to the item at `index`; `After` bias binds
 * it to the item at `index - 1`. Boundary positions with no item on the
 * chosen side degrade to the start / end sentinels.
 *
 * Valid positions are `0 <= index <= length`.
 */
export function anchor_at(sequence, index, bias) {
  let elements = visible_elements(sequence);
  let size = visible_length_elements(elements);
  let $ = (index < 0) || (index > size);
  if ($) {
    return new Error(new AnchorIndexOutOfBounds(index, size));
  } else {
    if (bias instanceof Before) {
      let $1 = visible_element_id_at(elements, index);
      if ($1 instanceof Some) {
        let id = $1[0];
        return new Ok(new AtItem(id, Bias$Before$const));
      } else {
        return new Ok(Anchor$End$const);
      }
    } else {
      let $1 = visible_element_id_at(elements, index - 1);
      if ($1 instanceof Some) {
        let id = $1[0];
        return new Ok(new AtItem(id, Bias$After$const));
      } else {
        return new Ok(Anchor$Start$const);
      }
    }
  }
}

function resolve_element_anchor(
  loop$elements,
  loop$id,
  loop$bias,
  loop$visible_before
) {
  while (true) {
    let elements = loop$elements;
    let id = loop$id;
    let bias = loop$bias;
    let visible_before = loop$visible_before;
    if (elements instanceof $Empty) {
      return new Error(undefined);
    } else {
      let el = elements.head;
      let rest = elements.tail;
      let $ = isEqual(element_id(el), id);
      if ($) {
        let $1 = element_is_visible(el);
        if (bias instanceof After && $1) {
          return new Ok(visible_before + 1);
        } else {
          return new Ok(visible_before);
        }
      } else {
        let $1 = element_is_visible(el);
        if ($1) {
          loop$elements = rest;
          loop$id = id;
          loop$bias = bias;
          loop$visible_before = visible_before + 1;
        } else {
          loop$elements = rest;
          loop$id = id;
          loop$bias = bias;
          loop$visible_before = visible_before;
        }
      }
    }
  }
}

function resolve_forwarded_gap(elements, left) {
  if (left instanceof Some) {
    let left_id = left[0];
    let $ = resolve_element_anchor(elements, left_id, Bias$After$const, 0);
    if ($ instanceof Ok) {
      return $;
    } else {
      return new Error(AnchorError$UnknownAnchorTarget$const);
    }
  } else {
    return new Ok(0);
  }
}

/**
 * Resolve an anchor to a current visible index in `[0, length]`.
 *
 * Anchors on deleted items still resolve: both biases collapse to the gap
 * where the item used to be. Anchors follow moved items.
 *
 * Anchors to compacted items resolve through the forwarding map to the gap
 * the item left behind — semantically the same as tombstone collapse.
 *
 * Returns `Error(UnknownAnchorTarget)` when the anchor references an item
 * this replica has never seen (created remotely and not yet merged), or one
 * that was compacted away and whose forwarding entry has since been removed
 * by the host's retention policy. Either way the anchor is unusable and the
 * holder should re-anchor.
 */
export function resolve(sequence, anchor) {
  let elements = visible_elements(sequence);
  if (anchor instanceof Start) {
    return new Ok(0);
  } else if (anchor instanceof End) {
    return new Ok(visible_length_elements(elements));
  } else {
    let id = anchor.id;
    let bias = anchor.bias;
    let $ = resolve_element_anchor(elements, id, bias, 0);
    if ($ instanceof Ok) {
      return $;
    } else {
      let $1 = $dict.get(sequence.forwardings, id);
      if ($1 instanceof Ok) {
        let left = $1[0].left;
        return resolve_forwarded_gap(elements, left);
      } else {
        return new Error(AnchorError$UnknownAnchorTarget$const);
      }
    }
  }
}

function encode_bias(bias) {
  if (bias instanceof Before) {
    return $json.string("before");
  } else {
    return $json.string("after");
  }
}

function encode_item_id(id) {
  let rid = id.replica_id;
  let counter = id.counter;
  return $json.object(
    toList([
      ["replica_id", $json.string($replica_id.to_string(rid))],
      ["counter", $json.int(counter)],
    ]),
  );
}

/**
 * Encode an anchor as a self-describing JSON value.
 *
 * Produces an envelope with `type`, `v` (schema version), and `anchor`, so
 * anchors can travel between replicas (e.g. shared cursors).
 */
export function anchor_to_json(anchor) {
  let _block;
  if (anchor instanceof Start) {
    _block = $json.object(toList([["kind", $json.string("start")]]));
  } else if (anchor instanceof End) {
    _block = $json.object(toList([["kind", $json.string("end")]]));
  } else {
    let id = anchor.id;
    let bias = anchor.bias;
    _block = $json.object(
      toList([
        ["kind", $json.string("item")],
        ["id", encode_item_id(id)],
        ["bias", encode_bias(bias)],
      ]),
    );
  }
  let encoded = _block;
  return $json.object(
    toList([
      ["type", $json.string("anchor")],
      ["v", $json.int(1)],
      ["anchor", encoded],
    ]),
  );
}

function bias_decoder() {
  let _pipe = $decode.string;
  return $decode.then$(
    _pipe,
    (value) => {
      if (value === "before") {
        return $decode.success(Bias$Before$const);
      } else if (value === "after") {
        return $decode.success(Bias$After$const);
      } else {
        return $decode.failure(Bias$Before$const, "before or after");
      }
    },
  );
}

function non_negative_int_decoder() {
  let _pipe = $decode.int;
  return $decode.then$(
    _pipe,
    (val) => {
      let $ = val >= 0;
      if ($) {
        return $decode.success(val);
      } else {
        return $decode.failure(val, "a non-negative integer");
      }
    },
  );
}

function item_id_decoder() {
  return $decode.field(
    "replica_id",
    $replica_id.decoder(),
    (rid) => {
      return $decode.field(
        "counter",
        non_negative_int_decoder(),
        (counter) => { return $decode.success(new ItemId(rid, counter)); },
      );
    },
  );
}

/**
 * Decode an anchor from a JSON string produced by `anchor_to_json`.
 */
export function anchor_from_json(json_string) {
  let anchor_decoder = $decode.field(
    "kind",
    $decode.string,
    (kind) => {
      if (kind === "start") {
        return $decode.success(Anchor$Start$const);
      } else if (kind === "end") {
        return $decode.success(Anchor$End$const);
      } else if (kind === "item") {
        return $decode.field(
          "id",
          item_id_decoder(),
          (id) => {
            return $decode.field(
              "bias",
              bias_decoder(),
              (bias) => { return $decode.success(new AtItem(id, bias)); },
            );
          },
        );
      } else {
        return $decode.failure(Anchor$Start$const, "one of start, end, item");
      }
    },
  );
  let envelope_decoder = $decode.field(
    "type",
    $decode.string,
    (type_tag) => {
      return $decode.field(
        "v",
        $decode.int,
        (version) => { return $decode.success([type_tag, version]); },
      );
    },
  );
  let $ = $json.parse(json_string, envelope_decoder);
  if ($ instanceof Ok) {
    let type_tag = $[0][0];
    let version = $[0][1];
    let $1 = (type_tag === "anchor") && (version === 1);
    if ($1) {
      return $json.parse(
        json_string,
        $decode.field(
          "anchor",
          anchor_decoder,
          (anchor) => { return $decode.success(anchor); },
        ),
      );
    } else {
      return new Error(
        new $json.UnableToDecode(
          toList([
            new $decode.DecodeError(
              "type=anchor and v=1",
              (type_tag + " v=") + $int.to_string(version),
              $List$Empty$const,
            ),
          ]),
        ),
      );
    }
  } else {
    return $;
  }
}

/**
 * Return all visible values in sequence order.
 */
export function values(sequence) {
  let _pipe = visible_elements(sequence);
  return $list.filter_map(
    _pipe,
    (el) => {
      if (el instanceof Stable) {
        let value = el.value;
        return new Ok(value);
      } else {
        let item = el[0];
        let $ = item.deleted;
        if ($ instanceof Some) {
          return new Error(undefined);
        } else {
          return new Ok(item.value);
        }
      }
    },
  );
}

/**
 * Select the identity for subsequent edits without rebuilding the sequence.
 *
 * Preserves item IDs, counters, stored order, and compaction metadata.
 * Independent writers must use distinct replica IDs.
 *
 * ## Examples
 *
 * ```gleam
 * let local = replica_id.new("B")
 * sequence.new(replica_id.new("A"))
 * |> sequence.bind(local)
 * |> sequence.replica_id()
 * // -> local
 * ```
 */
export function bind(sequence, replica) {
  return new Sequence(
    replica,
    sequence.counter,
    sequence.segments,
    sequence.forwardings,
    sequence.frontier,
  );
}

/**
 * Return the count of visible values.
 */
export function length(sequence) {
  let _pipe = sequence.segments;
  return $list.fold(
    _pipe,
    0,
    (count, segment) => {
      if (segment instanceof Block) {
        let values$1 = segment.values;
        return count + $list.length(values$1);
      } else {
        let item = segment[0];
        let $ = item.deleted;
        if ($ instanceof Some) {
          return count;
        } else {
          return count + 1;
        }
      }
    },
  );
}

/**
 * The stability frontier this sequence was last compacted at.
 *
 * Empty until the first `compact` call. Carried in the state so merging can
 * tell which side is compacted further.
 */
export function frontier(sequence) {
  return sequence.frontier;
}

/**
 * The number of entries in a forwarding map.
 */
export function forwarding_size(map) {
  let entries = map.entries;
  return $dict.size(entries);
}

/**
 * Remove previously emitted forwarding entries from the sequence.
 *
 * Forwardings are bounded by the host's retention policy: keep the map
 * returned by each `compact` round and expire old rounds by passing them
 * here. Anchors and deltas referencing removed entries hard-fail
 * (`UnknownAnchorTarget` / `UnknownOriginTarget`) and must re-anchor or
 * resync.
 */
export function remove_forwardings(sequence, map) {
  let entries = map.entries;
  let remaining = $dict.fold(
    entries,
    sequence.forwardings,
    (acc, id, _) => { return $dict.delete$(acc, id); },
  );
  return new Sequence(
    sequence.replica_id,
    sequence.counter,
    sequence.segments,
    remaining,
    sequence.frontier,
  );
}

function merge_move(a, b) {
  if (a instanceof Some) {
    if (b instanceof Some) {
      let a_move = a[0];
      let b_move = b[0];
      let $ = compare_moves(a_move, b_move);
      if ($ instanceof $order.Lt) {
        return new Some(b_move);
      } else if ($ instanceof $order.Eq) {
        return new Some(a_move);
      } else {
        return new Some(a_move);
      }
    } else {
      return a;
    }
  } else if (b instanceof Some) {
    return b;
  } else {
    return a;
  }
}

function merge_deleted(a, b) {
  if (a instanceof Some) {
    if (b instanceof Some) {
      let a_op = a[0];
      let b_op = b[0];
      let $ = compare_op_ids(a_op, b_op);
      if ($ instanceof $order.Lt) {
        return new Some(a_op);
      } else if ($ instanceof $order.Eq) {
        return new Some(a_op);
      } else {
        return new Some(b_op);
      }
    } else {
      return a;
    }
  } else if (b instanceof Some) {
    return b;
  } else {
    return a;
  }
}

function compare_optional_id(a, b) {
  if (a instanceof Some) {
    if (b instanceof Some) {
      let a_id = a[0];
      let b_id = b[0];
      return compare_item_ids(a_id, b_id);
    } else {
      return $order.Order$Gt$const;
    }
  } else if (b instanceof Some) {
    return $order.Order$Lt$const;
  } else {
    return $order.Order$Eq$const;
  }
}

function compare_origin_pair(a, b) {
  let a_left = a[0];
  let a_right = a[1];
  let b_left = b[0];
  let b_right = b[1];
  let $ = compare_optional_id(a_left, b_left);
  if ($ instanceof $order.Eq) {
    return compare_optional_id(a_right, b_right);
  } else {
    return $;
  }
}

/**
 * Origins are immutable in normal operation, but extracting a block member
 * (for a volatile delete or move) synthesizes origins from local neighbors,
 * so two replicas can disagree. Pick deterministically so merge commutes.
 * 
 * @ignore
 */
function pick_origins(a, b) {
  return $bool.guard(
    (isEqual(a.origin_left, b.origin_left)) && (isEqual(
      a.origin_right,
      b.origin_right
    )),
    [a.origin_left, a.origin_right],
    () => {
      let $ = compare_origin_pair(
        [a.origin_left, a.origin_right],
        [b.origin_left, b.origin_right],
      );
      if ($ instanceof $order.Lt) {
        return [a.origin_left, a.origin_right];
      } else if ($ instanceof $order.Eq) {
        return [a.origin_left, a.origin_right];
      } else {
        return [b.origin_left, b.origin_right];
      }
    },
  );
}

function merge_item(a, b) {
  let $ = pick_origins(a, b);
  let origin_left = $[0];
  let origin_right = $[1];
  return new Item(
    a.id,
    origin_left,
    origin_right,
    a.value,
    merge_deleted(a.deleted, b.deleted),
    merge_move(a.move, b.move),
  );
}

/**
 * One side has the element compacted into a block, the other still holds a
 * live item for it. A tombstone or a move keeps the item live and supersedes
 * the block slot; only a plain copy collapses to the stable representation.
 * The rule looks only at the live item, so both merge directions agree.
 *
 * A moved item is never collapsed into the block skeleton, even if the merged
 * frontier covers its move op: `compact` refuses to stabilize any state that
 * holds a move (see `compact`), so a covered-move block slot cannot legitimately
 * arise, and baking one here would strip the origins a peer's concurrent
 * above-frontier inserts integrate against and break merge commutativity.
 * 
 * @ignore
 */
function stable_or_live(item, _) {
  let $ = item.deleted;
  let $1 = item.move;
  if ($ instanceof None && $1 instanceof None) {
    return new Stable(item.id, item.value);
  } else {
    return new LiveEl(item);
  }
}

function reconcile_element(el, b_lives, b_stables, frontier) {
  if (el instanceof Stable) {
    let id = el.id;
    let $ = $dict.get(b_lives, id);
    if ($ instanceof Ok) {
      let other = $[0];
      return stable_or_live(other, frontier);
    } else {
      return el;
    }
  } else {
    let item = el[0];
    let $ = $dict.get(b_lives, item.id);
    if ($ instanceof Ok) {
      let other = $[0];
      return new LiveEl(merge_item(item, other));
    } else {
      let $1 = $dict.has_key(b_stables, item.id);
      if ($1) {
        return stable_or_live(item, frontier);
      } else {
        return el;
      }
    }
  }
}

function is_stable_element(el) {
  if (el instanceof Stable) {
    return true;
  } else {
    return false;
  }
}

function element_id_dict(elements) {
  return $list.fold(
    elements,
    $dict.new$(),
    (acc, el) => { return $dict.insert(acc, element_id(el), undefined); },
  );
}

function stable_elements_of(elements) {
  return $list.filter(elements, is_stable_element);
}

function stable_id_dict(elements) {
  let _pipe = elements;
  let _pipe$1 = stable_elements_of(_pipe);
  return element_id_dict(_pipe$1);
}

function live_item_dict(elements) {
  let _pipe = elements;
  let _pipe$1 = live_items_of(_pipe);
  return $list.fold(
    _pipe$1,
    $dict.new$(),
    (acc, item) => { return $dict.insert(acc, item.id, item); },
  );
}

function canonical_clocks(vector) {
  let _pipe = $version_vector.to_dict(vector);
  let _pipe$1 = $dict.to_list(_pipe);
  return $list.sort(
    _pipe$1,
    (x, y) => { return $replica_id.compare(x[0], y[0]); },
  );
}

function compare_clock_lists(loop$a, loop$b) {
  while (true) {
    let a = loop$a;
    let b = loop$b;
    if (a instanceof $Empty) {
      if (b instanceof $Empty) {
        return $order.Order$Eq$const;
      } else {
        return $order.Order$Lt$const;
      }
    } else if (b instanceof $Empty) {
      return $order.Order$Gt$const;
    } else {
      let ta = a.tail;
      let tb = b.tail;
      let ra = a.head[0];
      let ca = a.head[1];
      let rb = b.head[0];
      let cb = b.head[1];
      let $ = $replica_id.compare(ra, rb);
      if ($ instanceof $order.Eq) {
        let $1 = $int.compare(ca, cb);
        if ($1 instanceof $order.Eq) {
          loop$a = ta;
          loop$b = tb;
        } else {
          return $1;
        }
      } else {
        return $;
      }
    }
  }
}

/**
 * A deterministic, direction-independent order on version vectors, used
 * only to pick a covered-order source when merging states compacted at
 * concurrent frontiers (which a sequencer host never produces).
 * 
 * @ignore
 */
function frontier_tiebreak(a, b) {
  return compare_clock_lists(canonical_clocks(a), canonical_clocks(b));
}

/**
 * Collapse forwarding chains: a target that was itself dropped in a later
 * pass (or on the other side of a merge) is chased to a retained ID, so a
 * single lookup always lands on a live target.
 * 
 * @ignore
 */
function normalize_forwardings(entries) {
  let fuel = $dict.size(entries) + 1;
  return $dict.map_values(
    entries,
    (_, forwarding) => {
      let left = forwarding.left;
      let right = forwarding.right;
      return new Forwarding(
        chase_left(left, entries, fuel),
        chase_right(right, entries, fuel),
      );
    },
  );
}

function pick_forwarding(a, b) {
  let $ = compare_origin_pair([a.left, a.right], [b.left, b.right]);
  if ($ instanceof $order.Lt) {
    return a;
  } else if ($ instanceof $order.Eq) {
    return a;
  } else {
    return b;
  }
}

function merge_forwarding_entries(a, b) {
  return $dict.fold(
    b,
    a,
    (acc, id, forwarding) => {
      let $ = $dict.get(acc, id);
      if ($ instanceof Ok) {
        let existing = $[0];
        return $dict.insert(acc, id, pick_forwarding(existing, forwarding));
      } else {
        return $dict.insert(acc, id, forwarding);
      }
    },
  );
}

/**
 * Merge two sequence CRDT states.
 *
 * Items are joined by their stable IDs. Concurrent deletes are preserved by
 * keeping the winning delete op, and the merged item set is deterministically
 * reordered using each item's left and right origins. Stable blocks form a
 * fixed skeleton that live items are ordered around.
 *
 * States compacted at different frontiers merge as long as one frontier
 * dominates the other (with a global sequencer, floors are totally ordered
 * so this always holds). An item absent from the further-compacted side and
 * covered by its frontier is treated as compacted away and stays dropped.
 *
 * Pass the identity this replica edits under. The output uses `replica`
 * regardless of operand order, and its counter is the maximum of both
 * inputs. Independent writers must use distinct identities.
 *
 * ## Examples
 *
 * ```gleam
 * let local = replica_id.new("A")
 * sequence.merge(sequence.new(local), sequence.new(replica_id.new("B")), local)
 * |> sequence.replica_id()
 * // -> local
 * ```
 */
export function merge(a, b, replica) {
  let _block;
  let _pipe = merge_forwarding_entries(a.forwardings, b.forwardings);
  _block = normalize_forwardings(_pipe);
  let forwardings = _block;
  let frontier$1 = $version_vector.merge(a.frontier, b.frontier);
  let a_elements = segments_to_elements(a.segments);
  let b_elements = segments_to_elements(b.segments);
  let a_ids = element_id_dict(a_elements);
  let b_ids = element_id_dict(b_elements);
  let b_lives = live_item_dict(b_elements);
  let b_stables = stable_id_dict(b_elements);
  let dropped = (id) => {
    return ($dict.has_key(forwardings, id) || (!$dict.has_key(a_ids, id) && frontier_covers(
      a.frontier,
      id,
    ))) || (!$dict.has_key(b_ids, id) && frontier_covers(b.frontier, id));
  };
  let _block$1;
  let $ = $version_vector.compare(a.frontier, b.frontier);
  if ($ instanceof $version_vector.Before) {
    _block$1 = b_elements;
  } else if ($ instanceof $version_vector.After) {
    _block$1 = a_elements;
  } else if ($ instanceof $version_vector.Concurrent) {
    let $1 = frontier_tiebreak(a.frontier, b.frontier);
    if ($1 instanceof $order.Lt) {
      _block$1 = a_elements;
    } else if ($1 instanceof $order.Eq) {
      _block$1 = a_elements;
    } else {
      _block$1 = b_elements;
    }
  } else {
    _block$1 = a_elements;
  }
  let covered_source = _block$1;
  let _block$2;
  let $2 = isEqual(covered_source, a_elements);
  if ($2) {
    _block$2 = [b_lives, b_stables];
  } else {
    _block$2 = [live_item_dict(a_elements), stable_id_dict(a_elements)];
  }
  let $1 = _block$2;
  let other_lives = $1[0];
  let other_stables = $1[1];
  let _block$3;
  let _pipe$1 = covered_source;
  let _pipe$2 = $list.filter(
    _pipe$1,
    (el) => {
      return is_stable_element(el) || frontier_covers(
        frontier$1,
        element_id(el),
      );
    },
  );
  let _pipe$3 = $list.filter(
    _pipe$2,
    (el) => { return !dropped(element_id(el)); },
  );
  _block$3 = $list.map(
    _pipe$3,
    (_capture) => {
      return reconcile_element(_capture, other_lives, other_stables, frontier$1);
    },
  );
  let covered_elements = _block$3;
  let _block$4;
  let _pipe$4 = $list.append(
    live_items_of(a_elements),
    live_items_of(b_elements),
  );
  let _pipe$5 = $list.filter(
    _pipe$4,
    (item) => {
      return !frontier_covers(frontier$1, item.id) && !dropped(item.id);
    },
  );
  let _pipe$6 = $list.fold(
    _pipe$5,
    $dict.new$(),
    (pool, item) => {
      let $3 = $dict.get(pool, item.id);
      if ($3 instanceof Ok) {
        let existing = $3[0];
        return $dict.insert(pool, item.id, merge_item(existing, item));
      } else {
        return $dict.insert(pool, item.id, item);
      }
    },
  );
  let _pipe$7 = $dict.values(_pipe$6);
  _block$4 = $list.map(_pipe$7, (var0) => { return new LiveEl(var0); });
  let volatile_pool = _block$4;
  let elements = rebuild(
    $list.append(covered_elements, volatile_pool),
    forwardings,
    frontier$1,
  );
  return new Sequence(
    replica,
    $int.max(a.counter, b.counter),
    elements_to_segments(elements),
    forwardings,
    frontier$1,
  );
}

/**
 * Alias for `merge`, with the same explicit output replica identity.
 *
 * ## Examples
 *
 * ```gleam
 * sequence.merge_as(a, b, local) == sequence.merge(a, b, local)
 * // -> True
 * ```
 */
export function merge_as(a, b, replica) {
  return merge(a, b, replica);
}

function left_targets(
  loop$classified,
  loop$last_retained,
  loop$acc,
  loop$settled
) {
  while (true) {
    let classified = loop$classified;
    let last_retained = loop$last_retained;
    let acc = loop$acc;
    let settled = loop$settled;
    if (classified instanceof $Empty) {
      return acc;
    } else {
      let $ = classified.head;
      if ($ instanceof Retained) {
        let rest = classified.tail;
        let el = $[0];
        let $1 = settled(el);
        if ($1) {
          loop$classified = rest;
          loop$last_retained = new Some(element_id(el));
          loop$acc = acc;
          loop$settled = settled;
        } else {
          loop$classified = rest;
          loop$last_retained = last_retained;
          loop$acc = acc;
          loop$settled = settled;
        }
      } else {
        let rest = classified.tail;
        let id = $.id;
        loop$classified = rest;
        loop$last_retained = last_retained;
        loop$acc = $dict.insert(acc, id, last_retained);
        loop$settled = settled;
      }
    }
  }
}

/**
 * Forwardings for one pass, naming only settled landmarks.
 *
 * A forwarding must resolve identically on every replica, and volatile
 * membership does not: replicas compacting at the same frontier hold
 * different above-frontier items, so a forwarding naming one would point
 * somewhere the other cannot follow.
 *
 * Move anchors make this load-bearing: they splice at an exact position
 * rather than searching a window, so the identity of the target decides the
 * result outright.
 * 
 * @ignore
 */
function forwarding_entries_for_pass(classified, stable) {
  let settled = (el) => { return frontier_covers(stable, element_id(el)); };
  let lefts = left_targets(classified, Option$None$const, $dict.new$(), settled);
  let $ = $list.fold_right(
    classified,
    [$dict.new$(), Option$None$const],
    (acc, entry) => {
      let targets = acc[0];
      let next_retained = acc[1];
      if (entry instanceof Retained) {
        let el = entry[0];
        let $1 = settled(el);
        if ($1) {
          return [targets, new Some(element_id(el))];
        } else {
          return [targets, next_retained];
        }
      } else {
        let id = entry.id;
        return [$dict.insert(targets, id, next_retained), next_retained];
      }
    },
  );
  let rights = $[0];
  return $dict.fold(
    lefts,
    $dict.new$(),
    (acc, id, left) => {
      let _block;
      let $1 = $dict.get(rights, id);
      if ($1 instanceof Ok) {
        let target = $1[0];
        _block = target;
      } else {
        _block = Option$None$const;
      }
      let right = _block;
      return $dict.insert(acc, id, new Forwarding(left, right));
    },
  );
}

function frontier_covers_op(frontier, op) {
  let rid = op.replica_id;
  let counter = op.counter;
  return $version_vector.get(frontier, rid) >= counter;
}

/**
 * A settled tombstone is reclaimed and a settled plain item is baked into the
 * skeleton; anything above the frontier or holding an unacknowledged delete
 * stays live.
 * 
 * @ignore
 */
function item_stability(item, stable) {
  return $bool.guard(
    !frontier_covers(stable, item.id),
    Stability$KeepLive$const,
    () => {
      let $ = item.deleted;
      let $1 = item.move;
      if ($ instanceof Some) {
        let op = $[0];
        let $2 = frontier_covers_op(stable, op);
        if ($2) {
          return Stability$DropTombstone$const;
        } else {
          return Stability$KeepLive$const;
        }
      } else if ($1 instanceof Some) {
        return Stability$KeepLive$const;
      } else {
        return Stability$ToStable$const;
      }
    },
  );
}

function insert_optional_id(acc, id) {
  if (id instanceof Some) {
    let id$1 = id[0];
    return $dict.insert(acc, id$1, undefined);
  } else {
    return acc;
  }
}

/**
 * Every ID a live move still names as one of its target-gap boundaries.
 *
 * Reclaiming one of these would leave the move anchoring on a gap that has
 * to be reconstructed from forwardings, and the reconstruction is not
 * position-identical: a compacted replica and an uncompacted one would
 * splice the mover differently. Retaining them keeps move resolution exactly
 * what it was before the pass, at a cost of at most two extra tombstones per
 * live mover.
 * 
 * @ignore
 */
function move_anchor_ids(elements) {
  let _pipe = elements;
  let _pipe$1 = live_items_of(_pipe);
  return $list.fold(
    _pipe$1,
    $dict.new$(),
    (acc, item) => {
      let $ = item.move;
      if ($ instanceof Some) {
        let move_left = $[0].origin_left;
        let move_right = $[0].origin_right;
        let _pipe$2 = acc;
        let _pipe$3 = insert_optional_id(_pipe$2, move_left);
        return insert_optional_id(_pipe$3, move_right);
      } else {
        return acc;
      }
    },
  );
}

function do_compact(sequence, stable) {
  let elements = segments_to_elements(sequence.segments);
  let anchored = move_anchor_ids(elements);
  let classified = $list.map(
    elements,
    (el) => {
      if (el instanceof Stable) {
        return new Retained(el);
      } else {
        let item = el[0];
        let $ = $dict.has_key(anchored, item.id);
        if ($) {
          return new Retained(el);
        } else {
          let $1 = item_stability(item, stable);
          if ($1 instanceof DropTombstone) {
            return new Dropped(item.id);
          } else if ($1 instanceof ToStable) {
            return new Retained(new Stable(item.id, item.value));
          } else {
            return new Retained(el);
          }
        }
      }
    },
  );
  let new_entries = forwarding_entries_for_pass(classified, stable);
  let kept = $list.filter_map(
    classified,
    (entry) => {
      if (entry instanceof Retained) {
        let el = entry[0];
        return new Ok(el);
      } else {
        return new Error(undefined);
      }
    },
  );
  let updated_old = $dict.map_values(
    sequence.forwardings,
    (_, forwarding) => {
      let left = forwarding.left;
      let right = forwarding.right;
      return new Forwarding(
        chase_left(left, new_entries, $dict.size(new_entries) + 1),
        chase_right(right, new_entries, $dict.size(new_entries) + 1),
      );
    },
  );
  let all_forwardings = $dict.fold(
    new_entries,
    updated_old,
    (acc, id, forwarding) => { return $dict.insert(acc, id, forwarding); },
  );
  let compacted = new Sequence(
    sequence.replica_id,
    sequence.counter,
    elements_to_segments(kept),
    all_forwardings,
    stable,
  );
  return [compacted, new ForwardingMap(new_entries)];
}

/**
 * Compact everything at or below a stability frontier.
 *
 * `stable` must describe a causal cut the host knows no in-flight or future
 * op can reference (e.g. the version vector accumulated by replaying ops up
 * to a global sequencer's acknowledgement floor). For the stable region the
 * pass drops tombstones, merges runs of adjacent same-replica items with
 * sequential counters into blocks, and strips origins and move slots.
 *
 * Returns the compacted sequence and the forwarding entries emitted by this
 * pass (one per dropped ID). The cumulative forwarding map is also carried
 * in the sequence; hosts bound its growth with `remove_forwardings`.
 *
 * Compacting at the current frontier, at an older one, or at one concurrent
 * with it is a no-op — frontiers only advance.
 *
 * Moved items remain live so their move records and insertion origins survive.
 * The pass can still stabilize unrelated items and reclaim tombstones, while
 * retaining any target-gap boundaries referenced by a live move.
 */
export function compact(sequence, stable) {
  let $ = $version_vector.compare(stable, sequence.frontier);
  if ($ instanceof $version_vector.Before) {
    return [sequence, new ForwardingMap($dict.new$())];
  } else if ($ instanceof $version_vector.After) {
    return do_compact(sequence, stable);
  } else if ($ instanceof $version_vector.Concurrent) {
    return [sequence, new ForwardingMap($dict.new$())];
  } else {
    return [sequence, new ForwardingMap($dict.new$())];
  }
}

function right_of(forwarding) {
  return forwarding.right;
}

function left_of(forwarding) {
  return forwarding.left;
}

function translate_move(move, translate) {
  if (move instanceof Some) {
    let op = move[0].op_id;
    let move_left = move[0].origin_left;
    let move_right = move[0].origin_right;
    return $result.try$(
      translate(move_left, left_of),
      (move_left) => {
        return $result.try$(
          translate(move_right, right_of),
          (move_right) => {
            return new Ok(new Some(new Move(op, move_left, move_right)));
          },
        );
      },
    );
  } else {
    return new Ok(Option$None$const);
  }
}

function translate_element(el, translate) {
  if (el instanceof Stable) {
    return new Ok(el);
  } else {
    let item = el[0];
    return $result.try$(
      translate(item.origin_left, left_of),
      (origin_left) => {
        return $result.try$(
          translate(item.origin_right, right_of),
          (origin_right) => {
            return $result.try$(
              translate_move(item.move, translate),
              (move) => {
                return new Ok(
                  new LiveEl(
                    new Item(
                      item.id,
                      origin_left,
                      origin_right,
                      item.value,
                      item.deleted,
                      move,
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

/**
 * Translate a delta's origins onto a compacted state.
 *
 * Rebase support for evicted clients: origins (including move origins)
 * referencing compacted IDs are rewritten through `onto`'s forwarding map to
 * the gap the ID left behind. Items whose own ID was compacted away are
 * dropped from the delta — the op is already settled. Returns
 * `Error(UnknownOriginTarget)` when an origin is neither present, part of
 * the delta itself, nor forwarded (the forwarding expired); the host must
 * degrade the op to a positional edit or discard it.
 */
export function translate_origins(delta, onto) {
  let onto_ids = element_id_dict(segments_to_elements(onto.segments));
  let delta_elements = segments_to_elements(delta.segments);
  let delta_ids = element_id_dict(delta_elements);
  let known = (id) => {
    return $dict.has_key(onto_ids, id) || $dict.has_key(delta_ids, id);
  };
  let dropped = (id) => {
    return $dict.has_key(onto.forwardings, id) || (!$dict.has_key(onto_ids, id) && frontier_covers(
      onto.frontier,
      id,
    ));
  };
  let translate = (origin, pick) => {
    if (origin instanceof Some) {
      let id = origin[0];
      let $ = known(id);
      if ($) {
        return new Ok(origin);
      } else {
        let $1 = $dict.get(onto.forwardings, id);
        if ($1 instanceof Ok) {
          let forwarding = $1[0];
          return new Ok(pick(forwarding));
        } else {
          return new Error(TranslateError$UnknownOriginTarget$const);
        }
      }
    } else {
      return new Ok(Option$None$const);
    }
  };
  let _block;
  let _pipe = delta_elements;
  let _pipe$1 = $list.filter(
    _pipe,
    (el) => { return !dropped(element_id(el)); },
  );
  _block = $list.try_map(
    _pipe$1,
    (_capture) => { return translate_element(_capture, translate); },
  );
  let translated = _block;
  if (translated instanceof Ok) {
    let elements = translated[0];
    return new Ok(
      new Sequence(
        delta.replica_id,
        delta.counter,
        elements_to_segments(elements),
        delta.forwardings,
        delta.frontier,
      ),
    );
  } else {
    return translated;
  }
}

function encode_optional_item_id(item_id) {
  if (item_id instanceof Some) {
    let id = item_id[0];
    return encode_item_id(id);
  } else {
    return $json.null$();
  }
}

function encode_op_id(id) {
  let rid = id.replica_id;
  let counter = id.counter;
  return $json.object(
    toList([
      ["replica_id", $json.string($replica_id.to_string(rid))],
      ["counter", $json.int(counter)],
    ]),
  );
}

function encode_optional_move(move) {
  if (move instanceof Some) {
    let op_id = move[0].op_id;
    let origin_left = move[0].origin_left;
    let origin_right = move[0].origin_right;
    return $json.object(
      toList([
        ["op_id", encode_op_id(op_id)],
        ["origin_left", encode_optional_item_id(origin_left)],
        ["origin_right", encode_optional_item_id(origin_right)],
      ]),
    );
  } else {
    return $json.null$();
  }
}

function encode_optional_op_id(op_id) {
  if (op_id instanceof Some) {
    let op = op_id[0];
    return encode_op_id(op);
  } else {
    return $json.null$();
  }
}

function encode_segment(segment, encode_value) {
  if (segment instanceof Block) {
    let first_id = segment.first_id;
    let values$1 = segment.values;
    return $json.object(
      toList([
        ["kind", $json.string("block")],
        ["first_id", encode_item_id(first_id)],
        ["values", $json.array(values$1, encode_value)],
      ]),
    );
  } else {
    let item = segment[0];
    return $json.object(
      toList([
        ["kind", $json.string("item")],
        ["id", encode_item_id(item.id)],
        ["origin_left", encode_optional_item_id(item.origin_left)],
        ["origin_right", encode_optional_item_id(item.origin_right)],
        ["value", encode_value(item.value)],
        ["deleted", encode_optional_op_id(item.deleted)],
        ["move", encode_optional_move(item.move)],
      ]),
    );
  }
}

function encode_forwarding(entry) {
  let id;
  let left;
  let right;
  id = entry[0];
  left = entry[1].left;
  right = entry[1].right;
  return $json.object(
    toList([
      ["id", encode_item_id(id)],
      ["left", encode_optional_item_id(left)],
      ["right", encode_optional_item_id(right)],
    ]),
  );
}

/**
 * Encode a sequence CRDT as a self-describing JSON value.
 *
 * Produces an envelope with `type`, `v` (schema version), and `state`. The
 * state includes this replica ID, local counter, applied compaction
 * frontier, forwarding entries, and every segment: compact blocks of stable
 * values and full items including tombstones.
 */
export function to_json(sequence, encode_value) {
  return $json.object(
    toList([
      ["type", $json.string("sequence")],
      ["v", $json.int(2)],
      [
        "state",
        $json.object(
          toList([
            ["self_id", $replica_id.to_json(sequence.replica_id)],
            ["counter", $json.int(sequence.counter)],
            ["frontier", $version_vector.to_json(sequence.frontier)],
            [
              "forwardings",
              $json.array(
                $dict.to_list(sequence.forwardings),
                encode_forwarding,
              ),
            ],
            [
              "segments",
              $json.array(
                sequence.segments,
                (_capture) => { return encode_segment(_capture, encode_value); },
              ),
            ],
          ]),
        ),
      ],
    ]),
  );
}

/**
 * Bring a decoded payload's segments into canonical base order.
 *
 * Version 2 stores the pre-move base and overlays moves on read, so its
 * segments are already the base. Version 1 stored the move-APPLIED order, so
 * a mover sits at its post-move slot and would be pinned there.
 *
 * A v1 payload with no move records never had an overlay, so its order is
 * already the base. One with movers but no compacted segments still carries
 * every origin, so the base re-derives exactly. One with both is
 * unrecoverable — the compacted elements have no origins to re-integrate
 * from, and replicas at different frontiers would reconstruct the mover's
 * slot differently — so it is rejected and the holder must resync.
 * 
 * @ignore
 */
function base_order_segments(version, segments, forwardings) {
  let elements = segments_to_elements(segments);
  let $ = (version >= 2) || !$list.any(live_items_of(elements), has_move);
  if ($) {
    return new Ok(elements_to_segments(elements));
  } else {
    let $1 = $list.any(elements, is_stable_element);
    if ($1) {
      return new Error(undefined);
    } else {
      return new Ok(
        elements_to_segments(
          rebuild_base(elements, forwardings, $version_vector.new$()),
        ),
      );
    }
  }
}

function include_origin_counter(counter, origin) {
  if (origin instanceof Some) {
    let id = origin[0];
    return $int.max(counter, id.counter);
  } else {
    return counter;
  }
}

function allocation_counter(counter, segments, forwardings, frontier) {
  let _block;
  let _pipe = $version_vector.to_dict(frontier);
  let _pipe$1 = $dict.values(_pipe);
  _block = $list.fold(_pipe$1, counter, $int.max);
  let counter$1 = _block;
  let counter$2 = $list.fold(
    segments,
    counter$1,
    (max, segment) => {
      if (segment instanceof Block) {
        let first_id = segment.first_id;
        let values$1 = segment.values;
        return $int.max(
          max,
          first_id.counter + $int.max(0, $list.length(values$1) - 1),
        );
      } else {
        let item = segment[0];
        let _block$1;
        let _pipe$2 = $int.max(max, item.id.counter);
        let _pipe$3 = include_origin_counter(_pipe$2, item.origin_left);
        _block$1 = include_origin_counter(_pipe$3, item.origin_right);
        let max$1 = _block$1;
        let _block$2;
        let $ = item.deleted;
        if ($ instanceof Some) {
          let op = $[0];
          _block$2 = $int.max(max$1, op.counter);
        } else {
          _block$2 = max$1;
        }
        let max$2 = _block$2;
        let $1 = item.move;
        if ($1 instanceof Some) {
          let move$1 = $1[0];
          let _pipe$4 = $int.max(max$2, move$1.op_id.counter);
          let _pipe$5 = include_origin_counter(_pipe$4, move$1.origin_left);
          return include_origin_counter(_pipe$5, move$1.origin_right);
        } else {
          return max$2;
        }
      }
    },
  );
  return $list.fold(
    forwardings,
    counter$2,
    (max, entry) => {
      let id = entry[0];
      let forwarding = entry[1];
      let _pipe$2 = $int.max(max, id.counter);
      let _pipe$3 = include_origin_counter(_pipe$2, forwarding.left);
      return include_origin_counter(_pipe$3, forwarding.right);
    },
  );
}

function op_id_decoder() {
  return $decode.field(
    "replica_id",
    $replica_id.decoder(),
    (rid) => {
      return $decode.field(
        "counter",
        non_negative_int_decoder(),
        (counter) => { return $decode.success(new OpId(rid, counter)); },
      );
    },
  );
}

function move_decoder() {
  return $decode.field(
    "op_id",
    op_id_decoder(),
    (op_id) => {
      return $decode.field(
        "origin_left",
        $decode.optional(item_id_decoder()),
        (origin_left) => {
          return $decode.field(
            "origin_right",
            $decode.optional(item_id_decoder()),
            (origin_right) => {
              return $decode.success(new Move(op_id, origin_left, origin_right));
            },
          );
        },
      );
    },
  );
}

function segment_decoder(value_decoder) {
  return $decode.field(
    "kind",
    $decode.string,
    (kind) => {
      if (kind === "block") {
        return $decode.field(
          "first_id",
          item_id_decoder(),
          (first_id) => {
            return $decode.field(
              "values",
              $decode.list(value_decoder),
              (values) => {
                return $decode.success(new Block(first_id, values));
              },
            );
          },
        );
      } else if (kind === "item") {
        return $decode.field(
          "id",
          item_id_decoder(),
          (id) => {
            return $decode.field(
              "origin_left",
              $decode.optional(item_id_decoder()),
              (origin_left) => {
                return $decode.field(
                  "origin_right",
                  $decode.optional(item_id_decoder()),
                  (origin_right) => {
                    return $decode.field(
                      "value",
                      value_decoder,
                      (value) => {
                        return $decode.field(
                          "deleted",
                          $decode.optional(op_id_decoder()),
                          (deleted) => {
                            return $decode.optional_field(
                              "move",
                              Option$None$const,
                              $decode.optional(move_decoder()),
                              (move) => {
                                return $decode.success(
                                  new Live(
                                    new Item(
                                      id,
                                      origin_left,
                                      origin_right,
                                      value,
                                      deleted,
                                      move,
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      } else {
        return $decode.failure(
          new Block(new ItemId($replica_id.new$(""), 0), $List$Empty$const),
          "segment kind of block or item",
        );
      }
    },
  );
}

function forwarding_decoder() {
  return $decode.field(
    "id",
    item_id_decoder(),
    (id) => {
      return $decode.field(
        "left",
        $decode.optional(item_id_decoder()),
        (left) => {
          return $decode.field(
            "right",
            $decode.optional(item_id_decoder()),
            (right) => {
              return $decode.success([id, new Forwarding(left, right)]);
            },
          );
        },
      );
    },
  );
}

/**
 * Decode a sequence CRDT from a JSON string produced by `to_json`.
 *
 * Returns `Ok(Sequence)` on success, or `Error(json.DecodeError)` if the
 * input is not a valid sequence JSON envelope. Live items are reordered
 * deterministically from their stable origins before the `Sequence` is
 * returned. If retained IDs or the compaction frontier exceed the encoded
 * allocation counter, the counter is raised to that high-water mark. This
 * prevents ID reuse when the snapshot is edited under any replica identity.
 */
export function from_json(json_string, value_decoder) {
  let state_decoder = (version) => {
    return $decode.field(
      "state",
      $decode.field(
        "self_id",
        $replica_id.decoder(),
        (self_id) => {
          return $decode.field(
            "counter",
            non_negative_int_decoder(),
            (counter) => {
              return $decode.field(
                "frontier",
                $version_vector.decoder(),
                (frontier) => {
                  return $decode.field(
                    "forwardings",
                    $decode.list(forwarding_decoder()),
                    (forwardings) => {
                      return $decode.field(
                        "segments",
                        $decode.list(segment_decoder(value_decoder)),
                        (segments) => {
                          let counter$1 = allocation_counter(
                            counter,
                            segments,
                            forwardings,
                            frontier,
                          );
                          let forwarding_map = $dict.from_list(forwardings);
                          let $ = base_order_segments(
                            version,
                            segments,
                            forwarding_map,
                          );
                          if ($ instanceof Ok) {
                            let base = $[0];
                            return $decode.success(
                              new Sequence(
                                self_id,
                                counter$1,
                                base,
                                forwarding_map,
                                frontier,
                              ),
                            );
                          } else {
                            return $decode.failure(
                              new Sequence(
                                self_id,
                                counter$1,
                                $List$Empty$const,
                                forwarding_map,
                                frontier,
                              ),
                              "a v1 payload whose moved items were not already compacted",
                            );
                          }
                        },
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
      (state) => { return $decode.success(state); },
    );
  };
  let envelope_decoder = $decode.field(
    "type",
    $decode.string,
    (type_tag) => {
      return $decode.field(
        "v",
        $decode.int,
        (version) => { return $decode.success([type_tag, version]); },
      );
    },
  );
  let $ = $json.parse(json_string, envelope_decoder);
  if ($ instanceof Ok) {
    let type_tag = $[0][0];
    let version = $[0][1];
    let $1 = (type_tag === "sequence") && ((version === 1) || (version === 2));
    if ($1) {
      return $json.parse(json_string, state_decoder(version));
    } else {
      return new Error(
        new $json.UnableToDecode(
          toList([
            new $decode.DecodeError(
              "type=sequence and v=1 or v=2",
              (type_tag + " v=") + $int.to_string(version),
              $List$Empty$const,
            ),
          ]),
        ),
      );
    }
  } else {
    return $;
  }
}
