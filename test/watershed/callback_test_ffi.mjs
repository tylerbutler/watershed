export function withReporter(fallback, work) {
  const previous = Object.getOwnPropertyDescriptor(globalThis, "reportError");
  const previousConsoleError = console.error;
  const errors = [];
  try {
    Object.defineProperty(globalThis, "reportError", {
      configurable: true,
      value: fallback ? undefined : (error) => errors.push(String(error)),
    });
    console.error = (error) => errors.push(String(error));
    return work(() => errors.length, () => errors.join("\n"));
  } finally {
    console.error = previousConsoleError;
    if (previous) Object.defineProperty(globalThis, "reportError", previous);
    else delete globalThis.reportError;
  }
}
