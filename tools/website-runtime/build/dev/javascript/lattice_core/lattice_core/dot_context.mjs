/// <reference types="./dot_context.d.mts" />
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import * as $set from "../../gleam_stdlib/gleam/set.mjs";
import { CustomType as $CustomType } from "../gleam.mjs";
import * as $replica_id from "../lattice_core/replica_id.mjs";

export class Dot extends $CustomType {
  constructor(replica_id, counter) {
    super();
    this.replica_id = replica_id;
    this.counter = counter;
  }
}
export const Dot$Dot = (replica_id, counter) => new Dot(replica_id, counter);
export const Dot$isDot = (value) => value instanceof Dot;
export const Dot$Dot$replica_id = (value) => value.replica_id;
export const Dot$Dot$0 = (value) => value.replica_id;
export const Dot$Dot$counter = (value) => value.counter;
export const Dot$Dot$1 = (value) => value.counter;

class DotContext extends $CustomType {
  constructor(dots) {
    super();
    this.dots = dots;
  }
}

/**
 * Create a new empty DotContext.
 *
 * Returns a context with no observed dots. Use `add_dot` to record events.
 */
export function new$() {
  return new DotContext($set.new$());
}

/**
 * Add a specific dot to the context.
 *
 * Records that the event `(replica_id, counter)` has been observed. If the
 * dot is already present, the context is returned unchanged.
 */
export function add_dot(context, replica_id, counter) {
  return new DotContext($set.insert(context.dots, new Dot(replica_id, counter)));
}

/**
 * Remove a list of dots from the context.
 *
 * Returns a new context with all dots in `dots` removed. Dots that are not
 * present are silently ignored.
 */
export function remove_dots(context, dots) {
  return new DotContext(
    $list.fold(
      dots,
      context.dots,
      (acc, dot) => { return $set.delete$(acc, dot); },
    ),
  );
}

/**
 * Check if all given dots are present in the context.
 *
 * Returns `True` only if every dot in `dots` has been observed (i.e., every
 * dot was previously added via `add_dot` and not subsequently removed).
 * Returns `True` for an empty `dots` list.
 */
export function contains_dots(context, dots) {
  return $list.all(dots, (dot) => { return $set.contains(context.dots, dot); });
}
