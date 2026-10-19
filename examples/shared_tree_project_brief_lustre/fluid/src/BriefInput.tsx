import { useLayoutEffect, useReducer, useRef } from "react";
import { Composition, reconcileInput } from "./input.ts";
import type { EditableNode } from "./edits.ts";

interface Props {
  field: string;
  value: string;
  disabled: boolean;
  node: EditableNode;
  onValue(value: string): void;
  onFocus(): void;
  onBlur(): void;
}

export function BriefInput({ field, value, disabled, node, onValue, onFocus, onBlur }: Props) {
  const ref = useRef<HTMLInputElement>(null);
  const composition = useRef(new Composition());
  const previousNode = useRef(node);
  const [, render] = useReducer((revision: number) => revision + 1, 0);
  useLayoutEffect(() => {
    const input = ref.current;
    if (!input) return;
    if (previousNode.current !== node) {
      previousNode.current = node;
      composition.current.cancel();
      input.blur();
    }
    if (disabled) composition.current.cancel();
    reconcileInput(input, value, document.activeElement === input, composition.current.active);
  });
  useLayoutEffect(() => () => { composition.current.cancel(); }, []);
  return <input ref={ref} type="text" data-field={field} disabled={disabled}
    onFocus={() => { composition.current.resume(); onFocus(); }}
    onBlur={() => {
      composition.current.cancel();
      onBlur();
      render();
    }}
    onCompositionStart={() => {
      if (!disabled) composition.current.start();
    }}
    onCompositionEnd={(event) => {
      const completed = composition.current.end(event.currentTarget.value);
      if (!disabled && completed !== undefined) onValue(completed);
      else composition.current.cancel();
      render();
    }}
    onInput={(event) => {
      if (disabled) { composition.current.cancel(); return; }
      const next = composition.current.input(event.currentTarget.value);
      if (next !== undefined) onValue(next);
    }}
  />;
}
