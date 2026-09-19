import type * as _ from "../../gleam.d.mts";

declare class Root extends _.CustomType {}

declare class Key extends _.CustomType {
  /** @deprecated */
  constructor(key: string, parent: Path$);
  /** @deprecated */
  key: string;
  /** @deprecated */
  parent: Path$;
}

declare class Index extends _.CustomType {
  /** @deprecated */
  constructor(index: number, parent: Path$);
  /** @deprecated */
  index: number;
  /** @deprecated */
  parent: Path$;
}

declare class Subtree extends _.CustomType {
  /** @deprecated */
  constructor(parent: Path$);
  /** @deprecated */
  parent: Path$;
}

export type Path$ = Root | Key | Index | Subtree;

export const separator_subtree: string;

export const separator_element: string;

export const separator_event: string;

export const root: Path$;

export function to_string(path: Path$): string;

export function matches(path: Path$, candidates: _.List<string>): boolean;

export function split_subtree_path(path: string): _.List<string>;

export function add(parent: Path$, index: number, key: string): Path$;

export function subtree(path: Path$): Path$;

export function event(path: Path$, event: string): string;

export function child(path: Path$): string;
