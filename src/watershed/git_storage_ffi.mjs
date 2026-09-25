export function initial_request(request) {
  return new Request(request, {
    redirect: "manual",
    signal: AbortSignal.timeout(30_000),
  });
}

export function valid_service_url(value) {
  try {
    new Request(value);
    return true;
  } catch (error) {
    if (error instanceof TypeError) return false;
    throw error;
  }
}
