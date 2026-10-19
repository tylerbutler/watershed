export class Composition {
  active = false;
  private canceled = false;
  private duplicate: string | undefined;

  resume(): void { this.canceled = false; this.duplicate = undefined; }
  start(): void { this.resume(); this.active = true; }
  cancel(): void { this.active = false; this.canceled = true; this.duplicate = undefined; }
  end(value: string): string | undefined {
    if (!this.active || this.canceled) return undefined;
    this.active = false;
    this.duplicate = value;
    return value;
  }
  input(value: string): string | undefined {
    if (this.active || this.canceled) return undefined;
    const duplicate = this.duplicate;
    this.duplicate = undefined;
    return value === duplicate ? undefined : value;
  }
}

type NativeInput = Pick<HTMLInputElement,
  "value" | "selectionStart" | "selectionEnd" | "selectionDirection" | "setSelectionRange">;

export function reconcileInput(
  input: NativeInput, value: string, focused: boolean, composing: boolean,
): void {
  if (composing || input.value === value) return;
  const start = input.selectionStart;
  const end = input.selectionEnd;
  const direction = input.selectionDirection ?? "none";
  input.value = value;
  if (focused && start !== null && end !== null) {
    input.setSelectionRange(Math.min(start, value.length), Math.min(end, value.length), direction);
  }
}
