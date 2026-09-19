type Constructor<T> = abstract new (...args: never[]) => T;

export function requiredInstance<T>(
  value: unknown,
  constructor: Constructor<T>,
  demo: string,
  selector: string,
): T {
  if (!(value instanceof constructor)) {
    throw new Error(`${demo}: missing or invalid ${selector}`);
  }
  return value;
}
