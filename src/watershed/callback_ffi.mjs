export function capture(work, onSuccess, onError) {
  let value;
  try {
    value = work();
  } catch (error) {
    return onError(describe(error));
  }
  return onSuccess(value);
}

export function guard(work, onError) {
  try {
    work();
  } catch (error) {
    onError(describe(error));
  }
  return undefined;
}

export function report(detail) {
  const error = new Error(detail);
  if (typeof globalThis.reportError === "function") {
    globalThis.reportError(error);
  } else {
    console.error(error);
  }
}

function describe(error) {
  if (error instanceof Error) {
    return error.name + ": " + error.message;
  }
  return String(error);
}
